# Xmip Platform Direction

Xmip is designed as the next era of enterprise integration platforms.

Xmip keeps the integration ambition of earlier enterprise integration platforms but changes the execution model.

## Core direction

Stream first.

Interpretation second.

Pub/sub third.

Process or SendPort fourth.

## Stream first

Xmip receives streams before it assumes meaning.

A received stream becomes part of an Xmip Message.

The original stream must remain available according to policy.

Xmip should avoid unnecessary deserialization, parsing, validation, or transformation.

## Interpretation second

Interpretation happens only when needed.

Interpretation may include contract recognition, content handling, metadata extraction, promoted properties, validation, or transformation preparation.

Receiving a stream is the first act.

Interpretation is not the first act.

## Pub/sub third

After the message has enough metadata or promoted properties, Xmip evaluates Subscriptions.

Subscriptions look for patterns in the message flow.

A matching Subscription creates an action.

## Process or SendPort fourth

A Subscription action kicks off one of two runtime paths:

- Process,
- SendPort.

A Process owns state and may create new Messages and child Interchanges.

A SendPort owns outbound organizational delivery behavior and completes when one SendLocation succeeds.

## Runtime order

1. Receive stream.
2. Create Message.
3. Create or extend Interchange.
4. Interpret only as required.
5. Evaluate Subscriptions.
6. Kick off Process or SendPort.
7. Persist audit and history according to policy.
