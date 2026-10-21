#requires -Version 7.6.7

Set-StrictMode -Version Latest

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
