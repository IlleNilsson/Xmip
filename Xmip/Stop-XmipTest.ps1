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
            amendment 2026-09-20).

            Which runs: those -Suite, -Cluster and -Test pick together, as
            Start-XmipTest was told them; those on the pipeline from
            Get-XmipTestStatus; those with the process ids in -Id; or every
            run when nothing is named.

            A run of Core.Estate, the estate's Pester suite, is one pwsh of
            its own: stopping it ends that pwsh and whatever it started, and
            takes its record; its log is kept. One that has already ended is
            listed by Get-XmipTestStatus with its verdict and is never picked
            by a filter; named by -Id it is REFUSED, since nothing of it runs.

            A run is one process, so a test is stopped by stopping the run
            that drives it. A run that also drives a test not named is
            REFUSED rather than stopped, naming what else it runs, because
            stopping it would stop those too (ADR-0055 clause 5). The refusal
            comes before anything is stopped, so a command that is refused
            has done nothing (clause 2).

        .PARAMETER InputObject
            The runs to stop, from Get-XmipTestStatus.

        .PARAMETER Id
            The process ids of the runs to stop.

        .PARAMETER Cluster
            The runs to stop by the cluster each rolls as, wildcards allowed:
            -Cluster Z* stops every roll whose cluster begins with Z. A
            pattern no roll matches is REFUSED, naming the clusters rolling,
            so nothing is stopped by accident and nothing silently is not.

        .PARAMETER Test
            The runs to stop by the tests they drive, as Start-XmipTest -Test
            names them, wildcards allowed; with -Cluster, only on those
            clusters. A run started without -Test drives its whole suite and
            is matched by every test in it. A pattern no running test matches
            is REFUSED, naming what is running.

        .PARAMETER Suite
            The runs to stop by the suite each runs, as Start-XmipTest -Suite
            names it, wildcards allowed: -Suite Core.Estate stops the estate's
            Pester run. A pattern no running suite matches is REFUSED, naming
            what is running.

        .EXAMPLE
            Stop-XmipTest

        .EXAMPLE
            Stop-XmipTest -Suite Core.Estate

        .EXAMPLE
            Stop-XmipTest -Cluster C1 -Test RoundTrip

        .EXAMPLE
            Stop-XmipTest -Cluster 'Z*'

        .EXAMPLE
            Get-XmipTestStatus | Where-Object -Property Stress -EQ -Value brutal |
                Stop-XmipTest -WhatIf
    #>
    [CmdletBinding(
        SupportsShouldProcess,
        ConfirmImpact = 'Medium',
        DefaultParameterSetName = 'Filter')]
    [OutputType([void])]
    param(
        # The pipeline's object was -Test until 2026-09-21, which left
        # Stop-XmipTest -Test RoundTrip binding a test's name to a run's
        # status and failing, while Start-XmipTest -Test RoundTrip meant the
        # test. One word, one meaning on one noun: the object is
        # -InputObject, PowerShell's own name for it, and -Test is a test.
        [Parameter(ParameterSetName = 'Object', ValueFromPipeline)]
        [PSTypeName('Xmip.TestStatus')]
        [PSObject[]] $InputObject,

        [Parameter(ParameterSetName = 'Id', Mandatory)]
        [int[]] $Id,

        [Parameter(ParameterSetName = 'Filter')]
        [SupportsWildcards()]
        [ArgumentCompleter({
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            # The clusters rolling now, which are the only ones there are to
            # stop (ADR-0055 clause 4).
            Get-XmipTestStatus |
                ForEach-Object { "$($_.Cluster)" } |
                Where-Object { $_ -ne '' -and $_ -like "$wordToComplete*" } |
                Sort-Object -Unique
        })]
        [string] $Cluster,

        [Parameter(ParameterSetName = 'Filter')]
        [SupportsWildcards()]
        [ArgumentCompleter({
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            # The tests running now, on the clusters already named if any. A
            # completer runs in the caller's scope, so the whole-suite list is
            # asked of the module (see Start-XmipTest's -Suite completer).
            $module = Get-Module -Name Xmip | Select-Object -First 1

            if ($null -eq $module) {
                return
            }

            [string] $among = "$($fakeBoundParameters['Cluster'])"

            & $module {
                param($Among)

                Get-XmipTestStatus |
                    Where-Object { $Among -eq '' -or "$($_.Cluster)" -like $Among } |
                    ForEach-Object { Get-XmipTestOfRoll -Roll $_ }
            } $among |
                Where-Object { $_ -like "$wordToComplete*" } |
                Sort-Object -Unique
        })]
        [string[]] $Test = @(),

        [Parameter(ParameterSetName = 'Filter')]
        [SupportsWildcards()]
        [string] $Suite
    )

    begin {
        $ErrorActionPreference = 'Stop'
        [System.Collections.Generic.List[int]] $targets = @()
    }

    process {
        foreach ($item in @($InputObject)) {
            if ($null -ne $item) {
                $targets.Add([int] $item.Id)
            }
        }

        if ($PSBoundParameters.ContainsKey('Id')) {
            $targets.AddRange($Id)
        }
    }

    end {
        # An estate run that has ended is listed, and there is nothing of it
        # to stop: it is chosen only by its id, and then refused in words.
        [object[]] $listed = @(Get-XmipTestStatus)
        [object[]] $running = @($listed | Where-Object { $_.State -eq 'running' })

        if ($PSCmdlet.ParameterSetName -eq 'Filter') {
            [hashtable] $asked = @{
                Running = $running
                Cluster = $Cluster
                Test    = $Test
                Suite   = $Suite
            }

            [object[]] $picked = @(Select-XmipTestRoll @asked)
            $targets.AddRange([int[]] @($picked | ForEach-Object { $_.Id }))
        }

        foreach ($number in @($targets | Sort-Object -Unique)) {
            $roll = $listed | Where-Object { $_.Id -eq $number } | Select-Object -First 1

            if ($null -eq $roll) {
                Write-Error "No test run has pid $number. Get-XmipTestStatus lists them."
                continue
            }

            # The estate's Pester run is one pwsh and what it started; it has
            # no nodes and no cluster (Stop-XmipEstateRun).
            if ($roll.Kind -eq 'pester' -and $roll.State -ne 'running') {
                Write-Error ("REFUSED: the $($roll.Suite) run $number has ended " +
                    "($($roll.State)); there is nothing to stop.")
                continue
            }

            if ($roll.Kind -eq 'pester') {
                if ($PSCmdlet.ShouldProcess("the $($roll.Suite) run $number", 'Stop')) {
                    Stop-XmipEstateRun -Run $roll
                }

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


function Stop-XmipEstateRun {
    <#
        .SYNOPSIS
            Ends a running estate run: its pwsh and everything that pwsh
            started, then its record.

        .DESCRIPTION
            A test may start a process of its own — cargo, a node, a host —
            and ending only the run's pwsh would orphan it, so the whole
            tree is ended, as Stop-XmipTest ends a roll's tree. The log is
            kept, for what the run said before it was stopped.

        .PARAMETER Run
            The run, from Get-XmipEstateRun.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [PSObject] $Run
    )

    try {
        [System.Diagnostics.Process]::GetProcessById($Run.Id).Kill($true)
    }
    catch {
        [string] $why = $_.Exception.Message
        Write-Error "REFUSED: $($Run.Suite) run $($Run.Id) could not be stopped: $why"
        return
    }

    Wait-Process -Id $Run.Id -Timeout 5 -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $Run.Record -Force -ErrorAction SilentlyContinue
    Write-Verbose "stopped the $($Run.Suite) run $($Run.Id)"
}
