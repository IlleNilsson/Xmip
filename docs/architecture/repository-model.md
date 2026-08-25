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

Five architectural domains. The domain is metadata: it explains a repository,
it does not place it on disk.

| Domain | What it holds | Examples |
| --- | --- | --- |
| **Foundation** | things Xmip *is* | `xmip-core`, `xmip-core-stream`, `xmip-core-message`, `xmip-core-context`, `xmip-core-journey`, `xmip-core-node`, `xmip-core-cluster`, `xmip-core-party`, `xmip-core-event` |
| **Capabilities** | things Xmip *does* | `xmip-core-receive`, `xmip-core-send`, `xmip-core-transport`, `xmip-core-logic`, `xmip-core-prepare`, `xmip-core-identify`, `xmip-core-authenticate`, `xmip-core-authorize`, `xmip-core-contract`, `xmip-core-path`, `xmip-core-assign`, `xmip-core-transform`, `xmip-core-route`, `xmip-core-process` |
| **Technology** | how a capability is implemented | `xmip-core-transport-ftp`, `xmip-core-path-xpath` |
| **Operations** | running and governing Xmip | audit, observe, report, retain, archive, CLI, PowerShell, GUI |
| **Platform** | platform-wide runtime services | `xmip-core-abi`, `xmip-core-runtime`, `xmip-core-configure`, `xmip-core-persist`, `xmip-core-resilience`, `xmip-core-exclusiveness` |

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

## 6. Crates

Every repository has one primary Rust crate whose name matches the repository
name, unless an accepted architecture decision defines an exception. ADR-0014
clause 14 defines the exceptions that exist: a module carrying its own language
is not a Rust crate, which is why `xmip-core-powershell` and `xmip-core-gui`
declare `primaryLanguage` and do not pretend otherwise.

Platform foundation stays together while the architecture is settling.
Loadable modules can separate later precisely because they depend on published
contracts rather than on internal implementation — that is what ADR-0012's C
ABI buys, and the reason to pay for it.

## 7. Composition

ADR-0016 governs. The submodule hierarchy mirrors capability ownership, so a
repository owns what it contains:

```text
xmip-core-path/
└── modules/
    ├── xpath/
    ├── json-pointer/
    └── index/
```

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

`Sync-XmipEstate` reconciles the live estate against `architecture.toml`. It is
remote only: nothing is cloned and nothing is built.

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
