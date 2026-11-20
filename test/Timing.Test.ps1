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
    - an upper bound a constant makes, `< WAIT * 3` and the like, whose value
      is under a second: each name in it resolved to the `const` or the
      `let` of the file that declares it, or to the estate's one `const` of
      that name where every declaration agrees, and the arithmetic done;

    and any call of `xcore::latency::at_once`, whose answer is only ever
    held to such a bound, or of `xcore::latency::Rounds::crossing`, whose
    rounds are held to one, or of `worked_beside_a_plain_wake` or
    `woke_beside_a_plain_wake`, which each hold a figure to one, or of
    `xcore::spent::Spent::begin`, an account a test opens only to hold an
    own share to a time, whatever it is held beside (2026-11-20: the
    archive's first write was held so in its crate's parallel suite, within
    a millisecond of the writes after it, and nothing here read it). A lower
    bound alone, or a bound of a second or more — its value worked out as
    above, at least a million microseconds — proves a wait or a give-up and
    stays where it is, an outcome check. A bound that names anything else —
    a figure measured beside it, a method, a name no file resolves — is not a
    constant and is left alone.

    And inside a timing program, every time held under a constant bound
    below a second is held by the fastest of five or beside what it is
    measured against (rust-style.md 5c, 2026-11-15): its clause names a
    fastest (`fastest_of_five`, or a figure named so), or a figure a `let` took
    from one — from `at_once`, from a function of the file that holds a
    fastest, or as a difference with another measured figure — or the test
    fails naming it. A single sample, a batch timed together, a mean or a
    median under a constant bound fails it.
    `module/foundation/core/src/latency.rs` is the instrument itself, its
    tests its own arithmetic, and so is `spent.rs` beside it; so are its timing program's
    `processor_time.rs` and `spent.rs`, which hold a spin counted by its own
    processor time to
    what it counts, which no load reaches.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    # The condition of an assertion: its text up to its message.
    [string] $script:Bound = '\s<=?\s'
    [string] $script:Measured = (
        '\.fastest_of_five\b|Duration::from_millis\(\s*(?!\d{4}|\d{1,3}_\d{3})|' +
        'Duration::from_(micros|nanos)\(|\.as_(millis|micros|nanos)\(\)'
    )

    # The instruments' own tests: their arithmetic, not a time held.
    [string[]] $script:Instrument = @(
        'module/foundation/core/src/latency.rs'
        'module/foundation/core/src/spent.rs'
        'module/foundation/core/tests/measured/processor_time.rs'
        'module/foundation/core/tests/measured/spent.rs'
    )

    # A second, a millisecond, a microsecond and a nanosecond in microseconds,
    # written as Rust's arithmetic reads them whatever the culture.
    [hashtable] $script:Unit = @{ secs = 1000000; millis = 1000; micros = 1; nanos = 0.001 }
    [cultureinfo] $script:Invariant = [cultureinfo]::InvariantCulture

    # The types of a constant a bound is worked out from: a Duration or a number.
    [string] $script:Typed = '^((std::time::)?Duration|[uif](8|16|32|64|128|size))$'

    # A constant on one line: its name, its type and its expression.
    [string] $script:Declared = (
        '^\s*(pub(\([\w:]+\))?\s+)?const\s+(?<name>\w+)\s*:\s*(?<type>[^=]+?)\s*=\s*' +
        '(?<text>.+?);'
    )

    # A `let` of a Duration made from a literal.
    [string] $script:DurationLet = (
        '^\s*let\s+(mut\s+)?(?<name>\w+)\s*(:\s*[\w:]+\s*)?=\s*' +
        '(?<text>(std::time::)?Duration::from_\w+\([^;]*\));'
    )

    # A test, or a hold in one, that only a build without debug assertions runs:
    # the estate builds its tests with them on (`.cargo/config.toml`, rust-style.md
    # section 5b), so it never runs. Until 2026-11-15 two of the runtime's
    # timing holds sat behind one.
    [string] $script:ReleaseOnly = (
        '!\s*cfg!\(\s*debug_assertions\s*\)|cfg!\(\s*not\s*\(\s*debug_assertions\s*\)\s*\)|' +
        '\bif\s+cfg!\(\s*debug_assertions\s*\)|#\[\s*cfg\s*\(\s*not\s*\(\s*debug_assertions|' +
        '#\[\s*cfg_attr\s*\(\s*debug_assertions\s*,\s*ignore'
    )

    # A clause of a fastest of five, or of a figure a `let` took from one.
    [string] $script:Fastest = 'fastest|\bat_once\(|saturating_sub\(\s*[a-z_]|abs_diff\(\s*[a-z_]'

    <#
        .SYNOPSIS
            Where in `Line` a file's tests begin: its first `#[cfg(test)]`, or
            the top of a file that is all test. With `Module`, the first
            `#[cfg(test)]` that opens a module, past any attribute after it:
            production code opens an account (`Spent::begin`), and a test
            item's own `#[cfg(test)]` above it does not make it a test's.
    #>
    function Get-TestStart([string] $Path, [string[]] $Line, [switch] $Module) {
        if ($Path -match '(^|/)(tests|test)/') {
            return 0
        }

        for ([int] $index = 0; $index -lt $Line.Count; $index++) {
            if ($Line[$index] -notmatch '^\s*#\[cfg\(test\)\]') {
                continue
            }

            [int] $next = $index + 1
            while ($Module -and $next -lt $Line.Count -and $Line[$next] -match '^\s*#\[') {
                $next++
            }

            [bool] $opens = $next -lt $Line.Count -and
                $Line[$next] -match '^\s*(pub(\([\w:]+\))?\s+)?mod\s'
            if (-not $Module -or $opens) {
                return $index
            }
        }

        return $Line.Count
    }

    <#
        .SYNOPSIS
            Each `assert!` from `Start` on in `Line`: the index of its first line,
            and its condition, the text before its message, split at `&&` and
            `||` into clauses.
    #>
    function Get-Assertion([string[]] $Line, [int] $Start) {
        [string] $text = ''
        [int] $at = 0
        [int] $depth = 0

        for ([int] $index = $Start; $index -lt $Line.Count; $index++) {
            [string] $code = $Line[$index] -replace '//.*$', ''

            if ($depth -eq 0) {
                if ($code -notmatch '\bassert!\(') {
                    continue
                }

                $text = ''
                $at = $index
                $code = $code.Substring($code.IndexOf('assert!(') + 'assert!('.Length)
                $depth = 1
            }

            $text += " $code"
            $depth += ([regex]::Matches($code, '\(')).Count - ([regex]::Matches($code, '\)')).Count

            if ($depth -le 0 -or $code -match ';\s*$') {
                $depth = 0
                [string] $condition = (($text -split ',\s*"')[0] -replace '\)\s*;\s*$', '').Trim()
                [pscustomobject] @{ At = $at; Clause = @($condition -split '&&|\|\|') }
            }
        }
    }

    <#
        .SYNOPSIS
            The constants `Line` declares by name, each `const` on one line and
            each `let` of a Duration made from a literal: its type and its text.
    #>
    function Get-Constant([string[]] $Line) {
        [hashtable] $found = @{}

        foreach ($code in $Line) {
            if ($code -match $script:Declared) {
                $found[$Matches['name']] = @{ Type = $Matches['type']; Text = $Matches['text'] }
            }
            elseif ($code -match $script:DurationLet) {
                $found[$Matches['name']] = @{ Type = 'Duration'; Text = $Matches['text'] }
            }
        }

        return $found
    }

    <#
        .SYNOPSIS
            What `Text` comes to in microseconds where it is a constant, its names
            resolved in `Local`, else in the estate's: `Micros`, and `Time`, whether
            it is a Duration; $null where anything in it is not a constant.
    #>
    function Measure-Bound([string] $Text, [hashtable] $Local, [int] $Depth = 0) {
        if ($Depth -gt 8) {
            return $null
        }

        [string] $expression = $Text -replace '(std|core)::time::', '' -replace '(?<=\d)_(?=\d)', ''
        $expression = $expression -replace '\s+as\s+[uif](8|16|32|64|128|size)\b', ''
        $expression = $expression -replace '(?<=\d)[ui](8|16|32|64|128|size)\b', ''
        [bool] $time = $expression -match 'Duration::'
        $expression = $expression -replace 'Duration::ZERO', '(0)'

        while ($expression -match 'Duration::from_(secs|millis|micros|nanos)\(([^()]*)\)') {
            [string] $unit = ([double] $script:Unit[$Matches[1]]).ToString($script:Invariant)
            $expression = $expression.Replace($Matches[0], "(($($Matches[2]))*$unit)")
        }

        if ($expression -match 'Duration::|\.[A-Za-z_]|\[') {
            return $null
        }

        $expression = $expression -replace '\b[A-Za-z_]\w*::', ''
        [string[]] $names = @(
            [regex]::Matches($expression, '\b[A-Za-z_]\w*\b') | ForEach-Object -MemberName Value |
                Sort-Object -Unique
        )
        foreach ($name in $names) {
            [hashtable] $known = Find-Constant -Name $name -Local $Local
            if ($null -eq $known -or $known.Type -notmatch $script:Typed) {
                return $null
            }

            $value = Measure-Bound -Text $known.Text -Local $Local -Depth ($Depth + 1)
            if ($null -eq $value) {
                return $null
            }

            $time = $time -or $known.Type -match 'Duration'
            [string] $micros = ([double] $value.Micros).ToString($script:Invariant)
            $expression = $expression -replace "\b$name\b", "($micros)"
        }

        if ($expression -notmatch '^[\d\s\.\+\-\*/\(\)]+$') {
            return $null
        }

        try {
            [double] $micros = [System.Data.DataTable]::new().Compute($expression, '')
        }
        catch {
            return $null
        }

        return @{ Micros = $micros; Time = $time }
    }

    <#
        .SYNOPSIS
            The constant `Name` names: the file's own where `Local` declares it,
            else the estate's one.
    #>
    function Find-Constant([string] $Name, [hashtable] $Local) {
        if ($Local.ContainsKey($Name)) {
            return $Local[$Name]
        }

        return $script:Estate[$Name]
    }

    <#
        .SYNOPSIS
            The bound in microseconds that `Clause` holds a time under, where a
            constant makes it; $null where it is no upper bound, or no constant,
            or not a time.
    #>
    function Get-ConstantBound([string] $Clause, [hashtable] $Local) {
        if ($Clause -notmatch '^(?<left>.*?)\s<=?\s(?<right>.*)$') {
            return $null
        }

        [string] $left = $Matches['left']
        [string] $right = $Matches['right'].Trim()
        # A clause split out of parentheses, `(a < b)`, keeps its last one.
        while ($right.EndsWith(')') -and
            ($right.Split(')').Count -gt $right.Split('(').Count)) {
            $right = $right.Substring(0, $right.Length - 1).TrimEnd()
        }

        $bound = Measure-Bound -Text $right -Local $Local
        if ($null -eq $bound) {
            return $null
        }

        if ($left -match '\.as_(secs|millis|micros|nanos)\(\)\s*$') {
            return $bound.Micros * $script:Unit[$Matches[1]]
        }

        if ($bound.Time) {
            return $bound.Micros
        }

        return $null
    }

    <#
        .SYNOPSIS
            Each timing assertion in a file's tests, as `path:line`.
    #>
    function Find-TimingAssertion([string] $Path, [string[]] $Line) {
        [int] $start = Get-TestStart -Path $Path -Line $Line
        [int] $module = Get-TestStart -Path $Path -Line $Line -Module
        [hashtable] $local = Get-Constant -Line $Line
        [string] $holding = '\bat_once\(|\bRounds::crossing\(|\b(worked|woke)_beside_a_plain_wake\('
        # An account opened in a test's module is only ever held to a time.
        [string] $account = '\bSpent::begin\('

        [int[]] $found = @(
            for ([int] $index = $start; $index -lt $Line.Count; $index++) {
                [string] $code = $Line[$index] -replace '//.*$', ''
                if ($code -match $holding -or ($index -ge $module -and $code -match $account)) {
                    $index
                }
            }

            foreach ($assertion in (Get-Assertion -Line $Line -Start $start)) {
                foreach ($clause in $assertion.Clause) {
                    $bound = Get-ConstantBound -Clause $clause -Local $local
                    [bool] $literal = $clause -match $script:Bound -and
                        $clause -match $script:Measured
                    if ($literal -or ($null -ne $bound -and $bound -lt $script:Unit['secs'])) {
                        $assertion.At
                    }
                }
            }
        )

        $found | Sort-Object -Unique | ForEach-Object { "${Path}:$($_ + 1)" }
    }

    <#
        .SYNOPSIS
            Each gate in a file's tests, or anywhere in a timing program, that
            only a build without debug assertions passes, as `path:line`.
    #>
    function Find-ReleaseOnly([string] $Path, [string[]] $Line) {
        [int] $start = 0
        if ($Path -notmatch '(^|/)measured/') {
            $start = Get-TestStart -Path $Path -Line $Line
        }

        for ([int] $index = $start; $index -lt $Line.Count; $index++) {
            if (($Line[$index] -replace '//.*$', '') -match $script:ReleaseOnly) {
                "${Path}:$($index + 1)"
            }
        }
    }

    <#
        .SYNOPSIS
            The names a file's `let`s bind to a fastest of five or to what is
            measured beside it, as `$script:Fastest` reads one, or to what a
            function of the file that holds a fastest answers, or to another
            such name.
    #>
    function Get-HeldName([string[]] $Line) {
        [string] $source = $script:Fastest
        [string[]] $holding = @(Get-HoldingFunction -Line $Line)
        if ($holding.Count -gt 0) {
            $source += '|\b(' + ($holding -join '|') + ')\('
        }

        [object[]] $lets = @(Get-Let -Line $Line)
        [System.Collections.Generic.HashSet[string]] $held = @()
        do {
            [int] $before = $held.Count
            foreach ($let in $lets) {
                [int] $known = @($let.Name | Where-Object { $held.Contains($_) }).Count
                [bool] $references = @(
                    $held | Where-Object { $let.Value -match "\b$_\b" }
                ).Count -gt 0
                if ($known -lt $let.Name.Count -and ($let.Value -match $source -or $references)) {
                    $let.Name | ForEach-Object { [void] $held.Add($_) }
                }
            }
        } while ($held.Count -gt $before)

        return , $held
    }

    <#
        .SYNOPSIS
            The functions in `Line` whose body holds a fastest.
    #>
    function Get-HoldingFunction([string[]] $Line) {
        for ([int] $index = 0; $index -lt $Line.Count; $index++) {
            if ($Line[$index] -notmatch '^(?<indent>\s*)(pub(\([\w:]+\))?\s+)?fn\s+(?<name>\w+)') {
                continue
            }

            [string] $name = $Matches['name']
            [string] $end = "^$($Matches['indent'])\}\s*$"
            [int] $last = $index + 1
            while ($last -lt $Line.Count -and $Line[$last] -notmatch $end) {
                $last++
            }

            [string] $body = $Line[$index..([Math]::Min($last, $Line.Count - 1))] -join "`n"
            if ($body -match 'fastest') {
                $name
            }
        }
    }

    <#
        .SYNOPSIS
            Each `let` in `Line`: the names it binds and the text it binds them to.
    #>
    function Get-Let([string[]] $Line) {
        for ([int] $index = 0; $index -lt $Line.Count; $index++) {
            if ($Line[$index] -notmatch '^\s*let\s+(?<pattern>\([^=]*\)|\[[^=]*\]|(mut\s+)?\w+)') {
                continue
            }

            [string] $pattern = $Matches['pattern']
            [string] $text = $Line[$index]
            while ($text -notmatch ';\s*(//.*)?$' -and $index + 1 -lt $Line.Count) {
                $index++
                $text += "`n$($Line[$index])"
            }

            [string[]] $names = @(
                [regex]::Matches($pattern, '\b[a-z_]\w*\b') | ForEach-Object -MemberName Value |
                    Where-Object { $_ -notin 'mut', '_' }
            )
            [pscustomobject] @{ Name = $names; Value = ($text -split '=', 2)[-1] }
        }
    }

    <#
        .SYNOPSIS
            Each time a timing program holds under a constant bound below a second
            by neither a fastest of five nor what is measured beside it, as
            `path:line`.
    #>
    function Find-UnheldAssertion([string] $Path, [string[]] $Line) {
        [hashtable] $local = Get-Constant -Line $Line
        [System.Collections.Generic.HashSet[string]] $held = Get-HeldName -Line $Line

        foreach ($assertion in (Get-Assertion -Line $Line -Start 0)) {
            foreach ($clause in $assertion.Clause) {
                $bound = Get-ConstantBound -Clause $clause -Local $local
                if ($null -eq $bound -or $bound -ge $script:Unit['secs']) {
                    continue
                }

                [bool] $named = @($held | Where-Object { $clause -match "\b$_\b" }).Count -gt 0
                if ($clause -notmatch 'fastest' -and -not $named) {
                    "${Path}:$($assertion.At + 1)"
                }
            }
        }
    }

    # The estate's Rust: the composed trees and the root's own .src.
    [string[]] $script:Paths = @(
        Get-XmipSourceFile -Root $script:Root -Language Rust | ForEach-Object -MemberName Path
    )

    # The estate's constants by name: a name every file declares alike
    # resolves in any file; one declared otherwise anywhere resolves only in
    # the file that declares it.
    [hashtable] $script:Estate = @{}
    [hashtable] $said = @{}
    [string[]] $files = @($script:Paths | ForEach-Object { Join-Path $script:Root $_ })
    [object[]] $hits = @(Select-String -LiteralPath $files -Pattern $script:Declared -CaseSensitive)
    foreach ($hit in $hits) {
        [System.Text.RegularExpressions.Match] $match = [regex]::Match($hit.Line, $script:Declared)
        [string] $name = $match.Groups['name'].Value
        [string] $type = $match.Groups['type'].Value
        [string] $text = $match.Groups['text'].Value

        if (-not $said.ContainsKey($name)) {
            $said[$name] = "$type=$text"
            $script:Estate[$name] = @{ Type = $type; Text = $text }
        }
        elseif ($said[$name] -ne "$type=$text") {
            $script:Estate[$name] = $null
        }
    }
}

