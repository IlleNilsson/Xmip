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

    The monotonic clock (ADR-0068, amendment 2026-11-15): a decision counts
    its span on the monotonic reading of the Clock it was handed, so a test
    steps `xcore::clock::Stepped` past it with no sleep; a wait the
    operating system makes, and a span only reported, read std's `Instant`.
    Each file whose decisions were moved onto the Clock holds no
    `Instant` at all, and the estate's other `Instant::now` readings are
    counted: the count may fall as the decisions move, and may not rise.
    SystemClock's origin, its one reading, is not counted.

    Production code only: a file's tests, from its first `#[cfg(test)]` line
    down, are `Get-XmipSourceFile`'s `Code` boundary, and a file under
    `tests/`, `test/`, `fixture/` or `measured/`, or named for one, is a
    test's own.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    # The one production Clock.
    [string] $script:Clock = 'module/foundation/core/src/clock.rs'

    # A reading of the operating system's wall clock.
    [string] $script:Reading = '\bSystemTime::now\s*\('

    # A reading of the operating system's monotonic clock: a call, or the
    # function handed on, as SystemClock's origin is.
    [string] $script:Monotonic = '\bInstant::now\b'

    # std's Instant at all: what a file whose decisions read the Clock holds
    # none of.
    [string] $script:Instant = '\bInstant\b'

    # The production Instant::now readings outside SystemClock on
    # 2026-11-16, once the resilience guards', Xmip Storage's client's and
    # standby's, net's watched connection and HTTP/2 tally's, the cluster's
    # sync plane's, the transports' turn deadline's, the runtime's own and
    # an operate surface's decisions read the Clock (148 before the last
    # four, 121 before the send step's, 97 before a surface's). A ratchet:
    # lower it as the decisions move (ADR-0068, amendments 2026-11-15 and
    # 2026-11-16); never raise it.
    [int] $script:MonotonicCeiling = 94

    # The files whose decisions read the Clock handed in (ADR-0068,
    # amendments 2026-11-15 and 2026-11-16): none reads std's Instant.
    # `net` is a Library and reads no clock: its watched connection and
    # HTTP/2 tally take the reading their caller made.
    [string[]] $script:Decides = @(
        'module/core/capability/resilience/circuit-breaker/src/lib.rs'
        'module/core/capability/resilience/rate-limit/src/lib.rs'
        'module/platform/persist/.src/storage/client.rs'
        'module/platform/persist/.src/storage/standby/follow.rs'
        'module/core/library/net/src/watched.rs'
        'module/core/library/net/src/http2/connection.rs'
        'module/core/library/net/src/http2/limits.rs'
        'module/core/library/net/src/http2/receive.rs'
        'module/platform/cluster/src/sync/serving.rs'
        'module/platform/cluster/src/sync/upstream.rs'
        'module/core/capability/transport/.src/deadline.rs'
        'module/platform/runtime/src/departure.rs'
        'module/platform/runtime/src/pickup/released.rs'
        'module/platform/runtime/src/pickup/state.rs'
        'module/platform/runtime/src/plane/follow.rs'
        'module/platform/runtime/src/plane/fresh.rs'
        'module/platform/runtime/src/plane/line.rs'
        'module/platform/runtime/src/plane/remote/asking.rs'
        'module/platform/runtime/src/plane/remote/fresh.rs'
        'module/platform/runtime/src/plane/shared.rs'
        'module/platform/runtime/src/running/revocation_list.rs'
        'module/platform/runtime/src/sending.rs'
        'module/platform/runtime/src/stream_share.rs'
        'module/platform/runtime/src/stream_share/one_read.rs'
        'module/platform/runtime/src/work_step/dispatch.rs'
        'module/core/capability/schedule/src/due.rs'
        'module/platform/runtime/src/held_work.rs'
        'module/platform/runtime/src/queue_watch.rs'
        'module/platform/runtime/src/send_step.rs'
        'module/platform/runtime/src/send_step/behind.rs'
        'module/platform/runtime/src/send_step/dispatch.rs'
        'module/platform/runtime/src/send_step/due.rs'
        'module/platform/runtime/src/send_step/figures.rs'
        'module/platform/runtime/src/send_step/reading.rs'
        'module/platform/runtime/src/send_step/renewal.rs'
        'module/platform/runtime/src/send_step/scan.rs'
        'module/platform/runtime/src/send_step/settles.rs'
        'module/platform/runtime/src/send_step/under_claim.rs'
    )

    # A test's own file: an integration test, the root's test tree, a
    # fixture, a timing program, or a test module in a file of its own.
    [string] $script:TestOwn = '(^|/)(tests?|fixture|measured)(/|\.rs$)'

    <#
        .SYNOPSIS
        Each production line of `Line`, a file at `Path`, that matches
        `Pattern`, as `path:line`.
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
            [string[]] $Line,

            [Parameter(Mandatory = $true)]
            [string] $Pattern
        )

        for ([int] $index = 0; $index -lt $Line.Count; $index++) {
            [string] $code = $Line[$index]

            if ($code.TrimStart().StartsWith('//')) {
                continue
            }

            if ($code -match $Pattern) {
                "${Path}:$($index + 1)"
            }
        }
    }

    $script:Found = [System.Collections.Generic.List[string]]::new()
    $script:Counted = [System.Collections.Generic.List[string]]::new()
    $script:Held = @{}

    foreach ($file in @(Get-XmipSourceFile -Root $script:Root -Language Rust)) {
        if ($file.Code -eq 0 -or $file.Path -eq $script:Clock -or
            $file.Path -match $script:TestOwn) {
            continue
        }

        [string] $full = Join-Path $script:Root $file.Path
        [string[]] $line = @(Get-Content -LiteralPath $full -TotalCount $file.Code)
        $script:Found.AddRange([string[]] @(
                Find-XmipClockReading -Path $file.Path -Line $line -Pattern $script:Reading
            ))
        $script:Counted.AddRange([string[]] @(
                Find-XmipClockReading -Path $file.Path -Line $line -Pattern $script:Monotonic
            ))

        if ($file.Path -in $script:Decides) {
            $script:Held[$file.Path] = @(
                Find-XmipClockReading -Path $file.Path -Line $line -Pattern $script:Instant
            )
        }
    }
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

        @(Find-XmipClockReading -Path $script:Clock -Line $line -Pattern $script:Reading).Count |
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
        [string] $path = 'module/x/src/lib.rs'

        @(Find-XmipClockReading -Path $path -Line $sample -Pattern $script:Reading) |
            Should -Be @("${path}:1", "${path}:2")
        'module/x/tests/measured/main.rs' | Should -Match $script:TestOwn
        'module/x/.src/fixture/crowd.rs' | Should -Match $script:TestOwn
        'module/x/src/storage/commit/tests.rs' | Should -Match $script:TestOwn
        'module/x/src/contest.rs' | Should -Not -Match $script:TestOwn
    }
}

