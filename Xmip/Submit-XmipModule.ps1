#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    Committing and pushing one verified module, under the landing's message.

.DESCRIPTION
    Apart from Publish-XmipChange.ps1 since 2026-09-22, when that file had grown
    to 1,586 lines against the 400 the estate allows a file, and the owner asked
    for the estate to be consolidated. The landing is one command made of several
    subjects; each subject is a file.

    Style: doc/governance/powershell-style.md
#>


function Publish-XmipUnpushed {
    <#
        .SYNOPSIS
            Pushes modules that are committed and not on origin.

        .DESCRIPTION
            A module can be committed without being pushed — an interrupted
            run, or an operator who committed by hand. Nothing is uncommitted,
            so the landing loop passes it by, and then `Publish-XmipPin` stages
            every moved gitlink with `git add -A` and pins it anyway.

            **That publishes a superproject commit naming a module commit origin
            has never seen.** A fresh clone cannot check the estate out at all:
            `git submodule update` asks origin for a commit that is not there.

            It happened on 2026-09-03. Nine modules had their tracked build
            output removed in one pass, eight of them had no other change, and
            the run warned about all eight and pinned all eight. The warning was
            correct and nothing acted on it, which `powershell-style.md` names
            exactly: a rule that reports and returns success is not a rule.

            Pushing rather than refusing, because the commits already exist and
            completing them is the same thing the tool does for every other
            module. It does not test them: this pushes what an operator already
            committed, and testing is the landing path's business for the
            commits it makes itself.

        .PARAMETER RepositoryRoot
            The Xmip working tree.

        .PARAMETER Module
            The module paths to push, relative to the root.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Module
    )

    foreach ($name in $Module) {
        [string] $path = Join-Path -Path $RepositoryRoot -ChildPath $name

        Write-Host "   pushing $name, committed and not on origin..." -ForegroundColor DarkGray

        if (-not $PSCmdlet.ShouldProcess($name, 'push')) {
            continue
        }

        & git -C $path push origin HEAD:main --quiet

        if ($LASTEXITCODE -ne 0) {
            throw "Pushing $name failed. The estate must not pin a commit origin does not have."
        }

        Write-Output $name
    }
}


function Submit-XmipModule {
    <#
        .SYNOPSIS
            Commits and pushes each module, in the order given.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
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

    foreach ($name in $Module) {
        $path = Join-Path -Path $RepositoryRoot -ChildPath $name

        # Before ShouldProcess, deliberately. Twice — 2026-08-29 and again the
        # next morning — a run froze between cargo's last line and 'staging',
        # and everything in that gap was silent. Xmip's own rule about arrivals
        # applies to its tooling: every gate says it is being asked. If this
        # prints and 'staging' does not, the stall is ShouldProcess or the
        # branch check, and the operator's console has the prompt the log
        # cannot show.
        Write-Host "   landing $name..." -ForegroundColor DarkGray

        if (-not $PSCmdlet.ShouldProcess($name, 'commit and push')) {
            continue
        }

        # A submodule at a bare commit has no branch to push to. Main is put
        # *here*, at the commit the superproject pinned: `checkout main` went
        # to wherever the stale local main pointed — behind origin after a
        # `git submodule update` — refused over the changed files, left HEAD
        # detached, and the push of that stale main failed (2026-09-12, twice).
        $branch = (& git -C $path branch --show-current) -join ''

        if ([string]::IsNullOrWhiteSpace($branch)) {
            Write-Host "   NOTE: detached HEAD, putting main here" -ForegroundColor Yellow
            & git -C $path checkout -B main --quiet
        }

        # Each step announced before it runs, not after.
        #
        # The first attempt at this put one line before the push and learned
        # nothing, because the run was stalling in `git add -A` — which walks
        # the entire working tree and stats every file under an ignored
        # target/. A trace after the slow step reports only the steps that
        # finished, which is the opposite of what a stall needs.
        Write-Host "   staging $name..." -ForegroundColor DarkGray
        & git -C $path add -A

        Write-Host '   committing...' -ForegroundColor DarkGray
        & git -C $path commit -m $Message --quiet

        Write-Host '   pushing to origin...' -ForegroundColor DarkGray
        & git -C $path push origin main --quiet

        if ($LASTEXITCODE -ne 0) {
            throw "Pushing $name failed. Anything before it is already on origin; " +
                'fix this and run again.'
        }

        Write-Host "   OK, landed" -ForegroundColor Green
        $name
    }
}


function Resolve-XmipCommitSubject {
    <#
        .SYNOPSIS
            The subject line for a superproject commit, from what is staged.

        .DESCRIPTION
            **The caller's message wins whenever there is one.** A land carries
            one message and it belongs on both commits it produces — the module's
            and the superproject's — so the estate's own `git log` reads what
            changed rather than "Pin 1 module".

            The owner's call, 2026-09-05: a superproject log full of "Pin 1
            module" is not correct. The earlier rule (2026-08-29) used the
            message only when the commit also changed a platform-repository file,
            on the reasoning that a pure gitlink move records no author intent.
            But the intent is the message the person typed at the land, and the
            module already committed it — the superproject should say the same
            thing, not a generic count.

            "Pin N module" remains the fallback for a pin with no message at all,
            which is how `Publish-XmipPin` is called outside a land.
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

    if ($Message) {
        return $Message
    }

    $pins = @($Staged | Where-Object { $_ -like 'module/*' })
    $noun = if ($pins.Count -eq 1) { 'module' } else { 'modules' }

    return "Pin $($pins.Count) $noun"
}
