#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    What forty-two repositories need instead of `git status` and `git push`.

.DESCRIPTION
    Three commands, named and parameterised to read like the git underneath
    them.

        Get-XmipStatus                  git status, across the estate
        Publish-XmipChange -m '...'     git add, commit and push, in dependency
                                        order, having tested first
        Publish-XmipPin                 move the superproject's gitlinks

    `xmip-git` and `xgit` are aliases for the second. The estate talks about
    "Xmip-Git"; PowerShell requires an approved verb. An alias is how both are
    satisfied, and it is what aliases are for.

    Neither asks the caller to know anything git would not have asked. The
    dependency order is read out of the manifests, because it is already written
    there and making a person supply it is how the estate grows gray hairs.

    Colour is decoration, never the message. Every line that reports an outcome
    says it in words first — OK, FAILED, REFUSED, NOTE — because a reader who
    does not separate red from green is otherwise reading an unlabelled result,
    and so is anyone piping this to a file. -ForegroundColor stays as a second
    channel for those it helps.

    Style: docs/governance/powershell-style.md
#>

function Get-XmipStatus {
    <#
        .SYNOPSIS
            `git status`, across the estate.

        .DESCRIPTION
            Every module that has something uncommitted, what it is, and whether
            it looks like source or like build output.

            Objects out, not text, so
            `Get-XmipStatus | Where-Object Suspicious` answers "is anything
            about to commit a target directory again" without parsing anything.

        .PARAMETER Short
            One line per module rather than one per file. Mirrors
            `git status --short`.

        .PARAMETER RepositoryRoot
            The Xmip working tree. Defaults to the one this module was imported
            from.

        .EXAMPLE
            Get-XmipStatus

        .EXAMPLE
            Get-XmipStatus -Short

        .EXAMPLE
            Get-XmipStatus | Where-Object Suspicious
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch] $Short,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $RepositoryRoot = (Get-XmipRepositoryRoot)
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    Import-XmipPoshGit

    # The platform repository first. It is a repository like the others, and it
    # holds the PowerShell module, the decision records and the assembly — the
    # things most likely to be uncommitted while every submodule is clean.
    $estate = @('.') + @(Get-XmipDeclaredModule -RepositoryRoot $RepositoryRoot)

    foreach ($module in $estate) {
        $path =
            if ($module -eq '.') { $RepositoryRoot }
            else { Join-Path -Path $RepositoryRoot -ChildPath $module }

        if (-not (Test-Path -LiteralPath $path)) {
            Write-Warning "$module is declared and not present. Run Sync-XmipEstate."
            continue
        }

        Push-Location -LiteralPath $path

        try {
            $git = Get-GitStatus
        }
        finally {
            Pop-Location
        }

        if (-not $git) {
            Write-Warning "$module is not a git repository."
            continue
        }

        # posh-git for what porcelain does not have — branch, ahead, behind —
        # and porcelain for the files.
        #
        # Not both from posh-git. Get-GitStatus disables file status for
        # repositories it judges large and still answers HasWorking: False, so
        # its Index and Working sets read as "clean" when they mean "not
        # counted". On 2026-08-27 that hid two modified modules and cost three
        # rounds of a red build.
        $changed = @(& git -C $path status --porcelain | Where-Object { $_ })
        $files = @($changed | ForEach-Object { $_.Substring(3).Trim('"') } | Sort-Object -Unique)

        $behind = $git.BehindBy -gt 0

        if ($files.Count -eq 0 -and -not $behind -and $git.AheadBy -eq 0) {
            continue
        }

        $suspicious = @($files | Where-Object { Test-XmipBuildOutput -Path $_ })

        if ($Short) {
            [PSCustomObject]@{
                Module     = $module
                Branch     = $git.Branch
                Changed    = $files.Count
                AheadBy    = $git.AheadBy
                BehindBy   = $git.BehindBy
                Suspicious = $suspicious.Count -gt 0
            }

            continue
        }

        foreach ($line in $changed) {
            $file = $line.Substring(3).Trim('"')

            [PSCustomObject]@{
                Module     = $module
                Branch     = $git.Branch
                State      = $line.Substring(0, 2)
                Path       = $file
                Suspicious = [bool] (Test-XmipBuildOutput -Path $file)
            }
        }
    }
}

