# ADR-0013: The Journey model and message disposition

## Status

Proposed. Amends `docs/architecture/message-disposition.md` — see "What this changes".

## Context

The runtime cannot be written without this. "A Stream arrives and nothing subscribes" is a
branch in the code. So is "two Subscriptions matched, one failed". Left undecided, the first
implementation answers them by accident, and an audit schema and an operator view get built
on top of whatever it happened to do.

Two things already exist and this ADR is written to agree with them:

- `docs/architecture/message-disposition.md` defines Accept, Reject and the Xmip DMQ.
- `src/journey_model.rs` defines `JourneyState`, with tests.

A third is implied. `XmipHost.journey_id` in `include/xmip_module.h` returns *a* journey
identifier, singular, for the call in flight. If one Publication fanned out to three
subscribers and a module executed on behalf of all three, there would be no correct value to
return. The boundary had already committed to a shape.

## The path in

```text
Stream arrives
  │
  ├─ identify · authenticate · authorize ──── fails ──▶ reject · audit · keep NOTHING
  │
  ├─ Receive Port creates a Message ───────── fails ──▶ reject · audit · KEEP the Stream
  │
  ├─ Contract validation ─────────────────── fails ──▶ store · audit · respond if possible
  │                                                     goes no further
  ├─ Promote
  │
  └─ Publish ─────── zero Subscriptions ────────────▶ Xmip DMQ · final disposition
                     one or more ─────────────────▶ one Journey each
```

## Decision

### 1. The gate decides custody

Nothing enters Xmip that is not identified, authenticated and authorized. Every action taken
against Xmip is audited, including every refusal.

**Before the gate** — a connection fault, an unauthenticated peer, an unauthorized one. Xmip
refuses and retains nothing. There is no counterparty to hold the data for, and a store of
unauthenticated bytes is a liability, not a feature.

**After the gate** — an identified, authenticated, authorized partner whose Stream cannot be
deserialized. Xmip still refuses and creates no Message, but the Stream is kept, because
there is an accountable counterparty who can fix their serialiser and replay.

The distinction is custody, not fault. Both are producer faults, or producer-and-Xmip
combinations. What differs is whether anyone is answerable for the bytes.

### 2. A faulty Stream is held by `xmip-core-retain`

The retention service owns it. No separate store, no new module.

This settles *where* a faulty Stream lives and *how long* in one stroke: retention already has
policy, ageing and expiry, so a faulty Stream is subject to the same rules as anything else
Xmip keeps.

### 3. Contract validation completes Accept

A Message that fails contract validation is **stored under retention policy**, is **audited**,
and **goes no further** — no Promotion, no Publication, no Journey.

Where the protocol can carry a response, the producer is told immediately. `XmipDeliverySink`
already provides for this: `deliver` takes a `reply` writer, NULL when the transport has no
reply channel. HTTP, MLLP and SOAP get an answer; a file drop or a queue read cannot, and the
audit record is the only trace.

This has a runtime consequence worth stating: for responding protocols, contract validation
must complete **inside** the receive call. It cannot be deferred to a worker without losing
the ability to answer.

**Why this is not a contradiction.** `message-disposition.md` says an accepted Xmip Message
shall never disappear. A contract-failed Message is stored only until retention rules apply.
Both are true if Accept is not complete until the contract passes:

```text
identified · authenticated · authorized · deserializable · contract-valid  =  ACCEPTED
```

Everything before that line is a refusal, differing only in what is kept. Everything after it
is owned by Xmip and shall never disappear.

### 4. Accept means ownership

Accept means Xmip takes ownership. An accepted Xmip Message shall never disappear. After
Accept, Xmip owns it until final disposition. Unchanged in substance from
`message-disposition.md`; clause 3 states where the line sits.

### 5. An accepted Message with no Subscription goes to the Xmip DMQ

Unchanged. The DMQ is the final disposition for accepted Messages that cannot be routed, and
preserves the Message with its receive context, validation results, correlation and trace
references, audit references, failure reason, timestamps, artifact identities and
subscription evaluation metadata.

That metadata is the point. When nothing matched, the operator's question is "what were the
promoted properties, and which Subscription nearly matched?" — not "what was in the body".

### 6. A Publication produces zero, one or N Journeys

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

### 7. A failed Journey does not send the Message to the DMQ

If a Message matched three Subscriptions and one Journey failed, the Message *was* routed.
Only a Message that matched **zero** Subscriptions is undeliverable. A failed Journey is
recoverable through the Journey record and does not invalidate the two that succeeded.

### 8. Journey state is what `journey_model.rs` already says

```rust
enum JourneyState { Active, Waiting, Suspended, Recovering, Completed, Failed }
```

`Completed` and `Failed` are terminal. `Suspended` and `Recovering` are the
operator-recoverable path. This ADR records the existing enum rather than proposing another.

## What this changes

`message-disposition.md` says Reject means Xmip does not take ownership and no Xmip Message
is created, with the rejection audited. That remains true — **no Message survives a
rejection**.

Two things are added:

1. Rejection after the gate now *keeps the Stream*, under `xmip-core-retain`. Retention is
   deliberately asymmetric with identity: authenticated partner, keep; anonymous, do not.
2. Contract validation is named as the completion of Accept, which places contract-failed
   Messages outside the "shall never disappear" guarantee and under retention instead.

Both are changes, not clarifications, and the specification should be updated to match rather
than left to disagree quietly.

## Open

- **Which module owns the Xmip DMQ.** Clauses 2 and 3 put faulty Streams and contract-failed
  Messages under retention. The DMQ is different: retention ages things out on policy, and an
  accepted Message shall never disappear.
- **"Final disposition" versus replay.** An operator who adds the missing Subscription will
  want to replay from the DMQ. Either "final" means its Journey ends there, or the asymmetry
  with replayable faulty Streams needs a reason.
- **`JourneyState` cannot distinguish a sender's bad data from a broken system.** The ABI
  makes that distinction — `XMIP_E_MALFORMED` versus `XMIP_E_IO` — because the two wake up
  different people. `Failed` covers both. Raised, not resolved.
- **Ordering.** Nothing here says whether Journeys from one Publication may run concurrently.
  Independence suggests yes; an ordered Send Port would need otherwise.

## Provenance

Clauses 1, 2 and 3 record the owner's position: Xmip rejects any connection, stream or message
deserialization fault; nothing enters unidentified, unauthenticated or unauthorized; actions
against Xmip are audited; a faulty Stream is taken care of by the retention service;
contract-failed Messages are stored until retention applies, answered immediately where the
protocol allows, and go no further.

The before-gate and after-gate split, and the reading that Accept completes at contract
validation, were proposed here to reconcile that position with the existing specification.

Clauses 4, 5 and 8 record existing specification and code. Clauses 6 and 7 are derived from
the `journey_id` boundary and the immutability of Stream and Message, and are the parts most
likely to need correction.
