# Xmip

A messaging and integration platform. On-premises first, cloud-installable.
Written in Rust, built around immutable Streams, immutable Messages,
long-running Journeys, modular capabilities and Contracts. Licensed
AGPL-3.0-or-later.

Xmip runs on Windows, Linux and macOS: a single server, an on-premises
cluster, a cloud node or a small device. It operates without internet access.

This repository is the root of the estate: the manifest that names every Xmip
repository, the architecture and decision records, and the PowerShell module
that maintains them. The module repositories are mounted under `module/` as
git submodules.

| Reader | Section |
| --- | --- |
| New to Xmip | [Beginners](#beginners) |
| Running Xmip | [Operators](#operators) |
| Building Xmip or a module for it | [Developers](#developers) |
| Evaluating Xmip for an organization | [Chief Information Officers](#chief-information-officers) |
| Responsible for the engineering | [Chief Engineering Officers](#chief-engineering-officers) |

---

## Beginners

Xmip receives data, processes it and sends it on. The vocabulary is defined in
[`doc/terminology.md`](doc/terminology.md). Five terms are enough to begin.

- **Stream.** What arrives: bytes from a file, a socket, a queue, a mailbox,
  the rows a SQL statement returns, a device on a bus. A Stream belongs to the
  sender until Xmip accepts it.
- **Message.** What Xmip accepts a Stream as: immutable content with a shape.
  A **Contract** decides acceptance. Content must be well-formed, and where a
  Contract is named it must conform; otherwise the Stream is refused and the
  sender is told where and why. An accepted Message is written to disk before
  anything acts on it and is never lost.
- **Journey.** The path a Message takes through Xmip. A Journey checkpoints
  and survives a restart.
- **Receive, Process, Send.** The three stages of that path. The monitor is
  organized around them.
- **Status.** Every scope has one: Fine, Working, Stressed, Holding or Done. A
  Status names what an operator can do about it, and the worst Status beneath
  a scope says where to look.

Nothing in Xmip starts on its own. You start a node, a test or a monitor, and
you stop it.

### First run

1. Install PowerShell 7.6.5 or later. Windows PowerShell 5.1 is a different
   product and is not supported.

   ```sh
   winget install Microsoft.PowerShell          # Windows
   sudo snap install powershell --classic       # Linux, any distribution with snap
   sudo apt-get install -y powershell           # Debian, Ubuntu; Microsoft package repository required
   sudo dnf install -y powershell               # Fedora, RHEL; Microsoft package repository required
   brew install powershell                      # macOS
   ```

   Every command below runs inside `pwsh` and is identical on all three
   platforms.

2. Clone the estate and load the module.

   ```powershell
   git clone --recursive https://github.com/IlleNilsson/Xmip.git
   cd Xmip
   Import-Module -Name ./Xmip
   Install-XmipModule
   Install-XmipPrerequisite -Role developer -Install
   ```

   `Install-XmipModule` links the module into your user module path. In any
   later shell, `Import-Module -Name Xmip` is sufficient.

3. Run the Playground, Xmip's own integration test. It needs no network and no
   other software.

   ```powershell
   Start-XmipTest -Suite Playground -Test RoundTrip -Nodes alpha, beta -OnlineNodes alpha
   Start-XmipWeb -Snapshot .local-work/playground/playground-snapshot.toml
   Get-XmipTestStatus
   Get-XmipTestResult | Where-Object -Property State -NE -Value fine
   Stop-XmipTest
   Stop-XmipWeb
   ```

   The monitor at http://127.0.0.1:5087 shows the three stages, the cluster
   Status and every node. `alpha` and `beta` are two simulated node processes;
   `alpha` may use the internet, `beta` may not.

Every command that changes state accepts `-WhatIf`. `Get-Help Start-XmipTest
-Full` documents every parameter.

---

## Operators

### Platforms

Xmip supports current platforms only
([ADR-0021](doc/decision/ADR-0021-current-platforms-only.md)). Linux, Windows
and macOS are equal: the runtime, the `xmip` command line, the PowerShell
module and the web monitor run on all three.

| | Windows | Linux | macOS |
| --- | --- | --- | --- |
| PowerShell 7.6.5 or later, Core edition | `winget` | `snap`, `apt`, `dnf`, `zypper`, `pacman` | `brew` |
| Prerequisites | `Install-XmipPrerequisite` reads [`prerequisite.toml`](prerequisite.toml), one package per operating system and package manager | | |
| Local layout | `install/install-local.ps1` under `%ProgramData%\Xmip` | `install/install-local.sh` under `/opt/xmip` | `install/install-local.sh` |
| Desired state | `deploy/dsc/xmip-node.dsc.yaml` | `deploy/ansible/roles` | `deploy/ansible/roles` |
| Remote operation | PowerShell Remoting over WinRM or SSH | SSH | SSH |

`Install-XmipPrerequisite -Role operator` reports what a machine lacks;
`-Install` installs it. The command never elevates: where a package requires
administrative rights it prints the command and stops. A prerequisite below
its floor fails the command.

### Surfaces

Four surfaces read one operator boundary
([ADR-0014](doc/decision/ADR-0014-operator-surfaces.md),
[ADR-0027](doc/decision/ADR-0027-the-operator-boundary.md)), so they cannot
disagree.

| Surface | Purpose |
| --- | --- |
| `xmip` | Command line. `xmip health <scope>`; `--json` for one document; `--follow` for a stream of changes over SSH or a pipe. |
| PowerShell module | The same answers as objects on the pipeline. |
| Web monitor | Read-only. Serves many operators. |
| Desktop | Monitors and configures. Windows, Linux and macOS. |

Observation reads snapshots the runtime publishes and never enters the message
path. Audit is the durable record.

### Configuration

Configuration is TOML on disk; JSON is used only on the wire
([ADR-0031](doc/decision/ADR-0031-configuration-is-toml-json-is-transport.md)).
`xmip validate <file>` checks a node configuration without starting anything.

A node is offline unless its configuration says `online = true`
([ADR-0045](doc/decision/ADR-0045-offline-is-the-default.md)). An online node
may reach the internet for duties that require it, such as certificate
provisioning at a public edge.

A security profile, `standard`, `enterprise` or `regulated`, sets identity
isolation and whether the runtime fails closed
([deployment-model.md](doc/architecture/deployment-model.md), section 4).

### Rehearsal

The Playground runs Xmip's scenarios continuously, at a chosen stress level,
with as many simulated node processes as you name.

```powershell
Start-XmipTest -Suite Playground -Test HeavyLoad, LowLatency -Stress Harsh -Nodes n1, n2, n3
Get-XmipTestStatus
Get-XmipTestResult -Test HeavyLoad -Worst
Stop-XmipTest
```

---

## Developers

### Setup

Complete the beginners' steps, then:

```powershell
git submodule update --init --recursive
git config push.recurseSubmodules check
```

A submodule is a commit, not a branch. [CONTRIBUTING.md](CONTRIBUTING.md)
explains the consequences.

### Build, test, land

The runtime and modules are Rust on the stable channel. The operator surfaces
are .NET 11; the PowerShell module targets `net10.0` because `pwsh` hosts it.

```powershell
Start-XmipTest -Suite Estate                          # the estate's Pester suite
Start-XmipTest -Suite Estate -Test Rust.Style         # one file
Publish-XmipChange -Message 'short precise message'   # test, commit, push, pin; alias xgit
```

`Publish-XmipChange` tests and lands a change across every repository it
touched, in dependency order, modules first. `cargo fmt`, `cargo clippy
--workspace --all-targets -- -D warnings` and the suite must pass. Until the
first Linear release, work commits directly to `main`
([release-model.md](doc/governance/release-model.md)).

### Layout

```text
architecture.toml     the estate: every repository, named by its position in the tree
prerequisite.toml     what a machine needs, per role and operating system
rust-toolchain.toml   channel = stable
Xmip/                 the estate's PowerShell module
module/               the modules, submodules at module/<domain>/<leaf>
test/                 the estate's Pester suite; test/playground is the Playground
deploy/               Ansible roles and a DSC configuration for a node
install/              local layout scripts
template/             the Rust and .NET repository templates
doc/                  the record
```

### The record

The estate is governed by its own documents. Do not contradict an accepted
record; propose a new one or an amendment.

| Document | Content |
| --- | --- |
| [`doc/terminology.md`](doc/terminology.md) | the vocabulary |
| [`architecture/runtime-model.md`](doc/architecture/runtime-model.md) | what Xmip does at runtime |
| [`architecture/repository-model.md`](doc/architecture/repository-model.md) | why the estate is shaped as it is |
| [`architecture/module-model.md`](doc/architecture/module-model.md) | the module boundary, loading and isolation |
| [`architecture/deployment-model.md`](doc/architecture/deployment-model.md) | nodes, profiles, roles, installation, recovery |
| [`architecture/observability-model.md`](doc/architecture/observability-model.md) | audit, logs, traces, retention, observation |
| [`doc/decision/`](doc/decision) | the decision records, indexed by subject |
| [`governance/rust-style.md`](doc/governance/rust-style.md), [`governance/powershell-style.md`](doc/governance/powershell-style.md) | style rules, enforced by the suite |
| [`development/creating-transports-contracts-and-processes.md`](doc/development/creating-transports-contracts-and-processes.md) | adding a transport, a contract or a process |
| [`doc/planning/open-problems.md`](doc/planning/open-problems.md) | open questions, in order |

Two documents live with the repository that owns them: identity per protocol
in `module/capability/authenticate/doc/`, the ABI specification in
`module/foundation/abi/doc/`. `doc/planning/` is working notes and not
authoritative.

### The estate module

Every command accepts `-WhatIf`. Reporting is the default.

| Command | Purpose |
| --- | --- |
| `Install-XmipModule` | Link the module onto `PSModulePath`. |
| `Install-XmipPrerequisite` | Report and install what a machine needs, per role. |
| `Sync-XmipEstate` | Reconcile the estate with `architecture.toml`: create and configure on GitHub, compose the submodule tree. |
| `Sync-XmipRepository` | Local working copies: clone, pull, status, branch, push, distribute. |
| `Get-XmipManifest`, `Test-XmipManifest` | Read and validate `architecture.toml`. |
| `Get-XmipStatus` | The whole estate at once: dirty, ahead, behind. |
| `Publish-XmipChange` | Test and land a change, dependency order, modules first. |
| `Start-XmipTest`, `Get-XmipTestStatus`, `Stop-XmipTest` | A suite of Xmip's tests: the Playground or the estate's Pester suite. |
| `Start-XmipTestNode`, `Get-XmipTestNode`, `Stop-XmipTestNode` | Simulated node processes, by name. |
| `Get-XmipTestResult`, `Get-XmipHistory` | What a run reports, now and over time. |
| `Start-XmipWeb`, `Get-XmipWeb`, `Stop-XmipWeb` | The web monitor. |
| `Get-XmipDecisionRecord`, `New-XmipDecisionIndex` | The decision record and its index. |

```powershell
Sync-XmipEstate                                       # report drift
Sync-XmipEstate -Create -WhatIf                       # what would be created on GitHub
Sync-XmipEstate -Compose                              # wire the submodule tree locally
Sync-XmipRepository -Status                           # dirty, ahead, behind
Get-XmipStatus
```

`-Create` and `-Configure` require a GitHub token with `repo` scope, from
`-GitHubToken` or `$env:GITHUB_TOKEN`. Nothing deletes a repository.

### Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) and [GOVERNANCE.md](GOVERNANCE.md).
Established architectural decisions require explicit permission before they
change
([architectural-change-permission.md](doc/governance/architectural-change-permission.md)).
A module is a crate against a C ABI
([ADR-0012](doc/decision/ADR-0012-module-boundary.md)) and may be written in
any language that can implement one.

---

## Chief Information Officers

**What Xmip is.** One platform that moves data between the systems your
organization runs and the partners it deals with: files, queues, sockets,
databases, cloud services, industrial, healthcare and e-invoicing protocols.
It runs on your own machines, a single server, an on-premises cluster, a node
in a cloud of your choice or a device at the edge, on Windows, Linux or macOS,
with the same behavior on each.

**What remains under your control.** Your data stays on your infrastructure.
Xmip installs and operates without internet access; a node reaches out only
where its configuration permits, and the software reports nothing to anyone.
Every accepted message is written to disk before it is processed, and no
accepted message is lost. Every action is recorded in an audit that is
separate from live monitoring.

**Licensing.** Xmip is AGPL-3.0-or-later. There is no commercial license, no
dual license and no contributor agreement that could enable one
([ADR-0023](doc/decision/ADR-0023-licensing-model.md)). The platform cannot be
relicensed or withdrawn. Modules written against the C ABI are your own work
under your own terms. Organizations whose policy excludes AGPL will find that
policy engaged; the record acknowledges this.

**Assurance.** Three security profiles, `standard`, `enterprise` and
`regulated`, determine identity isolation and whether the runtime stops rather
than operate unobserved. Identity is verified per protocol against the
published standards. Certificates are the first mechanism built; they are
provisioned by Let's Encrypt at a public edge and by your own authority
elsewhere. Xmip is developed in Sweden and is source-available, which is
relevant where data sovereignty is regulated. It implements the AS4 and Peppol
protocols that European e-invoicing mandates require from 2026.

**Maturity.** Xmip has no stable release. `main` is the Continuum, the
evolving state of the project. A Linear release is a stabilized, reproducible,
versioned line cut from it; the first has not been cut
([release-model.md](doc/governance/release-model.md)). The manifest declares
the maturity of every repository. Three hundred and forty-three repositories
are declared, most of them protocol, contract and archive technologies;
forty-four are built and mounted. The runtime, the operator surfaces and the
Playground are operational.

*Note.* Xmip is designed to succeed the previous generation of integration
servers, whose vendors now offer hosted services only. Its operator vocabulary
is deliberately theirs.
[`doc/planning/market-position.md`](doc/planning/market-position.md) holds
the comparison.

---

## Chief Engineering Officers

**Architecture.**

- The message path is Rust throughout. Concurrency, throughput and defect cost
  are decided there.
- The module boundary is a C ABI
  ([ADR-0012](doc/decision/ADR-0012-module-boundary.md)). A module implements
  a versioned table the runtime calls. Modules may be written in any language
  that implements the ABI and kept in their own repositories.
- Durability precedes execution. A Stream is accepted only when well-formed
  and, where a Contract is named, conformant
  ([ADR-0042](doc/decision/ADR-0042-a-contract-holds-well-formedness-always-and-conformance-when-named.md)).
  An accepted Message is on disk before anything acts on it; a Journey
  checkpoints and survives a restart
  ([runtime-model.md](doc/architecture/runtime-model.md)).
- One repository per module, forty-four in five domains, mounted at
  `module/<domain>/<leaf>`. Dependency rules are stated in the manifest and
  enforced by a test: foundation never depends on a technology, a technology
  may depend on its capability, operations consume public contracts only
  ([repository-model.md](doc/architecture/repository-model.md)).
- Four operator surfaces read one published snapshot through one shared
  library ([ADR-0014](doc/decision/ADR-0014-operator-surfaces.md),
  [ADR-0052](doc/decision/ADR-0052-the-operator-surfaces-share-one-model.md)).
  Observation never queries the message path
  ([ADR-0027](doc/decision/ADR-0027-the-operator-boundary.md)).
- Current platforms only: stable Rust, .NET 11, PowerShell 7.6.5 Core
  ([ADR-0021](doc/decision/ADR-0021-current-platforms-only.md)).

**Governance.** Fifty-two decision records, indexed by subject, are the memory
of the estate. A change that contradicts one is a new record or an amendment.
Rust and PowerShell style rules are gates in the test suite; length limits are
recommendations whose breach requires prior agreement and a recorded reason.
One command lands a change across every affected repository in dependency
order and refuses when a gate fails.

**Verification.** The Playground
([ADR-0028](doc/decision/ADR-0028-the-xmip-playground.md)) is an integration
test over time: every transport by every contract, round after round, with
injected faults, at four stress levels, with a fleet of node processes
contending over real files, publishing the snapshots the monitors read. The
estate's suite holds a test for every defect that has reached an operator's
console.

**Open items.**
[`doc/planning/open-problems.md`](doc/planning/open-problems.md) lists what is
undecided, in order, with options and a recommendation for each. A visual
designer is not built; the monitor is the first operator screen.

*Note.* The designs Xmip departs from are named in the decision records where
the departure was decided.
[`doc/planning/market-position.md`](doc/planning/market-position.md) holds
the comparison.

---

Licensed [AGPL-3.0-or-later](LICENSE).
