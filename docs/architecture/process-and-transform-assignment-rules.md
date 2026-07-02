# Process and Message Creation Rules

## Agreed state

Xmip artifacts are explicit deployable artifacts. At runtime they behave as Actors.

## Transform

Transformation may be performed by:

```text
Receive Port
Process
Send Port
```

A transformation creates a new immutable message form with a new messageId and the same interchangeId.

## Assign

Assignment may be performed only by:

```text
Process
```

Receive Ports do not assign.

Send Ports do not assign.

## Routing

Routing is Xmip pub/sub matching.

A Process does not imperatively route a message.

A Receive Port, Process or Send Port publishes. Routing evaluates subscriptions and starts matching actors.

## Process

A Process is a subscription-started integration artifact. It may validate, promote, assign, transform, execute and publish.

It does not receive external streams directly and it does not deliver to external targets directly.
