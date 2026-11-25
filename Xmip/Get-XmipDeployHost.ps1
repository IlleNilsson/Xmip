#requires -Version 7.7.0

Set-StrictMode -Version Latest

# The site a deployed node's package is built as (deploy/package/README.md).
[string] $script:XmipDeploySite = 'personal-computer'

# The account each AlmaLinux machine's kickstart makes, which is given the
# environment's own SSH key: Xmip's choice, never asked.
[string] $script:XmipDeployLinuxAccount = 'xmip-admin'

function Get-XmipDeployHypervisor {
    <#
        .SYNOPSIS
            The kind of virtual machine this host makes: hyperv on Windows,
            libvirt (KVM) on Linux; refused in words on macOS, which has
            neither. The one answer Deploy-XmipEnvironment and
            Start-XmipTest -VirtualMachine both take (ADR-0015, amendment
            2026-11-25).

        .DESCRIPTION
            -Hypervisor overrides it for one case alone: Ansible's controller
            does not run on Windows, so a Windows host's Hyper-V machines are
            made by Ansible from WSL, a Linux guest, and the WSL command
            Deploy-XmipEnvironment names on Windows carries -Hypervisor
            hyperv. Microsoft DSC applies its documents on the machine it
            runs on, so msdsc takes the host's own kind alone.

        .PARAMETER Hypervisor
            The kind given, hyperv or libvirt; empty, the host's.

        .PARAMETER Technology
            msdsc or ansible: what makes the machines.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string] $Hypervisor = '',

        [Parameter()]
        [string] $Technology = 'msdsc'
    )

    [string] $own = if ($IsWindows) { 'hyperv' } elseif ($IsLinux) { 'libvirt' } else { '' }
    if (-not $own) {
        throw ('REFUSED: this host makes no virtual machine Xmip deploys: Hyper-V on ' +
            'Windows, or KVM through libvirt on Linux; macOS has neither.')
    }
    if (-not $Hypervisor -or $Hypervisor -eq $own) {
        return $own
    }
    if ($Hypervisor -eq 'hyperv' -and $IsLinux -and $Technology -eq 'ansible') {
        return 'hyperv'
    }
    throw ("REFUSED: this host makes $own virtual machines; -Hypervisor $Hypervisor is " +
        'taken only by Ansible from WSL, making a Windows host''s Hyper-V machines.')
}

function Get-XmipAccountFolder {
    <#
        .SYNOPSIS
            This account's own Xmip folder on this machine: Xmip in
            %LOCALAPPDATA% on Windows; elsewhere xmip in $XDG_STATE_HOME, or
            in ~/.local/state. The runtime keeps a cluster's authority there
            where no folder is named (runtime::signed::own_folder; ADR-0031,
            amendment 2026-11-25), and a deployment its images.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ($IsWindows) {
        return Join-Path $env:LOCALAPPDATA 'Xmip'
    }
    [string] $base = if ($env:XDG_STATE_HOME) { $env:XDG_STATE_HOME }
    else { Join-Path $HOME '.local/state' }
    return Join-Path $base 'xmip'
}

