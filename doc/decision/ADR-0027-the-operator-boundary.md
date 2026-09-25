# ADR-0027: The operator boundary, and what a measurement is

- Status: Accepted
- Date: 2026-09-03
- Related: ADR-0014 (the operator surfaces), ADR-0012 (the module boundary),
  ADR-0018 (the Service and the Host Services), ADR-0022 (identity classes),
  ADR-0052 (amendments 2026-09-24: clause 3's containment once, in
  `observe::Scope`, and the surfaces call the runtime's exports; the earlier
  one that had two writers is struck; and the last copies, the same day),
  ADR-0041 (a mood's color name and its rollup), ADR-0056 (the stage words,
  a node's evidence and its run entry), ADR-0062 (section 9, a program's
  audit record)
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
counted  streams | messages | journeys | bytes | retrying | failed
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

An unpublished figure is absent, never silently zero. Every surface says the
six under their own names — there is no Received, Processed or Sent, because
those are the words this clause exists to keep apart (amendment of 2026-09-14).


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

## Amendment, 2026-09-14: two outcome counts

Clause 5 named four counted things when it was accepted: streams, messages,
journeys, bytes. It now names six, corrected in place. `XMIP_COUNTED_RETRYING`
is the number of work items awaiting another attempt; `XMIP_COUNTED_FAILED`
is the number of outcomes that ended unsuccessfully in the measurement window.
Both are counts, unit count, and they cross the way the four do: a scope, the
thing counted, the unit and the window. They do not change the words. What is retrying or
failed is a Journey or a Message, and the item behind the figure is ADR-0032's
business, not the figure's. The runtime maps both and publishes neither yet; a
surface shows an unpublished figure as absent, never as zero.

Proposed by an assistant session on 2026-09-12, in five pull requests that
merged without the record. The owner accepted the two counts on 2026-09-14 and
declined the rest of the proposal — ADR-0052's amendment of the same date says
what and why.

## Amendment, 2026-09-24: section 7, the rules a surface calls

The owner, 2026-09-24: *Code shall be uniquely placed, used by others, whom in
turn has unique code used by others. It is common sense.* The surfaces wrote
again what the runtime's crates already decide — whether one scope is beneath
another (clause 3), the stage words, what a mood is called and painted, which
record is the worst — and a language boundary was the reason given. It is not
one: the boundary is crossed. `xmip_operate.h` gains a section 7 of eight
exported symbols, each a thin forwarder into the crate that owns the rule and
no rule of its own:

| Symbol | Forwards to |
|---|---|
| `xmip_scope_contains_v1` | `observe::Scope::contains` |
| `xmip_scope_parts_v1` | `observe::Scope::segments` |
| `xmip_stage_words_v1` | `node::Stage::WORDS` |
| `xmip_stage_declared_v1` | `node::Stage::declared` |
| `xmip_health_word_v1` | `observe::Health::word` |
| `xmip_health_named_v1` | `observe::Health::named` |
| `xmip_health_color_v1` | `observe::Health::color` |
| `xmip_health_order_v1` | `observe::Standing::worst_first` |

**Versioned by clause 2's own rule, additively.** Each is a separate optional
symbol with its version in its name, as `xmip_wait_change_v1` was: the
version-1 table is untouched and `XMIP_OPERATE_VERSION` stays 1, because no
existing symbol changed shape. A runtime that predates section 7 lacks the
symbols, and a surface binding them says which one is missing rather than
failing on a call. A change to one of them is a `_v2` beside it.

**Pure, and outside clause 6's concern.** None reads the snapshot or holds a
table, so none can make execution wait; each may be called from any thread,
before any node started. Strings come back borrowed from the caller's own
input or static in the library, and nothing handed back is freed by the
caller. Every call returns a status: `XMIP_E_MALFORMED` for text that is not
UTF-8, `XMIP_E_INVALID` for a mood section 3 does not define or a declaration
naming a word that is no stage — its REFUSED sentence written into the
caller's buffer the way `xmip_validate_v1` writes its report — and
`XMIP_E_NOT_FOUND` for a word that names no mood.

The runtime's `rule.rs` (now `src/ffi/rule.rs`, ADR-0050, refined 2026-09-25) implements them; `xmip-core-abi`'s `operate::rule`
declares their shapes, and the runtime's tests fail to compile if an export
drifts from them; `Xmip.Abi`'s `RuntimeRules` binds them once for every .NET
surface. ADR-0052's amendment of the same date says who calls each.


## Amendment, 2026-09-24 (later the same day): section 7 grows, and section 8 reads a publication

ADR-0052's amendment "the last cross-language copies, and a publication read
once" moved seven more rules to their owners. Section 7 gains seven symbols,
each a separate optional export under the same rules as the first eight —
pure, a thin forwarder, `XMIP_OPERATE_VERSION` unchanged:

| Symbol | Forwards to |
|---|---|
| `xmip_health_rolled_v1` | `observe::Health::rolled` |
| `xmip_counted_word_v1` | `observe::Counted::word` |
| `xmip_stage_counted_v1` | `observe::Counted::at` |
| `xmip_stage_pausable_v1` | `node::Stage::pausable` |
| `xmip_stage_location_v1` | `node::Stage::location` |
| `xmip_capability_published_v1` | `observe::capability::declared` |
| `xmip_capability_entry_v1` | `node::Capability::from_entry` |

