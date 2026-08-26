# ADR-0003: Xmip runtime flow

## Status

Accepted.

## Decision

Xmip runtime flow is stream-first, security-aware, transformable, promotable, auditable, and interchange-tracked.

Transformation and promotion happen before subscription or orchestration decisions when required by the incoming stream.

Orchestration and subscription need metadata and promoted properties to know what to do.

## Incoming flow

```text
Receive stream
Identify sender
Authenticate sender
Authorize sender
Create message
Create or attach interchange
Transform and promote when configured or required
Evaluate subscription or orchestration decision
Execute process or send port
Audit all significant actions
```

## Message immutability

**Amended 2026-08-26. The Stream is immutable. The Message is not.**

This section read *"Messages are immutable"* without qualification, and that is
false in a way that mattered: a Message that could not accumulate could not
carry promoted properties, validation results or execution history at all —
which is most of what a Message is for.

**Content is immutable. Context accumulates.**

A Message's Sections point at Streams, and a Stream is never modified. What
grows is everything around the content: context, promoted properties, Contract
metadata, validation results, execution history.

Content changes only through Assignment or Transformation, and those create a
new Stream and a new Message generation rather than editing anything. So:

```text
metadata changes   the same Message, carrying more
content changes    a new Stream, a new Message generation
```

The new generation keeps lineage to the one before it. *"Through the
interchange"* below is retired vocabulary — ADR-0013 replaced Interchange with
Journey, and `runtime-model.md` section 23 conflict 5 records that the
generation link, not a shared interchange identifier, is what carries lineage.

`runtime-model.md` section 3 holds the full statement.

## Interchange lifecycle

The interchange starts when a stream enters Xmip.

The interchange remains until every related message and stream has left Xmip or reached a configured terminal state.

The interchange carries lineage, history, audit references, and promoted properties according to configuration.

## Promotion

Promoted properties may be created from received streams, transformed messages, assigned messages, or send-side preparation.

Promoted properties may travel from old messages to new messages through the interchange.

Promoted properties support subscription, orchestration, routing, audit, tracking, and operational search.

## Subscription and orchestration

A subscription looks for patterns in the message flow and creates an action.

The action may start a process or a send port.

A process may create child interchanges and new messages.

## Send flow

A send port may be triggered by orchestration or by subscription from a receive port.

Before sending, a send port may promote and transform the message when configured or required by the destination.

The send port completes when one send location succeeds according to configured retry and location order rules.

## Audit

Audit is mandatory for:

- receive,
- identity lookup,
- authentication result,
- authorization result,
- transformation,
- promotion,
- assignment,
- subscription match,
- orchestration decision,
- process handoff,
- send port handoff,
- send location result,
- terminal success,
- terminal failure.

## Consequences

Runtime code must not route or orchestrate before required promotion has occurred.

Transform and promotion are first-class runtime concepts, not optional marketing terms.

The project must represent this flow in architecture diagrams, code contracts, and future marketing images.
