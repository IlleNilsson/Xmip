#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    Mounting the estate's repositories where the manifest says, and rewriting their Cargo.toml.

.DESCRIPTION
    Nested inside Sync-XmipEstate until 2026-09-22, which made that one function
    719 lines against the 400 the estate allows a file, and let every helper
    read the GitHub token and address out of its scope unseen. Lifted when the
    owner asked for the estate to be consolidated; each now takes the
    connection it uses as a parameter, -GitHub.

    Style: doc/governance/powershell-style.md
#>

function Invoke-Compose {
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

    Assert-Command 'git'

    [string] $root = Get-XmipRepositoryRoot
    [string] $owner = [string](Get-PropertyValue $Manifest 'owner')
    $plan = Get-XmipComposePlan -Manifest $Manifest -Actual $Actual -Root $root
    [int] $added = 0

    foreach ($item in @($plan.ready)) {
        if (-not $PSCmdlet.ShouldProcess("$($item.Mount) -> $($item.Name)", 'Add submodule')) {
            continue
        }

        [string] $url = "https://github.com/$owner/$($item.Name).git"
        [string[]] $arguments = @('submodule', 'add', '--', $url, $item.Mount)

        Invoke-Native -FilePath 'git' -Arguments $arguments -At $root | Out-Null
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
        Invoke-Native -FilePath 'git' -Arguments @('add', '.gitmodules') -At $root | Out-Null

        Write-Host "MOVED: $what"
        $moved++
    }

    [string] $summary =
        ('Compose: {0} added, {1} moved, {2} refused, {3} already mounted, {4} waiting, ' +
        '{5} deprecated') -f $added, $moved, $refused, $plan.mounted, $plan.waiting, $plan.retired

    Write-Step $summary

    if (0 -lt $added) {
        Write-Step 'Review .gitmodules, then commit. Nothing was pushed.'
    }
}

function Invoke-Cargo {
    # Rewrites nothing that is already right, so it is safe to run twice.
    [CmdletBinding()]
    param()

    Assert-Command 'git'

    [string] $root = Get-XmipRepositoryRoot
    [hashtable] $mountOf = Get-XmipMountedPath -Root $root
    [hashtable] $pinnedAt = Get-XmipPinnedCommit -Root $root -MountOf $mountOf

    [hashtable] $edits = @{}
    [int] $revs = 0

    [object[]] $findings = @(Get-XmipCrateFinding -Root $root -MountOf $mountOf -PinnedAt $pinnedAt)

    foreach ($finding in $findings) {
        Write-Host ('  {0,-28} {1} -> {2}' -f $finding.Module, $finding.Was, $finding.Is)

        if (-not $edits.ContainsKey($finding.File)) {
            $edits[$finding.File] = @{}
        }

        $edits[$finding.File][$finding.Line] = $finding.New

        $revs++
    }

    foreach ($file in $edits.Keys) {
        if (-not $PSCmdlet.ShouldProcess($file, 'Rewrite Cargo.toml')) {
            continue
        }

        [string[]] $lines = @(Get-Content -LiteralPath $file)

        foreach ($line in $edits[$file].Keys) {
            $lines[$line - 1] = $edits[$file][$line]
        }

        Set-Content -LiteralPath $file -Value $lines -Encoding utf8NoBOM
    }

    [int] $rooted = 0

    foreach ($name in $mountOf.Keys) {
        [string] $file = Join-Path $root (Join-Path $mountOf[$name] 'Cargo.toml')

        if (-not (Test-Path -LiteralPath $file)) {
            continue
        }

        [string] $text = Get-Content -LiteralPath $file -Raw

        if ($text -match '(?m)^\s*\[workspace\]') {
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($name, 'Make its own workspace root')) {
            continue
        }

        # Cargo walks up from a package looking for a workspace, finds
        # Xmip/Cargo.toml and refuses to build. exclude in the parent is not
        # enough and does not travel: a standalone clone has no parent to
        # read it from. An empty [workspace] here stops the walk.
        [string[]] $header = @(
            '# Its own workspace root, so this repository builds on its own.',
            '[workspace]',
            ''
        )

        [hashtable] $write = @{
            LiteralPath = $file
            Value       = $header + @(Get-Content -LiteralPath $file)
            Encoding    = 'utf8NoBOM'
        }

        Set-Content @write

        Write-Host "  ROOTED: $name"
        $rooted++
    }

    if (0 -lt $rooted) {
        Write-Step "Cargo: $rooted modules made their own workspace root"
    }

    Write-Step "Cargo: $revs dependency revs in $($edits.Count) files"

    if (0 -lt $edits.Count) {
        Write-Step 'Each module is its own repository. Commit and push them individually.'
    }
}
