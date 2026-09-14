#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Resolve-XmipClusterFile {
    <#
        .SYNOPSIS
            The one `<cluster>-<kind>.toml` in a directory, or a refusal that
            names the clusters found there.

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

    [System.IO.FileInfo[]] $files = @(
        Get-ChildItem -Path $Directory -Filter "*-$Kind.toml" -File | Sort-Object -Property Name
    )

    if ($files.Count -eq 1) {
        return $files[0].FullName
    }

    if ($files.Count -eq 0) {
        # The caller's own "No <kind> file at" message follows, on this path.
        return Join-Path -Path $Directory -ChildPath "<cluster>-$Kind.toml"
    }

    [string] $names = ($files | ForEach-Object { $_.Name }) -join ', '
    throw "$Directory holds $Kind files of $($files.Count) clusters ($names); name one with -Path."
}
