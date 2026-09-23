# Xmip

**Accountable messaging and integration, under your control.**

Xmip is an on-premises-first, cloud-installable messaging and integration
platform for organizations that must connect systems reliably without making
a cloud provider their control plane.

Xmip accepts data, validates what it has accepted, records responsibility for
it, processes it, and attempts every configured delivery. A Message does not
disappear when something goes wrong: its Journey, evidence and outcome remain
available so an operator can see what happened and decide what happens next.

Written in Rust and licensed AGPL-3.0-or-later, Xmip runs on Windows, Linux
and macOS — from one server or edge device to an on-premises cluster or nodes
in a cloud of your choice. It operates without internet access.

## Why Xmip

| Need | Xmip's answer |
| --- | --- |
| Keep data and operations under organizational control | On-premises first, air-gap capable and cloud-installable, with no hosted control plane. |
| Know what happened to every accepted Message | Durable Messages, checkpointed Journeys, explicit outcomes and a persistent Audit. |
| Find integration failures without archaeology | One operational model: the worst scope, its Status and its evidence, on every surface. |
| Connect old, current and specialist systems | Contracts, transports and processing capabilities are independent Modules behind a stable C ABI. |
| Change the platform without replacing it | Small capability boundaries, explicit dependencies and one repository per Module. |
| Avoid another opaque integration black box | Source-available implementation, recorded architectural decisions and machine-checked rules. |

Xmip deliberately carries forward the integration-server concepts that worked
— Receive Locations, Xmip Processes and Send Locations — while correcting the
failure modes its decision record names.

This repository is the root of the Xmip estate: the manifest that names every
Xmip repository, the architecture models, the decision records, the
governance, and the PowerShell module that maintains them. Module
repositories are mounted under `module/` as git submodules.

