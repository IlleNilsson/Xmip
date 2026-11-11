#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    The demo readiness check's web part: the web operations tool started
    over the roll's snapshot, answering over https at its address under the
    Essentials' authority.

.DESCRIPTION
    The host is started as the demo starts it, Start-XmipOperationWeb over
    the snapshot with -Tester, so it is built, served in Xmip's own TLS under
    the Essentials' authority and audited as every start of it is (ADR-0009,
    amendment 2026-10-21; ADR-0063). What is checked is what a browser on the
    demo machine meets: the address answers https, with a certificate that
    reaches the anchor the tester's browser trusts.

    The check stands where the browser stands, so it reaches the host as a
    browser does, through .NET's own TLS client and not Xmip's: the runtime's
    TLS is the host's side of the connection (xmip_operate.h section 21) and
    no TLS client of it reaches the tooling, and a browser's TLS is never
    Xmip's either — as Xmip.Surface.Test's BrowserOverTlsTest reaches the host.
    The chain is built over the Essentials' anchor alone, with no operating
    system store (ADR-0063), and presents no certificate, which proves no one:
    the host serves such a browser and lets it act on nothing (ADR-0009,
    amendment 2026-10-06).

    Style: doc/governance/powershell-style.md
#>


# How long a web host just started is given to answer before the check says
# it did not. A start is seconds; how long it took is said either way.
[timespan] $script:XmipDemoAnswerWait = [timespan]::FromMinutes(1)


function Test-XmipDemoWeb {
    <#
        .SYNOPSIS
            Starts the web operations tool over the run's snapshot and checks
            it answers over https under the Essentials' authority; returns
            what it found in words, or throws why not.

        .PARAMETER Run
            The run, from New-XmipDemoState: its snapshot and tester, and
            where the host it launched is kept.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Run
    )

    [hashtable] $asked = @{
        Snapshot    = @($Run['snapshot'])
        PassThru    = $true
        ErrorAction = 'Stop'
    }

    if ($Run['tester'] -ne '') {
        $asked.Tester = $Run['tester']
    }

    $web = Start-XmipOperationWeb @asked

    if ($null -eq $web) {
        throw 'Start-XmipOperationWeb started no web host.'
    }

    $Run['launched']['web'] = [int] $web.Id
    Write-XmipDemoRecord -Run $Run

    [string] $anchor = Get-XmipDemoWebAnchor -Id $web.Id
    [string] $answered = Test-XmipDemoHttps -Url $web.Url -TrustAnchor $anchor
    [string] $for = if ($Run['tester'] -ne '') {
        "for the tester $($Run['tester'])"
    }
    else {
        'for no tester: a browser acts as no one but the user the host runs as'
    }

    return ("$($web.Url) $answered, its certificate issued under the Essentials' " +
        "authority ($anchor); the host is pid $($web.Id), $for")
}


function Get-XmipDemoWebAnchor {
    <#
        .SYNOPSIS
            The trust anchor a running web host was given, which must be the
            Essentials' authority's; throws otherwise, or where the host has
            ended.

        .PARAMETER Id
            The host's process id.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [int] $Id
    )

    $layout = Get-XmipEssentialsLayout
    $process = Get-Process -Id $Id -ErrorAction SilentlyContinue

    if ($null -eq $process) {
        [string] $logs = (Get-XmipEstateLayout -Root $layout.Root).Web
        throw "the web host, pid $Id, ended as it started; its log under $logs says why."
    }

    [hashtable] $read = @{ CommandLine = "$($process.CommandLine)"; Name = 'Xmip:TrustAnchor' }
    [string] $anchor = Read-XmipOperationWebArgument @read
    [string] $authority = [System.IO.Path]::GetFullPath($layout.Authority)

    # Inside the folder, never beside it: authority-old\ca.pem shares the
    # folder's name as a prefix, and a separator after it tells them apart.
    [string] $inside = [System.IO.Path]::TrimEndingDirectorySeparator($authority) +
        [System.IO.Path]::DirectorySeparatorChar
    [System.StringComparison] $case = [System.StringComparison]::OrdinalIgnoreCase
    [bool] $under = $anchor -ne '' -and
        [System.IO.Path]::GetFullPath($anchor).StartsWith($inside, $case)

    if (-not $under) {
        throw "the web host trusts '$anchor', not the Essentials' authority under $authority."
    }

    return $anchor
}


