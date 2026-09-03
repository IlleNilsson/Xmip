# Working in the Xmip estate

Xmip is a Rust, cross-platform Messaging & Integration Platform — the
replacement for BizTalk, MuleSoft and their kind. On-premises first,
cloud-installable. `docs/planning/market-position.md` opens with the position;
`docs/terminology.md` is the vocabulary and its words are chosen, not casual.

## Read before writing

The estate is governed by its own records, and they are current:

- `docs/decisions/README.md` — the ADR index. ADR-0011 names things, ADR-0012
  is the module boundary, ADR-0014 the operator surfaces, ADR-0019 identity,
  ADR-0025 module loading. Do not contradict an accepted record; propose a new
  one or an amendment, and let the owner decide.
- `docs/architecture/` — five models. `repository-model.md` explains why 43
  submodules mount where they do.
- `docs/governance/rust-style.md` and `powershell-style.md` — enforced by
  `tests/*.Tests.ps1`, not aspirational. Lines ≤ 100 columns; files ≤ 400
  production lines; a file is named for what it defines; a loop variable is
  never a parameter. **Length rules are strict recommendations: breaking one
  requires the owner's agreement FIRST, then the recorded reason.** An
  assistant follows that absolutely.
- `docs/planning/open-problems.md` — what is open and in what order. Problem
  19 and the Suggested order section are the queue.
- `docs/planning/allocation.toml` — the ledger of what moved where. Tested by
  `tests/Allocation.Tests.ps1`; keep it true when files move.

## How work lands

One command tests and lands everything, dependency order, modules first:

    Import-Module ./Xmip/Xmip.psd1 -Force
    xgit -m 'short precise message'    # alias for Publish-XmipChange

Dependencies track `branch = "main"` (ADR-0005), so a module must be pushed
before anything depending on it can be verified — the tool handles the order.
Run `Invoke-Pester -Path ./tests` before landing anything non-trivial; the
suite is ~96 tests and is the estate's memory of every past defect. pwsh 7.6.5,
PSToml and posh-git required. Rust builds with stable cargo; C# builds with the
.NET 11 preview SDK but the PowerShell binary module targets net10.0 because
pwsh hosts it (ADR-0014, amendment 2026-08-30).

## Hard-learned rules

- Ask the owner before breaking any recommendation, deleting non-trivial
  content, or deciding anything two records disagree on. He answers fast and
  dislikes discovering decisions after the fact far more than being asked.
- Read a file before editing it; check a signature before calling it. Most of
  this repository's test suite exists because someone (usually an assistant)
  skipped that.
- Say outcomes in words — OK, FAILED, REFUSED — never colour alone.
- Commit messages are short and precise; reasoning belongs in a decision
  record or the file itself.
- Full paths when naming files to the owner.
- The estate ends every session square: everything committed, everything
  pushed, `git status` clean in all 43 submodules and the superproject.
  `Get-XmipStatus` shows the whole estate at once.

## The assistant's working area

`.ai-interaction/` at the repository root, git-ignored. Every log, run script
and scratch file an assistant produces goes there and nowhere else — logs as
`.ai-interaction/land.log`, runnable sequences as `.ai-interaction/*.ps1`. The
assistant's reach is this repository; nothing above `D:\Repos\Xmip` is its
business.

`.ai-work/` is not yours either: `Sync-XmipEstate -Report` writes it. The
assistant argued the two folders had different authors and deserved different
prefixes; the owner heard the argument and ruled otherwise on 2026-08-31 —
machine-generated working output is `.ai-*`, whichever machinery wrote it.
The folders stay separate; the prefix does not. Write to `.ai-interaction/`,
never to `.ai-work/`.

`.local-work/` is the third of the untracked family and also not yours:
device-local state for building or running Xmip on this machine — a target
choice, a local node configuration. Nothing writes it yet; it is reserved so
the first thing that does has a home. The three together: `.ai-interaction/`
is who, `.ai-work/` is what machinery, `.local-work/` is where.
