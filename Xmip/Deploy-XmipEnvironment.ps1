#requires -Version 7.7.0

Set-StrictMode -Version Latest

function Deploy-XmipEnvironment {
    <#
        .SYNOPSIS
            Makes a cluster's environment from its cluster file: a virtual
            machine for each node, each far end and each machine of its own
            its [environment] names, and the Xmip node each runs, with
            Microsoft DSC v3 or Ansible, never a mix.

        .DESCRIPTION
            One file says what an environment is: the cluster file, its nodes
            and, in [environment], the far ends, the machines of their own, the
            sizes, the domain and the way out, and the images by operating
            system (ADR-0015, amendment 2026-11-25; the owner, 2026-11-25:
            *I still don't get why there is a need for two files?*). The
            machine kind follows the host: Hyper-V on Windows, KVM through
            libvirt on Linux, refused in words on macOS. What this host gives
            are defaults Xmip takes, a parameter given once only where it
            cannot choose, kept in the private state after: the network, a
            free private /24 where the file names none; the disks' folder;
            the uplink; the images, found by SHA-256; the build of this tree;
            the authority, every certificate and the Windows machines'
            Administrator secret, made in the private state.

            First the run takes the environment's private state, so a second
            run is refused while one runs, -WhatIf too. msdsc applies each
            document on its own: the network; each machine, one installation
            at a time; the domain; the way out; the names; each far end; each
            node, its configuration sliced and signed here; and last every
            node started together. ansible writes inventory.yml and runs
            deploy/dsc/ansible/environment.yml; its controller does not run
            on Windows, so there it is refused, naming the WSL command, which
            carries -Hypervisor hyperv and -WindowsHost. A run that applies
            and ends with every step in its desired state records what it
            made, deployed.toml, which Start-XmipTest -VirtualMachine runs on.

            One line is written per step, or per play: ETD, ATD and ETA, the
            time elapsed, left and in all. Everything DSC or Ansible says goes
            to .local-work/deploy/<cluster>/run.log, beside the YAML written
            for them. On Windows it asks for an elevated Xmip PowerShell
            Console, since Hyper-V's network is an administrator's to make,
            and never starts one. -WhatIf tests and changes nothing on the
            machines.

        .PARAMETER Path
            The cluster file: the System Tests' is
            test/core/system-test/configuration/Xmip-reference-environment.xmip.

        .PARAMETER Cluster
            The cluster's name, which the file names none of.

        .PARAMETER Technology
            msdsc (Microsoft DSC v3), what makes it where left out, or ansible.

        .PARAMETER Hypervisor
            The host's own where left out. hyperv from a Linux host is
            Ansible's alone, from WSL onto its Windows host.

        .PARAMETER ImageFolder
            The folder the installation images and the tool archives are found
            in by their SHA-256: images in the account's Xmip folder where
            neither given nor kept.

        .PARAMETER DiskFolder
            The folder the machines' disks go in, Xmip-<cluster> in it:
            Hyper-V's own or libvirt's where neither given nor kept.

        .PARAMETER Uplink
            The external switch (Hyper-V) or bridge (libvirt) the gateway's
            second adapter is on, where the host has several: its one where
            neither given nor kept.

        .PARAMETER WindowsHost
            Ansible on Hyper-V: the Windows host's address as WSL reaches it.

        .PARAMETER Operator
            Who operates the nodes besides this account's person: each a
            certificate's subject, CN=<person>, or an account.

        .EXAMPLE
            $file = './test/core/system-test/configuration/Xmip-reference-environment.xmip'
            Deploy-XmipEnvironment -Path $file -Cluster CL1

            On Windows, in an elevated Xmip PowerShell Console: the System
            Tests' virtual machines and nodes on Hyper-V.

        .EXAMPLE
            Deploy-XmipEnvironment -Path $file -Cluster CL1 -WhatIf

            Tests every step and changes nothing.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Path,

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z][A-Za-z0-9-]*$')]
        [string] $Cluster,

        [Parameter()]
        [ValidateSet('msdsc', 'ansible')]
        [string] $Technology = 'msdsc',

        [Parameter()]
        [ValidateSet('hyperv', 'libvirt')]
        [string] $Hypervisor = '',

        [Parameter()]
        [string] $ImageFolder,

        [Parameter()]
        [string] $DiskFolder,

        [Parameter()]
        [string] $Uplink,

        [Parameter()]
        [string] $WindowsHost,

        [Parameter()]
        [string[]] $Operator
    )

    $ErrorActionPreference = 'Stop'
    [string] $kind = Get-XmipDeployHypervisor -Hypervisor $Hypervisor -Technology $Technology
    [string] $file = (Resolve-Path -LiteralPath $Path).Path
    if ($Technology -eq 'ansible' -and $IsWindows) {
        throw (Get-XmipDeployWslRefusal -Path $file -Cluster $Cluster -Bound $PSBoundParameters)
    }
    if ($kind -eq 'hyperv' -and $IsWindows -and -not (Test-XmipDeployElevated)) {
        throw ('REFUSED: Hyper-V''s network, its switch''s address and its NAT, are an ' +
            'administrator''s to make: run this in an elevated Xmip PowerShell Console.')
    }
    [string] $estate = Split-Path -Path $PSScriptRoot -Parent
    $content = Read-XmipToml -Path $file
    [string] $log = Get-XmipDeployRunFolder -Cluster $Cluster
    New-Item -Path $log -ItemType Directory -Force -WhatIf:$false | Out-Null
    [string] $act = "Make its virtual machines and nodes with $Technology"
    [bool] $apply = $PSCmdlet.ShouldProcess("Xmip-$Cluster", $act)
    # -WhatIf means test and change nothing; the log, state and YAML are still written.
    $WhatIfPreference = $false
    # One run of an environment at a time, -WhatIf too: its tests would read
    # machines another run is changing. Held before anything is written to
    # the state, so a run refused changes no key or known_hosts another reads.
    [string] $folder = Get-XmipDeployStateFolder -Name $Cluster -Run $log
    [IO.FileStream] $held = Lock-XmipDeployState -Folder $folder
    try {
        [hashtable[]] $machines = @(Resolve-XmipDeployMachine -Cluster $content)
        [hashtable] $hosted = @{ Cluster = $Cluster; Content = $content; Machines = $machines
            Hypervisor = $kind; Technology = $Technology; Given = $PSBoundParameters
            Kept = (Read-XmipDeployHost -Folder $folder); Estate = $estate; State = $folder }
        [hashtable] $facts = Get-XmipDeployHost @hosted
        [hashtable] $reading = @{ Cluster = $content; Name = $Cluster; File = $file
            Technology = $Technology; Hypervisor = $kind; Facts = $facts; Estate = $estate
            Run = $log }
        [hashtable] $read = Get-XmipDeployEnvironment @reading
        Write-XmipDeployHost -Folder $folder -Facts $facts
        [hashtable] $state = Initialize-XmipDeployState -Read $read -Folder $folder -Technology (
            $Technology) -Record:$apply
        Initialize-XmipDeployIdentity -Read $read -Facts $facts
        $state['Operator'] = $facts.Operator
        if ($Technology -eq 'ansible') {
            [string] $inventory = Write-XmipDeployInventory -Read $read -State $state -Estate (
                $estate) -Run $log
            # A Windows host or machine is logged on to with a password no file holds.
            [bool] $windows = $kind -eq 'hyperv' -or @($read.Machines |
                    Where-Object { $_['image'].family -eq 'Windows' }).Count -gt 0
            # The machines a play goes to: each that runs a node, and the DNS server.
            [string[]] $named = @($read.Nodes | ForEach-Object { $_.machine.name }) + @(
                $read.NameServer | Where-Object { $_ } | ForEach-Object { $_.name })
            [hashtable] $played = @{ Inventory = $inventory; Estate = $estate; Log = $log
                Named = $named }
            [object[]] $hosts = @(Invoke-XmipDeployPlaybook @played -Check:(-not $apply) -AskPass:(
                    $windows))
            if ($apply -and @($hosts | Where-Object { -not $_.InDesiredState }).Count -eq 0) {
                Write-XmipDeployedEnvironment -Read $read -State $state
            }
            return $hosts
        }
        Invoke-XmipDeployRun -Read $read -State $state -Estate $estate -Log $log -Apply:$apply
        if ($apply) {
            Write-XmipDeployedEnvironment -Read $read -State $state
        }
    }
    finally {
        $held.Dispose()
    }
}

