#requires -PSEdition Core
#requires -Version 7.6.5
# The lab's AlmaLinux guests on the host: the GenericCloud image converted to a
# base VHDX once, a cloud-init NoCloud seed disk per guest (hostname, static
# address, the lab's SSH key), the VM hardware cloud-init needs, and the
# parameters the guest's own DSC document is given. Hyper-V calls are guarded
# at the resource boundary, as in LabHost.ps1.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The account cloud-init creates on every Linux guest; key-only, sudo without
# a password, the one way in.
$script:LabLinuxUser = 'xmiplab'

function Get-LabLinuxHostName {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Machine
    )

    return $Machine.Name.ToLowerInvariant()
}

function Get-LabPublicKey {
    <#
    .SYNOPSIS
    The lab's SSH public key as cloud-init takes it: its type and key, no comment.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab
    )

    [string] $path = "$($Lab.SshKeyPath).pub"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "The lab's SSH key is missing; run Initialize-LabCredential.ps1 first: $path"
    }
    [string[]] $fields = @((Get-Content -LiteralPath $path -Raw).Trim() -split '\s+')
    if ($fields.Count -lt 2 -or $fields[0] -ne 'ssh-ed25519' -or
        $fields[1] -notmatch '^[A-Za-z0-9+/=]+$') {
        throw "Not an ed25519 public key: $path"
    }
    return "$($fields[0]) $($fields[1])"
}

function Get-LabCloudInitData {
    <#
    .SYNOPSIS
    The three NoCloud files for one guest: meta-data, user-data, network-config.
    .DESCRIPTION
    Returns an ordered dictionary of file name to text, LF line endings. The
    adapter is matched by the static MAC Set-LabLinuxHardware gives it.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab,

        [Parameter(Mandatory = $true)]
        [hashtable] $Machine,

        [Parameter(Mandatory = $true)]
        [string] $PublicKey
    )

    [string] $hostName = Get-LabLinuxHostName -Machine $Machine
    [string] $mac = (Get-LabMacAddress -Address $Machine.Address).ToLowerInvariant() -replace
        '(..)(?!$)', '$1:'
    [string] $dns = ($Lab.Machines | Where-Object Role -eq 'DomainController').Address
    [string[]] $metaData = @(
        "instance-id: $($Lab.LabId)-$($Machine.Name)"
        "local-hostname: $hostName"
    )
    [string[]] $userData = @(
        '#cloud-config'
        "fqdn: $hostName.$($Lab.DomainName)"
        'users:'
        "  - name: $script:LabLinuxUser"
        '    gecos: Xmip lab'
        '    groups: [wheel]'
        '    sudo: "ALL=(ALL) NOPASSWD:ALL"'
        '    lock_passwd: true'
        '    ssh_authorized_keys:'
        "      - '$PublicKey'"
        'disable_root: true'
        'ssh_pwauth: false'
    )
    [string[]] $network = @(
        'version: 2'
        'ethernets:'
        '  lab:'
        '    match:'
        "      macaddress: '$mac'"
        '    set-name: eth0'
        "    addresses: ['$($Machine.Address)/$($Lab.Network.PrefixLength)']"
        '    routes:'
        '      - to: default'
        "        via: $($Lab.Network.Gateway)"
        '    nameservers:'
        "      search: [$($Lab.DomainName)]"
        "      addresses: [$dns]"
    )
    return [ordered] @{
        'meta-data' = ($metaData -join "`n") + "`n"
        'user-data' = ($userData -join "`n") + "`n"
        'network-config' = ($network -join "`n") + "`n"
    }
}

function New-LabCloudInitSeed {
    <#
    .SYNOPSIS
    Writes a guest's NoCloud seed: a small FAT32 VHDX labelled CIDATA.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab,

        [Parameter(Mandatory = $true)]
        [hashtable] $Machine,

        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    [hashtable] $content = @{
        Lab = $Lab
        Machine = $Machine
        PublicKey = Get-LabPublicKey -Lab $Lab
    }
    [System.Collections.Specialized.OrderedDictionary] $files = Get-LabCloudInitData @content
    if (-not $PSCmdlet.ShouldProcess($Path, 'Write cloud-init seed disk')) {
        return
    }
    New-VHD -Path $Path -SizeBytes 64MB -Dynamic | Out-Null
    [object] $disk = Mount-VHD -Path $Path -Passthru | Get-Disk
    try {
        Initialize-Disk -Number $disk.Number -PartitionStyle MBR
        [hashtable] $create = @{
            DiskNumber = $disk.Number
            UseMaximumSize = $true
            AssignDriveLetter = $true
        }
        [object] $partition = New-Partition @create
        [hashtable] $format = @{
            Partition = $partition
            FileSystem = 'FAT32'
            NewFileSystemLabel = 'CIDATA'
            Confirm = $false
        }
        Format-Volume @format | Out-Null
        [hashtable] $query = @{
            DiskNumber = $disk.Number
            PartitionNumber = $partition.PartitionNumber
        }
        [string] $drive = "$((Get-Partition @query).DriveLetter):\"
        [System.Text.UTF8Encoding] $utf8 = [System.Text.UTF8Encoding]::new($false)
        foreach ($name in $files.Keys) {
            [IO.File]::WriteAllText((Join-Path -Path $drive -ChildPath $name), $files[$name], $utf8)
        }
    }
    finally {
        Dismount-VHD -Path $Path
    }
}

