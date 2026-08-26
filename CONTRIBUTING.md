# Contributing to Xmip

Xmip follows an architecture-first engineering workflow:

```text
Requirements -> Architecture -> Implementation -> Verification -> Commit -> Pull request -> Review -> Merge
```

## Before implementation

A contribution must first identify:

- the requirement being addressed;
- the owning Xmip capability or repository;
- affected contracts and dependencies;
- compatibility and migration implications;
- the verification approach.

Repository placement is governed by [`architecture.toml`](architecture.toml). New repositories, dependencies and technology implementations must fit the classification and dependency rules in that manifest.

## Change scope

Keep pull requests focused. Architecture changes and implementation changes should not be mixed unless the implementation directly proves the architecture change.

Changes to the architecture baseline must update all authoritative representations that are affected, including the architecture specification and manifest.

## PowerShell tooling

Xmip PowerShell scripts require PowerShell Core 7.6.3 or newer and must remain cross-platform.

Use advanced functions and native PowerShell parameter sets. Mutating commands should support `ShouldProcess` where practical.

## Submodules

Xmip mounts every module as a submodule under `modules/<domain>/<leaf>`. Four
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
cd modules/foundation/core
git checkout main          # detached otherwise, and the commit goes nowhere
git add -A; git commit -m "..."; git push origin main

cd ../../..
git add -A; git commit -m "Pin core: ..."; git push origin main
```

Two commits in two repositories, child first. Always.

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
- known limitations or unverified runtime behaviour.

A branch or commit is not considered completed work until a pull request exists. A pull request is not project history until it is merged.

## Licence

Xmip is licensed under the GNU Affero General Public License, version 3 or later.

That licence grants the right to use, study, modify, redistribute and fork Xmip. This project does not restrict those rights and does not seek to.

What the licence asks in return is that modifications to Xmip itself remain available under the same terms, including when a modified version is offered to users over a network.

## Extending Xmip

Extensions do not require permission.

Any organisation may implement Xmip traits and interfaces and publish modules under whatever licence it chooses. Those modules are the publisher’s work, the publisher’s support and the publisher’s responsibility. Xmip neither endorses nor maintains them.

The boundary is the trait, not the licence.

## Contributions

Contributions to Xmip itself are reviewed and accepted through the official repositories, following the workflow above.

By contributing, you agree that accepted changes may be maintained, revised or replaced as the Xmip architecture develops.

## The name

A fork is free to exist. The name Xmip identifies this project, and a fork is asked not to present itself as Xmip.
