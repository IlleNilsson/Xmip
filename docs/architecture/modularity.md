# Xmip Deployment Modularity Model

Xmip modularity is not only source-code organization.

Xmip must be modular at deployment and runtime capability level.

The same Xmip runtime semantics must apply across deployment targets.

Deployment targets are not separate runtime models.

For foundational terminology, see `docs/architecture/foundations.md`.

## Principle

Xmip must ship as the smallest valid runtime needed for a given topology.

A deployment should not require receive technologies, send technologies, persistence engines, process hosts, orchestration hosts, or tooling that the topology does not use.

Xmip grows by adding deployable modules and Artifact Definitions, not by expanding the kernel with concrete technology implementations.

## Terms

### Xmip Runtime Kernel

The minimal Rust execution core.

Responsible for:

- execution context,
- deterministic state progression,
- preservation,
- recovery,
- lineage,
- publish/subscribe semantics,
- runtime contracts.

The kernel should remain small and portable.

The kernel trusts traits, interfaces, and contracts.

The kernel does not know every concrete implementation.

### Xmip Runtime Module

A deployable capability unit loaded by the runtime.

This is the Xmip equivalent of what other ecosystems may call DLLs, shared libraries, plugins, packages, crates, assemblies, or extension modules.

A runtime module may provide:

- receive capabilities,
- send capabilities,
- content deserializers,
- property promotion capabilities,
- process/orchestration capabilities,
- transformation capabilities,
- serialization capabilities,
- preservation providers,
- recovery providers,
- observability exporters,
- security/identity providers.

A module realizes behavior by implementing Xmip contracts.

### Artifact Definition

An Artifact Definition is defined in TOML configuration.

An Artifact Definition is not a runtime object by itself.

An Artifact Definition describes configured intent and references the module capability needed to realize that intent.

### Artifact Instance

An Artifact Instance is created at runtime when the Xmip kernel binds an Artifact Definition to loaded module code that satisfies the required traits, interfaces, or contracts.

```text
Artifact Definition
    + Module Code
    + Validated Contracts
        = Artifact Instance
```

The runtime operates on Artifact Instances.

## Cross-language module boundary

Xmip modules may be implemented using different technologies as long as they satisfy Xmip contracts.

Examples include:

- Rust,
- C,
- C++,
- COM,
- DCOM,
- PowerShell,
- .NET,
- Java,
- native libraries,
- legacy enterprise adapters,
- industrial adapters.

Node.js / JavaScript server solutions are not target module technologies for Xmip.

The kernel must not assume that modules are implemented in Rust.

Inside a Xmip host, the kernel interacts with modules through traits, interfaces, or equivalent contracts.

Between Xmip hosts, the transport protocol is gRPC and the standardized data is Protocol Buffers.

These boundaries are different and must not be confused.

## Context-driven subscription matching

Xmip is not a mandatory linear pipeline.

Subscriptions evaluate against whatever context is available at the point of publication.

Context may exist before deserialization.

Examples include:

- ReceiveLocation,
- ReceivePort,
- Content Type,
- subject,
- headers,
- metadata,
- file name,
- file attributes,
- queue name,
- promoted properties.

Deserialization, transformation, and promotion are optional stages before publication.

Promotion extracts values into message context.

Promotion may happen during transformation.

There is no separate concept of transformed properties.

## Footprint profiles

Deployment profiles select modules and configuration.

Deployment profiles do not redefine Xmip runtime semantics.

### Micro / IoT profile

Minimum possible footprint.

May include only:

- runtime kernel,
- selected receive module,
- selected deserializer/promoter module if needed,
- selected send module,
- selected local preservation/checkpoint module.

No cluster coordination is required unless explicitly configured.

### Edge profile

Small but more capable deployment.

May include:

- runtime kernel,
- selected receive/send modules,
- local preservation,
- limited process execution,
- lightweight observability.

### Server profile

Single-node enterprise runtime.

May include:

- runtime kernel,
- multiple receive/send modules,
- process/orchestration modules,
- transformation modules,
- stronger persistence,
- operational reporting.

### Cluster profile

Multi-node runtime.

May include:

- runtime kernel on each node,
- cluster persistence,
- lease/claim coordination,
- recovery orchestration,
- placement logic,
- isolation enforcement,
- distributed observability.

### Cloud profile

Cloud-hosted deployment.

May include:

- selected cloud persistence providers,
- selected cloud identity providers,
- selected cloud observability exporters,
- cloud-native packaging.

Cloud deployment does not redefine Xmip runtime semantics.

## Architectural rule

No Xmip runtime module may redefine core runtime semantics.

Runtime modules may extend capability, but the kernel owns:

- execution truth,
- deterministic state progression,
- preservation,
- recovery semantics,
- lineage,
- publish/subscribe semantics,
- kernel-to-module contracts,
- Protocol Buffers over gRPC kernel-to-kernel contract.

## Design consequence

Future code should avoid building all capabilities into the kernel.

Instead, code should move toward explicit module boundaries:

- kernel,
- receive module,
- deserialize/promote module,
- transformation module,
- publish/subscription module,
- process/orchestration module,
- send module,
- preservation module.

The current Rust prototype is still intentionally small, but the architecture direction is deployment modularity, not only source-file modularity.
