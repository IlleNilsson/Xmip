#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Stop-XmipTest {
    <#
        .SYNOPSIS
            Stops Xmip test runs: the nodes of each one first, then its
            cluster, then the run, then its run record. Every run on the
            machine when none is named.

        .DESCRIPTION
            A roll spawns a cluster process and the cluster spawns the nodes
            (the owner, 2026-09-19), and a process ended by a signal does not
            get to stop what it spawned. So this does what the tree would have
            done: asks every node beneath the roll to leave through the
            cluster's stop file, waits five seconds, ends what stayed, then
            ends the roll's cluster, then the roll. Nothing is orphaned —
            Get-Process xmip-* is empty afterwards, and the per-instance
            images the tree ran under are taken away with it (ADR-0053,
            amendment 2026-09-20). Takes Xmip.TestStatus objects from
            Get-XmipTestStatus on the pipeline, or -Id, or nothing for all.

        .PARAMETER Test
            The runs to stop, from Get-XmipTestStatus.

        .PARAMETER Id
            The process ids of the runs to stop.

        .PARAMETER Cluster
            The runs to stop by the cluster each rolls as, wildcards allowed:
            -Cluster Z* stops every roll whose cluster begins with Z. A
            pattern no roll matches is REFUSED, naming the clusters rolling,
            so nothing is stopped by accident and nothing silently is not.

        .EXAMPLE
            Stop-XmipTest

        .EXAMPLE
            Stop-XmipTest -Cluster 'Z*'

        .EXAMPLE
            Get-XmipTestStatus | Where-Object -Property Stress -EQ -Value brutal |
                Stop-XmipTest -WhatIf
    #>
    [CmdletBinding(
        SupportsShouldProcess,
        ConfirmImpact = 'Medium',
        DefaultParameterSetName = 'All')]
    [OutputType([void])]
    param(
        [Parameter(ParameterSetName = 'Object', ValueFromPipeline)]
        [PSTypeName('Xmip.TestStatus')]
        [PSObject[]] $Test,

        [Parameter(ParameterSetName = 'Id', Mandatory)]
        [int[]] $Id,

        [Parameter(ParameterSetName = 'Cluster', Mandatory)]
        [SupportsWildcards()]
        [string] $Cluster
    )

    begin {
        $ErrorActionPreference = 'Stop'
        [System.Collections.Generic.List[int]] $targets = @()
    }

    process {
        foreach ($item in @($Test)) {
            if ($null -ne $item) {
                $targets.Add([int] $item.Id)
            }
        }

        if ($PSBoundParameters.ContainsKey('Id')) {
            $targets.AddRange($Id)
        }
    }

    end {
        [object[]] $running = @(Get-XmipTestStatus)

        if ($PSCmdlet.ParameterSetName -eq 'All') {
            $targets.AddRange([int[]] @($running | ForEach-Object { $_.Id }))
        }

        if ($PSCmdlet.ParameterSetName -eq 'Cluster') {
            [object[]] $picked = @($running | Where-Object { "$($_.Cluster)" -like $Cluster })

            if ($picked.Count -eq 0) {
                [string] $rolling = @($running | ForEach-Object { $_.Cluster }) -join ', '
                [string] $there = if ($rolling) {
                    "Rolling now: $rolling."
                }
                else {
                    'Nothing is rolling.'
                }

                Write-Error "REFUSED. No roll matches $Cluster. $there"
                return
            }

            $targets.AddRange([int[]] @($picked | ForEach-Object { $_.Id }))
        }

        foreach ($number in @($targets | Sort-Object -Unique)) {
            $roll = $running | Where-Object { $_.Id -eq $number } | Select-Object -First 1

            if ($null -eq $roll) {
                Write-Error "No Playground roll has pid $number. Get-XmipTestStatus lists them."
                continue
            }

            if (-not $PSCmdlet.ShouldProcess("roll $number ($($roll.Stress))", 'Stop')) {
                continue
            }

            Get-XmipTestNode | Where-Object { $_.Parent -eq $number } |
                Stop-XmipTestNode -Confirm:$false
            Stop-XmipTestCluster -Parent $number

            try {
                Stop-Process -Id $number -Force -ErrorAction Stop
            }
            catch {
                [string] $why = $_.Exception.Message
                Write-Error "REFUSED: roll $number could not be stopped from this session: $why"
                continue
            }

            Wait-Process -Id $number -Timeout 5 -ErrorAction SilentlyContinue

            if (-not [string]::IsNullOrWhiteSpace($roll.Path)) {
                [string] $record = Join-Path -Path $roll.Path -ChildPath "roll-$number.toml"
                Remove-Item -LiteralPath $record -Force -ErrorAction SilentlyContinue
            }

            # The images the tree ran under go with it. The roll took what it
            # could on its way out and could not take its own, since a process
            # holds its image open; this takes the rest (ADR-0053, amendment
            # 2026-09-20).
            if (-not [string]::IsNullOrWhiteSpace($roll.Cluster)) {
                Remove-XmipPlaygroundImage -Cluster $roll.Cluster -Confirm:$false
            }

            Write-Verbose "stopped roll $number"
        }

        # The prompt followed one of the rolls and was told how many others
        # there were. Stopping one changes that count, and a segment saying
        # +1 over a cluster that has ended is the lie this record's amendment
        # of 2026-09-20 exists to stop. What is left is said again.
        Update-XmipPromptFollowing
    }
}

