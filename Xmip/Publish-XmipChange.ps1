#requires -PSEdition Core
#requires -Version 7.6

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

    Style: docs/governance/powershell-style.md
#>

function Get-XmipStatus {
    <#
        .SYNOPSIS
            `git status`, across the estate.

        .DESCRIPTION
            Every module that has something uncommitted, what it is, and whether
            it looks like source or like build output.

            Objects out, not text. `Get-XmipStatus | Where-Object Suspicious`
            answers "is anything about to commit a target directory again"
            without parsing anything.

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

        return [PSCustomObject]@{ Landed = @(); Verified = $false }
    }

    $suspect = @($status | Where-Object Suspicious)

    if ($suspect.Count -gt 0) {
        Write-Host 'Refusing. These have changes that look like build output:' -ForegroundColor Red
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

    foreach ($module in $ordered) {
        if (-not $NoVerify) {
            $failed = @(Test-XmipModule -RepositoryRoot $RepositoryRoot -Module @($module) -All:$All)

            if ($failed.Count -gt 0) {
                Write-Host ''
                Write-Host "Stopping at $module." -ForegroundColor Red

                if ($landed.Count -gt 0) {
                    Write-Host "Already landed: $($landed -join ', ')" -ForegroundColor Yellow
                    Write-Host 'Fix this one and run again; the rest will be skipped as clean.'

                    # Pin what did land, before returning.
                    #
                    # Without this, a failure halfway leaves the superproject
                    # holding gitlinks to commits that are no longer what those
                    # modules are on — one dirty submodule entry per module that
                    # succeeded. Stopping the run is right; leaving the estate
                    # unpinned is not, because the pin describes what is on
                    # origin and those modules *are* on origin.
                    Publish-XmipPin -RepositoryRoot $RepositoryRoot
                }
                else {
                    Write-Host 'Nothing landed this run.'
                }

                # Either way. A previous run may have left gitlinks stale, and
                # those modules are on origin whether or not this run added to
                # them. Publish-XmipPin no-ops when there is nothing to pin.
                Publish-XmipPin -RepositoryRoot $RepositoryRoot

                return [PSCustomObject]@{ Landed = $landed.ToArray(); Verified = $true }
            }
        }

        $result = @(
            Submit-XmipModule -RepositoryRoot $RepositoryRoot -Module @($module) -Message $Message
        )

        $result | ForEach-Object { $landed.Add($_) }
    }

    Publish-XmipPin -RepositoryRoot $RepositoryRoot

    [PSCustomObject]@{
        Landed   = $landed.ToArray()
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
                $blockers = @(
                    $needs[$_] |
                        ForEach-Object { $package[$_] } |
                        Where-Object { $_ -and $_ -ne $PSItem -and $waiting.Contains($_) }
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

function Test-XmipModule {
    <#
        .SYNOPSIS
            Runs each module's own tests. Returns the ones that failed.
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
            $note = if ($All) { 'landing anyway' } else { 'nothing here can test it' }
            Write-Host "== $module (no Cargo.toml, $note)" -ForegroundColor DarkGray

            if (-not $All) { $module }

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
            Write-Host "   detached HEAD, checking out main" -ForegroundColor Yellow
            & git -C $path checkout main
        }

        & git -C $path add -A
        & git -C $path commit -m $Message --quiet
        & git -C $path push origin main --quiet

        if ($LASTEXITCODE -ne 0) {
            throw "Pushing $module failed. Anything before it is already on origin; fix this and run again."
        }

        Write-Host "   landed" -ForegroundColor Green
        $module
    }
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

    $staged = @(& git -C $RepositoryRoot status --porcelain)

    if ($staged.Count -eq 0) {
        Write-Host 'Estate already pinned.' -ForegroundColor DarkGray
        return
    }

    # A gitlink shows as a path with no extension under modules/. Everything
    # else staged here is the platform repository's own content.
    $pins = @(
        $staged |
            ForEach-Object { $_.Substring(3) } |
            Where-Object { $_ -like 'modules/*' }
    )

    $noun = if ($pins.Count -eq 1) { 'module' } else { 'modules' }

    # Nothing under modules/ means the platform repository changed on its own,
    # and the caller's message is what describes that. Anything else is a pin.
    $subject =
        if ($pins.Count -eq 0 -and $Message) { $Message }
        else { "Pin $($pins.Count) $noun" }

    & git -C $RepositoryRoot commit -m $subject --quiet
    & git -C $RepositoryRoot push origin main --quiet

    if ($LASTEXITCODE -ne 0) {
        throw 'Pushing the estate failed. The modules are landed; only the pin is missing.'
    }

    if ($pins.Count -eq 0) {
        Write-Host 'Platform repository landed.' -ForegroundColor Green
    }
    else {
        Write-Host "Pinned $($pins.Count) $noun." -ForegroundColor Green
    }
}

# `xmip-git` reads the way the estate is talked about, and `Publish-XmipChange`
# reads the way PowerShell is talked about. An alias is how both are true at
# once: Xmip is not an approved verb, so a *function* by that name warns on
# import and disappears from `Get-Command -Verb`, while an alias is exempt and
# costs nothing.
Set-Alias -Name xmip-git -Value Publish-XmipChange
Set-Alias -Name xgit -Value Publish-XmipChange
