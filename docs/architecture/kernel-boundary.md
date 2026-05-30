# Xmip Kernel Boundary

This document defines what belongs in the Xmip runtime kernel and what must remain outside as deployable modules.

The purpose is to keep Xmip deployable from the smallest possible footprint up to clustered on-prem and cloud deployments.

## Core principle

The kernel owns runtime truth.

Modules provide capability.

Artifacts describe topology.

These three concepts must remain separate.

```text
Kernel  = runtime law and execution truth
Module  = deployable executable capability
Artifact = declarative topology/configuration
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

### Runtime state machine

The kernel owns valid runtime state transitions.

Examples:

```text
ReceiveLocation
ReceivePort
Analyze
Deserialize
Promote
Publish
ProcessLane
DeliveryLane
SendOut
Complete
```

The exact implementation may evolve, but state progression remains kernel-owned.

### Preservation

The kernel owns preservation semantics.

Preservation includes:

- ingress stream preservation,
- execution checkpoints,
- lineage,
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

The kernel owns the semantic contract for publishing and subscription resolution.

Modules may implement subscription matching or optimized routing, but they must not redefine the meaning of publish/subscribe execution.

### Runtime contracts

The kernel owns cross-language runtime contracts.

The stable boundary is protobuf/gRPC-compatible messages and buffers.

Endpoint modules and integrations may be implemented in other languages or script technologies, but they must communicate through the runtime contract.

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

## Deployment rule

If an IoT deployment can run without a capability, that capability is not kernel.

If a single receive/send topology can run without a capability, that capability is not kernel.

If a capability exists only for clustered on-prem or cloud deployments, it is not kernel; it is a cluster module or deployment profile module.

## Supported deployment range

Xmip must support the following deployment range without changing the kernel semantics:

```text
IoT device
Edge node
Single on-prem server
On-prem server cluster
Cloud node
Cloud cluster
Hybrid on-prem/cloud
```

## Kernel test

A proposed kernel feature must answer yes to at least one of these questions:

1. Is it required to preserve execution truth?
2. Is it required to recover execution?
3. Is it required to maintain lineage?
4. Is it required for publish/subscription semantics?
5. Is it required for the protobuf/gRPC runtime contract?

If not, it belongs in a module.

## Consequence

The kernel must remain small.

Xmip grows by adding deployable modules, not by expanding the kernel.
