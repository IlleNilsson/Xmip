#requires -PSEdition Core
#requires -Version 7.6.5

function New-XmipLocalPatch {
    <#
        .SYNOPSIS
            Writes a cargo configuration that patches every estate crate to its
            working tree, and returns its path.

        .DESCRIPTION
            Dependencies track `main` on origin (ADR-0005), so without this a
            module verifies only against siblings already pushed — which is why
            the landing used to push between tests. With every crate patched to
            its local path, the whole dependency tree verifies before anything
            is pushed (the owner, 2026-10-05: *Do dependecy tree build and stop
            when a leaf fails*).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot
    )

    [string] $directory = Join-Path -Path $RepositoryRoot -ChildPath '.local-work/landing'
    $null = New-Item -ItemType Directory -Path $directory -Force
    [string] $patch = Join-Path -Path $directory -ChildPath 'patch.toml'

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# Written by New-XmipLocalPatch for one landing. Never committed.')
    $seen = [System.Collections.Generic.HashSet[string]]::new()

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

            if ($text -match '(?ms)^\[package\][^\[]*?^name\s*=\s*"(xmip[^"]+)"') {
                [string] $crate = $Matches[1]

                if ($seen.Add($crate)) {
                    [string] $at = $_.DirectoryName -replace '\\', '/'
                    $lines.Add("[patch.`"https://github.com/IlleNilsson/$crate`"]")
                    $lines.Add("$crate = { path = `"$at`" }")
                }
            }
        }

    Set-Content -LiteralPath $patch -Value $lines -Encoding utf8NoBOM

    $patch
}
