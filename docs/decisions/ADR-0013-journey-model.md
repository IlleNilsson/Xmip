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

## Decision

### 1. The gate decides custody

Nothing enters Xmip that is not identified, authenticated and authorized. Every action taken
against Xmip is audited, including every refusal.

```text
                          identify → authenticate → authorize
                                        │
        ┌───────────────────────────────┴───────────────────────────────┐
   before the gate                                              after the gate
   no identity                                                  known partner
   reject · audit · keep nothing                                reject · audit · keep Stream
```

**Before the gate** — a connection fault, an unauthenticated peer, an unauthorized one. Xmip
refuses and retains nothing. There is no counterparty to hold the data for, and a store of
unauthenticated bytes is a liability, not a feature.

**After the gate** — an identified, authenticated, authorized partner whose Stream cannot be
deserialized. Xmip still refuses: no Xmip Message is created. But the Stream is kept, because
there is an accountable counterparty who can fix their serialiser and replay.

The distinction is custody, not fault. Both are producer faults, or producer-and-Xmip
combinations. What differs is whether anyone is answerable for the bytes.

### 2. A faulty Stream is held by `xmip-core-retain`

The retention service owns it. No separate store is introduced, and no new module is created.

This settles two questions that would otherwise need answering separately: *where* a faulty
Stream lives, and *how long*. Retention already has policy, ageing and expiry, so a faulty
Stream is subject to the same rules as anything else Xmip keeps, per partner or globally as
the policy states.

### 3. Accept means ownership

Accept means Xmip takes ownership and creates a Xmip Message. An accepted Xmip Message shall
never disappear. After Accept, Xmip owns it until final disposition. Unchanged from
`message-disposition.md`.

### 4. An accepted Message with no Subscription goes to the Xmip DMQ

Unchanged. The DMQ is the final disposition for accepted Messages that cannot be routed, and
preserves the Message with its receive context, validation results, correlation and trace
references, audit references, failure reason, timestamps, artifact identities and
subscription evaluation metadata.

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

## What this changes

`message-disposition.md` says Reject means Xmip does not take ownership and no Xmip Message
is created, with the rejection audited. That remains true in both cases above — **no Message
is ever created for a rejected Stream**.

What is added is that rejection after the gate now *keeps the Stream*, under
`xmip-core-retain`. That is a change, not a clarification, and the specification should be
updated to match rather than left to disagree quietly.

Retention is deliberately asymmetric with identity: authenticated partner, keep; anonymous,
do not.

## Open

- **Which module owns the Xmip DMQ.** Clause 2 settles the faulty Stream. The DMQ is
  different in purpose — retention ages things out on policy, the DMQ is a final disposition
  that must not silently expire, given "an accepted Xmip Message shall never disappear".
- **The DMQ is "final disposition" but a faulty Stream may be replayed.** An operator who adds
  the missing Subscription will want to replay from the DMQ too. Either "final" means "its
  Journey ends here" rather than "it can never be touched", or the asymmetry is intentional
  and should say why.
- **`JourneyState` cannot distinguish a sender's bad data from a broken system.** The ABI
  makes that distinction — `XMIP_E_MALFORMED` versus `XMIP_E_IO` — because the two wake up
  different people. `Failed` covers both. Raised, not resolved.
- **Ordering.** Nothing here says whether Journeys from one Publication may run concurrently.
  Independence suggests yes; an ordered Send Port would need otherwise.

## Provenance

Clauses 1 and 2 record the owner's position: Xmip rejects any connection, stream or message
deserialization fault; nothing enters unidentified, unauthenticated or unauthorized; actions
against Xmip are audited; a faulty Stream is taken care of by the retention service. The
split of that principle into before-gate and after-gate custody was proposed here and
accepted.

Clauses 3, 4 and 7 record existing specification and code. Clauses 5 and 6 are derived from
the `journey_id` boundary and the immutability of Stream and Message, and are the parts most
likely to need correction.
