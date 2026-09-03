# Xmip repository model

Why the estate is shaped the way it is.

`architecture.toml` is the answer to **what** the estate contains. It is
generated from, and reconciled against, the live repositories, and any document
that lists repositories is a second source of truth that will be wrong within a
week. This document holds only what the manifest cannot: the reasoning.

It replaces five documents written before `architecture.toml` existed —
`docs/repository-model.md`, `docs/crate-boundaries.md`,
`docs/architecture/repository-architecture.md`,
`docs/architecture/repository-structure.md` and
`docs/architecture/repository-and-crate-plan.md` — together with sections 9 to
15 of the architecture specification. All five used pre-ADR-0011 names
(`xmip-abi`, `xmip-service`, `xmip-host`), a submodule layout ADR-0016
replaced, and a `-Apply` mode that no longer exists. Their history is in git.

## 1. Classification

Five architectural domains. The domain **explains** a repository and does not
**name** it — `xmip-core-transport-ftp`, never `xmip-technology-transport-ftp`,
per ADR-0011.

It does place it on disk, and that is not a contradiction. The name is one
thing, the navigable tree is another: `Sync-XmipEstate -Compose` mounts a module
at `modules/<domain>/<leaf>`, so `xmip-core-journey` appears at
`modules/foundation/journey`. Section 7 has the shape.

**A leaf is not unique across the estate, and does not need to be.** The estate
declares `file` four times — under transport, audit, retain and archive — and
`sql` and `party` four times each. They do not collide because **a depth-three
module mounts inside its parent capability's repository, not inside Xmip**:

```text
xmip-core-transport-file  ->  modules/file   a submodule of xmip-core-transport
xmip-core-audit-file      ->  modules/file   a submodule of xmip-core-audit
```

Two paths in two repositories. The leaf namespace is per-parent, so it is the
parent that makes it unique, and a parent has no two children with one name.

That property held across 334 declared repositories before anything enforced it,
and it is invisible from the tree — which is why it was reported as a bug by
someone reading the tree, on 2026-08-29. `Sync-XmipEstate.Tests.ps1` now asserts
that no two repositories resolve to one mount, so the next name that would break
it fails a test rather than a clone.

That layout is for human navigation. Cargo dependencies define the technical
graph, and **no runtime behaviour reads a folder name**. Two tests do —
`Rust.Style.Tests.ps1` takes a file's crate from its path, and the mount test
above — because both are about names and have nothing else to read. This
paragraph previously said nothing read a folder name at all, which stopped being
true the moment the first of those was written.

*Corrected 2026-08-26. This paragraph read "it does not place it on disk", which
contradicted section 14 of `Xmip-Repository-Creation-Blueprint.md` — the
owner's own layout, grouped by domain. The scoping error was mine: ADR-0011 is
about names.*

| Domain | What it holds | Examples |
| --- | --- | --- |
| **Foundation** | things Xmip *is* | `xmip-core`, `xmip-core-stream`, `xmip-core-message`, `xmip-core-context`, `xmip-core-journey`, `xmip-core-node`, `xmip-core-cluster`, `xmip-core-party`, `xmip-core-event` |
| **Capabilities** | things Xmip *does* | `xmip-core-receive`, `xmip-core-send`, `xmip-core-transport`, `xmip-core-logic`, `xmip-core-prepare`, `xmip-core-identify`, `xmip-core-authenticate`, `xmip-core-authorize`, `xmip-core-contract`, `xmip-core-path`, `xmip-core-assign`, `xmip-core-transform`, `xmip-core-route`, `xmip-core-process` |
| **Technology** | how a capability is implemented | `xmip-core-transport-ftp`, `xmip-core-path-xpath` |
| **Operations** | running and governing Xmip | audit, observe, report, archive, CLI, PowerShell, GUI |
| **Platform** | platform-wide runtime services | `xmip-core-abi`, `xmip-core-runtime`, `xmip-core-configure`, `xmip-core-persist`, `xmip-core-resilience` |

**The test between Capabilities and Operations is the message path.** If a
Journey waits for it, it is a Capability. `xmip-core-retain` moved on
2026-08-26 for that reason: `disposition.rs` calls it at a gate — *"Stream, by
xmip-core-retain"* when Message creation is refused, *"Message, by
xmip-core-retain"* when validation fails — so nothing proceeds until retention
has taken it.

`audit`, `observe` and `report` stay in Operations because ADR-0014 clause 4
says observation never sits in the message path. `archive` stays too: it moves
*already-retained* data on a schedule, and no Journey waits for it.

