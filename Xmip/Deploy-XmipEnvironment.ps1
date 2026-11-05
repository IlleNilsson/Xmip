#requires -Version 7.7.0

Set-StrictMode -Version Latest

function Deploy-XmipEnvironment {
    <#
        .SYNOPSIS
            Makes an environment's machines with Microsoft DSC v3: its
            network, then each machine, installed from its ISO, until every
            one is in its desired state.

        .DESCRIPTION
            The environment file, TOML, names the hypervisor whose template
            makes the machines (deploy/dsc/msdsc/<hypervisor>: hyperv on a
            Windows host, libvirt on a Linux one), the network and the
            machines. Each of the template's documents is applied on its own,
            in order — the network, then each machine — with the parameters it
            declares, so every resource is set before the next one reads it.
            A machine installs on its own; while one does, its document is
            applied again every thirty seconds, which moves it on, until it
            answers from its disk and its media are removed.

            One line is written per step: ETD, ATD and ETA, the time elapsed,
            left and in all. Everything DSC
            says goes to .local-work/deploy/<environment>/run.log. A Hyper-V
            template asks for elevation: run it in an elevated Xmip
            PowerShell Console. -WhatIf tests and changes nothing.

        .PARAMETER Path
            The environment file, as deploy/dsc/msdsc/<hypervisor>/
            environment.example.xmip shows it.

        .EXAMPLE
            Deploy-XmipEnvironment -Path 'D:\Repos\Xmip\.local-work\deploy\hyperv.xmip'

        .EXAMPLE
            Deploy-XmipEnvironment -Path 'D:\Repos\Xmip\.local-work\deploy\hyperv.xmip' -WhatIf
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
    [string] $hypervisor = Get-TomlValue -Node $environment -Name 'hypervisor'
    [string] $estate = Split-Path -Path $PSScriptRoot -Parent
    [string] $template = Join-Path $estate "deploy/dsc/msdsc/$hypervisor"
    if (-not (Test-Path -LiteralPath (Join-Path $template 'machine.dsc.yaml'))) {
        throw "REFUSED: no template for the hypervisor '$hypervisor': $template"
    }
    [string] $log = Join-Path $estate ".local-work/deploy/$name"
    New-Item -Path $log -ItemType Directory -Force -WhatIf:$false | Out-Null
    [bool] $apply = $PSCmdlet.ShouldProcess($name, 'Make its network and machines')
    [string] $operation = if ($apply) { 'set' } else { 'test' }
    # -WhatIf means test and change nothing; the log and parameters are still written.
    $WhatIfPreference = $false

    [hashtable[]] $step = @(Get-XmipDeployStep -Environment $environment -Template $template)
    [datetime] $started = [datetime]::UtcNow
    [System.Collections.Generic.List[hashtable]] $waiting = @()
    [hashtable] $last = @{}
    [hashtable] $line = @{ Count = $step.Count; Started = $started }
    for ([int] $index = 0; $index -lt $step.Count; $index++) {
        [hashtable] $asked = @{ Step = $step[$index]; Operation = $operation; Log = $log }
        [hashtable] $result = Invoke-XmipDeployStep @asked
        Write-XmipDeployLine -Step $step[$index] -Result $result -Index $index @line
        if ($apply -and -not $result.InDesiredState) {
            $waiting.Add($step[$index])
        }
        $last[$step[$index].Name] = $result
    }
    while ($waiting.Count -gt 0) {
        Start-Sleep -Seconds 30
        foreach ($next in @($waiting)) {
            [hashtable] $result = Invoke-XmipDeployStep -Step $next -Operation 'set' -Log $log
            Write-XmipDeployLine -Step $next -Result $result -Index -1 @line
            $last[$next.Name] = $result
            if ($result.InDesiredState) {
                $waiting.Remove($next) | Out-Null
            }
        }
    }
    # Each step's last result, once, after the lines, so a table never splits them.
    foreach ($each in $step) {
        [pscustomobject] $last[$each.Name]
    }
}

