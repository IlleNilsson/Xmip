# Xmip Architecture Foundations

This document records architecture statements currently treated as foundational for Xmip.

The purpose is to prevent later documents, diagrams, and code from drifting away from the intended architecture.

## Xmip purpose

Xmip is about incoming, deserialized, transformed/promoted, processed, serialized, and outgoing messages with traceable publish/subscribe history inside Xmip.

The central runtime concern is the message and its context as it travels through Xmip.

## Kernel

The Xmip kernel is implemented in Rust.

The kernel owns runtime truth.

The kernel owns:

- execution state,
- deterministic state progression,
- preservation,
- recovery,
- lineage,
- publish/subscribe semantics,
- runtime contracts.

The kernel does not know every concrete implementation.

The kernel trusts traits, interfaces, and contracts.

## Modules

Modules provide executable capability.

Modules may be provided by Xmip or by third parties.

Modules realize artifact behavior by implementing Xmip contracts.

Modules may use technologies such as:

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

## Artifact Definitions

Artifact Definitions are defined in TOML configuration.

An Artifact Definition is not a runtime object by itself.

An Artifact Definition describes configured intent and references the module capability needed to realize that intent.

## Artifact Instances

An Artifact Instance is created at runtime when the Xmip kernel binds an Artifact Definition to loaded module code that satisfies the required traits, interfaces, or contracts.

```text
Artifact Definition
    + Module Code
    + Validated Contracts
        = Artifact Instance
```

The runtime operates on Artifact Instances.

## Artifact identity

Artifact identity belongs to the artifact, not to the concrete module implementation.

An artifact may change module or transport while keeping its artifact identity.

Example:

```text
OrdersInbound
    version 1 -> receive-http
    version 2 -> receive-mqtt
```

`OrdersInbound` remains the same artifact identity.

Newer Artifact Instances use the newer module and configuration.

## Port and location artifacts

ReceivePort and ReceiveLocation are artifacts.

SendPort and SendLocation are artifacts.

A port is a named topology placeholder.

A location is a configured capability bound to a port.

A port may have multiple locations.

## Subscriptions

A Subscription is an Artifact Definition in TOML.

A Subscription contains rules.

When a Subscription evaluates true at runtime, it causes a runtime action due to its Artifact Definition.

That action may publish.

A Subscription Instance is runtime metadata attached to the message journey.

Subscription Instances form a traceable chain similar to a call stack.

## Publication

Publication is part of Xmip runtime semantics.

Publication may cause further Subscription rules to evaluate.

A publication may publish back into Xmip.

This means message travel through Xmip may be recursive or chained until it eventually completes, waits, fails, or leaves Xmip through a SendLocation.

## Message

Xmip is centered on messages.

A message may originate from a stream, file, socket, protocol, external system, scheduled event, or another Xmip publication.

During runtime, a message accumulates context, including promoted properties and traceable publish/subscribe history.

## Runtime boundaries

Kernel-to-module communication happens through traits, interfaces, or equivalent contracts.

Kernel-to-kernel communication happens through Protocol Buffers over gRPC.

These boundaries are different and must not be confused.

## Deployment targets

Xmip may be deployed to different targets, such as:

```text
IoT device
Edge node
Single on-prem server
On-prem server cluster
Cloud node
Cloud cluster
Hybrid on-prem/cloud
```

These are deployment targets or deployment profiles.

They are not separate runtime models and do not receive special treatment in the core architecture.

The kernel semantics must remain stable across deployment targets.
