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
            Get-Process xmip-* is empty afterwards. Takes Xmip.TestStatus
            objects from Get-XmipTestStatus on the pipeline, or -Id, or
            nothing for all.

        .PARAMETER Test
            The runs to stop, from Get-XmipTestStatus.

        .PARAMETER Id
            The process ids of the runs to stop.

        .EXAMPLE
            Stop-XmipTest

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
        [int[]] $Id
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

            Write-Verbose "stopped roll $number"
        }
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

    [System.Diagnostics.Process[]] $clusters = @(
        Get-Process -Name 'xmip-playground-cluster' -ErrorAction SilentlyContinue |
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
