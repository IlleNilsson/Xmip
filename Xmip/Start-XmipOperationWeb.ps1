#requires -Version 7.7.0

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
            What the host writes to its console is kept in
            .local-work/web/web-<start time>.log and .err, and every start,
            refusal and failure is audited (ADR-0062), as the host itself
            audits its own start, stop and every error it logs.
            Without -Snapshot or -Local the host reads what its own gui.toml
            says.

            Each browser acts as the caller its connection proved — a client
            certificate, over this machine's loopback as from anywhere — with
            the role the host grants that caller (ADR-0009, amended 2026-10-06
            and 2026-10-21): the role gui.toml or XMIP_ROLE states, else
            the directory it names, else Observer. Over an Essentials roll the
            host is told the Essentials' fake directory, which allows the
            tester every role and no one else: the user the host runs as, and
            the subject of the tester's operator certificate, -Tester. A
            browser is never that user for reaching loopback. A browser
            nothing proved watches and acts on nothing. The node decides
            again (ADR-0009, amended 2026-11-01): the host hands it the
            browser's certificate, and each roll's node names the account the
            run runs as in [operate] relay and lists the tester among its
            operators — that account, and CN=<person> of every operator
            certificate the Essentials' authority signed before the roll
            started — so the node acts for the browser by the browser's own
            role and audits it through the host.

            Over a roll, unless -Url or -Certificate says otherwise, the host
            is served https://127.0.0.1:5087 in Xmip's own TLS under the
            Essentials' authority, .local-work/essentials/authority, made
            there the first time (Initialize-XmipEssentialsAuthority), and
            verifies a browser's certificate against it. From nothing to acting
            in the browser: New-XmipCertificate -Operator <person> -Path
            <folder>; New-XmipCertificate -Request <folder>/operator.csr
            -Configuration .local-work/essentials/authority/operator.xmip
            -Path <folder>/operator.pem; give the browser that chain with
            operator.key and trust authority.pem; then
            Get-XmipTestStatus | Start-XmipOperationWeb -Tester <person>.

            Several snapshots are one host over several clusters (ADR-0052,
            amendment 2026-09-20): Get-XmipTestStatus piped here over two rolls
            starts one host that serves both, and the three views say which
            cluster they are on and move between them. Two of them publishing
            one cluster is REFUSED by the host, because a cluster rolls once.
            Get-XmipTestStatus leaves out a run started -Hidden, so the pipe
            never follows one unasked; Get-XmipTestStatus -IncludeHidden
            names it too, and the views show it once "show test clusters" is
            ticked (ADR-0028, amendment 2026-09-30).

            -Local names a node on this machine by its local endpoint, one
            cluster each, beside any snapshot: one host, one surface per
            cluster, each of its own kind (the design approved 2026-11-12,
            section 3.4). At a node that gathers its cluster's view, one
            declaring the monitoring role, the views show the whole cluster as
            that node sees it, and their source line says who gathered it and
            how many of its nodes it reached; a node that has not answered yet
            is named when it first publishes.

            It builds the web host first, as Start-XmipTest builds a roll, and
            launches what it built, so the host is the source as it is. It binds to 127.0.0.1 by
            default rather than localhost, because a browser that cached HSTS for
            localhost from another app silently forces https and the plain-http
            server then looks dead. Get-XmipOperationWeb lists what is running and
            Stop-XmipOperationWeb ends it.

            Xmip's own traffic is TLS (ADR-0063 clause 1). Plain http is bound on
            loopback only, the one exception, and the host says so in its log and
            its audit where it binds it. Any other address is https:// and needs
            -Certificate and -PrivateKey: the host presents that certificate, asks
            a browser for one and checks one presented against -TrustAnchor. The
            host refuses plain http
            beyond loopback, and https with no certificate, before it listens; the
            refusal is in its audit and in the .err file beside its log.

        .PARAMETER Snapshot
            The snapshot file or files to monitor, one per cluster. Bound from
            the pipeline, so a Start-XmipTest -PassThru object names one and
            two rolls on the pipeline name two. A node xmip-service runs
            publishes its own, snapshot.xmip in its data directory, and
            Get-XmipProcess names it (ADR-0018, amendment 2026-09-30).

        .PARAMETER Local
            The local endpoint of a node on this machine to follow, one per
            cluster, as the node's [operate] local names it — xmip-<node>
            unless it names another: the node that gathers its cluster's view,
            so the host shows the whole cluster. The host reaches it as the
            account it runs as. Bound from the pipeline by property name, as
            -Snapshot is.

        .PARAMETER Url
            Where to bind. Defaults to http://127.0.0.1:5087, plain http on
            loopback, and to https://127.0.0.1:5087 over an Essentials roll. Use
            https://0.0.0.0:5443 with -Certificate, -PrivateKey and
            -TrustAnchor to reach it from another device on the network (the
            firewall must also allow the port); https://127.0.0.1:5443 serves
            TLS on this machine alone. Every https address is served in Xmip's
            own TLS by the runtime, never the platform's.

        .PARAMETER Certificate
            The PEM certificate chain, leaf first, the host presents on https.
            Named with -PrivateKey. Unset, the host's gui.toml or
            XMIP_CERTIFICATE decides (ADR-0063 clause 1; where the file comes from
            is provisioning's, ADR-0034).

        .PARAMETER PrivateKey
            The PEM private key of -Certificate.

        .PARAMETER TrustAnchor
            The PEM anchors a caller's certificate must reach. Unset, the host's
            gui.toml or XMIP_TRUST_ANCHOR; https needs one, since Xmip
            trusts no operating system's trust store (ADR-0063).

        .PARAMETER Tester
            The person the Essentials' tester is, as New-XmipCertificate
            -Operator named them: a browser presenting that operator
            certificate, CN=<person>, acts with every role over a roll.

        .PARAMETER PassThru
            Return the Xmip.Web object for the host started.

        .EXAMPLE
            Start-XmipOperationWeb

        .EXAMPLE
            Start-XmipTest -Suite Core.Essentials -Cluster CL1 -Stress Harsh -PassThru |
                Start-XmipOperationWeb

        .EXAMPLE
            Get-XmipTestStatus | Start-XmipOperationWeb

        .EXAMPLE
            Get-XmipTestStatus | Start-XmipOperationWeb -Tester alice@example.org

        .EXAMPLE
            Get-XmipProcess -Name 'xmip-service*' | Start-XmipOperationWeb

        .EXAMPLE
            Start-XmipOperationWeb -Snapshot /opt/xmip/data/snapshot.xmip

        .EXAMPLE
            $other = '.local-work/essentials/CL2-snapshot.xmip'
            Start-XmipOperationWeb -Local xmip-CL1-OP1 -Snapshot $other

        .EXAMPLE
            $tls = @{ Certificate = 'node.pem'; PrivateKey = 'node.key'; TrustAnchor = 'ca.pem' }
            $snapshot = '.local-work/essentials/CL1-snapshot.xmip'
            Start-XmipOperationWeb -Url https://0.0.0.0:5443 -Snapshot $snapshot @tls
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType('Xmip.Web')]
    param(
        # A path nobody publishes is refused where the caller is bound
        # (ADR-0055): a host over a path that is not there answers and shows
        # nothing. A path a rolling cluster publishes is another matter — a
        # roll writes its first snapshot when its first round ends — so that
        # one is waited for, in `end`, rather than refused.
        [Parameter(ValueFromPipelineByPropertyName)]
        [string[]] $Snapshot,

        [Parameter(ValueFromPipelineByPropertyName)]
        [string[]] $Local,

        [Parameter()]
        [ValidatePattern(
            '^https?://([A-Za-z0-9.-]+|\[[0-9A-Fa-f:]+\]|\*|\+):\d{1,5}/?$',
            ErrorMessage = "REFUSED. '{0}' is not an address to bind: http(s)://<host>:<port>."
        )]
        [string] $Url = 'http://127.0.0.1:5087',

        [Parameter()]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf },
            ErrorMessage = "REFUSED. No certificate file at '{0}'.")]
        [string] $Certificate,

        [Parameter()]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf },
            ErrorMessage = "REFUSED. No private key file at '{0}'.")]
        [string] $PrivateKey,

        [Parameter()]
        [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf },
            ErrorMessage = "REFUSED. No trust anchor file at '{0}'.")]
        [string] $TrustAnchor,

        [Parameter()]
        [ValidateNotNullOrWhiteSpace()]
        [string] $Tester,

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
        $reaching = [System.Collections.Generic.List[string]]::new()
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

        # One endpoint is one node, and one cluster, however often named.
        foreach ($endpoint in @($Local | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
            if (-not $reaching.Contains($endpoint.Trim())) {
                $reaching.Add($endpoint.Trim())
            }
        }
    }

    end {
        $ErrorActionPreference = 'Stop'

        # Every start is audited, and so is every refusal and failure
        # (ADR-0062): a Write-Error ends the call here under 'Stop', is
        # recorded, and goes on to the caller unchanged.
        trap {
            Write-XmipAudit -Action 'Start-XmipOperationWeb' -ErrorRecord $_
            break
        }

        Assert-XmipModuleCurrent

        foreach ($named in $following) {
            Wait-XmipSnapshot -Path $named
        }

        $layout = Get-XmipEssentialsLayout
        [string[]] $arguments = @("--Kestrel:Endpoints:Http:Url=$Url")

        # What the host presents and trusts, named here or left to its document
        # (ADR-0063 clause 1). Whether an address may be bound plain is the
        # host's to decide, by the one rule in Xmip.Surface; it refuses before
        # it listens and says why in its audit.
        foreach ($pair in @(
                @{ Key = 'Xmip:Certificate'; Path = $Certificate }
                @{ Key = 'Xmip:PrivateKey'; Path = $PrivateKey }
                @{ Key = 'Xmip:TrustAnchor'; Path = $TrustAnchor }
            )) {
            if ($pair.Path) {
                [string] $full = (Resolve-Path -LiteralPath $pair.Path).ProviderPath
                $arguments += "--$($pair.Key)=$full"
            }
        }

        [bool] $rolls = $false

        # One surface per cluster, each of its own kind: every node's local
        # endpoint and every snapshot, the list winning over gui.toml's.
        $arguments += @(Get-XmipOperationWebClusterArgument -Local $reaching -Snapshot $following)

        if ($following.Count -gt 0) {
            # A web host over an Essentials roll's file is a test's, and says so
            # in its declaration (ADR-0053); over anything else it is runtime.
            [string] $area = [System.IO.Path]::GetFullPath($layout.Area)
            $under = [System.StringComparison]::OrdinalIgnoreCase
            $rolls = @(
                $following | Where-Object { $_.StartsWith($area, $under) }
            ).Count -gt 0

            # And its roles come from the Essentials' fake directory, which
            # allows the tester and no one else (ADR-0009, amendments
            # 2026-09-14, 2026-10-06 and 2026-10-21): the user the host runs
            # as, and the subject of the tester's operator certificate, which
            # a browser proves, never by reaching loopback. Anywhere else an
            # unstated role grants nothing. Served https under the roll's
            # authority unless the call says otherwise.
            if ($rolls) {
                $arguments += '--Xmip:Purpose=test'
                $arguments += '--Xmip:Directory=tester'

                if (-not $PSBoundParameters.ContainsKey('Url')) {
                    $Url = 'https://127.0.0.1:5087'
                    $arguments[0] = "--Kestrel:Endpoints:Http:Url=$Url"
                }

                if ($Tester) {
                    $arguments += "--Xmip:Tester=CN=$($Tester.Trim())"
                }
            }
        }

        # Every cluster this host is told to read: each node's endpoint, each
        # snapshot.
        [string[]] $reads = @($reaching) + @($following)

        # Asked to follow what the pipeline names, and it named nothing: no roll
        # is running. An empty host would answer and show nothing (the owner's
        # console, 2026-09-19).
        if ($reads.Count -eq 0 -and $PSCmdlet.MyInvocation.ExpectingInput) {
            Write-Error ('REFUSED. The pipeline named no run to follow: nothing is rolling. ' +
                'Start-XmipTest first.')
            return
        }

        # The surface is stated, never guessed (ADR-0052 clause 3), so a roll is
        # not followed unasked. But a host that will not show the roll beside it
        # says so, and says how (the owner's console, twice, 2026-09-19).
        if ($reads.Count -eq 0) {
            [string] $rolling = (Get-XmipTestStatus |
                    Where-Object -Property Suite -EQ -Value $script:XmipEssentialsSuite |
                    ForEach-Object -MemberName Cluster) -join ', '

            if ($rolling) {
                Write-Warning ("No -Snapshot: this host reads its own gui.toml and will " +
                    "not show the roll $rolling. To follow it: " +
                    'Get-XmipTestStatus | Start-XmipOperationWeb')
            }
        }

        [string] $over = if ($reads.Count -gt 0) {
            " over $($reads -join ', ')"
        }
        else {
            ''
        }

        if (-not $PSCmdlet.ShouldProcess("the Xmip web monitor at $Url", "Start$over")) {
            return
        }

        Assert-XmipOperationWebFree -Url $Url

        # Over a roll, https under the Essentials' authority, the host's
        # certificate issued anew, unless the call named its own.
        if ($rolls -and $Url.StartsWith('https:') -and -not $Certificate) {
            $kept = Initialize-XmipEssentialsAuthority -Folder $layout.Authority -Confirm:$false
            $arguments += "--Xmip:Certificate=$($kept.Certificate)"
            $arguments += "--Xmip:PrivateKey=$($kept.PrivateKey)"

            if (-not $TrustAnchor) {
                $arguments += "--Xmip:TrustAnchor=$($kept.TrustAnchor)"
            }
        }

        Build-XmipOperationWeb -Root $layout.Root

        $launch = @{
            FilePath         = $layout.Web
            ArgumentList     = $arguments
            WorkingDirectory = Split-Path -Parent $layout.Web
            WindowStyle      = 'Hidden'
            PassThru         = $true
        }

        # The host's own output is kept beside its run, as a roll's is: a host
        # that dies at start says why in a file, not on a console nobody kept
        # (ADR-0062, the failure that prompted it). Named for the start time,
        # since Start-Process wants the file named before the pid exists.
        [string] $area = (Get-XmipEstateLayout -Root $layout.Root).Web
        Initialize-XmipAudit
        $null = New-Item -ItemType Directory -Path $area -Force
        [string] $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $launch.RedirectStandardOutput = Join-Path -Path $area -ChildPath "web-$stamp.log"
        $launch.RedirectStandardError = Join-Path -Path $area -ChildPath "web-$stamp.err"

        $process = Start-Process @launch
        Write-Verbose "web monitor starting at $Url as pid $($process.Id)"
        Write-XmipAudit -Action 'Start-XmipOperationWeb' -Phase Begin -Property @{
            Id       = $process.Id
            Url      = $Url
            Local    = $reaching -join ', '
            Snapshot = $following -join ', '
            Log      = $launch.RedirectStandardOutput
        }

        if ($PassThru) {
            return ConvertTo-XmipOperationWeb -Process $process
        }
    }
}
