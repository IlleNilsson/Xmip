#requires -PSEdition Core
#requires -Version 7.6.5
# What an unattended installation reads, written for one machine: Windows
# Setup's autounattend.xml and Anaconda's kickstart, and the small ISO image
# that carries them. Each answer is text and nothing else. $Machine is the
# input machine.dsc.yaml gives its Installation resource.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The attributes every component of an amd64 answer file carries.
$script:UnattendComponent = 'processorArchitecture="amd64" ' +
    'publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"'

function Get-MachineMacAddress {
    <#
    .SYNOPSIS
    The static MAC a machine is given: Hyper-V's prefix 00-15-5D and the last
    three octets of its address, so a kickstart can match its adapter by MAC.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Address
    )

    [byte[]] $bytes = ([ipaddress]::Parse($Address)).GetAddressBytes()
    return '00155D{0:X2}{1:X2}{2:X2}' -f $bytes[1], $bytes[2], $bytes[3]
}

function ConvertTo-UnattendPassword {
    <#
    .SYNOPSIS
    A password as an answer file holds it with PlainText false: Base64 of the
    UTF-16 password followed by the name of the element that holds it.
    .DESCRIPTION
    An encoding, not encryption: whoever reads the file can decode it, which
    is why the answer medium is deleted once the guest is installed.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [securestring] $Password,

        [Parameter(Mandatory = $true)]
        [string] $Element
    )

    [string] $plain = [pscredential]::new('answer', $Password).GetNetworkCredential().Password
    return [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($plain + $Element))
}

function Get-MachineWindowsAnswer {
    <#
    .SYNOPSIS
    The autounattend.xml that installs one Windows machine from its ISO.
    .DESCRIPTION
    A GPT layout on the first disk (EFI, MSR, Windows), the image the
    machine's image names as its edition, the computer name, the built-in
    Administrator enabled with the given password, and the out-of-box
    experience skipped. LF line endings.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [object] $Machine,

        [Parameter(Mandatory = $true)]
        [securestring] $AdministratorPassword
    )

    [hashtable] $value = @{
        EDITION = $Machine.image.edition
        COMPUTERNAME = $Machine.name
        PASSWORD = ConvertTo-UnattendPassword -Password $AdministratorPassword -Element (
            'AdministratorPassword')
    }
    [string] $template = Get-Content -LiteralPath (
        Join-Path -Path $PSScriptRoot -ChildPath 'autounattend.template.xml') -Raw
    [string] $answer = $template.Replace('COMPONENT>', "$script:UnattendComponent>")
    foreach ($token in $value.Keys) {
        [string] $text = [Security.SecurityElement]::Escape($value[$token])
        $answer = $answer.Replace(">$token<", ">$text<")
    }
    return $answer -replace "`r`n", "`n"
}

function Get-MachineNetmask {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [int] $PrefixLength
    )

    [string] $bits = ('1' * $PrefixLength).PadRight(32, '0')
    return (0..3 | ForEach-Object { [Convert]::ToByte($bits.Substring($_ * 8, 8), 2) }) -join '.'
}

