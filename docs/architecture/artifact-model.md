# Xmip Artifact Model

This document captures the initial Xmip artifact model.

It is intentionally architecture-first. It does not define final file formats, Rust structs, persistence schemas, or module loading mechanics.

## Core statement

In Xmip, artifacts are defined at startup from TOML configuration.

At runtime, Xmip operates on artifact instances.

```text
TOML configuration
    -> artifact definitions
        -> startup binding
            -> runtime artifact instances
```

## Artifact definition

An artifact definition is a configured capability declaration.

It combines:

- artifact identity,
- artifact category or lifecycle role,
- module reference,
- configuration,
- contract requirements,
- topology references.

An artifact definition is not the running object itself.

It is the startup definition used by a Xmip instance to construct runtime artifact instances.

## Runtime artifact instance

A runtime artifact instance is the in-memory/runtime representation created from an artifact definition when a Xmip kernel starts.

A runtime artifact instance is bound to:

- the Xmip kernel lifecycle,
- a module implementation,
- validated configuration,
- traits/interfaces/contracts,
- current deployment profile,
- preservation and recovery semantics.

The runtime works with instances, not raw TOML.

## Module + configuration

An artifact is not just configuration.

An artifact is also not just a binary module.

Conceptually:

```text
Artifact = Module + Configuration
```

More precisely:

```text
Artifact definition = configured module capability declaration
Runtime artifact instance = activated configured module capability
```

## Artifact identity

Artifact identity belongs to the artifact, not to the concrete module implementation or transport technology.

An artifact may change module implementation while keeping its identity.

Example:

```text
OrdersInbound
    version 1 -> receive-http module
    version 2 -> receive-mqtt module
```

`OrdersInbound` remains the same artifact identity.

Newer runtime artifact instances use the new module/configuration after startup or redeployment.

This means preservation, lineage, and deployment history must not be anchored only to the concrete implementation technology.

## Kernel knowledge

The Xmip kernel knows the universal integration lifecycle categories:

- receive,
- deserialize,
- transform,
- process/orchestrate,
- serialize,
- send,
- preserve,
- recover.

The kernel does not know each implementation.

The kernel trusts traits, interfaces, and contracts.

## Module implementation

Modules realize artifact behavior.

Modules may be provided by Xmip or by third parties.

A module may be implemented using technologies such as:

- Rust,
- C,
- C++,
- COM,
- DCOM,
- PowerShell,
- .NET,
- Java,
- native binaries,
- legacy enterprise adapters,
- industrial adapters.

Node.js / JavaScript server solutions are not a target module technology for Xmip.

## Kernel-to-module boundary

Inside a Xmip host, the Rust kernel interacts with modules through traits, interfaces, or equivalent contracts.

```text
Xmip Rust Kernel
    -> traits / interfaces / contracts
        -> module implementation
```

The kernel invokes contracts, not concrete implementation details.

## Kernel-to-kernel boundary

Between Xmip hosts, the transport protocol is gRPC and the standardized data is Protocol Buffers.

```text
Xmip host
    -> Protocol Buffers over gRPC
        -> Xmip host
```

This is separate from the kernel-to-module boundary.

## Startup flow

A Xmip instance startup should conceptually perform the following:

1. Load kernel configuration.
2. Load available modules.
3. Load TOML artifact definitions.
4. Resolve artifact categories and module references.
5. Validate configuration against required traits/interfaces/contracts.
6. Create runtime artifact instances.
7. Validate topology references between artifact instances.
8. Start eligible receive/schedule/runtime entry points.

## Receive artifacts

ReceivePort and ReceiveLocation are both artifacts.

At runtime, both become runtime artifact instances.

### ReceivePort

A ReceivePort is a named placeholder for one or more ReceiveLocation artifacts.

It is part of the topology and gives receive locations a stable named place to publish into.

### ReceiveLocation

A ReceiveLocation is a configured receive capability.

It binds a module implementation and configuration to a named ReceivePort.

Example:

```text
ReceivePort artifact definition
    name = Orders

ReceiveLocation artifact definition
    name = OrdersInbound
    module = receive-http
    receivePort = Orders
```

Later, `OrdersInbound` may change transport implementation:

```text
ReceiveLocation artifact definition
    name = OrdersInbound
    module = receive-mqtt
    receivePort = Orders
```

`OrdersInbound` remains the same artifact identity.

Newer artifact instances use MQTT instead of HTTP.

## Example concept

A receive location is not merely a TOML file and not merely a receive module.

It is a configured module capability.

```text
receive module
    + receive configuration
        -> receive artifact definition
            -> receive artifact instance at runtime
```

The same principle applies to send locations, transformations, processors/orchestrations, serializers, deserializers, and other capability categories.

## Open questions

The following remain open and must not be guessed:

1. Are subscriptions artifacts, relationships, or both?
2. Is there a deployment artifact that groups artifact definitions?
3. What exact state is preserved for an artifact instance?
4. What is the minimum TOML structure for the smallest valid Xmip deployment?
5. Are SendPort and SendLocation related in the same way as ReceivePort and ReceiveLocation?