function Invoke-XmipDeployRun {
    <#
        msdsc's run: each step tested or set, a machine set again every
        thirty seconds until it answers, then each step not in its desired
        state tested once more; each step's last result answered, and a run
        that set them refused where one still differs.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Read,

        [Parameter(Mandatory)]
        [hashtable] $State,

        [Parameter(Mandatory)]
        [string] $Estate,

        [Parameter(Mandatory)]
        [string] $Log,

        [Parameter()]
        [switch] $Apply
    )

    [string] $operation = if ($Apply) { 'set' } else { 'test' }
    [hashtable[]] $step = @(Get-XmipDeployStep -Read $Read -State $State -Estate $Estate)
    [hashtable] $line = @{ Count = $step.Count; Started = [datetime]::UtcNow }
    [Collections.Generic.List[object]] $last = @()
    for ([int] $index = 0; $index -lt $step.Count; $index++) {
        [hashtable] $asked = @{ Step = $step[$index]; Operation = $operation; Log = $Log }
        [hashtable] $result = Invoke-XmipDeployStep @asked
        Write-XmipDeployLine -Step $step[$index] -Result $result -Index $index @line
        # A machine installs on its own; it is moved on every thirty seconds
        # until it answers, and only then is the next one made.
        while ($Apply -and $step[$index].ContainsKey('Install') -and -not $result.InDesiredState) {
            Start-Sleep -Seconds 30
            $result = Invoke-XmipDeployStep -Step $step[$index] -Operation 'set' -Log $Log
            Write-XmipDeployLine -Step $step[$index] -Result $result -Index -1 @line
        }
        $last.Add([pscustomobject] $result)
    }
    # A node's service runs only once every node is started together, the last
    # step, so a step not in its desired state is tested once more after it.
    for ([int] $index = 0; $Apply -and $index -lt $step.Count; $index++) {
        if (-not $last[$index].InDesiredState) {
            [hashtable] $again = @{ Step = $step[$index]; Operation = 'test'; Log = $Log }
            $last[$index] = [pscustomobject] (Invoke-XmipDeployStep @again)
        }
    }
    # Each step's last result, once, after the lines, so a table never splits them.
    $last
    [string[]] $differ = @($last | Where-Object { -not $_.InDesiredState } |
        ForEach-Object { $_.Step })
    if ($Apply -and $differ.Count -gt 0) {
        throw "FAILED: not in their desired state after set: $($differ -join ', ') ($Log)."
    }
}