function Publish-XmipChange {
    <#
        .SYNOPSIS
            `git add`, `commit` and `push` across every changed module, in
            dependency order, having tested first.

        .DESCRIPTION
            **Order is read, not asked for.** Dependencies track `branch =
            "main"` under ADR-0005, so a module has to be on origin before
            anything that depends on it is tested — otherwise the test resolves
            the previous version and passes or fails for the wrong reason. Every
            manifest already declares its dependencies, so the order comes from
            there.

            **Each module is tested and landed before the next is tested.**
            Dependencies resolve against `main`, so a module cannot be verified
            against a sibling that is still only local. A failure halfway leaves
            the earlier ones landed and says so; that is recoverable, and no
            other order works at all.

            **Build output is refused rather than committed.** On 2026-08-27 a
            hand-run loop pushed 105 files of `target/` to xmip-core: it checked
            whether a module was dirty and never what was dirty.

            Redirect to capture, per the style document:

                Publish-XmipChange -m 'what changed' *>&1 |
                    Tee-Object -FilePath D:\Repos\land.log

        .PARAMETER Message
            The commit message. Positional and aliased `-m`, like git. Short and
            precise — the reasoning belongs in the decision record.

        .PARAMETER All
            Include modules with no tests of their own. Without it, a module
            that cannot be verified here is reported and left alone.

        .PARAMETER NoVerify
            Land without testing, like `git commit --no-verify`. For a change no
            compiler can check.

        .PARAMETER Pin
            Move the superproject's gitlinks and push, and do nothing else.

            The repair path. A run that stopped halfway leaves modules on origin
            and the superproject still pointing at where they were, which reads
            as a dirty working tree that `git add` cannot explain. This is
            `git submodule update` in the other direction.

            There is deliberately no `-Commit` without `-Push`. Dependencies
            track `branch = "main"` under ADR-0005, so a module that is committed
            and not pushed is a module the next one in the order will test
            against the *previous* published version — passing or failing for a
            reason that is not in the working tree. git can separate the two
            because git has no such rule; here the pair is one operation.

        .PARAMETER RepositoryRoot
            The Xmip working tree.

        .EXAMPLE
            Publish-XmipChange -m 'Operate is the fourth purpose' -WhatIf

        .EXAMPLE
            Publish-XmipChange 'Identities are configured per purpose'

        .EXAMPLE
            Publish-XmipChange -m 'Fix a typo in the README' -NoVerify

        .EXAMPLE
            xmip-git -m 'Arrivals and departures'

        .EXAMPLE
            xgit -Pin
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0)]
        [Alias('m')]
        [string] $Message = 'Pin the estate',

        [Parameter()]
        [switch] $All,

        [Parameter()]
        [switch] $NoVerify,

        [Parameter()]
        [switch] $Pin,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $RepositoryRoot = (Get-XmipRepositoryRoot)
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if ($Pin) {
        Publish-XmipPin -RepositoryRoot $RepositoryRoot -Message $Message

        return
    }

    # Not $all. PowerShell variable names are case-insensitive, so that name
    # overwrites the -All switch parameter and the next call hands an array to
    # a [switch].
    $estate = @(Get-XmipStatus -RepositoryRoot $RepositoryRoot -Short)

    # The platform repository is landed by the pin step rather than as a
    # module, because its commit has to be last: it records where the modules
    # ended up.
    $status = @($estate | Where-Object { $_.Module -ne '.' -and $_.Changed -gt 0 })

    # Ahead means committed and not pushed — from an interrupted run, usually.
    # Landing continues; this only says so, because it is the difference
    # between "nothing happened" and "the last run stopped halfway".
    $unpushed = @($estate | Where-Object { $_.Changed -eq 0 -and $_.AheadBy -gt 0 })

    foreach ($module in $unpushed) {
        Write-Warning "$($module.Module) is $($module.AheadBy) commit(s) ahead of origin and has nothing uncommitted."
    }

    $stale = @($estate | Where-Object { $_.BehindBy -gt 0 })

    foreach ($module in $stale) {
        Write-Warning "$($module.Module) is $($module.BehindBy) commit(s) behind origin. Pull before landing."
    }

    $platform = @($estate | Where-Object { $_.Module -eq '.' -and $_.Changed -gt 0 })

    if ($status.Count -eq 0 -and $platform.Count -eq 0) {
        Write-Host 'Nothing to land.' -ForegroundColor DarkGray
        return
    }

    if ($status.Count -eq 0) {
        Write-Host 'Only the platform repository has changes.' -ForegroundColor Cyan
        Publish-XmipPin -RepositoryRoot $RepositoryRoot -Message $Message

        # Landed is empty and that is correct: it counts modules and no module
        # changed. Platform says the run did something, because `Landed {}` and
        # `Verified False` on their own read as a failed run — which is how a
        # successful landing was reported as nothing happening on 2026-08-29.
        return [PSCustomObject]@{
            Landed   = @()
            Skipped  = @()
            Platform = $true
            Verified = $false
        }
    }

    $suspect = @($status | Where-Object Suspicious)

    if ($suspect.Count -gt 0) {
        Write-Host 'REFUSED. These have changes that look like build output:' -ForegroundColor Red
        $suspect | ForEach-Object { Write-Host "  $($_.Module)" }
        Write-Host ''
        Write-Host 'Get-XmipStatus | Where-Object Suspicious    shows which files.'
        Write-Host 'Add them to .gitignore, then run again.'

        return
    }

    $ordered = @(
        Sort-XmipModuleDependency -RepositoryRoot $RepositoryRoot -Module $status.Module
    )

    Write-Host "Landing $($ordered.Count) module(s), dependencies first:" -ForegroundColor Cyan
    $ordered | ForEach-Object { Write-Host "  $_" }

    # Test and land one module at a time, in order.
    #
    # Not test-everything-then-land-everything. Dependencies resolve against
    # `main`, so a module cannot be tested against a sibling that is still only
    # local — it would resolve the published version and fail for a reason that
    # is not there. The dependency has to be on origin first, which means
    # landing happens between tests rather than after all of them.
    #
    # The cost is that a failure halfway leaves the earlier modules landed. That
    # is recoverable — fix and run again — and it is the only order that can
    # work at all.
    $landed = [System.Collections.Generic.List[string]]::new()
    $skipped = [System.Collections.Generic.List[string]]::new()

    foreach ($module in $ordered) {
        if (-not $NoVerify) {
            # Nothing here can verify a module with no Cargo.toml — cli is
            # .NET 11, gui and powershell carry their own languages under
            # ADR-0014 clause 14. Left alone rather than landed unverified, and
            # -All is how you say land it anyway.
            $manifest = Join-Path -Path $RepositoryRoot -ChildPath "$module/Cargo.toml"

            if (-not $All -and -not (Test-Path -LiteralPath $manifest)) {
                $why = "SKIPPED. $module has no Cargo.toml, so nothing here can verify it."
                Write-Host $why -ForegroundColor DarkGray
                $skipped.Add($module)

                continue
            }

            $failed = @(Test-XmipModule -RepositoryRoot $RepositoryRoot -Module @($module) -All:$All)

            if ($failed.Count -gt 0) {
                Write-Host ''
                Write-Host "FAILED. Stopping at $module." -ForegroundColor Red

                if ($landed.Count -gt 0) {
                    Write-Host "  landed before it: $($landed -join ', ')" -ForegroundColor Yellow
                    Write-Host 'Fix this one and run again; the rest will be skipped as clean.'
                }
                else {
                    Write-Host 'Nothing landed this run.'
                }

                # Once, either way.
                #
                # Stopping the run is right; leaving the estate unpinned is not,
                # because the pin describes what is on origin and the modules
                # that landed *are* on origin. And a previous run may have left
                # gitlinks stale whether or not this one added to them, so this
                # is not conditional on $landed. Publish-XmipPin no-ops when
                # there is nothing to pin.
                #
                # -Message, because this stages the platform repository too. Its
                # absence here is what discarded the operator's message on
                # 2026-08-29: the subject rule was only half the defect, and the
                # other half was never passing the subject in.
                Publish-XmipPin -RepositoryRoot $RepositoryRoot -Message $Message

                return [PSCustomObject]@{
                    Landed   = $landed.ToArray()
                    Skipped  = $skipped.ToArray()
                    Platform = $true
                    Verified = $true
                }
            }
        }

        $result = @(
            Submit-XmipModule -RepositoryRoot $RepositoryRoot -Module @($module) -Message $Message
        )

        $result | ForEach-Object { $landed.Add($_) }
    }

    Publish-XmipPin -RepositoryRoot $RepositoryRoot -Message $Message

    if ($skipped.Count -gt 0) {
        Write-Host "SKIPPED, unverifiable here: $($skipped -join ', ')" -ForegroundColor DarkGray
    }

    [PSCustomObject]@{
        Landed   = $landed.ToArray()
        Skipped  = $skipped.ToArray()
        Platform = $true
        Verified = -not $NoVerify
    }
}

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

