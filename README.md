# Xmip

**Accountable messaging and integration, under your control.**

Xmip is an on-premises-first, cloud-installable messaging and integration
platform. It is designed for organizations that must connect systems reliably
without making a cloud provider their control plane.

Xmip accepts data, validates what it has accepted, records responsibility for
it, processes it, and attempts every configured delivery. A Message does not
simply disappear when something goes wrong: its Journey, evidence and outcome
remain available so operators can understand what happened and decide what
happens next.

Written in Rust and licensed AGPL-3.0-or-later, Xmip runs on Windows, Linux and
macOS—from one server or edge device to an on-premises cluster or nodes in a
cloud of your choice. It can operate without internet access.

## Why Xmip

| Need | Xmip's answer |
| --- | --- |
| Keep data and operations under organizational control | On-premises first, air-gap capable and cloud-installable without a hosted control-plane dependency. |
| Know what happened to every accepted Message | Durable Messages, checkpointed Journeys, explicit outcomes and a persistent Audit. |
| Find integration failures without archaeology | Shared operational evidence, drill-down and reasons attached to the affected scope. |
| Connect old, current and specialist systems | Contracts, transports and processing capabilities are independent Modules behind a stable C ABI. |
| Change the platform without replacing it | Small capability boundaries, explicit dependencies and one repository per Module. |
| Avoid another opaque integration black box | Source-available implementation, recorded architectural decisions and machine-checked rules. |

Xmip deliberately carries forward useful integration-server concepts—Receive
Locations, Xmip Processes and Send Ports—while correcting the failure modes
documented in its decision record. The intended position is direct: **a
replacement for BizTalk, MuleSoft and their kind for estates that need control,
durability and explainability.**

This repository is the root of the Xmip estate. It contains the architecture
manifest, shared governance, decision records and the PowerShell module that
maintains the estate. Module repositories are mounted below `module/` as git
submodules.

