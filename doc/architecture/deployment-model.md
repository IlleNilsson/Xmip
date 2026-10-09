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

| Target | What it is | Key store |
| --- | --- | --- |
| `device` | a Meadow-class microcontroller: bare metal, no_std, no TLS server | none: it keeps no store |
| `edge` | a Raspberry Pi, industrial PC or gateway under systemd, headless | the file key store |
| `computer` | a person's own Windows or Mac machine, one node of its own | DPAPI or the keychain |
| `server` | an on-premises Windows or Linux machine running the service | DPAPI or the file key store |
| `hosted` | a virtual machine or container at a hosting provider, headless | the file key store |

**No target's nodes open a database of their own**: every node calls Xmip
Storage, the nodes declaring the Storage role (sections 3 and 7). Behind
them is a database server IT runs, or, on a single machine or an edge site,
one embedded Storage node keeping both RocksDB, for the runtime database,
and SQLite, for the administration database. The pairing of `edge` and
`computer` with SQLite as the runtime store is superseded (ADR-0015,
amendment 2026-10-01).

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
- Work Process and delivery paths are Subscription-driven.
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

**The code and its tests are as operating-system agnostic as they can be**
(the owner, 2026-10-01: *it has to be as OS agnostic as it can*). Running the
tests on Windows alone is temporary: *We are temporarily only running Windows
tests, for time reasons. When we are over this hurdle we will run at least
Windows & Linux. I do not have an OS X machine.*

## 2. Two ways to build the runtime

**Server runtime** — the full runtime. Dynamic Modules, TOML configuration,
receive and send, process execution, Subscription matching, audit, tracing,
persistence, clustering, management, updates and deployment tooling. It
discovers and loads Modules on demand.

