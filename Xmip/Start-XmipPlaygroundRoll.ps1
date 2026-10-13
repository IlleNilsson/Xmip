#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    Starting one Playground roll: its choices, what already rolls, and the roll itself.

.DESCRIPTION
    Apart from Start-XmipTest.ps1 since 2026-09-22, when that file was 944 lines
    against the 400 the estate allows a file and the owner asked for the estate to
    be consolidated. Start-XmipTest chooses and refuses; what each kind of suite
    then does is here.

    Style: doc/governance/powershell-style.md
#>


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

    # -Nodes and -NodeRole reach the roll as the run's cluster file
    # (Write-XmipTestCluster), never as variables of their own.
    [string[]] $optional = @(
        'OnlineNodes', 'Cluster', 'Duration', 'TimeFactor', 'LoadBytes', 'Hidden'
    )

    foreach ($name in $optional) {
        if ($Bound.ContainsKey($name)) {
            $chosen[$name] = $Bound[$name]
        }
    }

    return $chosen
}


function Get-XmipPlaygroundRolling {
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

    foreach ($recorded in @(Get-XmipRollRecord -Path $Path)) {
        $process = Get-Process -Id $recorded.Id -ErrorAction SilentlyContinue
        [bool] $alive = $null -ne $process -and
            (Get-XmipPlaygroundImageKind -Name $process.ProcessName) -eq 'Roll' -and
            (Test-XmipPlaygroundBinary -Process $process -Path $layout.Roll)

        if (-not $alive) {
            Remove-Item -LiteralPath $recorded.File -Force
        }
    }
}


# Which live processes are the Playground's is Get-XmipPlaygroundProcess.ps1:
# Test-XmipPlaygroundBinary moved there on 2026-09-19, with the finding that a
# rebuilt binary must not make a running roll disappear.


