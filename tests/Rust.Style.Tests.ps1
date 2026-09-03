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

    # The ratchet, rust-style.md section 4. Empty, which is the intended state.
    #
    # Length is a strict recommendation: a file that must be longer may be
    # longer, with the owner's agreement first and the reason recorded here as
    # @{ Lines = <n>; Reason = '<why>' }. An entry with no reason cannot be
    # told from a file nobody got round to splitting, and a reason composed
    # after the fact is a defence, not a reason — arrival.rs stood on one for
    # a day and was split instead (347 + outcome.rs at 113, 2026-08-30).
    #
    # Three entries have come and gone, none needing an argument to remove:
    #
    #   foundation/core/src/identity.rs   705 -> seven files, largest 240
    #   capabilities/route/src/lib.rs     680 -> six files, largest 274
    #   platform/runtime/src/arrival.rs   440 -> split, above
    $script:Ratchet = @{ }

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

            [int] $allowed = $script:Ratchet[$path].Lines
            [string] $because =
                "$path is recorded at $allowed lines; growing past it is a deliberate edit"

            $file.Code | Should -BeLessOrEqual $allowed -Because $because
        }
    }

    It 'gives every recorded exception a reason' {
        # Length is a strict recommendation. Breaking it is allowed and costs a
        # sentence, which is what keeps it rare — the same instrument as
        # [[retired]] in architecture.toml, where a reason is required because
        # an entry without one cannot be told from an oversight.
        foreach ($path in $script:Ratchet.Keys) {
            [string] $why = "$path exceeds the recommendation and must say why"

            $script:Ratchet[$path].Reason | Should -Not -BeNullOrEmpty -Because $why

            ($script:Ratchet[$path].Reason).Length |
                Should -BeGreaterThan 30 -Because "$path needs a reason, not a word"
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
            $script:Document | Should -Match 'strict recommendation'
        }
    }
}

Describe 'ADR-0021: one edition, and the manifest knows which' {
    BeforeAll {
        [string] $script:Root = Join-Path $PSScriptRoot '..'

        Import-Module PSToml -ErrorAction Stop

        [hashtable] $script:Manifest =
            Get-Content -LiteralPath (Join-Path $script:Root 'architecture.toml') -Raw |
                ConvertFrom-Toml

        [string] $script:Declared = $script:Manifest.crate.edition

        # Every crate the estate ships: the modules, the template every new
        # repository is generated from, and the platform crate that assembles
        # them. target/ is build output and holds vendored manifests that
        # nobody here wrote.
        [System.IO.FileInfo[]] $script:Crate = @(
            Get-ChildItem -Path $script:Root -Filter 'Cargo.toml' -Recurse -File |
                Where-Object { $_.FullName -notmatch '[\/]target[\/]' } |
                Sort-Object FullName
        )
    }

    It 'declares an edition in the manifest' {
        # The manifest is where the estate says what its crates are. A crate
        # policy that names no edition cannot be checked against anything.
        [string]::IsNullOrWhiteSpace($script:Declared) | Should -BeFalse
    }

    It 'gives every crate the edition the manifest declares' {
        # On 2026-09-03 the manifest said 2021 and thirty-eight of thirty-nine
        # crates were 2024. It had been "corrected" to 2021 that same day, on
        # the grounds that it matched the root Cargo.toml — which it did, and
        # which was the only crate it matched.
        #
        # Open problem 3 was closed twice on that reading. This is what stops
        # it being closed a third time: the manifest is checked against the
        # estate, not against one crate.
        [string[]] $wrong = @()

        foreach ($file in $script:Crate) {
            [string] $text = Get-Content -LiteralPath $file.FullName -Raw

            if ($text -notmatch '(?m)^edition\s*=\s*"([^"]+)"') {
                continue
            }

            if ($Matches[1] -ne $script:Declared) {
                [string] $where = $file.FullName.Replace($script:Root, '').TrimStart('\', '/')

                $wrong += "$where is $($Matches[1])"
            }
        }

        [string] $because = "the manifest declares $($script:Declared):`n$($wrong -join "`n")"

        $wrong.Count | Should -Be 0 -Because $because
    }
}
