# ADR-0031: Configuration is TOML; JSON is transport

- Status: Accepted
- Date: 2026-09-05
- Related: ADR-0011 (module and repository naming), ADR-0030 (prefix external
  names), ADR-0028 (the Xmip Essentials), ADR-0029 (observation has history),
  ADR-0015 and ADR-0018 (amendments 2026-10-01: Xmip Storage, and a node's
  configuration read into memory)

## In brief

- Theme: The shape of the estate
- Subject: What Xmip configures itself in, and what it moves data in
- Name: Configuration is TOML; JSON is transport
- Order: 6
- Concepts: Configuration, TOML; Transport, JSON

**Xmip configures itself in TOML and never in JSON. JSON is for transport —
content in memory or on the wire — and never for configuration.** The estate's
own files on disk are TOML; JSON that appears does so as data being carried or
validated, not as a file Xmip reads its settings from.

## Context

The owner's rule, stated repeatedly across 2026-09-04 and 2026-09-05 and each
time after the assistant reached for JSON where it did not belong: *"Xmip does
not use JSON for configuration at all, anywhere"*; *"there will always be JSON
transport"*; *"we only want JSON in memory or on the network, not as
configuration."* It is written down here so it is not re-litigated a fifth time.

The estate already lived this before it was recorded: `architecture.json` was
deleted for `architecture.toml`, and the .NET hosts read `gui.toml` through
a TOML configuration provider rather than `appsettings.json`.

## Decision

### 1. Configuration is TOML

Everything Xmip reads its own settings from is TOML: `architecture.toml`, node
configuration, `gui.toml`, and any file that follows. There is no JSON
configuration anywhere in the estate, and none is to be added.

### 2. JSON is transport

JSON is for data in motion — content on the wire, a message body, a payload a
Contract validates. That is the case the estate keeps JSON for, and it is always
available: Xmip has to speak JSON to the world.

### 3. On disk is TOML, even for data the estate writes for itself

A file the estate persists — configuration or its own runtime data, like the
Essentials' snapshot and history — is TOML. JSON is reserved for what lives in
memory or on the network. A persisted file is neither, so it is TOML. (ADR-0029
clause 5 applies this to the history file.)

### 4. What is not Xmip's to choose

Two kinds of JSON are outside this rule because Xmip does not own their format:

- **Foreign tooling files.** `global.json`, `launchSettings.json` and
  `packages.lock.json` are .NET SDK artifacts in fixed formats. They are not
  Xmip configuration and cannot be TOML; they stay as the SDK requires.
- **Content that happens to be JSON.** A Stream whose payload is JSON is data
  being carried or validated, not a file the estate configures itself from —
  clause 2, not a violation of clause 1.

## Consequences

- A new setting goes in a TOML file; a new persisted artifact is written in TOML;
  a new data exchange with the outside may be JSON.
- The distinction to check is not the format but the role: is this Xmip reading
  its own settings, or Xmip moving data? The first is TOML, the second may be
  JSON.

## Provenance

The rule is the owner's, stated across 2026-09-04 and 2026-09-05 and finally
*"write every decision down."* Clauses 1 to 4 are the assistant's drafting of it,
on that instruction.

## Amendment, 2026-09-24: an Xmip Process's lists default to empty

The owner, 2026-09-24, on open problem 25 row (b): an Xmip Process's
`required_modules`, `xmip_subprocesses` and `extensions` **default to empty
when the document omits them**, as the document's top-level lists
(`modules`, `xmip_processes`, `receive_locations`, `send_locations`) already
do; an Xmip Subprocess's `required_modules` and `extensions` likewise. An
Xmip Process that needs no module and has no Subprocess or Extension says
nothing about them, and the desktop editor does not have to write three empty
lists for an Xmip Process it adds.

What the runtime cannot start without still has no default: the `start` of
an Xmip Process, and a Location's `transport`. A document without them is
refused, never completed. A Location's `start` has a meaning when absent
since 2026-10-13 (ADR-0014, amendment of that date): only `true` starts a
Receive Location, Send Port or Send Location, and nothing or `false` leaves
it known and not started (`configure::NOT_STARTED`). Both are read by
`xmip-core-configure`, which reads the one document, and so by
`xmip_validate_v1` for every surface
(ADR-0027, amendment 2026-09-05).

The format itself is still open problem 14; this settles what one key means in
the shape that exists. Held by
`module/platform/configure/src/lib.rs`
(`a_process_that_names_no_list_reads_them_as_empty`) and
`module/platform/runtime/src/start.rs` (`a_minimal_process_validates`);
described in `module/platform/configure/doc/node-configuration.md`.

Provenance: the ruling is the owner's, 2026-09-24; the wording is the
assistant's.

## Amendment, 2026-09-26: configuration lives in files, never in a database

The owner, 2026-09-26: *the route rules shall be stored in the TOML
configuration files. We do not want configuration in a database like
BizTalk. Databases are for runtime and history, not configuration.* Every
piece of configuration — a node's, an Xmip Application's routes and
everything a designer draws (ADR-0064) — is a TOML file in the repository,
read by `configure`. No database holds configuration, and nothing is
configured by writing a row. The stores ADR-0015 names hold what happens:
RocksDB the runtime's state, SQLite its history and the records an operator
queries — never what was configured.

## Amendment, 2026-10-01: a node holds its TOML as its execution tree

The owner, 2026-10-01: *The TOML configuration should be read to an in memory
database. The TOML configuration can be changed by operation tools or
editors, but will not go in use until thread or process is started, reused.
I guess that's why SQLite was there. But runtime matter has to be central so
other nodes with matching NodeRoles can pick up.* Later the same day he
decided: *So no in-memory database it is.*