| Reader | Start here |
| --- | --- |
| New to Xmip | [Beginner](#beginner) |
| Responsible for the engineering | [Chief Engineering Officer](#chief-engineering-officer) |
| Evaluating Xmip for an organization | [Chief Information Officer](#chief-information-officer) |
| Running Xmip | [Operator](#operator) |
| Building Xmip or a Module | [Developer](#developer) |

---

## Beginner

Xmip accepts Streams from applications, files, queues, databases, mailboxes and
devices. It decides whether each arrival is acceptable, turns accepted content
into a Message, and gives that Message one or more Journeys. Each Journey can
process the Message and deliver it to its destination. If a delivery cannot
complete, Xmip keeps the state and reports the reason instead of treating a
transport acknowledgement as a successful application delivery.

### The terms to begin with

A Stream arrives, and its arrival is audited before anything else. It is
deserialized and validated against a Contract; if that fails, the refusal
is reported, the Stream is disregarded, and the failure is audited. If it
holds, the content is published into Xmip as a
Message, and where a Subscription picks the Message up a Journey begins, to
an Xmip Process, a Send Port or a Send Port Group. The terms, in that order:

- **Stream.** What arrives at a Receive Location: bytes from a file, a
  socket, a queue, a mailbox, the rows a SQL statement returns, a device on
  a bus. A Stream belongs to the sender until Xmip accepts it.
- **Auditing.** The first thing that happens to an arrival, and the last
  to every outcome: the durable record of what Xmip did and how it came
  out. Every step below carries a note of what it audits. Entry, refusal,
  leaving, assignment, transformation, passing on, pickup, sending and
  every failure are always audited; policy may add to that list and never
  take from it. A failure is kept in its failure-time state, with the
  Message, the place and the reason, so it can be inspected, explained,
  retried or replayed. The record is what settles a dispute between two
  parties about what was sent and what was received.
- **Contract.** The rules for acceptance. A Stream is deserialized and must
  be well-formed and, where a Contract is named, conform to it. A Stream
  that fails is refused: the refusal says where and why, and the Stream
  stays the sender's responsibility.
  *Audited: the validation, and the refusal with its place and reason.*
- **Message.** Validated content, published into Xmip. A Message is
  immutable, written to disk before anything acts on it, and never lost.
  Assignment and transformation do not change it; each writes a new
  generation of it, and every generation is kept.
  *Audited: entry into Xmip, once per Message.*
- **Subscription.** What picks a published Message up: an Xmip Process, a
  Send Port or a Send Port Group declares the Messages it wants. A Message
  is published once and every Subscription that matches it opens one
  Journey; publishing creates no new Message. A Message no Subscription
  picks up goes to the Dead Message Queue, which is not a dead letter
  queue: nothing failed, nothing wanted it, and it is republished once the
  Subscription is corrected.
  *Audited: each pickup, by which Subscription, and a Message nothing
  picked up.*
- **Journey.** One durable line of work for a Message, begun by one
  Subscription, ending at the Xmip Process's answer or at the delivery. It
  checkpoints and survives a restart, and it ends Completed, Failed, or
  Dismissed when an operator stops it on purpose.
  *Audited: its beginning, each passing on, and how it ended.*
- **Processing.** What an Xmip Process does when a Subscription starts one:
  a definition running step by step and answering with a Message, no
  Message, or waiting for something named; a Message it answers with is
  published into Xmip like any other. It is not an operating system
  process, it receives no Streams and delivers nothing outside, and its
  state belongs to the cluster, never to a thread or a node. A Journey to a
  Send Port has no Processing.
  *Audited: the start, each step's outcome, and the answer.*
- **Assignment.** Setting values in a Message's context, from a literal or
  from another value, in order. It belongs to an Xmip Process alone and
  creates a new Message generation, as transformation does; publishing does
  not.
  *Audited: every assignment and every transformation, with the generation
  it wrote.*
- **Send.** A Send Port delivers a Message through its Send Locations; a
  Send Port Group is several Send Ports subscribed as one, so one Message
  goes to each. A transport acknowledgement is not an application delivery,
  and every surface names the exact Location.
  *Audited: every sending, and the Message leaving Xmip.*
- **Resilience.** Every delivery and every call out is an attempt, and a
  guard is asked before each attempt whether it may go, must wait, is refused
  or is answered by a fallback, and after it whether the outcome stands, the
  attempt is repeated, or the work is given up. Retry, timeout, circuit
  breaker, rate limit, bulkhead and fallback are the six guards
  ([ADR-0048](doc/decision/ADR-0048-a-resilience-technology-is-a-guard-on-the-attempt.md)).
  A guard judges; it never runs the operation. Retrying and Failed are
  counted at every scope and shown on every surface.
  *Audited: every failed attempt, and the giving up, with the Message in
  its failure-time state.*
- **Retention.** For the data it holds Xmip does two things over time: it
  retains a Message while it is live and archives it when its retention
  window passes. It never deletes. What becomes of an archive is the archive
  owner's decision, not Xmip's
  ([ADR-0040](doc/decision/ADR-0040-xmip-retains-and-archives-it-does-not-delete.md)).
- **Status.** Every leaf has a mood: Fine, Paused, Working, Stressed,
  Exhausted or Done. A scope above a leaf is Holding when a leaf beneath it
  needs attention, and it carries that leaf and its evidence, so the worst
  Status beneath a scope says where to look. Receive, Process and Send are
  the three stages every surface counts and colors.

The full vocabulary is in [`doc/terminology.md`](doc/terminology.md).

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

2. Clone the estate and load its PowerShell module.

   ```powershell
   git clone --recursive https://github.com/IlleNilsson/Xmip.git
   Set-Location -Path Xmip
   Import-Module -Name ./Xmip
   Install-XmipModule
   Install-XmipPrerequisite -Role developer -Install
   ```

   `Install-XmipModule` links the module into your user module path. In any
   later shell, `Import-Module -Name Xmip` is sufficient.

   A console of its own, in Windows Terminal: add a profile whose starting
   directory is the clone and whose command line is

   ```text
   pwsh -NoExit -Command "Import-Module -Name D:\Repos\Xmip\Xmip\Xmip.psd1"
   ```

   Do not add `-NoProfile`. posh-git is imported by a PowerShell profile
   file, `-NoProfile` skips every one of them, and the prompt then shows
   `PS D:\Repos\Xmip>` with no repository state (the owner's console,
   2026-09-18). Leave the Xmip status segment out of the command line and
   import it in the session that wants it: a console holding that module
   holds its assemblies, and a build into them fails until it is closed.
   That console is `pwsh`, which `Get-Process -Name xmip-*` does not find.

3. Start the Playground and its monitor. The Playground is Xmip's own
   integration rehearsal; it needs no network and no other software.

   ```powershell
   Start-XmipTest -Suite Core.Playground -Cluster C1 -Test RoundTrip -Nodes alpha, beta, gamma `
    -NodeCapability @{ alpha = 'receive'; beta = 'process'; gamma = 'send' } -OnlineNodes alpha
   Start-XmipOperationWeb -Snapshot .local-work/playground/C1-snapshot.toml
   Get-XmipTestStatus
   Get-XmipTestResult | Where-Object -Property State -NE -Value fine
   Stop-XmipTest
   Stop-XmipOperationWeb
   ```

   A roll is one cluster's test, and the cluster is a process the roll spawns
   (ADR-0052, amendment 2026-09-19); two rolls are two clusters side by side.
   Leave the two `Stop-` lines above until later and a second roll stands
   beside the first. One web host serves them both, and the three views say
   which cluster they are on and move between them (ADR-0052, amendment
   2026-09-20):

   ```powershell
   Start-XmipTest -Suite Core.Playground -Cluster orders -Test RoundTrip -Nodes east, mill `
    -NodeCapability @{ east = 'receive'; mill = 'process,send' } -OnlineNodes east
   Get-XmipTestStatus | Start-XmipOperationWeb
   ```

   Nothing of the second roll matches the first but the suite: a cluster
   called `orders`, two nodes called `east` and `mill`, and one node carrying
   two stages because its purpose needs both
   ([ADR-0056](doc/decision/ADR-0056-a-node-declares-what-it-can-do.md)). Xmip
   reads none of those names.

   The prompt follows one cluster and says how many it is not showing —
   `[orders+1 ≡ R:1.2K/s P:240/s S:238/s]`. The letters there are the three
   stages of the message path, which is the one place in Xmip where a letter
   means anything, and each is what that stage is moving per second, not a
   total since the roll began: `R:0/s` says stalled, which a rising total
   never can, and a dash says there has been only one publication so far. T
   and F are counts, on the line only when above zero.
   `xmip-cli --snapshot <path>` names which cluster the executable reads; it
   answers one cluster per invocation and shows totals, because a single
   reading has no interval to take a rate over.

   Every System Process Xmip owns is named `xmip-<what>` and declares its
   name, its location and its purpose, test or runtime (ADR-0053). A
   Playground process says which cluster and which node it is —
   `xmip-playground-C1-roll`, `xmip-playground-C1-cluster`,
   `xmip-playground-C1-node-alpha` — so twenty rows of `Get-Process` read as a
   tree rather than as one name repeated (amendment 2026-09-20).
   `Get-XmipProcess` lists them with what they said, and one line stops
   every one of them, whatever started it:

   ```powershell
   Get-Process -Name xmip-* | Stop-Process -Force
   ```

   `-OnlineNodes alpha` records that `alpha` may assume a route to the
   internet and the others may not (ADR-0045). `alpha` is the node this
   command declared `receive` for, so it is the receiving edge — the node that
   would obtain its server certificate from Let's Encrypt over ACME, which is
   the one online act Xmip has (ADR-0033, ADR-0034). The switch permits;
   nothing in the Playground reaches out.

   The web GUI at <http://127.0.0.1:5087> opens on the Monitor view, the
   board that follows receive, process and send as the cluster moves. Beside
   it are Configuration, the classic tree of the whole cluster, and Topology,
   the cluster's own communication. `C1` is the cluster and `alpha`, `beta`
   and `gamma` its three simulated node processes. Those names are yours and
   mean nothing — the owner, 2026-09-20: *Rn, Pn and Sn are arbitrary node
   names*, and the same of clusters. This walkthrough says `C1` only because
   the `xmip-cli` and PowerShell documents that ship in a developer's clone
   follow `C1-snapshot.toml`; roll under any other name and point them at that
   file, or let `Start-XmipTest` tell the session. Nothing in Xmip reads a
   cluster's name or a node's: what a node does is the capability it was
   started with
   ([ADR-0056](doc/decision/ADR-0056-a-node-declares-what-it-can-do.md)).
   `-NodeCapability @{ alpha = 'receive'; beta = 'process'; gamma = 'send' }`
   states it, or omit `-Nodes` and the level's complement deals the whole
   message path for you. A node given no capability declares none and runs the
   shared-directory tests whole, which `Start-XmipTest` says in words before
   it starts anything. `alpha` may use the internet because you said so; the
   others may not.

Nothing in Xmip starts on its own. You name a cluster and its nodes, you
start them when you want to, and you stop them. Every command that changes state accepts `-WhatIf`.
`Get-Help Start-XmipTest -Full` documents every parameter.

---

## Chief Engineering Officer

Xmip is engineered around one promise: after it accepts responsibility for a
Message, the system can say where that Message went, what acted on it,
whether delivery completed, and why work stopped when it did not.

### Architectural choices that serve that promise

| Engineering concern | Xmip's choice | Consequence |
| --- | --- | --- |
| Correctness under failure | Persist before execution; checkpoint each Journey ([runtime-model.md](doc/architecture/runtime-model.md)). | A restart resumes durable work instead of reconstructing intent from logs. |
| Throughput and predictable resource use | Rust throughout the message path. | Memory safety without a garbage-collected hot path. |
| Extensibility | A versioned C ABI, one trait table per capability, and a host that opens a Module at run time ([ADR-0012](doc/decision/ADR-0012-module-boundary.md), [ADR-0057](doc/decision/ADR-0057-a-vtable-is-a-promise-only-a-loader-is-a-saving.md)). | A Module may be written in any language that can implement the ABI, kept in its own repository, and opened as a shared library the host holds to the trait version the loading capability asked for. |
| Acceptance | A Stream is accepted only when well-formed and, where a Contract is named, conformant ([ADR-0042](doc/decision/ADR-0042-a-contract-holds-well-formedness-always-and-conformance-when-named.md)). | Responsibility transfers to Xmip at one explicit point, and durability follows it. |
| Operational consistency | The `xmip-cli` command line, PowerShell and both GUIs read one shared operator model ([ADR-0014](doc/decision/ADR-0014-operator-surfaces.md), [ADR-0052](doc/decision/ADR-0052-the-operator-surfaces-share-one-model.md)). | A scope, a Status and its evidence mean the same thing on every surface. |
| Safe observation | The runtime publishes snapshots asynchronously; observation never queries the message path ([ADR-0027](doc/decision/ADR-0027-the-operator-boundary.md)). | Monitoring cannot slow or stop what it watches. |
| Deployment flexibility | The same node model on Windows, Linux and macOS; current platforms only ([ADR-0021](doc/decision/ADR-0021-current-platforms-only.md)). | Edge, server, cluster and cloud nodes are one product. |
| Architectural memory | Accepted decision records and executable governance tests. | Tradeoffs survive staff and assistant turnover. |

### Message ownership and failure boundaries

A Stream is not a Message merely because bytes arrived. Xmip accepts only
well-formed content and, where configured, content conforming to its Contract.
Acceptance transfers responsibility to Xmip; durability therefore precedes
execution. Routing creates Journeys; assignment and transformation create new
immutable Message generations.

A failure is persisted with the Message state, the Journey position, its
classification, its evidence and the identities involved. An accepted Message
that no Subscription matched goes to the Dead Message Queue; a failed Journey
stays a failed Journey. The two are not collapsed into one dead-letter queue,
because their recovery actions differ.

### Boundaries and scale

The architecture manifest, [`architecture.toml`](architecture.toml), is the
estate's dependency graph and the only place its repositories are counted.
Foundation defines what Xmip is; Capabilities define what it does; Technology
repositories implement those capabilities; Operations run and govern the
system; Platform repositories provide runtime-wide services. One repository
per module and per technology: a module is mounted at
`module/<provider>/<domain>/<leaf>`, a technology inside its capability. Dependency
rules are stated in the manifest and enforced by a test: foundation never
depends on a technology, a technology may depend on its capability,
operations consume public contracts only
([repository-model.md](doc/architecture/repository-model.md)).

Receive and Send own orchestration, ports and locations. Direction-neutral
Transport Modules move Streams. Message Modules own representation. Contract
Modules own acceptance rules. Logic Modules own method and operation
semantics. A Handler is a runtime role, not a competing repository family.

### Governance and verification

The decision records, indexed by subject, are the memory of the estate. A
change that contradicts one is a new record or an amendment. Rust and
PowerShell style rules are gates in the test suite; length limits are
recommendations whose breach requires prior agreement and a recorded reason.
One command lands a change across every affected repository in dependency
order and refuses when a gate fails.

The Playground ([ADR-0028](doc/decision/ADR-0028-the-xmip-playground.md)) is
an integration test over time: every transport by every contract, round after
round, with injected faults, at four stress levels, with a cluster's nodes as
processes contending over real files and handing work receive to process to
send, publishing the snapshots the monitors read. The estate's suite holds a test for every defect that has reached an
operator's console.

The design record starts at:

- [`doc/architecture/runtime-model.md`](doc/architecture/runtime-model.md)
- [`doc/architecture/module-model.md`](doc/architecture/module-model.md)
- [`doc/architecture/repository-model.md`](doc/architecture/repository-model.md)
- [`doc/architecture/estate-map.md`](doc/architecture/estate-map.md)
- [`doc/architecture/deployment-model.md`](doc/architecture/deployment-model.md)
- [`doc/architecture/observability-model.md`](doc/architecture/observability-model.md)
- [`doc/decision/README.md`](doc/decision/README.md)

### Current maturity

Xmip has no stable release. `main` is the Continuum, the evolving state of the
project. A Linear release is a stabilized, reproducible, versioned line cut
from it; the first has not been cut
([release-model.md](doc/governance/release-model.md)). The runtime, the
operator surfaces and the Playground are operational, and since 2026-09-19
the runtime opens a Module for real: it loads the shared library, resolves
`xmip_create_module_v1`, refuses a descriptor the loading capability's trait
version does not admit, and drives the contract table through it — the same
code for a C Module and a Rust one. Technologies are still linked rather
than loaded, and most technology
repositories are scaffolded and not yet written. The manifest records that
distinction for every repository, and it belongs in every technical
evaluation. [`doc/planning/open-problems.md`](doc/planning/open-problems.md)
lists what is undecided, in order, with options and a recommendation for
each. A visual designer is not built; the Monitor view is the first operator
screen, with the Configuration tree and the Topology beside it.

*Note.* The designs Xmip departs from are named in the decision records where
the departure was decided.
[`doc/planning/market-position.md`](doc/planning/market-position.md) holds
the comparison.

---

## Chief Information Officer

Xmip is for organizations whose integration problem is not simply moving
data, but keeping control and accountability while systems, partners,
regulations and deployment models change.

### The organizational case

- **Control.** Xmip runs on infrastructure you choose. It has no hosted
  control plane and operates in an air-gapped environment. A node reaches out
  only where its configuration permits, and the software reports nothing to
  anyone.
- **Sovereignty.** Data, configuration, audit and operational evidence stay
  within the boundary your organization controls.
- **Continuity.** Accepted Messages are durable and Journeys survive
  restarts. The platform is designed around recovery, not optimistic
  delivery.
- **Accountability.** Audit records responsibility and outcomes; monitoring
  shows the current state. They are separate, so a live dashboard is never
  mistaken for the historical record.
- **Portability.** Windows, Linux and macOS are equal targets. A cloud node
  is an option, not a dependency.
- **Inspectable architecture.** Source and decisions are available for
  security, procurement and engineering review.

### Where Xmip fits

Xmip targets estates that would otherwise evaluate an integration server, an
enterprise service bus or a hosted integration platform, and need an
on-premises or sovereign deployment choice. Existing integration knowledge
stays useful because familiar responsibilities survive, while Xmip removes
the shared-database bottleneck and separates transport, content, contracts
and operation semantics.

### Security and assurance

Three security profiles, `standard`, `enterprise` and `regulated`, set
identity isolation and whether the runtime stops rather than operate
unobserved ([deployment-model.md](doc/architecture/deployment-model.md),
section 4). Identity is verified per protocol against the published
standards; authorization follows it; Receive and Send identities are
configured independently, because Xmip is the server on receive and the
client on send. Certificates are the first mechanism built; they are
provisioned by Let's Encrypt at a public edge and by your own authority
elsewhere. Xmip is developed in Sweden and is source-available, which is
relevant where data sovereignty is regulated. Its AS4 and Peppol transports
are protocol software for the operator of a certified access point, which is
what European e-invoicing runs on; certification itself belongs to the
operator, and no node runs a transport yet (market-position.md, section 8).

### Licensing

Xmip is AGPL-3.0-or-later. There is no commercial license, no dual license
and no contributor agreement that could enable one
([ADR-0023](doc/decision/ADR-0023-licensing-model.md)). The platform cannot
be relicensed or withdrawn. Modules written against the C ABI are your own
work under your own terms. Organizations whose policy excludes AGPL will find
that policy engaged; the record acknowledges this.

### A responsible adoption path

1. **Prove the operational model.** Run the Playground and inspect failure,
   recovery and monitoring behavior.
2. **Select one bounded integration.** Prefer a flow with a known Contract,
   clear ownership and a measurable delivery outcome.
3. **Run beside the incumbent.** Compare acceptance, throughput, evidence and
   recovery without making the pilot a migration event.
4. **Review the security profile.** Involve security, operations and data
   owners before moving responsibility for production Messages.
5. **Adopt a Linear release when one exists.** Until then, treat the
   Continuum as an engineering evaluation, not a supported product.

*Note.* Xmip is designed to succeed the previous generation of integration
servers, whose vendors now offer hosted services only. Its operator
vocabulary is deliberately theirs.
[`doc/planning/market-position.md`](doc/planning/market-position.md) holds
the comparison, including their lifecycles, sovereignty pressure, e-invoicing
and healthcare integration; it is planning evidence, not due diligence.

---

## Operator

Xmip gives an operator one job: keep accepted Messages moving, and know why
they are not moving when work stops. The operating model answers three
questions quickly: what is affected, what is Xmip doing about it, and what
evidence explains the current condition.

### One operational model

Every leaf has a mood: Fine, Paused, Working, Stressed, Exhausted or Done
([ADR-0041](doc/decision/ADR-0041-health-is-a-mood-and-does-not-propagate.md)).
A scope above a leaf is Holding when a leaf beneath it needs attention, and
Holding is never shown alone; it carries the worst affected leaf and that
leaf's evidence. An operator drills from the cluster into nodes, stages,
services and locations without asking the message path to count itself.

Four surfaces read one operator boundary
([ADR-0014](doc/decision/ADR-0014-operator-surfaces.md),
[ADR-0027](doc/decision/ADR-0027-the-operator-boundary.md)) through one
shared library, so they cannot disagree.

| Surface | Best use |
| --- | --- |
| `xmip-cli` | Text for a person; `--json` for one document; `--follow` for JSON Lines as things change, over SSH or a pipe. |
| PowerShell module | The same answers as objects on the pipeline, composing with filtering, remoting and existing administration practice. |
| Web GUI | Serves many operators from one host, each by the role at the keyboard, with drill-down to the leaf. |
| Desktop | The same on one machine. Windows, Linux and macOS. |

Both GUIs show three views: Monitor, the default, the board that follows
receive, process and send as the cluster moves; Configuration, the classic
tree of the whole cluster, held still; and Topology, the cluster's own
communication. From any row the drill-down goes through the configuration
that declared the scope and ends at that configuration
([ADR-0052](doc/decision/ADR-0052-the-operator-surfaces-share-one-model.md),
amendment 2026-09-14).

A role comes from a directory, never from Xmip: the group membership a
remoting session proved, or the account behind an SSH key. An Observer
watches; an Operator also pauses, resumes and configures; a Developer also
opens the specific point's configuration from its scope
([ADR-0009](doc/decision/ADR-0009-security-roles-vs-actor-capabilities.md)).
Observation reads snapshots the runtime publishes and never enters the
message path. Audit is the durable record of actions and outcomes; a live
monitor is not a replacement for it.

### Platforms and installation

Xmip supports current platforms only
([ADR-0021](doc/decision/ADR-0021-current-platforms-only.md)). Linux,
Windows and macOS are equal: the runtime, the `xmip-cli` command line, the
PowerShell module and the monitors run on all three.

| | Windows | Linux | macOS |
| --- | --- | --- | --- |
| PowerShell 7.6.5 or later, Core edition | `winget` | `snap`, `apt`, `dnf`, `zypper`, `pacman` | `brew` |
| Prerequisites | `Install-XmipPrerequisite` reads [`prerequisite.toml`](prerequisite.toml), one package per operating system and package manager | | |
| Desired state | `deploy/dsc/xmip-node.dsc.yaml` | `deploy/ansible/roles` | `deploy/ansible/roles` |
| Remote operation | PowerShell Remoting over WinRM or SSH | SSH | SSH |

`Install-XmipPrerequisite -Role operator` reports what a machine lacks;
`-Install` installs it. The command never elevates: where a package requires
administrative rights it prints the command and stops. A prerequisite below
its floor fails the command.

### Configuration and control

Configuration is TOML on disk; JSON is used only on the wire
([ADR-0031](doc/decision/ADR-0031-configuration-is-toml-json-is-transport.md)).
`xmip-cli validate <file>` checks a node configuration without starting anything.

A node is offline unless its configuration says `online = true`
([ADR-0045](doc/decision/ADR-0045-offline-is-the-default.md)). An online node
may reach the internet for duties that require it, such as certificate
provisioning at a public edge. Online access is a declared choice, never a
side effect of deployment.

The `xmip-cli` command line answers `xmip-cli health <scope>`, `measure`,
`list` and `show` over a scope, and `xmip-cli validate <file>`; the PowerShell
module answers the same as objects. Pause and resume are the two acts the
operator boundary carries, and the only two: the thing that watches must not
be able to stop the thing it watches
([ADR-0027](doc/decision/ADR-0027-the-operator-boundary.md)). They are built
on both — `xmip-cli pause`, `xmip-cli resume`, `Suspend-XmipScope` and
`Resume-XmipScope` with `-WhatIf` — and what stays queued is the role gate in
front of them (ADR-0009). Start, stop and restart of a scope were declined.

A security profile, `standard`, `enterprise` or `regulated`, sets identity
isolation and whether the runtime fails closed
([deployment-model.md](doc/architecture/deployment-model.md), section 4).

### Working an incident

1. Start at the cluster Status and read its evidence.
2. Drill into the worst node, stage and leaf scope.
3. Tell a refused Stream, an unmatched Message and a failed Journey apart;
   each has a different owner and a different recovery path.
4. Read the Audit and the persisted failure state before changing
   configuration.
5. Pause or resume through the operator boundary, then confirm the new
   published state.

An accepted Message that no Subscription matched is in the Dead Message
Queue and can be republished once the Subscription is corrected. A failed
Journey keeps its position and resumes from its checkpoint. A refused Stream
never became a Message and remains the sender's responsibility.

### Rehearsal

The Playground runs Xmip's own tests continuously, at a chosen stress level,
over as many node processes as you name.

```powershell
Start-XmipTest -Suite Core.Playground -Cluster nightly -Test HeavyLoad, LowLatency `
    -Stress Harsh -Nodes east, west, mill, quay -OnlineNodes east `
    -NodeCapability @{ east = 'receive'; west = 'receive'; mill = 'process'; quay = 'send' }
Get-XmipTestStatus
Get-XmipTestResult -Test HeavyLoad -Worst
Stop-XmipTest -Cluster nightly -Test HeavyLoad, LowLatency
```

`Stop-XmipTest` takes the run the way `Start-XmipTest` was told it, by
`-Cluster` and `-Test` together, or every run with neither. A run is one
process, so a test is stopped by stopping the run that drives it; a run that
also drives a test you did not name is refused, saying what else it runs,
and nothing is stopped.

You name the cluster with `-Cluster` and the nodes with `-Nodes`; nothing
names either for you, and Xmip reads nothing in the names you choose. Two
cluster names are two clusters side by side, each with its own web GUI.

Every tier is a process of its own: the test spawns the cluster, the cluster
spawns its nodes, and each declares itself, so `Get-XmipProcess` shows all
three. Omit both switches and you get the most the rig can give: `-Stress` is
`Brutal`, and `-Nodes` is that level's full complement, dealt over receive,
process and send so the message path runs between the node processes; in a
real environment an orchestrator spawns nodes, never Xmip.

Use the Playground to practice diagnosis and recovery, to verify an
operational change, and to show the monitor before Xmip carries
organizational data.

---

## Developer

Xmip is an estate of deliberately small Modules around a stable boundary.
The fastest way to contribute is to learn the nouns first, find the accepted
decision that owns the subject, and change the smallest responsible
repository.

### Setup

Complete the [first run](#first-run), then:

```powershell
git submodule update --init --recursive
git config push.recurseSubmodules check
```

A submodule is a commit, not a branch. [CONTRIBUTING.md](CONTRIBUTING.md)
explains how a Module change lands before the superproject updates its pin.
`git status` at the root ignores dirt inside the submodules
(`ignore = dirty` in `.gitmodules`): walking them took thirty seconds, and a
prompt provider such as posh-git runs that status on every prompt. A moved
pin still shows. `Get-XmipStatus` looks inside every module.

### Build, test, land

The runtime and modules are Rust on the stable channel. The operator surfaces
are .NET 11; the PowerShell module targets `net10.0` because `pwsh` hosts it.

```powershell
Publish-XmipChange -Message 'short precise message'   # alias xgit: every suite, then land
Start-XmipTest -Suite Core.Estate                     # every test/*.Test.ps1
Start-XmipTest -Suite Core.Estate -Test Rust.Style    # test/Rust.Style.Test.ps1 alone
Start-XmipTest -Suite Core.Playground -Cluster scratch -Test RoundTrip  # omit -Nodes: dealt
Start-XmipTest -Suite * -Cluster scratch              # every suite this estate knows
```

Four kinds of test, and `Publish-XmipChange` runs every one a change
touched, in dependency order, modules first, then commits, pushes and
updates the pins in the superproject:

| Suite | Runs | Command |
| --- | --- | --- |
| A module's own | its crate or project | `cargo test` in the module; `dotnet test <path to the *.Test.csproj>`; `Invoke-Pester module/core/operation/powershell/tests` |
| The Playground's own | `module/core/test/playground` | `cargo test` in `module/core/test/playground` |
| The estate's | the style rules, the manifest, the record, the estate module, one Pester file each under `test/` | `Start-XmipTest -Suite Core.Estate` |
| The Playground | Xmip end to end, every transport by every contract, as a cluster you name | `Start-XmipTest -Suite Core.Playground -Cluster <name>`, then `Get-XmipTestStatus`, `Get-XmipTestResult -Worst`, `Stop-XmipTest` |

Before a change lands, `cargo fmt`, `cargo clippy --workspace --all-targets
-- -D warnings` and the suite must pass. Until the first Linear release, work
commits directly to `main`
([release-model.md](doc/governance/release-model.md)).

A suite is named `<Provider>.<Name>`, like every other name in the estate
(ADR-0011, ADR-0059), and `core` is the reserved provider that means Xmip
itself — so Xmip's own two are `Core.Playground` and `Core.Estate`, and that
is what every record, refusal and surface spells. A bare `Playground` is
accepted and resolves to `Core.Playground`, so nothing you have typed stops
working. A third party's suite carries its own provider: `<Provider>.<Name>`.
A third party adds a suite by dropping a declaration in `test/suite` —
`provider`, `name` and the `command` that starts it — with no edit to Xmip's
own source.
Omit `-Test` and the whole suite runs, for every suite and every provider.

`-Test` takes wildcards, as every filter parameter in the module does:
`-Test Round*` is RoundTrip, `-Test *` is every test and says the same as
omitting it, and a pattern that matches nothing is refused by name before
anything starts. Wildcards and not regular expressions, so the dot in
`Rust.Style` is the dot you typed. `Get-XmipTestStatus -Cluster 'night*'`,
`Stop-XmipTest -Cluster 'night*' -Test 'Heavy*'`, `Get-XmipTestResult -Node 'east*'` and
`Get-XmipProcess -Name 'xmip-playground-*'` match the same way. `-Suite`
filters too (the owner, 2026-09-19): `-Suite *` runs every suite this estate
knows, one after another, and says in words which are about to run and which
did not start. A parameter that names what to start — `-Cluster` and `-Nodes`
on `Start-XmipTest` — is exact.

### Layout

```text
architecture.toml     the estate: every repository, named by its position in the tree
prerequisite.toml     what a machine needs, per role and operating system
rust-toolchain.toml   channel = stable
Xmip/                 the estate's PowerShell module
module/               what each provider ships, at module/<provider>/<domain>/<leaf>
test/                 the estate's Pester suite
deploy/               Ansible roles and a DSC configuration for a node
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
| [`architecture/estate-map.md`](doc/architecture/estate-map.md) | every declared repository, and whether it is mounted — generated |
| [`architecture/module-model.md`](doc/architecture/module-model.md) | the module boundary, loading and isolation |
| [`architecture/deployment-model.md`](doc/architecture/deployment-model.md) | nodes, profiles, roles, installation, recovery |
| [`architecture/observability-model.md`](doc/architecture/observability-model.md) | audit, logs, traces, retention, observation |
| [`doc/decision/`](doc/decision) | the decision records, indexed by subject |
| [`governance/rust-style.md`](doc/governance/rust-style.md), [`governance/powershell-style.md`](doc/governance/powershell-style.md) | style rules, enforced by the suite |
| [`development/creating-transports-contracts-and-processes.md`](doc/development/creating-transports-contracts-and-processes.md) | adding a transport, a contract or a process |
| [`doc/planning/open-problems.md`](doc/planning/open-problems.md) | open questions, in order |

A document whose subject is one module lives with that module
([ADR-0020](doc/decision/ADR-0020-documentation-structure.md), clause 3), in
its `doc/` folder: the ABI specification (`module/core/foundation/abi`), identity
per technology (`module/core/capability/authenticate`), adding a transport
(`module/core/capability/transport`), adding a contract
(`module/core/capability/contract`), the node configuration document
(`module/core/platform/configure`), Xmip Process instances
(`module/core/capability/process`), the content selector
(`module/core/capability/promote`), the audit record (`module/core/operation/audit`),
the reports (`module/core/operation/report`) and record identifiers
(`module/core/platform/persist`). `doc/planning/` is working notes and not
authoritative.

### Adding or changing a capability

1. Search [`doc/decision/README.md`](doc/decision/README.md) for the subject.
2. Read the architecture model that owns it and
   [`doc/planning/open-problems.md`](doc/planning/open-problems.md).
3. Do not contradict an accepted decision; propose an amendment or a new
   record.
4. Put shared behavior in the capability that owns it, never in each
   technology ([ADR-0044](doc/decision/ADR-0044-a-technology-shares-through-its-capability.md)).
5. Keep dependencies explicit and within the direction rules of
   `architecture.toml`.
6. Add the test for the behavior or the defect before landing the change.

### The estate module

Every command that changes state accepts `-WhatIf`. Reporting is the default.

| Command | Purpose |
| --- | --- |
| `Install-XmipModule` | Link the module onto `PSModulePath`. |
| `Install-XmipPrerequisite` | Report and install what a machine needs, per role. |
| `Sync-XmipEstate` | Reconcile the estate with `architecture.toml`: create and configure on GitHub, compose the submodule tree. |
| `Sync-XmipRepository` | Local working copies: clone, pull, status, branch, push, distribute. |
| `Get-XmipManifest`, `Test-XmipManifest` | Read and validate `architecture.toml`. |
| `Get-XmipEstateRepository`, `New-XmipEstateMap` | Every declared repository with where it sits and whether it is composed, and the generated [`estate-map.md`](doc/architecture/estate-map.md) over them — a tree of the whole estate with the lines each repository holds; `-Format Html` builds the same map as a page with the dependency graph the build draws. `Uses` and `Declared` on each repository say what its build uses and what the manifest says it uses. |
| `Get-XmipSourceFile` | Every source file the estate holds, with production and test lines counted apart. What the map weighs its tree with and what `test/Rust.Style.Test.ps1` gates file length with, so the two cannot disagree. |
| `Get-XmipStatus` | The whole estate at once: dirty, ahead, behind. |
| `Publish-XmipChange` | Test and land a change, dependency order, modules first. Aliased `xgit` and `xmip-git`. |
| `Publish-XmipPin` | Move the superproject's gitlinks to where the modules now are: how a land ends, and how one that stopped halfway is finished. |
| `Start-XmipTest`, `Get-XmipTestStatus`, `Stop-XmipTest` | A suite of Xmip's tests: `Core.Playground`, `Core.Estate` — a bare name is accepted and resolves to those — or a third party's `<Provider>.<Name>`. `-Suite` takes wildcards. |
| `Start-XmipTestNode`, `Get-XmipTestNode`, `Stop-XmipTestNode` | Simulated node processes, by name. |
| `Get-XmipTestResult`, `Get-XmipHistory` | What a run reports, now and over time. |
| `Start-XmipOperationWeb`, `Get-XmipOperationWeb`, `Stop-XmipOperationWeb` | The web GUI, detached; it opens no browser. One host holds one cluster per `-Snapshot`. |
| `Get-XmipDecisionRecord`, `New-XmipDecisionIndex` | The decision record and its index. |
| `Get-XmipRepositoryRoot`, `Expand-XmipEstate` | The module's own footing: find the estate from any working directory, and flatten `architecture.toml`'s nesting into repositories. |

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

Licensed [AGPL-3.0-or-later](LICENSE).
