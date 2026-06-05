# Xmip Audit and Correlation

## Audit

Xmip Audit is the umbrella for runtime accountability.

Xmip Audit consists of:

- Logs,
- Traces,
- Tracking.

Audit exists to answer:

- What happened?
- Where did it happen?
- By whom did it happen?
- Why did it happen?
- When did it happen?
- What was the outcome?

Every meaningful Xmip runtime step and interaction shall be auditable.

Audit is required for both successful and failed outcomes.

## Receive acceptance and rejection

Xmip always receives an external stream first.

Xmip Receive either accepts or rejects the stream.

Both outcomes shall be audited.

```text
External Stream
    -> Xmip Receive
        -> Accept
            -> Audit success
            -> Xmip Message created
        -> Reject
            -> Audit failure
            -> no Xmip Message created
```

Accept means that Xmip takes ownership and creates a Xmip Message.

Reject means that Xmip does not take ownership and no Xmip Message is created.

A rejected stream receive attempt is still an auditable runtime event.

## Logs

Logs are for Xmip internals.

Logs explain internal operational behavior of the Xmip runtime, nodes, artifact instances, module instances, configuration loading, startup, shutdown, failures, warnings, and internal decisions.

Logs should be verbose enough for operators and developers to understand what Xmip itself did.

Logs must not store message payloads.

## Traces

Traces are for messages.

Traces follow Xmip Messages through Xmip runtime execution.

Tracing records message-related execution flow, correlation, sub-correlation, timing, runtime boundaries, artifact instances, subscription instances, and interaction paths.

Traces must not store message payloads.

## Tracking

Tracking is for debugging and message inspection.

Tracking may store:

- the actual message,
- message context,
- publication history,
- subscription history,
- transformation history,
- assignment history,
- processing history,
- outcome.

Only Tracking stores the actual message.

Tracking must be controlled separately from Logs and Traces because it may contain sensitive data.

## Correlation Footprint

Every accepted Xmip Message shall receive a CorrelationId.

Rejected stream receive attempts are audited but do not create an owned Xmip Message.

No Xmip Message runtime action shall occur without a correlation footprint.

CorrelationId remains stable throughout the entire Xmip Message journey.

## Sub Correlation

Xmip creates SubCorrelationIds for significant runtime activities and interactions.

Examples include:

- Receive accept,
- Publish/Subscribe,
- Message Assignment,
- Message Transformation,
- Process execution,
- Send execution,
- Artifact Instance execution,
- Module Instance interaction.

SubCorrelationIds form a hierarchy beneath the CorrelationId.

## Audit Event

Each audit event should contain:

- CorrelationId when an owned Xmip Message exists,
- SubCorrelationId when applicable,
- ParentSubCorrelationId when applicable,
- EventName,
- Purpose,
- Node,
- Address,
- ArtifactInstance,
- ModuleInstance when applicable,
- ServiceIdentity,
- StartTime,
- EndTime,
- Outcome.

Failure audit must include details about what went wrong.

Those details must not put message payloads into Logs or Traces.

If actual message content must be preserved, it belongs in Tracking.

## Principle

Xmip Audit must be capable of reconstructing:

- what happened,
- where it happened,
- by whom it happened,
- why it happened,
- whether it succeeded or failed,
- what went wrong when it failed.

This principle supports highly regulated industries such as banking, aviation, energy, government, and defense.
