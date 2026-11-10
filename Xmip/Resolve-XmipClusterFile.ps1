#requires -Version 7.7.0

Set-StrictMode -Version Latest

function Resolve-XmipClusterFile {
    <#
        .SYNOPSIS
            The one `<cluster>-<kind>` file in a directory, or a refusal that
            names the clusters found there. A snapshot ends in .xmip, what an
            installation's tools open; history and activity end in .toml
            (ADR-0031, amendment 2026-11-10).

        .DESCRIPTION
            A roll publishes under the cluster the owner named it (ADR-0052,
            amendment 2026-09-14, ruling 8), so a directory may hold one
            cluster's files or several. One is the answer; none or several is
            a refusal that says which, since nothing here guesses a cluster.

        .PARAMETER Directory
            The directory to look in.

        .PARAMETER Kind
            snapshot, history or activity.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Directory,

        [Parameter(Mandatory)]
        [ValidateSet('snapshot', 'history', 'activity')]
        [string] $Kind
    )

    [string] $extension = if ($Kind -eq 'snapshot') { 'xmip' } else { 'toml' }

    [System.IO.FileInfo[]] $files = @(
        Get-ChildItem -Path $Directory -Filter "*-$Kind.$extension" -File |
            Sort-Object -Property Name
    )

    if ($files.Count -eq 1) {
        return $files[0].FullName
    }

    if ($files.Count -eq 0) {
        # The caller's own "No <kind> file at" message follows, on this path.
        return Join-Path -Path $Directory -ChildPath "<cluster>-$Kind.$extension"
    }

    [string] $names = ($files | ForEach-Object { $_.Name }) -join ', '
    throw "$Directory holds $Kind files of $($files.Count) clusters ($names); name one with -Path."
}
