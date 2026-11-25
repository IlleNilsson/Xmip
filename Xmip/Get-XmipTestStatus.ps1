#requires -Version 7.7.0

Set-StrictMode -Version Latest

function Get-XmipTestStatus {
    <#
        .SYNOPSIS
            The Xmip test runs on this machine: one object per run, with its
            suite, what it was started with and how it stands.

        .DESCRIPTION
            A run of the System Tests is a roll, and the suite it names is the
            one it was started with, read back from the run record. A run of
            Core.Estate is the estate's Pester suite in a pwsh of its own,
            listed from its record under .local-work/estate while it runs and
            after it ends: State says running, OK or FAILED in words, and
            Tally the counts. A new estate run clears the ended ones.

            A roll builds before it rolls, detached, and is listed while it
            does as kind build, State building, Tally saying how many crates
            cargo has compiled and the last of them; once its nodes start the
            roll is listed instead. A build that FAILED stays listed as
            FAILED, the reason in Fault and Tally — cargo's first error, or
            that its pwsh was stopped or died — until that cluster is started
            again.
            A run of Core.Demo, the demo readiness check, is listed from its
            record under .local-work/demo as an estate run is, with the
            cluster it rolls: State running, OK or FAILED in
            words, and Tally the part it is on or how many parts were OK;
            Get-XmipTestResult -Suite Core.Demo says each part and why.
            A roll is listed from the run record Start-XmipTest wrote under
            -Path: State running while its process is alive and is the System
            Tests' own roll binary — never a process that merely shares the
            name — and ended once it is gone, until its cluster is started
            again, Worst saying its last snapshot's worst result in words, or
            Fault that it ended before it published one. A roll stopped by
            Stop-XmipTest leaves no record. A roll started by hand (`cargo run
            --bin xmip-system-test-roll`) has no record and is listed with
            what a process alone can tell.

            A run of Core.Internal, the internal tests of named modules, is
            listed as an estate run is, kind internal.

            A roll, its build and a demo run say in RunsAs what Start-XmipTest
            ran them as: Process, as local processes, or VirtualMachine, on
            the virtual machines Deploy-XmipEnvironment deployed.

            Nothing here starts, stops or writes anything. Nothing running
            and nothing recorded means no output.

        .PARAMETER Path
            Where the rolls' run records are. Defaults to the repository's
            .local-work/system-test folder, where Start-XmipTest writes. The
            estate's records are always read from .local-work/estate.

        .PARAMETER Cluster
            Only the runs whose cluster matches, wildcards allowed. Every run
            unless said. This selects among the runs there are; the cluster is
            named, not matched, where Start-XmipTest spawns one. An estate run
            rolls as no cluster, so naming one leaves it out.

        .PARAMETER ComputerName
            The runs on that test computer instead, as its own
            Get-XmipTestStatus lists them in the copy of the estate
            Start-XmipTest -ComputerName sent there: running, OK or FAILED
            from its record and log there, ComputerName saying where, Path,
            Record and Log that computer's. Nothing where nothing was ever
            started there.

        .EXAMPLE
            Get-XmipTestStatus

        .EXAMPLE
            Get-XmipTestStatus -ComputerName build1

        .EXAMPLE
            Get-XmipTestStatus -Cluster 'C*' | Format-List

        .EXAMPLE
            Get-XmipTestStatus | Where-Object -Property Suite -EQ -Value Core.Estate
    #>
    [CmdletBinding()]
    [OutputType('Xmip.TestStatus')]
    param(
        [Parameter()]
        [string] $Path,

        [Parameter()]
        [SupportsWildcards()]
        [string] $Cluster = '*',

        [Parameter()]
        [ArgumentCompleter({
            & (Get-Module -Name Xmip | Select-Object -First 1) {
                Get-XmipTestComputerChoice -Word $args[0] } $args[2]
        })]
        [ValidateNotNullOrWhiteSpace()]
        [string] $ComputerName
    )

    $ErrorActionPreference = 'Stop'

    # There, that computer's own Get-XmipTestStatus answers.
    if ($PSBoundParameters.ContainsKey('ComputerName')) {
        [hashtable] $asked = @{ Cluster = $Cluster }
        $computer = Read-XmipTestComputer -Name $ComputerName

        return Invoke-XmipTestComputer -Computer $computer -Command Get-XmipTestStatus -Parameter (
            $asked) -AllowAbsent | ConvertFrom-XmipTestComputerStatus -ComputerName $ComputerName
    }

    $layout = Get-XmipSystemTestLayout

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = $layout.Area
    }

    # The estate's Pester runs, running or finished, from their own records.
    # None rolls as a cluster, so a -Cluster that names one leaves them out.
    Get-XmipEstateRun -Path $layout.Estate | Where-Object { "$($_.Cluster)" -like $Cluster }

    [System.Diagnostics.Process[]] $rolls = @(
        Get-XmipSystemTestProcess -Name 'xmip-system-test-*' -Path $layout.Roll -Kind Roll
    )
    [int[]] $live = @($rolls | ForEach-Object { $_.Id })

    # A roll that ended is listed from the record it left, until its cluster
    # is started again: a record is named for its roll's pid, so one whose
    # pid no live roll has is a roll that ended.
    [object[]] $ended = @(Get-XmipRollRecord -Path $Path | Where-Object { $_.Id -notin $live })
    [object[]] $builds = @(
        Get-XmipSystemTestBuild -Path $Path | Where-Object { "$($_.Cluster)" -like $Cluster }
    )
    [object[]] $demos = @(
        Get-XmipDemoRun -Path $layout.Demo | Where-Object { "$($_.Cluster)" -like $Cluster }
    )

    if ($rolls.Count + $ended.Count + $builds.Count + $demos.Count -eq 0) {
        return
    }

    # A demo run, running or finished, and a roll still building, or whose
    # build FAILED, until its nodes start.
    $demos
    $builds

    if ($rolls.Count + $ended.Count -eq 0) {
        return
    }

    Import-XmipOperatorModule

    [hashtable] $each = @{
        Path    = $Path
        Cluster = $Cluster
        Nodes   = @(Get-XmipTestNode)
        Suites  = @(Get-XmipTestSuite)
    }

    foreach ($roll in $rolls) {
        # A roll that exits while it is listed says no start time; it has
        # ended, and its record lists it so the next time it is asked.
        $began = try { $roll.StartTime } catch { $null }

        if ($null -eq $began) {
            continue
        }

        $recorded = Get-XmipRollRecord -Path $Path -Id $roll.Id
        ConvertTo-XmipRollStatus @each -Recorded $recorded -Id $roll.Id -StartTime $began
    }

    foreach ($recorded in $ended) {
        [datetime] $started = [datetime]::Parse(
            [string](Get-TomlValue -Node $recorded.Record -Name 'started' -Default '0001-01-01'),
            [cultureinfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::RoundtripKind)

        ConvertTo-XmipRollStatus @each -Recorded $recorded -Id $recorded.Id -StartTime (
            $started.ToLocalTime()) -Ended
    }
}

