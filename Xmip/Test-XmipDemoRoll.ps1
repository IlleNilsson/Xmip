#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    The demo readiness check's first part: the Essentials cluster rolled from
    the tree under test, its snapshot published, and every node it declares
    running.

.DESCRIPTION
    The check starts the roll exactly as Start-XmipTest -Suite Core.Essentials
    starts any roll, at the -Stress it was given, and its stop part ends it.
    It never follows a roll it did not start: one built from another tree, or
    at another stress, proves nothing of this one, so a cluster that rolls or
    builds already is refused before the check starts (Start-XmipDemoSuite;
    ADR-0028, amendment 2026-11-10). The build is load: it is waited for until
    it ends by itself, its roll spawned or its build FAILED. From the roll's
    spawn its first snapshot is given the bound a fresh roll is given for its
    first round (Wait-XmipSnapshot), its nodes must then run, and how long
    the snapshot took from the spawn is said.

    Style: doc/governance/powershell-style.md
#>


function Test-XmipDemoRoll {
    <#
        .SYNOPSIS
            Starts the run's cluster and waits until its snapshot is
            published and its nodes run; returns what it found in words, or
            throws why not.

        .PARAMETER Run
            The run, from New-XmipDemoState: its cluster, stress and hidden,
            and where the snapshot and the roll it launched are kept.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Run
    )

    [string] $cluster = $Run['cluster']
    [hashtable] $start = @{
        Suite       = $script:XmipEssentialsSuite
        Cluster     = $cluster
        Stress      = $Run['stress']
        Hidden      = [bool] $Run['hidden']
        PassThru    = $true
        ErrorAction = 'Stop'
    }

    # Its build's pid as Start-XmipTest returns it, then its roll's once
    # spawned: the stop part ends these and never another roll of the name.
    $building = Start-XmipTest @start | Select-Object -Last 1
    $Run['launched']['roll'] = $cluster
    $Run['launched']['roll_ids'] = @($building | ForEach-Object { [int] $_.Id })
    Write-XmipDemoRecord -Run $Run

    $spawned = Wait-XmipDemoBuild -Cluster $cluster
    $Run['launched']['roll_ids'] = @(@($Run['launched']['roll_ids']) + [int] $spawned.Id)
    Write-XmipDemoRecord -Run $Run

    $rolled = Wait-XmipDemoRoll -Roll $spawned
    $Run['snapshot'] = [string] $rolled.Roll.Snapshot
    Write-XmipDemoRecord -Run $Run

    [string] $nodes = if ($rolled.Nodes.Count -gt 0) { $rolled.Nodes -join ', ' } else { 'none' }

    return ("started $cluster, which rolls at $($rolled.Roll.Stress) as pid " +
        "$($rolled.Roll.Id); it published $($Run['snapshot']) $($rolled.Seconds) s after " +
        "the roll was spawned, and its nodes ($nodes) run")
}


function Wait-XmipDemoBuild {
    <#
        .SYNOPSIS
            Waits while a cluster's build runs and returns its roll once
            spawned; throws, with the build's own reason, where it FAILED or
            the cluster stopped.

        .PARAMETER Cluster
            The cluster, by its name.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.TestStatus')]
    param(
        [Parameter(Mandatory)]
        [string] $Cluster
    )

    while ($true) {
        [object[]] $rows = @(
            Get-XmipTestStatus -Cluster $Cluster -IncludeHidden |
                Where-Object { "$($_.Cluster)" -eq $Cluster -and $_.Kind -in 'roll', 'build' }
        )
        $roll = $rows | Where-Object { $_.Kind -eq 'roll' } | Select-Object -First 1
        $build = $rows | Where-Object { $_.Kind -eq 'build' } | Select-Object -First 1

        if ($null -ne $roll) {
            return $roll
        }

        if ($null -eq $build) {
            throw "$Cluster stopped before its roll was spawned."
        }

        if ($build.State -ne 'building') {
            throw "the build of $Cluster $($build.State): $($build.Fault)"
        }

        Start-Sleep -Seconds 2
    }
}


function Wait-XmipDemoRoll {
    <#
        .SYNOPSIS
            Waits for a roll's first snapshot within the bound a fresh roll
            has from its spawn, and then finds every node its run record
            declares running.

        .DESCRIPTION
            Returns Roll, the roll as Get-XmipTestStatus lists it once it has
            published; Nodes, the nodes its record declares; and Seconds,
            from the roll's spawn to its snapshot. Throws, naming what is
            missing: no snapshot within the bound (Wait-XmipSnapshot says
            which way), or nodes not running once it published.

        .PARAMETER Roll
            The roll just spawned, from Wait-XmipDemoBuild.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [PSObject] $Roll
    )

    [string] $cluster = [string] $Roll.Cluster
    [datetime] $spawned = $Roll.StartTime
    [string] $snapshot = [string] $Roll.Snapshot

    if ($snapshot -eq '') {
        throw "$cluster rolls as pid $($Roll.Id), and its run record names no snapshot."
    }

    Wait-XmipSnapshot -Path ([System.IO.Path]::GetFullPath($snapshot)) -Since $spawned
    [double] $seconds = [math]::Round(((Get-Date) - $spawned).TotalSeconds, 1)

    $published = Get-XmipTestStatus -Cluster $cluster -IncludeHidden |
        Where-Object { $_.Kind -eq 'roll' -and $_.Id -eq $Roll.Id } |
        Select-Object -First 1

    if ($null -eq $published) {
        throw "$cluster published $snapshot and then stopped."
    }

    [string[]] $declared = @()

    if (-not [string]::IsNullOrWhiteSpace($published.Record)) {
        $recorded = Read-XmipToml -Path $published.Record
        $declared = @(Get-TomlValue -Node $recorded -Name 'nodes' -Default @())
    }

    [string[]] $missing = @($declared | Where-Object { $_ -notin @($published.Nodes) })

    if ($missing.Count -gt 0) {
        throw ("$cluster published $snapshot $seconds s after its spawn, and its nodes " +
            "$($missing -join ', ') are not running.")
    }

    return [pscustomobject]@{ Roll = $published; Nodes = $declared; Seconds = $seconds }
}
