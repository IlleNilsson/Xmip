# Contributing to Xmip

Xmip is a Rust, cross-platform Messaging & Integration Platform — the
replacement for BizTalk, MuleSoft and their kind. On-premises first,
cloud-installable. `doc/planning/market-position.md` opens with the position;
`doc/terminology.md` is the vocabulary and its words are chosen, not casual.

This document is how work is done in the estate, and it holds for whoever is
doing it: a contributor sending a pull request, the owner, or a model asked
to help. The rules are not named for any one of them and not for any one
tool. Where a person and a machine genuinely differ, the rule says so rather
than pretending they are the same.

Xmip follows an architecture-first engineering workflow:

```text
Requirements -> Architecture -> Implementation -> Verification
  -> Commit -> Pull request -> Review -> Merge
```

## Read before writing

The estate is governed by its own records, and they are current:

- `doc/decision/README.md` — the ADR index. ADR-0011 names things, ADR-0012
  is the module boundary, ADR-0014 the operator surfaces, ADR-0019 identity,
  ADR-0025 module loading. Do not contradict an accepted record; propose a
  new one or an amendment, and let the owner decide.
- `doc/architecture/` — five models. `repository-model.md` explains why the
  submodules mount where they do.
- `doc/governance/rust-style.md` and `powershell-style.md` — enforced by
  `test/*.Test.ps1`, not aspirational. Lines ≤ 100 columns; files ≤ 400
  production lines; a file is named for what it defines; a loop variable is
  never a parameter. **Length rules are strict recommendations: breaking one
  requires the owner's agreement FIRST, then the recorded reason.** Nobody is
  exempt, and whatever can reformat a file in a second is exempt least of all.
- `doc/planning/open-problems.md` — what is open and in what order. Problem
  19 and the Suggested order section are the queue.
- `doc/planning/allocation.toml` — the ledger of what moved where. Tested by
  `test/Allocation.Test.ps1`; keep it true when files move.

Repository placement is governed by [`architecture.toml`](architecture.toml).
New repositories, dependencies and technology implementations must fit the
classification and dependency rules in that manifest.

## Be the colleague who remembers

Before engaging with any idea the owner raises, check whether the estate has
already answered it: the concept index in `doc/decision/README.md`, then
`doc/planning/open-problems.md`. If a record answers it, SAY SO FIRST —
"ADR-0024 settled this; the claim lives at the endpoint" — before any other
work.

The owner is human and designs better than he archives. Whoever works with
him arrives without that memory and can read the record far faster than he
can recall it: a new contributor has never read it, and a model starts every
session from nothing. That asymmetry is the value of the pairing, and it only
pays if the other side does the remembering from the record, including
correcting the owner. Gladly keeping along with a solved problem is the
specific failure this rule exists to prevent — it happened with exclusiveness,
and it cost real work.

## Hard-learned rules

- **A change is not done until everything related to it is changed.** The
  records, `README.md`, this document, cmdlet help, the governance documents,
  the tests and all four operator surfaces. The owner, 2026-09-20: *when you
  change things, you have to change all related — I can see for example, that
  the main README.md is not updated*, and six exported cmdlets were indeed
  missing from it while the module loader that had landed the day before
  appeared nowhere. A document that is read as true and is not is worse than
  one that is absent. Where the relationship can be checked, **write the test
  rather than trusting the next reader to remember** — that is what the rest
  of these rules are, and why they hold.
- Ask the owner before breaking any recommendation, deleting non-trivial
  content, or deciding anything two records disagree on. He answers fast and
  dislikes discovering decisions after the fact far more than being asked.
- Read a file before editing it; check a signature before calling it. Most of
  this repository's test suite exists because someone skipped that — often a
  model, which is why the estate trusts the tests and not the intention.
- Say outcomes in words — OK, FAILED, REFUSED — never color alone.
- Full paths when naming files to the owner.
- The estate ends every session square: everything committed, everything
  pushed, `git status` clean in every submodule and the superproject.
  `Get-XmipStatus` shows the whole estate at once.

## Before implementation

A contribution must first identify:

- the requirement being addressed;
- the owning Xmip capability or repository;
- affected contracts and dependencies;
- compatibility and migration implications;
- the verification approach.

## Change scope

Keep pull requests focused. Architecture changes and implementation changes
should not be mixed unless the implementation directly proves the
architecture change.

Changes to the architecture baseline must update all authoritative
representations that are affected — the architecture models in
`doc/architecture/`, the decision records and the manifest — together, in one
change. That is the first hard-learned rule narrowed to the baseline, and it
has a document of its own:
`doc/governance/architectural-change-permission.md`.

## How work lands

One command tests and lands everything, dependency order, modules first:

```powershell
Import-Module ./Xmip/Xmip.psd1 -Force
xgit -m 'short precise message'    # alias for Publish-XmipChange
```

