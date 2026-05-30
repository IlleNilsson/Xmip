# Xmip v0.1 — Full System Constructor Prompt (Very Detailed)

> **Use this entire document as a single prompt** for Claude / Base44 (or any code-generating model).
> It is intentionally detailed and normative so the generated architecture and code match Xmip’s philosophy.
>
> **Non‑negotiables:** deterministic, artifact-driven, identity-aware isolation, cluster-scoped persistence, fail‑closed validation, immutable messages, Rust-only core + artifacts (plugins) depending only on `xmip-interface`.

---

## ROLE & OUTPUT CONTRACT (READ FIRST)

You are the **Chief Architect + Lead Implementer** for **Xmip** (Cross‑platform Messaging & Integration Platform), v0.1.

### Your job
Generate a complete, implementation-ready design and code skeleton for Xmip with:
- **Architecture** (components, flows, boundaries)
- **Domain model** (types, invariants)
- **State machines** (durable, restartable)
- **Persistence model** (cluster-scoped state store)
- **Config model** (TOML files + schema + validation rules)
- **Rust crate structure** (workspace layout)
- **Core traits** (`xmip-interface`) and engine implementation (`xmip-core`)
- **CLI** (`xmip-cli`) for validation, reports, run/service
- **Artifact/plugin model** (dynamic loading, stable contract, no Rust ABI reliance)
- **Observability** (logs/traces/metrics/tracking with Xmip URI addressing)
- **Reports** (Firewall & Operations, Identity & Isolation Compliance)
- **Tests** (unit + integration + restart/recovery scenarios)

### Hard constraints
- **Rust-only** engine and artifacts.
- **Multi-repo ecosystem:** core repo + one repo per artifact.
- **Artifacts depend ONLY on `xmip-interface`**.
- **No Rust ABI dependency across boundaries** (must use a stable ABI boundary).
- **Deterministic execution**: identical inputs + config → identical behavior and outcomes.
- **Deterministic recovery**: restart does not change decisions.
- **Cluster-scoped persistence**: any eligible node can resume work after failures/restarts.
- **Fail-closed validation**: invalid configs block startup; regulated mode is strict.
- **Identity-aware isolation**: incompatible identity contexts must not share host processes; regulated mode may require node-level isolation.

### Output format you MUST produce
1. **Executive architecture overview** (concise but precise)
2. **Glossary & invariants** (MUST/SHOULD/MAY)
3. **Domain model (types)** — include key Rust structs/enums
4. **State machines** for: receive, process, send, service bus claiming, scheduler
5. **Persistence schema** (logical tables/keys) and store traits
6. **Config files** examples: `template.xmip.toml`, `cluster.xmip.toml`, `xmip.toml`
7. **Validation rules** and error messages (fail-closed)
8. **Crate/workspace layout** and module boundaries
9. **Artifact/plugin ABI** (how artifacts are compiled/loaded/invoked safely)
10. **Observability & Xmip URI** mapping rules
11. **Reports** contents + how generated
12. **CLI commands** (validate, run, report, inspect, dev)
13. **Test plan** and representative tests (including restart recovery)
14. **Implementation skeleton code** (compilable stubs preferred) for core crates
15. **Roadmap**: what is in v0.1 vs deferred to later

---

## 1) XMIP DEFINITION & POSITIONING

Xmip is a **stream-based Messaging & Integration Platform** with a deterministic runtime that executes **artifact-defined** messaging/integration topologies across nodes and clusters.

- Xmip operates primarily **within clusters**.
- Xmip supports **inter-cluster communication** via the Xmip **gRPC protocol** (v0.1 can stub protocol boundaries, but define it).

**Primary differentiators**
- Determinism enforced by architecture, not convention.
- Explicit isolation driven by identity contexts.
- Artifact-driven runtime topology and execution semantics.
- Recoverable runtime with durable state and lease-based claiming.
- Offline-first governance (Git is the system of record; CI advisory).

---

## 2) NON‑NEGOTIABLE PRINCIPLES (INVARIANTS)

### MUST
- **Rust-only** engine and artifacts.
- **Immutable messages**: routing never creates messages; only transformations/assignments do.
- **Artifact-defined runtime**: all behavior/topology declared by artifacts in TOML.
- **Deterministic placement**: placement decisions are derived from config + constraints.
- **Deterministic execution**: same inputs/config → same outputs/state transitions.
- **Deterministic recovery**: restarts do not change execution decisions.
- **Cluster-scoped persistence**: all decision-critical state is stored cluster-wide.
- **Lease-based claiming**: no “in-memory locks” for durable work.
- **Fail-closed validation**: violations block startup.
- **Identity isolation**: incompatible identity contexts MUST NOT share host process.
- **Regulated profile**: strict isolation + mandatory compliance reporting + fail-closed.

