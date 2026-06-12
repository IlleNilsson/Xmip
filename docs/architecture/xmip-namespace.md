# Xmip Namespace Model

Xmip shall use its own namespace to make architecture terms explicit.

The namespace makes it clear when a term refers to an Xmip runtime concept rather than a general business, operating-system, or programming-language concept.

## Principle

```text
Xmip.<Term>
```

means the term is part of Xmip architecture.

Examples:

```text
Xmip.Process
Xmip.Message
Xmip.Interchange
Xmip.Artifact
Xmip.Handler
Xmip.Extension
```

Outside Xmip, the same words may have broader meanings.

Inside Xmip, the namespace wins.

## Core namespaces

```text
Xmip.Kernel
Xmip.Cluster
Xmip.Node
Xmip.Host
Xmip.Module
Xmip.Handler
Xmip.Extension
```

## Artifact namespaces

```text
Xmip.Artifact.Definition
Xmip.Artifact.Instance

Xmip.Receive.Port
Xmip.Receive.Location

Xmip.Subscription

Xmip.Process.Definition
Xmip.Process.Instance
Xmip.Process.State
Xmip.Process.Stage
Xmip.Process.Outcome

Xmip.Send.Port
Xmip.Send.Location
```

## Message and interchange namespaces

```text
Xmip.Message
Xmip.Message.Section
Xmip.Message.Metadata

Xmip.Interchange
Xmip.Interchange.Chain
Xmip.Interchange.History
```

## Auditing namespaces

```text
Xmip.Audit
Xmip.Audit.Event
Xmip.Audit.Directive
Xmip.Audit.FailurePersistence
```

## Configuration namespaces

```text
Xmip.Configuration
Xmip.Configuration.Toml
Xmip.Configuration.RuntimeSettings
Xmip.Configuration.ArtifactDefinition
Xmip.Configuration.ModuleLoading
```

## Runtime namespaces

```text
Xmip.Runtime
Xmip.Runtime.Persistence
Xmip.Runtime.Execution
Xmip.Runtime.Ownership
Xmip.Runtime.Recovery
Xmip.Runtime.Retry
Xmip.Runtime.Failover
```

## Communication namespaces

```text
Xmip.Communication
Xmip.Communication.Medium
Xmip.Communication.Transport
Xmip.Communication.Protocol
Xmip.Communication.Pattern
Xmip.Communication.Capability
```

## Code layout intention

Rust crate/module naming should mirror the namespace where reasonable.

Example:

```text
xmip::process::definition
xmip::process::instance
xmip::process::state

xmip::message::message
xmip::message::section

xmip::interchange::chain
xmip::interchange::history

xmip::artifact::definition
xmip::artifact::instance

xmip::audit::event
xmip::audit::directive
```

## Process naming

`Xmip.Process` means the Xmip runtime artifact.

A normal human or organizational process may still be described in ordinary language, such as:

```text
Order fulfillment process
Patient admission process
Manufacturing process
```

Those are not automatically `Xmip.Process` objects unless represented by Xmip configuration and runtime state.

## Rule

When there is ambiguity, qualify the term with `Xmip.`.

When a concept is not part of Xmip runtime, do not force it into the Xmip namespace.
