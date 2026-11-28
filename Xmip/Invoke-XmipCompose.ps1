#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    Mounting the estate's repositories where the manifest says, and the
    workspace written over what is mounted.

.DESCRIPTION
    Nested inside Sync-XmipEstate until 2026-09-22, which made that one function
    719 lines against the 400 the estate allows a file, and let every helper
    read the GitHub token and address out of its scope unseen. Lifted when the
    owner asked for the estate to be consolidated; each now takes the
    connection it uses as a parameter, -GitHub.

    Style: doc/governance/powershell-style.md
#>

function Invoke-XmipCompose {
    # Short on purpose: the plan is computed at file scope, so this only
    # performs it. ShouldProcess is why it cannot move out with the rest.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Manifest,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Actual
    )

    Assert-XmipCommand -Name 'git'

    [string] $root = Get-XmipRepositoryRoot
    [string] $owner = [string](Get-XmipPropertyValue -Object $Manifest -Name 'owner')
    $plan = Get-XmipComposePlan -Manifest $Manifest -Actual $Actual -Root $root
    [int] $added = 0

    foreach ($item in @($plan.ready)) {
        if (-not $PSCmdlet.ShouldProcess("$($item.Mount) -> $($item.Name)", 'Add submodule')) {
            continue
        }

        [string] $url = "https://github.com/$owner/$($item.Name).git"
        [string[]] $arguments = @('submodule', 'add', '--', $url, $item.Mount)

        Invoke-XmipGit -At $root -Arguments $arguments | Out-Null
        Write-Host "COMPOSED: $($item.Mount)"
        $added++
    }

    [int] $moved = 0
    [int] $refused = 0

    foreach ($item in @($plan.misplaced)) {
        [string] $what = '{0}: {1} -> {2}' -f $item.Name, $item.From, $item.Mount

        if (-not $PSCmdlet.ShouldProcess($what, 'Move submodule')) {
            continue
        }

        # A rename refused is refused whole, so the rest can still move; the
        # summary says how many did not.
        try {
            Move-XmipSubmodule -Root $root -From $item.From -To $item.Mount
        }
        catch {
            Write-Host "REFUSED: $what — $($_.Exception.Message)"
            $refused++
            continue
        }

        # git mv rewrites .gitmodules and leaves it unstaged, and the next
        # git mv refuses to run while it is. So one move at a time is all a
        # run used to manage (found moving 25 modules, 2026-09-23).
        Invoke-XmipGit -At $root -Arguments @('add', '.gitmodules') | Out-Null

        Write-Host "MOVED: $what"
        $moved++
    }

    [string] $summary =
        'Compose: {0} added, {1} moved, {2} refused, {3} already mounted, {4} waiting' -f
        $added, $moved, $refused, $plan.mounted, $plan.waiting

    Write-XmipStep -Message $summary

    # Every crate mounted is a member of the estate's one workspace, and every
    # estate dependency takes its crate from the root by its mount (ADR-0016,
    # amendments 2026-11-20 and 2026-11-27; ADR-0005, amendment 2026-11-28).
    Update-XmipWorkspace -RepositoryRoot $root

    if (0 -lt $added) {
        Write-XmipStep -Message 'Review .gitmodules, then commit. Nothing was pushed.'
    }
}