- **Each node reads its TOML configuration once, as it starts, and holds it
  as its execution tree in memory** — its Locations, its Subscriptions with
  their compiled filters, its Xmip Processes, its Send Ports — which
  `build_execution_tree` in `xmip-core-runtime` already builds (ADR-0018
  clause 4, phase 2). That tree is the node's configuration at runtime, and
  routing matches against its compiled filters (`runtime-model.md`
  section 9).
- **No in-memory database.** One would be a second copy of the tree. It is
  added only if something needs to query configuration in ways the tree does
  not answer.
- **A changed TOML file takes effect when the thread or Host Service that
  uses it is started again**, reused, never mid-flight. The operation tools
  and editors change the TOML file, never a database.
- **Nothing configured is central.** Xmip Storage (ADR-0056, amendment of
  this date) keeps runtime matter centrally — the Ledger, its claims and its
  state — so another node with matching node roles can pick up, and its
  administration database keeps what must be shared and kept over time:
  audit history, operator state (what is paused, by whom, when, which every
  node honors), deployment state and cluster membership. It holds no
  configuration (`deployment-model.md` section 7).

This agrees with the amendment of 2026-09-26: *Databases are for runtime and
history, not configuration.* It settles the question a record of earlier the
same day had raised, that a central database would hold configuration loaded
at startup.

Provenance: the owner's rulings, quoted. The list of what the tree holds is
the runtime's own; the wording is the assistant's.

## Amendment, 2026-10-01: where the runtime's settings are configured

**Provenance.** The owner, 2026-10-01, on six settings the runtime needed and
configuration had no place for: *sort it and present a solution*. The
assistant presented one, and the owner: *If there are no questions, write it
down.* Two points were then asked one at a time, and the owner answered
each *Yes*: processing depth sits on the Receive Location, as
`runtime-model.md` section 6 says (the interaction type beside it was taken
off on 2026-10-29, ADR-0013's amendment: every transport is
request-response); and audit policy
works like retention, `[audit] default` per node, overridable per Port and
per Location. The key names are the assistant's drafting.

The keys, all TOML (`runtime-model.md` section 20, *Where the runtime's
settings are configured*):

- **An Xmip Application's document.** `[[receive_ports]]` with `name`; each
  `[[receive_locations]]` names its `receive_port` (refused without one) and
  states `depth` (`transfer`, `light`, `context`). `[[send_ports]]` gains
  `send_locations` (tried in order), `retry = { attempts, backoff }` on the
  active Location, `failover` (`next`, `none`), and `correlation`,
  the cluster's set its Journeys pass it by one at a time per key (the
  amendment of 2026-10-22 below).
- **A node's configuration.** `[[parties]]` with `name` and `identities`
  (ADR-0019), so `[receive_locations.accept] party = [...]` names them;
  `[retention] default`, overridable per Port; `[audit] default`,
  overridable per Receive or Send Port and per Location.

Each is read into the node's execution tree as it starts, like everything
else configured (the amendment above).

Built 2026-10-03, the Application's keys: an Xmip Application is a section
of `cluster.xmip` (the amendment of 2026-10-03, ADR-0064), and
`xmip-core-configure` reads its `[[receive_ports]]`, each Receive
Location's `receive_port` and `depth`, and each Send Port's
`send_locations`, `retry`, `failover` and `correlation` (`port.rs`). A
Receive Location without its Port, naming one the Application does not
declare, or without its depth, is a problem of the
Application, refused at startup phase 3; the execution tree holds the
Receive Ports a node's bound Receive Locations are at and the Send Ports
it takes, with their policy. How a Send Port's `send_locations` relate to
the one Send Location its binding gives it is not yet decided. The node's
keys — `[[parties]]`, `[retention]`, `[audit]` — are not read yet.


## Amendment, 2026-10-02: Subscriptions are shared through Xmip Storage

The owner, 2026-10-02: *Routes are defined in TOML, read into Storage at
Xmip Host Service startup, read from Storage when needed and kept in memory
until "not used for a while".* Asked whether they are shared across the
cluster: *They are shared.*

- **A Host Service writes its Subscriptions — the routes — into Xmip
  Storage's administration database as it starts.** They are shared: any
  node with a routing role routes a Message another node received.
- **Routing reads the Subscriptions from Xmip Storage when it needs them,
  compiles their filters, and keeps them in memory until they have not been
  used for a while**; the next use reads them again. **A while is one
  hour** (the owner, 2026-10-02, on the assistant's calculation: a miss is
  one read from a Storage node, about 1 ms; a compiled filter is a few KB,
  so 10,000 Subscriptions are about 40 MB; an hour keeps every route that
  runs hourly or more often in memory, and a daily route pays one miss a
  day).
- **A Host Service that writes changed Subscriptions makes every node drop
  the ones it holds** (the owner, 2026-10-02), so a route in constant use
  does not stay stale. Xmip Storage keeps a generation of the Subscriptions,
  raised by each change, and answers it with every Ledger write; a node
  that sees a newer generation drops what it holds and reads again. No
  extra round trip is made for it.
- **TOML stays the only place configuration is written.** Xmip Storage holds
  what the Host Services read from their TOML at start, never a change of
  its own; the operation tools and editors change the TOML file, never a
  database. A changed TOML file takes effect when the Host Service that
  reads it is started again, never mid-flight.
- The rest of a node's configuration — its Locations, Xmip Processes and
  Send Ports — is held as its execution tree in memory, as the amendment of
  2026-10-01 says.

This narrows the amendment of 2026-10-01, *Nothing configured is central*,
and that of 2026-09-26, *No database holds configuration*: the
Subscriptions are central, as a copy of the TOML that is never edited where
it is held.

Provenance: the owner's rulings, quoted; the wording is the assistant's.

## Amendment, 2026-10-03: one `cluster.xmip` per cluster, sliced to each node

