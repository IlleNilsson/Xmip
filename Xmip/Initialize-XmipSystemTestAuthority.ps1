#requires -Version 7.7.0

Set-StrictMode -Version Latest

function Initialize-XmipSystemTestAuthority {
    <#
        .SYNOPSIS
            The System Tests' authority, kept under its area, and a certificate
            for the web host under it; made where none is kept.

        .DESCRIPTION
            The System Tests tester acts in the web GUI with an operator
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
            System Tests' cluster.xmip declares [provision.operator] for, found
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
            Where the authority is kept. Get-XmipSystemTestLayout's Authority
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
        [string] $Folder = (Get-XmipSystemTestLayout).Authority,

        [Parameter()]
        [string] $HostName = '127.0.0.1'
    )

    $ErrorActionPreference = 'Stop'
    [string] $full = [System.IO.Path]::GetFullPath($Folder)

    if ((Split-Path -Path $full -Leaf) -cne 'authority') {
        throw "REFUSED. $full is not named authority, the folder the trust reads beside a slice."
    }

    [string] $act = "Keep the System Tests' authority and issue $HostName"

    if (-not $PSCmdlet.ShouldProcess($full, $act)) {
        return
    }

    Import-XmipOperatorModule
    $hosting = [Xmip.Surface.RuntimeLibrary]::Rules.Hosting
    $issued = $null
    [string] $refused = ''

    if (-not $hosting.Issue($full, 'Xmip System Tests authority', $HostName, $full,
            [ref] $issued, [ref] $refused)) {
        throw "REFUSED. The System Tests' authority at ${full}: $refused"
    }

    # The cluster the run names, and the node the System Tests' file declares
    # [provision.operator] for (Write-XmipOperatorSlice).
    [hashtable] $slicing = @{
        File      = (Get-XmipSystemTestLayout).Configuration
        Cluster   = (Read-XmipTestCluster -Path (Get-XmipTestClusterPath)).Name
        Authority = $full
    }
    [string] $configuration = Write-XmipOperatorSlice @slicing

    return [PSCustomObject]@{
        Certificate   = $issued.Certificate
        PrivateKey    = $issued.Key
        TrustAnchor   = $issued.Anchor
        Configuration = $configuration
    }
}
