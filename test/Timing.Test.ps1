#requires -PSEdition Core
#requires -Version 7.7.0

<#
    A timing test runs alone, in its module's timing program
    (doc/governance/rust-style.md section 5c): the cargo test target
    `measured`, declared with `test = false`, which the landing runs after
    the module's other tests with one test thread (Test-XmipMeasuredProgram).
    Until 2026-11-01 those tests ran inside each module's parallel suite,
    whose other tests slowed the measured work 1.5 to 3 times, and landings
    failed at random on them.

    This holds the rule: a timing assertion in a module's tests sits in a
    `measured` folder, the timing program's, or the test fails naming it.
    What reads as one, in a file's tests (from its first `#[cfg(test)]` on,
    or a whole file under `tests/` or `.src/test/`), is an `assert!` whose
    condition holds a measured time under a bound below a second:

    - an upper bound (`<` or `<=`) against `Duration::from_millis` of less
      than a thousand or of a figure computed, or `from_micros` or
      `from_nanos`, or a figure read as `as_millis()`, `as_micros()` or
      `as_nanos()`;
    - an upper bound on a fastest of five (`fastest_of_five`, the millisecond
      rule's figure, `xcore::latency`);

    and any call of `xcore::latency::at_once`, whose answer is only ever
    held to such a bound. A lower bound alone, or a bound of a second or
    more, proves a wait or a give-up and stays where it is.
    `module/foundation/core/src/latency.rs` is the instrument itself, its
    tests its own arithmetic.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    # The condition of an assertion: its text up to its message.
    [string] $script:Bound = '\s<=?\s'
    [string] $script:Measured = (
        '\.fastest_of_five\b|Duration::from_millis\(\s*(?!\d{4}|\d{1,3}_\d{3})|' +
        'Duration::from_(micros|nanos)\(|\.as_(millis|micros|nanos)\(\)'
    )

    # The instrument's own tests: its arithmetic, not a time held.
    [string[]] $script:Instrument = @('module/foundation/core/src/latency.rs')

    <#
        .SYNOPSIS
            Where in `Line` a file's tests begin: its first `#[cfg(test)]`, or
            the top of a file that is all test.
    #>
    function Get-TestStart([string] $Path, [string[]] $Line) {
        if ($Path -match '(^|/)(tests|test)/') {
            return 0
        }

        for ([int] $index = 0; $index -lt $Line.Count; $index++) {
            if ($Line[$index] -match '^\s*#\[cfg\(test\)\]') {
                return $index
            }
        }

        return $Line.Count
    }

    <#
        .SYNOPSIS
            Each timing assertion in a file's tests, as `path:line`.
    #>
    function Find-TimingAssertion([string] $Path, [string[]] $Line) {
        [string] $text = ''
        [int] $at = 0
        [int] $depth = 0

        for ([int] $index = (Get-TestStart $Path $Line); $index -lt $Line.Count; $index++) {
            [string] $code = $Line[$index] -replace '//.*$', ''

            if ($code -match '\bat_once\(') {
                "${Path}:$($index + 1)"
            }

            if ($depth -eq 0) {
                if ($code -notmatch '\bassert!\(') {
                    continue
                }

                $text = ''
                $at = $index
                $code = $code.Substring($code.IndexOf('assert!('))
            }

            $text += " $code"
            $depth += ([regex]::Matches($code, '\(')).Count - ([regex]::Matches($code, '\)')).Count

            if ($depth -le 0 -or $code -match ';\s*$') {
                $depth = 0
                [string] $condition = ($text -split ',\s*"')[0]

                if ($condition -match $script:Bound -and $condition -match $script:Measured) {
                    "${Path}:$($at + 1)"
                }
            }
        }
    }

    # The estate's Rust: the composed trees, and the root's own sources.
    [string[]] $script:Paths = @(
        Get-XmipSourceFile -Root $script:Root -Language Rust | ForEach-Object -MemberName Path
        Get-ChildItem -LiteralPath (Join-Path $script:Root '.src') -Recurse -Filter '*.rs' -File |
            ForEach-Object {
                [IO.Path]::GetRelativePath($script:Root, $_.FullName) -replace '\\', '/'
            }
    )
}

Describe 'A timing test runs alone, in its module''s measured program' {
    It 'holds no timing assertion outside a measured program' {
        [string[]] $outside = @(
            foreach ($path in $script:Paths) {
                if ($path -match '(^|/)measured/' -or $script:Instrument -contains $path) {
                    continue
                }

                [string[]] $line = @(Get-Content -LiteralPath (Join-Path $script:Root $path))
                Find-TimingAssertion $path $line
            }
        )

        [string] $because = "each belongs in its module's measured program (rust-style.md 5c):`n" +
            ($outside -join "`n")
        $outside.Count | Should -Be 0 -Because $because
    }

    It 'finds a timing assertion when there is one, so the gate is not silent by accident' {
        [string[]] $test = @(
            '#[cfg(test)]'
            'mod tests {'
            '    fn one() {'
            '        assert!('
            '            took.fastest_of_five < Duration::from_millis(1) + usual,'
            '            "{took:?}"'
            '        );'
            '        assert!(each < Duration::from_millis(SENDS as u64), "{each:?}");'
            '        assert!(waited < Duration::from_secs(2), "a give-up within seconds");'
            '        assert!(waited >= Duration::from_millis(150), "a lower bound");'
            '        let (_, fastest, _) = at_once("asked again", || ask());'
            '    }'
            '}'
        )

        @(Find-TimingAssertion 'module/x/src/lib.rs' $test) |
            Should -Be @('module/x/src/lib.rs:4', 'module/x/src/lib.rs:8', 'module/x/src/lib.rs:11')
    }

    It 'declares every measured program with test = false' {
        # A program's main file, and the crate it is the program of.
        [string] $program = '/?(tests/measured|\.src/test/measured)/main\.rs$'
        [string[]] $manifests = @(
            $script:Paths |
                Where-Object { $_ -match $program } |
                ForEach-Object {
                    [string] $crate = $_ -replace $program, ''
                    if ($crate) { "$crate/Cargo.toml" } else { 'Cargo.toml' }
                }
        )

        $manifests.Count | Should -BeGreaterThan 0
        foreach ($manifest in $manifests) {
            [string] $declared = InModuleScope Xmip -Parameters @{
                Path = (Join-Path $script:Root $manifest)
            } {
                Get-XmipMeasuredDeclaration -ManifestPath $Path
            }

            $declared | Should -Match '(?m)^test\s*=\s*false\s*$' -Because $manifest
        }
    }
}
