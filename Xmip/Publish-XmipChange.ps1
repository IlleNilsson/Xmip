#requires -PSEdition Core
#requires -Version 7.6.5

using namespace System.Collections.Generic

<#
.SYNOPSIS
    What the estate's repositories need instead of `git status` and `git push`.

.DESCRIPTION
    Three commands, named and parameterised to read like the git underneath
    them.

        Get-XmipStatus                  git status, across the estate
        Publish-XmipChange -m '...'     git add, commit and push, in dependency
                                        order, having tested first
        Publish-XmipPin                 move the superproject's gitlinks

    This file holds the second; since 2026-09-22 the parts it is made of are
    files of their own, each named for what it defines — Get-XmipStatus,
    Get-XmipDeclaredModule (what lands, in what order), Test-XmipModule and
    Test-XmipDotnetModule (verifying one), Submit-XmipModule (landing one) and
    Publish-XmipPin.

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

    Style: doc/governance/powershell-style.md
#>


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
            Publish-XmipChange -Message 'Identities are configured per purpose'

        .EXAMPLE
            Publish-XmipChange -m 'Fix a typo in the README' -NoVerify

        .EXAMPLE
            xmip-git -m 'Arrivals and departures'

        .EXAMPLE
            xgit -Pin
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType('Xmip.Change')]
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

    # A landing that failed is audited, whatever failed in it (ADR-0062): a
    # throw ends the call here, is recorded, and goes on to the caller
    # unchanged. A landing that stopped at a module says so below.
    trap {
        Write-XmipAudit -Action 'Publish-XmipChange' -ErrorRecord $_
        break
    }

    # Not $all. PowerShell variable names are case-insensitive, so that name
    # overwrites the -All switch parameter and the next call hands an array to
    # a [switch].
    #
    # Read before the -Pin branch, not after. -Pin is the repair path and it
    # pins whatever the gitlinks say, so it can publish an unpushed module
    # exactly as the landing path could. Asking what the estate looks like is
    # the first thing either path needs.
    [object[]] $estate = @(Get-XmipStatus -RepositoryRoot $RepositoryRoot -Short)

    # The platform repository is landed by the pin step rather than as a
    # module, because its commit has to be last: it records where the modules
    # ended up.
    [object[]] $status = @($estate | Where-Object { $_.Module -ne '.' -and $_.Changed -gt 0 })

    # Ahead means committed and not pushed — from an interrupted run, usually.
    #
    # This used to warn and carry on, and carrying on is what made it a defect:
    # the pin step stages every moved gitlink whether or not this run landed the
    # module, so the estate was pinned to commits origin had never seen. Pushed
    # first, before anything can pin them. See Publish-XmipUnpushed.
    # Modules only. The platform repository being ahead is Publish-XmipPin's
    # own case and it has a branch for it — pushing the superproject here would
    # take that decision away from the step whose commit it is.
    [object[]] $unpushed = @(
        $estate | Where-Object { $_.Module -ne '.' -and $_.Changed -eq 0 -and $_.AheadBy -gt 0 }
    )

    foreach ($module in $unpushed) {
        Write-Warning ("$($module.Module) is $($module.AheadBy) commit(s) ahead of origin " +
            'and has nothing uncommitted.')
    }

    # Pushed here only on the repair path. A landing pushes them after the
    # tree verifies, so a failure pushes nothing (an external review,
    # 2026-10-05).
    if ($Pin) {
        if ($unpushed.Count -gt 0) {
            Publish-XmipUnpushed -RepositoryRoot $RepositoryRoot -Module @($unpushed.Module)
        }

        Publish-XmipPin -RepositoryRoot $RepositoryRoot -Message $Message

        return
    }

    [object[]] $stale = @($estate | Where-Object { $_.BehindBy -gt 0 })

    foreach ($module in $stale) {
        Write-Warning ("$($module.Module) is $($module.BehindBy) commit(s) behind origin. " +
            'Pull before landing.')
    }

    [object[]] $platform = @($estate | Where-Object { $_.Module -eq '.' -and $_.Changed -gt 0 })

    if ($status.Count -eq 0 -and $platform.Count -eq 0) {
        Write-Host 'Nothing to land.' -ForegroundColor DarkGray
        return
    }

    if ($status.Count -eq 0) {
        Write-Host 'Only the platform repository has changes.' -ForegroundColor Cyan

        if (-not $NoVerify -and -not (Test-XmipPlatform -RepositoryRoot $RepositoryRoot)) {
            [string] $unverified = 'The platform repository did not verify; nothing landed.'
            Write-Error $unverified -ErrorAction Continue

            return
        }

        if ($unpushed.Count -gt 0) {
            Publish-XmipUnpushed -RepositoryRoot $RepositoryRoot -Module @($unpushed.Module)
        }

        Publish-XmipPin -RepositoryRoot $RepositoryRoot -Message $Message

        # Landed is empty and that is correct: it counts modules and no module
        # changed. Platform says the run did something, because `Landed {}` and
        # `Verified False` on their own read as a failed run — which is how a
        # successful landing was reported as nothing happening on 2026-08-29.
        return [PSCustomObject]@{
            PSTypeName = 'Xmip.Change'
            Landed     = @()
            Skipped    = @()
            Platform   = $true
            Verified   = $false
        }
    }

    [object[]] $suspect = @($status | Where-Object Suspicious)

    if ($suspect.Count -gt 0) {
        Write-Host 'REFUSED. These have changes that look like build output:' -ForegroundColor Red
        $suspect | ForEach-Object { Write-Host "  $($_.Module)" }
        Write-Host ''
        Write-Host 'Get-XmipStatus | Where-Object Suspicious    shows which files.'
        Write-Host 'Add them to .gitignore, then run again.'

        return
    }

    # What changed lands; what consumes it, unchanged, is compiled and linted
    # against it so a broken API shows before anything is pushed.
    [string[]] $consumers = @(
        Get-XmipModuleConsumer -RepositoryRoot $RepositoryRoot -Module $status.Module
    )
    [string[]] $ordered = @(
        Sort-XmipModuleDependency -RepositoryRoot $RepositoryRoot -Module (
            @($status.Module) + $consumers)
    )

    Write-Host "Landing $($status.Count) module(s), dependencies first:" -ForegroundColor Cyan
    $ordered | Where-Object { $consumers -notcontains $_ } | ForEach-Object { Write-Host "  $_" }
    [string] $against = "Checking $($consumers.Count) unchanged consumer(s) against them."
    Write-Host $against -ForegroundColor Cyan

    # The dependency tree is verified whole, then landed whole (the owner,
    # 2026-10-05: *Do dependecy tree build and stop when a leaf fails*).
    [hashtable] $tree = @{
        RepositoryRoot = $RepositoryRoot
        Ordered        = $ordered
        Consumer       = $consumers
        Platform       = $platform.Count -gt 0
        All            = $All
        NoVerify       = $NoVerify
        Message        = $Message
    }
    [pscustomobject] $checked = Test-XmipChangeTree @tree
    [List[string]] $landed = [List[string]]::new()
    [List[string]] $skipped = [List[string]]::new()
    $checked.Skipped | ForEach-Object { $skipped.Add($_) }
    [string[]] $verified = $checked.Verified

    if ($checked.Failed) {
        return [PSCustomObject]@{
            PSTypeName = 'Xmip.Change'
            Landed     = @()
            Skipped    = $skipped.ToArray()
            Platform   = $false
            Verified   = $false
        }
    }

    # The whole tree verified: push what an interrupted run left committed,
    # then land what changed, dependencies first, without building again.
    if ($unpushed.Count -gt 0) {
        Publish-XmipUnpushed -RepositoryRoot $RepositoryRoot -Module @($unpushed.Module)
    }

    foreach ($module in @($verified | Where-Object { $consumers -notcontains $_ })) {
        [string[]] $result = @(
            Submit-XmipModule -RepositoryRoot $RepositoryRoot -Module @($module) -Message $Message
        )

        $result | ForEach-Object { $landed.Add($_) }
    }

    Publish-XmipPin -RepositoryRoot $RepositoryRoot -Message $Message

    if ($skipped.Count -gt 0) {
        Write-Host "SKIPPED, unverifiable here: $($skipped -join ', ')" -ForegroundColor DarkGray
    }

    Write-XmipAudit -Action 'Publish-XmipChange' -Phase Finished -Property @{
        Landed   = $landed
        Skipped  = $skipped
        Verified = -not $NoVerify
        Subject  = $Message
    }

    [PSCustomObject]@{
        PSTypeName = 'Xmip.Change'
        Landed     = $landed.ToArray()
        Skipped    = $skipped.ToArray()
        Platform   = $true
        Verified   = -not $NoVerify
    }
}


# The estate talks about `xmip-git`; PowerShell talks about
# `Publish-XmipChange`. An alias is how both are true at
# once: Xmip is not an approved verb, so a *function* by that name warns on
# import and disappears from `Get-Command -Verb`, while an alias is exempt and
# costs nothing.
Set-Alias -Name xmip-git -Value Publish-XmipChange
Set-Alias -Name xgit -Value Publish-XmipChange
