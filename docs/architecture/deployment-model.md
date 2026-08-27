# Xmip deployment model

Where Xmip runs, what it runs as, how it is installed, and how it recovers.

This replaces `deployment-profiles.md`, `runtime-profiles.md`,
`runtime-roles-and-isolation.md`, `installer.md`, `service-identities.md`,
`desired-state-configuration.md`, `database-selection.md` and
`disaster-recovery.md` — eight documents, two of which described the same two
databases in almost the same words.

## 1. The deployment range

```text
IoT device            Cloud node
Edge node             Cloud cluster
Single on-prem server Hybrid on-prem/cloud
On-prem cluster
```

**The runtime semantics are identical on all of them.** What varies is which
Modules are loaded, which persistence and observability providers are
configured, and which cluster capabilities exist. A profile is a packaging and
configuration choice, never a different product.

The laws that hold everywhere:

- A Receive Location is where Xmip starts working.
- A Receive Port binds incoming Streams into the topology and creates Messages.
- Format detection precedes deserialization; deserialization precedes promotion.
- Promoted properties drive publication and Subscription matching.
- Process and delivery paths are Subscription-driven.
- A Send Port resolves to Send Locations.
- Preservation, lineage, checkpoints and recovery span the runtime.

`runtime-model.md` owns those; they are repeated here because the profiles are
where people expect them to be negotiable, and they are not.

### Build targets

The range above is where Xmip is deployed. This is what it is compiled for:

| Target | Notes |
| --- | --- |
| Windows x64 | |
| Linux x64 | |
| macOS, Apple silicon and x64 | developer machines primarily |
| Linux ARM64 | Raspberry Pi class and upward, and most edge hardware |
| Industrial and defence hardware | the constrained case; see below |

ARM and the industrial targets are the two that change decisions rather than
just adding a build. Both push toward the purpose-compiled runtime of section 2
rather than the dynamic one: an edge device with 512 MB of RAM does not want a
Module loader and a TOML parser it will never use, and a defence deployment
frequently cannot accept a runtime that loads code at all.

**This is a breadth statement, not a currency one.** ADR-0021 governs which
*versions* of a platform Xmip tracks and says to track the current one.
Nothing here reopens that: an ARM64 build is a current Rust stable build for a
different architecture, and Xmip integrating with hardware from the 1970s over
Modbus still does not mean Xmip runs on it.

Recovered from the `_origins` design export, 2026-08-26. The target list existed
nowhere else, and ARM and industrial hardware are exactly the two nobody adds
retroactively without regret.

## 2. Two ways to build the runtime

**Server runtime** — the full runtime. Dynamic Modules, TOML configuration,
receive and send, process execution, Subscription matching, audit, tracing,
persistence, clustering, management, updates and deployment tooling. It
discovers and loads Modules on demand.

**Purpose-compiled runtime** — a smaller build for one target: an endpoint
collector, an industrial gateway, a CAN bus bridge, a telemetry forwarder, a
field-site agent, a locked-down appliance, an air-gapped node. It may **link
selected Modules statically** instead of loading them.

That is allowed where the target benefits from a smaller footprint, fewer
files, simpler installation, stricter security, constrained hardware, offline
deployment or deterministic behaviour.

```text
Profile selection happens at build and packaging time.
Runtime profiles are not git branches.
```

A purpose-compiled runtime still behaves according to Xmip Definitions and
runtime contracts. **Purpose compilation is a packaging strategy, not an
alternative to modularity** — and a small device must never be forced to carry
the full server footprint to get correct semantics.

Two Rust rules that belong here rather than in a style guide: stages pass
**owned** work to each other rather than sharing mutable message state, and
blocking Handler work must never block a latency-sensitive runtime loop.

## 3. Runtime roles

Three roles, deliberately few:

| Role | May | Examples |
| --- | --- | --- |
| **Executor** | run Artifact Instances and do Xmip work | receive, deserialize, transform, promote, publish, process, serialize, send |
| **Reader** | inspect runtime state | Message Context, artifact state, lineage, logs, metrics, health, publication history, Subscription Instance history |
| **Writer** | change runtime state or operational outcome | claim work, checkpoint, preserve, acknowledge, retry, resume, suspend, terminate, move a Message, change operational state |

Roles combine per deployment:

```text
Edge node          Executor + Reader + Writer
Monitor component  Reader
Recovery component Reader + Writer + Executor
Cloud worker       Executor + Writer
```

These are deployment choices, not separate runtime models. The combination is
also what buys latency: a Host Service that is Reader, Executor *and* Writer
runs a whole Journey without a process hop, per ADR-0018 clause 10a.

**Do not create a role per capability.** Receive host, send host, process host,
preservation host, recovery coordinator and cluster coordinator are
capabilities or operational responsibilities. They are implemented by Artifact
Instances, Modules or profiles, and they do not extend the role model.

Runtime roles are also **not human roles**. Monitorer, Operator, Developer,
Administrator and Architect are people. A scoped human role such as Edge
Operator is a scoped Operator, not a new universal role. ADR-0009 is the general
statement of this; here it applies to deployment.

## 4. Trust and isolation

