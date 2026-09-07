# ADR-0027: The operator boundary, and what a measurement is

- Status: Accepted
- Date: 2026-09-03
- Related: ADR-0014 (the operator surfaces), ADR-0012 (the module boundary),
  ADR-0018 (the Service and the Host Services), ADR-0022 (identity classes)
- Amends: ADR-0012 (a second header, and one rename in the first)

## In brief

- Theme: Operating Xmip
- Subject: The operator boundary, and what a measurement is
- Name: The operator boundary
- Order: 4
- Concepts: Operator boundary, `xmip_operate.h`; Xmip URI, scope; Throughput, measurement, window; Health, worst active state

`xmip_module.h` is the boundary things plug **into**. There was never one to
drive Xmip **from outside**, which is why `xmip`, the PowerShell module and the
GUI could only answer questions about themselves: `abi`, `status` and `probe`
all describe the binding, and not one of them talks to a running Xmip.

**`xmip_operate.h` is the second boundary**, beside the first and versioned
apart from it, sharing only the primitives — `XmipStr`, `XmipStatus` and the
reader and writer pair. Above those the two have nothing in common: a Module
implements a table Xmip calls; a surface calls functions Xmip implements.

It carries four things an operator needs. **Health** as
observability-model.md already defines it, green through red, worst state
winning upward, every state drilling to its evidence. **Measurement**, which is
never a bare number: a scope, the thing counted, its unit and the window it
covers, because a Stream at a Receive Location and a Journey in a Process are
not the same quantity and Xmip does not pretend they are. **Reports**, the
historical counterpart. And **configuration** read, validated and reloaded —
never authored, because the node configuration format is still an open question
and a boundary that picks one closes it by accident.

**Scope is one tree, and it is the execution tree** ADR-0018 already builds and
validates at startup. A Party is a filter across that tree rather than a level
in it, because a Party is reachable through many endpoints on many nodes.

**Nothing here asks the hot path.** The runtime publishes snapshots and the
boundary reads them, which is section 6's rule — the thing that watches must
not be able to stop the thing it watches — stated as a property of the boundary
rather than as an aspiration in a document.

## Context

ADR-0014's amendment of 2026-08-26 made `xmip-core-abi` the interface *into*
Xmip — configuration, runtime, observing, eventing, auditing — and not only the
boundary Modules plug into. It recorded the consequence and left it open:

> **The ABI serves two audiences.** Module authors plug *in*; operator surfaces
> drive *from outside*. One header, two consumers, different stability
> expectations — a versioning question ADR-0012 did not have to answer when the
> boundary faced one way.

Nobody filed it, so the register never carried it. Meanwhile `xmip_module.h`
grew to twelve sections and every one of them faces inward: version, primitives,
status, descriptor, streams, host, module handle, vtable, and the transport,
message, path and contract traits. There is no connection to a node, no node
identity, no observation, no measurement, no report.

That is why both operator surfaces offer exactly `abi`, `status` and `probe`.
All three describe the binding. **Neither surface can reach a running Xmip**,
and the eighteen tests added to the PowerShell module on 2026-09-03 test a
binding with nothing behind it.

The requirement is the owner's, stated 2026-09-03: a command line and a
PowerShell module have to control configuration, get stats, and show the health
of the cluster and its nodes — with throughput reported for every kind of
thing, Cluster, Node, Receive, Process and Send.

Almost all of that is already architecture. observability-model.md section 6
defines health and its propagation; section 8 defines the four reports;
deployment-model.md section 8 says desired-state tooling places the TOML and the
TOML stays the source. What none of it has is a boundary.

## Decision

### 1. A second header, sharing primitives and nothing else

`include/xmip_operate.h` in `xmip-core-abi`, beside `xmip_module.h`.

It includes sections 2, 3 and 5 of the module header — `XmipStr`, `XmipStatus`,
and the reader and writer pair — and defines nothing that duplicates them. A
status means the same thing to both audiences or it means nothing to either.

Above the primitives they share no shape, because the direction is opposite. A
Module **implements** a `repr(C)` table that Xmip calls. A surface **calls**
functions Xmip implements. ADR-0012 clause 4 still holds for both: no
`dyn Trait`, no Rust layout, ever.

### 2. It versions independently

`XMIP_OPERATE_VERSION`, separate from `XMIP_ABI_VERSION`.

This is the versioning question ADR-0014's amendment left open, answered the
plain way. A module estate and an operator estate move at different speeds: a
surface gains a command far more often than a trait gains a method, and one
constant for both would force a module recompile for a change no module can
see.