`retain` had been classified by the company it kept rather than by what it does,
and its `xmip-core-event` dependency was the tell — eventing is for the
asynchronous family it was sitting with, not for something called synchronously
at a gate.

Every Technology repository is a direct child of exactly one Capability
repository. That is what makes the name computable from the tree, and the tree
computable from the name.

Two corrections against earlier drafts. **Service and Host are not separate
platform repositories** — ADR-0018 folded both into `xmip-core-runtime`, which
already owns `ExecutionTree`, `HostServicePlan` and `HostBitness`; ten
kilobytes that always change together do not need three repositories, three CI
pipelines and three submodule mounts. **Tracking is not an Operations
repository** — it is Audit under BizTalk vocabulary, and ADR-0014 names four
observation capabilities where a fifth would contradict it.

## 2. Naming

ADR-0011 governs. Shortest singular form, a verb where the module does
something, the recognised standard name for a technology, normalised to
lowercase and hyphenated. No file extensions, no informal abbreviations where a
standard name exists.

The path in `architecture.toml` **is** the name. Dots become hyphens and
nothing else happens:

```toml
[xmip.core.transport.ftp]   ->   xmip-core-transport-ftp
[xmip.core.path.xpath]      ->   xmip-core-path-xpath
```

`handler` is not a repository-name segment. It remains correct as the name of
the runtime role — a Module declares Handlers — and the repository that ships
the FTP Handler is `xmip-core-transport-ftp`. These two rules are constantly
misread as if they were one rule contradicting itself.

### The grammar of a name

The whole namespace as one tree — the grammar, not the inventory. Folded in
from `docs/planning/naming-hierarchy.md` on 2026-08-30, because a grammar is
this document's subject and not a plan.

```text
xmip
│
├── Xmip                                   the platform itself — outside the pattern
├── .github                                organisation defaults — outside the pattern
│
├── xmip-<single token>                    PLATFORM LEVEL
│   └── xmip-core                          foundation contracts, identifiers, shared types
│                                          no provider, implements nothing
│
├── xmip-template-<language>               scaffolding, one per language a module
│                                          can be written in — rust, dotnet
│
└── xmip-<provider>-<module>[-<standard>]  THE MODULE NAMESPACE
    │
    ├── provider = core ─────────────────  Xmip ships, hosts and supports it
    │   │
    │   ├── <module>                       xmip-core-path            the module itself
    │   │
    │   └── <module>-<standard>            xmip-core-path-xpath      Xmip's implementation
    │
    └── provider = anyone else ──────────  their licence, their support, no approval needed
        │
        ├── surface module                 xmip-acme-abi
        │   (abi, cli, powershell)         xmip-acme-cli
        │                                  nothing external to name — stops here
        │
        └── standard-keyed module          xmip-saxon-transform-xslt
            (everything else)              xmip-bosch-transport-can-bus
                                           standard is REQUIRED
```

Two things the tree states that prose keeps losing. A provider's surface
modules stop at the module because there is no external standard to name —
ADR-0012 clause 11. Everyone else's modules *must* carry the standard, because
`xmip-acme-transform` claims a capability while `xmip-acme-transform-xslt`
claims an implementation of something nameable, and only the second can be
held to anything.

*The planning file drew `xmip-template` as a single platform-level repository;
that was true until 2026-08-27, when it became one template per language.*

## 3. Maturity

Repository existence is independent of implementation maturity:

```text
reserved  scaffolded  implemented  verified  supported  deprecated  retired
```

The complete taxonomy is declared from the beginning. Maturity describes
implementation and support state, not whether the repository belongs in the
architecture. This is why 292 repositories are named and 43 exist: the manifest
is the design, and creation follows need.

## 4. Dependency rules

The graph must be acyclic. Beyond that:

- Foundation must not depend on Technology.
- A Capability must not depend on its own Technology children.
- A Technology repository may depend on its parent Capability.
- Technology sibling dependencies require explicit architectural
  justification, and must be declared in the manifest. HTTP on TCP and SOAP on
  HTTP are real and are declared; they are not inferred.
- Operations consume public contracts and events, never implementation
  internals.
- Platform services must not depend on specific technology implementations.

The technology tree is a dependency graph, not a directory hierarchy. Transport,
content and Contract stay independent and are composed by configuration:

