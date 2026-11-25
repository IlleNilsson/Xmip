#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    Spawning a built System Tests roll and writing its run record.

.DESCRIPTION
    The second half of Start-XmipSystemTestRoll until 2026-10-13, when the build
    stopped holding the console: the detached build (Start-XmipSystemTestBuild)
    calls this once cargo has finished, in its own pwsh, with everything the
    console decided handed over as one value.

    Style: doc/governance/powershell-style.md
#>


function Start-XmipSystemTestRollProcess {
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
            What Start-XmipSystemTestRoll decided: Suite, RunsAs, Cluster,
            Stress, Test, Rounds, Nodes, NodeRole, Capability, Path,
            ClusterFile, Named, Seconds, TimeFactor, Choice and What.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Start
    )

    $layout = Get-XmipSystemTestLayout
    [string] $cluster = $Start.Cluster
    [string] $path = $Start.Path
    [string[]] $nodes = @($Start.Nodes)
    [string] $clusterFile = $Start.ClusterFile

    [int[]] $rolling = @(Get-XmipSystemTestRolling -Path $path -Cluster $cluster)

    if ($rolling.Count -gt 0) {
        throw ("REFUSED: cluster $cluster began rolling as pid $($rolling -join ', ') " +
            'while this one built.')
    }

    # The cluster's ended rolls were listed from their records until now.
    Remove-XmipSystemTestStaleRecord -Path $path -Cluster $cluster

    $publication = Get-XmipSystemTestPublication -Roll $layout.Roll -Cluster $cluster -Path $path

    # The nodes a run starts as xmip-service are issued under the System Tests'
    # one authority, kept in the area it publishes in; it is made here, by
    # the one maker that names it, before the roll asks for it (ADR-0028,
    # amendment 2026-10-27).
    if (-not [string]::IsNullOrWhiteSpace([string] $Start['Service'])) {
        [string] $authority = Join-Path -Path $path -ChildPath 'authority'
        $null = Initialize-XmipSystemTestAuthority -Folder $authority -Confirm:$false
    }

    $launch = New-XmipSystemTestRollLaunch -Start $Start

    # What it starts audits where the tooling does (ADR-0062).
    Initialize-XmipAudit
    Initialize-XmipRuntimeDirectory
    $process = Start-XmipHiddenProcess -Launch $launch

    # The nodes are the cluster file's either way: an operator who named none
    # can read what they got, node_names says which of the two it was, and
    # cluster_file where they came from.
    $record = [ordered]@{
        suite        = $Start.Suite
        runs_as      = [string] $Start['RunsAs']
        cluster      = $cluster
        pid          = $process.Id
        started      = $process.StartTime.ToString('o')
        stress       = ([string] $Start.Stress).ToLowerInvariant()
        tests        = @($Start.Test)
        rounds       = [int] $Start.Rounds
        nodes        = @($nodes)
        node_names   = if ([bool] $Start.Named) { 'named' } else { 'configured' }
        cluster_file = $clusterFile
        capabilities = @(Get-XmipNodeCapabilityEntry -Capability $Start['Capability'])
        duration_s   = [double] $Start.Seconds
        time_factor  = [double] $Start.TimeFactor
        snapshot     = $publication.Snapshot
        history      = $publication.History
        activity     = $publication.Activity
        log          = $launch.RedirectStandardOutput
    }

    [string] $recordPath = Get-XmipRollRecordPath -Path $path -Id $process.Id
    Write-XmipToml -Path $recordPath -Value $record
    [string] $declared = Get-XmipNodeRoleText -Nodes $nodes -NodeRole $Start.NodeRole
    [string] $roster = if ($declared -ne '') { "; roster $declared" } else { '' }
    Write-Verbose "started $($Start.What)$roster as pid $($process.Id); record at $recordPath"

    return $process.Id
}


function New-XmipSystemTestRollLaunch {
    <#
        .SYNOPSIS
            The Start-Process arguments a roll is spawned with: its image, its
            environment, its rounds and its log.

        .DESCRIPTION
            A process name is its image file's name, so the roll, its cluster
            and every node run images linked for this cluster: the operating
            system then says xmip-system-test-<cluster>-node-<node>, both names
            the operator's, rather than one more xmip-system-test-node (the
            owner, 2026-09-20; ADR-0053, amendment). The roll finds its
            cluster binary beside its own image and the cluster finds the node
            binary the same way, which is why all three are linked here.

            The log is named for the start time, since Start-Process wants the
            file named before the pid exists; the run record says which log is
            whose.

        .PARAMETER Start
            What Start-XmipSystemTestRoll decided.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Start
    )

    $layout = Get-XmipSystemTestLayout
    [hashtable] $choice = $Start.Choice
    $choice.Image = Get-XmipSystemTestImageArea -Cluster $Start.Cluster
    [string] $image = New-XmipSystemTestImage -Cluster $Start.Cluster

    if (-not [string]::IsNullOrWhiteSpace([string] $Start['Service'])) {
        $choice.Service = [string] $Start['Service']
    }

    [hashtable] $environment = New-XmipSystemTestEnvironment @choice
    [string] $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

    [hashtable] $launch = @{
        FilePath               = $image
        WorkingDirectory       = $layout.SystemTest
        Environment            = $environment
        PassThru               = $true
        RedirectStandardOutput = Join-Path -Path $Start.Path -ChildPath "roll-$stamp.log"
        RedirectStandardError  = Join-Path -Path $Start.Path -ChildPath "roll-$stamp.err"
    }

    if ([int] $Start.Rounds -gt 0) {
        $launch.ArgumentList = @("$($Start.Rounds)")
    }

    return $launch
}
