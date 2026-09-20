#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Start-XmipOperationWeb {
    <#
        .SYNOPSIS
            Starts the Xmip web monitor, detached, over the surface you name.

        .DESCRIPTION
            The web GUI offers every role (ADR-0014, amended 2026-09-14). Over
            a snapshot a roll or a node published it shows the cluster, the
            drill-down and the history. This starts it as a background process and hands
            it the address and, when given, the snapshot to read — the surface
            is chosen on the command line, never guessed (ADR-0052 clause 3).
            Without -Snapshot the host reads what its own xmip.gui.toml says.

            Several snapshots are one host over several clusters (ADR-0052,
            amendment 2026-09-20): Get-XmipTestStatus piped here over two rolls
            starts one host that serves both, and the three views say which
            cluster they are on and move between them. Two of them publishing
            one cluster is REFUSED by the host, because a cluster rolls once.

            It launches the built executable when one is present and falls back
            to `dotnet run` from source otherwise. It binds to 127.0.0.1 by
            default rather than localhost, because a browser that cached HSTS for
            localhost from another app silently forces https and the plain-http
            server then looks dead. Get-XmipOperationWeb lists what is running and
            Stop-XmipOperationWeb ends it.

        .PARAMETER Snapshot
            The snapshot file or files to monitor, one per cluster. Bound from
            the pipeline, so a Start-XmipTest -PassThru object names one and
            two rolls on the pipeline name two.

        .PARAMETER Url
            Where to bind. Defaults to http://127.0.0.1:5087. Use
            http://0.0.0.0:5087 to reach it from another device on the network
            (the firewall must also allow the port).

        .PARAMETER FromSource
            Run `dotnet run` from the project rather than the built executable —
            for development, when the source is newer than the last build.

        .PARAMETER PassThru
            Return the Xmip.Web object for the host started.

        .EXAMPLE
            Start-XmipOperationWeb

        .EXAMPLE
            Start-XmipTest -Suite Core.Playground -Stress Harsh -PassThru |
                Start-XmipOperationWeb

        .EXAMPLE
            Get-XmipTestStatus | Start-XmipOperationWeb

        .EXAMPLE
            $snapshot = '.local-work/playground/C1-snapshot.toml'
            Start-XmipOperationWeb -Url http://0.0.0.0:5087 -Snapshot $snapshot
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('Xmip.Web')]
    param(
        # Checked where the caller is bound, not where the file is read
        # (ADR-0055): a host started over a path that is not there answers
        # and shows nothing, which is the failure this rule exists to stop.
        [Parameter(ValueFromPipelineByPropertyName)]
        [ValidateScript({
            if (Test-Path -LiteralPath $_ -PathType Leaf) {
                return $true
            }

            throw "REFUSED. No snapshot at '$_'. Get-XmipTestStatus names the one a roll publishes."
        })]
        [string[]] $Snapshot,

        [Parameter()]
        [ValidatePattern(
            '^https?://([A-Za-z0-9.-]+|\[[0-9A-Fa-f:]+\]|\*|\+):\d{1,5}/?$',
            ErrorMessage = "REFUSED. '{0}' is not an address to bind: http://<host>:<port>."
        )]
        [string] $Url = 'http://127.0.0.1:5087',

        [Parameter()]
        [switch] $FromSource,

        [Parameter()]
        [switch] $PassThru
    )

    # One host over every cluster the pipeline named, not one host each: two
    # rolls used to start a first host and then a refusal, because the second
    # found 5087 held (the owner's console, 2026-09-20). So the pipeline is
    # gathered here and the host is started once, in end.
    begin {
        $ErrorActionPreference = 'Stop'
        $following = [System.Collections.Generic.List[string]]::new()
    }

    process {
        foreach ($named in $Snapshot) {
            if ([string]::IsNullOrWhiteSpace($named)) {
                continue
            }

            [string] $full = [System.IO.Path]::GetFullPath($named)

            # One file is one publication however many objects named it.
            if (-not $following.Contains($full)) {
                $following.Add($full)
            }
        }
    }

    end {
        $ErrorActionPreference = 'Stop'
        $layout = Get-XmipPlaygroundLayout
        [string] $source = 'module/operation/gui/src/Xmip.Gui.Web'
        [string] $project = Join-Path -Path $layout.Root -ChildPath $source
        [string[]] $arguments = @("--Kestrel:Endpoints:Http:Url=$Url")

        if ($following.Count -gt 0) {
            $arguments += '--Xmip:Surface=snapshot'
            $arguments += Get-XmipOperationWebSnapshotArgument -Snapshot $following

            # A web host over a Playground roll's file is a test's, and says so
            # in its declaration (ADR-0053); over anything else it is runtime.
            [string] $area = [System.IO.Path]::GetFullPath($layout.Area)
            $under = [System.StringComparison]::OrdinalIgnoreCase
            [bool] $rolls = @(
                $following | Where-Object { $_.StartsWith($area, $under) }
            ).Count -gt 0

            if ($rolls) {
                $arguments += '--Xmip:Purpose=test'
            }
        }

        # Asked to follow what the pipeline names, and it named nothing: no roll
        # is running. An empty host would answer and show nothing (the owner's
        # console, 2026-09-19).
        if ($following.Count -eq 0 -and $PSCmdlet.MyInvocation.ExpectingInput) {
            Write-Error ('REFUSED. The pipeline named no run to follow: nothing is rolling. ' +
                'Start-XmipTest first.')
            return
        }

        # The surface is stated, never guessed (ADR-0052 clause 3), so a roll is
        # not followed unasked. But a host that will not show the roll beside it
        # says so, and says how (the owner's console, twice, 2026-09-19).
        if ($following.Count -eq 0) {
            [string] $rolling = (Get-XmipTestStatus |
                    Where-Object -Property Suite -EQ -Value $script:XmipPlaygroundSuite |
                    ForEach-Object -MemberName Cluster) -join ', '

            if ($rolling) {
                Write-Warning ("No -Snapshot: this host reads its own xmip.gui.toml and will " +
                    "not show the roll $rolling. To follow it: " +
                    'Get-XmipTestStatus | Start-XmipOperationWeb')
            }
        }

        [string] $over = if ($following.Count -gt 0) {
            " over $($following -join ', ')"
        }
        else {
            ''
        }

        if (-not $PSCmdlet.ShouldProcess("the Xmip web monitor at $Url", "Start$over")) {
            return
        }

        # A second host on a held address dies at once and says nothing, and the
        # first keeps answering with whatever it was started over (the owner's
        # console, 2026-09-19). Refuse, and say who holds it.
        if (Test-XmipOperationWebAnswering -Url $Url) {
            [string] $held = (Get-XmipOperationWeb | ForEach-Object -MemberName Id) -join ', '
            [string] $who = 'another process holds it'

            if ($held) {
                $who = "xmip-gui-web pid $held runs"
            }

            Write-Error "REFUSED. $Url already answers: $who. Stop-XmipOperationWeb ends ours."
            return
        }

        if (-not $FromSource -and (Test-Path -LiteralPath $layout.Web)) {
            $launch = @{
                FilePath         = $layout.Web
                ArgumentList     = $arguments
                WorkingDirectory = Split-Path -Parent $layout.Web
                WindowStyle      = 'Hidden'
                PassThru         = $true
            }
        }
        else {
            if (-not (Test-Path -LiteralPath $project)) {
                Write-Error "No web project at $project."
                return
            }

            $launch = @{
                FilePath     = 'dotnet'
                ArgumentList = @('run', '--project', $project, '--no-launch-profile') + $arguments
                PassThru     = $true
            }
        }

        $process = Start-Process @launch
        Write-Verbose "web monitor starting at $Url as pid $($process.Id)"

        if ($PassThru) {
            return ConvertTo-XmipOperationWeb -Process $process
        }
    }
}

