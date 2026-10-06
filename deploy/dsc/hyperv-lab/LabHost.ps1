#requires -PSEdition Core
#requires -Version 7.6.5
# Host-only operations are guarded at the resource boundary. Hyper-V has no
# cross-platform equivalent; the DSC protocol and validation remain portable.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-LabConfiguration {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    [hashtable] $lab = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
    if ($lab.LabId -notmatch '^[A-Za-z0-9-]+$') {
        throw 'LabId must contain only letters, digits and hyphens.'
    }
    if ($lab.DomainName -notmatch '^[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)+$') {
        throw 'Use a fully qualified lab domain name.'
    }
    if ($lab.NetbiosName -notmatch '^[A-Za-z][A-Za-z0-9-]{0,14}$') {
        throw 'NetbiosName must be a valid domain NetBIOS name.'
    }
    [string[]] $names = @($lab.Machines.Name)
    [string[]] $addresses = @($lab.Machines.Address) + $lab.Network.Gateway
    if (@($names | Select-Object -Unique).Count -ne $names.Count -or
        @($addresses | Select-Object -Unique).Count -ne $addresses.Count) {
        throw 'Machine names and addresses must be unique.'
    }
    if (@($lab.Machines | Where-Object Role -eq 'DomainController').Count -ne 1) {
        throw 'Exactly one domain controller is required.'
    }
    foreach ($machine in $lab.Machines) {
        if ($machine.Name -notmatch '^[A-Za-z][A-Za-z0-9-]{0,14}$' -or
            $machine.MemoryGB -lt 2 -or $machine.Cpu -lt 1 -or
            $machine.Role -notin @('DomainController', 'FileServer', 'Developer',
                'PostgreSql', 'Xmip')) {
            throw 'Invalid machine name, size or role.'
        }
    }
    # Restrict the first version to /24; all IPs must belong to that subnet.
    if ($lab.Network.Prefix -notmatch '^(\d+\.\d+\.\d+)\.0/24$' -or
        $lab.Network.PrefixLength -ne 24) {
        throw 'This lab supports an IPv4 /24 subnet only.'
    }
    [string] $networkBase = $Matches[1]
    foreach ($address in $addresses) {
        [ipaddress] $parsed = [ipaddress]::Parse($address)
        if ($parsed.AddressFamily -ne 'InterNetwork' -or
            $address -notlike "$networkBase.*" -or
            $parsed.GetAddressBytes()[3] -in @(0, 255)) {
            throw "Address outside the lab subnet: $address"
        }
    }
    foreach ($pathKey in @('Root', 'ServerImage', 'DeveloperImage', 'CredentialPath')) {
        if (-not [IO.Path]::IsPathFullyQualified($lab[$pathKey])) {
            throw "$pathKey must be an absolute path."
        }
    }
    return $lab
}