function Start-XmipPlaygroundRoll {
    <#
        .SYNOPSIS
            Starts one Playground roll for Start-XmipTest, detached: the build
            and the roll run in a pwsh of their own, and this returns at once.

        .DESCRIPTION
            The Playground's own work, once Start-XmipTest has chosen the
            suite and refused what it cannot run: lay the run out, refuse a
            cluster already rolling or building, write the run's cluster file,
            and hand the rest — the build, the roll's spawn and its run record
            — to Start-XmipPlaygroundBuild. Part of Start-XmipTest's body
            until 2026-09-22, when that one function was 610 lines against
            the 400 the estate allows a file.

            The build held the console until 2026-10-13, minutes on a first
            build. The owner, that day, of Start-XmipTest holding his console
            during the first build: the build runs detached too, and
            Get-XmipTestStatus says the run is building until its nodes start.

            It asks the caller, not itself, whether to go ahead: -Caller is
            Start-XmipTest's own $PSCmdlet, so -WhatIf and -Confirm given to
            Start-XmipTest decide here exactly as they did before the move.

        .PARAMETER Caller
            Start-XmipTest itself, for ShouldProcess.

        .PARAMETER Bound
            The parameters Start-XmipTest was given, for what was bound
            rather than defaulted.

        .PARAMETER Suite
            As Start-XmipTest takes it, already checked there.

        .PARAMETER Stress
            As Start-XmipTest takes it, already checked there.

        .PARAMETER Test
            As Start-XmipTest takes it, already checked there.

        .PARAMETER Rounds
            As Start-XmipTest takes it, already checked there.

        .PARAMETER Duration
            As Start-XmipTest takes it, already checked there.

        .PARAMETER TimeFactor
            As Start-XmipTest takes it, already checked there.

        .PARAMETER Nodes
            As Start-XmipTest takes it, already checked there.

        .PARAMETER NodeRole
            As Start-XmipTest takes it, already checked there.

        .PARAMETER OnlineNodes
            As Start-XmipTest takes it, already checked there.

        .PARAMETER Cluster
            As Start-XmipTest takes it, already checked there.

        .PARAMETER Path
            As Start-XmipTest takes it, already checked there.

        .PARAMETER PassThru
            As Start-XmipTest takes it, already checked there.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSCmdlet] $Caller,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary] $Bound,

        [Parameter(Mandatory = $false)]
        [string] $Suite,

        [Parameter(Mandatory = $false)]
        [string] $Stress,

        [Parameter(Mandatory = $false)]
        [string[]] $Test,

        [Parameter(Mandatory = $false)]
        [int] $Rounds,

        [Parameter(Mandatory = $false)]
        [timespan] $Duration,

        [Parameter(Mandatory = $false)]
        [double] $TimeFactor,

        [Parameter(Mandatory = $false)]
        [string[]] $Nodes,

        [Parameter(Mandatory = $false)]
        [hashtable] $NodeRole,

        [Parameter(Mandatory = $false)]
        [string[]] $OnlineNodes,

        [Parameter(Mandatory = $false)]
        [string] $Cluster,

        [Parameter(Mandatory = $false)]
        [string] $Path,

        [Parameter(Mandatory = $false)]
        [switch] $PassThru
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    $layout = Get-XmipPlaygroundLayout

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = $layout.Area
    }

    [hashtable] $choice = Get-XmipPlaygroundChoice -Bound $Bound
    $choice.Stress = $Stress
    $choice.Test = $Test
    $choice.Area = $Path

    [bool] $boundNodes = $Bound.ContainsKey('Nodes')
    [string] $of = if ($Test.Count -gt 0) { " of $($Test -join ', ')" } else { '' }
    [string] $for = if ($Rounds -gt 0) { " for $Rounds rounds" } else { ' until stopped' }
    [string] $with = if (-not $boundNodes) {
        ", the nodes of $(Get-XmipTestClusterPath)"
    }
    elseif ($Nodes.Count -eq 0) { ', no nodes' } else { ", nodes $($Nodes -join ', ')" }
    [string] $online = if ($OnlineNodes.Count -gt 0) { " ($($OnlineNodes -join ', ') online)" }
    [string] $what = "roll at $($Stress.ToLowerInvariant())$of$for$with$online as cluster $Cluster"

    if (-not $Caller.ShouldProcess("the Xmip Playground in $Path", "Start a $what")) {
        return
    }

    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    Remove-XmipPlaygroundStaleRecord -Path $Path
    Remove-XmipPlaygroundBuildEnded -Path $Path -Cluster $Cluster

    # A roll is a cluster, and two rolls are two clusters (ADR-0028; ADR-0052,
    # ruling 1 of 2026-09-14). Two under one name publish to one file and each
    # overwrites the other: on 2026-09-18 three rolled as CC1, the surfaces
    # saw 803, 2,259 and 11,499 leaves in turn, and the prompt went blank. A
    # cluster still building is about to roll, and is refused the same way.
    [int[]] $rolling = @(
        Get-XmipPlaygroundRolling -Path $Path -Cluster $Cluster
        Get-XmipPlaygroundBuild -Path $Path |
            Where-Object { $_.State -eq 'building' -and $_.Cluster -eq $Cluster } |
            ForEach-Object { $_.Id }
    )

    if ($rolling.Count -gt 0) {
        Write-Error ("REFUSED: cluster $Cluster is already rolling or building as pid " +
            "$($rolling -join ', '). Stop it with Stop-XmipTest -Id " +
            "$($rolling -join ', '), or name another cluster.")
        return
    }

    # The nodes are the cluster's xmip.toml (ADR-0056, amendment 2026-10-03):
    # named, the run's own file is written from -Cluster, -Nodes and -NodeRole;
    # omitted, the test cluster's is taken as it is. XMIP_TEST_CLUSTER names it
    # to the roll, and the run record says the nodes it declares.
    [string] $clusterFile = if ($boundNodes) {
        Write-XmipTestCluster -Cluster $Cluster -Nodes $Nodes -NodeRole $NodeRole -Path $Path
    }
    else {
        Get-XmipTestClusterPath
    }

    $configured = Read-XmipTestCluster -Path $clusterFile
    $choice.ClusterFile = $clusterFile

    if (-not $boundNodes) {
        $Nodes = $configured.Nodes
        $NodeRole = @{}
        $configured.Role.Keys | Where-Object { $configured.Role[$_] -ne '' } |
            ForEach-Object { $NodeRole[$_] = $configured.Role[$_] }

        # Asked as named nodes are, before anything spawns (ADR-0055).
        $asked = @{ Nodes = $Nodes; Test = $Test; NodeRole = $NodeRole }
        [string] $refused = Get-XmipNodeRoleRefusal @asked

        if ($refused -ne '') {
            Write-Error "$clusterFile`: $refused"
            return
        }

        [string] $said = Get-XmipNodeRoleWarning @asked

        if ($said -ne '') {
            Write-Warning "$clusterFile`: $said"
        }
    }

    [bool] $hidden = $Bound.ContainsKey('Hidden') -and [bool] $Bound['Hidden']
    [bool] $boundDuration = $Bound.ContainsKey('Duration')
    [bool] $boundFactor = $Bound.ContainsKey('TimeFactor')
    $choice.Hidden = $hidden

    # Everything the roll is spawned and recorded with, handed to the
    # detached build as one value (Start-XmipPlaygroundRollProcess).
    [hashtable] $start = @{
        Suite       = $Suite
        Cluster     = $Cluster
        Stress      = $Stress
        Test        = @($Test)
        Rounds      = $Rounds
        Nodes       = @($Nodes)
        NodeRole    = $NodeRole
        OnlineNodes = @($OnlineNodes)
        Path        = $Path
        ClusterFile = $clusterFile
        Named       = $boundNodes
        Seconds     = if ($boundDuration) { $Duration.TotalSeconds } else { 0 }
        TimeFactor  = if ($boundFactor) { $TimeFactor } else { 1.0 }
        Hidden      = $hidden
        Choice      = $choice
        What        = $what
    }

    # Where the roll will publish, asked of the roll binary already built, if
    # there is one, before the build can replace it; a first build has none
    # to ask, and an older one that cannot answer is not a reason to refuse:
    # the prompt is then not told until the next start.
    [string] $snapshot = ''

    if (Test-Path -LiteralPath $layout.Roll) {
        [hashtable] $where = @{ Roll = $layout.Roll; Cluster = $Cluster; Path = $Path }

        try {
            $snapshot = (Get-XmipPlaygroundPublication @where).Snapshot
        }
        catch {
            Write-Verbose "the roll built before could not say where it publishes: $_"
        }
    }

    $start.Snapshot = $snapshot
    [int] $id = Start-XmipPlaygroundBuild -Start $start

    # The prompt, where this session shows one, follows the roll just started:
    # the shipped document names one cluster, and on 2026-09-18 a roll of a
    # cluster it did not name left the prompt frozen on another cluster's
    # file. Said here because this
    # command knows the file; nothing is loaded that is not loaded already.
    #
    # And it is told what else is rolling. The prompt reads one publication,
    # so with two clusters it followed whichever started last and looked like
    # the whole estate; now the segment says how many it is not showing
    # (ADR-0052, amendment 2026-09-20). Named by this session, never counted
    # from files on disk — a surface is stated (clause 3).
    $prompt = 'Xmip.PowerShell.PromptMonitor' -as [type]

    # A hidden run is not followed: the prompt is the owner's (ADR-0028,
    # amendment 2026-09-30).
    if ($null -ne $prompt -and -not $hidden -and $snapshot -ne '') {
        [string[]] $beside = @(
            Get-XmipTestStatus -Path $Path | ForEach-Object -MemberName Snapshot |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
        $prompt::Follow($snapshot, $beside)
    }

    Write-Host ("Started cluster $Cluster as pid $id, detached: it builds, then rolls. " +
        "Get-XmipTestStatus says building until its nodes start, and the reason if " +
        "the build FAILED; Stop-XmipTest -Id $id stops it.")

    if ($PassThru) {
        return Get-XmipTestStatus -Path $Path -IncludeHidden | Where-Object { $_.Id -eq $id }
    }
}
