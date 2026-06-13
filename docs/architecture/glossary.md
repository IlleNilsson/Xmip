# Xmip Glossary

Xmip architecture shall use one term for one concept.

## Kernel

The Kernel is the stable Xmip runtime core.

The Kernel loads Modules, applies runtime policy, controls execution, owns persistence boundaries, and enforces auditing, tracing, tracking, identity, authorization, and lifecycle rules.

The Kernel shall not hard-code technology behavior.

## TOML Configuration

TOML configuration defines set values that affect Xmip runtime behavior and the Definitions a node can handle.

TOML configuration is not runtime state.

TOML configuration defines what may exist and how it should be configured.

Runtime persistence records what did happen, what is happening, and what must resume or be audited.

## Definition

A Definition is a named Xmip configuration object defined in TOML.

A Definition declares what may exist and how it is configured.

Examples:

- ReceivePortDefinition,
- ReceiveLocationDefinition,
- SubscriptionDefinition,
- ProcessDefinition,
- SendPortDefinition,
- SendLocationDefinition,
- ContractDefinition.

A Definition may declare:

- name,
- kind-specific configuration,
- Handler reference where applicable,
- Handler configuration where applicable,
- runtime-affecting configuration values,
- contracts or contract references where applicable,
- security requirements where applicable,
- tracing and tracking settings where applicable.

A Definition describes what a node may handle.

A Definition does not process a message by itself.

## Instance

An Instance is the runtime execution of a Definition.

An Instance is created when Xmip runtime uses a Definition to handle a specific message, stream, action, or execution scope.

An Instance handles the message it was given.

An Instance is auditable and may be traceable and trackable according to policy.

Runtime persistence records Instance state, outcome, failure, retry, and recovery information where applicable.

Examples:

- ReceivePortInstance,
- ReceiveLocationInstance,
- SubscriptionInstance,
- ProcessInstance,
- SendPortInstance,
- SendLocationInstance.

## Definition versus Instance

Definition means configured in TOML.

Instance means running or previously run in runtime.

Examples:

```text
ReceiveLocationDefinition
    -> ReceiveLocationInstance

SendLocationDefinition
    -> SendLocationInstance

ProcessDefinition
    -> ProcessInstance
```

## Module

A Module is a loadable Xmip capability package.

A Module is loaded at startup according to Xmip TOML configuration.

A Module may define:

- Handlers,
- Extensions.

## Handler

A Handler is a technology-specific trait/interface implemented by a Module.

A Handler has a specific technology purpose.

Examples:

- HTTP Handler,
- FTP Handler,
- SFTP Handler,
- RabbitMQ Handler,
- Kafka Handler,
- File Handler,
- CANBUS Handler,
- FHIR Handler,
- HL7 Handler.

Handlers implement communication, protocol, format, or technology behavior.

Handlers are incorporated as contracts such as traits or interfaces so the Kernel can call them through stable boundaries.

## Extension

An Extension is a utility capability defined by a Module.

An Extension is loaded at startup according to Xmip TOML configuration.

An Extension may be used from anywhere within the Xmip runtime where policy allows it.

Extensions connect Xmip to external executable code, shared libraries, scripts, language runtimes, or utility behavior.

Examples:

- .NET Extension,
- Java Extension,
- Python Extension,
- Go Extension,
- Rust Extension,
- C/C++ Extension,
- PowerShell Extension,
- Bash Extension,
- company-specific utility Extension.

## Handler versus Extension

A Handler has a technology purpose.

An Extension has a utility purpose.

Handlers bind Xmip to external communication, protocol, format, or transport behavior.

Extensions provide reusable executable capability callable from within Xmip runtime.

## Interchange

An Interchange is a trackable message-flow lineage through Xmip.

When a message first enters Xmip, Xmip creates a root Interchange with an interchange id.

When a message is assigned, transformed, or otherwise produces a new trackable message lineage, Xmip creates a child Interchange with a new interchange id.

The child Interchange references its parent Interchange.

A message therefore carries an interchange chain, not only a single interchange id.

The interchange chain allows Xmip to track the full parent-child journey of a message through receive, assignment, transformation, process, subscription, send, retry, failure, and recovery.

## Interchange Chain

An Interchange Chain is the ordered list of Interchange ids carried by a message.

The first item is the root Interchange.

The last item is the current Interchange.

Example:

```text
Interchange I1
    Message M1 received

Interchange I1 -> I2
    Message M2 created by transformation

Interchange I1 -> I2 -> I3
    Message M3 created by assignment
```

## Interchange History

Interchange History is the persisted history of all messages sprung from the original incoming message.

Interchange History shall be persisted until all messages sprung from the incoming message have left Xmip or reached a terminal Xmip outcome.

The detail level of Interchange History persistence is controlled by Xmip TOML configuration.

Depending on configuration, Interchange History may persist metadata only, stream references, selected sections, full message states, or full message payloads.

Regardless of configured detail level, messages in the Interchange History must be recoverable and viewable according to the configured retention and security policy while the history is active.

## Message

A Message is an immutable processing unit within an Interchange Chain.

A Message has:

- message id,
- interchange chain,
- current interchange id,
- metadata,
- one or more Sections.

A new Message is created when Xmip performs an operation that creates a new message state, such as assignment or transformation.

Routing alone does not create a new Message.

## Section

A Section is a stream contained within a Message.

Each Section has:

- section id,
- metadata,
- stream reference.

A Message contains one or more Sections.

Sections may reuse stream references when content is unchanged.

## Audit

Audit is the persistent accountability record of Xmip actions and outcomes.

Failures are always audited.

The following lifecycle events are always audited:

- entry into Xmip,
- leaving Xmip,
- assigned,
- transformed,
- passed on,
- picked up,
- sent,
- failure.

Audit policy may decide additional successful actions to persist as audit records, but the mandatory lifecycle events and failures are not optional.

## Failure Persistence

When a failure occurs, Xmip shall persist the message in its failure-time state.

The persisted failure state shall include:

- message id,
- interchange chain,
- current interchange id,
- message metadata,
- section metadata,
- stream references or stored streams as required by policy,
- Instance context,
- failure reason,
- failure classification,
- time of failure,
- runtime place where failure occurred.

Failure persistence is mandatory.

Failure persistence is part of auditability.

Failure persistence exists so Xmip can inspect, report, recover, retry, move to a dead message queue, or explain what failed and why.

## Retired terms

### Adapter

Retired.

Use Handler.

### Plugin

Retired.

Use Module, Handler, or Extension depending on the exact meaning.

### Artifact

Retired.

Use explicit Definition and Instance names instead.

### Enabler

Retired.

Use explicit Definition and Instance names instead.

## Terminology hierarchy

```text
Kernel
    Module
        Handler
        Extension
```

```text
TOML Configuration
    Runtime settings
    Definitions
```

```text
Definition
    TOML configuration
    may reference Handler
    may contain Handler configuration
```

```text
Runtime
    Instance
        handles assigned message
```

```text
Message
    Interchange Chain
        root Interchange
        current Interchange
    Interchange History
    Sections
```

```text
Failure
    persists message state
    persists interchange chain
    persists Instance context
```

```text
Audit
    mandatory lifecycle events
    mandatory failures
```

```text
Handler
    = technology-specific trait/interface
```

```text
Extension
    = reusable runtime utility capability
```
