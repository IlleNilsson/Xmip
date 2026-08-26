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
Definition           configured intent, declared in TOML
Instance             Definition + Module Instance + validated Contracts
```

Collapsing any two of these is the failure this document exists to prevent. The
runtime does not implement capability. A Module does not decide execution truth.
A Definition is not running. An Instance is not configurable.
`runtime-model.md` section 21 owns the Definition/Instance rule and the naming
convention that goes with it.

### Modules follow the same split

A **Module Definition** describes a deployable module as configured or known to
Xmip. A **Module Instance** is that module loaded into one specific runtime
boundary — comparable to a loaded assembly in .NET or a classpath element in
Java.

**One Module Definition yields many Module Instances**, across nodes,
processes, containers, isolation boundaries and deployment profiles. A
Definition binds to a Module *Instance*, not to an abstract module name, which
is what makes "which copy of the FTP handler actually ran this" answerable.

### What a Module may be written in

```text
Rust    C    C++    COM    DCOM    PowerShell    .NET    Java
native binaries    legacy enterprise adapters    industrial adapters
```

**Node.js and JavaScript server solutions are not a target module
technology.** The C ABI in section 10 is what makes this list possible; a
language that cannot produce or call a stable C entry point cannot host a
Module.

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

### Communication layering

`supported technologies` is not one field's worth of truth. A Module declaring
a communication capability declares all five layers:

```text
Communication Medium -> Transport -> Protocol -> Interaction Pattern -> Capability
```

| Layer | Examples |
| --- | --- |
| Medium | IP network, CAN network, serial, file system, broker or cloud service, wireless/IoT |
| Transport | TCP, UDP, CANBUS, RS-232, RS-485 |
| Protocol | HTTP, FTP, AMQP, MQTT, MLLP, DNS, SNMP, CoAP, J1939, CANopen |
| Interaction pattern | REST, SOAP, Web API, WebHook, queue, topic, subject, stream, polling, event-driven |
| Capability | receive, send, poll, publish, subscribe, acknowledge, replay, track offset, read/write/move/delete file, monitor directory, broadcast, multicast, read telemetry, write command |

**Not every technology uses every layer, and not every technology is
IP-based.** CANBUS is not below TCP and not below UDP; it is a transport under
the CAN network medium. The runtime must never assume that CANBUS, TCP, UDP,
HTTP, queues, files and industrial protocols belong to one hierarchy — the
five layers exist precisely so that no false inheritance is needed to describe
them.

`repository-model.md` section 4 declares the dependencies that do exist —
HTTP on TCP, MLLP on TCP — and those are real because both sit on the IP
medium. They are declared, never inferred.

## 7. Handler lineage

Some Modules belong to the same technology family and share behaviour,
configuration concepts, operational constraints or protocol expectations. The
manifest declares that too:

```text
family    base component id    derived-from component ids    supported technologies
```

**This is not source-code inheritance.** It is metadata, and it exists so that
family knowledge can be shared without the runtime learning any of it.

| Family | Shared concepts |
| --- | --- |
| **TCP** | connection management, session handling, request/response, streaming, framing, timeout, keepalive, connection pooling, TLS |
| **Queue** | queue, topic, subject, stream and partition identity, consumer group, durable subscription, acknowledgement, visibility timeout, offset, cursor, dead-letter behaviour, competing consumers, ordered or unordered delivery |
| **File** | local and shared file, directory watch, polling, event-driven |
| **Industrial / IoT** | declared reliability semantics — see below |

**Each concrete Module declares what it actually supports.** A family
describes shared vocabulary, not a guarantee that every member implements all
of it.

UDP deserves its own note, because it is where this most often goes wrong.
**UDP provides neither ordering nor reliable delivery.** A UDP-based Module
needing reliability, ordering, de-duplication, acknowledgement, replay or
persistence must declare and implement those capabilities itself, or bind to
Xmip persistence semantics. It may not assume the runtime supplies them.

FTPS belongs to the FTP family: it is FTP with TLS. **SFTP does not** — it is
the SSH File Transfer Protocol, sharing a purpose with FTP and nothing else.
See `runtime-model.md` section 23, conflict 10.

### The runtime learns none of it

> The runtime does not implement HTTP, REST, SOAP, WebHook, TCP, UDP, CANBUS,
> OPC UA, Modbus, MQTT, Profinet, EtherNet/IP, BACnet, LoRaWAN, CoAP or DDS
> behaviour, and never will.

It reads the metadata above and applies platform rules only: loadability,
compatibility, trust, isolation, ownership, identity, authorization, audit,
retention, configuration binding, retry and outcome policy. Technology
behaviour stays inside the Module.

This is what makes industrial and IoT support a matter of writing Modules
rather than of changing Xmip.

## 8. Loading and registration

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

## 9. Execution thread

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

## 10. The ABI boundary is layered

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

## 11. Isolation

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

## 12. What the runtime relies on Rust for

Rust's guarantees are part of the runtime design, not an implementation
detail:

- Stream values are immutable, always. Changed content creates a new Stream and
  a new Message generation; accumulated context does not.
- **Runtime stages pass work by ownership.** A stage receives a Message,
  persists state where replay requires it, creates an outcome, and hands
  ownership of that outcome to the next stage.
- Channels are preferred for stage handoff. Shared mutable message state is
  avoided.
- Runtime failures return `Result`. **Panics are not runtime control flow.**
- Handler boundaries are traits — inside a Host Service, above the C ABI of
  section 10.
- Configuration is loaded into typed structures, not consulted as text.
- The core runtime avoids `unsafe`.

Ownership handoff is what keeps thread and task boundaries legible, and it is
why section 9 can state so plainly that a Module function runs on the calling
thread: there is no hidden shared state for it to run against.

Two persistence sources of truth, and they are not the same store:
**runtime persistence** is authoritative for replay, **management
persistence** is authoritative for administration.

## 13. Deployment targets do not change any of this

IoT device, edge node, single on-premises server, on-premises cluster, cloud
node, cloud cluster, hybrid — these are deployment profiles, not runtime models.
**The semantics above hold identically on all of them**, which is the entire
reason for keeping the runtime small. `deployment-model.md` owns the profiles.
