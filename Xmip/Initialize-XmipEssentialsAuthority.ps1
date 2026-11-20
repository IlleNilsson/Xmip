#requires -Version 7.7.0

Set-StrictMode -Version Latest

function Initialize-XmipEssentialsAuthority {
    <#
        .SYNOPSIS
            The Essentials' authority, kept under its area, and a certificate
            for the web host under it; made where none is kept.

        .DESCRIPTION
            The Essentials tester acts in the web GUI with an operator
            certificate (ADR-0009, amendment 2026-10-21): the host serves
            https on 127.0.0.1 under the roll's authority and the tester
            presents a certificate that authority signed. The authority is
            kept in the layout's Authority folder, authority.key and
            authority.pem, private files, made there where none is kept, as a
            cluster's own authority is; the host's key and certificate,
            host.key and host.pem, are issued anew beside it at each start. All
            of it is the runtime's (xmip_operate.h section 21, through
            Xmip.Surface's RuntimeLibrary); nothing here writes a key.

            Beside the folder, operator.xmip is the slice of the node the
            Essentials' cluster.xmip declares [provision.operator] for, found
            by that table and never by its name, sliced as the run names the
            cluster (Get-XmipTestClusterPath) and signed by this authority
            through xmip_cluster_signed_slice_v1, written anew at each call
            (ADR-0031, amendment 2026-11-19). The tester has their request
            signed by it with the operator module's own cmdlet:
            New-XmipCertificate -Request <operator.csr> -Configuration
            <Area>/operator.xmip. The runtime reads it as its trust admits a
            slice, so one edited by hand is refused.

            Returns the host's Certificate, PrivateKey and TrustAnchor, and the
            Configuration a tester signs by.

        .PARAMETER Folder
            Where the authority is kept. Get-XmipEssentialsLayout's Authority
            unless given. Its name is authority, the folder the trust reads
            beside a slice.

        .PARAMETER HostName
            The name a browser reaches the host by, and its certificate names:
            127.0.0.1 unless given.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string] $Folder = (Get-XmipEssentialsLayout).Authority,

        [Parameter()]
        [string] $HostName = '127.0.0.1'
    )

    $ErrorActionPreference = 'Stop'
    [string] $full = [System.IO.Path]::GetFullPath($Folder)

    if ((Split-Path -Path $full -Leaf) -cne 'authority') {
        throw "REFUSED. $full is not named authority, the folder the trust reads beside a slice."
    }

    [string] $act = "Keep the Essentials' authority and issue $HostName"

    if (-not $PSCmdlet.ShouldProcess($full, $act)) {
        return
    }

    Import-XmipOperatorModule
    $hosting = [Xmip.Surface.RuntimeLibrary]::Rules.Hosting
    $issued = $null
    [string] $refused = ''

    if (-not $hosting.Issue($full, 'Xmip Essentials authority', $HostName, $full,
            [ref] $issued, [ref] $refused)) {
        throw "REFUSED. The Essentials' authority at ${full}: $refused"
    }

    # Names are configuration (ADR-0056, amendment 2026-10-03): the cluster
    # the run names, and the node the cluster's file declares the table for.
    [string] $file = (Get-XmipEssentialsLayout).Configuration
    [string] $cluster = (Read-XmipTestCluster -Path (Get-XmipTestClusterPath)).Name
    $nodes = Get-TomlValue -Node (Read-XmipConfiguration -Path $file) -Name 'nodes'
    [string[]] $signing = @(Get-TomlKey -Node $nodes | Where-Object {
            $provision = Get-TomlValue -Node (Get-TomlValue -Node $nodes -Name $_) -Name 'provision'
            $null -ne (Get-TomlValue -Node $provision -Name 'operator')
        })

    if ($signing.Count -ne 1) {
        throw ("REFUSED. $file declares [provision.operator] for $($signing.Count) nodes " +
            "($($signing -join ', ')); one node's slice signs a tester's request.")
    }

    [string] $answer = ''
    $design = [Xmip.Surface.RuntimeLibrary]::Rules.Design
    [string] $text = Get-Content -LiteralPath $file -Raw -Encoding utf8

    if (-not $design.TrySignedSlice($text, $file, $signing[0], $cluster, $full, [ref] $answer)) {
        throw "REFUSED. The slice of $($signing[0]) from ${file}: $answer"
    }

    [string] $beside = Split-Path -Path $full -Parent
    [string] $configuration = Join-Path -Path $beside -ChildPath 'operator.xmip'
    Write-XmipWholeFile -Path $configuration -Text (ConvertFrom-Json -InputObject $answer).text

    return [PSCustomObject]@{
        Certificate   = $issued.Certificate
        PrivateKey    = $issued.Key
        TrustAnchor   = $issued.Anchor
        Configuration = $configuration
    }
}
