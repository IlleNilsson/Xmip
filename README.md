# Xmip

A cross-platform messaging and integration platform, built around immutable
Streams, immutable Messages, long-running Journeys, modular capabilities and
implied Contracts.

This repository is the root of the estate: the manifest that names every Xmip
repository, the architecture record, and the PowerShell module that reconciles
both against reality.

---

## Requirements

Xmip tracks current platforms and does not carry compatibility with superseded
ones — [ADR-0021](doc/decision/ADR-0021-current-platforms-only.md).

| | Required | Notes |
| --- | --- | --- |
| PowerShell | **7.6.5+, Core edition** | Windows PowerShell 5.1 will not work, and is not meant to |
| git | 2.40+ | |
| Rust | latest stable | pinned by channel in `rust-toolchain.toml`, not by version |
| Pester | 6+ | developers only, for `test/` |
| .NET | 11 | optional, for the Blazor surfaces |

PowerShell is the one prerequisite Xmip cannot install for you, because the
tooling is written in it. Everything else `Install-XmipPrerequisite` reports
and can install.

---

## Set up

### 1. Get PowerShell 7.6.5 or later

```powershell
winget install Microsoft.PowerShell        # Windows
brew install powershell                    # macOS
```

Check with `$PSVersionTable.PSVersion`. Anything below 7.6.5, or an edition other
than `Core`, and nothing below will run.

### 2. Clone and load the module

```powershell
git clone https://github.com/IlleNilsson/Xmip.git
cd Xmip

Import-Module .\Xmip
```

### 3. Make it available everywhere

```powershell
Install-XmipModule
```

This links `Xmip` into your per-user module directory — a junction on
Windows, so no elevation and no Developer Mode. It is a link, not a copy, so
edits in the repository are live in the next session.

From then on, in any console and any directory:

```powershell
Import-Module Xmip
```

### 4. Install what the machine is missing

```powershell
Install-XmipPrerequisite -Role operator            # report what is missing
Install-XmipPrerequisite -Role developer -Install  # install it
```

Reporting is the default; `-Install` acts and `-WhatIf` shows what it would do.
It never elevates: where a prerequisite needs administrative rights it prints
the command and stops, because a setup script that silently runs elevated
installers is the thing an estate blocks.

Roles are cumulative and declared in
[`prerequisite.toml`](prerequisite.toml):

| Role | For | Adds |
| --- | --- | --- |
| `operator` | running Xmip | PowerShell, git, PSToml |
| `developer` | building it | Rust, a linker, Pester, optionally .NET |
| `build` | producing releases | everything above |

A prerequisite below its declared floor is reported as `outdated` and the
command **fails** rather than warning, so CI notices.

### 5. Check it works

```powershell
Get-Command -Module Xmip
Get-XmipManifest -Path .\architecture.toml | Select-Object -ExpandProperty repositories | Measure-Object
```

Developers, additionally:

```powershell
cargo fmt --check
cargo clippy --workspace --all-targets -- -D warnings
Invoke-Pester .\tests -Output Detailed
```

---

## Commands

Every command supports `-WhatIf`. An operation switch means do it; `-WhatIf`
means do not. There is no plan mode and no `-Apply`: reporting is the default
and needs no ceremony to reach.

| Command | Does |
| --- | --- |
| `Install-XmipModule` | Links this module onto `PSModulePath`. Run once. |
| `Install-XmipPrerequisite` | Reports and installs what a machine needs. |
| `Sync-XmipEstate` | Reconciles the estate with `architecture.toml` — creates and configures on GitHub, composes the submodule hierarchy locally. |
| `Sync-XmipRepository` | Local working copies: clone, pull, status, branch, push, distribute. |
| `Get-XmipManifest` | Reads `architecture.toml` and flattens the estate. |
| `Test-XmipManifest` | Validates naming, crates, maturity and dependencies. |
| `Get-XmipRepositoryRoot` | Finds the repository by walking up to `architecture.toml`. |
| `Get-XmipDecisionRecord` | Reads `doc/decision/` and returns what each record declares about itself. |
| `New-XmipDecisionIndex` | Generates `doc/decision/README.md` from the records. `-Save` writes it. |

### Reconcile the estate