Roles alone do not contain a compromised Module. Three questions, three
different answers:

```text
runtime role       what may this component do?
trust boundary     what may it touch?
isolation boundary what can it infect if compromised?
```

> Executor is not one trust level. Executor is scoped by isolation boundary.

The rules:

1. A Reader cannot execute artifact behaviour.
2. A Writer cannot load arbitrary Module code.
3. An Executor cannot automatically affect another Executor.
4. Untrusted Modules run isolated — separate process, container or sandbox.
5. Artifact Instances share process memory only inside an explicit trust
   boundary.
6. Inbound and outbound permissions are explicit.
7. Edge deployments use the smallest practical permission and isolation
   footprint.

### Security profiles

The seven rules above describe mechanisms. A **security profile** says how
strictly an estate applies them, and is declared once per cluster.

| Profile | For | Means |
| --- | --- | --- |
| `standard` | small estates, internal traffic | process isolation per identity context; violations block startup |
| `enterprise` | multi-tenant or partner-facing | the above, plus mandatory Service Identity separation per runtime role |
| `regulated` | government, defence, healthcare, finance | the above, plus node-level isolation for `highAssurance` identity contexts, fail-closed everywhere, and mandatory compliance reporting |

Three properties are worth stating plainly, because each is a place a profile
system usually goes soft:

**A profile only tightens.** There is no profile that relaxes a rule, and no
setting that switches one off. `standard` is the floor and it already blocks
startup on an identity-isolation violation (ADR-0022 clause 5). The profiles
above it add constraints; none removes one.

**Fail-closed is what `regulated` buys.** Where a lower profile may degrade —
an unreachable audit sink, a certificate that cannot be checked right now — the
regulated profile stops. An estate that selects `regulated` has decided that not
running is preferable to running unobserved, and the runtime must be able to act
on that decision rather than log its regret.

**The profile is declared, not inferred.** Xmip does not guess that an estate is
regulated because it sees Kerberos. Recovered from the `_origins` design export,
2026-08-26; the source called this out and it is right — an inferred security
posture is one nobody has agreed to.

## 5. Service Identity

Xmip needs a platform-neutral name for the non-human identities its components
run as. Windows Managed Service Accounts are a good model and are not portable,
so the architectural term is **Service Identity**.

A Service Identity answers two questions:

```text
what identity is this runtime component running as?
what is it allowed to access?
```

**Xmip does not impose one account model.** Each platform realises Service
Identity natively:

| Platform | Realisation |
| --- | --- |
| Windows | Managed Service Account, group MSA, domain or local service account |
| Linux | dedicated service user, systemd user, LDAP-backed identity, Kerberos principal |
| Containers, Kubernetes | container runtime identity, service account, workload identity, mounted token |
| Cloud | managed identity, service principal, IAM role |
| Edge, embedded | device identity or provisioned certificate |

This is the operator-facing half of ADR-0019: a Service Identity is what Xmip
*is* when it acts, and a Party identity is what Xmip presents when it reaches a
counterparty. They are configured separately and confusing them grants a
transport handler the runtime's own permissions.

## 6. Installation

**Package managers first.** Windows package manager, Linux distribution
packages, macOS package manager, container image flow. Manual archive
installation may exist; it is not the preferred path.

The installer places runtime binaries, management binaries, default TOML
configuration, service definitions where the platform has them, and the two
bundled databases:

```text
xmip/
    bin/
    config/
    modules/
    data/
        persistence-rocksdb/
        management.sqlite
    logs/
```

It creates the layout, initialises both databases, installs default
configuration, and registers the Xmip Service where services exist.

## 7. Two databases, and why

| | Runtime persistence | Management |
| --- | --- | --- |
| Default engine | RocksDB-style embedded key/value | SQLite-style embedded relational |
| Optimised for | high write volume, replay from a known state | queryable administration views |
| Source of truth for | **replay** | **administration** |

**Runtime persistence** holds Messages, Stream references or payloads per
policy, correlation identifiers and history, process state, retry state, failure
state, replay checkpoints, recovery state and runtime audit records.

**Management** holds node registration, cluster membership, installed Modules,
available Handlers and Extensions, configuration versions, deployment state,
operator metadata and management audit.

They are separate databases and stay separate. Their access patterns are
opposites — one is written constantly and read by key, the other is written
rarely and queried arbitrarily — and one engine serving both serves neither.

### Record identifiers are UUIDv7

**Every record in either database is keyed by a UUIDv7**, per RFC 9562.

RFC 9562 replaced RFC 4122 in May 2024 and defines versions 6, 7 and 8. The
highest number is not the answer: **v8 is deliberately vendor-defined and
experimental**, and v6 exists to reorder v1 for legacy migration. v7 is the one
designed for this job — 48 bits of Unix millisecond timestamp in the most
significant position, then random entropy.

**The timestamp leading is the whole point, and it is not cosmetic here.** v7
values sort chronologically as raw bytes, so records written in sequence land in
sequence. Against an LSM store that is the difference between appending and
scattering: random v4 keys distribute writes across the entire keyspace, forcing
compaction to rewrite everything, while v7 keys append. The ToDo is a work
queue written constantly and read by key, which is exactly the access pattern v7
was designed for — the engine choice in the table above and this choice are the
same decision seen twice.