**Provenance.** The owner, 2026-10-03: *All these outwards, hardware
assumptions and calculations should be configurable per cluster and node.
Kept in the Cluster TOML file*; *There is one xmip.toml file per cluster.
When deployed the sections regarding a node will be sliced to that node.*

- **A cluster's configuration is one file, `cluster.xmip`.** What the whole
  cluster shares is in it once; what concerns one node is in that node's
  sections, `[nodes.<name>]`.
- **Deployment slices it.** Desired state (`deployment-model.md` section 8)
  writes each node the cluster's shared sections and that node's own, and
  the node reads its slice at start, as it reads its configuration today
  (the amendment of 2026-10-01). Where both say a value, the node's wins.
- **Every outward and hardware assumption is configured there**, per
  cluster and per node: the TCP segment and the segments a chunk holds
  (`runtime-model.md` section 3), the receive pool's threads per hardware
  thread and its idle time, the Send pool's likewise and a send's claim
  lease and scan (`send_threads_per_hardware_thread`, `send_idle`,
  `send_lease`, `send_scan`, built 2026-10-03 with the send step,
  `runtime-model.md` section 10), the Work Process step's scan of its
  queues (`work_scan`, built 2026-11-12; ADR-0066, amendment 2026-11-12;
  until then a constant), the Work pool's threads per hardware thread, the
  most turns that step holds at once (`work_threads_per_hardware_thread`,
  built 2026-11-12; ADR-0066, third amendment 2026-11-12; until then the
  Send pool's figure), a polled Receive Location's rest after a
  receive that found nothing and after a failure that may mend
  (`receive_poll`, `receive_backoff`, built 2026-10-12, `runtime-model.md`
  section 5), the recovery sweep of a Location whose far end tells it of a
  change (`receive_sweep`, built 2026-10-20; ADR-0024, amendment
  2026-10-20), how long a stopping Receive Location drains what its far end
  already let go of (`receive_drain`, built 2026-10-15, the same section),
  how long each read of a TLS handshake a Receive Location terminates waits,
  apart from the Location's own wait (`receive_handshake`, built
  2026-10-20; ADR-0033, amendment 2026-10-20),
  how many of the oldest failed Journeys of each Send Port a node keeps
  (`failed_window`, built 2026-10-16, `runtime-model.md` section 10),
  the node's budget beside its pools — the arrivals it carries at once
  across all its Receive Locations, the chunks those carries hold, and the
  chunks its sends hold (`node_receive_threads_per_hardware_thread`,
  `receive_chunks_per_thread`, `send_chunks_per_thread`, built 2026-10-19,
  `runtime-model.md` section 3; ADR-0018, amendment 2026-10-19),
  the Storage client's timeouts and
  pass-over, and the longest a Storage node holds one node's wait on its
  queues (`storage_wait`, built 2026-11-12; ADR-0018, amendment
  2026-11-12), and how many of what no node waits on a Storage node keeps
  (`storage_unwaited`, built 2026-11-12; ADR-0018, amendment 2026-11-12)
  — under `[tuning]` for the cluster and `[nodes.<name>.tuning]`
  for a node (the key names are the assistant's drafting). The built-in
  values are the defaults where neither says; a new assumption of this kind
  gets its key in the change that brings it.

This answers open problem 14 (the node configuration format): one cluster
file, not three, and the node's section wins.

## Amendment, 2026-10-05: Prepare, Contract, Promote, Transform and Demote on the Port and the Location

**Provenance.** The owner, 2026-10-05, asked how a Receive and Send
artifact configures Prepare, Promote, Demote and Transformation: *Look at
BizTalk how it is done, Prepare would be PipelineComponent, Transform would
be Map, Promote, Demote are the same terminology.* Weighing his design
against BizTalk's: *I have a nagging feeling that one wants to be able to
perform all these steps on the Port & Location. Let's say you have two
Receive Locations in one Receive Port. The format on one Receive Location
may not be the same as for the other. The format shall end up as the same
in the Receive Port. The reverse goes for Send*; on Prepare, *There could be
cases where one wants to prepare on both levels*; on Contracts, *I think that
needs to go on both places for both Receive & Send. Then the designer,
developer, end user has a possibility to place functionality where it
belongs for the current case*; and on validation: *Contracts do not
decide whether validation should be done or not. It is the configuration of
the Receive Port, Receive Location, Send Port and Send Location*; *there
might or might not be a contract configured. During development validation
by a contract is default on for Receive. For Send there might or might not
be a contract configured. During development validation by a contract is
optional*; asked whether that meant the designer's default or the
runtime's: *Yes on all.* The order of the steps within a level and the key
names are the assistant's drafting.

- **Each of the four artifacts — Receive Port, Receive Location, Send Port,
  Send Location — may configure Prepare, a Contract, and Transform; the
  receive pair Promote, the send pair Demote.** Every one is optional. The
  Location speaks the format of the world outside — the Party's, the
  endpoint's — and the Port speaks the one format of its purpose: two
  Receive Locations of different formats meet in one format at their
  Receive Port, and a Send Port's one format leaves through Send Locations
  that each speak their endpoint's. BizTalk has a Location's pipeline and a
  Port's maps; Xmip has every step at both levels.
- **Receive runs the Location, then the Port; send runs the Port, then the
  Location.** Prepare works on the Stream, never on a Message
  (`runtime-model.md` section 8), so the Port's Prepare is the inner layer:
  on receive it runs after the Location's and before Message creation, on
  send after the Location serializes and demotes and before the Location's.
  ```text
  Receive  Location prepare -> Port prepare -> Message creation, default promotion
           -> Location: Contract, validate, promote, transform
           -> Port:     Contract, validate, promote, transform -> Publication
  Send     Port:     Contract, validate, transform, demote
           -> Location: transform, Contract, validate, serialize, demote
           -> Port prepare -> Location prepare
  ```
- **Validation is the artifact's choice, never the Contract's.** A Contract
  is structure the artifact may also use only to deserialize and promote.
  Where a Receive Port or Location names a Contract, it validates unless it
  says `validate = false`; where a Send Port or Location names one,
  validation is optional and off unless it says `validate = true`. The
  designer writes the same: `validate = true` when a Contract is added on
  the receive side, the choice left open on the send side.
- **A Transform is compiled at design time** (ADR-0066 clause 1); the
  artifact names it. **Promote and Demote** use Content Selectors
  (`module/core/capability/promote/doc/content-selector.md`); the Port
  promotes and demotes in its format, the Location in its own.
- **Startup checks the chain**: what a Location hands its Receive Port, a
  Transform's output and what a Send Port hands its Send Location must be
  what the next Contract names, where both are named; a mismatch is refused
  at start, never at the first Message. A Transform, a validation or a
  promotion that needs the content materialized is refused on a Receive
  Location at `transfer` or `light` depth (`runtime-model.md` section 7).

```toml
[[receive_ports]]
name     = "Orders"
contract = "xmip-core-contract-json-schema"     # the Port's one format
contract_settings = { reference = "schemas/order.json" }
promote  = { OrderNumber = "order.number" }     # Content Selectors

[[receive_locations]]
name         = "OrdersEdi"
receive_port = "Orders"
contract     = "xmip-core-contract-edifact"     # the Party's format
validate     = false                            # receive: true unless said
transform    = "EdifactOrderToOrder"            # compiled at design time

[[receive_locations.prepare]]                   # in order
step     = "xmip-core-prepare-decompress"
settings = { format = "gzip" }

[[send_ports]]
name      = "ErpOut"
transform = "OrderToErpOrder"
demote    = { OrderNumber = "order.number" }

[[send_locations]]
name     = "ErpPrimary"
contract = "xmip-core-contract-xml-schema"
validate = true                                 # send: off unless said
demote   = { OrderNumber = "headers['X-Order']" }
```

This replaces `runtime-model.md`'s single receive gate and single send
validation with one per level, and answers which artifact configures a
Preparation Step, a promotion, a demotion and a Transformation. Not built.

## Amendment, 2026-10-05: only `cluster.xmip` is edited

**Provenance.** The owner, 2026-10-05: *node TOML files shall not be
edited, only cluster TOML files, the files are sliced / node and
distributed. […] Of course the node TOML files can be changed, but that
breaks configuration rules.*

- **`cluster.xmip` is the one configuration anyone edits** — by
  hand, in the VS Code designer or in any tool. A node's `node.xmip`
  is the slice desired state writes from it (the amendment of 2026-10-03,
  `deployment-model.md` section 8), never edited.
- **A node's file changed by hand breaks this rule**: the next deployment
  writes the slice over it, and until then the node runs what its cluster's
  file does not say. No Xmip tool offers to edit a node's file.

- **Save slices and ships.** The owner, the same day: *When editing is
  done, the cluster TOML file is sliced into node TOML files and shipped to
  each node on save.* Saving the cluster's file slices it through the one
  slicing, `configure::slice`, and puts each node's slice on that node; a
  changed slice takes effect as the amendment of 2026-10-01 says, when what
  reads it starts again.

The Operation Desktop's Configure page edited a node's own file, against
this rule. The owner: *Change it, we edit the cluster TOML file, drilling
down to nodes and artifacts from the overview of the cluster.*

Built 2026-10-05, the Operation Desktop: its Configure page opens the
cluster's file `gui.toml`'s `ClusterConfiguration` names, on an
overview of the cluster, and drills to a node, to artifacts by kind and to
an entry, every view and edit through `xmip_operate.h` section 10; a
node's own document is shown with the slicing's refusal and never edited.
Save writes the file, validates it, slices it per node through the new
`xmip_cluster_slices_v1` and writes each slice to
`<SliceDirectory>/<node>/node.xmip`, each step audited per node; the
desktop's own node (`Node`) is shipped and started from its slice, every
other node is *sliced, not shipped* until a node's slice can be placed
remotely (open problem 31). `NodeConfiguration`, `ConfigStore` and the
node-file editor are deleted.

## Amendment, 2026-10-05: a save is previewed, versioned, confirmed, watched and restarts only what changed

**Provenance.** The owner, 2026-10-05, on the cluster's file against a
BizTalk Group's management database: *Compare it to BizTalk, BizTalk Group
but better.* The assistant proposed five points and asked them one at a
time; the owner answered each *Yes*. The wording is the assistant's.

1. **Preview before save.** Before a save the editor shows, per node, what
   its slice changes and which threads or Host Services must start again
   for it to take effect.
2. **Every save is a version.** A save is numbered and audited with who
   saved it; each node keeps its previous slice, and a node can be rolled
   back to it.
3. **A node confirms its slice.** A node reads and validates a slice
   shipped to it before it uses it and answers accepted or refused, with
   the reason; the editor shows the answer per node. Waits on open problem
   31, placing a slice on a remote node.
4. **Drift is seen.** Each node reports a fingerprint of the slice it runs;
   the Monitor flags a node whose slice is not what the cluster's file
   slices to it — one edited by hand among them.
5. **Only what changed starts again.** A changed slice restarts the threads
   and Host Services whose configuration changed, never the whole node; the
   rest runs on untouched (narrowing the amendment of 2026-10-01: *a changed
   TOML takes effect when the thread/Host Service using it restarts*).

BizTalk applies a change from its Administration Console without preview,
keeps no history, tells no one whether a host instance took it, cannot
drift because every host reads one database — and stops when that database
does — and restarts whole host instances. Not built.

## Amendment, 2026-10-05: the Xmip Service beside the editor ships the slices

The owner, 2026-10-05, asked which side starts a slice's journey to a node
on another machine: *The Operation Desktop, or rater the Xmip Service where
the Operation Desktop is running on ships it.* The Xmip Service on the
machine the editor runs on pushes each node's slice to that node's Xmip
Service, over gRPC on TCP between machines (ADR-0052, amendment
2026-10-05); the node validates it and answers accepted or refused (the
amendment above, point 3). The editor never ships a slice itself. Open
problem 31.

Where each node is: the owner, asked whether its address is written under
`[nodes.<name>]`: *The cluster knows the addresses.* The shipping Xmip
Service learns each node's address from cluster membership — node
registration in the administration database (`deployment-model.md`,
*The administration database holds*) — not from `cluster.xmip`.

## Amendment, 2026-10-22: no Pipeline, the attachment keys decided, and debatching on both sides

**No Pipeline concept.** The amendment of 2026-10-05 already breaks
BizTalk's Receive and Send Pipelines into steps every Port and Location may
configure, and Xmip has no Pipeline beside them. BizTalk's stages, the
owner's mapping of 2026-10-22:

| BizTalk pipeline stage | Xmip |
| --- | --- |
| Decode, Encode | Prepare — a Receive or Send Preparation — and message security |
| Disassemble, Assemble | the Contract, with its deserialization or serialization |
| Validate | validation (`runtime-model.md` section 20, *Validation gates*) |
| Resolve Party | ADR-0019's identity steps: identify, authenticate, authorize |
| Pre-assemble | Transform and Demote, on send |

**The keys are decided** (ADR-0066, amendment of this date): each step is a
call to a compiled unit, an entry of `[[preparation_steps]]`,
`[[promotions]]`, `[[demotions]]` or `[[transformations]]`, and a Port or
Location attaches entries by name — `prepare = [...]`, `transform`,
`promote` on receive, `demote` on send. The inline `promote` and `demote`
tables of Content Selectors and the `[[…prepare]]` tables of a step and its
settings drafted on 2026-10-05 are replaced by them. `contract`,
`contract_settings` and `validate` stay as drafted; reading them is still
decided, not built.

**Debatching, on both sides.** Asked whether debatching belongs in the
receive or in an Xmip Work Process, the owner, 2026-10-22: *I'm not sure,
can we go with both?* So both: in the receive, streamed — each record
published as a Message of its own as soon as it is complete, a failure
reported for each record — and in an Xmip Work Process. One splitting
implementation, placed once, is called from both.

**Batching only in an Xmip Work Process.** The owner: *I'm not sure that I
want Debatching and Batching without a Xmip Work Process. It is not stream
friendly.* Batching gathers Messages over time, which a stream does not
wait for; it is a Work Process's.

Built in a Work Process: a Batch and a Debatch, the splitting placed once
in `xmip-core-runtime`'s `split`. The receive's debatching, its key and
its all-or-nothing rule are the amendment of 2026-10-27's.

## Amendment, 2026-10-22: Correlations replace a Send Port's ordering keys

The owner, 2026-10-22: *A default correlation set is its receive location
name. … I can widen and strangle parallelism at any configurable point.*
`cluster.xmip` declares `[[correlations]]` — `name`, `keys`,
`on_failure` (`block` where it says nothing, or `skip`) — once for the whole
cluster, and a Receive Location, a Receive Port, a Work Process or a Send
Port names one by `correlation` (ADR-0024 and ADR-0066, amendments of
this date). The Send Port's `execution_style`, `order_key` and
`on_failure` and the Work Process's `execution_style` are deleted with every
use: a Send Port that sends one at a time names a set keyed by `send-port`.
A set that is not declared, declared twice, with no key or with a key that
is no key word is refused at validation and as a node starts. A
Work Process names its compiled flow by `module` and `unit`.

## Amendment, 2026-10-27: debatching is all or nothing, and the records keep their order

The owner, 2026-10-27, agreed the three drafts of this amendment's
predecessor as proposed, and decided two points beside them: *If one
fails, they all fail*; *Sequence is in order found in inbound stream,
message*; and *It can be routed if all splits are done and validated, from
there on they have their own journeys. Context variables keeping them
together that makes a Work Process to handle them.* This replaces the
amendment of 2026-10-22's *each record published as a Message of its own
as soon as it is complete, a failure reported for each record*.

- **A splitting unit declares the capability `debatch`**, serving the
  stages `receive` and `process` alone (ADR-0066, amendment of this date).
- **A Receive Location or Receive Port attaches one** by `debatch =
  "<entry>"`, naming an entry of `[[debatches]]` — `name`, `module`, `unit`
  and `settings`, as the other calls are — in its own document. A Send
  Port or Send Location attaching one is refused in words.
- **Where it runs on receive**: after Prepare and Message creation, before
  the Contract.
- **Split as the chunks arrive, routed at the end.** Each record is written
  into the Ledger as a Stream of its own as soon as it is complete, so
  memory stays bounded by a record. Every record is split and validated
  by its Contract before any is routed; then all are routed in one write,
  in the order they had in the inbound Stream or Message, and from there
  each is a Journey of its own.
- **All or nothing, every failure reported.** Where any record fails,
  nothing is routed, the records written are removed, and the received
  Message fails as one. The splitting goes on past a failed record, every
  record still split and validated, writing nothing more, and the failure
  is reported once: a summary — how many records, how many failed —
  followed by each failed record's position and reason (the owner, the
  same day: *Failures … shall be accumulated*; ADR-0013, amendment of this
  date). In a Work Process the Debatch throws `record-refused`, that
  report its reason, for the design's error boundary.
