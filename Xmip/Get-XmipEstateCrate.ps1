#requires -PSEdition Core
#requires -Version 7.7.0

using namespace System.Collections.Generic

function Get-XmipEstateCrate {
    <#
        .SYNOPSIS
            Every estate crate in the working trees: its package name and its
            folder.

        .DESCRIPTION
            Read once for a landing: New-XmipLocalPatch patches each crate to
            its folder.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot
    )

    [HashSet[string]] $seen = [HashSet[string]]::new()

    # Build output, the assistant's working area and run output hold copies of
    # manifests; only a module's own Cargo.toml names a crate. Build output is
    # skipped at any depth, the working area and run output at the estate's
    # root alone, matched on the path below it: an estate cloned under another
    # one's .local-work finds its own crates.
    [string] $skip = "^(\.ai-interaction|$([regex]::Escape($script:XmipWorkName)))[\\/]|" +
        '(^|[\\/])(target|target-[^\\/]+|\.git|node_modules)[\\/]'
    [string] $root = [System.IO.Path]::GetFullPath($RepositoryRoot)

    [hashtable] $manifests = @{
        LiteralPath = $RepositoryRoot
        Filter      = 'Cargo.toml'
        File        = $true
        Recurse     = $true
        ErrorAction = 'SilentlyContinue'
    }

    Get-ChildItem @manifests |
        Where-Object { [System.IO.Path]::GetRelativePath($root, $_.FullName) -notmatch $skip } |
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
