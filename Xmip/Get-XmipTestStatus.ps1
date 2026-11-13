#requires -Version 7.7.0

Set-StrictMode -Version Latest

function Get-XmipTestStatus {
    <#
        .SYNOPSIS
            The Xmip test runs on this machine: one object per run, with its
            suite, what it was started with and how it stands.

        .DESCRIPTION
            A run of the Essentials is a roll, and the suite it names is the
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
            Reads the run records Start-XmipTest wrote under -Path and
            keeps the ones whose process is alive and is the Essentials' own
            roll binary — never a process that merely shares the name. A roll
            started by hand (`cargo run --bin xmip-essentials-roll`) has no record and is
            listed with what a process alone can tell.

            Nothing here starts, stops or writes anything. Nothing running
            and nothing recorded means no output.

        .PARAMETER Path
            Where the rolls' run records are. Defaults to the repository's
            .local-work/essentials folder, where Start-XmipTest writes. The
            estate's records are always read from .local-work/estate.

        .PARAMETER Cluster
            Only the runs whose cluster matches, wildcards allowed. Every run
            unless said. This selects among the runs there are; the cluster is
            named, not matched, where Start-XmipTest spawns one. An estate run
            rolls as no cluster, so naming one leaves it out.

        .PARAMETER IncludeHidden
            Lists the runs that declared themselves hidden too — an
            assistant's test runs, started with Start-XmipTest -Hidden — which
            are left out unless this is given, so Get-XmipTestStatus |
            Start-XmipOperationWeb never follows one unasked (ADR-0028,
            amendment 2026-09-30). A run is hidden by what it declared, never
            by its cluster's name; Hidden says which.

        .EXAMPLE
            Get-XmipTestStatus

        .EXAMPLE
            Get-XmipTestStatus -Cluster 'C*' | Format-List

        .EXAMPLE
            Get-XmipTestStatus | Where-Object -Property Suite -EQ -Value Core.Estate

        .EXAMPLE
            Get-XmipTestStatus -Cluster CL2 -IncludeHidden
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
        [switch] $IncludeHidden
    )

    $ErrorActionPreference = 'Stop'
    $layout = Get-XmipEssentialsLayout

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = $layout.Area
    }

    # The estate's Pester runs, running or finished, from their own records.
    # None rolls as a cluster, so a -Cluster that names one leaves them out.
    Get-XmipEstateRun -Path $layout.Estate | Where-Object { "$($_.Cluster)" -like $Cluster }

    [System.Diagnostics.Process[]] $rolls = @(
        Get-XmipEssentialsProcess -Name 'xmip-essentials-*' -Path $layout.Roll -Kind Roll
    )
    [object[]] $builds = @(
        Get-XmipEssentialsBuild -Path $Path | Where-Object { "$($_.Cluster)" -like $Cluster }
    )
    [object[]] $demos = @(
        Get-XmipDemoRun -Path $layout.Demo | Where-Object { "$($_.Cluster)" -like $Cluster }
    )

    if ($rolls.Count -eq 0 -and $builds.Count -eq 0 -and $demos.Count -eq 0) {
        return
    }

    Import-XmipOperatorModule
    $rules = [Xmip.Surface.RuntimeLibrary]::Rules

    # A demo run, running or finished, and a roll still building, or whose
    # build FAILED, until its nodes start: shown and hidden by the one rule,
    # as a roll is.
    $demos | Where-Object { $rules.Shown([bool] $_.Hidden, [bool] $IncludeHidden) }
    $builds | Where-Object { $rules.Shown([bool] $_.Hidden, [bool] $IncludeHidden) }

    if ($rolls.Count -eq 0) {
        return
    }

    [object[]] $nodes = @(Get-XmipTestNode)
    [object[]] $suites = @(Get-XmipTestSuite)

    foreach ($roll in $rolls) {
        $recorded = Get-XmipRollRecord -Path $Path -Id $roll.Id
        $record = if ($null -ne $recorded) { $recorded.Record } else { $null }

        [string] $rolledAs = [string](Get-TomlValue -Node $record -Name 'cluster' -Default '')

        if ($rolledAs -notlike $Cluster) {
            continue
        }

        # Whether a run is shown is the one rule, observe::run::shown, over
        # what the run declared (ADR-0028, amendment 2026-09-30).
        [bool] $hidden = [bool](Get-TomlValue -Node $record -Name 'hidden' -Default $false)

        if (-not $rules.Shown($hidden, [bool] $IncludeHidden)) {
            continue
        }

        [string] $snapshot = [string](Get-TomlValue -Node $record -Name 'snapshot' -Default '')
        $worst = if (Test-Path -LiteralPath $snapshot) {
            Get-XmipTestResult -Path $snapshot -Worst
        }

        $whose = [PSCustomObject]@{ Id = $roll.Id; Cluster = $rolledAs }
        [object[]] $mine = @(
            $nodes | Where-Object { Test-XmipTestNodeOfRoll -Node $_ -Roll $whose }
        )
        [object[]] $online = @($mine | Where-Object { $_.Online })

        # The suite the run was started with, from the record that carries it,
        # said the one way whatever spelling started it: a record written
        # earlier may say Essentials and this says Core.Essentials
        # (ADR-0059, amendment 2026-09-20). A roll started by hand has no
        # record and is the Essentials by the binary it is.
        [string] $named = [string](Get-TomlValue -Node $record -Name 'suite' -Default '')
        $ran = if ($named -ne '') {
            Get-XmipNamedTestSuite -Name $named -Known $suites | Select-Object -First 1
        }

        if ($null -ne $ran) {
            $named = $ran.Name
        }

        # What the run says it runs and reads, its snapshot's [run]: what the
        # start record asked for is said only until the snapshot is there,
        # and an unnamed run asks for nothing (ADR-0028, amendment 2026-11-11).
        $run = Get-XmipTestRun -Snapshot $snapshot
        [string[]] $asked = @(Get-TomlValue -Node $record -Name 'tests' -Default @())

        [hashtable] $row = @{
            Suite    = if ($named -ne '') { $named } else { $script:XmipEssentialsSuite }
            Kind     = 'roll'
            State    = 'running'
            Id       = $roll.Id
            Property = @{
                Cluster     = if ($rolledAs -ne '') { $rolledAs } else { $null }
                StartTime   = $roll.StartTime
                Stress      = Get-TomlValue -Node $record -Name 'stress'
                Tests       = if ($null -ne $run -and $run.Tests.Count -gt 0) {
                    @($run.Tests)
                } else {
                    $asked
                }
                Rounds      = [int](Get-TomlValue -Node $record -Name 'rounds' -Default 0)
                Nodes       = @($mine | ForEach-Object { $_.Name } | Sort-Object)
                OnlineNodes = @($online | ForEach-Object { $_.Name } | Sort-Object)
                RealNodes   = if ($null -ne $run) { @($run.RealNodes) } else { @() }
                Worst       = if ($null -ne $worst) { $worst.State } else { $null }
                Tally       = 'running'
                Snapshot    = $snapshot
                Path        = if ($null -ne $recorded) { $Path } else { $null }
                Record      = if ($null -ne $recorded) { $recorded.File } else { $null }
                Log         = Get-TomlValue -Node $record -Name 'log'
                Hidden      = $hidden
            }
        }

        New-XmipTestStatus @row
    }
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