- **Kept together by context**, decided by the owner the same day on
  Spring Integration's model — its `correlationId`, `sequenceNumber` and
  `sequenceSize` headers. Each record carries its Message's context and
  three values tying it to its batch, so a Work Process can take the
  records up together, by a Correlation keyed on them: the received
  Message's identifier (the batch), the record's position from one, and
  how many records there are. There is no flag for the last record: the
  position and the count say it. The key names were decided with the
  owner's leave, 2026-10-27: `debatch.message`, `debatch.position` and
  `debatch.count`.

Built 2026-10-27: the capability (`abi::UnitCapability::Debatch`), the
`[[debatches]]` list and the `debatch` attachment with their refusals and
the designer's Debatch view (`configure::step`, `configure::kinds`), the
one splitting implementation (`xmip-core-runtime`'s `split`: records
written as they complete, made Messages with the three values once all
are split, every failure gathered in `xcore::Outcomes`) and the
Work Process's Debatch through it. Decided, not built: the receive's call of it, which needs
the Contract run on receive, one write routing several Messages, and the
removal of written records from Xmip Storage (open problem 47); until
then a node refuses to start a Location or Port attaching a Debatch, as
it refuses every unit attachment (`configure::step::unrun`).

## Amendment, 2026-11-04: an Xmip file ends in `.xmip`; it is TOML inside