Describe 'A timing test runs alone, in its module''s measured program' {
    It 'holds no timing assertion outside a measured program' {
        [string[]] $outside = @(
            foreach ($path in $script:Paths) {
                if ($path -match '(^|/)measured/' -or $script:Instrument -contains $path) {
                    continue
                }

                [string[]] $line = @(Get-Content -LiteralPath (Join-Path $script:Root $path))
                Find-TimingAssertion -Path $path -Line $line
            }
        )

        [string] $because = "each belongs in its module's measured program (rust-style.md 5c):`n" +
            ($outside -join "`n")
        $outside.Count | Should -Be 0 -Because $because
    }

    It 'holds every time in a measured program by a fastest of five or what is beside it' {
        [string[]] $unheld = @(
            foreach ($path in $script:Paths) {
                if ($path -notmatch '(^|/)measured/' -or $script:Instrument -contains $path) {
                    continue
                }

                [string[]] $line = @(Get-Content -LiteralPath (Join-Path $script:Root $path))
                Find-UnheldAssertion -Path $path -Line $line
            }
        )

        [string] $because = 'a single sample, a batch, a mean or a median fails on load alone ' +
            "(rust-style.md 5c):`n" + ($unheld -join "`n")
        $unheld.Count | Should -Be 0 -Because $because
    }

    It 'runs every timing test in the build the estate tests with, debug assertions on' {
        [string[]] $gated = @(
            foreach ($path in $script:Paths) {
                if ($script:Instrument -contains $path) {
                    continue
                }

                [string[]] $line = @(Get-Content -LiteralPath (Join-Path $script:Root $path))
                Find-ReleaseOnly -Path $path -Line $line
            }
        )

        [string] $because = 'a hold only a release build runs never runs here (rust-style.md 5c):' +
            "`n" + ($gated -join "`n")
        $gated.Count | Should -Be 0 -Because $because
    }

    It 'finds a gate only a release build passes, so the check is not silent' {
        [string[]] $test = @(
            'fn production() {'
            '    if !cfg!(debug_assertions) { fast(); }'
            '}'
            '#[cfg(test)]'
            'mod tests {'
            '    #[test]'
            '    #[cfg_attr(debug_assertions, ignore = "a release figure")]'
            '    fn one() {'
            '        if !cfg!(debug_assertions) {'
            '            assert!(median < Duration::from_millis(1));'
            '        }'
            '        if cfg!(not(debug_assertions)) { held(); }'
            '        if cfg!(debug_assertions) { return; }'
            '    }'
            '    #[cfg(not(debug_assertions))]'
            '    fn two() {}'
            '    // if !cfg!(debug_assertions) is said, not run'
            '}'
        )

        @(Find-ReleaseOnly -Path 'module/x/src/lib.rs' -Line $test) |
            Should -Be @(
                'module/x/src/lib.rs:7', 'module/x/src/lib.rs:9', 'module/x/src/lib.rs:12',
                'module/x/src/lib.rs:13', 'module/x/src/lib.rs:15'
            )
        @(Find-ReleaseOnly -Path 'module/x/tests/measured/main.rs' -Line $test)[0] |
            Should -Be 'module/x/tests/measured/main.rs:2'
    }

    It 'finds a bound a constant makes, and a time held by nothing, so neither gate is silent' {
        [string[]] $test = @(
            'const WAIT: Duration = Duration::from_millis(300);'
            'const LONG: Duration = Duration::from_secs(2);'
            'const ROUNDS: u32 = 1_000;'
            '#[cfg(test)]'
            'mod tests {'
            '    fn one() {'
            '        assert!(waited < WAIT * 3, "a give-up soon after its wait");'
            '        assert!(waited < LONG, "an outcome, a second or more");'
            '        assert!(handed < Duration::from_millis(100) / ROUNDS, "{handed:?}");'
            '        assert!(held.len() <= ROUNDS as usize, "no time");'
            '        let (_, fastest, spent) = at_once("asked again", || ask());'
            '        assert!(spent < WAIT, "a figure of at_once");'
            '        let took = spread("a round", taken).fastest_of_five;'
            '        assert!(took < WAIT, "{took:?}");'
            '        assert!(each < WAIT + usual, "beside a plain wake");'
            '        let within = Duration::from_millis(150);'
            '        assert!(asked.elapsed() < within * 4, "one sample");'
            '    }'
            '}'
        )

        @(Find-TimingAssertion -Path 'module/x/src/lib.rs' -Line $test) |
            Should -Be @(
                'module/x/src/lib.rs:7', 'module/x/src/lib.rs:9', 'module/x/src/lib.rs:11',
                'module/x/src/lib.rs:12', 'module/x/src/lib.rs:14', 'module/x/src/lib.rs:17'
            )
        # In a timing program: the give-up, the hand-overs and the one sample;
        # never the outcome, the count, at_once's figure, the fastest of five
        # or the figure beside a plain wake.
        @(Find-UnheldAssertion -Path 'module/x/tests/measured/main.rs' -Line $test) |
            Should -Be @(
                'module/x/tests/measured/main.rs:7', 'module/x/tests/measured/main.rs:9',
                'module/x/tests/measured/main.rs:17'
            )
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
            '        let mut rounds = Rounds::crossing(WAKES);'
            '        worked_beside_a_plain_wake("a share", own, idle);'
            '        woke_beside_a_plain_wake("told", took, usual, WAKES);'
            '        let spent = Spent::begin();'
            '        assert!(first <= slowest + BEYOND, "beside the writes after it");'
            '    }'
            '}'
        )

        @(Find-TimingAssertion -Path 'module/x/src/lib.rs' -Line $test) |
            Should -Be @(
                'module/x/src/lib.rs:4', 'module/x/src/lib.rs:8', 'module/x/src/lib.rs:11',
                'module/x/src/lib.rs:12', 'module/x/src/lib.rs:13', 'module/x/src/lib.rs:14',
                'module/x/src/lib.rs:15'
            )
    }

    It 'finds an account a test opens, and leaves the one production code opens' {
        [string[]] $test = @(
            '#[cfg(test)]'
            'fn helper() {}'
            'fn committed() {'
            '    let spent = Spent::begin();'
            '}'
            '#[cfg(test)]'
            '#[allow(clippy::too_many_lines)]'
            'mod tests {'
            '    fn one() {'
            '        let spent = xcore::spent::Spent::begin();'
            '    }'
            '}'
        )

        @(Find-TimingAssertion -Path 'module/x/src/lib.rs' -Line $test) |
            Should -Be @('module/x/src/lib.rs:10')
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