```text
HTTP  depends on TCP
MLLP  depends on TCP
SOAP  request/response logic uses HTTP
FHIR  instances may travel over HTTP, FILE or any other transport
JSON  instances may travel over HTTP, FILE, FTP, MQ or any other transport
```

Credential and identity presentation is security functionality, not a transport
technology. That distinction is why `xmip-core-authenticate-kerberos` is not
`xmip-core-transport-kerberos`.

## 5. Boundaries between the capabilities that overlap

Five capabilities look similar from a distance and are constantly confused:

- `xmip-core-receive` owns Receive Ports, Receive Locations and inbound
  orchestration.
- `xmip-core-send` owns Send Ports, Send Groups, Send Locations and outbound
  orchestration.
- `xmip-core-transport` owns direction-neutral transport contracts, per
  ADR-0010. `xmip-core-transport-<technology>` implements one technology and
  declares whether it can receive, send or both.
- `xmip-core-message-<representation>` implements serialisation,
  deserialisation and materialisation.
- `xmip-core-contract-<technology>` implements Contract implication or
  evaluation.
- `xmip-core-path-<language>` implements an addressing language.
- `xmip-core-logic-<technology>` implements method and operation semantics:
  SOAP, HTTP API, gRPC.

`xmip-core-contract` does not own representation parsing, serialisation or Path
execution. Representation implementations materialise or serialise content.
Path implementations address materialised content. Contract implementations
evaluate the applicable Stream, Message or materialised structure without
absorbing either of the other two.

### Split on a base protocol, not on a resemblance

A repository is a protocol. **Depend on another protocol only where that other
protocol independently exists and more than one thing builds on it.**

TCP qualifies: HTTP, FTP, MLLP, AMQP and SMTP all sit on it, and it was
specified, implemented and standardised without reference to any of them. So do
UDP, HTTP and CAN bus. Those dependencies are declared, and they are real.

What does not qualify is a layer extracted because two protocols resemble each
other. Modbus RTU and Modbus TCP share function codes — but there is no
standalone Modbus application layer that anyone specifies or implements on its
own, and nothing outside Modbus would ever consume one. The same is true of
DICOM's DIMSE, of BACnet's services, and of most industrial protocols, which
are internally layered without any of those layers being reusable.

**Extracting a shared layer that only one family consumes is code reuse wearing
architecture's clothes.** It buys a saving for exactly one consumer and pays a
repository, a release cadence, a version-negotiation surface and a boundary to
maintain. ADR-0012 rejected per-module ABIs on the same arithmetic.

The consequence when two things genuinely diverge: they become **sibling
protocols, not one protocol plus an extracted core.** If DICOMweb is wanted, it
is `xmip-core-transport-dicomweb` depending on `xmip-core-transport-http` — a
separate protocol that happens to speak HTTP, which is what it actually is. If
Modbus RTU and Modbus TCP ever need separating, they separate into two
protocols, neither of them a base for the other.

`xmip-core-logic-*` is not a counterexample. A Logic repository exists where the
operation model is genuinely portable across wires that were not designed for
it — HTTP APIs over HTTP/1.1, /2 and /3; Matter over Thread, Wi-Fi or Ethernet.
That is a different situation from one protocol being tidy inside itself.

Recorded 2026-08-26. The assistant proposed splitting DICOM, Modbus and BACnet
into transport and logic pairs on the test *"the same operations appear over
more than one wire"*. The owner rejected it: that test asks whether reuse is
possible, not whether a base protocol exists, and the two are not the same
question.

### What a Stream carries does not decide which capability moves it

A transport moves Streams. **The subject matter of those Streams is a message
and contract concern, never a transport one.**

`xmip-core-transport-modbus` carries device register values.
`xmip-core-transport-dhcp` carries address leases.
`xmip-core-transport-mdns` carries service announcements. None of them carries
an invoice, and all three are transports, because moving the bytes is the same
job regardless of what the bytes mean.

This is worth stating because the wrong instinct is strong and sounds
principled: *"nobody receives a business message over DHCP, so DHCP is not a
transport."* The premise smuggles in that a Message must be a business
document. It need not. On an industrial edge node, *a new device appeared with
this vendor class* is the event the estate exists to react to — and it arrives
as a Stream over a transport, like everything else.

The test is mechanical: **does it move bytes between Xmip and an endpoint?**
If yes, it is a transport, and what those bytes mean is decided further along
by the representation, Contract and Path technologies.