function Import-XmipPoshGit {
    <#
        .SYNOPSIS
            Loads posh-git, and says how to get it when it is absent.

        .DESCRIPTION
            Imported on demand rather than declared in RequiredModules, for the
            same reason PSToml is: this module has to load on a machine that
            does not have its prerequisites yet, because
            Install-XmipPrerequisite is how they arrive.
    #>
    [CmdletBinding()]
    param()

    if (Get-Module -Name posh-git) {
        return
    }

    if (-not (Get-Module -ListAvailable -Name posh-git)) {
        throw @'
posh-git is not installed.

    Install-XmipPrerequisite -Role operator

or, on its own:

    Install-Module posh-git -Scope CurrentUser
'@
    }

    Import-Module -Name posh-git -ErrorAction Stop
}

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

function Get-XmipDeclaredModule {
    <#
        .SYNOPSIS
            Every submodule path in .gitmodules, in file order.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot
    )

    $modulesFile = Join-Path -Path $RepositoryRoot -ChildPath '.gitmodules'

    if (-not (Test-Path -LiteralPath $modulesFile)) {
        throw "No .gitmodules under $RepositoryRoot. Is that the Xmip working tree?"
    }

    $matchParams = @{
        Path    = $modulesFile
        Pattern = '^\s*path\s*=\s*(?<path>.+)$'
    }

    Select-String @matchParams |
        ForEach-Object { $_.Matches[0].Groups['path'].Value.Trim() }
}