function Get-XmipOperationWebSnapshotArgument {
    <#
        .SYNOPSIS
            How a web host is told which snapshots to read: one key for one,
            an indexed key each for several. Pure.

        .DESCRIPTION
            Microsoft.Extensions.Configuration reads --Xmip:Snapshot:0 and
            --Xmip:Snapshot:1 as the list Xmip.Surface's SurfaceChoice asks
            for; one snapshot keeps the plain key it has always had, so every
            reader of a host's command line still reads it (ADR-0052,
            amendment 2026-09-20).

        .PARAMETER Snapshot
            The full paths, in the order the host should hold them.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string[]] $Snapshot
    )

    if ($Snapshot.Count -eq 1) {
        return @("--Xmip:Snapshot=$($Snapshot[0])")
    }

    return @(0..($Snapshot.Count - 1) | ForEach-Object { "--Xmip:Snapshot:$_=$($Snapshot[$_])" })
}

function Test-XmipOperationWebAnswering {
    <#
        .SYNOPSIS
            Whether something already listens where a web host would.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string] $Url
    )

    [uri] $address = $Url
    [string] $reach = $address.Host

    if ($reach -in '0.0.0.0', '+', '*') {
        $reach = '127.0.0.1'
    }

    $client = [System.Net.Sockets.TcpClient]::new()

    try {
        $client.Connect($reach, $address.Port)
        return $true
    }
    catch [System.Net.Sockets.SocketException] {
        return $false
    }
    finally {
        $client.Dispose()
    }
}
