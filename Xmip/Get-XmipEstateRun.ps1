#requires -Version 7.6.5

Set-StrictMode -Version Latest

<#
.SYNOPSIS
    A run of the estate's Pester suite, as its run record says it, and what failed in it.

.DESCRIPTION
    Core.Estate runs as a roll does since 2026-09-25: in a process of its own,
    detached, recorded, observed and stopped from outside. It blocked the
    owner's console for ten minutes before that, and the rule is his: nothing
    starts itself; Start starts, Status observes, Stop stops (the owner,
    2026-09-12). Start-XmipEstateSuite starts it, Complete-XmipEstateRun is
    what the run writes when it ends, Stop-XmipEstateRun (in Stop-XmipTest.ps1)
    ends it early; what reads a run is here.

    A run is one TOML record under .local-work/estate (Get-XmipPlaygroundLayout's
    Estate), named for the time it started: estate-<yyyyMMdd-HHmmss-fff>.toml,
    beside the run's own log. Start writes what it started; the run itself
    writes the verdict over it when Pester returns — the counts, the duration
    and every failure's path and message. Read through Get-TomlValue, the one
    TOML reader the module keeps.

    Style: doc/governance/powershell-style.md
#>


function Get-XmipEstateRun {
    <#
        .SYNOPSIS
            Every recorded run of the estate's Pester suite, as the
            Xmip.TestStatus objects Get-XmipTestStatus lists beside rolls.

        .DESCRIPTION
            State is said in words: running while the run's own pwsh is alive
            and has not written a verdict, then OK or FAILED from the verdict
            it wrote. A run whose process is gone and which wrote nothing was
            stopped or died, and is FAILED with that said in Fault — never
            listed as running, and never as OK.

        .PARAMETER Path
            Where the records are. Defaults to .local-work/estate.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.TestStatus')]
    param(
        [Parameter()]
        [string] $Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = (Get-XmipPlaygroundLayout).Estate
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return
    }

    Import-Module PSToml -ErrorAction Stop

    foreach ($file in @(Get-ChildItem -LiteralPath $Path -Filter 'estate-*.toml' -File)) {
        $record = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Toml
        ConvertTo-XmipEstateRun -Record $record -File $file.FullName -Area $Path
    }
}


function ConvertTo-XmipEstateRun {
    <#
        .SYNOPSIS
            One estate run record as an Xmip.TestStatus.

        .PARAMETER Record
            The record, as ConvertFrom-Toml read it.

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

    [int] $id = [int](Get-TomlValue -Node $Record -Name 'pid' -Default 0)
    [datetime] $started = [datetime]::Parse(
        [string](Get-TomlValue -Node $Record -Name 'started' -Default '0001-01-01'),
        [cultureinfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::RoundtripKind)
    [string] $state = [string](Get-TomlValue -Node $Record -Name 'state' -Default '')
    [string] $fault = [string](Get-TomlValue -Node $Record -Name 'fault' -Default '')

    if ($state -eq '' -and (Test-XmipEstateAlive -Id $id -Started $started)) {
        $state = 'running'
    }
    elseif ($state -eq '') {
        $state = 'FAILED'
        $fault = 'The run ended without a verdict: it was stopped, or its pwsh died.'
    }

    [int] $passed = [int](Get-TomlValue -Node $Record -Name 'passed' -Default 0)
    [int] $failed = [int](Get-TomlValue -Node $Record -Name 'failed' -Default 0)
    [int] $skipped = [int](Get-TomlValue -Node $Record -Name 'skipped' -Default 0)
    [double] $seconds = [double](Get-TomlValue -Node $Record -Name 'duration_s' -Default 0)

    [string] $tally = if ($state -eq 'running') {
        'running'
    }
    else {
        "$passed passed, $failed failed, $skipped skipped in $([int] $seconds) s"
    }

    return [PSCustomObject]@{
        PSTypeName  = 'Xmip.TestStatus'
        Suite       = [string](Get-TomlValue -Node $Record -Name 'suite' -Default '')
        Kind        = 'pester'
        State       = $state
        Cluster     = $null
        Id          = $id
        StartTime   = $started.ToLocalTime()
        Stress      = $null
        Tests       = @(Get-TomlValue -Node $Record -Name 'tests' -Default @())
        Rounds      = $null
        Nodes       = $null
        OnlineNodes = $null
        Worst       = $null
        Tally       = $tally
        Passed      = $passed
        Failed      = $failed
        Skipped     = $skipped
        Fault       = $fault
        Snapshot    = $null
        Path        = $Area
        Record      = $File
        Log         = [string](Get-TomlValue -Node $Record -Name 'log' -Default '')
    }
}


function Test-XmipEstateAlive {
    <#
        .SYNOPSIS
            Whether the process a record names is still that run's pwsh, and
            not another process that was later given the same id.

        .PARAMETER Id
            The process id the record names.

        .PARAMETER Started
            When the record says the run started.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [int] $Id,

        [Parameter(Mandatory)]
        [datetime] $Started
    )

    if ($Id -le 0) {
        return $false
    }

    $process = Get-Process -Id $Id -ErrorAction SilentlyContinue

    if ($null -eq $process -or $process.ProcessName -notlike 'pwsh*') {
        return $false
    }

    [double] $apart = [math]::Abs(($process.StartTime.ToUniversalTime() -
            $Started.ToUniversalTime()).TotalSeconds)

    return $apart -lt 5
}


