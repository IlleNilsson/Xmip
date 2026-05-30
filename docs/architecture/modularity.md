# Xmip Deployment Modularity Model

Xmip modularity is not only source-code organization. Xmip must be modular at deployment and runtime capability level.

The same platform family must be able to run as:

- a tiny IoT deployment with only the minimum required runtime capabilities,
- a small edge/node deployment,
- a single-server integration runtime,
- an on-prem cluster,
- a cloud cluster.

## Principle

Xmip must ship as the smallest valid runtime needed for a given topology.

A deployment should not require receive technologies, send technologies, persistence engines, process hosts, or tooling that the topology does not use.

## Terms

### Xmip Runtime Kernel

The minimal execution core.

Responsible for:

- execution context,
- durable state transition,
- checkpoint/recovery boundary,
- lineage,
- preservation hooks,
- protobuf/gRPC-compatible runtime contracts.

The kernel should remain small and portable.

### Xmip Runtime Module

A deployable capability unit loaded by the runtime.

This is the Xmip equivalent of what other ecosystems may call DLLs, shared libraries, plugins, packages, crates, assemblies, or extension modules.

A runtime module may provide:

- receive handlers,
- send handlers,
- content deserializers,
- format analyzers,
- property promoters,
- process/orchestration handlers,
- transformation handlers,
- persistence providers,
- observability exporters,
- security/identity providers.

### Xmip Artifact

A declarative configuration/topology unit.

Artifacts describe what Xmip should run.

Runtime modules provide executable capability.

Artifacts and runtime modules must not be confused.

## Cross-language endpoint boundary

Xmip endpoints may interact with other languages and script technologies.

Examples:

- PowerShell,
- .NET,
- Rust,
- Python,
- Java,
- Node.js,
- Bash,
- native tools,
- industrial/embedded runtimes.

The kernel must not assume that endpoints are implemented in Rust.

The stable interoperability boundary is protobuf/gRPC-compatible messages and buffers.

This allows endpoint modules or external adapters to be implemented in different languages while still interacting with the Xmip runtime contract.

## Footprint profiles

### Micro / IoT profile

Minimum possible footprint.

May include only:

- runtime kernel,
- one receive module,
- one format/deserializer/promoter module,
- one send module,
- local persistence/checkpoint module.

No cluster coordination required.

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

- runtime kernel,
- cluster persistence,
- lease/claim coordination,
- recovery orchestration,
- placement logic,
- isolation enforcement,
- distributed observability.

### Cloud profile

Cluster profile plus cloud-native deployment and scaling.

May include:

- cloud persistence providers,
- cloud identity providers,
- cloud observability exporters,
- cloud-native packaging.

## Architectural rule

No Xmip runtime module may redefine core runtime semantics.

Runtime modules may extend capability, but the kernel owns:

- execution truth,
- deterministic state progression,
- preservation,
- recovery semantics,
- lineage,
- protobuf/gRPC runtime contract.

## Design consequence

Future code should avoid building all capabilities into the kernel.

Instead, code should move toward explicit module boundaries:

- kernel,
- receive module,
- analyze/deserialize/promote module,
- publish/subscription module,
- process module,
- send module,
- preservation module.

The current Rust prototype is still intentionally small, but the architecture direction is deployment modularity, not only source-file modularity.
