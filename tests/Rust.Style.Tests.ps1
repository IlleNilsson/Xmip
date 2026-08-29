#requires -PSEdition Core
#requires -Version 7.6.5

<#
    docs/governance/rust-style.md states the rules. This file is what makes them
    rules rather than preferences.

    Only one thing is gated: how long a file's production code is. Function
    length is clippy's job and is a warning there, for the reason
    powershell-style.md section 6 records — a length gate produced sixteen
    waivers and caught nothing, four times consecutively.

    Findings are objects, so a failure can be grouped and sorted rather than
    read as a wall of text:

        Get-XmipRustFile | Sort-Object Code -Descending | Select-Object -First 10
#>

# At file scope, not in BeforeAll: Pester discovers test names before BeforeAll
# runs, and a name interpolating a variable set there reads as 'over  lines'.
[int] $script:MaximumFileLines = 400

BeforeAll {
    $script:Root = Join-Path $PSScriptRoot '..'
    [int] $script:MaximumFileLines = 400

    <#
        .SYNOPSIS
        Every Rust source file in the estate, with its production and test lines
        counted separately.

        .DESCRIPTION
        `modules/` and `template/`. The template is Rust that the estate ships
        and that every new repository is generated from, so a rule it does not
        obey is a rule every new repository starts out breaking.

        `target/` is build output and is excluded: it holds generated sources
        that nobody wrote and that would dominate any measurement.
    #>
    function Get-XmipRustFile {
        [CmdletBinding()]
        [OutputType([PSCustomObject])]
        param()

        $roots = @('modules', 'template') |
            ForEach-Object { Join-Path $script:Root $_ } |
            Where-Object { Test-Path -LiteralPath $_ }

        Get-ChildItem -LiteralPath $roots -Recurse -Filter '*.rs' -File |
            Where-Object { $_.FullName -notmatch '[\\/]target[\\/]' } |
            ForEach-Object {
                $lines = @(Get-Content -LiteralPath $_.FullName)

                # The line that starts the test module, or past the end when
                # there is none. Tests below it are not counted against the
                # gate — see rust-style.md section 2.
                $boundary = 1..$lines.Count |
                    Where-Object { $lines[$_ - 1] -match '^\s*#\[cfg\(test\)\]' } |
                    Select-Object -First 1

                $code = if ($boundary) { $boundary - 1 } else { $lines.Count }

                [PSCustomObject]@{
                    Path  = [IO.Path]::GetRelativePath($script:Root, $_.FullName) -replace '\\', '/'
                    Code  = $code
                    Tests = $lines.Count - $code
                    Total = $lines.Count
                }
            }
    }

    # The ratchet. rust-style.md section 4.
    #
    # May only shrink. A file here that grows fails; a file not here that
    # exceeds the gate fails; removing an entry needs no justification.
    #
    # This is not a waiver list. A waiver list absorbs new violations and its
    # own maintenance becomes the work, which is what retired the PowerShell
    # function-length gate.
    $script:Ratchet = @{
        'modules/foundation/core/src/identity.rs' = 705
        'modules/capabilities/route/src/lib.rs'   = 680
        'modules/platform/runtime/src/arrival.rs' = 440
    }

    $script:Files = @(Get-XmipRustFile)
}

Describe 'Rust style, section 1: a file has one subject' {
    It "gates every file at or under $script:MaximumFileLines lines of code" {
        $over = @(
            $script:Files |
                Where-Object { $_.Code -gt $script:MaximumFileLines } |
                Where-Object { -not $script:Ratchet.ContainsKey($_.Path) }
        )

        [string] $detail = ($over | ForEach-Object { "$($_.Path) is $($_.Code)" }) -join "`n"

        $over.Count |
            Should -Be 0 -Because "these are over the gate and not on the ratchet:`n$detail"
    }

    It 'keeps every ratcheted file from growing' {
        foreach ($path in $script:Ratchet.Keys) {
            $file = $script:Files | Where-Object Path -eq $path

            if (-not $file) {
                # Gone, split, or renamed. All three are the outcome the ratchet
                # exists to produce.
                continue
            }

            [string] $because = "$path is on the ratchet at $($script:Ratchet[$path]); a ratchet only shrinks"

            $file.Code | Should -BeLessOrEqual $script:Ratchet[$path] -Because $because
        }
    }

    It 'has no ratchet entry for a file that no longer needs one' {
        # The entry outlived the problem. Removing it is the point.
        foreach ($path in $script:Ratchet.Keys) {
            $file = $script:Files | Where-Object Path -eq $path

            if (-not $file) {
                continue
            }

            [string] $because = "$path is now $($file.Code) lines; take it off the ratchet"

            $file.Code | Should -BeGreaterThan $script:MaximumFileLines -Because $because
        }
    }
}