function Test-XmipDemoHttps {
    <#
        .SYNOPSIS
            Asks an address over https until it answers or the wait ends:
            returns "answered HTTP <status> after <seconds> s"; throws where
            nothing answered, where the host's certificate does not reach the
            anchor, or where it answered with a server's error.

        .PARAMETER Url
            The address, https://<host>:<port>.

        .PARAMETER TrustAnchor
            The PEM anchors the host's certificate must reach.

        .PARAMETER Wait
            How long a host just started is given to answer.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Url,

        [Parameter(Mandatory)]
        [string] $TrustAnchor,

        [Parameter()]
        [timespan] $Wait = $script:XmipDemoAnswerWait
    )

    $anchors = [System.Security.Cryptography.X509Certificates.X509Certificate2Collection]::new()
    $anchors.ImportFromPemFile($TrustAnchor)
    $policy = [System.Security.Cryptography.X509Certificates.X509ChainPolicy]::new()
    $policy.TrustMode = 'CustomRootTrust'
    $policy.RevocationMode = 'NoCheck'
    $policy.CustomTrustStore.AddRange($anchors)
    $handler = [System.Net.Http.SocketsHttpHandler]::new()
    $handler.SslOptions.CertificateChainPolicy = $policy
    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [timespan]::FromSeconds(10)
    [System.Diagnostics.Stopwatch] $clock = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        $asked = Get-XmipDemoAnswer -Client $client -Url $Url

        while ($asked.Status -eq 0 -and -not $asked.Refused -and $clock.Elapsed -lt $Wait) {
            Start-Sleep -Milliseconds 250
            $asked = Get-XmipDemoAnswer -Client $client -Url $Url
        }
    }
    finally {
        $client.Dispose()
    }

    if ($asked.Refused) {
        throw "$Url presented a certificate that does not reach ${TrustAnchor}: $($asked.Fault)"
    }

    if ($asked.Status -eq 0) {
        throw "nothing answered https at $Url within ${Wait}: $($asked.Fault)"
    }

    if ($asked.Status -ge 500) {
        throw "$Url answered HTTP $($asked.Status), a server's error."
    }

    return "answered HTTP $($asked.Status) after $([math]::Round($clock.Elapsed.TotalSeconds, 1)) s"
}


function Get-XmipDemoAnswer {
    <#
        .SYNOPSIS
            One request to an address: Status, the HTTP status or 0 where
            nothing answered; Refused, whether the TLS handshake refused the
            host's certificate; Fault, the innermost reason.

        .PARAMETER Client
            The client, its TLS chain policy set.

        .PARAMETER Url
            The address.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [System.Net.Http.HttpClient] $Client,

        [Parameter(Mandatory)]
        [string] $Url
    )

    try {
        $response = $Client.GetAsync([uri] $Url).GetAwaiter().GetResult()
        [int] $status = [int] $response.StatusCode
        $response.Dispose()

        return [pscustomobject]@{ Status = $status; Refused = $false; Fault = '' }
    }
    catch {
        [System.Collections.Generic.List[System.Exception]] $chain = @()

        for ($fault = $_.Exception; $null -ne $fault; $fault = $fault.InnerException) {
            $chain.Add($fault)
        }

        [type] $handshake = [System.Security.Authentication.AuthenticationException]
        [bool] $refused = @($chain | Where-Object { $_ -is $handshake }).Count -gt 0

        return [pscustomobject]@{ Status = 0; Refused = $refused; Fault = $chain[-1].Message }
    }
}