function Get-XmipDeployStep {
    <#
        The documents to apply, in order, each with the values of the
        parameters it declares: the network, then one per machine.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Environment,

        [Parameter(Mandatory)]
        [string] $Template
    )

    $network = Get-TomlValue -Node $Environment -Name 'network'
    [string] $prefix = Get-TomlValue -Node $network -Name 'prefix'
    [object[]] $machines = @(Get-TomlValue -Node $Environment -Name 'machines' -Default @())
    [hashtable] $common = @{
        template = $Template
        environment = Get-TomlValue -Node $Environment -Name 'name'
        root = Get-TomlValue -Node $Environment -Name 'root'
        credentialPath = Get-TomlValue -Node $Environment -Name 'credential' -Default ''
        sshPublicKeyPath = Get-TomlValue -Node $Environment -Name 'ssh_public_key' -Default ''
        linuxAccount = Get-TomlValue -Node $Environment -Name 'linux_account' -Default ''
        domainName = Get-TomlValue -Node $Environment -Name 'domain'
        network = @{
            name = Get-TomlValue -Node $network -Name 'name'
            switchName = Get-TomlValue -Node $network -Name 'name'
            bridge = Get-TomlValue -Node $network -Name 'bridge' -Default ''
            prefix = $prefix
            gateway = Get-TomlValue -Node $network -Name 'gateway'
            prefixLength = [int] ($prefix -replace '^.*/', '')
            dnsServer = Get-TomlValue -Node $network -Name 'dns_server'
            enableNat = [bool] (Get-TomlValue -Node $network -Name 'nat' -Default $false)
        }
        machines = @($machines | ForEach-Object {
            @{
                name = Get-TomlValue -Node $_ -Name 'name'
                address = Get-TomlValue -Node $_ -Name 'address'
            }
        })
        names = @(Get-XmipDeployName -Environment $Environment)
    }
    @{ Name = 'network'; Document = Join-Path $Template 'network.dsc.yaml'; Value = $common }
    $images = Get-TomlValue -Node $Environment -Name 'images'
    foreach ($machine in $machines) {
        [hashtable] $value = $common.Clone()
        $value['image'] = Get-TomlValue -Node $images -Name (
            Get-TomlValue -Node $machine -Name 'image')
        $value['name'] = Get-TomlValue -Node $machine -Name 'name'
        $value['address'] = Get-TomlValue -Node $machine -Name 'address'
        $value['memoryGB'] = [int] (Get-TomlValue -Node $machine -Name 'memory_gb')
        $value['cpu'] = [int] (Get-TomlValue -Node $machine -Name 'cpu')
        $value['diskGB'] = [int] (Get-TomlValue -Node $machine -Name 'disk_gb')
        [string] $document = Join-Path $Template 'machine.dsc.yaml'
        @{ Name = $value['name']; Document = $document; Value = $value }
    }
}

function Get-XmipDeployName {
    <#
        The names the environment adds to its machines' own: each node a
        machine runs, at that machine's address, and the cluster at every
        address that runs one of its nodes.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Environment
    )

    [string[]] $running = @()
    foreach ($machine in @(Get-TomlValue -Node $Environment -Name 'machines' -Default @())) {
        [string[]] $nodes = @(Get-TomlValue -Node $machine -Name 'nodes' -Default @())
        if ($nodes.Count -eq 0) {
            continue
        }
        [string] $address = Get-TomlValue -Node $machine -Name 'address'
        foreach ($node in $nodes) {
            @{ name = $node; addresses = @($address) }
        }
        $running += $address
    }
    [string] $cluster = Get-TomlValue -Node $Environment -Name 'cluster' -Default ''
    if ($cluster -ne '' -and $running.Count -gt 0) {
        @{ name = $cluster; addresses = $running }
    }
}

