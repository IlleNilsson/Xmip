#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Start-XmipTest {
    <#
        .SYNOPSIS
            Starts one run of an Xmip test suite, detached, with the stress,
            scenarios, fleet and limits you choose. Nothing starts unless you
            call this.

        .DESCRIPTION
            Xmip provides its tests as suites, and -Suite says which one runs.
            Playground is a roll that runs detached until you stop it;
            Get-XmipTestStatus says what runs and Stop-XmipTest ends it.
            Estate is the Pester suite under test/, the estate's memory of every
            past defect: it runs here and now, says OK or FAILED, and returns
            the Pester result. A transport's or a contract's own suite joins as
            another value.

            The Playground (ADR-0028) is the estate's integration test over
            time: a roll drives every scenario round after round and publishes
            a snapshot, a history and the recent activity as TOML files a
            monitor reads. This starts exactly one roll as a background
            process, hands it every switch through its own environment — your
            session's environment is untouched — and writes a run record beside
            the snapshot so Get-XmipTestStatus can say what is running and
            Stop-XmipTest can end it, nodes first.

            The roll and node binaries are built first, a no-op when they are
            current, so a roll never runs yesterday's scenarios. The roll's own
            output goes
            to `roll-<start time>.log` and `.err` under -Path, one line per
            round; the run record `roll-<pid>.toml` beside them says which log
            is whose.

        .PARAMETER Suite
            Which of Xmip's test suites to run: Playground (the default) or
            Estate. The Playground parameters below belong to Playground alone.

        .PARAMETER Stress
            How hard: Calm, Realistic, Harsh or Brutal. Realistic is the roll's
            own default. Harsh and Brutal spawn a fleet of node processes
            unless -Nodes says otherwise.

        .PARAMETER Test
            Which tests of the suite to run; omit for the whole suite. The
            Playground's are RoundTrip, LowLatency, HeavyLoad, Retention,
            Filing, ExclusiveClaim and DailyBacklog. The estate's are its
            Pester files by name: Allocation, Decision, Rust.Style, XmipTest
            and the rest of test/. Tab completes either.

        .PARAMETER Rounds
            Run this many rounds and stop. Omit, or 0, to roll until stopped.

        .PARAMETER Duration
            A wall-clock ceiling; the roll stops when it is reached whatever
            the round count.

        .PARAMETER TimeFactor
            The factor on simulated time: 1 is real time, below 1 runs the
            simulated clock faster (the secretary ages on it).

        .PARAMETER Nodes
            How many node processes the fleet spawns. 0 means no fleet at any
            level. Omit for the level's own count: one, three, ten or forty,
            scaled to the machine's headroom.

        .PARAMETER OnlineNodes
            How many of the fleet's nodes, counting from the first, may assume
            a route to the internet (ADR-0045). None unless said.

        .PARAMETER LoadBytes
            The load scenario's payload: a number or a size like 512mb or 2gb.
            Omit for a megabyte.

        .PARAMETER Path
            Playground: where the run writes — snapshot, history, activity,
            run record and the roll's own log; defaults to
            `.local-work/playground` under the repository. Estate: the
            directory of Pester tests; defaults to test/ under the repository.

        .PARAMETER PassThru
            Return the Xmip.TestStatus object for the roll started.

        .EXAMPLE
            Start-XmipTest -Suite Playground -Test HeavyLoad, LowLatency -Stress Harsh -Rounds 20

        .EXAMPLE
            Start-XmipTest -Stress Brutal -Nodes 20 -OnlineNodes 5 -PassThru | Start-XmipWeb

        .EXAMPLE
            Start-XmipTest -Suite Estate -Test Rust.Style, XmipTest

        .EXAMPLE
            Start-XmipTest -Duration 00:15:00 -TimeFactor 9.5e-6 -WhatIf

        .EXAMPLE
            Start-XmipTest -Suite Estate

        .EXAMPLE
            (Start-XmipTest -Suite Estate).Failed | Format-Table ExpandedPath
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('Xmip.TestStatus', 'Pester.Run')]
    param(
        [Parameter()]
        [ValidateSet('Playground', 'Estate')]
        [string] $Suite = 'Playground',

        [Parameter()]
        [ValidateSet('Calm', 'Realistic', 'Harsh', 'Brutal')]
        [string] $Stress = 'Realistic',

        [Parameter()]
        [ArgumentCompleter({
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            [string[]] $names = if ($fakeBoundParameters['Suite'] -eq 'Estate') {
                [string] $root = Get-XmipRepositoryRoot -StartAt $PSScriptRoot
                Get-ChildItem -Path (Join-Path -Path $root -ChildPath 'test') -Filter '*.Test.ps1' |
                    ForEach-Object { $_.Name -replace '\.Test\.ps1$', '' }
            }
            else {
                'RoundTrip', 'LowLatency', 'HeavyLoad', 'Retention'
                'Filing', 'ExclusiveClaim', 'DailyBacklog'
            }

            $names | Where-Object { $_ -like "$wordToComplete*" }
        })]
        [string[]] $Test = @(),

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int] $Rounds = 0,

        [Parameter()]
        [timespan] $Duration,

        [Parameter()]
        [ValidateRange(0.0000001, 1000.0)]
        [double] $TimeFactor,

        [Parameter()]
        [ValidateRange(0, 200)]
        [int] $Nodes,

        [Parameter()]
        [ValidateRange(0, 200)]
        [int] $OnlineNodes,

        [Parameter()]
        [ValidatePattern('^\d+\s*(gb|g|mb|m|kb|k)?$')]
        [string] $LoadBytes,

        [Parameter()]
        [string] $Path,

        [Parameter()]
        [switch] $PassThru
    )

    if ($Suite -eq 'Estate') {
        [string[]] $foreign = @(
            $PSBoundParameters.Keys | Where-Object { $_ -in $script:XmipPlaygroundOnly }
        )

        if ($foreign.Count -gt 0) {
            Write-Error "-$($foreign -join ', -') belong to the Playground suite, not Estate."
            return
        }

        if (-not $PSCmdlet.ShouldProcess('the estate Pester suite', 'Start')) {
            return
        }

        return Start-XmipEstateSuite -Path $Path -Test $Test
    }

    if ($PSBoundParameters.ContainsKey('Nodes') -and $OnlineNodes -gt $Nodes) {
        Write-Error "-OnlineNodes $OnlineNodes exceeds -Nodes $Nodes."
        return
    }

    $layout = Get-XmipPlaygroundLayout

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = $layout.Area
    }

    [hashtable] $choice = Get-XmipPlaygroundChoice -Bound $PSBoundParameters
    $choice.Stress = $Stress
    $choice.Test = $Test
    $choice.Snapshot = Join-Path -Path $Path -ChildPath 'playground-snapshot.toml'
    $choice.History = Join-Path -Path $Path -ChildPath 'playground-history.toml'
    $choice.Activity = Join-Path -Path $Path -ChildPath 'playground-activity.toml'
    [hashtable] $environment = New-XmipPlaygroundEnvironment @choice

    [string] $of = if ($Test.Count -gt 0) { " of $($Test -join ', ')" } else { '' }
    [string] $for = if ($Rounds -gt 0) { " for $Rounds rounds" } else { ' until stopped' }
    [string] $what = "roll at $($Stress.ToLowerInvariant())$of$for"

    if (-not $PSCmdlet.ShouldProcess("the Xmip Playground in $Path", "Start a $what")) {
        return
    }

    [string] $roll = Invoke-XmipPlaygroundBuild -Binary roll
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    Remove-XmipPlaygroundStaleRecord -Path $Path

    $launch = @{
        FilePath         = $roll
        WorkingDirectory = $layout.Playground
        Environment      = $environment
        WindowStyle      = 'Hidden'
        PassThru         = $true
    }

    if ($Rounds -gt 0) {
        $launch.ArgumentList = @("$Rounds")
    }

    # The log is named for the start time, since Start-Process wants the file
    # named before the pid exists; the run record says which log is whose.
    [string] $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $launch.RedirectStandardOutput = Join-Path -Path $Path -ChildPath "roll-$stamp.log"
    $launch.RedirectStandardError = Join-Path -Path $Path -ChildPath "roll-$stamp.err"

    $process = Start-Process @launch

    [bool] $boundNodes = $PSBoundParameters.ContainsKey('Nodes')
    [bool] $boundDuration = $PSBoundParameters.ContainsKey('Duration')
    [bool] $boundFactor = $PSBoundParameters.ContainsKey('TimeFactor')

    $record = [ordered]@{
        suite       = $Suite.ToLowerInvariant()
        pid         = $process.Id
        started     = $process.StartTime.ToString('o')
        stress      = $Stress.ToLowerInvariant()
        tests       = @($Test)
        rounds      = $Rounds
        nodes       = if ($boundNodes) { $Nodes } else { -1 }
        online      = $OnlineNodes
        duration_s  = if ($boundDuration) { $Duration.TotalSeconds } else { 0 }
        time_factor = if ($boundFactor) { $TimeFactor } else { 1.0 }
        snapshot    = $environment.XMIP_PLAYGROUND_SNAPSHOT
        history     = $environment.XMIP_PLAYGROUND_HISTORY
        activity    = $environment.XMIP_PLAYGROUND_ACTIVITY
        log         = $launch.RedirectStandardOutput
    }

    Import-Module PSToml -ErrorAction Stop
    [string] $recordPath = Join-Path -Path $Path -ChildPath "roll-$($process.Id).toml"
    ConvertTo-Toml -InputObject $record | Set-Content -LiteralPath $recordPath -Encoding utf8
    Write-Verbose "started $what as pid $($process.Id); record at $recordPath"

    if ($PassThru) {
        return Get-XmipTestStatus -Path $Path | Where-Object { $_.Id -eq $process.Id }
    }
}

