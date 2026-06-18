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

Messages are immutable.

If assignment changes message state, Xmip creates a new message.

If transformation changes message content, Xmip creates a new message.

The new message keeps lineage through the interchange.

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
