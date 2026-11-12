#requires -Version 7.7.0

Set-StrictMode -Version Latest

function Deploy-XmipEnvironment {
    <#
        .SYNOPSIS
            Makes an environment, its machines and the Xmip node each runs,
            with the template set its environment file names: Microsoft DSC
            v3 or Ansible, never a mix.

        .DESCRIPTION
            The environment file, TOML, is the one place that says what an
            environment is (deploy/dsc/README.md): technology, msdsc or
            ansible, whose template set makes it all; the hypervisor whose
            machines it makes, hyperv on a Windows host, libvirt on a Linux
            one; the network, the images and the machines, each with the
            node it runs; and what a node is given: the cluster's file, this
            machine's xmip-service that slices and signs each node's
            configuration, the authority that signs it and issued each
            node's certificate, the package and, for msdsc, the tools DSC is
            brought to each AlmaLinux machine with. A file naming no
            technology is refused.

            First the run takes the environment's private state, so a second
            run of the environment is refused while one runs, -WhatIf too,
            before it writes anything there. Then the state is made: the
            technology that makes the environment, written by the first run
            that applies, so the other one is refused until the environment
            is removed; the SSH key the AlmaLinux machines are reached with,
            readable by this account alone; a host key for each such
            machine, which its kickstart gives it; and known_hosts holding
            them, so every login is checked strictly.

            msdsc applies each document on its own, with the parameters it
            declares: the network; each machine, one installation at a time,
            applied again every thirty seconds until it answers from its
            disk; the names, where one of the machines is the network's DNS
            server; then each node on its machine, in the order the file
            lists them: its configuration sliced and signed here, DSC
            brought to the machine and node.dsc.yaml applied there.

            ansible writes inventory.yml from the file and runs
            deploy/dsc/ansible/environment.yml: the machines, one
            installation at a time, the names, then the nodes, one machine
            at a time. Ansible's controller does not run on Windows, so
            there it is refused, naming the command to run in WSL.

            One line is written per step, or per play: ETD, ATD and ETA, the
            time elapsed, left and in all. Everything DSC or Ansible says
            goes to .local-work/deploy/<environment>/run.log, beside the
            YAML written for them. The Hyper-V template's network asks for
            elevation and its machines for a member of the Hyper-V
            Administrators group: run it in an elevated Xmip PowerShell
            Console. -WhatIf tests a fresh host too, and changes nothing: a
            msdsc resource answers what is not there yet as absent, and
            Ansible's --check answers a machine not made yet unreached and a
            host that would change not in its desired state.

        .PARAMETER Path
            The environment file, as deploy/dsc/libvirt.example.toml and
            deploy/dsc/hyperv.example.toml show it.

        .EXAMPLE
            Deploy-XmipEnvironment -Path '/mnt/d/Repos/Xmip/.local-work/deploy/libvirt.toml'

            On a Linux host: the libvirt environment's machines and nodes,
            with the technology its file names.

        .EXAMPLE
            Deploy-XmipEnvironment -Path 'D:\Repos\Xmip\.local-work\deploy\hyperv.toml' -WhatIf

            Tests every step and changes nothing.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Path
    )

    $ErrorActionPreference = 'Stop'
    $environment = Read-XmipToml -Path $Path
    [string] $name = Get-TomlValue -Node $environment -Name 'name'
    [string] $estate = Split-Path -Path $PSScriptRoot -Parent
    [string] $log = Join-Path (Get-XmipEstateLayout -Root $estate).Deploy $name
    New-Item -Path $log -ItemType Directory -Force -WhatIf:$false | Out-Null
    [hashtable] $read = Get-XmipDeployEnvironment -Environment $environment -Estate $estate -Run (
        $log)
    if ($read.Technology -eq 'ansible' -and $IsWindows) {
        [string] $wsl = ConvertTo-XmipWslPath -Path (Resolve-Path -LiteralPath $Path).Path
        [string] $module = ConvertTo-XmipWslPath -Path (Join-Path $PSScriptRoot 'Xmip.psd1')
        throw ('REFUSED: Ansible''s controller does not run on Windows ' +
            '(https://docs.ansible.com/ansible/latest/os_guide/intro_windows.html). Run it ' +
            "in WSL: wsl.exe -- pwsh -Command `"Import-Module $module; " +
            "Deploy-XmipEnvironment -Path $wsl`"")
    }
    [string] $act = "Make its machines and nodes with $($read.Technology)"
    [bool] $apply = $PSCmdlet.ShouldProcess($name, $act)
    # -WhatIf means test and change nothing; the log, state and YAML are still written.
    $WhatIfPreference = $false
    # One run of an environment at a time, -WhatIf too: its tests would read
    # machines another run is changing. Held before anything is written to
    # the state, so a run refused changes no key or known_hosts another reads.
    [string] $folder = Get-XmipDeployStateFolder -Name $name -Run $log
    [IO.FileStream] $held = Lock-XmipDeployState -Folder $folder
    try {
        [hashtable] $made = @{ Environment = $environment; Folder = $folder }
        [hashtable] $state = Initialize-XmipDeployState @made -Technology $read.Technology -Record:(
            $apply)
        if ($read.Technology -eq 'ansible') {
            [string] $inventory = Write-XmipDeployInventory -Read $read -State $state -Estate (
                $estate) -Run $log
            # A Windows host or machine is logged on to with a password no file holds.
            [bool] $windows = $read.Hypervisor -eq 'hyperv' -or @($read.Machines |
                    Where-Object { $_['image'].family -eq 'Windows' }).Count -gt 0
            # The machines a play goes to: each that runs a node, and the DNS server.
            [string[]] $named = @($read.Nodes | ForEach-Object { $_.machine.name }) + @(
                $read.NameServer | Where-Object { $_ } | ForEach-Object { $_.name })
            [hashtable] $played = @{ Inventory = $inventory; Estate = $estate; Log = $log
                Named = $named }
            return Invoke-XmipDeployPlaybook @played -Check:(-not $apply) -AskPass:$windows
        }
        Invoke-XmipDeployRun -Read $read -State $state -Estate $estate -Log $log -Apply:$apply
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
