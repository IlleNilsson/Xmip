#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    Verifying one module before it lands: build, format, lint and test.

.DESCRIPTION
    Apart from Publish-XmipChange.ps1 since 2026-09-22, when that file had grown
    to 1,586 lines against the 400 the estate allows a file, and the owner asked
    for the estate to be consolidated. The landing is one command made of several
    subjects; each subject is a file.

    Style: doc/governance/powershell-style.md
#>


function Test-XmipBuildOutput {
    <#
        .SYNOPSIS
            Whether a changed path is something a compiler produced.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $Path -match '^(target/|bin/|obj/|\.vs/|Cargo\.lock$|packages\.lock\.json$)'
}


# Features whose code does not compile, and the module that owns each.
#
# A shrink-only list, the same instrument as the file-length ratchet in
# Rust.Style.Test.ps1 and for the same reason: a waiver list absorbs new
# entries and its maintenance becomes the work, while this can only be emptied.
# Adding to it is a decision somebody has to argue for; removing is just fixing
# the feature.
#
# Empty, and that is the intended state — the same as the Rust file-length
# ratchet, emptied the same week.
#
# Both entries were found on 2026-08-29, the day declared features were first
# built, and both came off on 2026-08-30: tls needed rustls's ring feature
# enabled in transport's Cargo.toml, and dynamic-loading needed ADR-0025
# clause 5 — xmip-core-abi exporting the loading surface its own header always
# defined. Each had never compiled, from the day it was written.
#
# A new entry needs the owner's agreement first and its reason written here.
$script:XmipUnbuildableFeature = @{ }

<#
    .SYNOPSIS
    Every feature a module declares, less the ones known not to build.

    .DESCRIPTION
    `cargo build --all-features` is all-or-nothing, so one broken feature would
    mean the module cannot be checked at all. Naming the features instead keeps
    every other one verified while the two exceptions are outstanding.
#>
function Get-XmipBuildableFeature {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [string] $ManifestPath,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Module
    )

    [string] $manifest = Get-Content -LiteralPath $ManifestPath -Raw

    # The [features] table, to the next table header or the end.
    if ($manifest -notmatch '(?ms)^\[features\]\s*$(.*?)(?=^\[|\z)') {
        return @()
    }

    [string[]] $declared = @(
        $Matches[1] -split "`n" |
            ForEach-Object { if ($_ -match '^\s*([A-Za-z0-9_-]+)\s*=') { $Matches[1] } }
    )

    [string[]] $skip = @($script:XmipUnbuildableFeature[$Module])

    # `default` is what cargo build already does, so naming it adds nothing.
    return @($declared | Where-Object { $_ -ne 'default' -and $skip -notcontains $_ })
}