It also buys two things for free. A range scan over an identifier range **is** a
range scan over a time window, so "everything this node accepted between 09:00
and 09:05" needs no secondary index. And a Journey, its Messages and its Streams
sort into creation order without a separate sequence column, which is what makes
the execution history in section 3 of `runtime-model.md` readable straight from
the store.

**The choice is the same on every target OS.** Windows, Linux, macOS, ARM and
the industrial targets make no difference — UUID generation is a library
concern, and the Rust `uuid` crate emits RFC byte order everywhere. What varies
is not the operating system but two boundaries, and both are worth knowing
before someone meets them in production.

**Boundary one: .NET's `Guid` is not RFC byte order.** `System.Guid` inherits
the Windows COM/OLE layout, where the first three fields are little-endian. The
operator surfaces are .NET 11 (ADR-0014), so any identifier crossing into them
must use `ToByteArray(bigEndian: true)` and `new Guid(bytes, bigEndian: true)`.
Use the default overloads and the bytes come back scrambled relative to what the
store holds — the values still round-trip if you are consistent, and they stop
sorting, which is the entire reason for choosing v7. `Guid.CreateVersion7()`
exists from .NET 9, so .NET 11 has it.

**Boundary two: SQL Server sorts `uniqueidentifier` in its own order.** It
compares the last six bytes first, so a v7 written there sorts essentially at
random and behaves like a v4 — page splits, fragmentation, and inserts that get
dramatically slower at volume. This does not affect Xmip's own stores: RocksDB
compares raw bytes and SQLite compares BLOBs with `memcmp`, so RFC-ordered v7
sorts correctly in both. It matters only when Xmip identifiers are written into
somebody else's SQL Server through `xmip-core-transport-mssql`, which is an
integration target rather than Xmip storage. Do not conclude from that
literature that v7 is a bad key — conclude that it is a bad key *in SQL Server*.

Two further cautions:

**v7 leaks creation time.** The millisecond is recoverable from any identifier
that leaves the estate. Inside Xmip that is a feature. On anything published to
an external party, treat the identifier as disclosing when the record was made,
and use a v4 where that matters.

**Same-millisecond ordering needs the counter.** RFC 9562 allows the `rand_a`
field to act as a monotonic counter within a millisecond. A queue that ingests
faster than 1 kHz and cares about insertion order must use it, or ordering
within a millisecond is random.

Recorded 2026-08-26, and applied: `Cargo.toml` carries the `v7` feature and all
ten generation sites in `journey_model.rs`, `xmip-exclusiveness`,
`xmip-tracking` and `xmip-handler-file` call `Uuid::now_v7()`.

The `v4` feature stays enabled deliberately. It is the right choice for an
identifier that leaves the estate and must not disclose when it was created.

## 8. Desired state

Xmip supports Desired State Configuration for installation and node
configuration. First targets: **Microsoft DSC v3** for Windows and
PowerShell-driven environments, **Ansible** for Linux, server automation and
mixed infrastructure.

Desired state tooling installs the package and brings a node to its configured
state: directory layout, persistence and management store paths, module folder,
node TOML, service registration and running state.

**Desired state configuration does not replace Xmip TOML.** It orchestrates
installation and places the configuration; the TOML remains the node and runtime
configuration source. A configured node has Xmip installed, both store paths
present, config and module folders present, node TOML present, and the service
registered and running where services are supported.

## 9. Recovery

Xmip runs on computers, and computers fail. An Xmip Process may be short-lived
or may represent a Journey over time, waiting for information, decisions,
replies, timeouts or other Events.

**A Journey continues regardless of routing, processing, waiting, retries or
elapsed time.** Messages accumulate context and reference immutable Streams;
Assignment and Transformation create new Message generations, and new Streams
only when content changes. Work continues until it leaves Xmip and the departure has been
audited.

What must be persisted to resume safely:

```text
Journey state        where the work is
Checkpoint           the last safe execution point
Wait conditions      which Events or correlations it is waiting for
Recovery lease       which node is currently recovering it
Deduplication record which source fingerprints and Messages were already accepted
Audit position       how far the work has been audited
```

The flow:

```text
Xmip Service starts
    -> read configuration
    -> validate the execution tree
    -> start Host Services, which load Modules and register capabilities
    -> scan persisted active, waiting and suspended work
    -> acquire a recovery lease per Journey
    -> restore the checkpoint
    -> resume, or keep waiting
    -> continue the audit
```

**Recovery is cluster-scoped.** Any capable node may resume work if it can
satisfy the required capabilities and acquire the lease. **The same Journey must
never be recovered by two nodes at once** — that is exclusiveness, and ADR-0017
owns the lease mechanics: taken by a node, released by completion immediately or
by expiry only on failure, and nobody queues.

Xmip cannot own every bad decision in configuration or custom code, but it
mitigates avoidable loss:

- persist before acknowledging external completion where required;
- checkpoint before waiting;
- checkpoint before externally visible side effects where possible;
- deduplicate where receive or failover can replay work;
- audit the Journey.