The owner, 2026-11-04: *It should be .xmip but it is toml inside.* Asked
which files and whether their names change, he chose every TOML file Xmip
owns, and names without the prefix the extension now says.

- **Every file Xmip owns ends in `.xmip`** and is TOML inside, read and
  written as TOML as before: a cluster's `cluster.xmip` (was `xmip.toml`), a
  node's slice `node.xmip` (was `xmip-node.toml`), the surfaces' `gui.xmip`,
  `cli.xmip` and `powershell.xmip`, the deploy profiles and sites, what the
  runtime and the Essentials persist, and the estate's own
  `architecture.xmip`, `prerequisite.xmip`, `asset/brand/brand.xmip` and
  `doc/planning/allocation.xmip`.
- **What another tool names stays**: `Cargo.toml`, `rust-toolchain.toml`,
  `.cargo/config.toml`. The `toml` Contract technology checks TOML content,
  not Xmip's files, and keeps its name.
- **Editors read it as TOML**: the VS Code extension maps `.xmip` to TOML and
  validates every `.xmip` document; `.gitattributes` has GitHub show it as
  TOML.

Narrowed by the amendment of 2026-11-10: only what describes an installation
ends in `.xmip`.

## Amendment, 2026-11-05: one module reads, handles and saves configuration

The owner, 2026-11-05: *we need one module, functionality that reads,
handles and saves configuration*; and on how a machine with nothing yet
installed reads `prerequisite.toml`: *Do your best.*