### 3. Scope is the Xmip URI

The addressing form in observability-model.md section 7 becomes normative here,
which also gives it the decision record it never had:

```text
xmip://[userinfo@][host][:port]/path?query#fragment
```

Omitted userinfo means the caller's identity; omitted host means estate-wide.
Every call across this boundary that names a thing names it this way.

### 4. One scope tree, and it is the execution tree

```text
installation → cluster → node → host service → receive location
                                             │ xmip process
                                             └ send location
```

**This corrects observability-model.md, which carried two trees.** Section 6
said observation is navigable "from installation through Clusters, Nodes,
Parties and Endpoints"; section 7 said the hierarchy is
`installation → cluster → node → module → action`. Below the node they are
different trees, in one document, which ADR-0020 exists to prevent.

They were never rivals. Containment is what the Xmip Service already builds and
validates at startup — ADR-0018's execution tree, and real code. Effective
policy resolves down it, most specific winning, exactly as section 7 says.

**A Party is not a level in it.** A Party is reachable through many endpoints on
many nodes, so it is a filter across the tree, and section 6's navigation is a
second axis rather than the same one. Both are true; only one is containment.

### 5. A measurement is never a bare number

What crosses is a scope, the thing counted, its unit and the window:

```text
scope    an Xmip URI
counted  streams | messages | journeys | bytes
unit     count | bytes
window   the interval the value covers, and when it was taken
```

**Because throughput is not one quantity in Xmip's own vocabulary.** A Stream
arrives, becomes a Message, and produces Journeys. At a Receive Location you are
counting Streams and bytes; in an Xmip Process, Journeys; at a Send Location,
Messages and bytes. terminology.md keeps those three words apart on every page,
and a boundary returning "throughput" as one number would conflate exactly what
the estate refuses to conflate.

Cluster and Node figures are **sums over that tree**, not a separate concept and
not a separate call. That is what makes "throughput for every kind of thing"
one mechanism rather than five.

### 6. The boundary reads snapshots and never counts on demand

The runtime publishes measurements asynchronously; this boundary reads what was
published. There is no call that makes execution wait for a number.

observability-model.md section 6 states the rule — *the thing that watches must
not be able to stop the thing it watches* — and section 5 says the same of
audit. Stated in a document it is an aspiration. Stated as a property of the
boundary it is a thing a reviewer can check, and a synchronous count becomes a
change somebody has to argue for rather than one that arrives by convenience.

Every measurement therefore carries when it was taken. A reader that cannot see
staleness will eventually mistake a stalled publisher for an idle estate.

### 7. Health is surfaced, not redefined

Green, yellow, red; worst active state propagating upward; every state drilling
down to its evidence. observability-model.md section 6 decided it and this
record does not reopen it — it gives it a C surface over the tree in clause 4.

### 8. Cluster health is aggregated by the surface

A node answers for itself. A surface asking about a cluster asks each node.

**There is no inter-node protocol.** Open problem 19 records it, ADR-0024
dissolved the lease that would have needed one, and this record does not
introduce one — a control-plane protocol is precisely what ADR-0014 says Xmip
does not define. Remote operation rides PowerShell Remoting over WinRM or SSH,
and the CLI over SSH, as already decided.

This is better than aggregating server-side and not merely cheaper. **A surface
that asks each node itself can tell "unreachable" from "reports itself
healthy".** A node aggregating for its cluster cannot: it has one answer for a
peer that is down and a peer that is lying. Unreachable is health information,
and the design that loses it is the worse one.

### 9. Configuration is read, validated and reloaded — never authored

Three operations: return the effective configuration, validate a proposed
document without applying it, and reload from what is on disk.

**Writing TOML through this boundary is refused**, and not on taste. The node
configuration format is open problem 14 with three competing shapes and no
resolution order between them. A boundary that accepts a configuration document
has chosen one, and a question closed by an implementation detail is a question
nobody decided. deployment-model.md section 8 already says desired-state tooling
places the configuration and the TOML remains the source; this agrees with it.

Validation is the half worth having now: an operator finding out at startup that
a node TOML is wrong is the failure this removes.

### 10. `XmipNode` is renamed to `XmipValue`

In `xmip_module.h` sections 10 and 11: `XmipNode` becomes `XmipValue` and
`XmipNodeKind` becomes `XmipValueKind`.

It is a node in a parsed representation — null, bool, number, string, binary,
sequence, map — and an operator boundary needs a handle on an Xmip **Node**, the
machine running the Xmip Service. terminology.md: one term for one concept, in
code, configuration, documentation and diagnostics.

