#requires -Version 7.7.0

Set-StrictMode -Version Latest

function Start-XmipTestNode {
    <#
        .SYNOPSIS
            Starts emulated Xmip nodes by hand — the ones you name, at the
            stress you say, with the Node capabilities you give them — without
            a roll.

        .DESCRIPTION
            Each node is one process of the System Tests' node binary (ADR-0028
            clause 2), running the ExclusiveClaim and DailyBacklog tests over a directory
            the whole set shares, so the contention is between real processes.
            Each publishes its own snapshot under -Path and writes its own
            log beside it. The processes are detached; Get-XmipTestNode
            lists them and Stop-XmipTestNode ends them.

            A stale stop file in the shared directory would end every node in
            its first round, so it is removed first.

        .PARAMETER Nodes
            The nodes to start, by name — one process each. A name already
            running is refused; Get-XmipTestNode shows what runs.

        .PARAMETER Stress
            The level each node runs at; it sets the claim's injected breach
            rate, none at Calm.

        .PARAMETER NodeCapability
            The Node capabilities each node declares, stated per node, as
            Start-XmipTest takes them: @{ RX1 = 'online' }, online among them
            where it may assume a route to the internet (ADR-0045; ADR-0056,
            amendment 2026-11-24). None unless said; each must be in -Nodes,
            and each node publishes them in its own health.

        .PARAMETER Rounds
            Rounds before a node exits on its own. 0, the default, runs until
            stopped.

        .PARAMETER Interval
            The pause between a node's rounds. A quarter of a second unless
            given.

        .PARAMETER Path
            Where the nodes publish and log. Defaults to
            `.local-work/system-test/node` under the repository.

        .PARAMETER Shared
            The directory the nodes contend over. Defaults to `shared` under
            -Path.

        .PARAMETER PassThru
            Return one Xmip.TestNode object per node started.

        .EXAMPLE
            Start-XmipTestNode -Nodes RX1, PX1, TX1 -NodeCapability @{ RX1 = 'online' }

            The names are the tester's and mean nothing to Xmip: a node
            started here declares no stage, whatever it is called.

        .EXAMPLE
            Start-XmipTestNode -Nodes TX1, TX2 -Stress Harsh -Rounds 100 -PassThru
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('Xmip.TestNode')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateCount(1, 200)]
        [string[]] $Nodes,

        [Parameter()]
        [ValidateSet('Calm', 'Realistic', 'Harsh', 'Brutal')]
        [string] $Stress = 'Calm',

        [Parameter()]
        [AllowNull()]
        [hashtable] $NodeCapability,

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int] $Rounds = 0,

        [Parameter()]
        [timespan] $Interval = [timespan]::FromMilliseconds(250),

        [Parameter()]
        [string] $Path,

        [Parameter()]
        [string] $Shared,

        [Parameter()]
        [switch] $PassThru
    )

    $ErrorActionPreference = 'Stop'
    $layout = Get-XmipSystemTestLayout

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Join-Path -Path $layout.Area -ChildPath 'node'
    }

    if ([string]::IsNullOrWhiteSpace($Shared)) {
        $Shared = Join-Path -Path $Path -ChildPath 'shared'
    }

    [string[]] $capable = @(if ($NodeCapability) { $NodeCapability.Keys })
    Assert-XmipNodeName -Nodes $Nodes -NodeCapability $capable

    [string[]] $running = @(Get-XmipTestNode | ForEach-Object { $_.Name })
    [string[]] $taken = @($Nodes | Where-Object { $_ -in $running })

    if ($taken.Count -gt 0) {
        Write-Error "Already running: $($taken -join ', '). Get-XmipTestNode shows them."
        return
    }

    [string[]] $entries = @(Get-XmipNodeCapabilityEntry -Capability (
            Join-XmipNodeCapability -Nodes $Nodes -NodeCapability $NodeCapability -Declared @{}
        ))
    [string] $declared = if ($entries.Count -gt 0) { " ($($entries -join ', '))" }
    [string] $what = "Start $($Stress.ToLowerInvariant()) node(s) $($Nodes -join ', ')$declared"

    if (-not $PSCmdlet.ShouldProcess("emulated nodes in $Path", $what)) {
        return
    }

    [string] $binary = Invoke-XmipSystemTestBuild -Binary node
    New-Item -ItemType Directory -Path $Path, $Shared -Force | Out-Null
    Remove-Item -LiteralPath (Join-Path -Path $Shared -ChildPath 'stop') -Force -ErrorAction Ignore

    foreach ($nodeName in $Nodes) {
        [bool] $stated = $null -ne $NodeCapability -and $NodeCapability.ContainsKey($nodeName)
        [string[]] $words = @(
            if ($stated) { ConvertTo-XmipNodeCapability -Capability $NodeCapability[$nodeName] }
        )

        $launch = @{
            FilePath               = $binary
            WorkingDirectory       = $Path
            PassThru               = $true
            RedirectStandardOutput = Join-Path -Path $Path -ChildPath "$nodeName.log"
            RedirectStandardError  = Join-Path -Path $Path -ChildPath "$nodeName.err"
            ArgumentList           = @(
                '--name', $nodeName
                '--shared', $Shared
                '--stress', $Stress.ToLowerInvariant()
                '--rounds', "$Rounds"
                '--snapshot', (Join-Path -Path $Path -ChildPath "$nodeName.xmip")
                '--interval-ms', "$([int] $Interval.TotalMilliseconds)"
            )
        }

        # A node declaring none is told nothing: it declares nothing, offline.
        if ($words.Count -gt 0) {
            $launch.ArgumentList += @('--capabilities', ($words -join '+'))
        }

        # What it starts audits where the tooling does (ADR-0062).
        Initialize-XmipAudit
        Initialize-XmipRuntimeDirectory
        $process = Start-XmipHiddenProcess -Launch $launch
        Write-Verbose "started node $nodeName as pid $($process.Id)"

        if ($PassThru) {
            ConvertTo-XmipTestNode -Process $process
        }
    }
}
