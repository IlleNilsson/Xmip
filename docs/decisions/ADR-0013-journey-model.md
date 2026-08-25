# ADR-0013: Message disposition and the Journey model

## Status

Proposed. Records the runtime lifecycle from `docs/Xmip-Architecture-Specification-v1.2.md`
section 2, and extends `docs/architecture/message-disposition.md` with disposition at each
point of refusal.

## Context

The runtime cannot be written without knowing what happens at each refusal. "A Stream arrives
and nothing subscribes" is a branch in the code. So is "two Subscriptions matched, one
failed". Left undecided, the first implementation answers by accident.

Three things already exist and this ADR is written to agree with them:

- **v1.2 section 2** specifies the runtime lifecycle, including where security happens.
- **`message-disposition.md`** defines Accept, Reject and the Xmip DMQ.
- **`src/journey_model.rs`** defines `JourneyState`, with tests.

A fourth is implied. `XmipHost.journey_id` in `include/xmip_module.h` returns *a* journey
identifier, singular, for the call in flight. If one Publication fanned out to three
subscribers and a module executed on behalf of all three, there would be no correct value to
return. The boundary had already committed to a shape.

## The lifecycle

From v1.2 section 2, unchanged:

```text
Incoming Stream
    -> Transport identification
    -> Transport authentication
    -> Transport authorization
    -> Message creation
    -> Default promotion
    -> Configuration may inspect Stream and Message Context
    -> Optional message identification
    -> Optional message authentication
    -> Optional message authorization
    -> Contract implication
    -> Optional deserialization
    -> Validation
    -> Journey creation
```

Transport security is mandatory and happens **before** Message creation. Message-level
security is separate and optional, and happens **after** Message creation and default
promotion, so configuration can inspect the Stream and Context to decide whether it applies.

Because Message creation follows transport authorization, Xmip never parses content from an
unauthorized sender. The ordering is what makes that true.

## Definitions

```text
Identity         sent by the caller, or implied by the Receive Location
Authentication   verification of that identity, sent or implied
Authorization    whether that authenticated identity may send, post or poll
                 a Stream into Xmip
```

An implied identity is still authenticated. A Receive Location configured as a partner's drop
presents no credential, so authentication verifies the circumstance that implies it — the
path, the permissions, the source address. "No credential" means different evidence, not
absent verification.

`poll` inverts who initiates: Xmip fetches, the caller sends nothing, and identity is
therefore almost always implied.

### Identity is ADR-0019's

Identity travels on the transport, on the message, or on both; the line between them, the
per-layer authorization, and the alignment policy when they disagree are all specified in
**ADR-0019**. They were written here first and moved once they outgrew a record about
disposition. `docs/architecture/identity-by-technology.md` sorts the estate by that rule.

What remains below is what this ADR is for: what Xmip *keeps* at each point of refusal.

## Decision

### 1. Disposition of a refused Stream

| refused at | Message created | Stream kept |
|---|---|---|
| transport identification, authentication or authorization | no | **no** |
| Message creation — the Stream cannot be deserialized | no | **yes** |

Refusal before transport authorization retains nothing. There is no accountable counterparty,
and a store of unauthorized bytes is a liability rather than a feature. The attempt is audited
as a transport event; per v1.2 it "is not a Message or Journey".

Refusal at Message creation retains the Stream, because the sender is identified,
authenticated and authorized. There is someone answerable who can correct their serialiser and
replay.

### 2. A retained faulty Stream is held by `xmip-core-retain`

The retention service owns it. No separate store, no new module. This settles *where* it lives
and *how long*, since retention already has policy, ageing and expiry.

### 3. A Message that fails Validation is stored, answered, and goes no further

Stored under retention policy. Audited. No Journey is created — per v1.2, "Journey creation
occurs only after required validation succeeds".

Where the protocol can carry a response, the producer is told immediately.
`XmipDeliverySink.deliver` already provides for this: it takes a `reply` writer, NULL when
the transport has no reply channel. HTTP, MLLP and SOAP get an answer; a file drop or a queue
read cannot, and the audit record is the only trace.

This has a runtime consequence. For responding protocols, everything up to Validation must
complete **inside** the receive call. It cannot be deferred to a worker without losing the
ability to answer.

