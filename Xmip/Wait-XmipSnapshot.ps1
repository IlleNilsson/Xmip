#requires -Version 7.6.5

Set-StrictMode -Version Latest

# How long a fresh roll is given to publish its first round before the wait
# below gives up and says so. A Playground round is minutes, not hours.
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

    .PARAMETER Path
    The snapshot to wait for, full path.
#>
function Wait-XmipSnapshot {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return
    }

    [object] $rolling = Get-XmipTestStatus |
        Where-Object { $_.Snapshot -and ([IO.Path]::GetFullPath($_.Snapshot) -eq $Path) } |
        Select-Object -First 1

    if (-not $rolling) {
        throw "REFUSED. No snapshot at '$Path'. Get-XmipTestStatus names the one a roll publishes."
    }

    [string] $cluster = [string] $rolling.Cluster
    Write-Host "   waiting for $cluster to publish its first round..." -ForegroundColor DarkGray

    [datetime] $until = (Get-Date).Add($script:SnapshotWait)

    while ((Get-Date) -lt $until) {
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            return
        }

        # The run may end before it ever publishes — a roll refused at its
        # first round, a cluster stopped by hand. Then there is nothing to
        # wait for and saying so beats waiting out the bound.
        [bool] $still = @(Get-XmipTestStatus | Where-Object Cluster -eq $cluster).Count -gt 0

        if (-not $still) {
            throw "REFUSED. $cluster stopped without publishing '$Path'."
        }

        Start-Sleep -Seconds 2
    }

    [string] $waited = "$cluster published no snapshot within $($script:SnapshotWait)."

    throw "REFUSED. $waited Is its round longer than that?"
}
