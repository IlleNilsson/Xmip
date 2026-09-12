#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Start-XmipTestNode {
    <#
        .SYNOPSIS
            Starts emulated Xmip nodes by hand — the ones you name, at the
            stress you say, online or not — without a roll.

        .DESCRIPTION
            Each node is one process of the Playground's node binary (ADR-0028
            clause 2), running the claim and daily scenarios over a directory
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

        .PARAMETER OnlineNodes
            Which of the named nodes may assume a route to the internet
            (ADR-0045), by name. None unless said; each node publishes the
            word in its own health.

        .PARAMETER Rounds
            Rounds before a node exits on its own. 0, the default, runs until
            stopped.

        .PARAMETER Interval
            The pause between a node's rounds. A quarter of a second unless
            given.

        .PARAMETER Path
            Where the nodes publish and log. Defaults to
            `.local-work/playground/node` under the repository.

        .PARAMETER Shared
            The directory the nodes contend over. Defaults to `shared` under
            -Path.

        .PARAMETER PassThru
            Return one Xmip.TestNode object per node started.

        .EXAMPLE
            Start-XmipTestNode -Nodes alpha, beta, gamma -OnlineNodes alpha, beta

        .EXAMPLE
            Start-XmipTestNode -Nodes edge-1, edge-2 -Stress Harsh -Rounds 100 -PassThru
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
        [string[]] $OnlineNodes = @(),

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
    $layout = Get-XmipPlaygroundLayout

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Join-Path -Path $layout.Area -ChildPath 'node'
    }

    if ([string]::IsNullOrWhiteSpace($Shared)) {
        $Shared = Join-Path -Path $Path -ChildPath 'shared'
    }

    Assert-XmipNodeName -Nodes $Nodes -OnlineNodes $OnlineNodes

    [string[]] $running = @(Get-XmipTestNode | ForEach-Object { $_.Name })
    [string[]] $taken = @($Nodes | Where-Object { $_ -in $running })

    if ($taken.Count -gt 0) {
        Write-Error "Already running: $($taken -join ', '). Get-XmipTestNode shows them."
        return
    }

    [string] $online = if ($OnlineNodes.Count -gt 0) { " ($($OnlineNodes -join ', ') online)" }
    [string] $what = "Start $($Stress.ToLowerInvariant()) node(s) $($Nodes -join ', ')$online"

    if (-not $PSCmdlet.ShouldProcess("emulated nodes in $Path", $what)) {
        return
    }

    [string] $binary = Invoke-XmipPlaygroundBuild -Binary node
    New-Item -ItemType Directory -Path $Path, $Shared -Force | Out-Null
    Remove-Item -LiteralPath (Join-Path -Path $Shared -ChildPath 'stop') -Force -ErrorAction Ignore

    foreach ($nodeName in $Nodes) {
        [bool] $isOnline = $nodeName -in $OnlineNodes

        $launch = @{
            FilePath               = $binary
            WorkingDirectory       = $Path
            WindowStyle            = 'Hidden'
            PassThru               = $true
            RedirectStandardOutput = Join-Path -Path $Path -ChildPath "$nodeName.log"
            RedirectStandardError  = Join-Path -Path $Path -ChildPath "$nodeName.err"
            ArgumentList           = @(
                '--name', $nodeName
                '--shared', $Shared
                '--stress', $Stress.ToLowerInvariant()
                '--rounds', "$Rounds"
                '--snapshot', (Join-Path -Path $Path -ChildPath "$nodeName.toml")
                '--interval-ms', "$([int] $Interval.TotalMilliseconds)"
                '--online', $(if ($isOnline) { 'true' } else { 'false' })
            )
        }

        $process = Start-Process @launch
        Write-Verbose "started node $nodeName as pid $($process.Id)"

        if ($PassThru) {
            ConvertTo-XmipTestNode -Process $process
        }
    }
}
