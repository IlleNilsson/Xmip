# Xmip Definition and Instance Model

Xmip shall not use a generic parent term such as Artifact, Enabler, Component, Construct, or Participant.

Instead Xmip uses explicit Definition and Instance terminology.

## Principle

Every configurable Xmip object has:

```text
Definition
Instance
```

A Definition exists in TOML.

An Instance exists in runtime.

## Examples

```text
ReceivePortDefinition
ReceivePortInstance

ReceiveLocationDefinition
ReceiveLocationInstance

SubscriptionDefinition
SubscriptionInstance

ProcessDefinition
ProcessInstance

SendPortDefinition
SendPortInstance

SendLocationDefinition
SendLocationInstance
```

## Ownership

Definitions describe what may exist.

Instances describe what is executing or has executed.

## Rule

Avoid introducing artificial parent nouns.

Prefer the actual Xmip concept.

Example:

```text
Good:
    ProcessDefinition
    ProcessInstance

Avoid:
    ArtifactDefinition
    EnablerDefinition
    ComponentDefinition
```

The Xmip concept itself is the parent.

Definition and Instance describe its lifecycle state.