function Sort-XmipModuleDependency {
    <#
        .SYNOPSIS
            Orders modules so that nothing is landed before what it depends on.

        .DESCRIPTION
            Reads each manifest's package name and its Xmip dependencies, then
            repeatedly takes every module whose dependencies are already placed.

            Iterative rather than a recursive walk. The recursive version
            depended on a nested function seeing the parent's collections
            through PowerShell's scope rules, and silently emitted one module
            out of three — the kind of failure that looks like a smaller change
            set rather than like a bug.

            A cycle is reported rather than quietly broken. Cargo would refuse
            it anyway, and an arbitrary order here would turn a manifest error
            into a mysterious build failure.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Module
    )

    $package = @{}
    $needs = @{}

    foreach ($name in $Module) {
        $manifest = Join-Path -Path $RepositoryRoot -ChildPath "$name/Cargo.toml"

        if (-not (Test-Path -LiteralPath $manifest)) {
            # No manifest, no declared dependencies. Lands whenever.
            $needs[$name] = @()
            continue
        }

        $text = Get-Content -LiteralPath $manifest -Raw

        if ($text -match '(?m)^name\s*=\s*"(?<name>[^"]+)"') {
            $package[$Matches['name']] = $name
        }

        $needs[$name] = @(
            [regex]::Matches($text, '(?m)^\s*(?<alias>xmip[a-z0-9-]*)\s*=\s*\{(?<body>[^}]*)\}') |
                ForEach-Object {
                    $body = $_.Groups['body'].Value

                    if ($body -match 'package\s*=\s*"(?<package>[^"]+)"') {
                        $Matches['package']
                    }
                    else {
                        $_.Groups['alias'].Value
                    }
                }
        )
    }

    $placed = [System.Collections.Generic.List[string]]::new()
    $waiting = [System.Collections.Generic.List[string]]::new()
    $Module | ForEach-Object { $waiting.Add($_) }

    while ($waiting.Count -gt 0) {
        $ready = @(
            $waiting | Where-Object {
                # Named, not $PSItem. Each nested pipeline rebinds $_ *and*
                # $PSItem — they are the same variable — so the inner
                # Where-Object's $PSItem is the resolved dependency, never the
                # module being tested. Written as `$_ -ne $PSItem` it compared a
                # value with itself, filtered out every blocker, and made every
                # module look ready. The sort then emitted its input order,
                # which is alphabetical, and authenticate was tested before the
                # identify and context it depends on.
                $module = $_

                $blockers = @(
                    $needs[$module] |
                        ForEach-Object { $package[$_] } |
                        Where-Object { $_ -and $_ -ne $module -and $waiting.Contains($_) }
                )

                $blockers.Count -eq 0
            }
        )

        if ($ready.Count -eq 0) {
            throw "The manifests declare a dependency cycle among: $($waiting -join ', ')"
        }

        foreach ($name in $ready) {
            $placed.Add($name)
            [void] $waiting.Remove($name)
        }
    }

    $placed
}

