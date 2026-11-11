#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    A run of Core.Demo, the demo readiness check, as its record says it, and
    each of its parts in words.

.DESCRIPTION
    A run is one TOML record under .local-work/demo (Get-XmipEstateLayout's
    Demo), demo-<yyyyMMdd-HHmmss-fff>.toml, beside the run's own log. The
    console writes it once when it starts the run; the run writes it whole
    after every launch and every part (Test-XmipDemoReady.ps1). Read by the
    one reading of every detached run (Resolve-XmipDetachedRun): running
    while the run's pwsh is alive and has written no verdict, then OK or
    FAILED.

    Style: doc/governance/powershell-style.md
#>


function Get-XmipDemoRun {
    <#
        .SYNOPSIS
            Every recorded run of the demo readiness check, as the
            Xmip.TestStatus objects Get-XmipTestStatus lists beside rolls.

        .PARAMETER Path
            Where the records are. Defaults to .local-work/demo.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.TestStatus')]
    param(
        [Parameter()]
        [string] $Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = (Get-XmipEssentialsLayout).Demo
    }

    foreach ($read in @(Read-XmipRunRecord -Path $Path -Kind demo)) {
        ConvertTo-XmipDemoRun -Record $read.Record -File $read.File -Area $Path
    }
}


function ConvertTo-XmipDemoRun {
    <#
        .SYNOPSIS
            One demo run record as an Xmip.TestStatus: State running, OK or
            FAILED, and Tally the part it is on or how many were OK.

        .DESCRIPTION
            A run whose pwsh is gone and which wrote no verdict was stopped or
            died, and is FAILED with that said in Fault — never running, and
            never OK.

        .PARAMETER Record
            The record, as Read-XmipToml read it.

        .PARAMETER File
            The record's own path.

        .PARAMETER Area
            The directory it is in.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.TestStatus')]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Record,

        [Parameter(Mandatory)]
        [string] $File,

        [Parameter(Mandatory)]
        [string] $Area
    )

    $run = Resolve-XmipDetachedRun -Record $Record
    [string[]] $said = @(
        Get-TomlValue -Node $Record -Name 'parts' -Default @() |
            ForEach-Object { [string](Get-TomlValue -Node $_ -Name 'state' -Default '') }
    )
    [int] $passed = @($said | Where-Object { $_ -eq 'OK' }).Count
    [string] $fault = $run.Fault
    [string] $tally = if ($run.State -eq 'running') {
        "running: $([string](Get-TomlValue -Node $Record -Name 'doing' -Default ''))"
    }
    elseif ($fault -ne '') {
        $fault
    }
    else {
        "$passed of $($said.Count) parts OK"
    }

    [string] $stress = [string](Get-TomlValue -Node $Record -Name 'stress' -Default '')
    [hashtable] $row = @{
        Suite    = [string](Get-TomlValue -Node $Record -Name 'suite' -Default '')
        Kind     = 'demo'
        State    = $run.State
        Id       = $run.Id
        Property = @{
            Cluster   = [string](Get-TomlValue -Node $Record -Name 'cluster' -Default '')
            StartTime = $run.Started.ToLocalTime()
            Stress    = if ($stress -ne '') { $stress } else { $null }
            Tests     = @()
            Tally     = $tally
            Passed    = $passed
            Failed    = @($said | Where-Object { $_ -eq 'FAILED' }).Count
            Skipped   = @($said | Where-Object { $_ -eq 'SKIPPED' }).Count
            Fault     = $fault
            Path      = $Area
            Record    = $File
            Log       = [string](Get-TomlValue -Node $Record -Name 'log' -Default '')
            Hidden    = [bool](Get-TomlValue -Node $Record -Name 'hidden' -Default $false)
        }
    }

    return (New-XmipTestStatus @row)
}


function Get-XmipDemoResult {
    <#
        .SYNOPSIS
            Every part of the latest demo run, one Xmip.TestResult each, OK,
            FAILED or SKIPPED, the reason in Message, for Get-XmipTestResult
            -Suite Core.Demo.

        .DESCRIPTION
            The latest run is the one started last. While it runs, the parts
            written so far are returned and the part it is on is said. A run
            that ended without a verdict returns one result more saying so.

        .PARAMETER Path
            Where the records are. Defaults to .local-work/demo.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.TestResult')]
    param(
        [Parameter()]
        [string] $Path
    )

    $latest = @(Get-XmipDemoRun -Path $Path | Sort-Object -Property StartTime) |
        Select-Object -Last 1

    if ($null -eq $latest) {
        Write-Error ("No run of $script:XmipDemoSuite is recorded. Start-XmipTest -Suite " +
            "$script:XmipDemoSuite -Cluster <name> starts one.")
        return
    }

    if ($latest.State -eq 'running') {
        Write-Host "The $($latest.Suite) run $($latest.Id) is $($latest.Tally)."
    }

    $record = Read-XmipToml -Path $latest.Record

    foreach ($part in @(Get-TomlValue -Node $record -Name 'parts' -Default @())) {
        [hashtable] $made = @{
            Run    = $latest
            Name   = [string](Get-TomlValue -Node $part -Name 'name' -Default '')
            State  = [string](Get-TomlValue -Node $part -Name 'state' -Default '')
            Reason = [string](Get-TomlValue -Node $part -Name 'reason' -Default '')
        }
        New-XmipDemoResult @made
    }

    if ($latest.Fault -ne '') {
        New-XmipDemoResult -Run $latest -Name 'run' -State 'FAILED' -Reason $latest.Fault
    }
}


function New-XmipDemoResult {
    <#
        .SYNOPSIS
            One part of a demo run as an Xmip.TestResult, the shape
            Get-XmipTestResult returns for every suite.

        .PARAMETER Run
            The run, from Get-XmipDemoRun.

        .PARAMETER Name
            The part.

        .PARAMETER State
            OK, FAILED or SKIPPED.

        .PARAMETER Reason
            What the part found.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.TestResult')]
    param(
        [Parameter(Mandatory)]
        [PSObject] $Run,

        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $State,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Reason
    )

    [string] $words = Format-XmipDemoPart -Part (
        New-XmipDemoPart -Name $Name -State $State -Reason $Reason)

    return [PSCustomObject]@{
        PSTypeName = 'Xmip.TestResult'
        Suite      = $Run.Suite
        Test       = $Name
        Scenario   = ''
        Node       = ''
        Transport  = ''
        Contract   = ''
        State      = $State
        Severity   = $null
        Evidence   = $words
        Name       = $Name
        Message    = $Reason
        Observed   = $Run.StartTime
        Scope      = $Name
        Id         = $Run.Id
    }
}