function Test-XmipModule {
    <#
        .SYNOPSIS
            Runs each module's own tests, then builds every feature it declares.
            Returns the ones that failed.

        .DESCRIPTION
            **`cargo test` compiles the default feature set and nothing else**,
            so a module behind a feature flag is never seen by a compiler. Three
            files reached the estate that way and none had ever compiled:
            `technology.rs`, which was moved into a repository and never
            declared; `disposition.rs`, which imported two modules that had left
            for other repositories; and `host.rs`, whose `mod dynamic` is gated
            on `dynamic-loading`.

            All three were found by hand, one at a time, months apart. Building
            the declared features would have caught each on the day it was
            written.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Module,

        [Parameter()]
        [switch] $All
    )

    # $name, not $module. PowerShell variable names are case-insensitive, so
    # `foreach ($module in $Module)` iterates a parameter using the parameter's
    # own variable — one variable, two meanings. It survived because Join-Path
    # and Write-Host both accept an array and quietly do something reasonable
    # with it. The first strongly typed [string] parameter it was handed to
    # refused, on 2026-08-29, which is the only reason anyone found out.
    foreach ($name in $Module) {
        $path = Join-Path -Path $RepositoryRoot -ChildPath $name
        $manifest = Join-Path -Path $path -ChildPath 'Cargo.toml'

        if (-not (Test-Path -LiteralPath $manifest)) {
            # No Cargo.toml is not the end of the question any more.
            #
            # ADR-0014 puts every operator surface in .NET, so this branch used
            # to skip a third of them: cli, powershell and gui reported "nothing
            # here can test it" and landed only under -All, unverified. It said
            # that on the day the PowerShell module gained eighteen tests.
            #
            # Reported, never returned, still holds for a module with neither a
            # Cargo.toml nor a project: this function returns modules that
            # *failed*, and returning one that could not be tested made the
            # caller stop the entire run. Cannot be verified here and did not
            # fail are different answers, and only one should halt the estate.
            [bool] $dotnet = @(
                Get-ChildItem -Path $path -Filter '*.csproj' -Recurse -File |
                    Where-Object { $_.FullName -notmatch '[\\/](obj|bin)[\\/]' }
            ).Count -gt 0

            $selfVerify = Join-Path -Path $path -ChildPath 'verify.ps1'

            if (-not $dotnet -and (Test-Path -LiteralPath $selfVerify)) {
                # A repository that verifies itself: its verify.ps1 builds and
                # tests with whatever toolchain its language needs, declared in
                # prerequisite.toml, and its exit code is the verdict.
                Write-Host "== $name (verify.ps1)" -ForegroundColor Cyan

                if (-not (Test-XmipSelfVerifyingModule -Path $path -Name $name)) {
                    $name
                }

                continue
            }

            if (-not $dotnet) {
                [string] $why = "== $name (no Cargo.toml, no project and no verify.ps1, " +
                    'nothing can test it)'

                Write-Host $why -ForegroundColor DarkGray

                continue
            }

            Write-Host "== $name (.NET)" -ForegroundColor Cyan

            if (-not (Test-XmipDotnetModule -Path $path -Name $name)) {
                $name
            }

            continue
        }

        Write-Host "== $name" -ForegroundColor Cyan

        Push-Location -LiteralPath $path

        try {
            # Dependencies track main, so the lock is re-resolved or the test
            # runs against whatever was current when anyone last built.
            #
            # Announced, because this is the slow step and it used to be a
            # silent one. Fourteen git dependencies means fourteen fetches from
            # GitHub, and on 2026-08-30 that looked like a hung run for three
            # minutes: the module header was printed, then nothing, because
            # cargo's output is captured and only written when the module is
            # done. A prompt from git for credentials would appear on the
            # console and never in the log at all.
            Write-Host '   resolving dependencies...' -ForegroundColor DarkGray
            & cargo update 2>&1 | Out-Null

            Write-Host '   testing...' -ForegroundColor DarkGray

            # Written as it arrives, and still returning nothing.
            #
            # Emitting matters: this function returns the modules that failed,
            # and a native command left to write into the pipeline makes every
            # line of its output a return value, so the caller reads cargo's
            # passing tests as the list of failures.
            #
            # Capturing it and printing afterwards solved that and created a
            # worse one. On 2026-08-30 a rebuild of fourteen git dependencies
            # showed nothing for five minutes — not in the log, not on the
            # console, because the output was in a variable. A slow run and a
            # hung one were the same picture, and the only way to tell them
            # apart was to wait and find out.
            #
            # Write-Host inside ForEach-Object gives both: each line appears
            # when cargo emits it, and the block returns nothing.
            & cargo test 2>&1 | ForEach-Object { Write-Host $_ }
            $passed = $LASTEXITCODE -eq 0

            # rust-style.md says CI runs cargo fmt --check. It does, in a
            # workflow triggered by hand, which is not the path code lands on.
            #
            # On 2026-09-03 twenty-five of thirty-eight crates were unformatted
            # — 266 diffs — because the move to edition 2024 changed how
            # rustfmt orders imports and nobody re-ran it. Every one of those
            # landed green. A rule enforced only where nobody goes is not a
            # rule, which is the argument powershell-style.md already makes
            # about reporting and returning success.
            #
            # Checked rather than applied: a gate that rewrites the working
            # tree mid-landing decides for the operator what their commit
            # contains.
            if ($passed) {
                Write-Host '   checking format...' -ForegroundColor DarkGray

                & cargo fmt --check 2>&1 | ForEach-Object { Write-Host $_ }
                $passed = $LASTEXITCODE -eq 0

                if (-not $passed) {
                    Write-Host '   FAILED format. Run: cargo fmt' -ForegroundColor Red
                }
            }

            # Clippy, with every warning an error. Gated on 2026-09-04, once
            # the estate was clean: five crates warned, eight distinct issues,
            # seven mechanical and one real — a function taking two ids that
            # were already on the Message it was handed. Gating it with a
            # waiver on day one is how a gate becomes a waiver list.
            if ($passed) {
                Write-Host '   checking lints...' -ForegroundColor DarkGray

                & cargo clippy --all-targets -- -D warnings 2>&1 | ForEach-Object { Write-Host $_ }
                $passed = $LASTEXITCODE -eq 0

                if (-not $passed) {
                    [string] $hint = '   FAILED lints. Run: cargo clippy --all-targets'

                    Write-Host $hint -ForegroundColor Red
                }
            }

            # Only when the tests passed. A module that fails its tests is
            # already failing, and a second wall of compiler output buries the
            # error the operator has to read.
            if ($passed) {
                # @() around the call, not only inside the callee. A function
                # that returns @() emits nothing, so its caller receives $null
                # and [string[]] keeps it null — .Count then throws under
                # StrictMode. Found 2026-08-30, the first time a module with no
                # features table met an empty exception list.
                [string[]] $features =
                    @(Get-XmipBuildableFeature -ManifestPath $manifest -Module $name)

                if ($features.Count -gt 0) {
                    [string] $listed = $features -join ', '
                    [string] $note = "   building $($features.Count) declared feature(s): $listed"

                    Write-Host $note -ForegroundColor DarkGray

                    & cargo build --features ($features -join ',') 2>&1 |
                        ForEach-Object { Write-Host $_ }
                    $passed = $LASTEXITCODE -eq 0
                }
            }

            if ($passed -and (Test-Path -LiteralPath (Join-Path $path 'extension/package.json'))) {
                # The one Rust repository that also ships a TypeScript shell
                # (ADR-0014, amendment 2026-09-10) is verified in both languages.
                $passed = Test-XmipExtensionShell -Path (Join-Path $path 'extension') -Name $name
            }
        }
        finally {
            Pop-Location
        }

        if (-not $passed) {
            $name
        }
    }
}