# Features whose code does not compile, and the module that owns each.
#
# A shrink-only list, the same instrument as the file-length ratchet in
# Rust.Style.Tests.ps1 and for the same reason: a waiver list absorbs new
# entries and its maintenance becomes the work, while this can only be emptied.
# Adding to it is a decision somebody has to argue for; removing is just fixing
# the feature.
#
# Both entries were found on 2026-08-29, the day --all-features was first run:
#
#   tls               http/tls.rs calls rustls::crypto::ring::default_provider()
#                     and Cargo.toml asks for rustls with default features, so
#                     the ring provider is configured out.
#   dynamic-loading   host.rs imports validate_module_abi, ModuleAbiDescriptor
#                     and XMIP_MODULE_ENTRYPOINT. xmip-core-abi defines none of
#                     the three; ADR-0025 clause 5 says what it should define.
$script:XmipUnbuildableFeature = @{
    'modules/capabilities/transport' = @('tls')
    'modules/platform/runtime'       = @('dynamic-loading')
}

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

    foreach ($module in $Module) {
        $path = Join-Path -Path $RepositoryRoot -ChildPath $module
        $manifest = Join-Path -Path $path -ChildPath 'Cargo.toml'

        if (-not (Test-Path -LiteralPath $manifest)) {
            # Reported, never returned.
            #
            # This function returns modules that *failed*, and returning one
            # that could not be tested made the caller stop the entire run on
            # modules/operations/cli — which is .NET 11 and has no Cargo.toml by
            # design. Cannot be verified here and did not fail are different
            # answers, and only one of them should halt the estate.
            #
            # Whether an unverifiable module lands is the caller's decision, and
            # -All is where it is made.
            Write-Host "== $module (no Cargo.toml, nothing here can test it)" -ForegroundColor DarkGray

            continue
        }

        Write-Host "== $module" -ForegroundColor Cyan

        Push-Location -LiteralPath $path

        try {
            # Dependencies track main, so the lock is re-resolved or the test
            # runs against whatever was current when anyone last built.
            & cargo update 2>&1 | Out-Null

            # Captured, not emitted. This function returns the modules that
            # failed; a native command left to write into the pipeline makes
            # every line of its output a return value, and the caller reads
            # cargo's passing tests as the list of failures.
            $output = & cargo test 2>&1
            $passed = $LASTEXITCODE -eq 0

            # Only when the tests passed. A module that fails its tests is
            # already failing, and a second wall of compiler output buries the
            # error the operator has to read.
            if ($passed) {
                [string[]] $features = Get-XmipBuildableFeature -ManifestPath $manifest -Module $module

                if ($features.Count -gt 0) {
                    $output += "   building $($features.Count) declared feature(s): $($features -join ', ')"
                    $output += & cargo build --features ($features -join ',') 2>&1
                    $passed = $LASTEXITCODE -eq 0
                }
            }
        }
        finally {
            Pop-Location
        }

        # Information stream, so it reaches the console and any redirect.
        $output | ForEach-Object { Write-Host $_ }

        if (-not $passed) {
            $module
        }
    }
}

function Submit-XmipModule {
    <#
        .SYNOPSIS
            Commits and pushes each module, in the order given.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Module,

        [Parameter(Mandatory)]
        [string] $Message
    )

    foreach ($module in $Module) {
        $path = Join-Path -Path $RepositoryRoot -ChildPath $module

        if (-not $PSCmdlet.ShouldProcess($module, 'commit and push')) {
            continue
        }

        # A submodule at a bare commit has no branch to push to.
        $branch = (& git -C $path branch --show-current) -join ''

        if ([string]::IsNullOrWhiteSpace($branch)) {
            Write-Host "   NOTE: detached HEAD, checking out main" -ForegroundColor Yellow
            & git -C $path checkout main
        }

        & git -C $path add -A
        & git -C $path commit -m $Message --quiet
        & git -C $path push origin main --quiet

        if ($LASTEXITCODE -ne 0) {
            throw "Pushing $module failed. Anything before it is already on origin; fix this and run again."
        }

        Write-Host "   OK, landed" -ForegroundColor Green
        $module
    }
}