What `xmip-service` is today is a purpose-compiled runtime in this sense:
every technology it runs is linked by feature, so adding one — a transport,
a contract, a key store — is a rebuild with `Build-XmipService`, and the
node's TOML then names it. Its Module loader is built and drives the
contract table alone, and the service is built without it
([built, not in the assembled service](estate-map.md#module-loading)); Work Process
execution is [decided, not built](estate-map.md#process-execution).

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
(`node::NodeRole`; ADR-0056, amendments 2026-10-01). Eight:

| Role | Serves | May | Examples |
| --- | --- | --- | --- |
| **Receiving** | the receive stage | take Streams in and make Messages | a Receive Location, deserialize, promote, publish |
| **Processing** | the process stage | route and transform by Subscription | a Subscription, a Work Process, transform |
| **Sending** | the send stage | deliver Messages out | a Send Port, demote, serialize, send |
| **Executing** | all three, in one process | everything the three may | a whole Journey with no process hop: the low-latency choice |
| **Operational** | no stage | change runtime state or operational outcome | claim work, checkpoint, preserve, acknowledge, retry, resume, suspend, terminate, move a Message |
| **Monitoring** | no stage | inspect runtime state | Message Context, lineage, logs, metrics, health, publication history |
| **Development** | no stage | exercise Xmip from outside | the Playground (ADR-0028) |
| **Storage** | no stage | be the doorway to all storage | Xmip Storage: write a Stream chunk, write a Message, claim a Journey, hand it on, write an audit record |

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

**Storage is the doorway to all storage** (the owner, 2026-10-01: *to have
one or more Xmip Nodes with role Storage would be a safety… Xmip could just
do a round robin over Xmip Nodes roled Storage*). Every other node calls the
Storage nodes' operations — **Xmip Storage** — and never a database directly,
reaching them round robin, one Storage node for the whole of a statement —
a receive cycle's chunks, Publication and Journeys (the owner, 2026-10-03;
`runtime-model.md` section 3); more than one Storage node is the safety. Whether
a Storage node also carries the database is IT's question (section 7). A
one-node deployment is its own Storage node. `node::NodeRole::Storage` is
the role, and `xmip-core-persist`'s `storage` is Xmip Storage: its
operations, the embedded Storage node, the wire over Xmip's TLS and the
round robin (ADR-0056, amendment 2026-10-01, the Storage role). A node as
its own embedded Storage node is
[built, in the assembled service](estate-map.md#embedded-storage); Storage nodes
reached over the wire are
[built, not in the assembled service](estate-map.md#storage-nodes).

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
Profiles are [decided, not built](estate-map.md#security-profile): no configuration
key names one yet, and nothing checks identity isolation at start.

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

**Only an embedded Storage node keeps the stores in its `data/`** (section
7). A node without the Storage role keeps neither and reaches Xmip Storage
over Xmip's TLS (ADR-0063, amendment 2026-10-01); a Storage node in front of
a database server keeps none either, the server's files being IT's. A
one-node deployment is its own embedded Storage node, so its layout is the
one above.

## 7. Two databases, and why — behind Xmip Storage

Decided by the owner, 2026-10-01, validated part by part with the assistant,
and re-decided later the same day.

**Xmip Storage is the doorway.** The nodes declaring the Storage role
(section 3) serve every storage operation — write a Stream chunk, write a
Message, claim a Journey, hand it on, write an audit record — and every
other node calls them, never a database directly,
round robin over the Storage nodes (the owner: *to have one or more Xmip
Nodes with role Storage would be a safety… Xmip could just do a round robin
over Xmip Nodes roled Storage*). The records are the cluster's, not a node's
(the owner: *There is nothing local about either RocksDB or SQLite, they are
cluster services running on one or more nodes*; *All DB records have to be
central and clusterable, if one node fails another one should be able to
pick up*).

**Xmip Storage always keeps two databases, whatever the backend** (the owner:
*We still need the distinction between runtime and administration databases,
regardless of backend database technology*):

| | The runtime database | The administration database |
| --- | --- | --- |
| Holds | the Ledger: Streams in chunks, Messages, Journeys, claims; the state of each Work Process; retry, failure and replay state; the Messages a paused Subscription holds; audit records as first written | administration; operator state; audit kept over time; the Subscriptions each Host Service writes from its TOML as it starts ([decided, not built](estate-map.md#shared-subscriptions)) |
| Optimized for | high write volume, read by key, replay from a known state | what is kept and queried over time |
| On an embedded Storage node | RocksDB, `xmip-core-persist-rocksdb`, always | SQLite, `xmip-core-persist-sqlite` |
| Behind a database server | a database of its own on IT's server | a separate database on IT's server, which IT may place on another server |

**Runtime matter is central** in the runtime database — the Ledger, its
claims and its state — so another node with matching node roles can pick up.

**The administration database holds what must be shared and kept over
time:**

- administration: node registration, cluster membership, installed Modules,
  available Handlers and Extensions, configuration versions and deployment
  state;
- the Subscriptions, written from each Host Service's TOML as it starts and
  never edited there (ADR-0031, amendment 2026-10-02;
  [decided, not built](estate-map.md#shared-subscriptions));
- operator state: what is paused, by whom and when — every node honors a
  pause;
- audit, moved there from the runtime database by the audit keeper — on
  every backend (the owner: *RocksDB is the first storage for audit records,
  then transferred to SQLite, RocksDB for speed, SQLite for persistence over
  time*). The `audit.toml` file sink is to be replaced by this, for the
  tools outside a node as well — the cmdlets, the operation web and
  `xmip-cli` writing to the cluster's Storage nodes (ADR-0062, amendment
  2026-10-01; [decided, not built](estate-map.md#audit-through-storage)); until then
  every program appends to its `audit.toml`
  ([built, in the assembled service](estate-map.md#program-audit)), and the operating
  system's log stays the fallback (ADR-0062 clause 3).

**They are separate databases and stay separate, whatever engine holds
them.** Their access patterns are opposites — one is written constantly and
read by key, the other is written rarely and queried arbitrarily — and one
database serving both serves neither. That holds for RocksDB and SQLite on an
embedded Storage node and for two databases on a server alike.

**What is behind Xmip Storage is IT's to design** (the owner: *The storage
node may or may not carry the SQL storage, it is an IT-infrastructure
question… How IT-infrastructure designs their Database servers is their
concern*). Two forms are decided:

| | A shared database server (option A) | One embedded Storage node |
| --- | --- | --- |
| For | a cluster | a single machine, an edge site |
| What | database servers IT runs on the internal network — PostgreSQL first, through `xmip-core-persist-postgresql`; SQL Server later | RocksDB and SQLite through `xmip-core-persist`, in the node's `data/` |
| Clustering, failover, backup | IT's | **none**: no failover, stated plainly |
| A claim | a conditional update: set the owner where the owner is empty or lapsed | the same condition, in RocksDB on the one node |
| A write counts | once the runtime database has committed it | once it is synced to disk; group commit shares one sync among concurrent writes |

**PostgreSQL is the first database server Xmip Storage supports** (the
owner, 2026-10-01: *Don't leave out the elephant, Postgres*), as a persist
technology, `xmip-core-persist-postgresql`, reusing the PostgreSQL wire
protocol the estate already speaks in its PostgreSQL transport — one
implementation, no async runtime. SQL Server follows later. Both are
[decided, not built](estate-map.md#database-server).

**A node finds its Storage nodes from its TOML** (the owner, 2026-10-01,
asked whether a node should find them from a list of their addresses in its
TOML, tried round robin: *Yes*): the node's configuration lists their
addresses, for example
`[storage] nodes = ["storage-1.example:7443", "storage-2.example:7443"]`, and
the node tries them round robin.

Option A is chosen (the owner: *Go ahead*). **Every write counts only once the
database has it durably** (the owner: *Safe way*), the hand-ons between steps
included.

**A Storage node under test** (the owner, 2026-10-01: *for testing purposes
the Xmip Nodes of Storage type can use SQLite in memory for administration
and RocksDB for runtime*) keeps its administration database in SQLite in
memory and its runtime database in RocksDB, on disk in the test's directory,
so a kill test still proves the runtime database durable.

**The engine is no longer a node's choice.** The `[store] engine` choice is
removed: an embedded Storage node's runtime database is always RocksDB, and
the record of 2026-09-30 that let a node name SQLite as its runtime engine
is superseded (ADR-0015 and ADR-0018, amendments 2026-10-01).

**Configuration is TOML, read as a Host Service starts; the Subscriptions
are shared through Xmip Storage** (the owner, 2026-10-02: *Routes are
defined in TOML, read into Storage at Xmip Host Service startup, read from
Storage when needed and kept in memory until "not used for a while"*, and
*They are shared*; [decided, not built](estate-map.md#shared-subscriptions): a node
routes by the Subscriptions it binds,
[built, in the assembled service](estate-map.md#subscription-routing)). Each node reads its TOML configuration as it starts and
holds its Locations, Work Processes and Send Ports as its **execution
tree**, which `build_execution_tree` in `xmip-core-runtime` builds. Its
Subscriptions it writes into Xmip Storage's administration database, so any
node with a routing role routes a Message another node received; routing
reads them from Xmip Storage when it needs them, compiles their filters and
keeps them in memory until they have not been used for a while. The
operation tools and editors change the TOML file, never a database, and a
changed TOML file takes effect when the Host Service that reads it is
started again, never mid-flight (ADR-0031, amendments 2026-10-01 and
2026-10-02).

**Later, only if option A's latency is too slow:**

- **Option C** — an embedded engine on each Storage node, Xmip copying from a
  claimed primary to standbys asynchronously, and a witness holding the
  claim on which node is primary. It would bring into Xmip what A leaves to
  IT: ordered replication, a promote command, epoch fencing (each promotion
  raising an epoch, and a write carrying an older one refused), and a loss
  window — writes not yet copied when the primary dies.
- **Option D** — C for the hot runtime database, A for the administration
  database and its history.

**Rejected: option B**, an embedded engine on a shared disk. RocksDB is not
supported on network file systems.

The owner chose RocksDB and SQLite as the embedded engines on 2026-09-25
(ADR-0015, amendment); each is a technology under `xmip-core-persist`, so a
device build, which keeps no store, leaves both out.

**Encryption** (the owner, 2026-10-01: *Xmip encrypts to Xmip Node with
Role/Type Storage, from there it is the IT infrastructure/operations to
decide*; and for the embedded Storage node, *Well then Xmip has to support
encryption of that*): everything between a node and a Storage node travels
over Xmip's own TLS; behind a database server IT runs, encryption at rest is
IT's and operations' decision — SQL Server's Transparent Data Encryption or
encrypted disks, for example; on an embedded Storage node, test nodes
included, Xmip encrypts its own files at rest itself (ADR-0063 clauses 1 to 3,
amendment 2026-10-01).

**On an embedded Storage node both are encrypted, above the engine**
(ADR-0063 clause 2). Persist's
`EncryptedStore` seals every record with AES-256-GCM before either engine
sees it and looks it up by a keyed hash, so neither file holds what is stored
or what it is stored under; the data key is wrapped by the key home,
`xmip-core-secret`. The cost is stated rather than hidden: the management
store is a table of sealed records, so "queried arbitrarily" is answered by
reading records through persist, not by SQL over the file, and a query the
administration views need is an index persist keeps for it.

**Proposed 2026-10-09: laid-out columns, in the clear** (the owner, the same
day: *Store it in the clear*; *All columns shall be laid out*). Each table a
search reads — Journey, Message, held, Dead Message Queue, audit and
administration — keeps every single value of its record in a column of its
own, in the clear, beside the body: identifiers as the keys are kept, names
and words as text, times, states, counts and flags as they are. A list — a
Journey's entries, a Message's Sections and context, an audit record's
properties, a Dead Message's declines — is never a table of its own; it
stays in the body. On a database server they are columns with indexes
(`storage::schema`, `deploy/database/<server>/`); on an embedded Storage
node, whose engines have no columns, each index is kept as entries of its
own, their values in the clear as the server's, written in the record's
own batch, the records themselves still sealed. `XmipStorage::query` asks
one typed question of one index (`module/platform/persist/README.md`,
*Laid-out columns*; the amendment drafted for ADR-0063 waits on the owner).

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
configuration through two technologies, **Microsoft DSC v3** and
**Ansible**. Both are operating-system agnostic (the owner, 2026-10-02:
*Microsoft DSC 3+ as Ansible is OS agnostic, just different technologies*):
each deploys a node on Windows, Linux and macOS alike, and a site chooses
the one its IT runs.

Desired state tooling installs the package and brings a node to its configured
state: directory layout, persistence and management store paths, module folder,
node TOML, service registration and running state.

**A cluster's configuration is one `xmip.toml`, sliced to each node as it is
deployed** (the owner, 2026-10-03: *There is one xmip.toml file per cluster.
When deployed the sections regarding a node will be sliced to that node*;
ADR-0031, amendment 2026-10-03): desired state writes each node the
cluster's shared sections and its own `[nodes.<name>]`, the node's value
winning where both say one. Every outward and hardware assumption — the TCP
segment, the segments a chunk holds, the receive pool's threads per
hardware thread, idle times, the Storage client's timeouts — is configured
there, per cluster and per node, under `[tuning]`.

**Desired state configuration does not replace Xmip TOML.** It orchestrates
installation and places the configuration; the TOML remains the node and runtime
configuration source. A configured node has Xmip installed, both store paths
present, config and module folders present, node TOML present, and the service
registered and running where services are supported.

Each technology has its folder under `deploy/dsc`: `ansible` and `msdsc`.
The Ansible role `xmip_node` is written; Microsoft DSC v3's is not (its first
document was deleted on the owner's word, 2026-10-09). Desired state places
the cluster's `xmip.toml` on the node — the site's own, or a starter written
from a few variables — and writes the node's configuration
as `xmip-service --configuration <xmip.toml> --node <name> --slice` prints
it: `xmip-core-configure`'s one slicing
(`module/platform/configure/doc/cluster-configuration.md`), never one in
YAML or a template. The node reads the document `xmip-core-configure` reads
(`module/platform/configure/doc/node-configuration.md`). The estate root's
`cargo test --test deploy` renders the role, slices it and reads the slice
as `xmip-service` does.

## 9. Recovery

Xmip runs on computers, and computers fail. A Work Process may be short-lived
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
Claim                which node holds it, and until when
Deduplication record which source fingerprints and Messages were already accepted
Audit position       how far the work has been audited
```

The flow:

```text
Xmip Service starts
    -> read configuration
    -> validate the execution tree
    -> start Host Services, which load Modules and register capabilities
    -> start each Host Service's pools
    -> find lapsed work: claims nobody renewed
    -> claim it through Xmip Storage
    -> restore the checkpoint
    -> resume, or keep waiting
    -> continue the audit
```

**Recovery is cluster-scoped.** Any capable node may resume work if it can
satisfy the required capabilities. **The same Journey must never be recovered by
two nodes at once** — open until 2026-10-01, and answered then by claims
through Xmip Storage (the owner, 2026-10-01, validated part by part with the
assistant, and re-decided later the same day).

**A claim is a time-limited conditional update in the database behind Xmip
Storage** — set the owner where the owner is empty or lapsed — renewed while
the work runs. A node that dies stops renewing; its claims lapse, and any
other node capable of the work claims it and resumes from the last finished
step. Two nodes cannot both hold it, because the update is conditional in
the one database every Storage node is in front of. The owner recalled this
as the old exclusiveness; the word is ADR-0024's, a claim.

ADR-0017 answered this with a cluster-wide lease, and ADR-0024 retired that
record: a lease in per-node persistence proves nothing to another node.
ADR-0024's claim at the endpoint settles arrivals and nothing here, because a
Journey mid-flight is Xmip's own state and has no endpoint to claim it at.
The database behind Xmip Storage is that missing one place, and a
time-limited claim is right there for the reason the endpoint's own claims
end on their own — a dead holder must let go without anyone's help (ADR-0024,
amendment 2026-10-01).

**Every hand-on is one atomic write**: the step's result, the next Journey
and the claim released, together. On start a Host Service starts its pools,
finds lapsed work, restores checkpoints, resumes or keeps waiting, and
continues the audit. **Shutdown drains** and gives its claims back
explicitly, rather than leaving them to lapse (ADR-0018 clause 12). **The
Xmip Service dying stops no work** (ADR-0018 clause 5). **A Storage node
dying stops no work either** while another is left: every node reaches the
next one round robin. **The database server's failover is IT's.** An
embedded Storage node has none: while it is down, its site stores nothing.

### What Xmip does, and what the infrastructure does

The owner, 2026-10-01: *Now we are getting into failover and load balancing
which will be IT-infrastructure functionality, unless you think it is easy to
implement.* The split agreed, as re-decided later that day:

| Xmip | IT infrastructure |
| --- | --- |
| Xmip Storage: the storage operations every node calls, on one or more Storage nodes | the database server behind them: its clustering, failover and backup |
| round robin over the Storage nodes | load balancing incoming traffic |
| claims: conditional, time-limited, renewed while working | |
| one atomic write per hand-on, counted once the database has it durably | |

Replication between Storage nodes, a promote command and epoch fencing are
not Xmip's under option A; they are option C's, recorded in section 7 for
later, only if A's latency is too slow.

Xmip cannot own every bad decision in configuration or custom code, but it
mitigates avoidable loss:

- persist before acknowledging external completion where required;
- checkpoint before waiting;
- checkpoint before externally visible side effects where possible;
- deduplicate where receive or failover can replay work;
- audit the Journey.