### SHOULD
- Support Windows/Linux/macOS + ARM.
- Support “exactly-once where possible” internally; “at-least-once where external systems limit” externally.
- Keep artifacts small, versioned, independently releasable.
- Provide clear observability: logs/traces/metrics are first-class.

### MAY
- Optional tracking (payload persistence) controlled by policy.
- Optional performance/capacity reporting.

---

## 3) REPO & CRATE ARCHITECTURE

### Multi-repo model
Core repo (Rust workspace):
```
xmip/
  crates/
    xmip-interface/   # stable contract for artifacts
    xmip-core/        # runtime engine
    xmip-cli/         # CLI entry point
  docs/
```

Artifact repos:
```
xmip-artifact-<name>/
  crates/
    <artifact>/
  Cargo.toml
```

### Dependency rules
- `xmip-core` depends on `xmip-interface`.
- Artifacts depend ONLY on `xmip-interface` (and standard Rust crates).
- Artifacts do NOT depend on `xmip-core`.

---

## 4) CONFIGURATION MODEL (TOML)

Xmip uses three layers:

1. `template.xmip.toml` — reusable templates
2. `cluster.xmip.toml` — cluster-wide definitions and defaults
3. `xmip.toml` (node slice) — node-specific placement and runtime subset

### MUST: deterministic resolution
- Config merging order and precedence MUST be deterministic and documented.
- All resolved artifacts + versions + effective parameters produce a **Resolved Config** artifact set.

### Include in your output
- Full TOML examples for each file.
- A “Resolved Config” representation used at runtime.

---

## 5) ARTIFACT MODEL & TYPES

### Artifact
A named, versioned unit declared in config.

Artifact types include:

**Ports & Locations**
- `receivePort`
- `receiveLocation`
- `process`
- `sendPortGroup`
- `sendPort`
- `sendLocation`

**Handlers** (artifacts)
- `transportHandler`
- `contentHandler`
- `intentHandler`
- `contractHandler`

**Logic**
- `routingRule` (pub/sub)
- `processRule` (inside processes)
- `transformation` (creates new message)
- `assignment` (creates new message; **process-only**)

**Eventing**
- `event`
- `schedule`

### Artifact Instance
Runtime execution bound to:
- node
- host process
- configuration version
- identity context boundary

### Lanes
- Receive
- Process (optional)
- Send
- Void

Valid flows:
- Receive → Send
- Receive → Process → Send
- Receive → Void
- Receive → Process → Void

Assignments occur only within Process.

---

## 6) NODE, SERVICE, HOST PROCESSES

### Node capabilities
- receiving
- executing
- sending
- serviceBus
- monitoring
- operations
- development

A node may have multiple capabilities.

### Xmip Service
Runs on every node, responsible for:
- loading resolved config slice
- spawning host processes at startup
- enforcing identity isolation constraints
- claiming work from cluster store for eligible lanes
- supervising host processes
- emitting observability signals and reports

### Host Process
- Executes artifact instances.
- Must align with node capability.
- Is the boundary for identity isolation.
- Must not host artifacts from incompatible identity contexts.

---

## 7) IDENTITY & TRUST MODEL (DETAILED)

### Supported identity protocols
- Kerberos
- mTLS
- OAuth2 / OIDC
- SAML
- API Key
- Username/Password
- Anonymous

### Identity classes
- highAssurance
- federated
- sharedSecret
- anonymous

### Kerberos identity context fields
- domain
- service principal
- delegation scope
- delegation allow-list

### Trust
Trust is contextual acceptance of identity within a boundary (cluster, node, host process, artifact).

### Isolation rules (MUST)
- Different identity contexts MUST NOT share a host process.
- Delegation scopes MUST NOT co-reside when incompatible.
- In regulated profile: highAssurance identities require node-level isolation.
- Violations:
  - block startup (fail-closed),
  - are logged,
  - appear in Identity & Isolation Compliance Report.

---

## 8) MESSAGE MODEL (STREAM-BASED)

### Message (immutable)
Fields:
- `message_id` (stable UUID/ULID)
- `logical_name`
- `route` (REST-style path)
- `promoted_properties` (key/value for routing)
- `metadata` (creation instance + correlations + security labels)
- `sections[]` (stream-based)

### Sections
- stream-based (e.g., bytes stream handle/reference)
- metadata per section
- may reference prior stream for storage efficiency
- lazily decoded (avoid full materialization)

### Creation instance metadata (MUST)
- type: port | assignment | transformation
- name
- nodeName
- clusterName
- timestamp UTC

---

## 9) ROUTING, RULES, TRANSFORMATIONS

### Routing
- Based on `route` + `promoted_properties`.
- Uses `routingRule` artifacts for pub/sub.
- Routing does **not** create messages.