function Resolve-XmipCommitSubject {
    <#
        .SYNOPSIS
            The subject line for a superproject commit, from what is staged.

        .DESCRIPTION
            **A pin is a commit that contains nothing but gitlinks.** That is the
            whole rule, and the test is what else is staged rather than how many
            gitlinks there are.

            The defect this replaces, on 2026-08-29: the condition was
            `$pins.Count -eq 0 -and $Message`, so the caller's message was used
            only when *no* gitlink was staged. Two commits went in under "Pin 1
            module" while carrying an ADR, a test file and a documentation
            change, because each also moved one gitlink. The message a person
            typed was discarded by a rule about a file they did not name.

            A commit that moves gitlinks *and* changes the platform repository
            takes the caller's message: the gitlinks are incidental to what the
            person did, and `git show --stat` says so anyway. Only a commit that
            is gitlinks and nothing else has no author's intent to record.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Staged,

        [Parameter()]
        [string] $Message
    )

    $pins = @($Staged | Where-Object { $_ -like 'modules/*' })

    if ($pins.Count -ne $Staged.Count -and $Message) {
        return $Message
    }

    $noun = if ($pins.Count -eq 1) { 'module' } else { 'modules' }

    return "Pin $($pins.Count) $noun"
}

function Publish-XmipPin {
    <#
        .SYNOPSIS
            Moves the superproject's gitlinks to where the modules now are.

        .DESCRIPTION
            Counts what it is actually pinning rather than being told. The two
            numbers are not the same and the difference is the bug this was
            written to stop: a run that lands six modules and fails on the
            seventh leaves six stale gitlinks, and a later run that lands
            nothing still has six to pin. Told "nothing landed", the pin would
            skip; asked "what is dirty", it does the right thing either way.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter()]
        [string] $Message
    )

    if (-not $PSCmdlet.ShouldProcess('the estate', 'pin and push')) {
        return
    }

    & git -C $RepositoryRoot add -A

    # What is staged, not what is dirty. `git status --porcelain` reports a
    # submodule as modified when the only change is an untracked file *inside*
    # it — content the superproject cannot stage and has no business committing.
    # Counting those meant committing nothing, printing git's "no changes added
    # to commit" at the operator, and calling it a pin.
    $staged = @(& git -C $RepositoryRoot diff --cached --name-only)

    if ($staged.Count -eq 0) {
        Write-Host 'Estate already pinned.' -ForegroundColor DarkGray
        return
    }

    $pins = @($staged | Where-Object { $_ -like 'modules/*' })
    $noun = if ($pins.Count -eq 1) { 'module' } else { 'modules' }

    $subject = Resolve-XmipCommitSubject -Staged $staged -Message $Message

    & git -C $RepositoryRoot commit -m $subject --quiet
    & git -C $RepositoryRoot push origin main --quiet

    if ($LASTEXITCODE -ne 0) {
        throw 'Pushing the estate failed. The modules are landed; only the pin is missing.'
    }

    # Three outcomes, because there are three. Reporting "Pinned 1 module" over a
    # commit that also carried an ADR and a test file is how the wrong subject
    # went unnoticed for two commits: the line printed at the operator agreed
    # with the line written into git, and both were wrong.
    if ($pins.Count -eq 0) {
        Write-Host 'OK. Platform repository landed.' -ForegroundColor Green
    }
    elseif ($staged.Count -eq $pins.Count) {
        Write-Host "OK. Pinned $($pins.Count) $noun." -ForegroundColor Green
    }
    else {
        Write-Host "OK. Platform repository landed, $($pins.Count) $noun pinned." -ForegroundColor Green
    }
}

# The estate talks about `xmip-git`; PowerShell talks about
# `Publish-XmipChange`. An alias is how both are true at
# once: Xmip is not an approved verb, so a *function* by that name warns on
# import and disappears from `Get-Command -Verb`, while an alias is exempt and
# costs nothing.
Set-Alias -Name xmip-git -Value Publish-XmipChange
Set-Alias -Name xgit -Value Publish-XmipChange
