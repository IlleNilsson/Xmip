#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    What holds a cluster: a roll of it, or its build while it builds.

.DESCRIPTION
    One answer to "does this cluster roll or build", for every command that
    asks: Start-XmipSystemTestRoll refusing a second roll of one cluster,
    the demo readiness check refusing a cluster already taken and stopping
    the roll it started, and Wait-XmipSnapshot deciding whether a snapshot is
    still coming. Read from the run records, never from Get-XmipTestStatus,
    whose rows include runs that have ended — a demo run's verdict, a build
    that FAILED — and which loads the operator module to list them. Apart
    from Start-XmipSystemTestRoll.ps1 since 2026-11-10, when the demo
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
            A record whose roll has ended is no roll that runs: it stays,
            for Get-XmipTestStatus to list the ended roll, until its
            cluster is started again.

        .PARAMETER Path
            The System Tests' area the records are in.

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

    Get-XmipSystemTestRolling -Path $Path -Cluster $Cluster
    Get-XmipSystemTestBuild -Path $Path |
        Where-Object { $_.State -eq 'building' -and "$($_.Cluster)" -eq $Cluster } |
        ForEach-Object { [int] $_.Id }
}


function Get-XmipSystemTestRolling {
    <#
        .SYNOPSIS
            The pids rolling as a cluster, from the run records in a
            directory whose roll still runs.
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

        if ($rolledAs -eq $Cluster -and (Test-XmipRollAlive -Recorded $recorded)) {
            $recorded.Id
        }
    }
}


function Test-XmipRollAlive {
    <#
        .SYNOPSIS
            Whether the roll a run record names still runs: its pid is a
            System Tests roll, started when the record says, and not another
            process later given the same id.

        .PARAMETER Recorded
            One record, from Get-XmipRollRecord.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Recorded
    )

    $process = Get-Process -Id $Recorded.Id -ErrorAction SilentlyContinue

    if ($null -eq $process -or
        (Get-XmipSystemTestImageKind -Name $process.ProcessName) -ne 'Roll' -or
        -not (Test-XmipSystemTestBinary -Process $process -Path (Get-XmipSystemTestLayout).Roll)) {
        return $false
    }

    [string] $started = [string](Get-TomlValue -Node $Recorded.Record -Name 'started' -Default '')

    if ($started -eq '') {
        return $true
    }

    [datetime] $said = [datetime]::Parse($started, [cultureinfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::RoundtripKind)

    # A roll another session started elevated may not show this one when it
    # began; its kind and binary already vouch for it.
    try {
        [datetime] $began = $process.StartTime
    }
    catch {
        return $true
    }

    return [math]::Abs(($began.ToUniversalTime() - $said.ToUniversalTime()).TotalSeconds) -lt 5
}


function Remove-XmipSystemTestStaleRecord {
    <#
        .SYNOPSIS
            Deletes the run records of a cluster's rolls that have ended, as
            that cluster is started again: until then Get-XmipTestStatus
            lists an ended roll from its record.

        .PARAMETER Path
            The System Tests' area the records are in.

        .PARAMETER Cluster
            The cluster being started.
    #>
    [CmdletBinding()]
    [OutputType([void])]
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

        if ($rolledAs -eq $Cluster -and -not (Test-XmipRollAlive -Recorded $recorded)) {
            Remove-Item -LiteralPath $recorded.File -Force
        }
    }
}