function Get-XmipDeployHost {
    <#
        .SYNOPSIS
            What this host gives an environment, each a default Xmip takes
            and a person gives only where it cannot choose (the owner,
            2026-11-25): the network, the disks' folder, the uplink, the
            images and tools, the build each machine is given, and what the
            private state keeps for it. Refused in words where one is not
            there, naming what makes it.

        .DESCRIPTION
            A fact given once, as a parameter of Deploy-XmipEnvironment, is
            kept in the private state (host.toml) and taken by every later
            run that gives none. Kept, given, then Xmip's own:

            - Network: a free private /24 on this host, 10.77.<n>.0/24, the
              first no address or route of the host overlaps.
            - Root: Hyper-V's folder of virtual hard disks, or libvirt's
              /var/lib/libvirt/images, with Xmip-<cluster>.
            - Uplink, where the cluster names a gateway: the host's one
              external switch (Hyper-V) or bridge (libvirt).
            - Images: each found under the image folder by its SHA-256, the
              folder images in the account's Xmip folder where none is
              given; the tools Microsoft DSC is brought with found there by
              the names and SHA-256 prerequisite.toml gives them.
            - The build of this tree, .local-work/package/<version>: each
              family's package, module libraries and far-end program, and
              this host's xmip-service, which slices and signs.
            - The private state's: the cluster's authority, each machine's
              certificate, the operator's certificate and, for Windows
              machines, the Administrator secret.

        .PARAMETER Cluster
            The cluster's name.

        .PARAMETER Content
            The cluster file, as Read-XmipToml reads it.

        .PARAMETER Machines
            The machines, as Resolve-XmipDeployMachine resolves them.

        .PARAMETER Hypervisor
            hyperv or libvirt (Get-XmipDeployHypervisor).

        .PARAMETER Technology
            msdsc or ansible.

        .PARAMETER Given
            What Deploy-XmipEnvironment was given: ImageFolder, DiskFolder,
            Uplink, WindowsHost and Operator, each where given.

        .PARAMETER Kept
            What the private state kept, Read-XmipDeployHost's.

        .PARAMETER Estate
            The estate's root.

        .PARAMETER State
            The private state's folder.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $Cluster,

        [Parameter(Mandatory)]
        [AllowNull()]
        $Content,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [hashtable[]] $Machines,

        [Parameter(Mandatory)]
        [string] $Hypervisor,

        [Parameter(Mandatory)]
        [string] $Technology,

        [Parameter()]
        [System.Collections.IDictionary] $Given = @{},

        [Parameter()]
        [hashtable] $Kept = @{},

        [Parameter(Mandatory)]
        [string] $Estate,

        [Parameter(Mandatory)]
        [string] $State
    )

    [scriptblock] $fact = {
        param([string] $Name)
        if ($Given.Keys -contains $Name -and $Given[$Name]) { return $Given[$Name] }
        if ($Kept.Keys -contains $Name -and $Kept[$Name]) { return $Kept[$Name] }
        return $null
    }
    $environment = Get-TomlValue -Node $Content -Name 'environment' -Default $null
    [hashtable] $facts = @{
        Hashes = if ($Kept.Contains('Hashes')) { $Kept['Hashes'] } else { @{} }
        LinuxAccount = $script:XmipDeployLinuxAccount
        Authority = Join-Path $State 'authority'
        Identity = Join-Path $State 'identity'
        Operator = Join-Path $State 'operator'
        Secret = Join-Path $State 'secret.xml'
        WindowsHost = [string] (& $fact 'WindowsHost')
        Given = @{}
    }
    $facts.Network = [string] (& $fact 'Network')
    if (-not $facts.Network) {
        $facts.Network = [string] (Get-TomlValue -Node $environment -Name 'network' -Default '')
    }
    if (-not $facts.Network) {
        $facts.Network = Get-XmipDeployFreeNetwork -Taken @(Get-XmipDeployHostPrefix)
    }
    [string] $disks = [string] (& $fact 'DiskFolder')
    if (-not $disks) {
        $disks = Get-XmipDeployDiskRoot -Hypervisor $Hypervisor
    }
    $facts.Root = Join-Path $disks "Xmip-$Cluster"
    $facts.Uplink = ''
    if (Get-TomlValue -Node $environment -Name 'gateway' -Default '') {
        $facts.Uplink = Get-XmipDeployUplink -Given ([string] (& $fact 'Uplink')) -Hypervisor (
            $Hypervisor)
    }
    if ($Technology -eq 'ansible' -and $Hypervisor -eq 'hyperv' -and -not $facts.WindowsHost) {
        throw ('REFUSED: Ansible makes Hyper-V machines from its controller, which reaches ' +
            'the Windows host at the address -WindowsHost names.')
    }
    [string[]] $more = @(& $fact 'Operator' | Where-Object { $_ })
    $facts.Operators = @("CN=$([Environment]::UserName)") + $more
    [string] $images = [string] (& $fact 'ImageFolder')
    if (-not $images) {
        $images = Join-Path (Get-XmipAccountFolder) 'images'
    }
    $facts.ImageFolder = $images
    foreach ($key in 'ImageFolder', 'DiskFolder', 'Uplink', 'WindowsHost', 'Operator') {
        $named = & $fact $key
        if ($named) {
            $facts.Given[$key] = $named
        }
    }
    $facts.Given['Network'] = $facts.Network
    Add-XmipDeployImage -Facts $facts -Content $environment -Machines $Machines -Technology (
        $Technology) -Estate $Estate
    Add-XmipDeployBuild -Facts $facts -Content $Content -Machines $Machines -Estate $Estate
    return $facts
}

function Read-XmipDeployHost {
    <#
        .SYNOPSIS
            The host facts the private state kept, host.toml, as
            Get-XmipDeployHost takes them: each by its parameter's name, and
            the images' SHA-256 already read, by path; empty where none is
            kept.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $Folder
    )

    [string] $path = Join-Path $Folder 'host.toml'
    [hashtable] $kept = @{ Hashes = @{} }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return $kept
    }
    $read = Read-XmipToml -Path $path
    foreach ($key in 'Network', 'ImageFolder', 'DiskFolder', 'Uplink', 'WindowsHost') {
        $kept[$key] = [string] (Get-TomlValue -Node $read -Name $key -Default '')
    }
    $kept['Operator'] = @(Get-TomlValue -Node $read -Name 'Operator' -Default @())
    $hashes = Get-TomlValue -Node $read -Name 'Hashes' -Default $null
    foreach ($file in @(Get-TomlKey -Node $hashes)) {
        $read = Get-TomlValue -Node $hashes -Name $file
        $kept.Hashes[$file] = ConvertTo-XmipTomlTable -Node $read
    }
    return $kept
}

function Write-XmipDeployHost {
    <#
        .SYNOPSIS
            Keeps in the private state, host.toml, each host fact given or
            chosen, so a later run takes it unasked, and the images'
            SHA-256 read, so an image's gigabytes are read once.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $Folder,

        [Parameter(Mandatory)]
        [hashtable] $Facts
    )

    [Collections.Specialized.OrderedDictionary] $kept = [ordered] @{}
    foreach ($key in @($Facts.Given.Keys | Sort-Object)) {
        $kept[$key] = $Facts.Given[$key]
    }
    $kept['Hashes'] = $Facts.Hashes
    Write-XmipToml -Path (Join-Path $Folder 'host.toml') -Value $kept
}