function ConvertTo-XmipRollStatus {
    <#
        .SYNOPSIS
            One roll as an Xmip.TestStatus: running, or ended and listed from
            the record it left, its worst result in words from the snapshot
            it published. Nothing where -Cluster leaves it out.

        .PARAMETER Path
            The roll area, where its record is.

        .PARAMETER Cluster
            Get-XmipTestStatus's -Cluster.

        .PARAMETER Nodes
            The live System Tests nodes, from Get-XmipTestNode.

        .PARAMETER Suites
            The known suites, from Get-XmipTestSuite.

        .PARAMETER Recorded
            Its run record, from Get-XmipRollRecord; null for a roll started
            by hand.

        .PARAMETER Id
            Its pid.

        .PARAMETER StartTime
            When it started.

        .PARAMETER Ended
            Its process is gone.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.TestStatus')]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Cluster,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Nodes,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Suites,

        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Recorded,

        [Parameter(Mandatory)]
        [int] $Id,

        [Parameter(Mandatory)]
        [datetime] $StartTime,

        [Parameter()]
        [switch] $Ended
    )

    $record = if ($null -ne $Recorded) { $Recorded.Record } else { $null }
    [string] $rolledAs = [string](Get-TomlValue -Node $record -Name 'cluster' -Default '')

    if ($rolledAs -notlike $Cluster) {
        return
    }

    # A snapshot older than the roll is an earlier roll's of its cluster, and
    # says nothing of this one.
    [string] $snapshot = [string](Get-TomlValue -Node $record -Name 'snapshot' -Default '')
    [bool] $published = $snapshot -ne '' -and (Test-Path -LiteralPath $snapshot -PathType Leaf) -and
        (Get-Item -LiteralPath $snapshot).LastWriteTimeUtc -ge $StartTime.ToUniversalTime()
    $worst = if ($published) { Get-XmipTestResult -Path $snapshot -Worst }

    [string[]] $alive = @()
    [string[]] $capable = @()

    if (-not $Ended) {
        $whose = [PSCustomObject]@{ Id = $Id; Cluster = $rolledAs }
        [object[]] $mine = @(
            $Nodes | Where-Object { Test-XmipTestNodeOfRoll -Node $_ -Roll $whose }
        )
        $alive = @($mine | ForEach-Object { $_.Name } | Sort-Object)
        $capable = @(
            $mine | Where-Object { $_.Capability.Count -gt 0 } |
                ForEach-Object { "$($_.Name)=$($_.Capability -join '+')" } | Sort-Object
        )
    }

    # The suite the run was started with, from the record that carries it,
    # said the one way whatever spelling started it: a record written
    # earlier may say System and this says Core.System
    # (ADR-0059, amendment 2026-09-20). A roll started by hand has no
    # record and is the System Tests by the binary it is.
    [string] $named = [string](Get-TomlValue -Node $record -Name 'suite' -Default '')
    $ran = if ($named -ne '') {
        Get-XmipNamedTestSuite -Name $named -Known $Suites | Select-Object -First 1
    }

    if ($null -ne $ran) {
        $named = $ran.Name
    }

    # What the run says it runs and reads, its snapshot's [run]: what the
    # start record asked for is said only until the snapshot is there,
    # and an unnamed run asks for nothing (ADR-0028, amendment 2026-11-11).
    $run = if ($published) { Get-XmipTestRun -Snapshot $snapshot }
    [string[]] $asked = @(Get-TomlValue -Node $record -Name 'tests' -Default @())
    [string] $state = if ($Ended) { 'ended' } else { 'running' }

    [hashtable] $row = @{
        Suite    = if ($named -ne '') { $named } else { $script:XmipSystemTestSuite }
        Kind     = 'roll'
        State    = $state
        Id       = $Id
        Property = @{
            RunsAs         = Get-TomlValue -Node $record -Name 'runs_as'
            Cluster        = if ($rolledAs -ne '') { $rolledAs } else { $null }
            StartTime      = $StartTime
            Stress         = Get-TomlValue -Node $record -Name 'stress'
            Tests          = if ($null -ne $run -and $run.Tests.Count -gt 0) {
                @($run.Tests)
            } else {
                $asked
            }
            Rounds         = [int](Get-TomlValue -Node $record -Name 'rounds' -Default 0)
            # An ended roll's nodes are the ones it was started with.
            Nodes          = if ($Ended) {
                @(Get-TomlValue -Node $record -Name 'nodes' -Default @())
            } else {
                $alive
            }
            NodeCapability = if ($Ended) { $null } else { $capable }
            RealNodes      = if ($null -ne $run) { @($run.RealNodes) } else { @() }
            Worst          = if ($null -ne $worst) { $worst.State } else { $null }
            Tally          = $state
            Fault          = if ($Ended -and -not $published) {
                'The roll ended before it published a snapshot; its log says why.'
            } else {
                $null
            }
            Snapshot       = $snapshot
            Path           = if ($null -ne $Recorded) { $Path } else { $null }
            Record         = if ($null -ne $Recorded) { $Recorded.File } else { $null }
            Log            = Get-TomlValue -Node $record -Name 'log'
        }
    }

    New-XmipTestStatus @row
}

function Get-XmipTestRun {
    <#
        .SYNOPSIS
            What a roll's snapshot says of its run, its [run], through the
            surfaces' one reading of a publication: the tests it runs —
            Carried alone where it reads every node (ADR-0028, amendment
            2026-11-11) — and the nodes it found real, each on a machine of
            its own or started as xmip-service, never simulated (ADR-0028,
            amendment 2026-10-21). Nothing where the snapshot is not there
            yet.

        .PARAMETER Snapshot
            The roll's snapshot.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.Surface.RunHeader')]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string] $Snapshot
    )

    if ([string]::IsNullOrWhiteSpace($Snapshot) -or -not (Test-Path -LiteralPath $Snapshot)) {
        return $null
    }

    return [Xmip.Surface.SnapshotOperator]::new($Snapshot).Run()
}
