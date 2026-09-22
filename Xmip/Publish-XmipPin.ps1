#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    Moving the superproject's gitlinks to where the modules now are.

.DESCRIPTION
    Apart from Publish-XmipChange.ps1 since 2026-09-22, when that file had grown
    to 1,586 lines against the 400 the estate allows a file, and the owner asked
    for the estate to be consolidated. The landing is one command made of several
    subjects; each subject is a file.

    Style: doc/governance/powershell-style.md
#>


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
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter()]
        [string] $Message
    )

    if (-not $PSCmdlet.ShouldProcess('the estate', 'pin and push')) {
        return
    }

    # Nested first. A Technology's gitlink lives in its parent Capability's
    # repository, not here, so that parent has to record and push the moved
    # gitlink before the superproject can pin the parent. Deepest first, so a
    # chain of nesting settles from the bottom up; then the superproject below
    # sees each parent's own gitlink move and pins that.
    foreach ($parent in @(Get-XmipNestedParent -RepositoryRoot $RepositoryRoot)) {
        $parentPath = Join-Path -Path $RepositoryRoot -ChildPath $parent
        & git -C $parentPath add -A

        # Staged, not dirty — the same reason the superproject uses below: an
        # untracked file inside a grandchild reads as modified but is not the
        # parent's to commit.
        $nested = @(& git -C $parentPath diff --cached --name-only)

        if ($nested.Count -eq 0) {
            continue
        }

        Write-Host "   pinning nested in $parent..." -ForegroundColor DarkGray
        $subject = Resolve-XmipCommitSubject -Staged $nested -Message $Message
        & git -C $parentPath commit -m $subject --quiet
        & git -C $parentPath push origin main --quiet

        if ($LASTEXITCODE -ne 0) {
            throw "Pinning nested modules in $parent failed. " +
                'The technology is on origin; only its gitlink is missing.'
        }
    }

    # The estate map is generated from what is mounted and what each mount
    # holds (ADR-0060), and every module this landing moved changed what it
    # holds, so the pin is the one moment the map can be made true of exactly
    # what is being pinned. It was left to whoever remembered until
    # 2026-09-21, and nobody could: a change to one technology three levels
    # down made the superproject's map wrong without touching the
    # superproject, and the owner read a stale map twice in a day.
    #
    # A map that will not generate warns rather than stopping the pin. The
    # modules are on origin already, and an estate whose gitlinks point at
    # where the modules were is worse than a map a line count behind.
    try {
        New-XmipEstateMap -Root $RepositoryRoot -Save | Out-Null
    }
    catch {
        Write-Warning "The estate map was not regenerated: $($_.Exception.Message)"
    }

    & git -C $RepositoryRoot add -A

    # What is staged, not what is dirty. `git status --porcelain` reports a
    # submodule as modified when the only change is an untracked file *inside*
    # it — content the superproject cannot stage and has no business committing.
    # Counting those meant committing nothing, printing git's "no changes added
    # to commit" at the operator, and calling it a pin.
    $staged = @(& git -C $RepositoryRoot diff --cached --name-only)

    if ($staged.Count -eq 0) {
        # Committed is not pushed. On 2026-08-30 a rebase left the pin commit
        # in place with a clean tree; this branch said 'already pinned' and
        # returned, and the estate sat one commit ahead of a remote that had
        # never seen it. Nothing to commit still means everything to push.
        [string] $ahead = (& git -C $RepositoryRoot rev-list --count '@{upstream}..HEAD') -join ''

        if ($ahead -ne '0' -and -not [string]::IsNullOrWhiteSpace($ahead)) {
            Write-Host "   pushing $ahead committed pin(s) to origin..." -ForegroundColor DarkGray
            & git -C $RepositoryRoot push origin main --quiet

            if ($LASTEXITCODE -ne 0) {
                throw 'Pushing the estate failed. The pin is committed; only the push is missing.'
            }

            Write-Host 'OK. Estate pushed.' -ForegroundColor Green

            return
        }

        Write-Host 'Estate already pinned.' -ForegroundColor DarkGray
        return
    }

    $pins = @($staged | Where-Object { $_ -like 'module/*' })
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
        [string] $said = "OK. Platform repository landed, $($pins.Count) $noun pinned."
        Write-Host $said -ForegroundColor Green
    }
}
