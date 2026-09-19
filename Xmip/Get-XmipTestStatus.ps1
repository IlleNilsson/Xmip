#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Get-XmipTestStatus {
    <#
        .SYNOPSIS
            The Xmip test runs on this machine: one object per run, with its
            suite, what it was started with and how it stands.

        .DESCRIPTION
            A run of Core.Playground is a roll, and the suite it names is the
            qualified one it was started with, read back from the run record.
            Reads the run records Start-XmipTest wrote under -Path and
            keeps the ones whose process is alive and is the Playground's own
            roll binary — never a process that merely shares the name. A roll
            started by hand (`cargo run --bin xmip-playground-roll`) has no record and is
            listed with what a process alone can tell.

            Nothing here starts, stops or writes anything. Nothing running
            means no output.

        .PARAMETER Path
            Where the run records are. Defaults to the repository's
            .local-work/playground folder, where Start-XmipTest writes.

        .PARAMETER Cluster
            Only the runs whose cluster matches, wildcards allowed. Every run
            unless said. This selects among the runs there are; the cluster is
            named, not matched, where Start-XmipTest spawns one.

        .EXAMPLE
            Get-XmipTestStatus

        .EXAMPLE
            Get-XmipTestStatus -Cluster 'Z*' | Format-List
    #>
    [CmdletBinding()]
    [OutputType('Xmip.TestStatus')]
    param(
        [Parameter()]
        [string] $Path,

        [Parameter()]
        [SupportsWildcards()]
        [string] $Cluster = '*'
    )

    $ErrorActionPreference = 'Stop'
    $layout = Get-XmipPlaygroundLayout

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = $layout.Area
    }

    [System.Diagnostics.Process[]] $rolls = @(
        Get-Process -Name 'xmip-playground-roll' -ErrorAction SilentlyContinue |
            Where-Object { Test-XmipPlaygroundBinary -Process $_ -Path $layout.Roll }
    )

    if ($rolls.Count -eq 0) {
        return
    }

    [object[]] $nodes = @(Get-XmipTestNode)
    Import-Module PSToml -ErrorAction Stop

    foreach ($roll in $rolls) {
        [string] $recordPath = Join-Path -Path $Path -ChildPath "roll-$($roll.Id).toml"
        $record = $null

        if (Test-Path -LiteralPath $recordPath) {
            $record = Get-Content -LiteralPath $recordPath -Raw | ConvertFrom-Toml
        }

        [string] $rolledAs = Get-XmipDeclaredText -Declaration $record -Key 'cluster'

        if ($rolledAs -notlike $Cluster) {
            continue
        }

        [string] $snapshot = if ($null -ne $record) { $record.snapshot } else { '' }
        $worst = if (Test-Path -LiteralPath $snapshot) {
            Get-XmipTestResult -Path $snapshot -Worst
        }

        [object[]] $mine = @($nodes | Where-Object { $_.Parent -eq $roll.Id })
        [object[]] $online = @($mine | Where-Object { $_.Online })

        # The suite the run was started with, qualified, from the record that
        # carries it. A roll started by hand has no record and is the
        # Playground by the binary it is.
        [string] $named = Get-XmipDeclaredText -Declaration $record -Key 'suite'

        [PSCustomObject]@{
            PSTypeName  = 'Xmip.TestStatus'
            Suite       = if ($named -ne '') { $named } else { $script:XmipPlaygroundSuite }
            Cluster     = if ($rolledAs -ne '') { $rolledAs } else { $null }
            Id          = $roll.Id
            StartTime   = $roll.StartTime
            Stress      = if ($null -ne $record) { $record.stress } else { $null }
            Tests       = if ($null -ne $record) { @($record.tests) } else { @() }
            Rounds      = if ($null -ne $record) { [int] $record.rounds } else { 0 }
            Nodes       = @($mine | ForEach-Object { $_.Name } | Sort-Object)
            OnlineNodes = @($online | ForEach-Object { $_.Name } | Sort-Object)
            Worst       = if ($null -ne $worst) { $worst.State } else { $null }
            Snapshot    = $snapshot
            Path        = if ($null -ne $record) { $Path } else { $null }
            Log         = if ($null -ne $record) { $record.log } else { $null }
        }
    }
}
