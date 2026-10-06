#requires -PSEdition Core
#requires -Version 7.6.5

using namespace System.Collections.Generic

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

    [List[string]] $lines = [List[string]]::new()
    $lines.Add('# Written by New-XmipLocalPatch for one landing. Never committed.')

    foreach ($crate in @(Get-XmipEstateCrate -RepositoryRoot $RepositoryRoot)) {
        $lines.Add("[patch.`"https://github.com/IlleNilsson/$($crate.Name)`"]")
        $lines.Add("$($crate.Name) = { path = `"$($crate.Directory)`" }")
    }

    Set-Content -LiteralPath $patch -Value $lines -Encoding utf8NoBOM

    $patch
}
