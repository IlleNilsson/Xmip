# Xmip Artifact Model

This document captures the current Xmip artifact model.

It is intentionally architecture-first. It does not define final file formats, Rust structs, persistence schemas, or module loading mechanics.

## Core statement

Xmip distinguishes between definition-time concepts and runtime concepts.

Definitions live in configuration and Continuum.

Instances live in runtime.

The word Artifact should be treated as an umbrella term. When precision matters, use Artifact Definition or Artifact Instance.

## Artifact Definition

An Artifact Definition is a configured runtime-capability declaration.

An Artifact Definition is composed of:

- configuration,
- Xmip-supported capability contracts,
- configured module references,
- artifact identity,
- artifact category or lifecycle role,
- topology references.

An Artifact Definition is not the running object itself.

It is the configured intent used by a Xmip instance to construct Artifact Instances at runtime.

Conceptually:

```text
Artifact Definition
    = Configuration
    + Xmip Capability Contracts
    + Configured Module References
```

## Artifact Instance

An Artifact Instance is the runtime result of resolving and binding an Artifact Definition.

An Artifact Instance exists only after the Xmip kernel has:

1. loaded relevant configuration,
2. loaded configured modules,
3. resolved configured module references,
4. validated required capability contracts,
5. created runtime context.

Conceptually:

```text
Artifact Instance
    = Artifact Definition
    + Loaded Modules
    + Validated Contracts
    + Runtime Context
```

The runtime operates on Artifact Instances, not raw TOML and not module code alone.

## Module Definition and Module Instance

Modules also follow the definition/instance distinction.

A Module Definition describes a deployable module as configured or known to Xmip.

A Module Instance is a loaded module in a specific runtime boundary.

A Module Instance may be compared to a loaded assembly in .NET or a loaded JAR/classpath element in Java.

The same Module Definition may result in multiple Module Instances across different nodes, processes, containers, isolation boundaries, or deployment profiles.

Conceptually:

```text
Module Definition
    -> Loaded Module
        -> Module Instance
```

Artifact Instances are bound to Module Instances, not merely to abstract module names.

## Definition and Instance acronym convention

Xmip uses a consistent architectural shorthand outside source code:

```text
D = Definition
I = Instance
```

Examples:

```text
AD = Artifact Definition
AI = Artifact Instance
MD = Module Definition
MI = Module Instance
SD = Subscription Definition
SI = Subscription Instance
```

These acronyms are for architecture discussions, diagrams, and compact documentation.

Source code should prefer explicit names such as ArtifactDefinition and ArtifactInstance.

Logs should also prefer explicit names.

## Artifact identity

Artifact identity belongs to the Artifact Definition and its runtime lineage, not to the concrete module implementation or transport technology.

An artifact may change module implementation while keeping its identity.

Example:

```text
OrdersInbound
    version 1 -> receive-http module
    version 2 -> receive-mqtt module
```

`OrdersInbound` remains the same artifact identity.

Newer Artifact Instances use the new module/configuration after startup or redeployment.

This means preservation, lineage, audit, tracking, and deployment history must not be anchored only to the concrete implementation technology.

## Kernel knowledge

The Xmip kernel knows Xmip-supported capability categories and contracts.

Examples include:

- receive,
- deserialize,
- transform,
- promote,
- publish,
- process/orchestrate,
- serialize,
- send,
- preserve,
- recover,
- audit,
- track,
- validate.

The kernel does not know each concrete implementation.

The kernel trusts traits, interfaces, and contracts.

## Module implementation

Modules realize configured capabilities.

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
        -> Module Instance
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
2. Load configured module declarations.
3. Load available modules.
4. Create Module Instances for loaded modules.
5. Load TOML Artifact Definitions.
6. Resolve artifact categories and configured module references.
7. Validate Artifact Definitions against required capability contracts.
8. Bind Artifact Definitions to compatible Module Instances.
9. Create Artifact Instances.
10. Validate topology references between Artifact Instances.
11. Start eligible receive/schedule/runtime entry points.

## Receive artifacts

ReceivePort and ReceiveLocation are both Artifact Definitions at configuration time.

At runtime, both become Artifact Instances.

### ReceivePort

A ReceivePort Definition is a named placeholder for one or more ReceiveLocation Definitions.

It is part of the topology and gives receive locations a stable named place to publish into.

A ReceivePort Definition may have multiple ReceiveLocation Definitions bound to it.

At runtime, a ReceivePort Instance provides the runtime receive topology target.

### ReceiveLocation

A ReceiveLocation Definition is a configured receive capability.

It binds configuration, receive capability contracts, and configured module references to a named ReceivePort Definition.

Example:

```text
ReceivePort Definition
    name = Orders

ReceiveLocation Definition
    name = OrdersInbound
    module = receive-http
    receivePort = Orders
```

Later, `OrdersInbound` may change transport implementation:

```text
ReceiveLocation Definition
    name = OrdersInbound
    module = receive-mqtt
    receivePort = Orders
```

`OrdersInbound` remains the same artifact identity.

Newer ReceiveLocation Instances use MQTT instead of HTTP.

## Send artifacts

SendPort and SendLocation are both Artifact Definitions at configuration time.

At runtime, both become Artifact Instances.

A SendPort Definition may have multiple SendLocation Definitions bound to it.

The detailed send semantics, including delivery rules, retry behavior, failover behavior, success with warnings, and error behavior, must be defined separately.

## Subscription artifacts

A Subscription Definition is an Artifact Definition in TOML.

A Subscription Definition contains a set of rules.

When those rules evaluate to true at runtime, the Subscription Definition causes a runtime action according to its Artifact Definition.

That action may publish.

At runtime, matching subscriptions create Subscription Instances.

A Subscription Instance is chained runtime metadata attached to the message journey until the message leaves Xmip through a SendLocation.

The Subscription Instance chain is similar to a call stack in a programming language: it records how a message was published through Xmip over time.

A publication can publish back into Xmip, where additional subscriptions may evaluate and cause further actions.

## Message journey participation

Artifacts and modules participate while a message or stream is passing through Xmip.

The message journey is primary.

Artifacts and modules do not own the message lifecycle.

## Example concept

A receive location is not merely a TOML file and not merely a receive module.

At configuration time, it is a ReceiveLocation Definition composed of configuration, Xmip receive capability contracts, and configured module references.

At runtime, it becomes a ReceiveLocation Instance when the kernel binds the definition to compatible loaded Module Instances and runtime context.

```text
ReceiveLocation Definition
    + Module Instance
    + Validated Contracts
    + Runtime Context
        -> ReceiveLocation Instance
```

The same principle applies to send locations, transformations, processors/orchestrations, serializers, deserializers, subscriptions, validations, tracking, audit, and other capability categories.

## Open questions

The following remain open and must not be guessed:

1. Is there a deployment artifact that groups Artifact Definitions?
2. What exact state is preserved for an Artifact Instance?
3. What is the minimum TOML structure for the smallest valid Xmip deployment?
4. What are the exact SendPort and SendLocation runtime semantics?
5. How are Subscription Instance chains bounded, recovered, and protected from cycles?
6. Which Message Contracts are first-class Artifact Definitions, and which are module-provided validation capabilities?
