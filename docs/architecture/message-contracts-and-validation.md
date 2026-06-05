# Xmip Message Contracts and Validation Gates

## Purpose

Xmip requires message validation as a runtime gate.

Every incoming message or stream must be validated according to what is knowable at that point in the message journey.

Validation is not required after every runtime activity.

Validation belongs at meaningful message-boundary stages where Xmip can verify whether the message is allowed to continue.

## Message Contract

A Message Contract defines what Xmip expects a message to satisfy at a given point in its journey.

A Message Contract may apply to:

- incoming streams,
- deserialized messages,
- transformed messages,
- process/orchestration input,
- process/orchestration output,
- messages before serialization,
- outgoing message intent before leaving Xmip.

Promotion and publication do not by themselves require validation gates.

Promotion extracts values into message context.

Publication makes a message available inside Xmip for subscription evaluation.

## Stream validation

If the incoming message is still a stream, Xmip may not yet know its internal structure.

At that stage validation can only use envelope and identity information such as:

- sender identity,
- service identity,
- certificate,
- transport identity,
- source address,
- receive location,
- receive port,
- content type,
- subject,
- file name,
- file attributes,
- headers,
- metadata.

## Deserialized validation

After deserialization, Xmip may validate structure and data types.

Examples:

- message structure,
- required fields,
- field data types,
- allowed values,
- schema rules,
- domain constraints,
- promoted property expectations.

## Transformation validation

After transformation, Xmip may validate the transformed message.

Examples:

- transformed structure,
- transformed field data types,
- target message contract,
- required fields,
- allowed values,
- domain constraints.

Promotion may happen during transformation, but promoted context is not a separate validation gate by itself.

## Serialization and outgoing checks

Xmip cannot validate a serialized message as structured message data after it has already been serialized.

Structured message validation must happen before serialization.

After serialization, Xmip may perform representation checks only.

Examples:

- serialized representation exists,
- content type is assigned,
- target encoding is assigned,
- destination contract metadata is present,
- send identity requirements are present,
- target system requirements are present.

These are outgoing representation checks, not structured message validation.

## Validation gates

Validation is a gate.

A message that fails a required validation gate must not continue through that passage as if it were valid.

The outcome must be audited.

## Passage validation

Validation may happen at these significant message-boundary passages:

- receive / stream boundary,
- deserialize boundary,
- transform boundary,
- process/orchestration input,
- process/orchestration output,
- pre-serialization boundary,
- optional outgoing representation boundary.

Validation is not required merely because a message is promoted or published into Xmip.

Subscriptions may evaluate after publication using the context already available.

## Outgoing validation

Validation when leaving Xmip is optional but supported.

Outgoing validation means validating message intent and representation requirements before or around send.

Outgoing validation does not mean validating already serialized bytes as structured message data.

Outgoing validation may check:

- expected output structure before serialization,
- outgoing content type,
- destination contract,
- target system requirements,
- send identity requirements,
- representation metadata after serialization.

## Audit relationship

Every validation gate must participate in the Xmip Audit model.

Validation events must include:

- CorrelationId,
- SubCorrelationId,
- EventName,
- Purpose,
- Node,
- Address,
- ServiceIdentity,
- StartTime,
- EndTime,
- Outcome.

If validation fails, the reason must be recorded as metadata.

Validation logs and traces must not store message payloads.

If the actual message must be preserved, it belongs in Tracking.

## Principle

Xmip must be able to prove not only that a message moved through Xmip, but that it satisfied the required Message Contracts at each required message-boundary passage.