# The parameters that mean something only to the Playground suite.
[string[]] $script:XmipPlaygroundOnly = @(
    'Stress', 'Rounds', 'Duration', 'TimeFactor'
    'Nodes', 'OnlineNodes', 'LoadBytes', 'PassThru'
)

function Start-XmipEstateSuite {
    <#
        .SYNOPSIS
            Runs the estate's Pester suite under test/ and returns the result.

        .DESCRIPTION
            `Invoke-Pester -Path ./test` finds nothing since 2026-09-11: the
            estate's test files carry the singular suffix `.Test.ps1` and
            Pester looks for the plural. Get-XmipPesterConfiguration tells it,
            the same configuration the landing gate uses. The result is
            returned, not printed, so a caller reads `PassedCount`,
            `FailedCount` and `Failed` like any other object; the verdict is
            said in words, OK or FAILED, with each failing test named.

        .PARAMETER Path
            The directory of tests. Defaults to test/ under the repository.

        .PARAMETER Test
            The test files to run, by name without the suffix: Rust.Style runs
            test/Rust.Style.Test.ps1. Omit for every file.
    #>
    [CmdletBinding()]
    [OutputType('Pester.Run')]
    param(
        [Parameter()]
        [string] $Path,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]] $Test = @()
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Join-Path -Path (Get-XmipRepositoryRoot) -ChildPath 'test'
    }

    $configuration = Get-XmipPesterConfiguration -Path $Path

    if ($Test.Count -gt 0) {
        [string[]] $files = @(
            $Test | ForEach-Object { Join-Path -Path $Path -ChildPath "$_.Test.ps1" }
        )
        [string[]] $missing = @($files | Where-Object { -not (Test-Path -LiteralPath $_) })

        if ($missing.Count -gt 0) {
            throw "No such test: $($missing -join ', '). The tests are the *.Test.ps1 in $Path."
        }

        $configuration.Run.Path = $files
    }

    # Strict mode off here, alone in this module, which sets it at module
    # scope: Pester runs the tests in this scope's descendants, and they are
    # written and run everywhere else in the console's default mode.
    Set-StrictMode -Off
    $ErrorActionPreference = 'Stop'

    $result = Invoke-Pester -Configuration $configuration

    [string] $tally = "$($result.PassedCount) passed, $($result.FailedCount) failed"

    if ($result.FailedCount -eq 0) {
        Write-Host "OK $tally" -ForegroundColor Green
    }
    else {
        Write-Host "FAILED $tally" -ForegroundColor Red
    }

    foreach ($failure in $result.Failed) {
        Write-Host "   FAILED $($failure.ExpandedPath)" -ForegroundColor Red
    }

    return $result
}

