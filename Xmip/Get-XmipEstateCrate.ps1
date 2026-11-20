#requires -PSEdition Core
#requires -Version 7.7.0

using namespace System.Collections.Generic

function Get-XmipEstateCrate {
    <#
        .SYNOPSIS
            Every estate crate in the working trees: its package name and its
            folder.

        .DESCRIPTION
            The estate's one workspace lists each as a member and patches each
            to its folder (Update-XmipWorkspace).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot
    )

    [HashSet[string]] $seen = [HashSet[string]]::new()

    # Build output, the working areas and run output hold copies of
    # manifests; only a module's own Cargo.toml names a crate. The estate's
    # one walk prunes them before it enters them (Find-XmipFile), so an
    # estate cloned under another one's .local-work finds its own crates; a
    # folder at the root whose name starts with a dot is a tool's (an
    # editor's, an assistant's worktree) and holds none of the estate's.
    [string] $root = [System.IO.Path]::GetFullPath($RepositoryRoot)

    Find-XmipFile -Path $root -Filter 'Cargo.toml' |
        Where-Object {
            -not [System.IO.Path]::GetRelativePath($root, $_.FullName).StartsWith('.')
        } |
        ForEach-Object {
            [string] $text = Get-Content -LiteralPath $_.FullName -Raw

            if ($text -notmatch '(?ms)^\[package\][^\[]*?^name\s*=\s*"(xmip[^"]+)"') {
                return
            }

            [string] $crate = $Matches[1]

            if (-not $seen.Add($crate)) {
                return
            }

            [pscustomobject]@{
                Name      = $crate
                Directory = $_.DirectoryName -replace '\\', '/'
            }
        }
}