Renamed now, while one crate and two surfaces consume it and ADR-0005 still
permits reshaping freely. After the operator boundary ships, the collision is in
two normative headers and every module author has read both.

## Amendment, 2026-09-05: the lifecycle exports, and who authors

Clause 9 said configuration is read, validated and reloaded — never authored —
and left where authoring happens implicit. The desktop editor made it concrete
(ADR-0014: the desktop host configures, the web host only watches, DSC deploys
at scale), and two runtime exports carry it:

- `xmip_start_v1(path)` reads a saved node configuration, validates it, and
  publishes what it planned as health. It takes a filesystem path — a saved
  file — because starting a node runs what is on disk.
- `xmip_validate_v1(configuration, …)` takes the configuration **text** the
  editor is holding, validates it, and publishes nothing. This is clause 9's
  "validate a proposed document without applying it": the editor's Validate
  button, checking a document before it is saved, against the same runtime that
  would start it. The report crosses as UTF-8, one problem per line.

Both are separate exported symbols, not entries in the `XmipOperate` table an
observer holds — an observer watches, a configurer acts, and the table stays
the watcher's. Authoring itself is still not on the boundary: the editor writes
the TOML file directly, and validation is the only configuration act the
runtime performs for it. Header section 6.

## Amendment, 2026-09-05: three states, no fourth

`XMIP_HEALTH_UNREACHABLE` is removed from `xmip_operate.h`. The owner's call:
common terminology, Green, Yellow and Red. A node that does not answer is
**Red**, with "no answer" as its evidence — a surface aggregating a cluster
says that about the node it could not reach, and an operator reads it the way
they read every other red.

Clause 8's reasoning stands unchanged: the surface is still the only thing
that can tell a node that did not answer from one that claims to be well. What
changed is the word it uses for the first, not the fact that it knows.

## Consequences

- `xmip-core-abi` gains `include/xmip_operate.h`, the Rust side of it, and a
  second version constant. Its specification document gains the second audience.
- `xmip-core-observe` publishes the snapshots clause 6 reads. Nothing about the
  message path changes; the publishing is the asynchronous path it already has.
- `xmip-core-cli` and `xmip-core-powershell` gain commands that reach a running
  Xmip for the first time. Their present three describe the binding and stay.
- observability-model.md sections 6 and 7 are corrected to one tree with Party
  as a filter. That is a documentation change this record makes rather than
  leaves to be discovered.
- The Xmip URI stops being a concept with no record. The ADR index listed it
  under *no decision recorded yet*; that entry goes.
- **The identity question ADR-0014 raised is not settled here and blocks
  shipping.** A surface holding runtime state in-process is a host process, and
  ADR-0022 clause 3 says different identity contexts must not share one. This
  record adds a second reason to settle it and settles nothing.
- Native libraries per platform and architecture, which ADR-0015's packaging
  does not yet cover, now apply to a second header as well.
- `Test-XmipModule` still cannot verify a .NET module, so every change to either
  surface lands under `-All`, unverified. That gate has to grow before this
  boundary carries weight.

## Alternatives considered

**One header for both audiences.** Rejected. It forces one version constant on
two populations that move at different speeds, and it puts the inward and
outward halves of the boundary in one file where a reader cannot tell which
direction a declaration faces.

**Aggregating cluster health on a node.** Rejected — clause 8. It needs an
inter-node protocol that does not exist, and it destroys the distinction between
a node that is unreachable and one that claims to be well.

**Throughput as a single counter per scope.** Rejected — clause 5. It reads as
the simpler design and it is simpler only because it has thrown away which
quantity it counted.

**Counting on demand at the boundary.** Rejected — clause 6. It is the obvious
implementation, it gives an exact answer, and it makes the observer able to
stall the observed. Snapshot staleness is the price and it is the right one.

**Writing configuration through the boundary.** Deferred, not rejected — clause
9. It becomes possible the day open problem 14 is decided, and not before.

## Provenance

The requirement is the owner's, given 2026-09-03: control configuration, get
stats, and show the health of cluster and nodes, with throughput reported for
Cluster, Node, Receive, Process and Send. Clause 5 exists because of the last
half of that sentence.

Clauses 1 to 10 are the assistant's drafting of it, on the owner's instruction
to settle the scope-hierarchy contradiction in this record rather than in a
separate one.

The reasoning in clause 8 about unreachable being health information is the
assistant's and is the clause most worth arguing with: it decides that the
estate has no cluster-wide view except the one a surface assembles, and an
operator who wants a single pane of glass will feel that before anyone else
does.
