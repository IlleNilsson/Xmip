#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    What holds a cluster: a roll of it, or its build while it builds.

.DESCRIPTION
    One answer to "does this cluster roll or build", for every command that
    asks: Start-XmipEssentialsRoll refusing a second roll of one cluster,
    the demo readiness check refusing a cluster already taken and stopping
    the roll it started, and Wait-XmipSnapshot deciding whether a snapshot is
    still coming. Read from the run records, never from Get-XmipTestStatus,
    whose rows include runs that have ended — a demo run's verdict, a build
    that FAILED — and which loads the operator module to list them. Apart
    from Start-XmipEssentialsRoll.ps1 since 2026-11-10, when the demo
    readiness check asked the same question a second way (ADR-0028,
    amendment 2026-11-10).

    Style: doc/governance/powershell-style.md
#>


function Get-XmipClusterRunning {
    <#
        .SYNOPSIS
            The pids rolling or building as a cluster in an area: each roll
            its run record names, and each build of it still building.
            Nothing when the cluster is free.

        .DESCRIPTION
            Records whose roll has ended are removed first, as every start
            removes them, so a record left is a roll that runs.

        .PARAMETER Path
            The Essentials' area the records are in.

        .PARAMETER Cluster
            The cluster, by its name.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Cluster
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return
    }

    Remove-XmipEssentialsStaleRecord -Path $Path
    Get-XmipEssentialsRolling -Path $Path -Cluster $Cluster
    Get-XmipEssentialsBuild -Path $Path |
        Where-Object { $_.State -eq 'building' -and "$($_.Cluster)" -eq $Cluster } |
        ForEach-Object { [int] $_.Id }
}


function Get-XmipEssentialsRolling {
    <#
        .SYNOPSIS
            The pids rolling as a cluster, from the run records in a directory.
            Stale records are removed before this is asked, so a record here is
            a roll that runs.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Cluster
    )

    foreach ($recorded in @(Get-XmipRollRecord -Path $Path)) {
        [string] $rolledAs = [string](
            Get-TomlValue -Node $recorded.Record -Name 'cluster' -Default ''
        )

        if ($rolledAs -eq $Cluster) {
            $recorded.Id
        }
    }
}


function Remove-XmipEssentialsStaleRecord {
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

    $layout = Get-XmipEssentialsLayout

    foreach ($recorded in @(Get-XmipRollRecord -Path $Path)) {
        $process = Get-Process -Id $recorded.Id -ErrorAction SilentlyContinue
        [bool] $alive = $null -ne $process -and
            (Get-XmipEssentialsImageKind -Name $process.ProcessName) -eq 'Roll' -and
            (Test-XmipEssentialsBinary -Process $process -Path $layout.Roll)

        if (-not $alive) {
            Remove-Item -LiteralPath $recorded.File -Force
        }
    }
}
