#requires -Version 7.7.0

Set-StrictMode -Version Latest

function Write-XmipOperatorSlice {
    <#
        .SYNOPSIS
            operator.xmip beside an authority's folder: the slice of the node
            a cluster file declares [provision.operator] for, found by that
            table and never by its name, sliced as -Cluster names the cluster
            and signed by that authority through xmip_cluster_signed_slice_v1;
            its path. A person's request is signed by it with the operator
            module's own cmdlet: New-XmipCertificate -Request <operator.csr>
            -Configuration <its path>.

        .DESCRIPTION
            The one writing of it, for the System Tests' authority
            (Initialize-XmipSystemTestAuthority) and a deployed environment's
            (Initialize-XmipDeployIdentity). The runtime reads it as its trust
            admits a slice, so one edited by hand is refused (ADR-0031,
            amendment 2026-11-19). Written anew at each call.

        .PARAMETER File
            The cluster file.

        .PARAMETER Cluster
            The cluster's name.

        .PARAMETER Authority
            The authority's folder, named authority: the folder the trust
            reads beside a slice.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $File,

        [Parameter(Mandatory)]
        [string] $Cluster,

        [Parameter(Mandatory)]
        [string] $Authority
    )

    Import-XmipOperatorModule
    # Names are configuration (ADR-0056, amendment 2026-10-03): the cluster
    # the run names, and the node the cluster's file declares the table for.
    $nodes = Get-TomlValue -Node (Read-XmipConfiguration -Path $File) -Name 'nodes'
    [string[]] $signing = @(Get-TomlKey -Node $nodes | Where-Object {
            $provision = Get-TomlValue -Node (Get-TomlValue -Node $nodes -Name $_) -Name 'provision'
            $null -ne (Get-TomlValue -Node $provision -Name 'operator')
        })

    if ($signing.Count -ne 1) {
        throw ("REFUSED. $File declares [provision.operator] for $($signing.Count) nodes " +
            "($($signing -join ', ')); one node's slice signs a tester's request.")
    }

    [string] $answer = ''
    $design = [Xmip.Surface.RuntimeLibrary]::Rules.Design
    [string] $text = Get-Content -LiteralPath $File -Raw -Encoding utf8

    if (-not $design.TrySignedSlice($text, $signing[0], $Cluster, $Authority, [ref] $answer)) {
        throw "REFUSED. The slice of $($signing[0]) from ${File}: $answer"
    }

    [string] $beside = Split-Path -Path $Authority -Parent
    [string] $configuration = Join-Path -Path $beside -ChildPath 'operator.xmip'
    Write-XmipWholeFile -Path $configuration -Text (ConvertFrom-Json -InputObject $answer).text
    return $configuration
}