A word that is no stage is `XMIP_E_NOT_FOUND`; a record that is no
capability record is `XMIP_E_NOT_FOUND`; a declaration naming a word that is
no stage is `XMIP_E_INVALID` with the node's name still written and the
refusal written as `xmip_stage_declared_v1` writes one.

**Section 8, a publication read by the runtime.** A surface that reads the
file a publisher wrote — a node's or a roll's snapshot — hands the text to
`xmip_publication_read_v1` and gets back a handle; `_head_v1`, `_records_v1`,
`_counts_v1`, `_nodes_v1`, `_links_v1` and `_run_v1` hand out what it read as
the header's values in section 5's fill shape (the records as
`XmipHealthEntry`, the counts as `XmipMeasurement`, the topology as the new
`XmipTopologyNode` and `XmipTopologyLink` with `XmipTopologyKind`,
`XmipTopologyOrigin` and `XmipCommunicationPattern`, the run's lists by
`XmipRunList`), and `xmip_publication_free_v1` releases the handle and
everything borrowed from it. A curve — the history file beside a
publication (ADR-0029), `observe::Curve` — is read the same way:
`xmip_curve_read_v1` into a handle, `xmip_curve_points_v1` as
`XmipMeasurement`s at the curve's node, `xmip_curve_free_v1`. Unlike section
7 it holds something, and says
so: every string borrows from the handle, and nothing is valid after the
free. It touches no running node, so clause 6 is not in play. A text that is
no publication is `XMIP_E_INVALID` with the reader's own words, as
`xmip_validate_v1` reports.

The runtime's `rule.rs`, `rule/node.rs`, `publication.rs` and `curve.rs` (all under
`src/ffi/` since 2026-09-25)
implement them;
`xmip-core-abi`'s `operate::rule`, `operate::publication` and the section 6
declarations beside them (`StartFn`, `ValidateFn`, which the language server
now calls through) declare their shapes; `Xmip.Abi`'s `RuntimeRules` and
`PublicationReader` bind them once.


## Amendment, 2026-09-25: section 9, a program's audit record

ADR-0062: every Xmip program audits through `xmip-core-audit`, and a .NET
program and PowerShell reach it through the runtime's library as they reach
section 7's rules. `xmip_operate.h` gains a section 9 of one symbol,
`xmip_audit_v1`, a thin forwarder into
`audit::program_audit::ProgramAudit::record` under section 7's rules — a
separate optional symbol, `XMIP_OPERATE_VERSION` unchanged, pure in clause
6's sense: it reads no snapshot and holds nothing afterwards.

It takes the program's name, the directory it was told (empty lets the
capability decide), the action, an `XmipPhase` and an `XmipSeverity`, a
message and the properties as key-then-value strings; it answers with an
`XmipKept` — suppressed, persisted, or held by the operating system's log
because the sink could not keep it — and, when not the sink, where and why
as UTF-8 in the caller's buffer, the way `xmip_validate_v1` writes its
report. `XMIP_E_INVALID` for a phase or severity the header does not define
or an odd property count; `XMIP_E_IO` when neither the sink nor the
operating system's log kept it. The record, its policy, the file sink and
the fallback are the capability's, never the forwarder's. Section 9 also
declares `XMIP_EVENT_SOURCE`, the Windows Event Log source the fallback
writes under, so the capability, the .NET fallback and the prerequisite
installer name it from one place.

The runtime's `src/ffi/audit.rs` implements it; `xmip-core-abi`'s `operate::audit`
declares its shape and its three enumerations, and the runtime's tests fail
to compile if the export drifts; `Xmip.Abi`'s `RuntimeAudit` binds it once,
reached as `RuntimeRules.Audit`, and `Xmip.Surface`'s `ProgramAudit` is what
every .NET program and both PowerShell modules call.


## Amendment, 2026-09-25: section 7 says where a scope sits

Open problem 25, row q: `Xmip.Surface`'s `ScopeTree.Node` took a scope's
first segment for its node, so the Monitor named the cluster as the node of
every record a roll publishes, and the PowerShell prompt looked for the
literal `node` segment itself — the scope's shape known in two surfaces and
known differently. Clause 4 puts the node beneath the cluster, and ADR-0053
gives a node the location `xmip:///<cluster>/node/<name>`; which segment that
is, and the stage of the message path beneath it, are `observe::Scope`'s now
(`node`, `stage`). Section 7 gains one symbol under its rules — a separate
optional export, pure, `XMIP_OPERATE_VERSION` unchanged:

| Symbol | Forwards to |
|---|---|
| `xmip_scope_node_v1` | `observe::Scope::node` and `observe::Scope::stage` |

It writes the node, borrowed from the scope, and the stage's static word,
each empty where there is none: the cluster is never a node, and a
cluster's or a node's name is never a stage. The runtime's
`src/ffi/rule.rs` implements it, `xmip-core-abi`'s `operate::rule` declares
its shape (`ScopeNodeFn`), and `Xmip.Abi`'s `RuntimeRules.Node` binds it;
ADR-0052's amendment of the same date says who calls it.


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
