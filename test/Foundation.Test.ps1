#requires -PSEdition Core
#requires -Version 7.7.0

<#
    A Foundation crate opens no file. ADR-0058 clause 1: a Foundation
    repository answers what a thing is, and nothing in it starts, opens,
    spawns, reads a file or waits on a clock. Until 2026-11-13
    xmip-core-node made a directory, wrote a System Process's declaration
    file, removed it and listed every file beside it; the file is the
    runtime's now (`xmip-core-runtime`'s `declared`; ADR-0058, amendment
    2026-11-13), and this is how none comes back.

    Every crate mounted at module/foundation is read, its `src` or `.src`.
    Production code only: a file's tests, from its first
    `#[cfg(test)]` down, may make what scratch files they need. The lines
    come from `Get-XmipSourceFile`, whose `Code` is exactly that boundary;
    a comment line is passed over.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    # How Rust reaches the file system: the standard library's module, and
    # what it is reached through.
    [string] $script:Touching = '\bstd::fs\b|\bfs::|\bFile::|\bOpenOptions\b|\bread_dir\b'

    # A Foundation crate's own source, as the estate mounts it (ADR-0016).
    [string] $script:Foundation = '^module/foundation/[^/]+/\.?src/'

    $script:Read = [System.Collections.Generic.List[string]]::new()

    <#
        .SYNOPSIS
        Every production line of a Foundation crate that touches a file.
    #>
    function Find-XmipFoundationFile {
        [CmdletBinding()]
        [OutputType([string[]])]
        param()

        foreach ($file in @(Get-XmipSourceFile -Root $script:Root -Language Rust)) {
            [string] $path = $file.Path -replace '\\', '/'

            if ($file.Code -eq 0 -or $path -notmatch $script:Foundation) {
                continue
            }

            $script:Read.Add($path)
            [string] $full = Join-Path $script:Root $file.Path
            [string[]] $line = @(Get-Content -LiteralPath $full -TotalCount $file.Code)

            for ([int] $index = 0; $index -lt $line.Count; $index++) {
                [string] $text = $line[$index]

                if (-not $text.TrimStart().StartsWith('//') -and $text -match $script:Touching) {
                    "${path}:$($index + 1) $($text.Trim())"
                }
            }
        }
    }

    $script:Found = @(Find-XmipFoundationFile)
}

Describe 'A Foundation crate opens no file' {
    It 'reads, writes, lists and removes no file in production code' {
        $script:Found | Should -BeNullOrEmpty -Because (
            'a definition opens no file; acting on one is Platform (ADR-0058 clause 1)')
    }

    It 'read the Foundation crates, the node among them' {
        $script:Read | Should -Contain 'module/foundation/node/src/declaration.rs'
        $script:Read | Should -Contain 'module/foundation/node/src/standing.rs'
    }
}
