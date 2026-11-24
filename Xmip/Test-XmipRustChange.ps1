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
    graph of its own, is a handful (the round-17 landing ran 366), and the
    crates named are verified in one command for each mode, never one for
    each crate (ADR-0028, amendment 2026-11-24; open problem 147):

    - the crates' format, in one command at the root;
    - the workspace linted with every feature of every member: every
      consumer of the change at once, against it, in place of a command per
      consumer; then every timing program's lint, in one command;
    - the crates' tests and their lints with their default features, the
      only build that compiles what a feature leaves out
      (`cfg(not(feature = ...))`), then their tests with every feature they
      declare, each a command over every crate named;
    - each crate built alone, `cargo check --all-targets` of it and nothing
      else: in one command cargo gives a dependency the features every crate
      named asks of it, so a crate that compiles only through another's
      features is caught here, as a repository built alone would catch it.

    A crate with a cargo configuration of its own, `.cargo/config.toml` in
    its folder, is verified in that folder, as cargo is run there by hand,
    where cargo reads it: the System Tests' rig. A changed crate the
    workspace does not hold, by its plan's members (Get-XmipWorkspacePlan),
    the template's, is verified as a repository alone builds: through its own
    manifest, `--manifest-path`, its format, its lints with its default
    features and with every feature, and its tests.

    What failed is named by the crate's folder and the test, from what cargo
    said (Get-XmipToolFailure). The timing programs run after every part of
    the landing, alone (Test-XmipMeasuredProgram, rust-style.md section 5c).

    Style: doc/governance/powershell-style.md
#>


function Test-XmipRustChange {
    <#
        .SYNOPSIS
            Verifies the changed crates in the workspace: each failure as
            Xmip.PartFailure, the crate's folder, the test and the words that
            say why; nothing when every step passed.

        .PARAMETER Module
            The changed crates, leaves first, as the estate names a module.
            The root crate is verified whenever a module lands, last, and is
            not named here.

        .PARAMETER Consumer
            Whether the change has consumers, so the whole workspace is
            linted against it; a change of comments and prose alone has none
            (Test-XmipCodeChange).

        .PARAMETER Alone
            The crates named and nothing else, for Core.Internal
            (Start-XmipInternalSuite): not the root crate and not the timing
            programs' lints; and every step to its end, every test of every
            crate run, so every failure is named, where a landing stops at
            its first.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.PartFailure')]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]] $Module = @(),

        [Parameter()]
        [switch] $Consumer,

        [Parameter()]
        [switch] $Alone
    )

    [string[]] $crates = if ($Alone) { @($Module) } else { @($Module) + '.' }
    [string[]] $member = @('.') + @((Get-XmipWorkspacePlan -RepositoryRoot $RepositoryRoot).Member)

    # Each member named by its package: what cargo names is read back to the
    # crate's folder by it.
    [System.Collections.Specialized.OrderedDictionary] $package = [ordered]@{}

    foreach ($name in @($crates | Where-Object { $_ -in $member })) {
        $manifest = Read-XmipModuleManifest -RepositoryRoot $RepositoryRoot -Module $name
        $package[$name] = $manifest.Package
    }

    [string[]] $together = @($package.Keys | Where-Object {
            $_ -eq '.' -or -not (Test-Path -LiteralPath (
                    Join-Path -Path $RepositoryRoot -ChildPath "$_/.cargo/config.toml"))
        })
    [hashtable] $plan = @{
        RepositoryRoot = $RepositoryRoot; Package = $package; Together = $together
        Consumer = [bool] $Consumer; Alone = [bool] $Alone
    }
    [List[pscustomobject]] $steps = [List[pscustomobject]]::new()
    $steps.AddRange([pscustomobject[]] @(Get-XmipRustStep @plan))

    foreach ($name in @($crates | Where-Object { $_ -notin $together })) {
        [hashtable] $crate = @{ RepositoryRoot = $RepositoryRoot; Name = $name }
        $steps.AddRange([pscustomobject[]] @(Get-XmipCrateStep @crate -Member ($name -in $member)))
    }

    foreach ($step in $steps) {
        Write-Host "   $($step.Name)..." -ForegroundColor DarkGray
        Push-Location -LiteralPath $step.At

        try {
            $ran = Invoke-XmipTool -Tool cargo -Argument $step.Argument
        }
        finally {
            Pop-Location
        }

        if ($ran.Passed) {
            continue
        }

        [hashtable] $read = @{ RepositoryRoot = $RepositoryRoot; Package = $package }
        ConvertTo-XmipRustFailure @read -Ran $ran -Step $step

        if (-not $Alone) {
            return
        }
    }
}