Describe 'A decision reads the Clock it was handed, not the monotonic clock' {
    It 'reads no Instant in a file whose decisions read the Clock' {
        [string[]] $missing = @(
            $script:Decides | Where-Object { -not $script:Held.ContainsKey($_) }
        )
        [string[]] $read = @($script:Held.Values | ForEach-Object { $_ })

        $missing | Should -BeNullOrEmpty -Because 'each file held is production code'
        $read | Should -BeNullOrEmpty -Because (
            "a decision counts its span on the Clock handed in, " +
            "Clock::monotonic_nanos with xcore::clock::between and nanos:`n" +
            ($read -join "`n")
        )
    }

    It 'reads Instant::now no more often than the ratchet allows' {
        Write-Host "  production code reads Instant::now $($script:Counted.Count) times"

        $script:Counted.Count | Should -BeLessOrEqual $script:MonotonicCeiling -Because (
            'a new decision reads the Clock handed in, and a wait or a reported span ' +
            'that reads Instant replaces one, never adds one: lower the ceiling as they move'
        )
    }

    It 'holds the one monotonic reading of the one production Clock, its origin' {
        [string] $full = Join-Path $script:Root $script:Clock
        [string[]] $line = @(Get-Content -LiteralPath $full)

        @(Find-XmipClockReading -Path $script:Clock -Line $line -Pattern $script:Monotonic).Count |
            Should -Be 1 -Because 'SystemClock counts its monotonic reading from one origin'
    }

    It 'finds a monotonic reading when there is one, so the gate is not silent by accident' {
        [string[]] $sample = @(
            'let started = Instant::now();'
            '    std::sync::LazyLock::new(std::time::Instant::now);'
            '// Instant::now() in a comment is no reading'
            'let now = clock.monotonic_nanos();'
            'heard: Instant,'
        )
        [string] $path = 'module/x/src/lib.rs'

        @(Find-XmipClockReading -Path $path -Line $sample -Pattern $script:Monotonic) |
            Should -Be @("${path}:1", "${path}:2")
        @(Find-XmipClockReading -Path $path -Line $sample -Pattern $script:Instant) |
            Should -Be @("${path}:1", "${path}:2", "${path}:5")
    }
}