- `xmip-core-configure` is that module for every file Xmip owns, `.xmip`
  and `.toml` alike (amendment 2026-11-10): it knows each
  file's name and place, reads it, validates it, and saves an edit with
  `toml_edit`, keeping comments and layout. The surfaces reach it in the
  order ABI, CLI, PowerShell, GUI; nothing else parses TOML or builds a
  file's path.
- A machine without cargo takes the module prebuilt, from Xmip's own
  release, as it later takes `xmip-service`; the estate builds its own once
  cargo is there. There is one reader either way.
- Not built: the estate's PowerShell still reads through `Read-XmipToml`
  and PSToml. Their replacement follows.

## Amendment, 2026-11-06: a node runs only the slice its cluster signed

The owner, 2026-11-06: *Having a cluster.xmip file is good, but not all. If
we have multiple nodes in a cluster, performing the same work we have a
problem. What if someone goes in and edit the node.xmip file and it should
not have been done.* Asked which way, he left it to the assistant, who
recommended a signed slice; the owner: *Go ahead.*

Seeing drift (the amendment of 2026-10-05, point 4) tells of an edit after
the node ran it, and a digest anyone may compute again proves nothing. So
the node itself refuses:

1. **A slice is signed as it is sliced to be placed.** Under the slice's
   text, a `[signature]` table holds `cluster`, the SHA-256 of the
   `cluster.xmip` it was sliced from (which save it is), `by`, the SHA-256
   of the signing certificate, and `value`, the cluster authority's
   signature over the text above the table and `cluster` together. The
   signing key is the cluster's authority (`provision::Issuer`, the
   `authority` folder beside the configuration), kept on the node that keeps
   the authority and on no other. A one-node install makes that authority
   as it is installed and signs its starter slice by the same code.
2. **A node runs only a slice that verifies.** As it starts, a node checks
   its `node.xmip` against the authority's certificate in the `authority`
   folder beside it, a certificate the file itself never names. One that
   verifies is kept as the node's accepted slice,
   `<node>.accepted.xmip` in its data directory. One that does not —
   edited by hand, unsigned, signed by another authority — is refused in
   words and audited, and the node runs its accepted slice instead; with
   none accepted, it does not start (`runtime::signed`, `start::read`).
3. **Every node says which save it runs.** A node reports `cluster` from
   its accepted slice; the Monitor flags one whose save is not its peers'.
4. **The file is the node's alone to write.** The install makes
   `node.xmip` writable by the node's service account and administrators
   only.

Signed with the authority's P-256 key, the signing `provision` has; a
hybrid ML-DSA signature beside it follows once Xmip signs with ML-DSA, not
only verifies.

Neither competitor signs: a BizTalk host reads one management database and
stops with it; MuleSoft's Runtime Manager writes over a local change at the
next deployment and runs it until then.

Every writer of a slice signs it through `runtime::signed`: the install's
starter, `xmip-service --slice` (with the authority beside the cluster's
file, made there where none is), the Essentials, and the Operation
Desktop's save (`xmip_cluster_signed_slice_v1`), which writes the
authority's certificate beside each slice it delivers. A test writes its
node through `runtime::fixture::write_signed`.

