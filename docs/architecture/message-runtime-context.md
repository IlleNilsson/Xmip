# Xmip Message Runtime Context

## Purpose

Xmip is centered on messages.

Xmip is about incoming, deserialized, transformed or promoted, processed, serialized, and outgoing messages with traceable publish and subscribe history inside Xmip.

The message and its runtime context are the primary runtime concerns.

## Message lifecycle

Conceptually:

```text
Incoming message
    -> Deserialize
    -> Transform / Promote
    -> Process
    -> Serialize
    -> Outgoing message
```

The exact path is determined by Artifact Definitions, Artifact Instances, Subscription rules, and runtime publications.

## Incoming message

A message may originate from many places, including:

- files,
- streams,
- receive locations,
- scheduled activity,
- external systems,
- another Xmip publication.

The original incoming representation matters, but it is not the whole runtime message.

## Deserialization

Deserialization turns the incoming representation into a form Xmip can reason about.

Deserialization occurs before transformation.

## Transformation and promotion

Transformation changes or enriches message content.

Promotion extracts values and makes them available as runtime context.

Promoted properties support Subscription evaluation, processing decisions, and delivery decisions.

## Processing

Processing performs business activity or orchestration activity.

Processing may continue the message journey and may publish.

## Serialization

Before a message leaves Xmip through a SendLocation, it may be serialized into the required outgoing representation.

## Publish and subscribe history

Xmip maintains traceable publish and subscribe history for the message while it is inside Xmip.

A Subscription is an Artifact Definition.

When a Subscription evaluates true at runtime, it causes runtime action due to its Artifact Definition.

That action may publish.

A Subscription Instance becomes part of the message history.

Subscription Instances form a chain similar to a call stack.

## Runtime message context

The runtime message context is more than payload.

Known categories include:

- message content,
- promoted properties,
- Subscription Instance chain,
- publication history,
- execution metadata,
- lineage metadata,
- preservation metadata,
- recovery metadata.

The exact persisted structure remains to be defined.

## Open questions

The following remain open:

1. What exact data is preserved?
2. What exact data is recovered?
3. How are Subscription Instance chains bounded?
4. How are repeated publication chains controlled?
5. What is the canonical representation of message content at each lifecycle stage?
