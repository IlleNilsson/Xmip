# Xmip deployment model

Where Xmip runs, what it runs as, how it is installed, and how it recovers.

This replaces `deployment-profiles.md`, `runtime-profiles.md`,
`runtime-roles-and-isolation.md`, `installer.md`, `service-identities.md`,
`desired-state-configuration.md`, `database-selection.md` and
`disaster-recovery.md` — eight documents, two of which described the same two
databases in almost the same words.

## 1. The deployment range

Xmip runs from a microcontroller to a provider's virtual machines, and the
range is said as **five targets**, each a profile under
`deploy/profile/target` (ADR-0015, amendment 2026-10-01):

| Target | What it is | Store and key store |
| --- | --- | --- |
| `device` | a Meadow-class microcontroller: bare metal, no_std, no TLS server | none: it keeps no runtime store |
| `edge` | a Raspberry Pi, industrial PC or gateway under systemd, headless | SQLite; the file key store |
| `computer` | a person's own Windows or Mac machine, one node of its own | SQLite; DPAPI or the keychain |
| `server` | an on-premises Windows or Linux machine running the service | RocksDB; DPAPI or the file key store |
| `hosted` | a virtual machine or container at a hosting provider, headless | RocksDB; the file key store |

**A cluster and a hybrid are arrangements of nodes, not targets.** An
on-premises cluster is servers; a hybrid deployment is servers on one side
and hosted nodes on the other, joined as one cluster or as Parties to each
other. Each node in either is built for its own target.

**The runtime semantics are identical on all of them.** What varies is which
Modules are linked and loaded, which persistence and observability providers
are configured, and which capabilities exist across the cluster — the union
of what its nodes declare, in ADR-0056's four kinds: online, feature,
authentication and runtime. A target is a packaging and configuration
choice, never a different product.

The laws that hold everywhere:

- A Receive Location is where Xmip starts working.
- A Receive Port binds incoming Streams into the topology and creates Messages.
- Format detection precedes deserialization; deserialization precedes promotion.
- Promoted properties drive publication and Subscription matching.
- Process and delivery paths are Subscription-driven.
- A Send Port resolves to Send Locations.
- Preservation, lineage, checkpoints and recovery span the runtime.

`runtime-model.md` owns those; they are repeated here because the targets
are where people expect them to be negotiable, and they are not.

### Build targets

Each target names the Rust triples it is built for. Across them, this is
what Xmip is compiled for:

| Platform | Notes |
| --- | --- |
| Windows x64 | `computer`, `server` |
| Linux x64 | `edge`, `server`, `hosted` |
| macOS, Apple silicon and x64 | `computer`; developer machines primarily |
| Linux ARM64 | `edge`, `server`, `hosted`: Raspberry Pi class and upward, and most edge hardware |
| Cortex-M, `thumbv7em-none-eabihf` | `device`: `xmip-core` alone, no_std |
| Industrial and defense hardware | the constrained case; see below |

ARM and the industrial targets are the two that change decisions rather than
just adding a build. Both push toward the purpose-compiled runtime of section 2
rather than the dynamic one: an edge device with 512 MB of RAM does not want a
Module loader and a TOML parser it will never use, and a defense deployment
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
deployment or deterministic behavior.

**A purpose-compiled runtime is a site's build.** A site,
`deploy/site/<name>.toml`, picks one target, the node roles it serves
(`deploy/profile/role`, one per `NodeRole` word; executing is receiving,
processing and sending in one process) and the domains it integrates
(`deploy/profile/domain`: healthcare, industrial, b2b, managed-service and
the rest, each naming the standards it serves). `Build-XmipService -Site`
turns it into one `cargo build` of `xmip-service`: the target's features,
every role's, each domain technology the build can link, and the
program's own. The target vetoes: a role or a domain needing a feature the
target refuses is refused in words, with the target's reason, and a device
site is refused because `xmip-service` needs the standard library — what
builds for a device is `xmip-core` alone.

