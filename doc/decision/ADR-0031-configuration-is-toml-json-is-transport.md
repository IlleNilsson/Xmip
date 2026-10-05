# ADR-0031: Configuration is TOML; JSON is transport

- Status: Accepted
- Date: 2026-09-05
- Related: ADR-0011 (module and repository naming), ADR-0030 (prefix external
  names), ADR-0028 (the Xmip Playground), ADR-0029 (observation has history),
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
deleted for `architecture.toml`, and the .NET hosts read `xmip.gui.toml` through
a TOML configuration provider rather than `appsettings.json`.

## Decision

### 1. Configuration is TOML

Everything Xmip reads its own settings from is TOML: `architecture.toml`, node
configuration, `xmip.gui.toml`, and any file that follows. There is no JSON
configuration anywhere in the estate, and none is to be added.

### 2. JSON is transport

JSON is for data in motion — content on the wire, a message body, a payload a
Contract validates. That is the case the estate keeps JSON for, and it is always
available: Xmip has to speak JSON to the world.

### 3. On disk is TOML, even for data the estate writes for itself

A file the estate persists — configuration or its own runtime data, like the
Playground's snapshot and history — is TOML. JSON is reserved for what lives in
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
an Xmip Process or a Location, and a Location's `transport`. A document
without them is refused, never completed — by `xmip-core-configure`, which
reads the one document, and so by `xmip_validate_v1` for every surface
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
each *Yes*: interaction type, and processing depth with it, sit on the
Receive Location, as `runtime-model.md` section 6 says; and audit policy
works like retention, `[audit] default` per node, overridable per Port and
per Location. The key names are the assistant's drafting.

The keys, all TOML (`runtime-model.md` section 20, *Where the runtime's
settings are configured*):

- **An Xmip Application's document.** `[[receive_ports]]` with `name`; each
  `[[receive_locations]]` names its `receive_port` (refused without one) and
  states `interaction` (`composite`, `data-transfer`, `batch-load`) and
  `depth` (`transfer`, `light`, `context`). `[[send_ports]]` gains
  `send_locations` (tried in order), `retry = { attempts, backoff }` on the
  active Location, `failover` (`next`, `none`), `execution_style`,
  `order_key` and `on_failure` (`block`, `skip`); a Sequential Send Port
  without `on_failure` is refused at startup.
- **A node's configuration.** `[[parties]]` with `name` and `identities`
  (ADR-0019), so `[receive_locations.accept] party = [...]` names them;
  `[retention] default`, overridable per Port; `[audit] default`,
  overridable per Receive or Send Port and per Location.

Each is read into the node's execution tree as it starts, like everything
else configured (the amendment above).

Built 2026-10-03, the Application's keys: an Xmip Application is a section
of the cluster's `xmip.toml` (the amendment of 2026-10-03, ADR-0064), and
`xmip-core-configure` reads its `[[receive_ports]]`, each Receive
Location's `receive_port`, `interaction` and `depth`, and each Send Port's
`send_locations`, `retry`, `failover`, `execution_style`, `order_key` and
`on_failure` (`port.rs`). A Receive Location without its Port, naming one
the Application does not declare, or without its interaction or depth,
and a Sequential Send Port without `on_failure`, are problems of the
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

## Amendment, 2026-10-03: one `xmip.toml` per cluster, sliced to each node

**Provenance.** The owner, 2026-10-03: *All these outwards, hardware
assumptions and calculations should be configurable per cluster and node.
Kept in the Cluster TOML file*; *There is one xmip.toml file per cluster.
When deployed the sections regarding a node will be sliced to that node.*

- **A cluster's configuration is one file, `xmip.toml`.** What the whole
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
  `runtime-model.md` section 10), the Storage client's timeouts and
  pass-over — under `[tuning]` for the cluster and `[nodes.<name>.tuning]`
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
against BizTalk's: *I have a nagging feeling that one want to be able to
perform all these steps on the Port & Location. Lets say you have two
Receive Locations in one Receive Port. The format on one Receive Location
may not be the same as for the other. The format shall end up as the same
in the Receive Port. The reveser goes for Send*; on Prepare, *There could be
cases where one want to prepeare on bot levles*; on Contracts, *I think that
need to go on boh places for both Receive & Send. Then the designer,
developer, end user has a posibility to place functionallity where it
belongs for the current case*; and on validation: *Contracts does not
decide wheter validation should be done or not. It is the configuration of
the Receive Port, Receive Location, Send Port and Send Location*; *there
might or might not be a contract configured. During development validation
by a contracts is default on for Receive. For Send there might or might not
be a contract configured. During development validation by a contracts is
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

## Amendment, 2026-10-05: only the cluster's `xmip.toml` is edited

**Provenance.** The owner, 2026-10-05: *node TOML files shall not be
edited, only cluster TOML files, the files are sliced / node and
distributed. […] Of course the node TOML files can be changed, but that
breaks configuration rules.*

- **The cluster's `xmip.toml` is the one configuration anyone edits** — by
  hand, in the VS Code designer or in any tool. A node's `xmip-node.toml`
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
cluster's file `xmip.gui.toml`'s `ClusterConfiguration` names, on an
overview of the cluster, and drills to a node, to artifacts by kind and to
an entry, every view and edit through `xmip_operate.h` section 10; a
node's own document is shown with the slicing's refusal and never edited.
Save writes the file, validates it, slices it per node through the new
`xmip_cluster_slices_v1` and writes each slice to
`<SliceDirectory>/<node>/xmip-node.toml`, each step audited per node; the
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
