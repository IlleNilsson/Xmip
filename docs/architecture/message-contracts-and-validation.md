# Xmip Message Contracts and Validation Gates

## Purpose

Xmip requires message validation as a runtime gate.

Every incoming message or stream must be validated according to what is knowable at that point in the message journey.

Validation is not limited to the initial receive step. Validation may occur at every passage while a message travels through Xmip.

## Message Contract

A Message Contract defines what Xmip expects a message to satisfy at a given point in its journey.

A Message Contract may apply to:

- incoming streams,
- deserialized messages,
- transformed messages,
- promoted context,
- process/orchestration input,
- process/orchestration output,
- send input,
- outgoing messages.

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

## Validation gates

Validation is a gate.

A message that fails a required validation gate must not continue through that passage as if it were valid.

The outcome must be audited.

## Passage validation

Validation may happen at every significant passage:

- receive,
- deserialize,
- transform,
- promote,
- publish,
- subscription match,
- message assignment,
- process/orchestration input,
- process/orchestration output,
- serialize,
- send.

Each passage may define required or optional Message Contracts.

## Outgoing validation

Validation when leaving Xmip is optional but supported.

Outgoing validation may check:

- expected output structure,
- outgoing content type,
- destination contract,
- serialized representation,
- target system requirements,
- send identity requirements.

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

Xmip must be able to prove not only that a message moved through Xmip, but that it satisfied the required Message Contracts at each required passage.
