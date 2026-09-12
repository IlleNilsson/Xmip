# Xmip

**A messaging and integration platform that runs where your data is.
On-premises first, cloud-installable.** Written in Rust, built around
immutable Streams, immutable Messages, long-running Journeys, modular
capabilities and implied Contracts. Licensed AGPL-3.0-or-later, with no
second license.

It runs on Windows, Linux and macOS, on a single server, an on-premises
cluster, a cloud node or a small device, and it works with no internet at all.
Nothing in Xmip phones anywhere to work.

This repository is the root of the estate: the manifest that names every Xmip
repository, the architecture record, the decision record, and the PowerShell
module that reconciles all of it against reality. The forty-four module
repositories are mounted beneath `module/` as git submodules.

Read the section written for you:

| You are | Read |
| --- | --- |
| new to Xmip, or to integration platforms | [Beginners](#beginners) |
| running Xmip for an organization | [Operators](#operators) |
| building Xmip, or a module for it | [Developers](#developers) |
| deciding whether Xmip belongs in your estate | [Chief Information Officers](#chief-information-officers) |
| answering for the engineering | [Chief Engineering Officers](#chief-engineering-officers) |

---

## Beginners

Xmip receives data, processes it and sends it on. Every word it uses is chosen
and explained in [`doc/terminology.md`](doc/terminology.md); these five are
enough to start:

- A **Stream** is what arrives: bytes from a file, a socket, a queue, a mail
  box, the rows a SQL statement returns, a device on a bus. Until Xmip has
  accepted it, it is the sender's; a Stream in flight does not survive a
  restart, and the sender's protocol says so.
- A **Message** is what Xmip accepted the Stream as: immutable content with a
  shape. A **Contract** decides the acceptance: the content must be well-formed
  always, and where a Contract is named it must conform to it, or the Stream
  is refused and the sender is told where and why. An accepted Message is on
  disk before anything acts on it and never disappears.
- A **Journey** is the path a Message takes through Xmip, step by step, and
  it may take a long time. A Journey checkpoints and survives a restart.
- **Receive, Process, Send** are the three stages of that path. The monitor is
  organized around them.
- **Every scope has a Status:** Fine, Working, Stressed, Holding, Done. A
  Status names what an operator can do about it, and the worst one beneath a
  scope says where to look. How a Status is presented, as a word, a color, a
  shape, a sound, is the surface's choice; the Status itself is the same on
  every surface.

Nothing starts on its own. You start Xmip, you start a test, you start the
monitor, and you stop them. The fastest way to see it move is the Playground,
Xmip's own integration test, which needs no network and no other software.

**Fifteen minutes, on any of the three platforms.**

1. Install PowerShell 7.6.5 or later (the Core edition; Windows PowerShell 5.1
   is a different product and will not do):

   ```sh
   winget install Microsoft.PowerShell                    # Windows
   sudo snap install powershell --classic                 # Linux, any distribution with snap
   sudo apt-get install -y powershell                     # Debian and Ubuntu, after Microsoft's package repository is added
   sudo dnf install -y powershell                         # Fedora and RHEL, after Microsoft's package repository is added
   brew install powershell                                # macOS
   ```

   Then `pwsh` opens it. Microsoft's own page has the repository lines for
   each distribution. The rest of this file runs inside `pwsh`, identically on
   every platform.

2. Get the estate and load its module:

   ```powershell
   git clone --recursive https://github.com/IlleNilsson/Xmip.git
   cd Xmip
   Import-Module -Name ./Xmip
   Install-XmipModule                                    # once: links the module so any later shell finds it
   Install-XmipPrerequisite -Role developer -Install     # Rust, a linker, Pester, .NET
   ```

   From then on, in any shell and any directory, `Import-Module -Name Xmip`
   is enough; the link is a junction on Windows and a symbolic link elsewhere,
   so edits in the repository are live in the next session.

3. Start a test, watch it, stop it:

   ```powershell
   Start-XmipTest -Suite Playground -Test RoundTrip -Nodes alpha, beta -OnlineNodes alpha
   Start-XmipWeb -Snapshot .local-work/playground/playground-snapshot.toml
   Get-XmipTestStatus                                    # what runs, at what stress, with which nodes
   Get-XmipTestResult | Where-Object -Property State -NE -Value fine
   Stop-XmipTest
   Stop-XmipWeb
   ```

   Every parameter is named, here and in every Xmip document; PowerShell
   accepts the first two by position, but a line that names them reads the
   same to a person who has never seen the command.

   The board at http://127.0.0.1:5087 shows the three stages, the cluster's
   Status and every node. `alpha` and `beta` are two simulated node processes;
   `alpha` is allowed to assume the internet, `beta` is not.

Every command that changes anything takes `-WhatIf` and does nothing but say
what it would do. `Get-Help Start-XmipTest -Full` explains every switch.

---

## Operators

**Platforms.** Xmip tracks current platforms and does not carry compatibility
with superseded ones ([ADR-0021](doc/decision/ADR-0021-current-platforms-only.md)).
Linux is a first-class platform, not a port: the runtime, the `xmip` command
line, the PowerShell module and the web monitor run there as they do on
Windows, and the deployment tooling has a Linux shape of its own.

| | Windows | Linux | macOS |
| --- | --- | --- | --- |
| PowerShell 7.6.5+, Core | `winget` | `snap`, `apt`, `dnf`, `zypper`, `pacman` | `brew` |
| Prerequisites | `Install-XmipPrerequisite` reads [`prerequisite.toml`](prerequisite.toml), which declares a package per operating system and per package manager | | |
| Local layout | `install/install-local.ps1`, under `%ProgramData%\Xmip` | `install/install-local.sh`, under `/opt/xmip` | `install/install-local.sh` |
| Desired state | `deploy/dsc/xmip-node.dsc.yaml` | `deploy/ansible/roles` | `deploy/ansible/roles` |
| Remote operation | PowerShell Remoting over WinRM or SSH | SSH | SSH |

`Install-XmipPrerequisite -Role operator` reports what a machine is missing;
`-Install` installs it. It never elevates: where a package needs
administrative rights it prints the command and stops, because a script that
silently runs elevated installers is the thing an estate blocks. A
prerequisite below its floor fails the command rather than warning, so an
automated check notices.

**What you operate with.** Four surfaces read one boundary
([ADR-0014](doc/decision/ADR-0014-operator-surfaces.md),
[ADR-0027](doc/decision/ADR-0027-the-operator-boundary.md)), so no two of them
can disagree:

| Surface | What it is |
| --- | --- |
| `xmip` | the command line: `xmip health <scope>`, `--json`, `--follow` for a stream of changes over SSH or a pipe |
| the PowerShell module | the same answers as objects on the pipeline, and a live health segment in the prompt |
| the web monitor | reads and shows; it never changes anything, so it can face many operators |
| the desktop | monitors and configures, on Windows, Linux and macOS |

Observation never sits in the message path and can never slow it: every
surface reads a snapshot the runtime published. Audit is the durable record.

**Two switches you decide.** A node is *offline* unless you say otherwise
([ADR-0045](doc/decision/ADR-0045-offline-is-the-default.md)): `online = true`
in a node's configuration says it may assume a route to the internet, for the
duties that need one, such as certificate provisioning at a public edge. A
security profile, `standard`, `enterprise` or `regulated`, sets how the runtime
isolates identities and whether it fails closed
([deployment-model.md](doc/architecture/deployment-model.md), section 4).

**Configuration is TOML on disk, and JSON only on the wire**
([ADR-0031](doc/decision/ADR-0031-configuration-is-toml-json-is-transport.md)).
Every configuration file can be checked without starting anything:
`xmip validate <file>`.

**Rehearse before you trust.** The Playground runs Xmip's own scenarios over
time, at a stress you choose, with as many simulated node processes as you
name; it is how the estate proves itself and how you can prove a machine:

```powershell
Start-XmipTest -Suite Playground -Test HeavyLoad, LowLatency -Stress Harsh -Nodes n1, n2, n3
Get-XmipTestStatus
Stop-XmipTest
```

---

## Developers

**Set up.** After the beginner's three steps, the estate module gives you
everything else. Clone with `--recursive`, and after any pull:

```powershell
git submodule update --init --recursive
git config push.recurseSubmodules check      # once, per clone
```

A submodule is a commit, not a branch; the four facts that explain every
submodule surprise are in [CONTRIBUTING.md](CONTRIBUTING.md).

**Build and test.** The runtime and the modules are Rust on the stable channel;
the operator surfaces are .NET 11 (the PowerShell module targets `net10.0`
because `pwsh` hosts it). One command tests and lands a change across every
repository it touched, in dependency order, modules first:

```powershell
Start-XmipTest -Suite Estate                          # the estate's own suite: every past defect
Publish-XmipChange -Message 'short precise message'   # test, commit, push, pin; xgit is its alias
```

`Start-XmipTest -Suite Estate -Test Rust.Style` runs one file. `cargo fmt`,
`cargo clippy --workspace --all-targets -- -D warnings` and the suite pass
before every commit; until the first Linear release, work commits directly to
`main` ([release-model.md](doc/governance/release-model.md)).

**Where things are.**

```text
architecture.toml     the estate: every repository, named by its position in the tree
prerequisite.toml     what a machine needs, per role and per operating system
rust-toolchain.toml   channel = stable

Xmip/                 the estate's PowerShell module
module/               the modules, mounted as git submodules at module/<domain>/<leaf>
test/                 the estate's Pester suite, and test/playground, the Playground
deploy/               Ansible roles and a DSC configuration for a node
install/              the local layout, one script for Windows and one for the rest
template/             what a new Rust or .NET repository is generated from
doc/                  see below
```

**Read before writing.** The estate is governed by its own records and they
are current: [`doc/decision/README.md`](doc/decision/README.md) is the
decision index, read by subject; the five models under
[`doc/architecture/`](doc/architecture) say what Xmip does and why it is
shaped this way; [`rust-style.md`](doc/governance/rust-style.md) and
[`powershell-style.md`](doc/governance/powershell-style.md) are enforced by
the suite, not aspirational. Do not contradict an accepted record; propose a
new one or an amendment.

| Document | Answers |
| --- | --- |
| [`doc/terminology.md`](doc/terminology.md) | what every Xmip word means |
| [`architecture/runtime-model.md`](doc/architecture/runtime-model.md) | what Xmip does at runtime |
| [`architecture/repository-model.md`](doc/architecture/repository-model.md) | why the estate is shaped this way |
| [`architecture/module-model.md`](doc/architecture/module-model.md) | the module boundary, loading and isolation |
| [`architecture/deployment-model.md`](doc/architecture/deployment-model.md) | nodes, profiles, roles, installation, recovery |
| [`architecture/observability-model.md`](doc/architecture/observability-model.md) | audit, logs, traces, retention, observation |
| [`doc/decision/`](doc/decision) | every decision, read as one document, by subject |
| [`development/creating-transports-contracts-and-processes.md`](doc/development/creating-transports-contracts-and-processes.md) | how to add a transport, a contract or a process |
| [`doc/planning/open-problems.md`](doc/planning/open-problems.md) | what is open, and in what order |

Two documents live with the repository that owns them: identity per protocol
against the standards in `module/capability/authenticate/doc/`, and the
normative ABI specification in `module/foundation/abi/doc/`. `doc/planning/`
is working notes and explicitly not authoritative.

**The estate module.** Every command supports `-WhatIf`; reporting is the
default and needs no ceremony.

| Command | Does |
| --- | --- |
| `Install-XmipModule` | links this module onto `PSModulePath`, once |
| `Install-XmipPrerequisite` | reports and installs what a machine needs, per role |
| `Sync-XmipEstate` | reconciles the estate with `architecture.toml`: creates and configures on GitHub, composes the submodule tree |
| `Sync-XmipRepository` | local working copies: clone, pull, status, branch, push, distribute |
| `Get-XmipManifest`, `Test-XmipManifest` | reads and validates `architecture.toml` |
| `Get-XmipStatus` | the whole estate at once: dirty, ahead, behind, per repository |
| `Publish-XmipChange` (`xgit`) | tests and lands a change, dependency order, modules first |
| `Start-XmipTest`, `Get-XmipTestStatus`, `Stop-XmipTest` | a suite of Xmip's tests: the Playground, or the estate's Pester suite |
| `Start-XmipTestNode`, `Get-XmipTestNode`, `Stop-XmipTestNode` | simulated node processes by name, online or not |
| `Get-XmipTestResult`, `Get-XmipHistory` | what a run says now, and over time |
| `Start-XmipWeb`, `Get-XmipWeb`, `Stop-XmipWeb` | the web monitor |
| `Get-XmipDecisionRecord`, `New-XmipDecisionIndex` | the decision record and its index |

```powershell
Sync-XmipEstate                                       # report drift, change nothing
Sync-XmipEstate -Create -WhatIf                       # what would be created on GitHub
Sync-XmipEstate -Compose                              # wire the submodule hierarchy locally
Sync-XmipRepository -Status                           # what is dirty, ahead, behind
Get-XmipStatus                                        # the whole estate at once
```

`-Compose` mounts every repository at its place in the tree, so
`git clone --recursive` reproduces it; parents pin commits deliberately
([ADR-0016](doc/decision/ADR-0016-submodule-composition.md)). Nothing ever
deletes a repository. `-Create` and `-Configure` need a GitHub token with
`repo` scope, from `-GitHubToken` or `$env:GITHUB_TOKEN`.

**Contributing.** Read [CONTRIBUTING.md](CONTRIBUTING.md) and
[GOVERNANCE.md](GOVERNANCE.md). Established architectural decisions need
explicit permission before they change
([architectural-change-permission.md](doc/governance/architectural-change-permission.md)).
A module for Xmip is a crate against a C ABI
([ADR-0012](doc/decision/ADR-0012-module-boundary.md)); it may be written in
any language that can implement one.

---

## Chief Information Officers

**What you get.** One platform that receives, processes and sends your
organization's data between the systems you run and the partners you deal
with: files, queues, sockets, databases, cloud services, industrial and
healthcare protocols, e-invoicing networks. It runs on the machines you
choose, a single server, a cluster on your premises, a node in a cloud you
pick, or a small device at the edge, on Windows, Linux or macOS, and it
behaves the same on all of them.

**What stays yours.** Your data stays on your machines. Xmip installs and
runs with no internet at all; a node may reach out only when you have said so
in its configuration, and nothing in it reports anywhere. Every accepted
message is written to disk before anything acts on it, and nothing accepted is
ever lost. Everything Xmip does is recorded in an audit that is separate from
the live monitoring, so what happened is always answerable afterwards.

**What it costs, and what it cannot do to you.** Xmip is AGPL-3.0-or-later
and there is no commercial license, no dual license and no contributor
agreement that could ever enable one
([ADR-0023](doc/decision/ADR-0023-licensing-model.md)). A platform that cannot
be relicensed cannot be taken away from you or priced away from you later.
Your legal team may reject AGPL as policy; that cost is known and accepted,
and the record says so. A module you write against the C ABI is your own
work, under your own terms.

**What you can require of it.** Three security profiles, `standard`,
`enterprise` and `regulated`, decide how strictly identities are isolated and
whether the runtime stops rather than run unobserved. Identity is proven per
protocol against the published standards; certificates are the first
mechanism built, provisioned by Let's Encrypt at a public edge and by your own
authority everywhere else. It is Swedish and source-available, which matters
where sovereignty is legislated, and it speaks the AS4 and Peppol e-invoicing
protocols that European mandates require from 2026 onward.

**Where it stands, plainly.** Xmip has no stable release yet. `main` is the
Continuum, the evolving truth; a Linear release is a stabilized, reproducible,
versioned line cut from it, and the first has not been cut
([release-model.md](doc/governance/release-model.md)). The manifest declares
the maturity of every one of the estate's repositories; planned is not built,
and the record never says otherwise. Three hundred and forty-three
repositories are declared, most of them protocol, contract and archive
technologies; forty-four are built and mounted, and the runtime, the operator
surfaces and the Playground are what run today.

*Footnote.* Xmip is built to take over from the integration servers of the
previous generation, whose vendors now sell hosted services only; its operator
vocabulary is theirs on purpose, so existing knowledge transfers. The
competitive position, the dates and the honest counterweights are in
[`doc/planning/market-position.md`](doc/planning/market-position.md).

---

## Chief Engineering Officers

**What you get.**

- **A runtime in Rust, in the whole message path.** Correctness under
  concurrency, throughput and the cost of a defect are decided there, and
  nothing in the path is garbage-collected or interpreted.
- **A module boundary that is a C ABI**
  ([ADR-0012](doc/decision/ADR-0012-module-boundary.md)). A module implements
  a versioned table the runtime calls. Your team can write a module in any
  language that implements one, keep it in your own repository under your own
  terms, and load it into a node without touching Xmip.
- **Durability before execution.** A Stream is accepted only when it is
  well-formed and, where a Contract is named, conforms to it
  ([ADR-0042](doc/decision/ADR-0042-a-contract-holds-well-formedness-always-and-conformance-when-named.md)).
  An accepted Message is on disk before anything acts on it; a Journey
  checkpoints and survives a restart; an abrupt stop loses nothing accepted,
  and a Stream not yet accepted is still the sender's
  ([runtime-model.md](doc/architecture/runtime-model.md)).
- **An estate you can read.** One repository per module, forty-four today in
  five domains, mounted as submodules at `module/<domain>/<leaf>`; dependency
  rules the manifest states and a test enforces: foundation never depends on
  a technology, a technology may depend on its capability, operations consume
  public contracts only ([repository-model.md](doc/architecture/repository-model.md)).
- **Four operator surfaces that cannot disagree.** The command line, the
  PowerShell module and the two GUI hosts read one published snapshot through
  one shared library ([ADR-0014](doc/decision/ADR-0014-operator-surfaces.md),
  [ADR-0052](doc/decision/ADR-0052-the-operator-surfaces-share-one-model.md)).
- **Monitoring that cannot slow the runtime.** Observation reads what the
  runtime published; it never asks the hot path for a number
  ([ADR-0027](doc/decision/ADR-0027-the-operator-boundary.md)).
- **Current platforms only.** Stable Rust, .NET 11, PowerShell 7.6.5 Core;
  nothing carries a superseded platform ([ADR-0021](doc/decision/ADR-0021-current-platforms-only.md)).

**How the engineering is governed.** Fifty-two decision records, read as one
document by subject, are the memory of the estate; a change that contradicts
one is a new record or an amendment, never a quiet edit. The style rules for
Rust and PowerShell are gates in the test suite. Length limits are strict
recommendations, and breaking one needs the owner's agreement first and the
reason recorded. One command lands a change across every repository it
touched, in dependency order, and refuses when a gate fails.

**How it proves itself.** The Playground ([ADR-0028](doc/decision/ADR-0028-the-xmip-playground.md))
is an integration test over time, not a unit suite: every transport by every
contract, round after round, with injected faults, at four stress levels, with
a fleet of node processes contending over real files, publishing the same
snapshots the monitors read. The estate's own suite holds a test for every
defect that reached the operator's console, and says so in each test.

**What is open.** [`doc/planning/open-problems.md`](doc/planning/open-problems.md)
lists what is undecided, in order, with the options and the lean for each. The
monitor is the first screen an operator can look at; a visual designer is not
built.

*Footnote.* The designs Xmip replaces are named in the decision records where
a choice was made against them, each with its reason;
[`doc/planning/market-position.md`](doc/planning/market-position.md) holds
the comparison as a whole.

---

Licensed [AGPL-3.0-or-later](LICENSE).