function Get-XmipRustStep {
    <#
        .SYNOPSIS
            Test-XmipRustChange's steps over the members named, at the root:
            one command for each mode, then each crate built alone.

        .PARAMETER Package
            Each member named, its folder to its package.

        .PARAMETER Together
            The members verified at the root, every one but a crate with a
            cargo configuration of its own.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Package,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Together,

        [Parameter()]
        [bool] $Consumer,

        [Parameter()]
        [bool] $Alone
    )

    [string[]] $every = @($Package.Keys | ForEach-Object { '-p', $Package[$_] })
    [string[]] $selected = @($Together | ForEach-Object { '-p', $Package[$_] })
    [string[]] $featured = @(
        $Together | Where-Object {
            Test-XmipDeclaredFeature -ManifestPath (
                Join-Path -Path $RepositoryRoot -ChildPath "$_/Cargo.toml")
        } | ForEach-Object { '-p', $Package[$_] }
    )
    [string[]] $lint = @(if ($Consumer) { '--workspace' } else { $every })

    # Core.Internal runs every crate's every test and lint, so a failure
    # names all that fail; a landing stops at the first.
    [string[]] $going = @(if ($Alone) { '--keep-going' })
    [string[]] $all = @(if ($Alone) { '--no-fail-fast' })
    [scriptblock] $step = {
        param([string] $Name, [string[]] $Argument, [string] $Crate = '')
        [pscustomobject]@{
            Name = $Name; At = $RepositoryRoot; Argument = $Argument; Crate = $Crate
        }
    }

    # Members named, or every member: `cargo fmt` with no -p formats the
    # whole workspace, which a crate named alone outside it never asked for.
    if ($lint.Count -gt 0) {
        & $step 'format' (@('fmt', '--check') + $every)

        # Every member, so every consumer of the change, against the change.
        & $step 'the lints, every feature' (
            @('clippy', '--all-targets', '--all-features') + $going + $lint)
    }

    # `--all-targets` leaves out a target cargo does not test by default;
    # across the workspace, `--test measured` takes the crates that have one.
    if (-not $Alone) {
        & $step 'the timing programs'' lints' (
            @('clippy', '--workspace', '--all-features', '--test', 'measured'))
    }

    if ($selected.Count -eq 0) {
        return
    }

    & $step 'the tests' (@('test') + $all + $selected)
    & $step 'the lints' (@('clippy', '--all-targets') + $going + $selected)

    # With every feature they declare, where one does: a crate with none was
    # tested whole by the default run.
    if ($featured.Count -gt 0) {
        & $step 'the tests with every feature' (@('test', '--all-features') + $all + $featured)
    }

    foreach ($name in $Together) {
        & $step "$name, built alone" @('check', '--all-targets', '-p', $Package[$name]) $name
    }
}


function Get-XmipCrateStep {
    <#
        .SYNOPSIS
            Test-XmipRustChange's steps for one crate in its own folder: a
            member with a cargo configuration of its own, its tests and lints;
            a crate the workspace does not hold, through its own manifest, its
            format and its lints with every feature too.

        .PARAMETER Name
            The crate's folder from the root.

        .PARAMETER Member
            Whether the workspace holds it.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [bool] $Member
    )

    [string] $crate = Join-Path -Path $RepositoryRoot -ChildPath $Name
    [string] $manifest = Join-Path -Path $crate -ChildPath 'Cargo.toml'
    [string[]] $own = @(if (-not $Member) { '--manifest-path', $manifest })
    [scriptblock] $step = {
        param([string] $What, [string[]] $Argument)
        [pscustomobject]@{ Name = "$Name, $What"; At = $crate; Argument = $Argument; Crate = $Name }
    }

    if (-not $Member) {
        & $step 'its format' (@('fmt', '--check') + $own)
        & $step 'its lints with every feature' (
            @('clippy', '--all-targets', '--all-features') + $own)
    }

    & $step 'its tests' (@('test') + $own)
    & $step 'its lints' (@('clippy', '--all-targets') + $own)

    if (Test-XmipDeclaredFeature -ManifestPath $manifest) {
        & $step 'its tests with every feature' (@('test', '--all-features') + $own)
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