function Get-LabHostFinding {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab
    )

    if ($null -eq (Get-Command -Name Get-VM -ErrorAction SilentlyContinue)) {
        return 'Hyper-V is not enabled; enable the host feature and reboot first.'
    }
    [object] $switch = Get-VMSwitch -Name $Lab.Network.SwitchName -ErrorAction SilentlyContinue
    if ($null -eq $switch -or $switch.SwitchType -ne 'Internal' -or
        $switch.Notes -ne $Lab.LabId) {
        Write-Output -InputObject 'Internal lab switch is missing or does not match.'
    }
    [string] $alias = "vEthernet ($($Lab.Network.SwitchName))"
    [hashtable] $ipQuery = @{
        InterfaceAlias = $alias
        AddressFamily = 'IPv4'
        ErrorAction = 'SilentlyContinue'
    }
    [object[]] $ips = @(Get-NetIPAddress @ipQuery)
    if (@($ips | Where-Object {
        $_.IPAddress -eq $Lab.Network.Gateway -and $_.PrefixLength -eq 24
    }).Count -ne 1) {
        Write-Output -InputObject 'Lab host gateway is missing.'
    }
    [object] $nat = Get-NetNat -Name $Lab.LabId -ErrorAction SilentlyContinue
    if ($Lab.Network.EnableNat -and ($null -eq $nat -or
        $nat.InternalIPInterfaceAddressPrefix -ne $Lab.Network.Prefix)) {
        Write-Output -InputObject 'Outbound NAT is missing or differs.'
    }
    if (-not $Lab.Network.EnableNat -and $null -ne $nat) {
        Write-Output -InputObject 'NAT exists although the lab requests isolation.'
    }
    foreach ($machine in $Lab.Machines) {
        [object] $vm = Get-VM -Name $machine.Name -ErrorAction SilentlyContinue
        if ($null -eq $vm) {
            Write-Output -InputObject "$($machine.Name): VM is missing."
            continue
        }
        [object[]] $nics = @(Get-VMNetworkAdapter -VMName $machine.Name)
        [object] $memory = Get-VMMemory -VMName $machine.Name
        [object[]] $disks = @(Get-VMHardDiskDrive -VMName $machine.Name)
        [string] $disk = Join-Path -Path $Lab.Root -ChildPath "$($machine.Name)/os.vhdx"
        if ($vm.Notes -ne $Lab.LabId -or $vm.Generation -ne 2 -or
            $vm.ProcessorCount -ne $machine.Cpu -or
            $memory.Startup -ne ($machine.MemoryGB * 1GB) -or
            $memory.DynamicMemoryEnabled -or $vm.State -ne 'Running' -or
            $nics.Count -ne 1 -or $nics[0].SwitchName -ne $Lab.Network.SwitchName -or
            $disks.Count -ne 1 -or $disks[0].Path -ne $disk) {
            Write-Output -InputObject "$($machine.Name): VM settings differ."
        }
        if ((Get-VMFirmware -VMName $machine.Name).SecureBoot -ne 'On') {
            Write-Output -InputObject "$($machine.Name): Secure Boot is disabled."
        }
        if ($machine.Role -eq 'Developer' -and
            -not (Get-VMSecurity -VMName $machine.Name).TpmEnabled) {
            Write-Output -InputObject "$($machine.Name): virtual TPM is disabled."
        }
    }
}

function Set-LabNetwork {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab
    )

    [object] $switch = Get-VMSwitch -Name $Lab.Network.SwitchName -ErrorAction SilentlyContinue
    if ($null -ne $switch -and ($switch.Notes -ne $Lab.LabId -or
        $switch.SwitchType -ne 'Internal')) {
        throw 'REFUSED: the switch name belongs to a different configuration.'
    }
    if (-not $PSCmdlet.ShouldProcess($Lab.Network.SwitchName, 'Configure lab networking')) {
        return
    }
    if ($null -eq $switch) {
        New-VMSwitch -Name $Lab.Network.SwitchName -SwitchType Internal | Out-Null
        Set-VMSwitch -Name $Lab.Network.SwitchName -Notes $Lab.LabId
    }
    [string] $alias = "vEthernet ($($Lab.Network.SwitchName))"
    [hashtable] $ipQuery = @{
        InterfaceAlias = $alias
        AddressFamily = 'IPv4'
        ErrorAction = 'SilentlyContinue'
    }
    [object[]] $ips = @(Get-NetIPAddress @ipQuery)
    if (@($ips | Where-Object IPAddress -eq $Lab.Network.Gateway).Count -eq 0) {
        if (@($ips | Where-Object IPAddress -NotLike '169.254.*').Count -gt 0) {
            throw 'REFUSED: the switch already has a different static host address.'
        }
        [hashtable] $gateway = @{
            InterfaceAlias = $alias
            IPAddress = $Lab.Network.Gateway
            PrefixLength = 24
        }
        New-NetIPAddress @gateway | Out-Null
    }
    [object] $nat = Get-NetNat -Name $Lab.LabId -ErrorAction SilentlyContinue
    if ($null -ne $nat -and ($nat.InternalIPInterfaceAddressPrefix -ne $Lab.Network.Prefix -or
        -not $Lab.Network.EnableNat)) {
        throw 'REFUSED: NAT differs; resolve it explicitly before running DSC.'
    }
    if ($Lab.Network.EnableNat -and $null -eq $nat) {
        if (@(Get-NetNat).Count -gt 0) {
            throw 'REFUSED: another host NAT exists; choose an isolated lab or resolve it first.'
        }
        New-NetNat -Name $Lab.LabId -InternalIPInterfaceAddressPrefix $Lab.Network.Prefix |
            Out-Null
    }
}

