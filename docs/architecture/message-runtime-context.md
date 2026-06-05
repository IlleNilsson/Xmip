# Xmip Message Runtime Context

## Purpose

Xmip is centered on messages, but Xmip always receives a stream first.

The stream may represent many things, such as an application message, file, photo, binary payload, document, or another transferable representation.

A stream becomes a Xmip Message only after it has entered the world of Xmip and Xmip has taken ownership.

Xmip takes ownership only after the required receive or stream boundary validation succeeds.

After ownership is accepted, the Xmip Message and its runtime context are the primary runtime concerns.

Artifacts, modules, subscriptions, validations, processes, and send operations participate while a Xmip Message is passing through Xmip.

They do not own the message journey.

## Stream acceptance and ownership

Xmip receives streams.

A received stream is not automatically a Xmip Message.

Before ownership, Xmip may inspect only what is knowable at the stream boundary, such as envelope, source, identity, certificate, headers, metadata, file attributes, content type, and receive location.

If the required receive or stream boundary validation succeeds, Xmip accepts ownership and creates a Xmip Message.

If validation fails, Xmip must not treat the stream as an owned Xmip Message.

The failure must still be audited as a rejected receive attempt.

Conceptually:

```text
External stream
    -> receive / stream boundary validation
        -> accepted: Xmip Message is created and owned by Xmip
        -> rejected: no Xmip Message ownership is taken
```

## Message lifecycle

Xmip is not a mandatory linear pipeline.

After stream validation succeeds and Xmip takes ownership, the Xmip Message accumulates context, is published into Xmip, and is acted upon by subscriptions according to the context available at that point.

Conceptually:

```text
External stream
    -> validate receive or stream boundary
    -> accept ownership
    -> create Xmip Message
    -> collect envelope and receive context
    -> publish into Xmip
    -> subscription evaluation
        -> Inbox
        -> Process / Orchestration
        -> SendPort
        -> publish again when appropriate
```

Optional message understanding stages may occur before publication or before later publications:

```text
Deserialize
    -> validate deserialized message contract

Transform
    -> validate transformed message contract

Promote
    -> add promoted properties to message context
```

Promotion may happen during transformation.

Promotion is not itself a validation gate.

Publication is not itself a validation gate.

The exact path is determined by Artifact Definitions, Artifact Instances, Message Contracts, Subscription rules, and runtime publications.

## Incoming stream sources

A stream may originate from many places, including:

- files,
- streams,
- receive locations,
- scheduled activity,
- external systems,
- another Xmip publication.

The original incoming representation matters, but it is not the whole runtime message.

At the stream boundary, Xmip may not know the internal structure.

At that stage subscriptions and validation may use envelope and receive context, such as:

- ReceiveLocation,
- ReceivePort,
- Content Type,
- subject,
- headers,
- metadata,
- file name,
- file attributes,
- queue name,
- sender identity,
- service identity,
- certificate.

## Message contracts and validation gates

Validation belongs to meaningful message-boundary stages.

Validation may occur at:

- receive / stream boundary,
- deserialize boundary,
- transform boundary,
- process/orchestration input,
- process/orchestration output,
- pre-serialization boundary,
- optional outgoing representation boundary.

Validation is a gate.

A stream that fails required receive or stream boundary validation must not become an owned Xmip Message.

A Xmip Message that fails a later required validation gate must not continue through that passage as if it were valid.

Xmip cannot validate a serialized payload as structured message data after serialization.

Structured message validation must happen before serialization.

After serialization, Xmip may only perform representation checks.

## Deserialization

Deserialization turns an owned Xmip Message representation into a form Xmip can reason about structurally.

Deserialization is optional and contract-driven.

A Xmip Message does not have to be deserialized before it can be published into Xmip or matched by subscriptions.

## Transformation and promotion

Transformation changes or enriches message content.

Promotion extracts values and makes them available as runtime context.

Promoted properties support Subscription evaluation, processing decisions, and delivery decisions.

There is no separate concept of transformed properties.

Promotion may happen during transformation.

## Publication

Publication makes an owned Xmip Message available inside Xmip for Subscription evaluation.

A Xmip Message may be published with only receive/envelope context.

A later publication may include richer context after deserialization, transformation, or promotion.

Publication does not require that the Xmip Message has passed through all optional understanding stages.

## Subscription evaluation

Subscriptions evaluate against whatever context is available at the point of publication or reintroduction.

Subscription context may include receive/envelope metadata, promoted properties, message contract metadata, artifact metadata, and runtime metadata.

When a Subscription evaluates true at runtime, it causes a runtime action due to its Artifact Definition.

That action may target:

- Inbox,
- Process / Orchestration,
- SendPort,
- another publication into Xmip.

A Subscription Instance becomes part of the message history.

Subscription Instances form a chain similar to a call stack.

## Processing

Processing performs business activity or orchestration activity.

Processing may consume, transform, validate, assign, publish, or send Xmip Messages according to Artifact Definitions and Message Contracts.

Processing may continue the message journey and may publish back into Xmip.

## Serialization

Before a Xmip Message leaves Xmip through a SendLocation, it may be serialized into the required outgoing representation.

Structured validation must happen before serialization.

After serialization, Xmip may check representation requirements such as content type, encoding, destination metadata, and send identity.

## Audit, tracking, and correlation

Xmip maintains Audit for runtime explainability.

Audit consists of:

- Logs,
- Traces,
- Tracking.

Only Tracking stores the actual message.

Logs and Traces store metadata only.

A rejected stream receive attempt is audited even when no Xmip Message ownership is taken.

Every owned Xmip Message receives a CorrelationId.

Significant runtime activities receive SubCorrelationIds.

No runtime action should occur without a correlation footprint.

## Runtime message context

The runtime message context is more than payload.

Known categories include:

- message content,
- receive/envelope context,
- promoted properties,
- Message Contract validation results,
- Subscription Instance chain,
- publication history,
- audit metadata,
- tracking metadata,
- correlation metadata,
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
6. Which Message Contracts are first-class Artifact Definitions, and which are module-provided validation capabilities?