function Set-LabLinuxHardware {
    <#
    .SYNOPSIS
    What a new AlmaLinux VM needs beyond the common hardware: the UEFI
    certificate authority's Secure Boot template, its static MAC and its seed.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab,

        [Parameter(Mandatory = $true)]
        [hashtable] $Machine,

        [Parameter(Mandatory = $true)]
        [string] $Directory
    )

    [hashtable] $firmware = @{
        VMName = $Machine.Name
        EnableSecureBoot = 'On'
        SecureBootTemplate = 'MicrosoftUEFICertificateAuthority'
    }
    Set-VMFirmware @firmware
    [string] $mac = Get-LabMacAddress -Address $Machine.Address
    Set-VMNetworkAdapter -VMName $Machine.Name -StaticMacAddress $mac
    [string] $seed = Join-Path -Path $Directory -ChildPath 'seed.vhdx'
    New-LabCloudInitSeed -Lab $Lab -Machine $Machine -Path $seed -Confirm:$false
    Add-VMHardDiskDrive -VMName $Machine.Name -Path $seed
}

function Get-LabLinuxBaseImage {
    <#
    .SYNOPSIS
    The base VHDX a Linux Os's guests differ from, converted from its GenericCloud
    image once with qemu-img. Returns the path; converts only with -Create.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab,

        [Parameter(Mandatory = $true)]
        [string] $Os,

        [switch] $Create
    )

    [string] $directory = Join-Path -Path $Lab.Root -ChildPath 'base'
    [string] $base = Join-Path -Path $directory -ChildPath "$Os.vhdx"
    if (-not $Create -or (Test-Path -LiteralPath $base -PathType Leaf) -or
        -not $PSCmdlet.ShouldProcess($base, 'Convert the GenericCloud image to VHDX')) {
        return $base
    }
    [hashtable] $image = $Lab.Images[$Os]
    New-Item -Path $directory -ItemType Directory -Force | Out-Null
    [string] $partial = "$base.partial"
    [string[]] $convert = @('convert', '-f', 'qcow2', '-O', 'vhdx', '-o', 'subformat=dynamic',
        $image.Path, $partial)
    & $image.QemuImg @convert
    if ($LASTEXITCODE -ne 0) {
        throw "qemu-img could not convert $($image.Path)."
    }
    # Hyper-V refuses a sparse virtual disk file.
    if ((Get-Item -LiteralPath $partial).Attributes.HasFlag([IO.FileAttributes]::SparseFile)) {
        & fsutil.exe sparse setflag $partial 0 | Out-Null
    }
    Move-Item -LiteralPath $partial -Destination $base
    return $base
}

function Get-LabReplicationSlot {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Machine
    )

    return (Get-LabLinuxHostName -Machine $Machine) -replace '[^a-z0-9]', '_'
}

function Get-LabLinuxGuestParameter {
    <#
    .SYNOPSIS
    What one Linux guest's DSC document is given: no secret, nothing it could
    not be told in the clear.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab,

        [Parameter(Mandatory = $true)]
        [hashtable] $Machine
    )

    [hashtable] $controller = $Lab.Machines | Where-Object Role -eq 'DomainController'
    [string] $hostName = Get-LabLinuxHostName -Machine $Machine
    [hashtable] $parameter = @{
        Name = $Machine.Name
        HostName = $hostName
        Address = $Machine.Address
        PrefixLength = $Lab.Network.PrefixLength
        Gateway = $Lab.Network.Gateway
        NetworkPrefix = $Lab.Network.Prefix
        Dns = $controller.Address
        DomainController = "$($controller.Name.ToLowerInvariant()).$($Lab.DomainName)"
        Role = $Machine.Role
    }
    if ($Machine.Role -eq 'PostgreSql') {
        $parameter.PostgreSql = Get-LabPostgreSqlParameter -Lab $Lab -Machine $Machine
    }
    if ($Machine.Role -eq 'Xmip') {
        $parameter.Xmip = @{ Node = $Machine.Name }
    }
    return $parameter
}

function Get-LabPostgreSqlParameter {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab,

        [Parameter(Mandatory = $true)]
        [hashtable] $Machine
    )

    [hashtable] $primary = $null
    if ($Machine.ContainsKey('StandbyOf')) {
        [hashtable] $source = $Lab.Machines | Where-Object Name -eq $Machine.StandbyOf
        $primary = @{
            Fqdn = "$(Get-LabLinuxHostName -Machine $source).$($Lab.DomainName)"
            Slot = Get-LabReplicationSlot -Machine $Machine
        }
    }
    [object[]] $standbys = @($Lab.Machines | Where-Object {
        $_.ContainsKey('StandbyOf') -and $_.StandbyOf -eq $Machine.Name
    } | ForEach-Object {
        @{ Address = $_.Address; Slot = Get-LabReplicationSlot -Machine $_ }
    })
    return @{
        MajorVersion = $Lab.PostgreSql.MajorVersion
        Port = $Lab.PostgreSql.Port
        Primary = $primary
        Standbys = $standbys
    }
}
