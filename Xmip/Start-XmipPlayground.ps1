#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Start-XmipPlayground {
    <#
        .SYNOPSIS
            Starts one roll of the Xmip Playground, detached, with the stress,
            scenarios, fleet and limits you choose. Nothing starts unless you
            call this.

        .DESCRIPTION
            The Playground (ADR-0028) is the estate's integration test over
            time: a roll drives every scenario round after round and publishes
            a snapshot, a history and the recent activity as TOML files a
            monitor reads. This starts exactly one roll as a background
            process, hands it every switch through its own environment — your
            session's environment is untouched — and writes a run record beside
            the snapshot so Get-XmipPlayground can say what is running and
            Stop-XmipPlayground can end it, nodes first.

            The roll and node binaries are built first, a no-op when they are
            current, so a roll never runs yesterday's scenarios. The roll's own
            output goes
            to `roll-<start time>.log` and `.err` under -Path, one line per
            round; the run record `roll-<pid>.toml` beside them says which log
            is whose.

        .PARAMETER Stress
            How hard: Calm, Realistic, Harsh or Brutal. Realistic is the roll's
            own default. Harsh and Brutal spawn a fleet of node processes
            unless -Nodes says otherwise.

        .PARAMETER Scenario
            Which scenarios to drive: pingpong, furious, load, secretary,
            filing, claim, daily. Omit for all seven.

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

        .PARAMETER Online
            Let the nodes assume a route to the internet (ADR-0045). Off
            unless said.

        .PARAMETER LoadBytes
            The load scenario's payload: a number or a size like 512mb or 2gb.
            Omit for a megabyte.

        .PARAMETER Path
            Where the run writes: snapshot, history, activity, run record and
            the roll's own log. Defaults to `.local-work/playground` under the
            repository.

        .PARAMETER PassThru
            Return the Xmip.Playground object for the roll started.

        .EXAMPLE
            Start-XmipPlayground -Stress Harsh -Scenario pingpong, load -Rounds 20

        .EXAMPLE
            Start-XmipPlayground -Stress Brutal -Nodes 20 -Online -PassThru | Start-XmipWeb

        .EXAMPLE
            Start-XmipPlayground -Duration 00:15:00 -TimeFactor 9.5e-6 -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('Xmip.Playground')]
    param(
        [Parameter()]
        [ValidateSet('Calm', 'Realistic', 'Harsh', 'Brutal')]
        [string] $Stress = 'Realistic',

        [Parameter()]
        [ValidateSet('pingpong', 'furious', 'load', 'secretary', 'filing', 'claim', 'daily')]
        [string[]] $Scenario = @(),

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
        [switch] $Online,

        [Parameter()]
        [ValidatePattern('^\d+\s*(gb|g|mb|m|kb|k)?$')]
        [string] $LoadBytes,

        [Parameter()]
        [string] $Path,

        [Parameter()]
        [switch] $PassThru
    )

    $layout = Get-XmipPlaygroundLayout

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = $layout.Area
    }

    [hashtable] $choice = Get-XmipPlaygroundChoice -Bound $PSBoundParameters
    $choice.Stress = $Stress
    $choice.Scenario = $Scenario
    $choice.Online = $Online.IsPresent
    $choice.Snapshot = Join-Path -Path $Path -ChildPath 'playground-snapshot.toml'
    $choice.History = Join-Path -Path $Path -ChildPath 'playground-history.toml'
    $choice.Activity = Join-Path -Path $Path -ChildPath 'playground-activity.toml'
    [hashtable] $environment = New-XmipPlaygroundEnvironment @choice

    [string] $of = if ($Scenario.Count -gt 0) { " of $($Scenario -join ', ')" } else { '' }
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
        pid         = $process.Id
        started     = $process.StartTime.ToString('o')
        stress      = $Stress.ToLowerInvariant()
        scenarios   = @($Scenario | ForEach-Object { $_.ToLowerInvariant() })
        rounds      = $Rounds
        nodes       = if ($boundNodes) { $Nodes } else { -1 }
        online      = $Online.IsPresent
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
        return Get-XmipPlayground -Path $Path | Where-Object { $_.Id -eq $process.Id }
    }
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

    foreach ($name in 'Nodes', 'Duration', 'TimeFactor', 'LoadBytes') {
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
