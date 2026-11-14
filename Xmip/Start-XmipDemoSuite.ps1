#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    Starting a run of Core.Demo, the demo readiness check: detached, in a
    pwsh of its own, recorded, as the estate's Pester suite starts.

.DESCRIPTION
    The owner's demo is on 2026-12-18 and runs from main. Core.Demo proves
    a tree is demo-ready: it builds
    what the demo runs and runs it, part by part, and says each OK or FAILED
    in words, with the reason (ADR-0028, amendment 2026-11-10).
    Start-XmipTest -Suite Core.Demo starts it, Get-XmipTestStatus lists it,
    Get-XmipTestResult -Suite Core.Demo says each part, and Stop-XmipTest
    stops it and everything it started. What the run does is
    Test-XmipDemoReady.ps1; what reads its record is Get-XmipDemoRun.ps1.

    Style: doc/governance/powershell-style.md
#>


function Start-XmipDemoSuite {
    <#
        .SYNOPSIS
            Starts the demo readiness check in a pwsh of its own, detached,
            and returns the run at once.

        .DESCRIPTION
            The check takes minutes — it builds a roll, the web host, the
            desktop app and the VS Code extension, and watches the desktop
            app for a minute — so it runs as the estate's Pester suite does
            (Start-XmipDetachedShell): its output in demo-<start time>.log
            under .local-work/demo and its record beside it. -Stress omitted
            is Realistic, the demo's own.

            Refused before anything starts: a switch Core.Demo does not take;
            no -Cluster, since a test spawns a cluster and never invents a
            name for one; a run of the check still running, since two would
            share one web address and one desktop app's folder and gui.toml;
            and a cluster that rolls or builds already, since the check
            proves the roll it builds from this tree and never follows one
            (Get-XmipClusterRunning).

            A new run clears the records and logs of the runs that ended,
            and first stops what a run that ended without a verdict — its
            pwsh killed, its stop part never run — left running, as its
            record names it (Stop-XmipDemoRun).

        .PARAMETER Caller
            Start-XmipTest itself, for ShouldProcess.

        .PARAMETER Bound
            What Start-XmipTest was called with.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.TestStatus')]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCmdlet] $Caller,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Bound
    )

    [string] $refused = Get-XmipSuiteSwitchRefusal -Kind demo -Bound $Bound

    if ($refused -ne '') {
        Write-Error $refused
        return
    }

    [string] $cluster = [string] $Bound['Cluster']

    if ([string]::IsNullOrWhiteSpace($cluster)) {
        Write-Error "REFUSED. $script:XmipDemoSuite rolls a cluster you name: -Cluster <name>."
        return
    }

    $layout = Get-XmipEssentialsLayout
    [string] $area = $layout.Demo
    [object[]] $runs = @(Get-XmipDemoRun -Path $area)
    [int[]] $running = @($runs | Where-Object { $_.State -eq 'running' } | ForEach-Object Id)

    if ($running.Count -gt 0) {
        Write-Error ("REFUSED. The $script:XmipDemoSuite run $($running -join ', ') is still " +
            'running, and two would share one web address and one desktop app''s folder and ' +
            "gui.toml. Stop-XmipTest -Id $($running -join ', ') stops it; Get-XmipTestStatus " +
            'says when it ends.')
        return
    }

    if (-not $Caller.ShouldProcess("the $script:XmipDemoSuite check over $cluster", 'Start')) {
        return
    }

    foreach ($left in @($runs | Where-Object { $_.Fault -ne '' })) {
        Stop-XmipDemoRun -Run $left
    }

    Remove-XmipRunFinished -Run $runs
    [int[]] $taken = @(Get-XmipClusterRunning -Path $layout.Area -Cluster $cluster)

    if ($taken.Count -gt 0) {
        Write-Error ("REFUSED. $cluster already rolls or builds as pid $($taken -join ', '), " +
            "and $script:XmipDemoSuite proves the roll it builds from this tree, never one it " +
            "did not start. Stop-XmipTest -Id $($taken -join ', ') stops it, or name another " +
            'cluster.')
        return
    }

    [string] $stress = $script:XmipDemoStress

    if ($Bound.ContainsKey('Stress')) {
        $stress = [string] $Bound['Stress']
    }

    New-Item -ItemType Directory -Path $area -Force | Out-Null
    [string] $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    [hashtable] $run = @{
        Record  = Join-Path -Path $area -ChildPath "demo-$stamp.toml"
        Cluster = $cluster
        Stress  = $stress
        Tester  = [string] $Bound['Tester']
        Hidden  = [bool] $Bound['Hidden']
        Log     = Join-Path -Path $area -ChildPath "demo-$stamp.log"
    }

    $process = Start-XmipDetachedShell -Script (New-XmipDemoCommand @run) -Log $run.Log
    Write-XmipDemoStart -Run $run -Process $process

    Write-Host ("Started $script:XmipDemoSuite over $cluster as pid $($process.Id), in its " +
        "own pwsh, detached. Log: $($run.Log). Get-XmipTestStatus says which part it is " +
        "on, Get-XmipTestResult -Suite $script:XmipDemoSuite what each part said, and " +
        "Stop-XmipTest -Id $($process.Id) stops it and what it started.")

    return Get-XmipDemoRun -Path $area | Where-Object { $_.Id -eq $process.Id }
}