```powershell
Sync-XmipEstate                       # report drift, change nothing
Sync-XmipEstate -Create -WhatIf       # what would be created
Sync-XmipEstate -Create               # create the missing repositories
Sync-XmipEstate -Configure            # description, topics, features
Sync-XmipEstate -Compose              # wire the submodule hierarchy locally
Sync-XmipEstate -Report               # write .ai-work/architecture-report.json
```

`-Compose` mounts every repository that exists at its place in the tree —
`module/<domain>/<leaf>` for a module, `module/<leaf>` inside its parent for
an implementation. The filesystem hierarchy and the submodules are the same
thing, so `git clone --recursive` reproduces it. It never uses
`git submodule update --remote`; parents pin commits deliberately, per
ADR-0016.

A reserved repository that does not exist is not reported as drift. That is the
design, not a gap.

`-Create` skips repositories whose `maturity` is `reserved` unless you pass
`-IncludeReserved`. **Nothing ever deletes a repository.**

`-Create` and `-Configure` need a GitHub token, from `-GitHubToken` or
`$env:GITHUB_TOKEN`. A classic token with `repo` scope: fine-grained tokens
cannot create user-account repositories.

### Work with the repositories

```powershell
Sync-XmipRepository -Clone -ModulesOnly    # every module, beside this repository
Sync-XmipRepository -Status                # what is dirty, ahead, behind
Sync-XmipRepository -Pull
Sync-XmipRepository -Branch -Create feature/thing
Sync-XmipRepository -Push feature/thing
Sync-XmipRepository -Distribute -WhatIf    # execute doc/planning/allocation.toml
```

Clones land *beside* this repository, in `../xmip-repositories`, not inside it.

---

## Where things are

```text
architecture.toml     the estate: every repository, named by its position in the tree
prerequisite.toml     what a machine needs, per role and per operating system
rust-toolchain.toml   channel = stable

Xmip/                 the PowerShell module
module/              the Rust modules, mounted as git submodules
src/                  this repository's own Rust facade
test/                Pester
deploy/               Ansible and DSC node configuration
doc/                 see below
```

### Documentation

One document per subject, and no versions in filenames —
[ADR-0020](doc/decision/ADR-0020-documentation-structure.md).

| Document | Answers |
| --- | --- |
| [`doc/terminology.md`](doc/terminology.md) | what every Xmip word means |
| [`architecture/runtime-model.md`](doc/architecture/runtime-model.md) | what Xmip does at runtime |
| [`architecture/repository-model.md`](doc/architecture/repository-model.md) | why the estate is shaped this way |
| [`architecture/module-model.md`](doc/architecture/module-model.md) | the module boundary, loading and isolation |
| [`architecture/deployment-model.md`](doc/architecture/deployment-model.md) | nodes, profiles, roles, installation, recovery |
| [`architecture/observability-model.md`](doc/architecture/observability-model.md) | audit, logs, traces, retention, observation |
| [`doc/decision/`](doc/decision) | **every decision, read as one document** — by subject, not by number |

Two documents now live with the repository that owns them, reachable through the
submodules:

| Document | Where |
| --- | --- |
| identity, per protocol, against the standards | `module/capability/authenticate/doc/` |
| the normative ABI specification | `module/foundation/abi/doc/` |

Governance:

| Document | Answers |
| --- | --- |
| [`governance/powershell-style.md`](doc/governance/powershell-style.md) | how the PowerShell here is written |
| [`governance/rust-style.md`](doc/governance/rust-style.md) | where the Rust here lives, and why length is not the measure |
| [`governance/release-model.md`](doc/governance/release-model.md) | Continuum, Linear, and how work reaches them |

Development:

| Document | Answers |
| --- | --- |
| [`development/creating-transports-contracts-and-processes.md`](doc/development/creating-transports-contracts-and-processes.md) | how a developer adds a transport, a contract or a process |

`doc/planning/` is working notes and is explicitly **not** authoritative.

---

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) and
[GOVERNANCE.md](GOVERNANCE.md). Established architectural decisions need
explicit permission before they change —
[architectural-change-permission.md](doc/governance/architectural-change-permission.md).

Until the first Linear release, work commits directly to `main`. After it,
development branch and pull request. The reasoning, and the trigger, are in
[release-model.md](doc/governance/release-model.md).

Licensed [AGPL-3.0-or-later](LICENSE).