### 4. An accepted Message with no Subscription goes to the Xmip DMQ

Unchanged from `message-disposition.md`. The DMQ is the final disposition for accepted
Messages that cannot be routed, and preserves the Message with its receive context, validation
results, correlation and trace references, audit references, failure reason, timestamps,
artifact identities and subscription evaluation metadata.

That metadata is the point. When nothing matched, the operator's question is "what were the
promoted properties, and which Subscription nearly matched?" — not "what was in the body".

### 5. A Publication produces zero, one or N Journeys

```text
Publication          one event, one identity, immutable
  └── Journey        one per matched Subscription
```

A Journey is one line of execution, not a tree. The Publication is finished when all of its
Journeys are terminal — not when they all succeed. "3 matched, 2 delivered, 1 failed" is
expressible without any record having to lie.

Journeys are independent because the world is. If a Process succeeds and an SFTP Send fails,
the file cannot be un-sent. There is no transaction across a Send Location, so there is none
across a Publication.

### 6. A failed Journey does not send the Message to the DMQ

If a Message matched three Subscriptions and one Journey failed, the Message *was* routed.
Only a Message that matched **zero** Subscriptions is undeliverable. A failed Journey is
recoverable through the Journey record and does not invalidate the two that succeeded.

### 7. Journey state is what `journey_model.rs` already says

```rust
enum JourneyState { Active, Waiting, Suspended, Recovering, Completed, Failed }
```

`Completed` and `Failed` are terminal. `Suspended` and `Recovering` are the
operator-recoverable path. This ADR records the existing enum rather than proposing another.

### 8. Both identities are kept, and disagreement is configured

Specified in ADR-0019 clauses 6 and 7. Recorded here only because it changes disposition:
`onMisalignment = "quarantine"` sends the Message to the Xmip DMQ carrying both identities
and the alignment result, which is a fifth route into the DMQ that clause 4 did not
anticipate. `onMisalignment = "reject"` refuses at message authorization, and the Message is
stored under retention policy exactly as clause 3 stores a Validation failure.

## What this adds

`message-disposition.md` says Reject means Xmip does not take ownership and no Xmip Message is
created, with the rejection audited. That remains true — **no Message survives a rejection**.

What is added is *what is kept*, which the specification does not say: nothing before transport
authorization, the Stream after it, and the Message after Validation fails. Retention is
deliberately asymmetric with identity — authorized sender, keep; unauthorized, do not.

## Open

- **"An accepted Xmip Message shall never disappear" versus retention.** Per
  `message-disposition.md`, Accept is Message creation — which happens before Validation. So a
  Validation-failed Message is an *accepted* Message, and clause 3 stores it only until
  retention rules apply. Either "never disappear" means "never silently lost", and governed
  expiry under audited policy satisfies it, or Validation-failed Messages need a rule of their
  own. **This needs a ruling; it is not resolved here.**
- **Which module owns the Xmip DMQ.** Retention ages things out on policy; an accepted Message
  shall never disappear. Those pull in opposite directions.
- **"Final disposition" versus replay.** An operator who adds the missing Subscription will
  want to replay from the DMQ, where a faulty Stream is replayable. Either "final" means its
  Journey ends there, or the asymmetry needs a reason.
- **`JourneyState` cannot distinguish a sender's bad data from a broken system.** The ABI makes
  that distinction — `XMIP_E_MALFORMED` versus `XMIP_E_IO` — because they wake different
  people. `Failed` covers both.
- **Ordering.** Whether Journeys from one Publication may run concurrently. Independence
  suggests yes; an ordered Send Port would need otherwise.
- ~~Which identity is authoritative when both exist and disagree.~~ **Answered in ADR-0019 clause 7.**

## Provenance

The lifecycle is v1.2 section 2 verbatim. The definitions of identity, authentication and
authorization are the owner's, as is the disposition of faulty Streams to the retention
service and of Validation-failed Messages.

Clauses 4 and 7 record existing specification and code. Clauses 5 and 6 are derived from the
`journey_id` boundary and the immutability of Stream and Message, and remain the parts most
likely to need correction.

An earlier revision of this ADR described a single security gate and placed Accept at
Validation. Both were wrong: v1.2 specifies two security passes with Message creation between
them, and `message-disposition.md` places Accept at Message creation. Corrected here.