### Process rules
- `processRule` applies within a `process` artifact.

### Transformations
- Can occur in receive, process, or send lane.
- Produce new immutable messages.

### Assignments
- Process-only
- Produce new immutable messages.

---

## 10) SERVICE BUS, DURABLE STATE & CLAIMING (CORE)

Xmip’s internal service bus is a **durable, cluster-scoped queueing and state system**.

### Key requirements
- Work items are claimed with **leases**.
- Lease expiry returns work to pending state deterministically.
- Exactly-once commit where possible by durable state transitions.

### Generic work item / step
A “step” represents one deterministic action:
- consume input message reference
- execute artifact action
- persist output message references (or terminal state)

### Durable step state machine (MUST)
- Pending
- Claimed(lease)
- Executing
- Succeeded
- FailedRetryable
- FailedTerminal
- DeadLettered (optional terminal)
- Voided (optional terminal)

### Persisted step identity (MUST)
A stable identifier such as:
`(message_id, lane, action_instance_id, config_version, step_index)`

### Retry policy (generic)
- maxAttempts
- timeoutPerAttempt
- backoff (initial, multiplier, max, deterministic jitter)
- retryOn (error classes)
- onExhausted: deadLetter | void | terminalFail

### Deterministic jitter
If jitter is used, it MUST be deterministic (hash-based) so behavior is reproducible.

---

## 11) SEND LOCATION RESILIENCE (FULLY SPECIFIED)

Xmip implements a Polly-like resilience model for outbound sends with **cluster-scoped persistence**.

### SendPortGroup
- Holds ordered sendLocations.
- Holds chain policy: timeout/retry/backoff/breaker/failover/onExhausted.

### Severity semantics (LOCKED)
- Per sendLocation failure → **WARNING** `SendLocationFailed`
- Later success → overall **SUCCESS with warnings preserved**
- All locations failed → **ERROR** `SendPortExhausted` + terminal outcome

### Persistence (MUST, cluster-scoped)
Persist per send step:
- currentLocationIndex
- attemptNo for current location
- nextEligibleAt
- lastErrorClass
- attempt history (for reporting)
Persist per sendLocation breaker state:
- state: closed/open/half-open
- openUntil
- counters/window state needed for deterministic transitions
Optional idempotency ledger:
- (destinationId, deliveryToken) => delivered

### Delivery guarantees
- bestEffort: commit=attempt made
- atLeastOnce: commit=destination ack confirmed
- exactlyOnceWithExternalCooperation: only if destination supports it (validated)

### Idempotency modes
- receiverDedupes
- senderLedger
- none (restricted in regulated unless allowDuplicates=true)

### Error taxonomy (stable enum)
- Timeout
- NetworkTransient
- RateLimited
- Remote5xx
- Remote4xxPermanent
- AuthDenied
- ContractViolation
- MessageTooLarge
- DestinationUnavailable

### Failover algorithm (deterministic)
For location Li:
1. Attempt with timeout
2. If failure:
   - classify error
   - if retryable and attempts remain: compute backoff; persist nextEligibleAt; reschedule
   - else: WARN location failed; update breaker; advance to next location
3. If no next location: ERROR SendPortExhausted; terminal outcome per policy

### Circuit breaker
- cluster-wide per sendLocation
- deterministic transitions
- persisted openUntil and counters

---

## 12) SEQUENTIAL SOURCES (FILE/FTP/FTPS/SFTP)

Sequential enforcement is **state-based**, not “single process forever”.

Requirements:
- Durable claim model
- Lease mechanism
- Checkpointed recovery
- Exactly-once where possible; at-least-once where external constraints apply

Define durable checkpoint keys and the claim lifecycle.

---

## 13) OBSERVABILITY & XMIP URI

### Four pillars
- Logging
- Tracing
- Metrics
- Tracking (optional, policy-controlled)

### Xmip URI (RFC3986 compliant)
`xmip://[userinfo@][host][:port]/path?query#fragment`

Defaults:
- omit userinfo → caller identity
- omit host → all nodes (cluster-wide scope)

Used for:
- logs
- traces
- metrics
- tracking
- operations
- reports

### Requirements
- Every artifact instance has a stable Xmip URI.
- Events, metrics, traces must be addressable via Xmip URI.

---

## 14) REPORTS (MANDATORY)

### Firewall & Operations Report (mandatory)
Include:
- TCP/UDP ports used
- UNC paths / file paths for locations
- protocol exposures
- per-node capability summary
- per-artifact network IO footprint (derived from config)

### Identity & Isolation Compliance Report (mandatory)
Include:
- identity contexts discovered
- host process assignments
- violations (must be none to start)
- regulated-mode node isolation checks