Dependencies track `branch = "main"` (ADR-0005), so a module must be pushed
before anything depending on it can be verified — the tool handles the order.
Run `Start-XmipTest -Suite Core.Estate` before landing anything non-trivial; the
suite is around two hundred tests and is the estate's memory of every past
defect.

**The toolchain.** PowerShell Core 7.6.5 or newer, with PSToml and posh-git.
Rust builds with stable cargo; C# builds with the .NET 11 preview SDK, but
the PowerShell binary module targets net10.0 because pwsh hosts it (ADR-0014,
amendment 2026-08-30).

**Writing PowerShell.** Every script must remain cross-platform. Use advanced
functions and native PowerShell parameter sets, and support `ShouldProcess`
on a mutating command where that is practical.

## Submodules

Xmip mounts every module as a submodule: what starts a node at
`module/foundation/<leaf>` and `module/platform/<leaf>`, everything else at
`module/<provider>/<domain>/<leaf>` (ADR-0016). Four
facts explain every surprise:

- **A submodule is a commit, not a branch.** `Xmip` records "at this path, this
  commit". Nothing tracks a branch.
- **They clone detached.** No branch is checked out, so a commit made without
  checking one out is reachable from nothing.
- **Pushing the parent does not push the children.** `push.recurseSubmodules
  check` refuses a parent push whose gitlink names an unpushed commit.
- **`git checkout -- .` restores from the index, not from HEAD.** Use
  `git checkout HEAD -- .` to discard staged changes too.

**Getting a working estate**

```powershell
git clone --recursive https://github.com/IlleNilsson/Xmip.git
git submodule update --init --recursive   # after any pull
git config push.recurseSubmodules check   # once, per clone
```

**Seeing what is going on**

```powershell
git submodule status                              # commit, path, branch
git submodule foreach --quiet 'git status --short' # what is dirty, where
```

A leading `+` in `git submodule status` means the working copy is not on the
commit the parent pins.

**Changing something in a module**

```powershell
cd module/foundation/core
git checkout main          # detached otherwise, and the commit goes nowhere
git add -A; git commit -m "..."; git push origin main

cd ../../..
git add -A; git commit -m "Pin core: ..."; git push origin main
```

Two commits in two repositories, child first. Always. `xgit` does this for
the whole estate in one step, and is what a session should normally use.

**Estate commands**

```powershell
Sync-XmipEstate -Compose   # mount, move and skip deprecated
Sync-XmipEstate -Cargo     # dependency revs from the submodule pins
```

## Commit messages

**Short and precise.** A subject line that says what changed, and a body only
when the reason is not obvious from the diff.

The reasoning belongs in the decision record, not the commit. An ADR is read on
purpose; a commit message is read while looking for something else.

Nobody gets credit for length.

## Pull requests

A pull request should state:

- requirement;
- architecture impact;
- implementation summary;
- changed files;
- verification performed;
- known limitations or unverified runtime behavior.

A branch or commit is not considered completed work until a pull request
exists. A pull request is not project history until it is merged.

## The working area

`.ai-interaction/` at the repository root, git-ignored. Every log, run script
and scratch file a working session produces goes there and nowhere else —
logs as `.ai-interaction/land.log`, runnable sequences as
`.ai-interaction/*.ps1`. A session's reach is this repository; nothing above
the clone is its business.

`.ai-work/` carries the same prefix and is a different folder:
`Sync-XmipEstate -Report` writes it, and nothing else should. The argument was
made that the two have different authors and so deserve different prefixes;
the owner heard it and ruled otherwise on 2026-08-31 — machine-generated
working output is `.ai-*`, whichever machinery wrote it. The folders stay
separate; the prefix does not. Write to `.ai-interaction/`, never to
`.ai-work/`.

`.local-work/` is the third of the untracked family: device-local state for
building or running Xmip on this machine — a target choice, a local node
configuration. Nothing writes it yet; it is reserved so the first thing that
does has a home. It is not a scratch folder either; scratch is
`.ai-interaction/`. The three together: `.ai-interaction/` is who, `.ai-work/`
is what machinery, `.local-work/` is where.

## License

Xmip is licensed under the GNU Affero General Public License, version 3 or
later.

That license grants the right to use, study, modify, redistribute and fork
Xmip. This project does not restrict those rights and does not seek to.

What the license asks in return is that modifications to Xmip itself remain
available under the same terms, including when a modified version is offered
to users over a network.

## Extending Xmip

Extensions do not require permission.

Any organization may implement Xmip traits and interfaces and publish modules
under whatever license it chooses. Those modules are the publisher's work, the
publisher's support and the publisher's responsibility. Xmip neither endorses
nor maintains them.

The boundary is the trait, not the license.

## Contributions

Contributions to Xmip itself are reviewed and accepted through the official
repositories, following the workflow above.

By contributing, you agree that accepted changes may be maintained, revised or
replaced as the Xmip architecture develops.

## The name

A fork is free to exist. The name Xmip identifies this project, and a fork is
asked not to present itself as Xmip.