function Get-XmipEstateResult {
    <#
        .SYNOPSIS
            The failures of the latest estate run, one Xmip.TestResult each,
            for Get-XmipTestResult -Suite Core.Estate.

        .DESCRIPTION
            The latest run is the one started last. While it runs there is
            no verdict yet, and that is said rather than answered with an
            empty list that would read as nothing failing. A run that passed
            says so in words and returns nothing, since nothing failed. A run
            that ended with no failing test and still FAILED — Pester threw,
            or the run was stopped — returns one result saying why.

        .PARAMETER Path
            Where the records are. Defaults to .local-work/estate.

        .PARAMETER Test
            Only failures in these test files, by name without the suffix,
            wildcards allowed.

        .PARAMETER Worst
            Only the first failure.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.TestResult')]
    param(
        [Parameter()]
        [string] $Path,

        [Parameter()]
        [AllowNull()]
        [SupportsWildcards()]
        [string[]] $Test,

        [Parameter()]
        [switch] $Worst
    )

    $run = @(Get-XmipEstateRun -Path $Path | Sort-Object -Property StartTime) |
        Select-Object -Last 1

    if ($null -eq $run) {
        Write-Error ("No run of $script:XmipEstateSuite is recorded. " +
            "Start-XmipTest -Suite $script:XmipEstateSuite starts one.")
        return
    }

    if ($run.State -eq 'running') {
        Write-Warning ("The $($run.Suite) run $($run.Id) is still running and has no " +
            'verdict yet. Get-XmipTestStatus says when it has.')
        return
    }

    $record = Get-Content -LiteralPath $run.Record -Raw | ConvertFrom-Toml
    [object[]] $results = @(
        foreach ($failure in @(Get-TomlValue -Node $record -Name 'failures' -Default @())) {
            New-XmipEstateResult -Run $run -Failure $failure
        }
    )

    if ($results.Count -eq 0 -and $run.State -ne 'OK') {
        $results = @(New-XmipEstateResult -Run $run -Failure @{ message = $run.Fault })
    }

    if ($null -ne $Test) {
        $results = @(
            $results | Where-Object {
                [string] $file = $_.Test
                @($Test | Where-Object { $file -like $_ }).Count -gt 0
            }
        )
    }

    if ($results.Count -eq 0) {
        [string] $among = if ($null -ne $Test) { " among $($Test -join ', ')" } else { '' }
        Write-Host ("$($run.State). The $($run.Suite) run $($run.Id): $($run.Tally); " +
            "nothing failed$among.")
        return
    }

    if ($Worst) {
        return $results[0]
    }

    return $results
}


function New-XmipEstateResult {
    <#
        .SYNOPSIS
            One failure of an estate run as an Xmip.TestResult.

        .PARAMETER Run
            The run, from Get-XmipEstateRun.

        .PARAMETER Failure
            One of the record's failures.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.TestResult')]
    param(
        [Parameter(Mandatory)]
        [PSObject] $Run,

        [Parameter(Mandatory)]
        [object] $Failure
    )

    [string] $path = [string](Get-TomlValue -Node $Failure -Name 'path' -Default '')
    [string] $said = [string](Get-TomlValue -Node $Failure -Name 'message' -Default '')

    return [PSCustomObject]@{
        PSTypeName = 'Xmip.TestResult'
        Suite      = $Run.Suite
        Test       = [string](Get-TomlValue -Node $Failure -Name 'file' -Default '')
        Scenario   = ''
        Node       = ''
        Transport  = ''
        Contract   = ''
        State      = 'FAILED'
        Severity   = $null
        Evidence   = if ($path -ne '') { "$path — $said" } else { $said }
        Name       = $path
        Message    = $said
        Observed   = $Run.StartTime
        Scope      = $path
        Id         = $Run.Id
    }
}