function Get-XmipPlaygroundChoice {
    <#
        .SYNOPSIS
            The optional roll switches the caller actually gave, as the
            arguments New-XmipPlaygroundEnvironment takes for them.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Bound
    )

    [hashtable] $chosen = @{}

    foreach ($name in 'Nodes', 'OnlineNodes', 'Duration', 'TimeFactor', 'LoadBytes') {
        if ($Bound.ContainsKey($name)) {
            $chosen[$name] = $Bound[$name]
        }
    }

    return $chosen
}

function Remove-XmipPlaygroundStaleRecord {
    <#
        .SYNOPSIS
            Deletes run records whose roll is no longer running — a roll that
            reached its rounds or its ceiling leaves one behind.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $layout = Get-XmipPlaygroundLayout

    foreach ($file in @(Get-ChildItem -LiteralPath $Path -Filter 'roll-*.toml' -File)) {
        [string] $number = $file.BaseName -replace '^roll-', ''

        if ($number -notmatch '^\d+$') {
            continue
        }

        $process = Get-Process -Id ([int] $number) -ErrorAction SilentlyContinue
        [bool] $alive = $null -ne $process -and
            (Test-XmipPlaygroundBinary -Process $process -Path $layout.Roll)

        if (-not $alive) {
            Remove-Item -LiteralPath $file.FullName -Force
        }
    }
}

function Test-XmipPlaygroundBinary {
    <#
        .SYNOPSIS
            Whether a process runs the named binary — the Playground's own
            build, not any process that happens to share the name.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [System.Diagnostics.Process] $Process,

        [Parameter(Mandatory)]
        [string] $Path
    )

    [string] $actual = try { $Process.Path } catch { '' }

    if ([string]::IsNullOrWhiteSpace($actual)) {
        return $false
    }

    return [System.IO.Path]::GetFullPath($actual) -ieq [System.IO.Path]::GetFullPath($Path)
}
