#requires -PSEdition Core
#requires -Version 7.6.5

<#
    doc/governance/rust-style.md states the rules. This file is what makes them
    rules rather than preferences.

    Only one thing is gated: how long a file's production code is. Function
    length is clippy's job and is a warning there, for the reason
    powershell-style.md section 6 records — a length gate produced sixteen
    waivers and caught nothing, four times consecutively.

    Findings are objects, so a failure can be grouped and sorted rather than
    read as a wall of text:

        Get-XmipSourceFile -Language Rust |
            Sort-Object Code -Descending | Select-Object -First 10
#>

# At file scope, not in BeforeAll: Pester discovers test names before BeforeAll
# runs, and a name interpolating a variable set there reads as 'over  lines'.
[int] $script:MaximumFileLines = 400

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')
    [int] $script:MaximumFileLines = 400

    # The counter used to live here, where nothing else could reach it, and
    # the estate map needed the same number. Two counters disagree within a
    # week — ADR-0020 clause 5 — so it moved into the module and this calls
    # it. `Get-XmipSourceFile` reads `module/`, `test/`, `template/` and
    # `sdk/`, and the template is Rust every new repository is generated
    # from, so a rule it breaks is a rule every new repository starts out
    # breaking.
    $script:Files = @(Get-XmipSourceFile -Root $script:Root -Language Rust)
}

Describe 'Rust style, section 1: a file has one subject' {
    It "gates every file at or under $script:MaximumFileLines lines of code" {
        $over = @($script:Files | Where-Object { $_.Code -gt $script:MaximumFileLines })

        [string] $detail = ($over | ForEach-Object { "$($_.Path) is $($_.Code)" }) -join "`n"

        $over.Count | Should -Be 0 -Because "these are over the gate:`n$detail"
    }
}

Describe 'Rust style, section 5: a file is named for what it defines' {
    BeforeAll {
        # The crate a file belongs to, taken from the path rather than from
        # Cargo.toml: module/<domain>/<crate>/src/... for what starts a node,
        # module/<provider>/<domain>/<crate>/src/... otherwise. Reading the manifest
        # would be more correct and would also make this test depend on every one of
        # them being parseable, which is a different test's job.
        $script:Named = $script:Files | ForEach-Object {
            $parts = $_.Path -split '/'

            [PSCustomObject]@{
                Path  = $_.Path
                Name  = [IO.Path]::GetFileNameWithoutExtension($_.Path)
                Crate = if ($parts[0] -eq 'sdk') { 'sdk' }
                        elseif ($parts[0] -eq 'module' -and
                            $parts[1] -notin 'foundation', 'platform' -and
                            $parts.Count -ge 4) { $parts[3] }
                        elseif ($parts.Count -ge 3) { $parts[2] }
                        else { $parts[0] }
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
        # Not an assertion. The same reporting Xmip.Style.Test.ps1 does for
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
        $script:Document = Get-Content (Join-Path $script:Root 'doc/governance/rust-style.md') -Raw
    }

    It 'names this file as the thing that enforces it' {
        $script:Document | Should -Match 'test/Rust\.Style\.Test\.ps1'
    }

    It 'states the same gate this file enforces' {
        $script:Document | Should -Match "over $script:MaximumFileLines lines"
    }
}

Describe 'ADR-0021: one edition, and the manifest knows which' {
    BeforeAll {
        $manifest = Get-XmipManifest -Path (Join-Path $script:Root 'architecture.toml')

        [string] $script:Declared = $manifest.crate.edition

        # Every crate the estate ships: the modules, the template every new
        # repository is generated from, and the platform crate that assembles
        # them. Build output and the working areas are never walked.
        [System.IO.FileInfo[]] $script:Crate = @(
            InModuleScope Xmip -Parameters @{ Root = $script:Root } {
                param($Root)
                Find-XmipFile -Path $Root -Filter 'Cargo.toml'
            }
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

    It 'builds dependencies optimized in every workspace root' {
        # rust-style.md section 5b (the owner, 2026-09-26): a debug build of
        # the codec's base64 took seconds where a release build took
        # milliseconds, and tests timed out for it. A workspace root is the
        # only place a profile is read, so every one carries it.
        [string[]] $missing = @()

        foreach ($file in $script:Crate) {
            [string] $text = Get-Content -LiteralPath $file.FullName -Raw

            if ($text -notmatch '(?m)^\[workspace\]' -or $text -notmatch '(?m)^\[package\]') {
                continue
            }

            if ($text -notmatch '(?m)^\[profile\.dev\.package\."\*"\]\s*\r?\nopt-level\s*=\s*3') {
                $missing += $file.FullName.Replace($script:Root, '').TrimStart('\', '/')
            }
        }

        $missing.Count | Should -Be 0 -Because ($missing -join "`n")
    }
}