function Get-MachineKickstart {
    <#
    .SYNOPSIS
    The ks.cfg that installs one AlmaLinux machine from its DVD.
    .DESCRIPTION
    Installs from the DVD's own repositories, so no network is needed while
    installing: the host name, the static address on the adapter with the
    machine's static MAC, the network's DNS server, the Linux account with
    the given SSH key, no password and sudo without one, root locked, sshd
    and firewalld enabled. LF line endings.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [object] $Machine,

        [Parameter(Mandatory = $true)]
        [string] $PublicKey
    )

    [string] $hostName = "$($Machine.name.ToLowerInvariant()).$($Machine.domainName)"
    [string] $mac = (Get-MachineMacAddress -Address $Machine.address) -replace '(..)(?!$)', '$1:'
    [object] $network = $Machine.network
    [string] $netmask = Get-MachineNetmask -PrefixLength $network.prefixLength
    [string] $user = $Machine.linuxAccount
    [string[]] $kickstart = @(
        "# $($Machine.name), installed from the DVD."
        'cdrom'
        'text'
        'skipx'
        'firstboot --disable'
        'lang en_US.UTF-8'
        'keyboard --vckeymap=us'
        'timezone Etc/UTC --utc'
        "network --device=$mac --bootproto=static --ip=$($Machine.address) " +
            "--netmask=$netmask --gateway=$($network.gateway) " +
            "--nameserver=$($network.dnsServer) --hostname=$hostName --noipv6 " +
            '--onboot=yes --activate'
        'rootpw --lock'
        "user --name=$user --groups=wheel --lock"
        "sshkey --username=$user `"$PublicKey`""
        'firewall --enabled --service=ssh'
        'selinux --enforcing'
        'services --enabled=sshd,firewalld'
        'zerombr'
        'clearpart --all --initlabel --disklabel=gpt'
        'autopart --type=lvm --nohome'
        'reboot'
        ''
        '%packages'
        '@^minimal-environment'
        'openssh-server'
        'firewalld'
        'sudo'
        'tar'
        'hyperv-daemons'
        '%end'
        ''
        '%post --erroronfail'
        "echo '$user ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/$user"
        "chmod 0440 /etc/sudoers.d/$user"
        "echo 'PasswordAuthentication no' > /etc/ssh/sshd_config.d/40-xmip.conf"
        '%end'
    )
    return ($kickstart -join "`n") + "`n"
}

function Get-MachinePublicKey {
    <#
    .SYNOPSIS
    The SSH public key as a kickstart takes it: its type and key, no comment.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    [string[]] $fields = @((Get-Content -LiteralPath $Path -Raw).Trim() -split '\s+')
    if ($fields.Count -lt 2 -or $fields[0] -ne 'ssh-ed25519' -or
        $fields[1] -notmatch '^[A-Za-z0-9+/=]+$') {
        throw "REFUSED: not an ed25519 public key: $Path"
    }
    return "$($fields[0]) $($fields[1])"
}

function Get-MachineAnswerMedium {
    <#
    .SYNOPSIS
    What one machine's answer medium holds: its volume label and its files.
    .DESCRIPTION
    Windows Setup reads autounattend.xml from the root of any removable
    medium; Anaconda reads ks.cfg from a volume labelled OEMDRV without being
    told to. The Windows answer takes the Administrator password from the
    machine's credential file, the Linux answer its SSH public key.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [object] $Machine
    )

    if ($Machine.image.family -eq 'Windows') {
        [pscredential] $administrator = Import-Clixml -LiteralPath $Machine.credentialPath
        [hashtable] $windows = @{
            Machine = $Machine
            AdministratorPassword = $administrator.Password
        }
        return @{
            Label = 'XMIP'
            File = [ordered] @{ 'autounattend.xml' = Get-MachineWindowsAnswer @windows }
        }
    }
    [string] $key = Get-MachinePublicKey -Path $Machine.sshPublicKeyPath
    return @{
        Label = 'OEMDRV'
        File = [ordered] @{ 'ks.cfg' = Get-MachineKickstart -Machine $Machine -PublicKey $key }
    }
}

function New-MachineAnswerMedium {
    <#
    .SYNOPSIS
    Writes an answer medium as an ISO image (ISO 9660 with Joliet names),
    through the image mastering API every Windows host has: no tool to install.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [hashtable] $Medium
    )

    if (-not $PSCmdlet.ShouldProcess($Path, 'Write the answer medium')) {
        return
    }
    [string] $stage = "$Path.files"
    New-Item -Path $stage -ItemType Directory -Force | Out-Null
    try {
        [System.Text.UTF8Encoding] $utf8 = [System.Text.UTF8Encoding]::new($false)
        foreach ($name in $Medium.File.Keys) {
            [string] $file = Join-Path -Path $stage -ChildPath $name
            [IO.File]::WriteAllText($file, $Medium.File[$name], $utf8)
        }
        [object] $image = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
        # 1 is ISO 9660 and 2 is Joliet: both read by WinPE and by Anaconda.
        $image.FileSystemsToCreate = 3
        $image.VolumeName = $Medium.Label
        $image.Root.AddTree($stage, $false)
        Save-MachineImageStream -Path $Path -Result $image.CreateResultImage()
    }
    finally {
        Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction Ignore
    }
}

function Save-MachineImageStream {
    <#
    .SYNOPSIS
    Copies an image mastering result, a COM IStream, to a file.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [object] $Result
    )

    [long] $left = [long] $Result.TotalBlocks * $Result.BlockSize
    # The image is a COM IStream; its Read is reached through the interface.
    [Reflection.MethodInfo] $read =
        [System.Runtime.InteropServices.ComTypes.IStream].GetMethod('Read')
    [byte[]] $buffer = [byte[]]::new(64KB)
    [IO.FileStream] $out = [IO.File]::Create($Path)
    try {
        while ($left -gt 0) {
            [int] $count = [Math]::Min($left, $buffer.Length)
            $read.Invoke($Result.ImageStream, @($buffer, $count, [IntPtr]::Zero)) | Out-Null
            $out.Write($buffer, 0, $count)
            $left -= $count
        }
    }
    finally {
        $out.Dispose()
    }
}