```text
The build sets what is possible: the site's target, roles and domains.
The node's TOML picks from it at run time: what a node starts.
Sites are files, not git branches.
```

A purpose-compiled runtime still behaves according to Xmip Definitions and
runtime contracts. **Purpose compilation is a packaging strategy, not an
alternative to modularity** — and a small device must never be forced to carry
the full server footprint to get correct semantics.

The Rust rules a purpose-compiled runtime still obeys — stages pass owned
work, blocking Handler work never blocks a latency-sensitive loop — are
`module-model.md` section 12, and hold on every build.

### TLS is built in or it is not there

**A guarded connection needs the `tls` feature at build time.** TLS is
`xmip-core-library-tls` (ADR-0033, amendment 2026-09-23): the hybrid key exchange, the
node's certificate and the trust store. A transport that can guard a
connection — `http` and the technologies riding on it, and every technology
that takes the feature as they are wired up — carries a `tls` feature that
pulls it in, off by default, because a forwarder on an edge device should not
carry a TLS stack it never opens.

So a package either has it or it does not, and this is a packaging decision
like any other in this section:

```text
cargo build --features tls        a node that may speak https, ldaps, STARTTLS
cargo build                       a node on plain sockets only
```

Without the feature an `https://` endpoint is refused with a message saying
so, rather than sent in the clear. The node configuration `deploy/` writes
names no feature and no module: a node loads what its configuration names
from what its program was built with, so a package built without `tls` and a
Location configured for `https` is the operator's error the node reports at
once.

## 3. Node roles

A node declares its roles, and they are the one vocabulary for what a node is
for — at run time, in a deployment, and in what its program is built with
(`node::NodeRole`; ADR-0056, amendment 2026-10-01). Seven:

| Role | Serves | May | Examples |
| --- | --- | --- | --- |
| **Receiving** | the receive stage | take Streams in and make Messages | a Receive Location, deserialize, promote, publish |
| **Processing** | the process stage | route and transform by Subscription | a Subscription, an Xmip Process, transform |
| **Sending** | the send stage | deliver Messages out | a Send Port, demote, serialize, send |
| **Executing** | all three, in one process | everything the three may | a whole Journey with no process hop: the low-latency choice |
| **Operational** | no stage | change runtime state or operational outcome | claim work, checkpoint, preserve, acknowledge, retry, resume, suspend, terminate, move a Message |
| **Monitoring** | no stage | inspect runtime state | Message Context, lineage, logs, metrics, health, publication history |
| **Development** | no stage | exercise Xmip from outside | the Playground (ADR-0028) |

**Executing is the sum of receiving, processing and sending** (the owner,
2026-10-01: *Leave Executing as a sum of Receiving, Processing and Sending.
Executing would be used for Low Latency*). A node that declares the three is
executing, and is said so: one thing has one name. It is what buys latency —
a Journey whose receive, process and send run in one process crosses no
process boundary — per ADR-0018 clause 10a. A node declaring one of the three
hands every Journey on, and pays the hop.

Roles combine per deployment:

```text
Edge node          Executing + Monitoring + Operational
Monitor component  Monitoring
Recovery component Monitoring + Operational + Executing
Hosted worker      Receiving + Operational, or Processing + Sending
```

These are deployment choices, not separate runtime models.

**Executor, Reader and Writer are gone.** This section named three runtime
roles until 2026-10-01 — Executor, Reader, Writer — for the subject
`NodeRole` names, and two vocabularies for one thing is one too many.
Executor is receiving, processing, sending or executing; Reader is
monitoring; Writer is operational; development had no counterpart. The rule
that stood here — *do not create a role per capability*, with receive, send
and process hosts named among the capabilities it kept out — is overruled for
those three by the owner's ruling above. It stands for the rest:
preservation host, recovery coordinator and cluster coordinator are
capabilities or operational responsibilities, implemented by Artifact
Instances, Modules or profiles, and they do not extend the role model.

**A role also picks what is built.** `deploy/profile/role/<role>.toml`, one
per role, says which capabilities a deployment's program carries for it, and
a site names its roles beside its target and its domains (ADR-0015,
amendment 2026-10-01).

