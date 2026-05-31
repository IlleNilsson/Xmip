# Xmip Artifact Model

This document captures the initial Xmip artifact model.

It is intentionally architecture-first. It does not define final file formats, Rust structs, persistence schemas, or module loading mechanics.

## Core statement

In Xmip, artifacts are defined at startup from TOML configuration.

The TOML configuration defines Artifact Definitions.

An Artifact Definition does not become useful by itself.

At runtime, the Xmip kernel combines an Artifact Definition with loaded module code that satisfies the required traits, interfaces, or contracts.

That combination becomes an Artifact Instance.

```text
TOML configuration
    -> Artifact Definition
        + loaded module code
        + validated contracts
            -> Artifact Instance at runtime
```

The runtime operates on Artifact Instances, not raw TOML and not module code alone.

## Artifact Definition

An Artifact Definition is a configured capability declaration.

It combines:

- artifact identity,
- artifact category or lifecycle role,
- module reference,
- configuration,
- contract requirements,
- topology references.

An Artifact Definition is not the running object itself.

It is the startup definition used by a Xmip instance together with loaded module code to construct Artifact Instances.

## Artifact Instance

An Artifact Instance is the runtime result of binding an Artifact Definition to module code.

An Artifact Instance exists only after the Xmip kernel has loaded modules, resolved the Artifact Definition, validated configuration, and bound the definition to a contract-compatible implementation.

An Artifact Instance is bound to:

- the Xmip kernel lifecycle,
- a module implementation,
- validated configuration,
- traits/interfaces/contracts,
- current deployment profile,
- preservation and recovery semantics.

The runtime works with Artifact Instances.

## Module + configuration

An artifact is not just configuration.

An artifact is also not just module code.

Conceptually:

```text
Artifact Definition + Module Code = Artifact Instance
```

or:

```text
Artifact Definition = configured module capability declaration
Artifact Instance = runtime-bound configured module capability
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

Newer Artifact Instances use the new module/configuration after startup or redeployment.

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
3. Load TOML Artifact Definitions.
4. Resolve artifact categories and module references.
5. Validate configuration against required traits/interfaces/contracts.
6. Bind Artifact Definitions to module code.
7. Create Artifact Instances.
8. Validate topology references between Artifact Instances.
9. Start eligible receive/schedule/runtime entry points.

## Receive artifacts

ReceivePort and ReceiveLocation are both artifacts.

At runtime, both become Artifact Instances.

### ReceivePort

A ReceivePort is a named placeholder for one or more ReceiveLocation artifacts.

It is part of the topology and gives receive locations a stable named place to publish into.

A ReceivePort may have multiple ReceiveLocation artifacts bound to it.

### ReceiveLocation

A ReceiveLocation is a configured receive capability.

It binds a module implementation and configuration to a named ReceivePort.

Example:

```text
ReceivePort Artifact Definition
    name = Orders

ReceiveLocation Artifact Definition
    name = OrdersInbound
    module = receive-http
    receivePort = Orders
```

Later, `OrdersInbound` may change transport implementation:

```text
ReceiveLocation Artifact Definition
    name = OrdersInbound
    module = receive-mqtt
    receivePort = Orders
```

`OrdersInbound` remains the same artifact identity.

Newer Artifact Instances use MQTT instead of HTTP.

## Send artifacts

SendPort and SendLocation are both artifacts.

At runtime, both become Artifact Instances.

A SendPort may have multiple SendLocation artifacts bound to it.

The detailed send semantics, including delivery rules, retry behavior, failover behavior, success with warnings, and error behavior, must be defined separately.

## Subscription artifacts

A Subscription is an Artifact Definition in TOML.

A Subscription contains a set of rules.

When those rules evaluate to true, the Subscription publishes.

At runtime, matching subscriptions create Subscription Instances.

A Subscription Instance is chained runtime metadata attached to the message journey until the message leaves Xmip through a SendLocation.

The Subscription Instance chain is similar to a call stack in a programming language: it records how a message was published through Xmip over time.

A publication can publish back into Xmip, where additional subscriptions may evaluate and publish again.

## Example concept

A receive location is not merely a TOML file and not merely a receive module.

It is a configured module capability declared in TOML and activated with module code at runtime.

```text
receive module code
    + receive Artifact Definition
        -> receive Artifact Instance at runtime
```

The same principle applies to send locations, transformations, processors/orchestrations, serializers, deserializers, subscriptions, and other capability categories.

## Open questions

The following remain open and must not be guessed:

1. Is there a deployment artifact that groups Artifact Definitions?
2. What exact state is preserved for an Artifact Instance?
3. What is the minimum TOML structure for the smallest valid Xmip deployment?
4. What are the exact SendPort and SendLocation runtime semantics?
5. How are Subscription Instance chains bounded, recovered, and protected from cycles?
