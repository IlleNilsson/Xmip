#requires -PSEdition Core
#requires -Version 7.7.0

<#
    The estate's style limits, in one place, for every style test: a file is
    at most this many lines of code, in Rust, C# and PowerShell alike
    (CONTRIBUTING.md).

    Dot-sourced at a test file's own scope, not in BeforeAll: Pester
    discovers test names before BeforeAll runs, and a name that says the
    limit needs it then.

    Not a test file: Pester is told its extension, .Test.ps1, and this is not
    one.

    Style: doc/governance/powershell-style.md
#>

[int] $script:MaximumFileLines = 400
