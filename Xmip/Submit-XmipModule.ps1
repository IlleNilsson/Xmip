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

        # Throws on failure: the estate must not pin a commit origin does not have.
        Invoke-XmipGit -At $path -Arguments @('push', 'origin', 'HEAD:main', '--quiet') | Out-Null

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
        [string] $branch = @(Invoke-XmipGit -At $path -Arguments @('branch', '--show-current'))[0]

        if ([string]::IsNullOrWhiteSpace($branch)) {
            Write-Host "   NOTE: detached HEAD, putting main here" -ForegroundColor Yellow
            Invoke-XmipGit -At $path -Arguments @('checkout', '-B', 'main', '--quiet') | Out-Null
        }

        Write-Host "   staging $name..." -ForegroundColor DarkGray
        [string[]] $staged = @(Submit-XmipRepositoryChange -At $path -Message $Message)

        # A host whose own files are clean is dirty only through its nested
        # modules, which land on their own after it, and it is pinned to them
        # at the end. Until 2026-09-22 this committed anyway: git refused,
        # printed its status, and that status went down the pipeline as the
        # names of modules landed, while the refusal itself was never read.
        if ($staged.Count -eq 0) {
            [string] $note = '   nothing of its own to commit; its nested modules land next'
            Write-Host $note -ForegroundColor DarkGray
            continue
        }

        Write-Host "   OK, landed" -ForegroundColor Green
        $name
    }
}


function Submit-XmipRepositoryChange {
    <#
        .SYNOPSIS
            Stages everything in one repository, commits it and pushes main;
            returns what was staged, and does nothing more when that is
            nothing.

        .DESCRIPTION
            The estate's one commit-and-push: a module when it lands, a
            parent when it pins its nested modules, and the superproject when
            it pins the modules. What is staged, not what is dirty: `git
            status` reports a submodule as modified when the only change is an
            untracked file inside it, which the parent cannot stage.

            The subject is the caller's message, or "Pin N module(s)" when
            there is none (Resolve-XmipCommitSubject). Each step throws on
            its own, the commit as much as the push: until 2026-09-23 only
            the push was checked, and a failed commit followed by a push with
            nothing new reported the parent pinned. A failed push leaves
            everything before it on origin, so fixing it and running again is
            safe.

            Each step is announced before it runs, not after: the first trace
            of a stalled landing put one line before the push and learned
            nothing, because the stall was in `git add -A`, which walks the
            whole working tree and stats every file under an ignored target/.

        .PARAMETER At
            The repository's working tree.

        .PARAMETER Message
            The commit's subject; empty for a pin outside a landing.

        .PARAMETER Saying
            Said once something is staged, before the commit: what this
            commit is, for the operator.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $At,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Message = '',

        [Parameter(Mandatory = $false)]
        [string] $Saying = ''
    )

    Invoke-XmipGit -At $At -Arguments @('add', '-A') | Out-Null
    [string[]] $asked = @('diff', '--cached', '--name-only')
    [string[]] $staged = @(Invoke-XmipGit -At $At -Arguments $asked)

    if ($staged.Count -eq 0) {
        return
    }

    [string] $subject = Resolve-XmipCommitSubject -Staged $staged -Message $Message

    if ($Saying -ne '') {
        Write-Host $Saying -ForegroundColor DarkGray
    }

    Write-Host '   committing...' -ForegroundColor DarkGray
    Invoke-XmipGit -At $At -Arguments @('commit', '-m', $subject, '--quiet') | Out-Null

    Write-Host '   pushing to origin...' -ForegroundColor DarkGray
    Invoke-XmipGit -At $At -Arguments @('push', 'origin', 'main', '--quiet') | Out-Null

    return $staged
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
