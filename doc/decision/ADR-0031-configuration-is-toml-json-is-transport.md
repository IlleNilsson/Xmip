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