The desired-state templates slice and sign on the machine the environment
is deployed from, never on a node: `xmip-service --slice --authority`
signs each node's slice with the environment's authority there, the one
`New-XmipCertificate -Node` issues the nodes' certificates from, and a node
is shipped its slice and that authority's certificate alone
(`Xmip.Environment/Slice` and `Xmip.Node/Slice` in Microsoft DSC v3; the
role `xmip_node`'s `tasks/slice.yml` in Ansible). `--install` writes a
starter `cluster.xmip` only for a node that has no slice yet.

Point 4 is built in both desired-state templates (2026-11-07): `node.xmip`
is, on Linux, the node's account's, group root, mode 0640, and on Windows
inherits nothing, SYSTEM and the administrators in full control and the
node's account with Modify. In Ansible the role `xmip_node` sets it, the
package's starter included; in Microsoft DSC `Xmip.Node/Slice` sets it as
it places the slice, the file being its own, and its get and test report
it, out of the desired state where it differs. The virtual account's SID
is computed in the resource as Windows computes it, since the account
exists only once the package has registered the service. DSC's own
`Microsoft.Filesystem/ACL` is not used: it takes the whole access list as
SDDL, and 3.4.0-preview.2 ships it in none of its packages.

Not built: point 3.

## Amendment, 2026-11-07: the node pins its authority, its name and its serial

A review of the signed slice found five ways past it. The anchor was read
from the `authority` folder beside the slice it checked, so whoever could
write the configuration folder replaced both and the node took the forgery.
The signature carried no serial, so an older slice the same authority
signed ran again. It carried no node, so another node's slice ran. The
accepted slice was written as an ordinary file, and where it was written was
the data directory the unverified file named. So, in place of point 2's
anchor and keeping:

1. **The signature says which node, which serial and when.** Beside
   `cluster`, `by` and `value`, the `[signature]` table holds `node`, the
   slice's `[service]` `node_name`; `serial`, strictly increasing from one
   signing to the next (the signer's clock in nanoseconds, one above the
   last it gave where the clock has not moved); and `issued`, Unix seconds.
   The signature is over the text and every one of them but `by` and
   `value`. A slice naming no node is not signed.
2. **The node holds its trust outside the configuration folder.** Its
   accepted slice is `<stem>.accepted.xmip`, after the configuration file's
   stem, in the default data directory, `../data` from the configuration
   folder: found from where the configuration is and never from what a
   slice says, and written by the node alone, as a private file
   (`secret::private_file`). That folder is the node's own and the slice's
   writers — the deploying machine, the Operation Desktop, an administrator
   — write the configuration folder, so a file that changes the one cannot
   change the other. The accepted slice's signature is the pin: its `by`,
   the authority's fingerprint; its `node`, the node's name; its `serial`,
   the last accepted.
3. **A slice runs only where it follows the pin.** The certificate beside
   the configuration must be the one the pin names, or the node does not
   start and says so. The slice must verify against it, be signed for the
   node the pin names, and carry a serial above the pin's, or be the
   accepted slice itself again. Anything else is refused in words and the
   node runs its accepted slice.
4. **The first slice a node accepts pins all three.** Every deployment
   starts the node as it installs it, so that slice is the administrator's.
   An authority replaced on purpose is taken by removing the node's
   accepted slice, which pins the next.
5. **Only the running node keeps.** `runtime::signed::accepted` checks and
   keeps; `runtime::signed::checked` checks the same and writes nothing,
   and is what `start::read` uses: a plan, `xmip-service --install` running
   as an administrator, and a surface.

Every signer is unchanged in how it is called (`runtime::signed::sign`,
`xmip-service --slice`, the Essentials, the Operation Desktop's
`xmip_cluster_signed_slice_v1`), and the desired-state templates still
ship `node.xmip` and `authority/authority.pem` alone.

The serial is the signer's clock: a deploying machine whose clock is set
back signs slices a node refuses until the clock passes the pin, said in
words where it happens. Not built: the deployment seeding the pin itself
rather than the node's first start.

## Amendment, 2026-11-10: only what describes an installation ends in `.xmip`

The owner, 2026-11-10: *I did not want to change the extension from .toml to
.xmip for all .toml files, just the ones that need to be associated with VS
Code designer and other tools.* `.xmip` is for what describes an
installation, the files the designer and Xmip's tools open; everything else
Xmip keeps is `.toml` again. The amendment of 2026-11-04 stands as the record
of what was done; this one narrows it.

- **`.xmip`, unchanged**: a cluster's `cluster.xmip` (and the Essentials'
  `<cluster>.xmip`, the test clusters' and the samples'), a node's slice
  `node.xmip` and its accepted copy `<stem>.accepted.xmip`, a node
  configuration the runtime reads (the Essentials' `authority/operator.xmip`),
  a snapshot (`snapshot.xmip`, `<cluster>-snapshot.xmip`, a node's
  publication), and a site, `deploy/site/<name>.xmip`.
- **`.toml` again**: the estate's `architecture.toml`, `prerequisite.toml`,
  `asset/brand/brand.toml`, `asset/brand/presentation/story.toml` and
  `audio/timing.toml`, `doc/planning/allocation.toml`; the deploy profiles,
  `deploy/profile/role/<role>.toml` and `deploy/profile/target/<target>.toml`;
  the desired-state environments, `deploy/dsc/hyperv.example.toml` and
  `libvirt.example.toml` and the copy `Deploy-XmipEnvironment` reads
  (`.local-work/deploy/hyperv.toml`, `libvirt.toml`), the one file that says
  which technology makes an environment and which node runs on which
  machine, from which the YAML DSC and Ansible read is written (ADR-0015,
  amendment 2026-11-11); the surfaces' `gui.toml` (the phone's
  `android-gui.toml` too), `cli.toml` and `powershell.toml`; the landing's
  `.local-work/landing/patch.toml`; `audit.toml`; the Essentials' records,
  `<cluster>-history.toml`, `<cluster>-activity.toml`, `roll-<pid>.toml`,
  `build-<start time>.toml` and `estate-<start time>.toml`; a process's
  declaration, `<name>-<pid>.toml`; an operator's order,
  `<nanos>-<sequence>-<act>.toml`; a test suite's declaration under
  `test/suite`; a module's manifest, `xmip-module.toml`, and the designer's
  `module.toml`.