function Update-XmipPromptFollowing {
    <#
        .SYNOPSIS
            Tells the prompt, where this session has one, which roll to follow
            and how many are rolling beside it.

        .DESCRIPTION
            The prompt reads one publication (ADR-0052 clause 3; amendment
            2026-09-20). Where the one it followed has ended, it follows the
            first still rolling; where none is left it is left alone, since a
            snapshot nobody publishes reads as nothing and the segment goes
            quiet by itself. Nothing is loaded that is not loaded already.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    $prompt = 'Xmip.PowerShell.PromptMonitor' -as [type]

    if ($null -eq $prompt) {
        return
    }

    [string[]] $rolling = @(
        Get-XmipTestStatus | ForEach-Object -MemberName Snapshot |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    if ($rolling.Count -gt 0) {
        $prompt::Follow($rolling[0], $rolling)
    }
}

function Stop-XmipTestCluster {
    <#
        .SYNOPSIS
            Ends the cluster process a roll spawned, so no cluster outlives
            the roll that started it.

        .DESCRIPTION
            The nodes are asked to leave first, through the stop file they and
            their cluster share; by the time this runs the cluster has nothing
            left to supervise. A cluster started elevated shows no path to a
            session that is not, so its name vouches for it (ADR-0053).

        .PARAMETER Parent
            The process id of the roll whose cluster to end.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [int] $Parent
    )

    # Found through Get-XmipPlaygroundProcess, which judges by declaration
    # first and by name second, so a cluster whose image was rebuilt under it
    # is still found and still stopped (2026-09-19). Since 2026-09-20 its name
    # carries its cluster — xmip-playground-V1-cluster — so the kind is asked
    # for rather than the name.
    $layout = Get-XmipPlaygroundLayout

    [System.Diagnostics.Process[]] $clusters = @(
        Get-XmipPlaygroundProcess -Name 'xmip-playground-*' -Path $layout.Cluster -Kind Cluster |
            Where-Object {
                $owner = try { $_.Parent } catch { $null }
                $null -ne $owner -and $owner.Id -eq $Parent
            }
    )

    foreach ($cluster in $clusters) {
        Stop-Process -Id $cluster.Id -Force -ErrorAction SilentlyContinue
        Wait-Process -Id $cluster.Id -Timeout 5 -ErrorAction SilentlyContinue
        Write-Verbose "stopped cluster $($cluster.Id) of roll $Parent"
    }
}