function New-XmipDemoCommand {
    <#
        .SYNOPSIS
            The script a detached demo run executes in its own pwsh: import
            Xmip and run Test-XmipDemoReady, every stream into its log.

        .DESCRIPTION
            Every value is written into it as a single-quoted literal
            (ConvertTo-XmipLiteral), so no path or name is parsed as code.

        .PARAMETER Record
            The run record's path.

        .PARAMETER Cluster
            The cluster it rolls.

        .PARAMETER Stress
            The stress it starts its roll at.

        .PARAMETER Tester
            The tester, or empty.

        .PARAMETER Hidden
            Whether the run is declared hidden.

        .PARAMETER Log
            The run's log.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Record,

        [Parameter(Mandatory)]
        [string] $Cluster,

        [Parameter(Mandatory)]
        [string] $Stress,

        [Parameter()]
        [AllowEmptyString()]
        [string] $Tester = '',

        [Parameter()]
        [bool] $Hidden = $false,

        [Parameter(Mandatory)]
        [string] $Log
    )

    [string] $module = Join-Path -Path $PSScriptRoot -ChildPath 'Xmip.psd1'
    [string] $hide = if ($Hidden) { '$true' } else { '$false' }

    return @(
        '$ErrorActionPreference = ''Stop'''
        "Import-Module -Name $(ConvertTo-XmipLiteral -Text $module)"
        "`$run = @{ Record = $(ConvertTo-XmipLiteral -Text $Record)"
        "    Cluster = $(ConvertTo-XmipLiteral -Text $Cluster)"
        "    Stress = $(ConvertTo-XmipLiteral -Text $Stress)"
        "    Tester = $(ConvertTo-XmipLiteral -Text $Tester)"
        "    Hidden = $hide; Log = $(ConvertTo-XmipLiteral -Text $Log) }"
        '& (Get-Module -Name Xmip | Select-Object -First 1) {'
        '    param([hashtable] $Run)'
        '    Test-XmipDemoReady @Run'
        '} $run *>&1 | ForEach-Object { "$_" }'
    ) -join [Environment]::NewLine
}


function Write-XmipDemoStart {
    <#
        .SYNOPSIS
            Writes the record of a demo run just started — what, over which
            cluster, and the pid Stop-XmipTest ends — where the run has not
            written its own yet.

        .PARAMETER Run
            What the run was started with, as New-XmipDemoCommand takes it.

        .PARAMETER Process
            The run's pwsh.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Run,

        [Parameter(Mandatory)]
        [System.Diagnostics.Process] $Process
    )

    [hashtable] $began = @{
        Record  = $Run.Record
        Cluster = $Run.Cluster
        Stress  = $Run.Stress
        Tester  = $Run.Tester
        Hidden  = $Run.Hidden
        Log     = $Run.Log
        Id      = $Process.Id
        Started = $Process.StartTime
    }
    $state = New-XmipDemoState @began

    try {
        Write-XmipDemoRecord -Run $state -NoClobber
    }
    catch {
        if (-not (Test-Path -LiteralPath $Run.Record)) {
            throw
        }

        Write-Verbose "the run wrote $($Run.Record) before its start was recorded; its own stands"
    }
}
