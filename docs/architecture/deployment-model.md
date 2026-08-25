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
elapsed time.** Messages are immutable and reference immutable Streams;
Assignment and Transformation create new Messages, and new Streams only when
content changes. Work continues until it leaves Xmip and the departure has been
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
