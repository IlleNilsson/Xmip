#requires -Version 7.7.0

Set-StrictMode -Version Latest

function Get-XmipOperationWebClusterArgument {
    <#
        .SYNOPSIS
            How a web host is told which clusters to read: one surface per
            cluster, each of its own kind. Pure.

        .DESCRIPTION
            Microsoft.Extensions.Configuration reads --Xmip:Clusters:0:Surface
            with --Xmip:Clusters:0:Local, or with --Xmip:Clusters:0:Snapshot, as
            the list Xmip.Surface's SurfaceChoice.OpenAll opens: one surface per
            cluster, in the order given, each node's local endpoint and then
            each snapshot. The list wins over the surface the host's own
            gui.toml names (the design approved 2026-11-12, section 3.4).
            Get-XmipOperationWeb reads it back from the host's command line.

        .PARAMETER Local
            The local endpoint of each node to follow, one cluster each. A node
            that gathers its cluster's view answers for the whole cluster.

        .PARAMETER Snapshot
            The full path of each snapshot to read, one cluster each.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter()]
        [AllowEmptyCollection()]
        [string[]] $Local = @(),

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]] $Snapshot = @()
    )

    [object[]] $clusters = @(
        $Local | ForEach-Object { @{ Surface = 'local'; Key = 'Local'; Place = $_ } }
        $Snapshot | ForEach-Object { @{ Surface = 'snapshot'; Key = 'Snapshot'; Place = $_ } }
    )

    for ([int] $at = 0; $at -lt $clusters.Count; $at++) {
        "--Xmip:Clusters:${at}:Surface=$($clusters[$at].Surface)"
        "--Xmip:Clusters:${at}:$($clusters[$at].Key)=$($clusters[$at].Place)"
    }
}
