#requires -Version 7.7.0

Set-StrictMode -Version Latest

# How long a fresh roll is given to publish its first round before the wait
# below gives up and says so. An Essentials round is minutes, not hours.
[timespan] $script:SnapshotWait = [timespan]::FromMinutes(10)


<#
    .SYNOPSIS
    Waits for a snapshot a rolling cluster has not published yet.

    .DESCRIPTION
    A roll publishes when a round ends, so the file a run names does not
    exist between `Start-XmipTest` and the end of its first round. The owner,
    2026-09-23, piping two fresh rolls into the monitor and being refused:
    *Fix it.*

    A path no run names is refused as it always was. A path a run names is
    waited for while that run is still there, and the wait is bounded: a
    round that takes longer than [`SNAPSHOT_WAIT`] is a round the operator
    should hear about rather than a console that hangs (ADR-0055).

    Whether the run is still there is asked of the run records
    (Get-XmipClusterRunning): a roll of the cluster, or its build. A row
    Get-XmipTestStatus keeps after its run ended — a demo run's verdict, a
    build that FAILED — is no roll to wait for (2026-11-10).

    .PARAMETER Path
    The snapshot to wait for, full path.

    .PARAMETER Since
    When the bound starts: now, or the roll's spawn where a caller knows it,
    so the bound is the one a fresh roll has for its first round.
#>
function Wait-XmipSnapshot {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter()]
        [datetime] $Since = (Get-Date)
    )

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return
    }

    [object] $rolling = Get-XmipTestStatus -IncludeHidden |
        Where-Object { $_.Snapshot -and ([IO.Path]::GetFullPath($_.Snapshot) -eq $Path) } |
        Select-Object -First 1

    if (-not $rolling) {
        throw "REFUSED. No snapshot at '$Path'. Get-XmipTestStatus names the one a roll publishes."
    }

    [string] $cluster = [string] $rolling.Cluster
    Write-Host "   waiting for $cluster to publish its first round..." -ForegroundColor DarkGray

    [datetime] $until = $Since.Add($script:SnapshotWait)
    [string] $area = (Get-XmipEssentialsLayout).Area

    while ((Get-Date) -lt $until) {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            return
        }

        # The run may end before it ever publishes — a roll refused at its
        # first round, a cluster stopped by hand. Then there is nothing to
        # wait for and saying so beats waiting out the bound.
        [int[]] $alive = @(Get-XmipClusterRunning -Path $area -Cluster $cluster)

        if ($alive.Count -eq 0) {
            throw "REFUSED. $cluster stopped without publishing '$Path'."
        }

        Start-Sleep -Seconds 2
    }

    [string] $waited = "$cluster published no snapshot within $($script:SnapshotWait)."

    throw "REFUSED. $waited Is its round longer than that?"
}
