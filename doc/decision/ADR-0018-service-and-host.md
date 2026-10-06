# ADR-0018: The Xmip Service and the Xmip Host Services

- Status: Accepted, with open questions recorded at the end
- Date: 2026-08-25
- Related: ADR-0012 (module boundary), ADR-0014 (operator surfaces),
  ADR-0024 (a claim at the endpoint; a Journey's claim through Xmip Storage,
  amendment 2026-10-01),
  ADR-0015 (amendment 2026-10-01: Xmip Storage; RocksDB always the embedded
  runtime engine),
  ADR-0052 (the operator surfaces read what `xmip-service` publishes; amendment 2026-09-30),
  ADR-0056 (amendment 2026-10-01: clause 10a's combination is the executing role)
- Read by: ADR-0027 clause 4, which makes the execution tree this record builds
  the one scope tree everything observable is addressed against

## In brief

- Theme: What Xmip is at runtime
- Subject: One Service per node, and it stays out of the message path
- Name: The Service and the Host Services
- Order: 5
- Concepts: Host Service; Service, the Xmip Service

The Xmip Service is the master and the only thing the operating system starts.
It reads the node configuration, builds and validates the execution tree, then
supervises the Xmip Host Services. **No Stream, Message or Journey passes
through it.** It loads no Modules and executes no Extensions.

## Context

`terminology.md` defined System Process, Host Process, Xmip Process and Xmip
Subprocess. It never defined **Xmip Service**, which is the term carrying the
whole runtime model — used twice in passing and specified nowhere. Two people
reading the same documents disagreed about which way the containment ran, and
the code implemented one reading while the manifest descriptions implied the
other.

BizTalk is the reference and the warning. Its Host Instances are Windows
services, which is right: they are long-running, the operator starts and stops
them, and the service manager supervises them. They were all called
`BTSNTSvc.exe` and named `BTSSvc$BizTalkServerApplication`, which told an
operator nothing about which one was doing FTP and which was running
orchestrations. Diagnosis required opening the Administration Console.

## Decision

**1. The Xmip Service is the master. One per node.** The operating system
starts it and nothing else. It reads the node's configuration, builds and
validates the execution tree, then registers, starts and supervises the Xmip
Host Services.

**2. The Xmip Service is never in the message path.** No Stream, no Message, no
Journey passes through it. It loads no Modules and executes no Extensions. Same
principle as ADR-0014 clause 4 holds for observation, and for the same reason.

**3. An Xmip Host Service is a long-running service, not a child process.**
Registered with the service manager, started and stopped by name, supervised by
the operating system. Many per node. Each hosts its configured Modules and does
the work: Receive Locations, Xmip Processes, Send Locations. Each holds
the claim on what it is working on, per ADR-0024 — taken at the endpoint rather
than from a lease store inside Xmip.

**4. Startup is nine phases, split between the two.**

Xmip Service:

```
1  read-configuration      the node's configuration, whole
2  build-execution-tree    what this node is supposed to be
3  validate-startup        fail here, before anything is registered or started
4  plan-host-services      which Host Services, with what character and Modules
5  start-host-services     register what is missing, start in configured order
```

Xmip Host Service, each within itself:

```
6  load-modules            its own Modules, ABI-verified per ADR-0012
7  register-capabilities   into its capability registry
8  verify-extensions       verified, not loaded
9  accept-work             Receive Locations poll, Send Locations ready,
                           Xmip Processes runnable
```

Phase 3 is the gate. The master proves the whole node's configuration coherent
before registering or starting anything, so a bad configuration fails as one
clear error rather than as four half-started services.

**5. Losing the master must not stop the node.** The Xmip Service is a
supervisor, not a participant. When it dies, Host Services keep receiving,
processing and sending, and keep their claims — which are held at the endpoint
and owe the master nothing. What is lost is supervision and reconfiguration, not
work.

**6. The master re-attaches; it does not re-spawn.** On restart it enumerates
the services it registered, adopts those already running, and starts only what
is missing. Because Host Services are registered services rather than child
processes, the service manager already holds this state and Xmip does not need
to keep its own record of what it started.

**7. The service name is composed from configuration, and Xmip guarantees it is
legal.**

```toml
[default.host]
serviceNamePattern   = "xmip-host-{host}"
serviceNameSanitiser = "[^a-z0-9-]"
```

Variables: `{host}` `{cluster}` `{node}` `{id}` `{trust}` `{bitness}`
`{latency}` `{index}`. The template composes, the sanitizer regex replaces what
is not legal, and a validator that Xmip owns — not the operator — checks the
result against the platform's rules. An operator who could configure the
validator could configure a name that registers on Windows and fails on Linux,
and find out in production.

**8. An unnamed host falls back to its identifier, which lives in
configuration.** A GUID minted at spawn time changes on every restart and
traces to nothing. A GUID assigned when the host is declared is stable and
matches back by construction:

```toml
[host.orders]
id = "3f2a9c14-8d51-4b0e-a6f7-1c2d3e4f5a6b"
description = "Order intake and EDI translation"
```

**9. The description always carries the readable identity.** Whatever the
service is called, the description names the host and says what it does, so a
service list stays diagnosable even when the name is a GUID:

```
xmip-host-orders    Xmip Host Service 'orders' — Order intake and EDI
                    translation, 12 Modules, trusted, 64-bit
```

Where the operator has written a description, that is used. Where nobody has,
one is generated: module count, character, and which of Receive, Process and
Send this host actually does. Three facts an operator can act on, rather than a
list of forty Modules nobody will read.

**10. Every Host Service runs the same executable, so the command line carries
the host.** `xmip host --host orders` (one executable with a `host` subcommand,
as `registration.rs` invokes it — not a separate `xmip-host` binary). Otherwise
`ps` and Task Manager show identical entries and the BizTalk complaint returns
intact.

**10a. Latency is bought with isolation, and the currency is process hops.** A
Journey whose receive, process and send all run in one Host Service crosses no
process boundary. Split across three Host Services it pays serialization, a
copy and a context switch at every hop, and it is no longer low latency
whatever anybody labels it.

So there is no `low_latency` flag on a Host Service and no `low_latency_capable`
on a Module. Neither was ever a property of the thing it was attached to. What
exists instead is the role combination already in
`runtime-roles-and-isolation.md`: a host configured as Reader, Executor *and*
Writer runs a whole Journey without a hop, and a host configured as Reader only
cannot.

The trade is real and belongs to the operator, not to a boolean. One Host
Service doing everything is the fastest and shares a process between an
untrusted transport and the routing it feeds. Three Host Services isolate that
and cost three hops. Which is right depends on the workload, which is why
BizTalk separated hosts by workload in the first place.

**11. Supervision is `xmip-core-resilience`, by configuration.** Restarting a
dead Host Service is retry with backoff. Giving up and reporting the node
degraded is a circuit breaker. Waiting for drain is a timeout. Not restarting
six at once is a bulkhead. A Host Service that will not start at all is a
fallback. No new concept: the primitives already exist, applied to services
instead of to messages.

**12. Shutdown drains.**

```
drain      the master tells Host Services to stop accepting new work
finish     in-flight Journeys complete or checkpoint
release    claims released at the endpoint explicitly, not left to expire
exit       Host Services stop, the master stops last
```

**13. Configuration that no longer names a Host Service is reconciled.** A host
renamed or removed leaves a registered service behind. The master drains and
deregisters services it registered that configuration no longer names,
otherwise the service list accumulates ghosts and an operator cannot tell a
live host from a dead one.

## Consequences

- `xmip-core-service` and `xmip-core-host` are not separate repositories. Both
  are modules inside `xmip-core-runtime`, which already owns `ExecutionTree`,
  `StartupValidationReport`, `HostProcessPlan` and `HostBitness`. Ten kilobytes
  that always change together do not need three repositories, three CI
  pipelines and three submodule mounts.
- `xmip-core-runtime` depends on `xmip-core-configure` and
  `xmip-core-resilience`. Platform on Platform, still acyclic.
- The crate layering `xmip-service → xmip-host → xmip-runtime` is correct and
  survives the fold as module layering inside one crate.
- `terminology.md` gains **Xmip Service** and **Xmip Host Service**, and
  **Host Process** is narrowed to the System Process a Host Service runs as.

## Open

**Registration needs elevation.** Creating a Windows service requires
administrator; writing a systemd unit and reloading requires root. Proposed,
not yet accepted: the master runs elevated and the Host Services run under
configured least-privilege accounts. The master is small, loads no Modules and
is not in the message path; all untrusted code is in the children. That is how
IIS, systemd and SQL Server are arranged. The alternative is a small privileged
helper, which is safer on paper and one more thing to install and get wrong.

**An operator stopping a Host Service.** Proposed, not yet accepted: respect
it and report the divergence rather than restarting. If the master overrides a
deliberate stop, nobody can take a host out of service to investigate, which is
a daily operational need. BizTalk leaves it alone.

**What the spawn plan depends on beyond the node's own configuration.** Cluster
membership, node role, capability and load may all bear on which Host Services
a given node should run. Deferred deliberately: the node-local case is settled
and sufficient to build against, and the cluster-wide case needs its own
decision rather than an assumption made here.

## Amendment, 2026-09-06: phases 4-5 renamed to host-services

The startup phases 4 and 5 were named `plan-system-processes` /
`start-system-processes`, and the code mirrored them
(`StartupPhase::PlanSystemProcesses`, `XmipServiceState::ReadyToStartSystemProcesses`).
That carried the exact "Process" overload the owner flagged: terminology.md is
explicit that a Host Service is **not** a System Process (a Host Process is the
operating-system process a Host Service runs as). ADR-0035 settled that
terminology.md arbitrates such a collision, so the phases are renamed to
`plan-host-services` / `start-host-services` — they plan and start **Host
Services**, which is what phase 3's tree already validated. The state and phase
enums in `service.rs` were renamed to match. No behavior changed; the names now
say what the phases do.

## Amendment, 2026-09-26: the executable is the estate root's

The Xmip Service had no executable. The owner, 2026-09-26, chose from two
(the root `xmip` crate, or a new repository): **the root crate.** `xmip-service`
is a binary of the estate's root crate, the assembly that already carries the
modules' features; it links the technologies a deployment needs by
build feature, because `xmip-core-runtime`, a Platform crate, may depend on
no technology. The runtime stays a library the binary drives.

## Amendment, 2026-09-28: the nine phases run

The owner, 2026-09-28: *The runtime starts on a node, loading all modules
needed to work according to dependencies and configuration.*
`xmip-core-runtime`'s `running::Running::start` runs clause 4's nine phases
over a node's configuration and the technologies the program starting it
linked (`linked::Linked`): phases 1 to 3 read, build and validate — every
Location held to its technology's settings declaration, and a transport, an
accepted mechanism or a filter name the program was not built with refused
there; phase 4 plans the Host Services the started Modules need
(`host::plan`, one host-type rule); phase 5 starts the one this process is,
the in-process host, and refuses a Module needing a Host Process of its own,
which nothing spawns yet; phase 6 loads each technology the configuration
names once and opens each started library once (ADR-0025, ADR-0057); phase
7 registers each capability once; phase 8 is the execution tree's; phase 9
builds each Location's transport once and serves every Receive Location on
a thread of its own. `Running::stop` is clause 12 for one process: drain
(each Receive Location takes nothing more once its current receive
returns), finish (what it took is carried whole), release (transports and
Modules let go), exit.

What is not built: the master supervising Host Processes, registration
(`registration.rs` generates what a service manager is told, and nothing
applies it), and the executable the amendment of 2026-09-26 decides —
`xmip-service` in the root crate — so the program starting a node today is
the runtime's own test. `service.rs` keeps the phase names; the plan type
and the service state that restated phases 1 to 3 are deleted, and
`start::start`, what `xmip_start_v1` runs, is those three phases alone.

## Amendment, 2026-09-28: `xmip-service` runs a node on all three platforms

The owner, 2026-09-28: *the runtime starts on Windows, Linux and OS X. So the
equivalent for all three OSes.* `xmip-service` is built in the estate root
crate (`.src/service/`), as the amendment of 2026-09-26 decided:

```text
xmip-service --configuration <path> [--console] [--purpose test|runtime]
xmip-service --configuration <path> --definition
```

It calls `Running::start` with the technologies its build linked: the
transports its site's domains serve, of `file`, `http`, `tcp` and `udp`,
each a feature of the root crate (ADR-0015, amendment 2026-10-01). It serves
until a stop arrives and then calls `Running::stop`, which is clause 12's
drain for one process, and exits 0. Every stop arrives on one channel and is
the same drain:

- **Windows**: the Service Control Manager's Stop or Shutdown (the
  `windows-service` crate's dispatcher and control handler). The service
  reports start pending, running once the node accepts work, stop pending
  and stopped.
- **Linux, as a systemd unit, and macOS, as a launchd daemon**: SIGTERM,
  which is how both stop a service. The unit is `Type=notify`, and systemd
  hears `READY=1` once phase 9 accepts work and `STOPPING=1` when the drain
  begins.
- **A console, `--console`, on every platform**: Ctrl+C, and on Linux and
  macOS SIGTERM and SIGHUP as well (the `ctrlc` crate).

A node it cannot start is refused in words with exit code 2
(`registration::REFUSED`). The unit carries `RestartPreventExitStatus=2`,
so a service manager does not restart a configuration that will still be
wrong. Nothing in Xmip restarts anything; the service manager owns restarts.
The process declares itself as `xmip:///<cluster>/node/<node>` (ADR-0053)
and audits its start, its stop with whoever stopped it, how long the drain
took, what became of every Stream, and every failure (ADR-0062).
`--definition` prints what `registration.rs` generates for this platform, so
an installer registers what the runtime writes rather than a copy of it.
Registering remains the installer's job, and elevation remains open.

A test in the root crate (`.src/test/service/stop.rs`) starts it in a
console over loopback, carries Messages to it, sends Ctrl+C on Windows and
SIGTERM on Linux, and holds the drain, exit code 0 and the audit to a bound.
The Service Control Manager's controls are tested at the handler.
macOS compiles by `cfg` and has not been run.

What it cannot do yet: the build links no authenticator, policy or
identifier, because a node configuration cannot yet say how one is set up.
A Receive Location that accepts nothing therefore refuses every Stream at
its gate. The node receives and counts every Message, and carries none
onward until the configuration can name its gates.

## Amendment, 2026-09-30: `xmip-service` opens the node's runtime store

Since the amendment of 2026-09-30 to ADR-0013 a paused Subscription holds
what it matches in the runtime store, so the pause and what it holds survive
a restart. `xmip-service` opened no store: no node configuration could name
one, and a node it ran held in memory for its own life. Now:

- **The configuration names the store** in `[store]`
  (`xmip-core-configure`'s `store.rs`, `node-configuration.md`): `engine`
  and `key_store` by module name, as a Location names its transport, and
  `place` and `keys`, where each keeps its bytes, relative to the
  configuration file. Every key may be left out. The defaults follow the
  records: the engine is `xmip-core-persist-rocksdb`, the runtime store's
  (ADR-0015, amendment 2026-09-25), at `<data>/persistence-rocksdb`, the
  installed layout's (`deployment-model.md` section 6); the key store is the
  platform's (ADR-0063 clause 4) — `xmip-core-secret-dpapi` on Windows,
  `-keychain` on macOS, `-file` on every other Unix — keeping its keys at
  `<data>/key`, under the key-encryption key `runtime`. `<data>` is the
  node's data directory, `[service] data`, relative to the configuration
  file and `../data` when absent: in the installed layout (ADR-0015 clause
  10) the `data` beside the `config` the file is in. An engine other than
  the default names its `place`, since a default place is the default
  engine's.
- **The runtime opens it** (`xmip-core-runtime`'s `store.rs`). The program
  links engines and key stores as it links transports (`Linked::engines`,
  `Linked::key_stores`); phase 3 refuses a `[store]` naming one the program
  was not built with, and phase 9 opens persist's `EncryptedStore` over the
  engine and refuses a store that does not open — its directory, the
  engine's lock held by another process, a key that does not unwrap —
  before anything serves. A program that linked no engine, starting a node
  that names no store, holds in memory as before; a program that opened a
  store itself (the Playground) hands it over and that one is the node's.
- **`xmip-service` links them by build feature**: `persist-rocksdb` for a
  server or hosted site, `persist-sqlite` for an edge or computer site
  (ADR-0015, amendment 2026-10-01), and with either the
  platform's key store. A refused store is the refusal every node that
  cannot start gets: words on stderr, exit 2 (`registration::REFUSED`), and
  the failure audited (ADR-0062). The start record says the store, and the
  console says where it is.
- **It takes orders.** An operator's pause or resume of a Subscription
  reaches the service as an `observe::Order` left in `<data>/orders`, which
  the service declares (ADR-0053, `orders`) and looks in between its waits
  for a stop, every ten milliseconds; each is applied through the runtime's
  act (`Pickup::act`), audited as `subscription.pause` or
  `subscription.resume`, and said on the console. An order for an Event
  subscription is refused in words: this process keeps no hub.

The root crate's test starts the service over a configured store, pauses a
Subscription by an order, stops it the operating system's way, starts it
again, and hears the Subscription answer a second pause as already paused;
a store naming an engine the build left out, and one that does not open,
are refused with exit 2. What the pause held is not seen there: the build
links no authenticator, so every Stream is refused at its gate before
routing (the amendment of 2026-09-28), and that a held Message survives a
restart is proved where Streams route, in the runtime's `pickup` and the
Playground.

Provenance: the owner, 2026-09-30, *Sort what you can*, after the gap was
reported. The keys, their defaults, the data directory, the order place and
the look of ten milliseconds are the assistant's drafting from the records
named, for the owner to overrule.

## Amendment, 2026-09-30: `xmip-service` publishes its node

`xmip-service` ran a node, kept its store and took its orders, and published
nothing: no operation surface could see a real node — its Monitor, its
Topology, its Subscriptions — and a surface had nowhere to read where to
leave a pause. Only the Playground's rolls published. Now the service
publishes its node through the one publication there is (ADR-0052;
`observe::Publication`, ADR-0027):

- **What.** The runtime says what a running node is
  (`xmip-core-runtime`'s `Running::publication`, `running/publication.rs`):
  records beneath its location — itself, its System Process alive, what it
  declares at `capability` (ADR-0056: receive where a Receive Location
  starts, process where a Subscription routes, send where a Send Port
  starts), each module loaded, each Location, each Subscription Fine or
  Paused by whom — the figures its tally counted at the stage that counts
  each kind (Streams at receive, Journeys at process, Messages at send, and
  what failed at the node), its Subscriptions with their standing, and the
  node drawn as a topology. The drawing is `observe::topology::draw` and
  `party`, the one every publisher calls, moved there from the Playground
  (ADR-0052, amendment of this date). A node's configuration names no Party
  yet, so the Party on each side is drawn as `any-party`.
- **Where.** `<data>/snapshot.toml`, beside `<data>/orders`, in the node's
  data directory, and the publication's `orders` names that directory, so
  a surface leaves a pause where the node takes it. The service declares the
  file (ADR-0053, `snapshot`); `Get-XmipProcess` lists it as `Snapshot`, and
  `Start-XmipOperationWeb` binds it by name, so an operator opens the web
  over a node with
  `Get-XmipProcess -Name 'xmip-service*' | Start-XmipOperationWeb`, or with
  `Start-XmipOperationWeb -Snapshot <data>/snapshot.toml`.
- **How.** Whole or not at all: `observe::publication::write_atomic`, the
  one writer, moved there from the Playground, which calls it too.
- **When.** As the node starts to accept work; at the look after an order
  was applied, so a pause shows in the next publication, not a round later;
  otherwise every quarter of a second, the Playground's round. Once more
  after the drain, saying the node stopped — the node, its System Process,
  its modules and its Locations Done, what it declared and its
  Subscriptions' standing kept (`running::publication::stopped`) — so a
  surface over the file shows a stopped node, never a running one that went
  quiet. It is written on the service's own thread between its looks for a
  stop; no Receive Location, routing or departure waits for it. A write a
  reader refuses for the instant it reads — Windows refuses a rename over a
  file open without delete sharing — is asked again at the next look; one
  still refused a round later is audited as the failure to `publish`, once,
  not at every round (ADR-0062).

The root crate's test (`.src/test/service/publication.rs`) starts the
service over loopback with a store and a Subscription, reads the snapshot
where the service declares it through observe's reader — the function the
runtime's library forwards to every .NET surface
(`xmip_publication_read_v1`) — carries Messages and sees them counted, leaves
a pause where the publication says as a surface does, sees the next
publication say paused within a quarter of a second, and after the stop
reads the node Done and the pause standing.

What it does not do: it writes no history or activity beside the snapshot,
so the Monitor's curves and recent activity over a service node are empty;
and two nodes of one cluster are two publications of one cluster, which a
web host refuses to hold at once (ADR-0052, amendment 2026-09-19).

Provenance: the gap, reported on 2026-09-30, is sorted under the owner's
*Sort what you can* of that day. The file's name and place,
the quarter-second cadence, the publication at an order and at the stop,
`any-party`, and the figures' stages are the assistant's drafting from the
records named, for the owner to overrule.

## Amendment, 2026-10-01: the combination in clause 10a is the executing role

Clause 10a says a host configured as Reader, Executor *and* Writer runs a
whole Journey without a hop. Those three words were `deployment-model.md`
section 3's, and the owner, 2026-10-01, gave the node one vocabulary: *Leave
Executing as a sum of Receiving, Processing and Sending. Executing would be
used for Low Latency.* The combination clause 10a describes is now named:
**executing**, a node role (`node::NodeRole`, ADR-0056, amendment
2026-10-01) — receiving, processing and sending in one process. A node that
declares only one of the three hands every Journey on to another process, and
pays the hops this clause prices. Still no `low_latency` flag: the role is the
choice, and the trade stays the operator's. The clause's reasoning stands;
only the names changed.

## Amendment, 2026-10-01: pools per step, the Ledger, and claims through Xmip Storage

**Provenance.** The owner, 2026-10-01, validated part by part with the
assistant, and re-decided for storage later the same day; his words are
quoted where they decided.

**Threads, not fibers.** The owner asked *What about using Fibers instead of
Threads?*; threads were agreed, fibers to be revisited only if measurement
shows thread switching dominating.

**A Host Service runs a dynamic, bounded pool per step** (the owner: *Go with
the dynamic, bounded pool*): a bounded pool of I/O threads per Receive
Location, routing inside it (amendment 2026-10-03), a pool for the
Xmip Process step, a Send pool. A
CPU-bound step's pool is capped at the core count. An I/O-bound step's pool
grows while work waits, up to a configured maximum — the bulkhead of clause
11 — never below one thread, and shrinks after a configured idle time.
Threads are started ahead of need, never per Message. Steps hand on through
the Ledger, serialized through Xmip Storage and deserialized by the next
step's thread (the owner: *every sub action starts a new thread, in between
the stream shall be serialized and then on every sub a new thread
deserializes the message from RocksDB* — realized as pools, which he
accepted). A waiting Xmip Process and a retry waiting for its backoff hold
no thread; their state and due time are in the Ledger. A Stream is written
in chunks sized from the memory available, never whole in memory
(`runtime-model.md` section 3).

**Clause 10a's executing role** — receiving, processing and sending in one
Host Service for low latency — is the amendment of 2026-10-01 above.

**Every Ledger write counts only once the database has it durably** (the
owner: *Safe way*), the hand-ons between steps included: behind a database
server its commit, on the embedded Storage node a sync to disk, where group
commit lets concurrent writes share one sync.

**Clause 3's claim, for a Journey, is taken through Xmip Storage**, not at an
endpoint: a conditional update in the database behind it — set the owner
where the owner is empty or lapsed — time-limited and renewed while the work
runs (ADR-0024, amendment of this date). Clause 3 stands for arrivals, whose
claim is the endpoint's.

**Clause 5, sharpened.** The Xmip Service dying stops no work, as before. A
Host Service dying stops renewing its claims; they lapse, and any capable
node resumes from the last finished step. A Storage node dying stops no work
while another is left, every node reaching the next round robin; the
database server's failover is IT's, and an embedded Storage node has none
(`deployment-model.md` section 9).

**Clause 12, sharpened.** Every hand-on is one atomic write — the result, the
next Journey and the claim released together. On start a Host Service starts
its pools, finds lapsed work, restores checkpoints, resumes or keeps waiting,
and continues the audit. Shutdown drains and gives its claims back
explicitly — *release* in clause 12 — rather than leaving them to lapse.

**The store's engine is no longer a choice.** The amendment of 2026-09-30
named the engine in `[store] engine`, defaulting to RocksDB and allowing
SQLite, with `persist-sqlite` built for an edge or computer site. That choice
is superseded: a node calls Xmip Storage and opens no database of its own;
an embedded Storage node's runtime database is always RocksDB, with SQLite
as its administration database (ADR-0015, amendment of this date). A
Storage node under test keeps its administration database in SQLite in
memory and its runtime database in RocksDB on disk in the test's directory
(the owner: *for testing purposes the Xmip Nodes of Storage type can use
SQLite in memory for administration and RocksDB for runtime*).

**Configuration is TOML, read as a Host Service starts; the Subscriptions
are shared through Xmip Storage** (the owner, 2026-10-02: *Routes are
defined in TOML, read into Storage at Xmip Host Service startup, read from
Storage when needed and kept in memory until "not used for a while"*, and
*They are shared*). Each node reads its TOML configuration as it starts and
holds its Locations, Xmip Processes and Send Ports as its **execution
tree**, which `build_execution_tree` in `xmip-core-runtime` builds. Its
Subscriptions it writes into Xmip Storage's administration database, so any
node with a routing role routes a Message another node received; routing
reads them from Xmip Storage when it needs them, compiles their filters and
keeps them in memory until they have not been used for a while. The
operation tools and editors change the TOML file, never a database, and a
changed TOML file takes effect when the Host Service that reads it is
started again, never mid-flight (ADR-0031, amendments 2026-10-01 and
2026-10-02). So a Host Service takes up a
changed configuration only when it is started again, under clause 6's reattach and clause 13's
reconciliation; nothing changes beneath work in flight.

**A node finds its Storage nodes from its TOML** (the owner, 2026-10-01,
asked whether a node should find them from a list of their addresses in its
TOML, tried round robin: *Yes*): the node's configuration lists their
addresses, for example
`[storage] nodes = ["storage-1.example:7443", "storage-2.example:7443"]`, and
the node tries them round robin. This closes the question this amendment had left open; the node
configuration's document follows in the build. The code follows this
record.

## Amendment, 2026-10-03: no routing pool

Routing runs inside the receive cycle, on the Receive Location's pool, before
the sender is acknowledged (the owner, 2026-10-03: *Go with A*; ADR-0013,
amendment of this date). The amendment of 2026-10-01 named a routing pool
among the pools per step; there is none. The pools are one per Receive
Location, one for the Xmip Process step and one for send.

## Amendment, 2026-10-05: another runtime runs out of process

The owner, 2026-10-05, asked whether an Xmip Process should run in a
process engine on another runtime: *Xmip Service or Xmip Hosts does not run
other runtimes inhouse, they run outhouse. I know that is a performance
penalty but that is what it takes. The only runtime, for now that I'd
considder taking inprocess is dotnet. We will see, we can have a
configurable switch. InProcess = true | false*

- No Xmip Service or Xmip Host Service loads another language runtime — a
  JVM, a Go or Node runtime — into its own process. Such a runtime runs in
  a process of its own beside it, and Xmip talks to it out of process (over
  gRPC on a named pipe on one machine, on TCP between machines; ADR-0052,
  amendment 2026-10-05). The cost in speed is accepted.
- **Rust runs on threads within the Xmip Host Process; .NET is invited
  unless excluded; every other runtime is invited only by configuration.**
  The owner, the same day: *Read it as InProcess with threads is default
  true, any other runtime has to be opt in by configuration*; *As long as
  they are on the peremiter the are within Xmip Processes, otherwise they
  have to be exclusivley invited. I do not like JVM or dotnet Runtime within
  our perfect Rust code*; and, correcting the assistant's reading: *I said
  that dotnet runtime was invited unless excluded.* So `InProcess`
  defaults to `true`, and .NET runs on threads within the Xmip Host Process
  unless configuration sets it `false`; a JVM, Go, Python or any other
  runtime is never loaded into an Xmip process unless configuration
  explicitly invites it. Where `InProcess` lives is not decided.
- A program in another language at the perimeter — one that calls Xmip
  from outside, an Event subscriber among them — is its own process and
  needs no invitation.

## Amendment, 2026-10-06: every process is a process

The owner agreed the process vocabulary anew on 2026-10-06. Four terms, each
a process:

- **Xmip Service** — the main service on each node.
- **Xmip Host Service** — loaded according to configuration to carry out
  work on incoming, executing and outgoing payload.
- **Xmip Host Subprocess** — for things we do not want to execute within an
  Xmip Host Service. It spawns with a name of its parent's name, a dash and
  something readable but short (ADR-0053, amendment 2026-10-06).
- **Xmip Work Process** — a process that does work the designer, developer
  or end user has defined; it may run in-process of an Xmip Host Service or
  an Xmip Host Subprocess. The owner: *In this case it means a Process that
  does work that the designer, developer or end user has defined.* The
  name is his, correcting a draft that wrote Worker the same day: *I
  requested Xmip Work Process*.

What follows from it:

- The Xmip Work Process is what this record and the estate called an
  Xmip Process: the integration process defined by configuration and artifacts.
  "Xmip Process" names nothing any more; a node's `[[xmip_processes]]` is
  `[[work_processes]]`, and every type, symbol, command word and label
  follows (`WorkProcessConfiguration`, `WorkProcess`, `work-process`).
- The **Xmip Subprocess**, a configured child part of an Xmip Process
  (`xmip_subprocesses`), is deleted with every use, its type, its validation
  and its tests. Pre-GA it is deleted, never deprecated (CONTRIBUTING).
- The **Host Process**, the System Process a Host Service runs as, goes:
  the Host Service is the process.

Nothing spawns an Xmip Host Subprocess yet
([decided, not built](../architecture/estate-map.md#host-subprocess)).
`doc/terminology.md` carries the four terms.

## Amendment, 2026-10-06: a Publication is written once, and a lost claim stops its work

A review whose findings the owner approved for repair on 2026-10-06 found
two holes in the amendment of 2026-10-01 — *every hand-on is one atomic
write* and *renewed while the work runs* — where an answer was lost or
dropped.

**Clause 12's atomic writes include the Publication, once.** A Publication
is known by its Message. Its one write keeps, with the rest, that it was
written and the digest of what was asked; asked again — a node's request
repeated after its answer was lost — it writes nothing and answers the
claims of it its node still holds, and the node sends only those. Until
then a repeated Publication wrote its Journeys again, so one another node
had completed meanwhile was reset, queued again and sent a second time.
Another Publication of the same Message is refused; publishing a business
Message again stays what it was, another Message with an identifier of its
own (ADR-0013 clause 4c).

**Clause 5's renewal is answered, and its answer obeyed.** A renewal that
finds the claim another's ends the work there: no further attempt is made
from this node and nothing is written for it, the loss counted and
audited. A renewal Xmip Storage does not answer leaves the claim
unconfirmed, and its Send Port is Done from the first unanswered renewal,
its evidence naming Xmip Storage as what did not answer and since when — the
owner, 2026-10-06: *Storage is not here is a flat-out error* — on every
surface while it lasts; the window that follows bounds attempts and softens
no mood: the node goes on only
while a lease from the request that last confirmed the claim lasts, on its
own clock, never comparing it with the Storage node's, and past it presumes
the claim lost, audits it once and attempts nothing more until a renewal
is answered. An external operation already under way is not called back:
it carries the Journey's identifier, the transports' deduplication key, so
the delivery semantics of `runtime-model.md` section 15 stand — exactly once
where the far end deduplicates, at least once elsewhere, never at most once.

`runtime-model.md` section 9 and section 10, *Corrected 2026-10-06*, say
how each runs; `xmip-core-persist` (`storage::publication`) and
`xmip-core-runtime` (`send_step::renewal`) hold them.