function Get-XmipDeployWslRefusal {
    <#
        Why Ansible is refused on Windows, naming the command to run in WSL:
        Ansible's controller does not run on Windows. The command carries the
        Windows host's kind, -Hypervisor hyperv, and its address as WSL
        reaches it, -WindowsHost, where this host's WSL adapter has one.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Cluster,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Bound
    )

    [string] $wsl = ConvertTo-XmipWslPath -Path $Path
    [string] $module = ConvertTo-XmipWslPath -Path (Join-Path $PSScriptRoot 'Xmip.psd1')
    [string] $reached = if ($Bound.Keys -contains 'WindowsHost') { $Bound['WindowsHost'] }
    else { Get-XmipDeployWslHost }
    if (-not $reached) {
        $reached = '<the Windows host''s address as WSL reaches it>'
    }
    return ('REFUSED: Ansible''s controller does not run on Windows ' +
        '(https://docs.ansible.com/ansible/latest/os_guide/intro_windows.html). Run it ' +
        "in WSL: wsl.exe -- pwsh -Command `"Import-Module $module; Deploy-XmipEnvironment " +
        "-Path $wsl -Cluster $Cluster -Technology ansible -Hypervisor hyperv " +
        "-WindowsHost $reached`"")
}

function Get-XmipDeployWslHost {
    <#
        This Windows host's address on its WSL adapter, vEthernet (WSL...),
        as a WSL guest in NAT mode reaches it; empty where it has none.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return [string] (@(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                Where-Object { $_.InterfaceAlias -like 'vEthernet (WSL*' }) |
            Select-Object -First 1 | ForEach-Object { $_.IPAddress })
}

function Test-XmipDeployElevated {
    <#
        Whether this Windows session is elevated, an administrator's.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $principal = [Security.Principal.WindowsPrincipal](
        [Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function ConvertTo-XmipWslPath {
    <#
        A Windows path as WSL mounts it: D:\Repos\Xmip is /mnt/d/Repos/Xmip.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if ($Path -notmatch '^([A-Za-z]):[\\/](.*)$') {
        return $Path -replace '\\', '/'
    }
    return "/mnt/$($Matches[1].ToLowerInvariant())/$($Matches[2] -replace '\\', '/')"
}