Describe 'Rust style, section 5: a file is named for what it defines' {
    BeforeAll {
        # The crate a file belongs to, taken from the path rather than from
        # Cargo.toml: modules/<domain>/<crate>/src/... . Reading the manifest
        # would be more correct and would also make this test depend on 43 of
        # them being parseable, which is a different test's job.
        $script:Named = $script:Files | ForEach-Object {
            $parts = $_.Path -split '/'

            [PSCustomObject]@{
                Path  = $_.Path
                Name  = [IO.Path]::GetFileNameWithoutExtension($_.Path)
                Crate = if ($parts.Count -ge 3) { $parts[2] } else { $parts[0] }
            }
        }
    }

    It 'has no file whose name repeats its crate' {
        # transport/src/transport.rs inside xmip-core-transport spent its name
        # saying where it already was.
        $stutter = @($script:Named | Where-Object { $_.Name -eq $_.Crate })

        [string] $detail = ($stutter | ForEach-Object { $_.Path }) -join "`n"

        $stutter.Count | Should -Be 0 -Because "these repeat their crate:`n$detail"
    }

    It 'uses no mod.rs' {
        # http.rs beside http/, not http/mod.rs. Five tabs called mod.rs is
        # what the 2018 form exists to stop.
        $legacy = @($script:Named | Where-Object { $_.Name -eq 'mod' })

        [string] $detail = ($legacy | ForEach-Object { $_.Path }) -join "`n"

        $legacy.Count | Should -Be 0 -Because "these use the pre-2018 form:`n$detail"
    }

    It 'reports every name used by more than one file' {
        # Not an assertion, and deliberately not one. Section 5 permits a repeat
        # when the subject is the same — xmip_core::direction and
        # xmip_transport::direction are both direction — and forbids it when it
        # is not. No test can tell those apart, so this prints them and a person
        # decides.
        #
        # The case that set the rule: three files called identity.rs holding the
        # vocabulary, the outcome of the gates, and a Party's identity.
        $repeated = $script:Named |
            Where-Object { $_.Name -ne 'lib' } |
            Group-Object Name |
            Where-Object Count -gt 1

        foreach ($group in $repeated) {
            Write-Host ("  {0}" -f $group.Name)
            $group.Group | ForEach-Object { Write-Host "      $($_.Path)" }
        }

        $script:Named.Count | Should -BeGreaterThan 0 -Because 'the estate has Rust in it'
    }
}

Describe 'Rust style, section 2: tests are measured separately' {
    It 'reports the shape of the ten largest files' {
        # Not an assertion. The same reporting Xmip.Style.Tests.ps1 does for
        # PowerShell functions: the number is more useful printed than gated.
        $script:Files |
            Sort-Object Code -Descending |
            Select-Object -First 10 |
            ForEach-Object {
                Write-Host ("  {0,-52} {1,5} code {2,5} tests" -f $_.Path, $_.Code, $_.Tests)
            }

        $script:Files.Count | Should -BeGreaterThan 0 -Because 'the estate has Rust in it'
    }

    It 'finds tests beside the code they test' {
        # rust-style.md section 2. A crate with no test module anywhere is not
        # necessarily wrong, but the estate as a whole having none would mean
        # the boundary this file measures does not exist.
        @($script:Files | Where-Object { $_.Tests -gt 0 }).Count |
            Should -BeGreaterThan 10 -Because 'tests belong in the file with their subject'
    }
}

Describe 'The style document describes what is enforced' {
    BeforeAll {
        $script:Document = Get-Content (Join-Path $script:Root 'docs/governance/rust-style.md') -Raw
    }

    It 'names this file as the thing that enforces it' {
        $script:Document | Should -Match 'tests/Rust\.Style\.Tests\.ps1'
    }

    It 'states the same gate this file enforces' {
        $script:Document | Should -Match "over $script:MaximumFileLines lines"
    }

    It 'lists every ratcheted file' {
        foreach ($path in $script:Ratchet.Keys) {
            # The document and the test must not drift. A ratchet nobody can
            # read is a waiver list with better manners.
            #
            # Both sets of parentheses are load-bearing. Without the inner pair
            # PowerShell reads the comma as an argument separator and hands
            # Escape two arguments, which has no overload.
            [string] $relative = ($path -replace '^modules/', '')

            $script:Document | Should -Match ([regex]::Escape($relative))
        }
    }
}
