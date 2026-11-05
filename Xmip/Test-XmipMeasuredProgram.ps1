#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    A module's timing program, `measured`: linted, and run after the module's
    other tests, alone, one test at a time.

.DESCRIPTION
    The estate's one implementation of the rule in rust-style.md section 5c:
    a test that holds Xmip to a time is in its module's `measured` program,
    which a plain `cargo test` leaves out (`test = false`), and which runs
    here once everything else of the module has passed, with nothing beside
    it. Until 2026-11-01 those tests ran inside each module's parallel suite,
    whose other tests slowed the measured work 1.5 to 3 times, and landings
    failed at random on them.

    Style: doc/governance/powershell-style.md
#>


# The cargo test target every module's timing program is: one name, so the
# landing finds it in any module without being told.
$script:XmipMeasuredProgram = 'measured'


function Test-XmipMeasuredProgram {
    <#
        .SYNOPSIS
            Lints a module's `measured` program and, unless only checking, runs
            it with one test thread. Whether it passed; true where the module
            has none.

        .DESCRIPTION
            Run from the module's directory, after its other tests passed.
            Modules verify one after another, so nothing else runs then.
            Linted apart from `--all-targets`, which leaves out a target cargo
            does not test by default; `--test` beside `--all-targets` is
            ignored, so it is a call of its own.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string] $ManifestPath,

        # The features the module's tests run with: the program names the
        # ones it needs in `required-features`.
        [Parameter()]
        [AllowEmptyCollection()]
        [string[]] $Feature = @(),

        # The cargo configuration from New-XmipLocalPatch, as `--config`.
        [Parameter()]
        [AllowEmptyCollection()]
        [string[]] $Through = @(),

        # Lint only: for a consumer of a changed module, which is not landed.
        [Parameter()]
        [switch] $CheckOnly
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
    [string[]] $withFeatures = @()

    if ($Feature.Count -gt 0) {
        $withFeatures = @('--features', ($Feature -join ','))
    }

    Write-Host "   checking lints of $program..." -ForegroundColor DarkGray
    [string[]] $linting = @('clippy') + $Through + '--test' + $program + $withFeatures +
        '--' + '-D' + 'warnings'

    if (-not (Invoke-XmipTool -Tool cargo -Argument $linting).Passed) {
        Write-Host "   FAILED lints. Run: cargo clippy --test $program" -ForegroundColor Red
        return $false
    }

    if ($CheckOnly) {
        return $true
    }

    Write-Host "   timing, $program alone, one test at a time..." -ForegroundColor DarkGray
    [string[]] $alone = @('test') + $Through + '--test' + $program + $withFeatures + '--' +
        '--test-threads=1'

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
