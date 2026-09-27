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
        [hashtable] $nested = @{
            At      = Join-Path -Path $RepositoryRoot -ChildPath $parent
            Message = $Message
            Saying  = "   pinning nested in $parent..."
        }

        Submit-XmipRepositoryChange @nested | Out-Null
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

    # Staged, not dirty: counting a submodule that holds only an untracked
    # file meant committing nothing, printing git's "no changes added to
    # commit" at the operator, and calling it a pin.
    [string[]] $staged = @(Submit-XmipRepositoryChange -At $RepositoryRoot -Message $Message)

    if ($staged.Count -eq 0) {
        # Committed is not pushed. On 2026-08-30 a rebase left the pin commit
        # in place with a clean tree; this branch said 'already pinned' and
        # returned, and the estate sat one commit ahead of a remote that had
        # never seen it. Nothing to commit still means everything to push.
        [int] $ahead = (Get-XmipRepositoryStatus -At $RepositoryRoot).AheadBy

        if ($ahead -gt 0) {
            Write-Host "   pushing $ahead committed pin(s) to origin..." -ForegroundColor DarkGray
            Invoke-XmipGit -At $RepositoryRoot -Arguments @('push', 'origin', 'main', '--quiet') |
                Out-Null

            Write-Host 'OK. Estate pushed.' -ForegroundColor Green

            return
        }

        Write-Host 'Estate already pinned.' -ForegroundColor DarkGray
        return
    }

    $pins = @($staged | Where-Object { $_ -like 'module/*' })
    $noun = if ($pins.Count -eq 1) { 'module' } else { 'modules' }

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