- **No compatibility**: no reader takes the old `.xmip` name of a file that
  is `.toml` again.
- **Editors**: the VS Code extension maps and validates `.xmip` alone; a
  `.toml` file is TOML to every editor, and `.gitattributes` keeps showing
  `.xmip` as TOML on GitHub.

## Amendment, 2026-11-12: a node trusts a slice before it runs it, and keeps the last that ran

**Provenance.** The owner, 2026-11-12, brought a review of the estate,
*Here are some thoughts*; one finding was this defect, and the order he
gave for it is what follows: separate accepting a slice as trusted from
activating it; keep the pin and the anti-replay state apart from the last
configuration that activated; validate a candidate before it replaces the
recovery configuration; say what happens when activation fails; runtime
startup owns all of it. The policy for a failed activation (point 5) is
the assistant's, decided while designing, for the owner to change.

Until this day the running node kept a slice that verified as its accepted
slice before anything read it (amendment 2026-11-07, point 2), and only
then ran ADR-0018's phases over it. A correctly signed slice naming a
technology the build lacks replaced the accepted slice and was then
refused at phase 3, and the slice that ran before could not be placed back,
its serial now below the pin's. The fallback protected against a bad
signature, not against a configuration the node cannot run. The
amendments of 2026-11-06 and 2026-11-07 stand as the record of what was
done; this one narrows 2026-11-06 point 2 and 2026-11-07 points 2 to 5.

1. **Three states, two files the node writes.** The *candidate* is
   `node.xmip`, which the deployer writes and the node never does. The
   *pin*, `<stem>.pin.toml`, holds the authority's fingerprint (`by`), the
   node (`node`), the highest serial seen in a slice that verified
   (`serial`) and that slice's file's SHA-256 (`slice`); a record, so
   `.toml` (amendment 2026-11-10). The *active configuration*,
   `<stem>.active.xmip`, is the signed file of the last slice that ran; it
   replaces `<stem>.accepted.xmip`, which no reader takes. Both are private
   files the node alone writes (`secret::private_file::replace`), in the
   default data directory, found from the configuration's place alone.
   Their names and the pin's form are `configure::signed`'s
   (`pin_at`, `active_at`, `Pin`); the trust rules `runtime::signed`'s.
2. **Trust first, pinned as seen.** The anchor beside the configuration
   must be the pinned one, or the node does not start. `node.xmip` byte for
   byte the active configuration is no candidate. Otherwise it is admitted
   where it verifies, names the pinned node, and carries a serial above the
   pinned one, or the pinned serial and the pinned slice's digest: the same
   candidate, seen and not yet run. Anything else is refused in words and
   never runs. A candidate above the pin is pinned as seen before anything
   reads it; a node with no pin pins the first slice it admits, the
   candidate, or else the active configuration. Removing the pin re-pins on
   purpose, as removing the accepted slice did.
3. **An attempt, serving nothing.** Every startup phase runs over the
   candidate, and then the program's own steps that can refuse: the
   operate listeners, the cluster authority's serving and the orders watch.
   `Running::start` builds and serves nothing; `Running::activate` first
   replaces the active configuration with the candidate's file, then
   serves, and the program then says it accepts work. The order is
   `runtime::running::activation::started`.
4. **The fallback.** A candidate refused at any step is let go, its Storage
   node stopped as it is dropped, and the same attempt is made over the
   active configuration, verified again against the pinned anchor and node,
   in the same process. With none, or where it refuses too, the start is
   refused with exit code 2 and both refusals in words.
5. **The policy, decided while designing.** A refusal before the node
   accepts work refuses the attempt, not the node, whether the
   configuration or the machine caused it. A refused candidate is never
   made active, stays in `node.xmip`, and is tried again at the next start,
   so one a passing cause refused takes once the cause is gone. Once a node
   accepts work under a configuration nothing later demotes it. Rolling
   back means signing the earlier `cluster.xmip` again, under a fresh
   serial; an older slice placed back is refused as replayed, even above
   the active configuration's serial. The alternative, refusing the whole
   start on a refusal the machine caused, was rejected: it leaves the node
   down with its recovery configuration on disk.
6. **Every node says what it runs.** `<node>/configuration` is Fine saying
   *active: serial M of save sha256:…*, or *activated: serial N of save …,
   replacing serial M of save …*; Stressed saying *candidate refused: …;
   the node runs its active configuration, serial M of save …*, or that
   the candidate runs and could not be kept. A stopped node keeps it. Every
   surface reads the snapshot, so none keeps words of its own. The
   activation is audited as `configuration`, a refused candidate as its
   failure. Point 3 of 2026-11-06 is built in part: a node says which save
   it runs; the Monitor's comparison of peers needs a structured value and
   is not built.
7. **The deployer can tell.** `xmip-service --configuration <path>
   --activation` says the node's standing in its words, from its
   publication, and exits 0 only where the slice at `<path>` is the active
   configuration. Microsoft DSC's `Xmip.Node/Slice` and Ansible's role
   `xmip_node` ask it after the restart: the node is out of its desired
   state until the shipped slice is active, and a run again restarts it.

A node that holds `<stem>.accepted.xmip` has no pin and pins the first
slice it is given; the environments deployed before this day are deployed
again. Not built: the deployment seeding the pin itself (as 2026-11-07).