Optional reports:
- performance/capacity
- artifact drill-down end-to-end

Reports must be reproducible from resolved config + cluster runtime metadata.

---

## 15) GOVERNANCE & BUILD

- Git-centric, offline-first.
- Local build is canonical.
- CI is advisory.
- Contributions are human-moderated.
- Extensions may be commercial or open source.
- No forking or reimplementing core semantics.

---

## 16) ARTIFACT PLUGIN MODEL (NO RUST ABI DEPENDENCY)

You MUST design a stable boundary for artifact plugins. Options include:
- C ABI boundary (`cdylib`) with explicit function exports and opaque handles
- WASM (if you choose this, justify + ensure Rust-only artifacts)
- Another stable ABI mechanism

Requirements:
- `xmip-interface` defines the contract types and serialization formats.
- `xmip-core` loads artifacts dynamically and negotiates interface version compatibility.
- Artifacts cannot access core internals; they operate via interface calls.

Define:
- plugin discovery (paths, naming conventions)
- version negotiation
- safety rules (panic containment, timeouts, resource limits)
- deterministic execution constraints (no nondeterministic APIs without mediation)

---

## 17) CLI (XMIP-CLI) — REQUIRED COMMANDS

Design `xmip-cli` commands such as:
- `xmip validate` (validate config; fail-closed)
- `xmip resolve` (render resolved config)
- `xmip run` (start node service)
- `xmip report firewall` (generate report)
- `xmip report identity` (generate report)
- `xmip inspect message <id>` (dev mode)
- `xmip dev scaffold-artifact <type>` (create artifact repo skeleton)

CLI must work offline.

---

## 18) INTER-CLUSTER PROTOCOL (STUB OK IN V0.1)

Define Xmip gRPC protocol at a high level:
- handshake and identity
- message transfer
- ack/receipt semantics
- compatibility versioning

You may stub implementation in v0.1, but define interfaces so it can be implemented later.

---

## 19) PERSISTENCE BACKENDS

Define a cluster store abstraction with at least:
- KV operations (get/put/compare-and-swap)
- queue/stream operations (enqueue/dequeue/claim with lease)
- time (monotonic + UTC)
- transactional or idempotent operations where needed

Provide:
- trait `ClusterStore`
- in-memory test store
- file-based dev store (optional)
- pluggable backends (future)

All logic must be correct under distributed contention.

---

## 20) TESTING REQUIREMENTS (MUST INCLUDE)

Provide a test plan and write representative tests:
- Deterministic config resolution
- Identity isolation violation blocks startup
- Lease expiry causes deterministic re-claim
- Restart mid-step resumes deterministically without duplication
- Send failover:
  - warning per location failure
  - success with warnings preserved
  - exhaustion yields error and terminal outcome
- Sequential source claims with checkpoint recovery
- Report generation stability (same input → same report)

---

## 21) WHAT TO IMPLEMENT IN V0.1 (SCOPE CONTROL)

You MUST clearly define what is “in” for v0.1:

### In-scope (minimum viable engine)
- Config parsing + resolution + validation (fail-closed)
- ClusterStore trait + in-memory store for tests
- Lease-based claiming for work items
- Message model with streaming sections (can use references/handles)
- Basic lanes: Receive (stub), Process (minimal), Send (detailed)
- Plugin loader + minimal artifact execution contract
- Identity context modeling + isolation enforcement
- Reports: Firewall & Operations, Identity & Isolation Compliance
- CLI commands for validate/resolve/report/run (run may be dev-only)

### Deferred (explicitly say deferred)
- Full inter-cluster gRPC implementation (only define interfaces)
- Full connector library (keep minimal examples)
- Advanced scheduling and complex process orchestration
- UI tooling

---

## 22) DELIVERABLES YOU MUST OUTPUT NOW

Produce:

A) **Architecture narrative** with diagrams in text (boxes/arrows)
B) **Rust workspace layout** (folders/modules)
C) `xmip-interface`:
   - core types
   - trait definitions for artifacts
   - ABI boundary definitions
   - version negotiation structs
D) `xmip-core`:
   - config resolver/validator
   - cluster store trait usage
   - service bus queues + lease claiming
   - host process manager
   - lane executors
   - send policy engine (retry/breaker/failover) with cluster persistence
   - identity isolation enforcer
   - report generators
E) `xmip-cli`:
   - command structure
   - wiring into core functions
F) **Config examples** (template/cluster/node)
G) **Validation rules list** with exact failure messages
H) **Persistence key schema** (logical tables/keys)
I) **Observability event schema**
J) **Tests** (code scaffolding)
K) **Short roadmap** beyond v0.1

Important: keep everything deterministic, recoverable, and enforced by design.

END OF PROMPT.
