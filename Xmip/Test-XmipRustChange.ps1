#requires -PSEdition Core
#requires -Version 7.7.0

using namespace System.Collections.Generic

<#
.SYNOPSIS
    The landing's Rust part: the estate's one workspace verified against a
    change (ADR-0016, amendment 2026-11-20).

.DESCRIPTION
    One workspace, one resolution, one build directory, so what was a cargo
    command per module and per consumer, each resolving and building a
    graph of its own, is a handful (the round-17 landing ran 366):

    - the changed crates' format, in one command at the root;
    - the workspace linted with every feature of every member: every
      consumer of the change at once, against it, in place of a command per
      consumer; then every timing program's lint, in one command;
    - each changed crate, leaves first, and the root crate last, in its own
      folder, as cargo is run there by hand (a crate's own `.cargo` is read):
      its tests and its lints with its default features, the only build that
      compiles what a feature leaves out (`cfg(not(feature = ...))`), then
      its tests with every feature it declares.

    A changed crate the workspace does not hold, by its plan's members
    (Get-XmipWorkspacePlan), the template's, is verified as a repository
    alone builds: through its own manifest, `--manifest-path`, its format,
    its lints with its default features and with every feature, and its
    tests.

    The timing programs run after every part of the landing, alone
    (Test-XmipMeasuredProgram, rust-style.md section 5c).

    Style: doc/governance/powershell-style.md
#>


function Test-XmipRustChange {
    <#
        .SYNOPSIS
            Verifies the changed crates in the workspace; what failed, in
            words, or nothing when every step passed.

        .PARAMETER Module
            The changed crates, leaves first, as the estate names a module.
            The root crate is verified whenever a module lands, last, and is
            not named here.

        .PARAMETER Consumer
            Whether the change has consumers, so the whole workspace is
            linted against it; a change of comments and prose alone has none
            (Test-XmipCodeChange).

    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]] $Module = @(),

        [Parameter()]
        [switch] $Consumer
    )

    [string[]] $crates = @($Module) + '.'
    [string[]] $member = @('.') + @((Get-XmipWorkspacePlan -RepositoryRoot $RepositoryRoot).Member)
    [string[]] $selected = @(
        $crates | Where-Object { $_ -in $member } | ForEach-Object {
            '-p', (Read-XmipModuleManifest -RepositoryRoot $RepositoryRoot -Module $_).Package
        }
    )
    [string[]] $lint = if ($Consumer) { @('--workspace') } else { $selected }

    [List[pscustomobject]] $steps = [List[pscustomobject]]::new()
    $steps.Add([pscustomobject]@{
            Name = 'format'; At = $RepositoryRoot; Argument = @('fmt', '--check') + $selected
        })

    # Every member, so every consumer of the change, against the change.
    $steps.Add([pscustomobject]@{
            Name     = 'the lints, every feature'
            At       = $RepositoryRoot
            Argument = @('clippy', '--all-targets', '--all-features') + $lint
        })

    # `--all-targets` leaves out a target cargo does not test by default;
    # across the workspace, `--test measured` takes the crates that have one.
    $steps.Add([pscustomobject]@{
            Name     = 'the timing programs'' lints'
            At       = $RepositoryRoot
            Argument = @('clippy', '--workspace', '--all-features', '--test', 'measured')
        })

    foreach ($name in $crates) {
        [string] $crate = Join-Path -Path $RepositoryRoot -ChildPath $name
        [string] $manifest = Join-Path -Path $crate -ChildPath 'Cargo.toml'

        # Not a member: its own manifest names it, its format and its lints
        # with every feature too, which the workspace's steps above leave out.
        [string[]] $own = @()

        if ($name -notin $member) {
            $own = @('--manifest-path', $manifest)
            $steps.Add([pscustomobject]@{
                    Name = "$name, its format"; At = $crate; Argument = @('fmt', '--check') + $own
                })
            $steps.Add([pscustomobject]@{
                    Name     = "$name, its lints with every feature"
                    At       = $crate
                    Argument = @('clippy', '--all-targets', '--all-features') + $own
                })
        }

        $steps.Add([pscustomobject]@{
                Name = "$name, its tests"; At = $crate; Argument = @('test') + $own
            })
        $steps.Add([pscustomobject]@{
                Name     = "$name, its lints"
                At       = $crate
                Argument = @('clippy', '--all-targets') + $own
            })

        # With every feature it declares, where it declares one: a crate with
        # none was tested whole by its default run.
        if (Test-XmipDeclaredFeature -ManifestPath $manifest) {
            $steps.Add([pscustomobject]@{
                    Name     = "$name, its tests with every feature"
                    At       = $crate
                    Argument = @('test', '--all-features') + $own
                })
        }
    }

    foreach ($step in $steps) {
        Write-Host "   $($step.Name)..." -ForegroundColor DarkGray
        Push-Location -LiteralPath $step.At

        try {
            if (-not (Invoke-XmipTool -Tool cargo -Argument $step.Argument).Passed) {
                return $step.Name
            }
        }
        finally {
            Pop-Location
        }
    }
}


function Test-XmipDeclaredFeature {
    <#
        .SYNOPSIS
            Whether a Cargo.toml declares a feature of its own besides
            the `default` one.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string] $ManifestPath
    )

    [string] $manifest = Get-Content -LiteralPath $ManifestPath -Raw

    # The [features] table, to the next table header or the end.
    if ($manifest -notmatch '(?ms)^\[features\]\s*$(.*?)(?=^\[|\z)') {
        return $false
    }

    @($Matches[1] -split "`n" | Where-Object {
            $_ -match '^\s*([A-Za-z0-9_-]+)\s*=' -and $Matches[1] -ne 'default'
        }).Count -gt 0
}