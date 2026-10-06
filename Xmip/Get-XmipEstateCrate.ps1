#requires -PSEdition Core
#requires -Version 7.6.5

using namespace System.Collections.Generic

function Get-XmipEstateCrate {
    <#
        .SYNOPSIS
            Every estate crate in the working trees: its package name, its
            folder, and the name of the library cargo writes without a hash.

        .DESCRIPTION
            Read once for a landing: New-XmipLocalPatch patches each crate to
            its folder, and Clear-XmipUnhashedLibrary removes the libraries
            one workspace left for another.

            Cargo names a path crate's library without its hash when the crate
            builds a cdylib or dylib, so the rlib beside it is one file, shared
            by every workspace in the one build directory. Unhashed is that
            library's name (`xmip_core_runtime`), empty for any other crate.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot
    )

    [HashSet[string]] $seen = [HashSet[string]]::new()

    # Build output, the assistant's working area and run output hold copies of
    # manifests; only a module's own Cargo.toml names a crate.
    [string] $skip = '[\\/](target|target-[^\\/]+|\.git|\.ai-interaction|' +
        '\.local-work|node_modules)[\\/]'

    [hashtable] $manifests = @{
        LiteralPath = $RepositoryRoot
        Filter      = 'Cargo.toml'
        File        = $true
        Recurse     = $true
        ErrorAction = 'SilentlyContinue'
    }

    Get-ChildItem @manifests |
        Where-Object { $_.FullName -notmatch $skip } |
        ForEach-Object {
            [string] $text = Get-Content -LiteralPath $_.FullName -Raw

            if ($text -notmatch '(?ms)^\[package\][^\[]*?^name\s*=\s*"(xmip[^"]+)"') {
                return
            }

            [string] $crate = $Matches[1]

            if (-not $seen.Add($crate)) {
                return
            }

            [string] $unhashed = ''
            [string] $library = '(?ms)^\[lib\][^\[]*?^crate-type\s*=\s*\[[^\]]*"c?dylib"'

            if ($text -match $library) {
                $unhashed = $crate -replace '-', '_'

                if ($text -match '(?ms)^\[lib\][^\[]*?^name\s*=\s*"([^"]+)"') {
                    $unhashed = $Matches[1]
                }
            }

            [pscustomobject]@{
                Name      = $crate
                Directory = $_.DirectoryName -replace '\\', '/'
                Unhashed  = $unhashed
            }
        }
}
