# Xmip module model

What belongs inside the Xmip runtime, what must be a loadable Module, and how
the boundary between them works.

This replaces `kernel-boundary.md`, `modularity.md`, `runtime-modularity.md`,
`module-loading.md` (both copies of it), and the module sections of
`platform-system-definition.md`. The normative C ABI stays in
`module-abi-specification.md` and moves to `xmip-core-abi` with the header it
describes; this document is the model, that one is the contract.

**"Kernel" is retired.** All six source documents used it for the stable runtime
core. There is no Kernel repository and there will not be one: ADR-0018 folded
service and host into `xmip-core-runtime`, which is the thing every one of those
documents meant. The word also collides with the operating system kernel in a
product that discusses System Processes on every page. Read "the runtime" or
`xmip-core-runtime` wherever an older document says Kernel.

## 1. The four things, kept separate

```text
Runtime              runtime law and execution truth
Module               deployable executable capability
Artifact Definition  configured intent, declared in TOML
Artifact Instance    Artifact Definition + Module code + validated Contracts
```

Collapsing any two of these is the failure this document exists to prevent. The
runtime does not implement capability. A Module does not decide execution truth.
A Definition is not running. An Instance is not configurable.

## 2. What the runtime owns

The minimum semantics every Xmip deployment needs, regardless of profile.

**Execution context** — execution identity, current runtime state, runtime
generation, lineage, checkpoint boundary, preservation state, recovery state.

**Runtime state progression.** Xmip is **not a mandatory linear pipeline.**
Messages may be received, optionally deserialized, optionally transformed,
optionally promoted, published, subscribed, processed, serialized and sent,
according to Artifact Definitions and runtime context.

Context available *before* deserialization can already drive Subscription
evaluation — Receive Location, Receive Port, content type, subject, headers,
metadata, file name, file attributes, queue name, promoted properties. This is
what makes the Transfer and Light processing depths in `runtime-model.md`
possible: routing without parsing.

Promotion extracts values into Message Context, and may happen during
transformation. **There is no separate concept of transformed properties.**

**Preservation** — incoming representation, execution checkpoints, lineage,
publish and subscribe history, replay and recovery boundaries, durability hooks.

**Recovery** — authoritative execution state, lineage, replay boundary,
preservation log, deterministic continuation.

**Publish and subscribe semantics.** A Subscription is an Artifact Definition.
When it evaluates true at runtime it causes the action its Definition declares,
which may publish. A Module may implement subscription *matching* or optimised
routing; **a Module may not redefine what publish and subscribe mean.**

**The contracts themselves**, which come in two kinds that are constantly
confused:

```text
inside one Host Service    traits and interfaces, in-process, over the C ABI
between Host Services      gRPC, with Protocol Buffers as the wire format
```

These are different boundaries with different costs. ADR-0018 clause 10a prices
the second one: a process hop is serialisation, a copy and a context switch.

## 3. What the runtime must never require

```text
HTTP        MQTT        SMTP        SFTP        file system adapters
XML         JSON        EDI         business transformations
process and orchestration implementations
cloud provider specifics            database persistence providers
observability exporters             UI tooling
```

Every one of these is a deployable Module. A runtime that requires any of them
cannot run on the IoT profile, and the profiles in `deployment-model.md` stop
being one product.

## 4. The test

A proposed runtime feature must answer yes to at least one:

1. Is it required to preserve execution truth?
2. Is it required to recover execution?
3. Is it required to maintain lineage?
4. Is it required for publish and subscribe semantics?
5. Is it required for the gRPC and Protocol Buffers contract between Host
   Services?
6. Is it required for the contract between the runtime and a Module?

If not, it is a Module.

> Xmip grows by adding Modules and Artifact Definitions, never by expanding the
> runtime with concrete technology.

## 5. The loadable binary model

A Module ships as a platform-native shared library:

```text
Windows   .dll
Linux     .so
macOS     .dylib
```

**Installing a capability must never require recompiling the runtime.** A Module
is installed by placing its package and manifest where the runtime can discover
it, or by registering it through Xmip deployment tooling.

Modules may also be Rust crates compiled in, where the deployment profile calls
for a purpose-compiled runtime — the ABI exists so that the dynamic case is
possible, not so that it is mandatory.

## 6. The manifest

Each Module carries `xmip-module.toml` declaring:

```text
component id            supported Xmip contract version
module kind             platform
version                 binary path
required capabilities   supported technologies
trust requirement       isolation requirement
```

The runtime receives one or more module roots from node configuration and scans
them for manifests.

## 7. Loading and registration

```text
Xmip Service
    reads configuration
    builds the execution tree
    validates startup                 <- fails here, before anything starts
    plans Host Services
    starts Host Services
Xmip Host Service, each within itself
    loads its configured Modules      ABI-verified per ADR-0012
    registers Handlers                into the Handler registry
    registers Extensions              into the Extension registry
    verifies Extensions               verified, not loaded
    accepts work
```

The runtime resolves configured Handler names through the registry and talks to
**Handler traits, never to concrete implementations**. Extensions are runtime
utilities, not Handlers: a Handler does technology-specific receive, send,
content or logic work; an Extension provides reusable capability to whatever may
call it.

**Modules load at startup. Extensions are verified at startup where possible and
loaded only when execution requires them.** ADR-0018 owns the nine phases.

## 8. Execution thread

Loading a shared library does not create a thread. This surprises people often
enough to state plainly:

```text
Host Service thread
    -> calls a Module function
    -> Module code runs on that same thread
    -> returns
```

A Module function runs on the calling thread unless Xmip explicitly schedules it
elsewhere. **If isolation is required, Xmip uses a separate Host Service. If
concurrency is required, Xmip schedules onto a worker thread or pool.** A Module
that spawns its own threads to get concurrency has escaped both the isolation
policy and the resilience policy.

## 9. The ABI boundary is layered

Rust traits are **not** the dynamic library boundary. Treating them as one is
undefined behaviour waiting for a compiler upgrade.

```text
dynamic library boundary
    -> stable C ABI entrypoint
    -> versioned module descriptor and function table
    -> Xmip-owned safe wrapper
    -> Rust traits, inside the Host Service
```

`xmip-core-abi` defines the contracts module authors implement and the wrappers
rely on. The dynamic ABI is explicit, versioned, and **checked before a Module
is accepted** — not after it has been dlopened and called.

## 10. Isolation

A Module may run in-process, out-of-process, in a trusted or untrusted Host
Service, and at a declared execution width — 32-bit, 64-bit, 128-bit, a qubit
count, or native.

The runtime decides where, from: Host type, Artifact Definition, the Module
manifest, trust, platform and configured policy.

There is **no low-latency host type.** Earlier drafts listed one alongside the
32-bit and 64-bit cases, as though latency were a property a process could
declare. ADR-0018 clause 10a settled it: latency is bought with isolation and
paid for in process hops. A Host Service configured as Reader, Executor *and*
Writer runs a whole Journey without crossing a boundary; three Host Services
doing the same work pay three hops. The role combination in
`deployment-model.md` is the real control, and a boolean was never going to be.

## 11. Deployment targets do not change any of this

IoT device, edge node, single on-premises server, on-premises cluster, cloud
node, cloud cluster, hybrid — these are deployment profiles, not runtime models.
**The semantics above hold identically on all of them**, which is the entire
reason for keeping the runtime small. `deployment-model.md` owns the profiles.
