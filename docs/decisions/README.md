# What Xmip has decided

Twenty-two decisions, read as one document.

Every decision has a number. The number is an identifier for machines, for
citations in code comments, and for filenames — it is not how anyone
understands anything, so it does not appear in this document until the last
section, which exists only to turn a citation back into a subject.

Read this front to back to know what Xmip has decided. Use the
[concept index](#concept-index) when you have a word and want the decision that
governs it.

Each entry states the decision, not the reasoning behind it — the reasoning is
in the record, one link away.

**Where the rest lives.** These are decisions. The six architecture documents in
[`../architecture/`](../architecture) describe the system as it currently
stands, and [`../terminology.md`](../terminology.md) defines every Xmip word. A
decision says *what was chosen and why*; an architecture document says *what is
true now*.

---

## 1. What Xmip is at runtime

### Runtime flow

Xmip's flow is stream-first, security-aware, transformable, promotable,
auditable and interchange-tracked. Transformation and promotion happen *before*
subscription or orchestration decisions when the incoming Stream requires it,
because orchestration and subscription need metadata and promoted properties to
know what to do.

→ [Runtime flow, in full](ADR-0003-runtime-flow.md)

### Message disposition and the Journey

A Journey is a line, not a tree: a Publication produces one Journey per matched
Subscription, and zero matches means no Journey at all. A Journey exists only
after Validation. Every point of refusal has a defined disposition, so nothing
accepted disappears silently.

Terminal states are `Completed`, `Failed` and `Dismissed` — the last added
2026-08-26 so that an operator's deliberate stop is distinguishable from a
fault.

→ [The Journey model, in full](ADR-0013-journey-model.md) — **still Proposed**

### Everything that communicates is an Actor

A recursive Communication Domain model. An Actor is any entity that can
communicate; a Domain is an Actor that contains other Actors; every Domain
follows the same communication rules. The recursion is the point — a Node, a
Receive Port and a Receive Location obey one set of rules, not three.

→ [The Communication Domain model, in full](ADR-0007-communication-domain-model.md)

### Existing entities gained Actor semantics

Xmip's entities became Actors when they communicate, publish, subscribe, own
work, report status or transfer responsibility. Nothing was renamed or removed
to make this true. A Receive Location is an Actor that receives external input
and reports to its parent Receive Port.

→ [Entities as Actors, in full](ADR-0008-xmip-entities-as-actors.md)

### One Service per node, and it stays out of the message path

The Xmip Service is the master and the only thing the operating system starts.
It reads the node configuration, builds and validates the execution tree, then
supervises the Xmip Host Services. **No Stream, Message or Journey passes
through it.** It loads no Modules and executes no Extensions.

→ [The Service and the Host Services, in full](ADR-0018-service-and-host.md)

### Exclusiveness, which is not locking

A lock protects a critical section and callers block on it. Runtime
exclusiveness decides *which running instance owns a unit of work* — nobody
blocks, a node that doesn't get it goes and finds other work, and it is held by
renewal, so a runtime that stops being live stops being the owner.

Receive Locations, Processes and Send Locations are treated alike. **The
transport declares whether it is exclusive by default, and the default follows
the resource:** a discrete claimable artefact is, a query or queue or connection
is not. Leases live in `xmip-core-persist`, which Xmip already requires — no
Consul, etcd, Redis or ZooKeeper.

→ [Exclusiveness, in full](ADR-0017-exclusiveness.md)

---

## 2. Identity and security

### Identity, Parties and the two directions

A Receive Location declares a **closed set** of identities and mechanisms it
accepts; anything else is refused at authentication and is not attempted
against the others. Authentication precedes authorization. A Send Location
presents its configured identity outward. A Party holds identities in both
directions.

Where transport identity and message identity disagree, the model is DMARC's:
**alignment, not precedence**.

→ [Identity, Parties and direction, in full](ADR-0019-identity-parties-and-direction.md)

### Send-side identity is resolved independently

What Xmip presents outward is resolved without reference to what it
authenticated inbound. A Send Location may carry its own identity; where it has
none, it inherits from its parent Send Port.

→ [Send-side identity inheritance, in full](ADR-0006-send-side-identity-inheritance.md)

### Identity classes, and who may run beside whom

Four classes — `highAssurance`, `federated`, `sharedSecret`, `anonymous` —
derived from *how an identity is proven*, never configured. **Different identity
contexts must not share a host process.** Constrained and unconstrained Kerberos
delegation are distinct contexts even for the same principal. The `regulated`
profile isolates `highAssurance` at the node. A violation blocks startup.

*Identity, Parties and the two directions* settles which identity wins. This
settles which identities may co-reside, which is a different question with a
worse failure mode.

→ [Identity classes and runtime isolation, in full](ADR-0022-identity-classes-and-runtime-isolation.md)

### Security roles are not Actor capabilities

Two separate concepts that look alike and are constantly conflated. A security
role is what a human or Service Identity is permitted to do. An Actor capability
is what a runtime entity is able to do. Neither implies the other.

→ [Security roles versus Actor capabilities, in full](ADR-0009-security-roles-vs-actor-capabilities.md)

---

## 3. Modules and the boundary

### The module boundary is a C ABI, not a Rust crate

The normative boundary is a written specification and a C header. Rust bindings
are a convenience and a module author is never obliged to use them —
conformance is judged against the specification. The interface is a `repr(C)`
table of `extern "C"` function pointers. **`dyn Trait` never crosses the
boundary**, because Rust trait objects have no stable layout and passing one
across a toolchain change is undefined behaviour. Ownership, lifetime and error
representation are specified, not left to convention.

→ [The module boundary, in full](ADR-0012-module-boundary.md)

### Contract, transport and representation stay separate

`receive` and `send` own orchestration. A separate `transport` capability owns
direction-neutral transport contracts, and each transport implementation
declares whether it supports receive, send or both. Content representation is
its own family. **Handler is a runtime module role and never a repository-name
prefix.**

→ [Contract and transport boundaries, in full](ADR-0010-contract-transport-repository-boundaries.md)
— written before the `xmip-core-*` rename, so read the names as
`xmip-core-receive` and so on.

---

## 4. The shape of the estate

### One naming rule for the whole namespace

```text
xmip-<provider>-<module>-<standard>
```

Shortest singular form, a verb where the module does something, the recognised
standard name for a technology. In `architecture.toml` the TOML tree path **is**
the name — dots become hyphens and nothing else happens.

→ [Module and repository naming, in full](ADR-0011-module-naming.md)

### Submodule composition mirrors ownership

Two levels, each owned by the repository that pins it. `Xmip` pins
`modules/transport`; `xmip-core-transport` pins `modules/kafka`. A parent pins
commits, and reconciliation never uses `git submodule update --remote`.

→ [Submodule composition, in full](ADR-0016-submodule-composition.md)

### Repository naming, first attempt

Names are derived from rules rather than chosen. The original scheme was
`xmip-handler-<technology-or-family>`.

⚠ **Replaced in practice by *One naming rule for the whole namespace***, which
retired `handler` as a name segment — but this record still reads `Accepted`.
The status is stale and should be corrected.

→ [The original naming rules, in full](ADR-0001-repository-naming-rules.md)

### The handler universe

Organised handler support by technology, protocol and industry space, across
integration, business, cloud, healthcare, industrial, energy, finance,
logistics, government, database, file, network, messaging and device.

**Superseded by *Contract, transport and representation stay separate*.** Kept
because its reasoning produced the technology lists `architecture.toml` now
carries. Nothing in it is current — do not implement from it.

→ [The handler universe, in full](ADR-0004-handler-universe.md)

---

## 5. Operating Xmip

### The operator surfaces and their language

Rust is the language of the runtime; everything in the message path is Rust. The
operator surfaces — an executable and a web solution — are .NET 11, and both are
**clients of the `xmip` executable**. Nothing outside the runtime calls the ABI:
not PowerShell, not the GUI, not a .NET surface. Anything a surface can do, the
command line can already do.

Observation never sits in the message path and is lossy by design; `report` and
`audit` are the durable records. Remote operation rides existing shell remoting
— PowerShell Remoting over WinRM or SSH, and the CLI over SSH. Xmip defines no
bespoke remote control protocol.

→ [The operator surfaces, in full](ADR-0014-operator-surfaces.md)

### Packaging and distribution

Packaging covers the node; Modules are out of scope. MSI via WiX, published
through winget, on Windows. `.deb` and `.rpm` on Linux. An OCI image every
release. A portable archive for people who want no installer at all. x86-64 and
arm64 on both — **arm64 is not optional**, because the IoT and embedded profiles
require it.

→ [Packaging and distribution, in full](ADR-0015-packaging.md)

### Current platforms only

Xmip tracks the current stable release of every platform it depends on and
carries no compatibility with superseded ones. PowerShell 7.6 Core, .NET 11,
latest stable Rust, Pester 6.

**The version numbers are not the decision** — they will be history soon enough.
The decision is the rule that produced them, which is why `prerequisite.toml`
and `rust-toolchain.toml` express channels rather than pins. A floor states what
would break; it does not freeze anything.

→ [Current platforms only, in full](ADR-0021-current-platforms-only.md)

---

## 6. How the work is done

### One document per subject, no versions in filenames

A subject has exactly one document. If two describe the same subject, one is
wrong and you cannot tell which by looking. Versions belong in git history, not
in filenames. Architecture is six documents.

→ [The documentation structure, in full](ADR-0020-documentation-structure.md)

### Pre-alpha refactor discipline

Code may be moved, split, renamed and reshaped aggressively where that improves
correctness, modularity or alignment with the specification. **When the
implementation conflicts with the specification, the implementation is wrong.**
And where the assistant is unsure, disagrees, drifts from the specification or
suspects it is hallucinating, it must say so before continuing.

→ [Pre-alpha refactor discipline, in full](ADR-0005-pre-alpha-refactor-discipline.md)

### Memory lives in the repository

Xmip's project memory is stored in the repository, never in conversation
history. Every significant decision becomes an artifact. This document exists
because of that rule.

→ [Saved state and way forward, in full](ADR-0002-saved-state-and-way-forward.md)

---

## Concept index

You have a word. This gives you the decision that governs it.

| Concept | Decided by |
| --- | --- |
| ABI, C header, `xmip_module.h` | [The module boundary](ADR-0012-module-boundary.md) |
| ABI, the interface into Xmip | [The operator surfaces](ADR-0014-operator-surfaces.md) |
| Actor | [The Communication Domain model](ADR-0007-communication-domain-model.md), [Entities as Actors](ADR-0008-xmip-entities-as-actors.md) |
| Alignment, misalignment | [Identity, Parties and direction](ADR-0019-identity-parties-and-direction.md) |
| Anonymous, federated, highAssurance, sharedSecret | [Identity classes and runtime isolation](ADR-0022-identity-classes-and-runtime-isolation.md) |
| arm64, embedded, IoT | [Packaging and distribution](ADR-0015-packaging.md) |
| Audit, the durable record | [The operator surfaces](ADR-0014-operator-surfaces.md) |
| Authentication, authorization, and their order | [Identity, Parties and direction](ADR-0019-identity-parties-and-direction.md) |
| Blazor, .NET, the GUI | [The operator surfaces](ADR-0014-operator-surfaces.md) |
| Claim, claimable artefact | [Exclusiveness](ADR-0017-exclusiveness.md) |
| CLI, the `xmip` executable | [The operator surfaces](ADR-0014-operator-surfaces.md) |
| Communication Domain | [The Communication Domain model](ADR-0007-communication-domain-model.md) |
| Delegation, constrained and unconstrained | [Identity classes and runtime isolation](ADR-0022-identity-classes-and-runtime-isolation.md) |
| Dismiss, Dismissed | [The Journey model](ADR-0013-journey-model.md) |
| Disposition | [The Journey model](ADR-0013-journey-model.md) |
| DMQ | [The Journey model](ADR-0013-journey-model.md) |
| Documentation, one document per subject | [The documentation structure](ADR-0020-documentation-structure.md) |
| Exclusiveness, leases, renewal | [Exclusiveness](ADR-0017-exclusiveness.md) |
| Handler, a runtime role and not a name | [Contract and transport boundaries](ADR-0010-contract-transport-repository-boundaries.md), [Module and repository naming](ADR-0011-module-naming.md) |
| Host Service | [The Service and the Host Services](ADR-0018-service-and-host.md) |
| Identity context, co-residency | [Identity classes and runtime isolation](ADR-0022-identity-classes-and-runtime-isolation.md) |
| Journey, Journey states | [The Journey model](ADR-0013-journey-model.md) |
| Kerberos | [Identity, Parties and direction](ADR-0019-identity-parties-and-direction.md), [Identity classes and runtime isolation](ADR-0022-identity-classes-and-runtime-isolation.md) |
| Naming, modules and repositories | [Module and repository naming](ADR-0011-module-naming.md) |
| MSI, winget, deb, rpm, OCI | [Packaging and distribution](ADR-0015-packaging.md) |
| Observation, and why it is lossy | [The operator surfaces](ADR-0014-operator-surfaces.md) |
| Party | [Identity, Parties and direction](ADR-0019-identity-parties-and-direction.md) |
| Pester, PowerShell, .NET, Rust versions | [Current platforms only](ADR-0021-current-platforms-only.md) |
| Promotion, promoted properties | [Runtime flow](ADR-0003-runtime-flow.md) |
| Publication, Subscription matching | [The Journey model](ADR-0013-journey-model.md) |
| Receive Location, Receive Port | [Entities as Actors](ADR-0008-xmip-entities-as-actors.md), [Identity, Parties and direction](ADR-0019-identity-parties-and-direction.md) |
| Refactoring freely, pre-alpha | [Pre-alpha refactor discipline](ADR-0005-pre-alpha-refactor-discipline.md) |
| Regulated, enterprise, standard profiles | [Identity classes and runtime isolation](ADR-0022-identity-classes-and-runtime-isolation.md) |
| Remote operation, WinRM, SSH | [The operator surfaces](ADR-0014-operator-surfaces.md) |
| Security roles | [Security roles versus Actor capabilities](ADR-0009-security-roles-vs-actor-capabilities.md) |
| Send Location, Send Port | [Send-side identity inheritance](ADR-0006-send-side-identity-inheritance.md) |
| Service, the Xmip Service | [The Service and the Host Services](ADR-0018-service-and-host.md) |
| Stream-first | [Runtime flow](ADR-0003-runtime-flow.md) |
| Submodules | [Submodule composition](ADR-0016-submodule-composition.md) |
| Transport, direction-neutral | [Contract and transport boundaries](ADR-0010-contract-transport-repository-boundaries.md) |
| Version floors, channels | [Current platforms only](ADR-0021-current-platforms-only.md) |

Concepts with **no decision recorded yet**, and where they live instead: Event
and Schedule
([`runtime-model.md`](../architecture/runtime-model.md) section 17), the Xmip URI
([`observability-model.md`](../architecture/observability-model.md) section 7),
delivery semantics
([`runtime-model.md`](../architecture/runtime-model.md) section 15), and the node
configuration format
([`open-problems.md`](../planning/open-problems.md) problem 14).

---

## Resolving a citation

Code comments, commit messages and the records themselves cite each other by
number. This turns one back into a subject. It is the only place in this
document where a number is the thing you look at, and it is here so that it is
nowhere else.

| | Subject | |
| --- | --- | --- |
| [0001](ADR-0001-repository-naming-rules.md) | Repository naming, first attempt | ⚠ replaced in practice by 0011 |
| [0002](ADR-0002-saved-state-and-way-forward.md) | Memory lives in the repository | |
| [0003](ADR-0003-runtime-flow.md) | Runtime flow | |
| [0004](ADR-0004-handler-universe.md) | The handler universe | superseded by 0010 |
| [0005](ADR-0005-pre-alpha-refactor-discipline.md) | Pre-alpha refactor discipline | |
| [0006](ADR-0006-send-side-identity-inheritance.md) | Send-side identity inheritance | |
| [0007](ADR-0007-communication-domain-model.md) | The Communication Domain model | |
| [0008](ADR-0008-xmip-entities-as-actors.md) | Entities as Actors | |
| [0009](ADR-0009-security-roles-vs-actor-capabilities.md) | Security roles versus Actor capabilities | |
| [0010](ADR-0010-contract-transport-repository-boundaries.md) | Contract and transport boundaries | |
| [0011](ADR-0011-module-naming.md) | Module and repository naming | |
| [0012](ADR-0012-module-boundary.md) | The module boundary | |
| [0013](ADR-0013-journey-model.md) | Message disposition and the Journey model | **Proposed** |
| [0014](ADR-0014-operator-surfaces.md) | The operator surfaces and their language | |
| [0015](ADR-0015-packaging.md) | Packaging and distribution | |
| [0016](ADR-0016-submodule-composition.md) | Submodule composition | |
| [0017](ADR-0017-exclusiveness.md) | Exclusiveness | |
| [0018](ADR-0018-service-and-host.md) | The Service and the Host Services | |
| [0019](ADR-0019-identity-parties-and-direction.md) | Identity, Parties and the two directions | |
| [0020](ADR-0020-documentation-structure.md) | One document per subject | |
| [0021](ADR-0021-current-platforms-only.md) | Current platforms only | |
| [0022](ADR-0022-identity-classes-and-runtime-isolation.md) | Identity classes and runtime isolation | |

---

## What this document cannot do

**The summaries above are copies, not views.** Markdown has no transclusion —
it is not in CommonMark, GitHub implements none of it, and the proposals have
been left to third parties for a decade. HTML is no better: the mechanism was
HTML Imports and it is a discontinued draft, removed from browsers. So there is
no way to make this document *show* the records rather than restate them.

That means the same fact lives in two places, which ADR-0020 forbids, in the
document that indexes ADR-0020. It is a knowing exception and it should not be
a permanent one.

`tests/Decisions.Tests.ps1` limits the damage. It fails when a decision exists
that this document does not mention, when a link here does not resolve, when a
status here disagrees with the record, and when the concept index claims a word
that the record it points at no longer contains. That last one catches the
likeliest drift — a term renamed while the index goes on advertising it. What
no test can check is whether a summary is still a fair account of the decision.
Only a reader can, so change a record and read what it says here.

**The proper fix, when it is worth the afternoon:** each record grows an
`## In brief` section and declares its own theme and concepts, and a
`New-XmipDecisionIndex` cmdlet generates this file from the twenty-two records.
A test regenerates and fails if the committed copy differs. The index becomes a
build artefact, the records become the single source, and this section is
deleted — the same argument as the firewall report in `observability-model.md`,
which is derived and never authored, for the same reason.
