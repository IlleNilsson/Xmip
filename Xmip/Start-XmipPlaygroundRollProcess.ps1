#requires -PSEdition Core
#requires -Version 7.6.7

<#
.SYNOPSIS
    Spawning a built Playground roll and writing its run record.

.DESCRIPTION
    The second half of Start-XmipPlaygroundRoll until 2026-10-13, when the build
    stopped holding the console: the detached build (Start-XmipPlaygroundBuild)
    calls this once cargo has finished, in its own pwsh, with everything the
    console decided handed over as one value.

    Style: doc/governance/powershell-style.md
#>


function Start-XmipPlaygroundRollProcess {
    <#
        .SYNOPSIS
            Spawns the roll of a run whose binaries are built, and writes the
            run record Get-XmipTestStatus reads. Returns the roll's pid.

        .DESCRIPTION
            Refuses, by throwing, a cluster that started rolling while this
            one built: two rolls under one name publish to one file (ADR-0052,
            ruling 1 of 2026-09-14), and the console asked only before the
            build began.

        .PARAMETER Start
            What Start-XmipPlaygroundRoll decided: Suite, Cluster, Stress,
            Test, Rounds, Nodes, NodeRole, OnlineNodes, Path, ClusterFile,
            Named, Seconds, TimeFactor, Hidden, Choice and What.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Start
    )

    $layout = Get-XmipPlaygroundLayout
    [string] $cluster = $Start.Cluster
    [string] $path = $Start.Path
    [string[]] $nodes = @($Start.Nodes)
    [string] $clusterFile = $Start.ClusterFile
    [bool] $hidden = [bool] $Start.Hidden

    [int[]] $rolling = @(Get-XmipPlaygroundRolling -Path $path -Cluster $cluster)

    if ($rolling.Count -gt 0) {
        throw ("REFUSED: cluster $cluster began rolling as pid $($rolling -join ', ') " +
            'while this one built.')
    }

    $publication = Get-XmipPlaygroundPublication -Roll $layout.Roll -Cluster $cluster -Path $path
    $launch = New-XmipPlaygroundRollLaunch -Start $Start

    # What it starts audits where the tooling does (ADR-0062).
    Initialize-XmipAudit
    $process = Start-Process @launch

    # The nodes are the cluster file's either way: an operator who named none
    # can read what they got, node_names says which of the two it was, and
    # cluster_file where they came from.
    $record = [ordered]@{
        suite        = $Start.Suite
        cluster      = $cluster
        pid          = $process.Id
        started      = $process.StartTime.ToString('o')
        stress       = ([string] $Start.Stress).ToLowerInvariant()
        tests        = @($Start.Test)
        rounds       = [int] $Start.Rounds
        nodes        = @($nodes)
        node_names   = if ([bool] $Start.Named) { 'named' } else { 'configured' }
        cluster_file = $clusterFile
        online       = @($Start.OnlineNodes)
        duration_s   = [double] $Start.Seconds
        time_factor  = [double] $Start.TimeFactor
        snapshot     = $publication.Snapshot
        history      = $publication.History
        activity     = $publication.Activity
        log          = $launch.RedirectStandardOutput
        hidden       = $hidden
    }

    [string] $recordPath = Get-XmipRollRecordPath -Path $path -Id $process.Id
    Write-XmipToml -Path $recordPath -Value $record
    [string] $declared = Get-XmipNodeRoleText -Nodes $nodes -NodeRole $Start.NodeRole
    [string] $roster = if ($declared -ne '') { "; roster $declared" } else { '' }
    Write-Verbose "started $($Start.What)$roster as pid $($process.Id); record at $recordPath"

    return $process.Id
}


function New-XmipPlaygroundRollLaunch {
    <#
        .SYNOPSIS
            The Start-Process arguments a roll is spawned with: its image, its
            environment, its rounds and its log.

        .DESCRIPTION
            A process name is its image file's name, so the roll, its cluster
            and every node run images linked for this cluster: the operating
            system then says xmip-playground-<cluster>-node-<node>, both names
            the operator's, rather than one more xmip-playground-node (the
            owner, 2026-09-20; ADR-0053, amendment). The roll finds its
            cluster binary beside its own image and the cluster finds the node
            binary the same way, which is why all three are linked here.

            The log is named for the start time, since Start-Process wants the
            file named before the pid exists; the run record says which log is
            whose.

        .PARAMETER Start
            What Start-XmipPlaygroundRoll decided.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Start
    )

    $layout = Get-XmipPlaygroundLayout
    [hashtable] $choice = $Start.Choice
    $choice.Image = Get-XmipPlaygroundImageArea -Cluster $Start.Cluster
    [string] $image = New-XmipPlaygroundImage -Cluster $Start.Cluster

    [hashtable] $environment = New-XmipPlaygroundEnvironment @choice
    [string] $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

    [hashtable] $launch = @{
        FilePath               = $image
        WorkingDirectory       = $layout.Playground
        Environment            = $environment
        WindowStyle            = 'Hidden'
        PassThru               = $true
        RedirectStandardOutput = Join-Path -Path $Start.Path -ChildPath "roll-$stamp.log"
        RedirectStandardError  = Join-Path -Path $Start.Path -ChildPath "roll-$stamp.err"
    }

    if ([int] $Start.Rounds -gt 0) {
        $launch.ArgumentList = @("$($Start.Rounds)")
    }

    return $launch
}