function Invoke-XmipDeployStep {
    <#
        One document applied or tested by dsc, with the values of the
        parameters it declares; answers whether every resource is in its
        desired state. What dsc says goes to the log; a failure is refused
        with dsc's own last errors.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Step,

        [Parameter(Mandatory)]
        [ValidateSet('set', 'test')]
        [string] $Operation,

        [Parameter(Mandatory)]
        [string] $Log
    )

    [System.Collections.IDictionary] $wanted = (Read-XmipYaml -Path $Step.Document)['parameters']
    [hashtable] $value = @{}
    foreach ($name in $wanted.Keys) {
        $value[$name] = $Step.Value[$name]
    }
    [string] $parameters = Join-Path $Log "$($Step.Name).parameters.yaml"
    Write-XmipYaml -Path $parameters -Value @{ parameters = $value }
    [string] $trace = Join-Path $Log 'run.log'
    [datetime] $begun = [datetime]::UtcNow
    "== $($begun.ToString('o')) $Operation $($Step.Name)" | Add-Content -LiteralPath $trace
    # The template's own resources are found on PATH, beside its documents.
    [string] $path = $env:PATH
    $env:PATH = (Split-Path -Path $Step.Document -Parent) + [IO.Path]::PathSeparator + $path
    try {
        [string[]] $arguments = @('config', '--parameters-file', $parameters, $Operation,
            '--file', $Step.Document)
        [string] $json = (& dsc @arguments 2>> $trace) -join "`n"
        [int] $exit = $LASTEXITCODE
        if ($exit -eq 0 -and $Operation -eq 'set') {
            $arguments[3] = 'test'
            $json = (& dsc @arguments 2>> $trace) -join "`n"
            $exit = $LASTEXITCODE
        }
    }
    finally {
        $env:PATH = $path
    }
    $json | Add-Content -LiteralPath $trace
    [int] $seconds = ([datetime]::UtcNow - $begun).TotalSeconds
    [string[]] $errors = @(Get-Content -LiteralPath $trace -Tail 200 |
        Where-Object { $_ -match 'ERROR' } | Select-Object -Last 3)
    [bool] $elevation = ($errors -join ' ') -match 'Elevated security context required'
    if ($exit -ne 0 -and $Operation -eq 'test' -and -not $elevation) {
        # Some resources (HyperVDsc's DVD drives, NetworkingDsc's address)
        # throw when tested before what they build on exists, as on a fresh
        # host; set makes that first. Testing says so and goes on.
        return @{ Step = $Step.Name; InDesiredState = $false; Seconds = $seconds
            Note = 'cannot be tested until the steps before it are made' }
    }
    if ($exit -ne 0) {
        throw "REFUSED: $($Step.Name): dsc $Operation exit $exit. $($errors -join ' ') ($trace)"
    }
    [object[]] $results = @(($json | ConvertFrom-Json -AsHashtable)['results'])
    [object[]] $differ = @($results | Where-Object { -not $_['result']['inDesiredState'] })
    return @{
        Step = $Step.Name
        InDesiredState = $differ.Count -eq 0
        Seconds = $seconds
        Note = ''
    }
}

function Write-XmipDeployLine {
    <#
        One line per step: the departure, expected and actual, and the
        estimated arrival, clock times; the time elapsed, left and in all;
        then which step and how it stands. -Index -1 is a round of waiting
        for an installation, whose end is not known.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Step,

        [Parameter(Mandatory)]
        [hashtable] $Result,

        [Parameter(Mandatory)]
        [int] $Index,

        [Parameter(Mandatory)]
        [int] $Count,

        [Parameter(Mandatory)]
        [datetime] $Started
    )

    [datetime] $now = [datetime]::UtcNow
    [timespan] $elapsed = $now - $Started
    [string] $state = if ($Result.InDesiredState) { 'in its desired state' }
    elseif ($Result.Note) { "not yet in its desired state, $($Result.Note)" }
    else { 'not yet in its desired state' }
    # The departure, expected and actual, is the command's start; the arrival
    # is estimated at the pace so far. A round of waiting has no estimate.
    [string] $departure = $Started.ToLocalTime().ToString('HH:mm')
    [string] $left = 'unknown'
    [string] $total = 'unknown'
    [string] $eta = 'unknown'
    if ($Index -ge 0) {
        [timespan] $remaining = [timespan]::FromSeconds(
            $elapsed.TotalSeconds / ($Index + 1) * ($Count - $Index - 1))
        $left = $remaining.ToString('h\:mm\:ss')
        $total = ($elapsed + $remaining).ToString('h\:mm\:ss')
        $eta = $now.Add($remaining).ToLocalTime().ToString('HH:mm')
    }
    [string] $place = if ($Index -ge 0) { "step $($Index + 1) of $Count" } else { 'waiting' }
    # A middle dot between the fields, written by its code point.
    [string] $dot = " $([char] 0x00B7) "
    [string] $times = @(
        "ETD: $departure", "ATD: $departure", "ETA: $eta"
        "Elapsed: $($elapsed.ToString('h\:mm\:ss'))", "Left: $left", "Total: $total"
    ) -join $dot
    Write-Host -Object "$times$dot${place}: $($Step.Name) $state ($($Result.Seconds) s)"
}
