# Xmip Kernel Boundary

This document defines what belongs in the Xmip runtime kernel and what must remain outside as deployable modules.

The purpose is to keep the kernel small while preserving the same runtime semantics across deployment targets.

For foundational terminology, see `docs/architecture/foundations.md`.

## Core principle

The kernel owns runtime truth.

Modules provide executable capability.

Artifact Definitions describe configured intent in TOML.

Artifact Instances are created at runtime when the kernel binds Artifact Definitions to loaded module code that satisfies Xmip contracts.

These concepts must remain separate.

```text
Kernel              = runtime law and execution truth
Module              = deployable executable capability
Artifact Definition = TOML configured capability declaration
Artifact Instance   = Artifact Definition + Module Code + Validated Contracts
```

## Kernel responsibilities

The kernel owns the minimum runtime semantics required for every Xmip deployment.

### Execution context

The kernel defines and preserves the authoritative execution context.

Includes:

- execution identity,
- current runtime state,
- runtime generation,
- lineage,
- checkpoint boundary,
- preservation state,
- recovery state.

### Runtime state progression

The kernel owns valid runtime state progression.

Xmip is not a mandatory linear pipeline.

Messages may be received, optionally deserialized, optionally transformed, optionally promoted, published, subscribed, processed, serialized, and sent according to Artifact Definitions and runtime context.

Context available before deserialization may already support subscription evaluation.

Examples of context include:

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

Promotion extracts values into message context.

Promotion may happen during transformation.

There is no separate concept of transformed properties.

### Preservation

The kernel owns preservation semantics.

Preservation includes:

- incoming representation preservation,
- execution checkpoints,
- lineage,
- publish/subscribe history,
- replay/recovery boundaries,
- state durability hooks.

### Recovery

The kernel owns recovery semantics.

Recovery must preserve:

- authoritative execution state,
- lineage,
- replay boundary,
- preservation log,
- deterministic continuation.

### Publish and subscription semantics

The kernel owns the semantic contract for publishing and subscription evaluation.

A Subscription is an Artifact Definition.

When a Subscription evaluates true at runtime, it causes a runtime action according to its Artifact Definition.

That action may publish.

Modules may implement subscription matching or optimized routing, but they must not redefine the meaning of publish/subscribe execution.

### Runtime contracts

The kernel owns runtime contracts.

Inside a Xmip host, the kernel interacts with modules through traits, interfaces, or equivalent contracts.

Between Xmip hosts, the transport protocol is gRPC and the standardized data is Protocol Buffers.

These boundaries are different and must not be confused.

## Not kernel responsibilities

The following must not be required in the kernel:

- HTTP,
- MQTT,
- SMTP,
- SFTP,
- file system adapters,
- XML-specific handling,
- JSON-specific handling,
- EDI-specific handling,
- business transformations,
- process/orchestration implementations,
- cloud provider specifics,
- database-specific persistence providers,
- observability exporters,
- UI tooling.

These are deployable modules.

## Deployment targets

Deployment targets do not redefine Xmip runtime semantics.

Examples of deployment targets include:

```text
IoT device
Edge node
Single on-prem server
On-prem server cluster
Cloud node
Cloud cluster
Hybrid on-prem/cloud
```

These are deployment targets or deployment profiles, not separate runtime models.

## Kernel test

A proposed kernel feature must answer yes to at least one of these questions:

1. Is it required to preserve execution truth?
2. Is it required to recover execution?
3. Is it required to maintain lineage?
4. Is it required for publish/subscription semantics?
5. Is it required for the protobuf/gRPC kernel-to-kernel contract?
6. Is it required for kernel-to-module contracts?

If not, it belongs in a module.

## Consequence

The kernel must remain small.

Xmip grows by adding deployable modules and Artifact Definitions, not by expanding the kernel with concrete technology implementations.
