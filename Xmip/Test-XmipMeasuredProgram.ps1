#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    A module's timing program, `measured`: run in the optimized build after
    every other part of the landing, alone, one test at a time.

.DESCRIPTION
    The estate's one implementation of the rule in rust-style.md section 5c:
    a test that holds Xmip to a time is in its module's `measured` program,
    which a plain `cargo test` leaves out (`test = false`), and which runs
    here once everything else of the landing has passed, with nothing beside
    it. Until 2026-11-01 those tests ran inside each module's parallel suite,
    whose other tests slowed the measured work 1.5 to 3 times, and landings
    failed at random on them.

    It runs in the `measured` profile, every crate at opt-level 3 with debug
    assertions kept: the millisecond rule is measured on the optimized build
    (the owner, 2026-11-01; ADR-0018, amendment 2026-11-20), while every
    other build of the estate compiles its own crates at opt-level 1. The
    workspace's lint of every timing program is the Rust part's
    (Test-XmipRustChange).

    Style: doc/governance/powershell-style.md
#>


# The cargo test target every module's timing program is: one name, so the
# landing finds it in any module without being told.
$script:XmipMeasuredProgram = 'measured'

# The cargo profile every timing program runs in (the root's Cargo.toml).
$script:XmipMeasuredProfile = 'measured'


function Test-XmipMeasuredProgram {
    <#
        .SYNOPSIS
            Runs a module's `measured` program with every feature it
            declares, one test thread, in the `measured` profile. Whether it
            passed; true where the module has none.

        .DESCRIPTION
            Run from the module's directory, after every other part of the
            landing passed, so nothing else runs beside it.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string] $ManifestPath
    )

    [string] $program = $script:XmipMeasuredProgram
    [string] $declared = Get-XmipMeasuredDeclaration -ManifestPath $ManifestPath

    if (-not $declared) {
        return $true
    }

    # Tested by default, cargo would run it among the module's other tests.
    if ($declared -notmatch '(?m)^test\s*=\s*false\s*$') {
        Write-Host "   FAILED. $program is declared without test = false." -ForegroundColor Red
        return $false
    }

    Write-Host "   timing, $program alone, one test at a time..." -ForegroundColor DarkGray
    [string[]] $alone = @('test', '--profile', $script:XmipMeasuredProfile, '--all-features',
        '--test', $program, '--', '--test-threads=1')

    (Invoke-XmipTool -Tool cargo -Argument $alone).Passed
}


function Get-XmipMeasuredDeclaration {
    <#
        .SYNOPSIS
            The [[test]] table a Cargo.toml declares its timing program,
            `measured`, in; empty where it declares none.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $ManifestPath
    )

    [string] $manifest = Get-Content -LiteralPath $ManifestPath -Raw
    [string] $name = [regex]::Escape($script:XmipMeasuredProgram)

    # Each [[test]] table, to the next table header or the end.
    foreach ($table in [regex]::Matches($manifest, '(?ms)^\[\[test\]\]\s*$(.*?)(?=^\[|\z)')) {
        [string] $body = $table.Groups[1].Value

        if ($body -match "(?m)^name\s*=\s*`"$name`"\s*$") {
            return $body
        }
    }

    ''
}
