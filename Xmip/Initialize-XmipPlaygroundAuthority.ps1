#requires -Version 7.6.7

Set-StrictMode -Version Latest

function Initialize-XmipPlaygroundAuthority {
    <#
        .SYNOPSIS
            The Playground's authority, kept under its area, and a certificate
            for the web host under it; made where none is kept.

        .DESCRIPTION
            The Playground tester acts in the web GUI with an operator
            certificate (ADR-0009, amendment 2026-10-21): the host serves
            https on 127.0.0.1 under the roll's authority and the tester
            presents a certificate that authority signed. The authority is
            kept in the layout's Authority folder, authority.key and
            authority.pem, private files, made there where none is kept, as a
            cluster's own authority is; the host's key and certificate,
            host.key and host.pem, are issued anew beside it at each start. All
            of it is the runtime's (xmip_operate.h section 21, through
            Xmip.Surface's RuntimeLibrary); nothing here writes a key.

            Beside them, operator.toml names the folder in
            [provision.operator], so the tester has their request signed by
            the same authority with the operator module's own cmdlet:
            New-XmipCertificate -Request <operator.csr> -Configuration
            <Authority>/operator.toml. The runtime reads that file as a node
            configuration, so it carries a [service] table: the cluster the
            Playground rolls, as its xmip.toml names it (Get-XmipTestClusterPath),
            and the folder's name as the node's, which no node runs as.

            Returns the host's Certificate, PrivateKey and TrustAnchor, and the
            Configuration a tester signs by.

        .PARAMETER Folder
            Where the authority is kept. Get-XmipPlaygroundLayout's Authority
            unless given.

        .PARAMETER HostName
            The name a browser reaches the host by, and its certificate names:
            127.0.0.1 unless given.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string] $Folder = (Get-XmipPlaygroundLayout).Authority,

        [Parameter()]
        [string] $HostName = '127.0.0.1'
    )

    $ErrorActionPreference = 'Stop'
    [string] $full = [System.IO.Path]::GetFullPath($Folder)

    [string] $act = "Keep the Playground's authority and issue $HostName"

    if (-not $PSCmdlet.ShouldProcess($full, $act)) {
        return
    }

    Import-XmipOperatorModule
    $hosting = [Xmip.Surface.RuntimeLibrary]::Rules.Hosting
    $issued = $null
    [string] $refused = ''

    if (-not $hosting.Issue($full, 'Xmip Playground authority', $HostName, $full,
            [ref] $issued, [ref] $refused)) {
        throw "REFUSED. The Playground's authority at ${full}: $refused"
    }

    [string] $configuration = Join-Path -Path $full -ChildPath 'operator.toml'

    if (-not (Test-Path -LiteralPath $configuration)) {
        # Names are configuration (ADR-0056, amendment 2026-10-03): the
        # cluster the Playground rolls, from its xmip.toml, and the folder's.
        [string] $cluster = (Read-XmipTestCluster -Path (Get-XmipTestClusterPath)).Name
        [string] $place = Split-Path -Path $full -Leaf
        Set-Content -LiteralPath $configuration -Encoding utf8NoBOM -Value @(
            "# What signs a Playground tester's operator request (ADR-0009, amendment"
            '# 2026-10-21): New-XmipCertificate -Request <operator.csr> -Configuration'
            '# this file. The runtime reads it as a node configuration; no node runs as it.'
            '[service]'
            'name = "xmip-playground-authority"'
            "cluster_name = `"$cluster`""
            "node_name = `"$place`""
            ''
            '[provision.operator]'
            'authority = "."'
        )
    }

    return [PSCustomObject]@{
        Certificate   = $issued.Certificate
        PrivateKey    = $issued.Key
        TrustAnchor   = $issued.Anchor
        Configuration = $configuration
    }
}
