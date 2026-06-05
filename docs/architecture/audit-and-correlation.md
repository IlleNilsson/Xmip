# Xmip Audit and Correlation

## Audit

Xmip Audit consists of:

- Logs
- Traces
- Tracking

Audit exists to answer:

- What happened?
- Where did it happen?
- By whom did it happen?
- Why did it happen?
- When did it happen?

## Logs

Logs provide operational explanation.

Logs store metadata only and must not store message payloads.

## Traces

Traces provide execution correlation.

Traces store metadata only and must not store message payloads.

## Tracking

Tracking preserves message lineage.

Tracking stores:

- the actual message,
- message context,
- publication history,
- subscription history,
- transformation history,
- assignment history,
- processing history,
- outcome.

Only Tracking stores the actual message.

## Correlation Footprint

Every message or stream entering Xmip shall receive a CorrelationId.

No runtime action shall occur without a correlation footprint.

CorrelationId remains stable throughout the entire Xmip journey.

## Sub Correlation

Xmip creates SubCorrelationIds for significant runtime activities.

Examples include:

- Publish/Subscribe,
- Message Assignment,
- Message Transformation,
- Process execution,
- Send execution,
- Receive execution.

SubCorrelationIds form a hierarchy beneath the CorrelationId.

## Audit Event

Each audit event should contain:

- CorrelationId,
- SubCorrelationId,
- ParentSubCorrelationId,
- EventName,
- Purpose,
- Node,
- Address,
- ServiceIdentity,
- StartTime,
- EndTime,
- Outcome.

## Principle

Xmip Audit must be capable of reconstructing:

- what happened,
- where it happened,
- by whom it happened,
- why it happened.

This principle supports highly regulated industries such as banking, aviation, energy, government, and defense.