function Set-LabVirtualMachine {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab,

        [Parameter(Mandatory = $true)]
        [hashtable] $Machine
    )

    [object] $vm = Get-VM -Name $Machine.Name -ErrorAction SilentlyContinue
    if ($null -ne $vm -and $vm.Notes -ne $Lab.LabId) {
        throw "REFUSED: $($Machine.Name) is not owned by this lab."
    }
    if (-not $PSCmdlet.ShouldProcess($Machine.Name, 'Create or start lab VM')) {
        return
    }
    if ($null -eq $vm) {
        [string] $image = if ($Machine.Role -eq 'Developer') {
            $Lab.DeveloperImage
        }
        else {
            $Lab.ServerImage
        }
        [string] $directory = Join-Path -Path $Lab.Root -ChildPath $Machine.Name
        [string] $disk = Join-Path -Path $directory -ChildPath 'os.vhdx'
        if (Test-Path -LiteralPath $directory) {
            throw "REFUSED: unregistered VM directory already exists: $directory"
        }
        New-Item -Path $directory -ItemType Directory | Out-Null
        New-VHD -Path $disk -ParentPath $image -Differencing | Out-Null
        [hashtable] $create = @{
            Name = $Machine.Name
            Generation = 2
            VHDPath = $disk
            Path = $directory
            MemoryStartupBytes = $Machine.MemoryGB * 1GB
            SwitchName = $Lab.Network.SwitchName
        }
        New-VM @create | Out-Null
        Set-VM -Name $Machine.Name -Notes $Lab.LabId -AutomaticCheckpointsEnabled $false
        Set-VMProcessor -VMName $Machine.Name -Count $Machine.Cpu
        Set-VMMemory -VMName $Machine.Name -DynamicMemoryEnabled $false
        Set-VMFirmware -VMName $Machine.Name -EnableSecureBoot On
        if ($Machine.Role -eq 'Developer') {
            Set-VMKeyProtector -VMName $Machine.Name -NewLocalKeyProtector
            Enable-VMTPM -VMName $Machine.Name
        }
    }
    # Existing VM hardware drift is reported, never repaired by stopping a VM.
    if ((Get-VM -Name $Machine.Name).State -eq 'Off') {
        Start-VM -Name $Machine.Name | Out-Null
    }
}

function Assert-LabMedia {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Lab
    )

    foreach ($image in @($Lab.ServerImage, $Lab.DeveloperImage)) {
        if (-not (Test-Path -LiteralPath $image -PathType Leaf)) {
            throw "Prepared Windows VHDX image is missing: $image"
        }
        [object] $vhd = Get-VHD -Path $image
        if ($vhd.Attached -or $vhd.VhdType -eq 'Differencing' -or $vhd.VhdFormat -ne 'VHDX') {
            throw 'Base images must be detached, standalone VHDX files.'
        }
    }
    foreach ($media in @($Lab.PostgreSql, $Lab.Development)) {
        [string] $installer = if ($media.ContainsKey('Installer')) {
            $media.Installer
        }
        else {
            $media.PowerShellMsi
        }
        if (-not (Test-Path -LiteralPath $installer -PathType Leaf) -or
            $media.Sha256 -notmatch '^[a-fA-F0-9]{64}$') {
            throw 'Provide local installers and their verified SHA256 values in lab.json.'
        }
        if ((Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash -ne $media.Sha256) {
            throw "Installer checksum differs: $installer"
        }
    }
}