Runtime roles are also **not human roles**. Observer, Operator, Developer,
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

> Executing is not one trust level. A node serving the message path —
> receiving, processing, sending, executing — is scoped by isolation boundary.

The rules:

1. A monitoring node cannot execute artifact behavior.
2. An operational node cannot load arbitrary Module code.
3. A node serving the message path cannot automatically affect another.
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
| `enterprise` | multi-tenant or party-facing | the above, plus mandatory Service Identity separation per runtime role |
| `regulated` | government, defense, healthcare, finance | the above, plus node-level isolation for `highAssurance` identity contexts, fail-closed everywhere, and mandatory compliance reporting |

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

**Xmip does not impose one account model.** Each platform realizes Service
Identity natively:

| Platform | Realization |
| --- | --- |
| Windows | Managed Service Account, group MSA (supported wherever it exists: ADR-0019, amendment 2026-09-25), domain or local service account |
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
    module/
    data/
        persistence-rocksdb/
        management.sqlite
    logs/
```

It creates the layout, initializes both databases, installs default
configuration, and registers the Xmip Service where services exist.

## 7. Two databases, and why

| | Runtime persistence | Management |
| --- | --- | --- |
| Engine | RocksDB, `xmip-core-persist-rocksdb` | SQLite, `xmip-core-persist-sqlite` |
| Optimized for | high write volume, replay from a known state | queryable administration views |
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
The owner chose the two engines on 2026-09-25 (ADR-0015, amendment); each is
a technology under `xmip-core-persist`, so a device build can leave RocksDB
and its C++ toolchain out.

**Both are encrypted, above the engine** (ADR-0063 clause 2). Persist's
`EncryptedStore` seals every record with AES-256-GCM before either engine
sees it and looks it up by a keyed hash, so neither file holds what is stored
or what it is stored under; the data key is wrapped by the key home,
`xmip-core-secret`. The cost is stated rather than hidden: the management
store is a table of sealed records, so "queried arbitrarily" is answered by
reading records through persist, not by SQL over the file, and a query the
administration views need is an index persist keeps for it.

### Record identifiers are UUIDv7

**Every record in either database is keyed by a UUIDv7**, per RFC 9562: the
timestamp leads, so records written in sequence land in sequence and a range
over identifiers is a range over time. The reasoning, the two boundaries an
integrator meets (.NET's `Guid` byte order, SQL Server's sort order) and the
two cautions are `module/platform/persist/doc/record-identifier.md`.
The engine is keyed by a keyed hash of the identifier, not the identifier
(ADR-0063), so the ordering holds for the identifier and not on disk; the same
document says what that costs.

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

The node TOML either writes is the document `xmip-core-configure` reads
(`module/platform/configure/doc/node-configuration.md`): `[service]`, and
nothing the reader has a default for, so the runtime store is the installed
layout's. The estate root's `cargo test --test deploy` renders both and reads
them as `xmip-service` does.

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
satisfy the required capabilities. **The same Journey must never be recovered by
two nodes at once**, and how that is guaranteed is **open**.

ADR-0017 answered it with a cluster-wide lease and ADR-0024 retired that record:
a lease in per-node persistence proves nothing to another node, which is why
`ExclusiveScope::Cluster` was never servable. ADR-0024's answer — claim the
artifact at the endpoint — settles arrivals and settles nothing here, because a
Journey mid-flight is Xmip's own state and has no endpoint to claim it at.

This is the same open problem as *work does not move by itself* in
`runtime-model.md` section 3: a Message in node A's ToDo is node A's work, and
moving it is an explicit act nobody has designed. Recovery is that act under a
different name.

Xmip cannot own every bad decision in configuration or custom code, but it
mitigates avoidable loss:

- persist before acknowledging external completion where required;
- checkpoint before waiting;
- checkpoint before externally visible side effects where possible;
- deduplicate where receive or failover can replay work;
- audit the Journey.
