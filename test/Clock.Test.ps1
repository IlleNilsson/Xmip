#requires -PSEdition Core
#requires -Version 7.7.0

<#
    One clock (ADR-0068, amendment 2026-11-14): every wall-clock reading in
    the estate's production code is `xcore::Clock`'s, and the one production
    Clock, `xcore::SystemClock` in module/foundation/core/src/clock.rs, holds
    the one `SystemTime::now()`. Until 2026-11-14 sixteen files read the
    operating system's clock each its own way — a claimed name, a signature's
    date, a file's write time, an archived item's moment — and a library,
    `codec::civil`, read it too, under a calendar that should only convert.
    A moment is a parameter everywhere below the reading: a test pins the
    moment, or hands in a Clock of its own.

    Production code only: a file's tests, from its first `#[cfg(test)]` line
    down, are `Get-XmipSourceFile`'s `Code` boundary, and a file under
    `tests/`, `test/`, `fixture/` or `measured/`, or named for one, is a
    test's own. The wall clock alone: the monotonic clock, `Instant::now()`,
    is not held here.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    # The one production Clock.
    [string] $script:Clock = 'module/foundation/core/src/clock.rs'

    # A reading of the operating system's wall clock.
    [string] $script:Reading = '\bSystemTime::now\s*\('

    # A test's own file: an integration test, the root's test tree, a
    # fixture, a timing program, or a test module in a file of its own.
    [string] $script:TestOwn = '(^|/)(tests?|fixture|measured)(/|\.rs$)'

    <#
        .SYNOPSIS
        Each production line of `Line`, a file at `Path`, that reads the wall
        clock, as `path:line`.
    #>
    function Find-XmipClockReading {
        [CmdletBinding()]
        [OutputType([string[]])]
        param(
            [Parameter(Mandatory = $true)]
            [string] $Path,

            [Parameter(Mandatory = $true)]
            [AllowEmptyCollection()]
            [AllowEmptyString()]
            [string[]] $Line
        )

        for ([int] $index = 0; $index -lt $Line.Count; $index++) {
            [string] $code = $Line[$index]

            if ($code.TrimStart().StartsWith('//')) {
                continue
            }

            if ($code -match $script:Reading) {
                "${Path}:$($index + 1)"
            }
        }
    }

    $script:Found = @(
        foreach ($file in @(Get-XmipSourceFile -Root $script:Root -Language Rust)) {
            if ($file.Code -eq 0 -or $file.Path -eq $script:Clock -or
                $file.Path -match $script:TestOwn) {
                continue
            }

            [string] $full = Join-Path $script:Root $file.Path
            [string[]] $line = @(Get-Content -LiteralPath $full -TotalCount $file.Code)
            Find-XmipClockReading -Path $file.Path -Line $line
        }
    )
}

Describe 'The estate reads the wall clock in one place' {
    It 'reads SystemTime::now() in no production code but xcore::SystemClock' {
        [string] $detail = $script:Found -join "`n"

        $script:Found.Count | Should -Be 0 -Because (
            "a wall-clock reading is xcore::Clock's: call SystemClock, or the " +
            "Clock handed in, and pass the moment down:`n$detail"
        )
    }

    It 'holds the one reading in the one production Clock' {
        [string] $full = Join-Path $script:Root $script:Clock
        [string[]] $line = @(Get-Content -LiteralPath $full)

        @(Find-XmipClockReading -Path $script:Clock -Line $line).Count |
            Should -Be 1 -Because 'SystemClock reads the operating system''s clock once'
    }

    It 'finds a reading when there is one, so the gate is not silent by accident' {
        [string[]] $sample = @(
            'let now = std::time::SystemTime::now();'
            '    amz_date(SystemTime::now())'
            '// SystemTime::now() in a comment is no reading'
            'let started = Instant::now();'
            'let at = SystemClock.unix_seconds();'
        )

        @(Find-XmipClockReading -Path 'module/x/src/lib.rs' -Line $sample) |
            Should -Be @('module/x/src/lib.rs:1', 'module/x/src/lib.rs:2')
        'module/x/tests/measured/main.rs' | Should -Match $script:TestOwn
        'module/x/.src/fixture/crowd.rs' | Should -Match $script:TestOwn
        'module/x/src/storage/commit/tests.rs' | Should -Match $script:TestOwn
        'module/x/src/contest.rs' | Should -Not -Match $script:TestOwn
    }
}