Recorded 2026-08-26 after the assistant argued the wrong way on it, and the
owner overruled. The reasoning is here rather than in the commit message
because the same instinct will recur every time a protocol arrives whose
payload is not obviously business data.

There is a real distinction nearby, and it is not this one: a runtime that
*uses* a discovery protocol to locate an endpoint and bind a Receive Location
to it is doing self-configuration, not transport. Same protocol, different
feature. See `docs/planning/open-problems.md`.

## 5b. What a technology repository implements

A technology repository implements somebody else's specification, and the
manifest says which:

```toml
[xmip.core.transport.tcp]
specification = "IETF RFC 9293"

[xmip.core.transport.http]
dependency = ["xmip-core-transport-tcp"]
specification = "IETF RFC 9110, with the applicable HTTP/1.1, HTTP/2 and HTTP/3 documents"
```

It sits beside `dependency` because it answers the neighbouring question. The
dependency says HTTP is built on TCP; the specification says which HTTP.
Together they are what somebody picking up an unimplemented repository needs
before they write a line — and the alternative is that each implementer decides
privately which document they are working from, which is how two transports end
up disagreeing about framing.

**Compliance is claimed only after conformance evidence exists.** Naming a
specification here is a statement of intent, not a claim of conformance. The
distinction matters because integration buyers read compliance claims as
warranties, and a half-implemented RFC that says it implements the RFC is worse
than one that says nothing.

Most repositories have no `specification`, and that is correct: a capability
implements an Xmip contract rather than an external standard, and vendor
technologies have documentation rather than specifications. The field is for
where a normative external document exists.

Recovered from `handler-specification-map.md` during the ADR-0020
consolidation, 2026-08-26. It was the only record of which RFC each transport
implements, and it had been classified for deletion.

## 6. Crates

Every Rust repository has one primary crate whose Cargo package name matches
the repository name. The first-party provider segment remains part of that
package identity:

```text
xmip-core-message     repository and Cargo package
xmip-core-transport   repository and Cargo package
```

A dependent crate may use a shorter local dependency key without changing the
package identity:

```toml
xmip-message = { package = "xmip-core-message", git = "..." }
```

That keeps imports readable while repository, package, diagnostics and release
metadata still name the same owned component. The manifest's
`primaryCrateMatchesRepository = true` rule is therefore literal; there is no
first-party naming exception.

Repositories whose declared `primaryLanguage` is not Rust do not invent a
Cargo package. ADR-0014 clause 14 governs those surfaces:
`xmip-core-cli` and `xmip-core-gui` are .NET 11, and
`xmip-core-powershell` is PowerShell.

Platform foundation stays together while the architecture is settling.
Loadable modules can separate later precisely because they depend on published
contracts rather than on internal implementation — that is what ADR-0012's C
ABI buys, and the reason to pay for it.

## 7. Composition

ADR-0016 governs, and `Sync-XmipEstate -Compose` performs it. **The filesystem
hierarchy and the submodules are one thing** — wiring the submodules is what
produces the tree, and `git clone --recursive` reproduces it for everyone else.

Two levels. Depth two mounts under `Xmip`, grouped by architectural domain,
which is the layout in section 14 of `Xmip-Repository-Creation-Blueprint.md`:

```text
Xmip/
├── modules/
│   ├── foundation/
│   │   ├── core   journey   message   stream   party   event   abi
│   ├── capabilities/
│   │   ├── transport   route   process   transform   contract   path
│   ├── operations/
│   │   ├── audit   observe   report   retain   archive   cli   powershell
│   └── platform/
│       └── runtime   configure   persist   resilience
└── template/
    ├── rust     what a Rust module repository is generated from
    └── dotnet   what a .NET one is
```

**The templates are submodules of the estate, not neighbours of it.** They sat
beside `Xmip/` until 2026-08-29, which meant cloning the estate did not get
them, nothing measured them, and a rename could break repository creation
without anything noticing — which it did. Under `template/` they are surveyed by
`Get-XmipStatus`, landed by `Publish-XmipChange` and measured by the Rust style
rule like anything else.

They are **not** under `modules/`: a module is something Xmip loads at runtime,
and a template is never loaded by anything. `crate.template` in
`architecture.toml` names them by `owner/name` for the GitHub API; the path is
`template/<language>`.

Depth three mounts inside its own parent capability, ungrouped, because at that
level the parent *is* the grouping:

```text
xmip-core-path/
└── modules/
    ├── xpath/
    ├── json-pointer/
    └── index/
```