| Reader | Start here |
| --- | --- |
| New to Xmip | [Beginner](#beginner) |
| Responsible for the engineering | [Chief Engineering Officer](#chief-engineering-officer) |
| Evaluating Xmip for an organization | [Chief Information Officer](#chief-information-officer) |
| Running Xmip | [Operator](#operator) |
| Building Xmip or a Module | [Developer](#developer) |

---

## Beginner

Think of Xmip as a post office for systems.

It accepts Streams from applications, files, queues, databases, mailboxes and
devices. It decides whether each arrival is acceptable, turns accepted content
into a Message, and gives that Message one or more Journeys. Each Journey can
process the Message and deliver it to its destination. If a delivery cannot
complete, Xmip retains the state and reports the reason instead of pretending
that transport acknowledgements are the same as successful application
delivery.

### Five terms to begin with

- **Stream.** What arrives: bytes from a file, socket or queue; rows from a
  database query; mail; or data from a device. A Stream belongs to the sender
  until Xmip accepts it.
- **Contract.** The rules for acceptance. Content must be well-formed and, when
  a Contract is named, conform to it. A refused Stream remains the sender's
  responsibility and the refusal says where and why it occurred.
- **Message.** Immutable content Xmip has accepted. An accepted Message is
  persisted before processing begins.
- **Journey.** One durable line of work for a Message. It checkpoints its
  progress and survives a restart.
- **Receive, Process, Send.** Receive Locations accept arrivals, Xmip Processes
  perform work, and Send Ports organize departures. The monitor uses the same
  progression.

The full vocabulary is in
[`doc/terminology.md`](doc/terminology.md).

### First run

1. Install PowerShell 7.6.5 or later. Windows PowerShell 5.1 is not supported.

   ```sh
   winget install Microsoft.PowerShell          # Windows
   sudo snap install powershell --classic       # Linux with snap
   sudo apt-get install -y powershell           # Debian or Ubuntu
   sudo dnf install -y powershell               # Fedora or RHEL
   brew install powershell                      # macOS
   ```

2. Clone the estate and load its PowerShell module.

   ```powershell
   git clone --recursive https://github.com/IlleNilsson/Xmip.git
   Set-Location -Path Xmip
   Import-Module -Name ./Xmip
   Install-XmipModule
   Install-XmipPrerequisite -Role developer -Install
   ```

3. Start the Playground and its monitor. The Playground is Xmip's local
   integration rehearsal; it needs no external system.

   ```powershell
   Start-XmipTest -Suite Playground -Test RoundTrip -Nodes alpha, beta -OnlineNodes alpha
   Start-XmipWeb -Snapshot .local-work/playground/playground-snapshot.toml
   Get-XmipTestStatus
   Get-XmipTestResult | Where-Object -Property State -NE -Value fine
   Stop-XmipTest
   Stop-XmipWeb
   ```

The monitor at <http://127.0.0.1:5087> shows the receive, process and send
stages, the cluster mood and each simulated node. Nothing starts on its own.
Every estate command that changes state supports `-WhatIf`;
`Get-Help Start-XmipTest -Full` documents every parameter.

---

## Chief Engineering Officer

Xmip is engineered around one promise: after it accepts responsibility for a
Message, the system must be able to say where that Message went, what acted on
it, whether delivery completed, and why work stopped when it did not.

### Architectural choices that serve that promise

| Engineering concern | Xmip's choice | Consequence |
| --- | --- | --- |
| Correctness under failure | Persist before execution; checkpoint each Journey. | Restarts resume durable work instead of reconstructing intent from logs. |
| Throughput and predictable resource use | Rust throughout the message path. | Memory safety without a garbage-collected hot path. |
| Extensibility | Versioned C ABI and independently loadable Modules. | A Module may use any language capable of implementing the ABI. |
| Operational consistency | CLI, PowerShell and both GUIs read one shared operator model. | A scope, mood or piece of evidence means the same thing on every surface. |
| Safe observation | The runtime publishes snapshots asynchronously. | Monitoring does not enter or slow the message path. |
| Deployment flexibility | The same node model on Windows, Linux and macOS. | Edge, server, cluster and cloud nodes do not require separate products. |
| Architectural memory | Accepted Architecture Decision Records and executable governance tests. | Important tradeoffs survive staff and assistant turnover. |

### Message ownership and failure boundaries

A Stream is not a Message merely because bytes arrived. Xmip accepts only
well-formed content and, where configured, content conforming to its Contract.
Acceptance transfers responsibility to Xmip; durability therefore precedes
execution. Routing creates Journeys, while assignment and transformation create
new immutable Message generations.

Failures are persisted with the Message state, Journey position,
classification, evidence and relevant identities. An unmatched accepted
Message goes to the Xmip Dead Message Queue (DMQ); a failed Journey remains a
failed Journey. Those cases are intentionally not collapsed into one generic
dead-letter queue because their recovery actions differ.

### Boundaries and scale

The architecture manifest is the estate's dependency graph. Foundation defines
what Xmip is; Capabilities define what it does; Technology repositories
implement those capabilities; Operations run and govern the system; Platform
repositories provide runtime-wide services. The root currently mounts 44 common
repositories, while the broader technology estate can mature independently.

Receive and Send own orchestration, ports and locations. Direction-neutral
Transport Modules move Streams. Message Modules own representation. Contract
Modules own acceptance rules. Logic Modules own method and operation semantics.
A Handler is a runtime role, not a competing repository family.

### Verification and engineering governance

The Playground exercises integration behavior over time with named node
processes, selectable online access, injected faults and several stress levels.
The estate test suite records defects as permanent checks. Style, dependency
direction, manifest integrity and documentation rules are machine-checked
before changes land.

The design record starts at:

- [`doc/architecture/runtime-model.md`](doc/architecture/runtime-model.md)
- [`doc/architecture/module-model.md`](doc/architecture/module-model.md)
- [`doc/architecture/repository-model.md`](doc/architecture/repository-model.md)
- [`doc/architecture/deployment-model.md`](doc/architecture/deployment-model.md)
- [`doc/architecture/observability-model.md`](doc/architecture/observability-model.md)
- [`doc/decision/README.md`](doc/decision/README.md)

### Current maturity

Xmip has not cut its first stable Linear release. `main` is the Continuum:
working, evolving and not yet a compatibility promise. The runtime, operator
surfaces and Playground are operational; many technology repositories remain
reserved or scaffolded. That distinction is recorded in `architecture.toml`
and should be part of every technical evaluation.

---

## Chief Information Officer

Xmip is for organizations whose integration problem is not simply moving data,
but retaining control and accountability while systems, partners, regulations
and deployment models change.

### The organizational case

- **Control.** Xmip runs on infrastructure you choose. It has no required
  hosted control plane and can operate in an air-gapped environment.
- **Sovereignty.** Data, configuration, audit and operational evidence remain
  within the deployment boundary your organization controls.
- **Continuity.** Accepted Messages are durable and Journeys survive restarts.
  The platform is designed around recovery rather than optimistic delivery.
- **Accountability.** Audit records responsibility and outcomes; monitoring
  shows current state. These are separate concerns, so a live dashboard is not
  mistaken for the historical record.
- **Portability.** Windows, Linux and macOS are equal deployment targets. A
  cloud node is an option, not a dependency.
- **Inspectable architecture.** Source and decisions are available for
  security, procurement and engineering review.

### Where Xmip fits

Xmip targets estates that would otherwise evaluate traditional integration
servers, enterprise service buses or hosted integration platforms, but need an
on-premises or sovereign deployment choice. Existing integration knowledge
remains useful because familiar responsibilities survive, while Xmip removes
shared-database bottlenecks and separates transport, content, contracts and
operation semantics.

The detailed market position—including BizTalk's lifecycle, sovereignty
pressures, e-invoicing and healthcare integration—is maintained in
[`doc/planning/market-position.md`](doc/planning/market-position.md). It is
planning evidence, not a substitute for product due diligence.

### Security and assurance

Deployment profiles—`standard`, `enterprise` and `regulated`—control
identity isolation and whether a node fails closed when required assurance is
unavailable. Authentication is evaluated per protocol, authorization follows
it, and Receive and Send identities remain directionally explicit. Audit and
failure persistence provide the evidence needed for investigation and recovery.

Xmip is developed in Sweden and licensed AGPL-3.0-or-later. There is no
commercial or dual license and no contributor agreement designed to enable
later relicensing. Modules written independently against the C ABI remain the
author's work under the author's chosen terms. Organizations whose policy
excludes AGPL should identify that constraint at the start of evaluation.

### A responsible adoption path

1. **Prove the operational model.** Run the Playground locally and inspect
   failure, recovery and monitoring behavior.
2. **Select one bounded integration.** Prefer a flow with a known Contract,
   clear ownership and a measurable delivery outcome.
3. **Run beside the incumbent.** Compare acceptance, throughput, evidence and
   recovery without making the pilot a migration event.
4. **Review the deployment profile.** Involve security, operations and data
   owners before moving responsibility for production Messages.
5. **Adopt a Linear release when available.** Until then, treat the Continuum
   as an engineering evaluation rather than a supported production product.

---

## Operator

Xmip gives an operator one job: keep accepted Messages moving, and know why
they are not moving when work stops. The operating model is designed to answer
three questions quickly:

1. What is affected?
2. What is Xmip doing about it?
3. What evidence explains the current condition?

### One operational model

Every operational scope has a mood: Fine, Working, Stressed, Paused, Holding or
Done. Holding is never shown alone; it carries the worst affected leaf and its
evidence. Operators can drill from a cluster into nodes, stages, services and
locations without asking the message path to count itself.

The command line, PowerShell and both GUIs use the same scope tree, figures,
moods and evidence. They are different presentations of one model rather than
separate management products that can disagree.

| Surface | Best use |
| --- | --- |
| `xmip` | Human-readable commands, JSON for automation and JSON Lines for following changes over SSH or a pipe. |
| PowerShell | Typed objects that compose with filtering, remoting, scripts and existing administration practices. |
| Web monitor | Read-only shared monitoring with progressive drill-down. |
| Desktop monitor | Monitoring and configuration on Windows, Linux and macOS. |

The web monitor cannot change the runtime. Observation reads snapshots
published asynchronously by the runtime and never enters the message path.
Audit is the durable record of actions and outcomes; a live monitor is not a
replacement for it.

### Platforms and installation

Linux, Windows and macOS are equal operating targets. The runtime, command line,
PowerShell module and monitors use the same Xmip model on each.

| Concern | Windows | Linux | macOS |
| --- | --- | --- | --- |
| PowerShell 7.6.5 or later | `winget` | `snap`, `apt`, `dnf`, `zypper` or `pacman` | `brew` |
| Local installation | `install/install-local.ps1` | `install/install-local.sh` | `install/install-local.sh` |
| Desired state | DSC | Ansible | Ansible |
| Remote operation | PowerShell Remoting over WinRM or SSH | SSH | SSH |

`Install-XmipPrerequisite -Role operator` reports what a machine lacks;
`-Install` installs it. The command does not elevate itself. When a package
needs administrative rights, it prints the required command and stops.

### Configuration and control

Configuration is TOML on disk; JSON is reserved for wire exchange.
`xmip validate <file>` checks a node configuration without starting the node.
A node is offline unless its configuration explicitly says `online = true`.
Online access is therefore a declared operational choice, not an accidental
side effect of deployment.

The CLI exposes `measure`, `list`, `show`, `pause` and `resume`.
PowerShell supplies the corresponding pipeline objects and
`Suspend-XmipScope` and `Resume-XmipScope`, both with `-WhatIf`. Start,
stop and restart belong to service and host lifecycle management rather than
the observation boundary. The read-only web monitor exposes none of those
actions.

Deployment profiles—`standard`, `enterprise` and `regulated`—set identity
isolation and whether the runtime fails closed when required assurance is
unavailable. Receive and Send identities are configured independently because
Xmip is the server on receive and the client on send.

### Working an incident

1. Start at the cluster mood and read its evidence.
2. Drill into the worst node, stage and leaf scope.
3. Distinguish a refused Stream, unmatched Message and failed Journey; each has
   a different owner and recovery path.
4. Inspect the durable Audit and failure state before changing configuration.
5. Pause or resume only through the shared operator boundary, then confirm the
   new published state.

An unmatched accepted Message belongs in the Xmip DMQ and can be republished
after its Subscription is corrected. A failed Journey retains its execution
position and resumes from its checkpoint. A refused Stream never became an Xmip
Message and remains the sender's responsibility.

### Rehearsal

The Playground rehearses named scenarios, node availability and stress levels
without requiring a production system:

```powershell
Start-XmipTest -Suite Playground -Test HeavyLoad, LowLatency -Stress Harsh -Nodes n1, n2, n3
Get-XmipTestStatus
Get-XmipTestResult -Test HeavyLoad -Worst
Stop-XmipTest
```

Use it to practice diagnosis and recovery, verify an operational change, and
demonstrate the monitor before Xmip is connected to organizational data.

---

## Developer

Xmip is an estate of deliberately small Modules around a stable boundary. The
fastest way to contribute is to learn the nouns first, find the accepted
decision that owns the subject, and then change the smallest responsible
repository.

### Setup

Complete the [first run](#first-run), then configure submodule safety:

```powershell
git submodule update --init --recursive
git config push.recurseSubmodules check
```

A submodule is a pinned commit, not a branch.
[CONTRIBUTING.md](CONTRIBUTING.md) explains how a Module change lands before
the superproject updates its pin.

### Build, test and land

The runtime and Modules use stable Rust. The .NET operator surfaces target
.NET 11; the PowerShell binary module targets `net10.0` because PowerShell
hosts it.

```powershell
Start-XmipTest -Suite Estate
Start-XmipTest -Suite Estate -Test Rust.Style
Publish-XmipChange -Message 'short precise message'
```

`Publish-XmipChange` verifies and lands affected repositories in dependency
order, Modules first. Rust formatting, Clippy with warnings denied, and the
relevant suites must pass. Until the first Linear release, accepted work lands
on `main` as described in
[`doc/governance/release-model.md`](doc/governance/release-model.md).

### Repository layout

```text
architecture.toml     every declared repository and dependency
prerequisite.toml     tools required by role and operating system
rust-toolchain.toml   the Rust channel
Xmip/                 the estate PowerShell module
module/               common Modules mounted by domain
test/                 estate tests and the Playground
deploy/               Ansible roles and DSC configuration
install/              local installation layouts
template/             Rust and .NET repository templates
doc/                  architecture, decisions, governance and planning
```

### Adding or changing a capability

1. Search [`doc/decision/README.md`](doc/decision/README.md) for the subject.
2. Read the relevant architecture model and
   `doc/planning/open-problems.md`.
3. Do not contradict an accepted decision silently; propose an amendment or a
   new decision.
4. Put shared behavior in the capability that owns it, not in each technology
   implementation.
5. Keep dependencies explicit and preserve the direction rules in
   `architecture.toml`.
6. Add verification for the behavior or defect before landing the change.

The implementation guide for transports, Contracts and Processes is
[`doc/development/creating-transports-contracts-and-processes.md`](doc/development/creating-transports-contracts-and-processes.md).

### Estate commands

| Command | Purpose |
| --- | --- |
| `Install-XmipModule` | Link the module into `PSModulePath`. |
| `Install-XmipPrerequisite` | Report or install requirements for a role. |
| `Sync-XmipEstate` | Report manifest drift, configure repositories and compose submodules. |
| `Sync-XmipRepository` | Work with local copies: clone, pull, status, branch, push and distribute. |
| `Get-XmipManifest`, `Test-XmipManifest` | Read and validate the architecture manifest. |
| `Get-XmipStatus` | Report dirty, ahead and behind state across the estate. |
| `Publish-XmipChange` | Verify and land changes in dependency order. |
| `Start-XmipTest`, `Get-XmipTestStatus`, `Stop-XmipTest` | Control an estate or Playground test run. |
| `Start-XmipTestNode`, `Get-XmipTestNode`, `Stop-XmipTestNode` | Control named simulated nodes. |
| `Get-XmipTestResult`, `Get-XmipHistory` | Read current and historical results. |
| `Start-XmipWeb`, `Get-XmipWeb`, `Stop-XmipWeb` | Control the web monitor. |
| `Get-XmipDecisionRecord`, `New-XmipDecisionIndex` | Read and maintain the decision record. |

Examples:

```powershell
Sync-XmipEstate
Sync-XmipEstate -Create -WhatIf
Sync-XmipEstate -Compose
Sync-XmipRepository -Status
Get-XmipStatus
```

`-Create` and `-Configure` require a GitHub token with `repo` scope,
supplied through `-GitHubToken` or `$env:GITHUB_TOKEN`. Nothing deletes a
repository.

### Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) and [GOVERNANCE.md](GOVERNANCE.md).
Rust and PowerShell style rules are enforced by the suite. Established
architectural decisions require explicit permission before they change. A
Module is a crate behind the C ABI and may be written in any language capable
of implementing that boundary.

---

Licensed [AGPL-3.0-or-later](LICENSE).