The mount name is the last segment of the repository name and the owner is the
name minus that segment, so both are computed from the manifest rather than
configured. Grouping exists at depth two only: `capabilities/` has fifteen
entries and would be a wall without it, while `xmip-core-transport` has one kind
of child and needs none.

A fresh `git clone` of `Xmip` gets source and manifest and no submodules.
`git submodule update --init` is an explicit act and `--recursive` reaches the
implementations. Parent repositories pin submodule commits; reconciliation must
never use uncontrolled `git submodule update --remote`.

Level two waits. Zero of the 249 implementation repositories exist, so today's
composition pins the 42 modules only. A technology earns its own repository
when it has a second consumer or a separate release cadence — until then it is
a module inside its parent, which is how Camel treats `camel-file` inside
`camel-components` rather than as its own artifact.

Earlier drafts proposed a flat integration checkout —
`submodules/platform/`, `handlers/`, `content/`, `stores/`. That is rejected:
it puts the root in charge of what a module contains, which is exactly the
coupling the tree removes, and it makes a clone of any single module
repository useless on its own.

## 8. Reconciliation

`Sync-XmipEstate` reconciles the estate against `architecture.toml`, on GitHub
and on disk:

```powershell
Sync-XmipEstate -Create      # remote: create what the manifest names and GitHub lacks
Sync-XmipEstate -Configure   # remote: description, topics, features
Sync-XmipEstate -Compose     # local: wire the submodule hierarchy of section 7
```

**A reserved repository that does not exist is not drift.** It is section 3
working — the manifest is the design and creation follows need. The report
counts only what is missing *and* declared beyond `reserved`, and summarises the
rest in one line. Reporting all of them printed 293 warnings to surface one
action, which is a report nobody reads.

**Unexpected repositories are reported, and are not automatically wrong.** A
repository in the `xmip-` namespace that the manifest does not declare is
usually one of two things: something created deliberately and not yet declared,
or something left behind under a name the manifest has since changed. The report
names it and stops — deciding which it is needs a person, and the two responses
are opposites.

The owner's repositories outside the `xmip-` namespace are not the estate's
business and are never reported.

*Until 2026-08-26 this number was the literal `@()`. Nothing could have been
reported, because the estate only ever asked GitHub about names the manifest
already knew — so a repository under a superseded name was invisible by
construction, and every run said "0 unexpected" truthfully and uselessly.*

An operation switch means do it. `-WhatIf` means do not. There is no `-Apply`
and no plan mode — git does not work that way and neither should this. With no
operation switch at all it reports and stops, which is the safe default and
needs no ceremony to reach.

It reports missing repositories, unexpected repositories, deprecated and
retired repositories, active references to deprecated items, repository setting
drift, and missing or unexpected submodules.

**It never deletes a repository.** Nothing in the tooling does.

`Sync-XmipRepository` owns the local working copies: clone, pull, status, branch, push,
and `-Distribute`, which executes `docs/planning/allocation.toml` to put every
document and source file in the repository that owns it.

## 9. Source layout inside a repository

Organise by **deployable capability**, never by technical layer. The same
shape repeats at every level — repository, module, feature — so a developer
opening any part of Xmip recognises what they are looking at.

```text
feature/
├── contracts/        the public shape: traits, types, the capability surface
├── runtime/          behaviour
├── configuration/    how it is configured and bound
├── preservation/     what it persists and how it is recovered
├── observability/    audit, logs, traces, metrics
└── tests/
```

**Use only what the feature needs.** A small feature is `contracts/`,
`runtime/`, `tests/` and nothing else; an empty `preservation/` directory is
noise pretending to be structure.

Do not organise around `controllers`, `services`, `repositories`, `models`,
`utils` or `helpers` unless one of those genuinely names a capability. Those
names describe how a framework thinks, not what Xmip does, and a `utils`
directory is where cohesion goes to die.

The convention is language-independent. A `xmip-core-powershell` module and a
Rust crate hold the same shape for the same reason.

The outcome to aim at: opening any feature answers, without asking anyone,
what capability it provides and where its contracts, behaviour, persistence,
observability and tests live.

## 10. Sequence

One component at a time, and the order is not arbitrary:

1. Stabilise the public purpose and contract of the component.
2. Create its repository with an initial commit.
3. Move or rebuild the component there.
4. Build and test it independently.
5. Mount it in `Xmip` as a submodule.

`xmip-core` goes first, because every other repository depends on its shared
domain contracts, and a contract that changes after its dependants exist is
paid for by all of them.
