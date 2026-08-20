# ADR-0013: The Journey model

## Status

Proposed.

## Context

The runtime cannot be written without this. "A Stream arrives and nothing subscribes" is a
branch in the code. So is "two subscriptions matched, one succeeded and one failed". If the
first implementation answers these, the answer becomes permanent by accident, and an audit
schema and an operator view get built on top of whatever it happened to do.

Xmip already has most of the answer, unstated. `XmipHost.journey_id` in
`include/xmip_module.h` returns *a* journey identifier, singular, for the call in flight. If
one Publication fanned out to three subscribers and a module executed on behalf of all three,
there would be no correct value to return. The boundary has therefore already committed to a
shape; this ADR writes it down.

## Decision

### 1. A Journey is one line of execution

Not a tree. One Journey has exactly one outcome, its own retry, its own audit record.

### 2. A Publication produces zero, one or N Journeys

```text
Publication          one event, one identity, immutable
  └── Journey        one per matched Subscription
```

The Publication is finished when all of its Journeys are terminal — not when they all
succeed. Partial completion is a first-class fact: "3 subscriptions matched, 2 delivered,
1 failed" is expressible without any record having to lie.

Journeys are independent because the world is. If a Process succeeds and an SFTP Send fails,
the file cannot be un-sent. There is no transaction across a Send Location, so there is no
transaction across a Publication.

### 3. Two dead-letter queues, one per immutable artifact

```text
Dead Stream queue     a Stream that never became a Message
Dead Message queue    a Message that no Journey consumed
```

A Stream is kept **as-is** — the original bytes, unmodified. It arrived, and no Message could
be made from it: no Receive Port claimed it, a Prepare stage failed, or a Contract rejected
it before Publication.

A Message reaches the Dead Message queue when it published and **zero** Subscriptions
matched. Its Message Context goes with it, and the Context is the point: when nothing
matched, the operator's question is "what were the promoted properties?", not "what was in
the body".

Both raise a notification. Neither is silent.

This symmetry is deliberate. Stream and Message are the two immutable artifacts, so each gets
its own sink, and a dead Stream is never held as a dangling reference from something else.

### 4. A failed Journey does not dead-letter the Message

If a Message matched three Subscriptions and one Journey failed, the Message was consumed.
Only a Message with **zero** Journeys is undeliverable. A failed Journey is a Journey
failure, recoverable through the Journey record, and it does not invalidate the two that
succeeded.

### 5. Journey terminal states

```text
Delivered    the subscriber accepted it
Failed       something malfunctioned — retryable per XMIP_IS_RETRYABLE
Rejected     the Message was bad — a contract violation, not retryable
Cancelled    the host asked it to stop
```

`Unrouted` is a state of the **Publication**, not of a Journey, because no Journey was ever
created. This matters: nothing about "unrouted" is retryable, and no amount of retrying
manufactures a Subscription.

`Rejected` is separate from `Failed` for the same reason `XMIP_E_MALFORMED` is separate from
`XMIP_E_IO` in the ABI. One is the sender's problem, one is the operator's, and they wake up
different people.

### 6. Recovery is append-only

```text
from the Dead Stream queue    the Receive Port runs again over the kept Stream,
                              producing a new Message and a new Publication

from the Dead Message queue   the Message is published again, producing a new
                              Publication and new Journeys
```

Nothing is mutated in place. A Journey keeps its outcome forever, and a second attempt is a
second record. This follows from Stream and Message already being immutable — a Journey that
could be re-opened would be the only mutable thing in the model.

## Consequences

**The Journey begins at Publication**, which was already decided. Receive, Prepare, Contract
validation and Promotion therefore happen before any Journey exists. A Message rejected by
Contract validation produces no Journey at all and lands in the Dead Stream queue.

The cost is that "why did my message vanish?" has two answers depending on where it died, and
an operator has to know which queue to look in. That is the price of the Journey starting at
Publication rather than at ingress, and it is accepted here rather than discovered later.

**The two queues need an owner.** Neither is currently a module in
`xmip-architecture.json`. They are close to `xmip-core-retain` in mechanism and unlike it in
purpose — retention ages things out on policy, a dead-letter queue holds things until someone
acts. That is a separate decision.

**Notification needs a channel.** "Both raise a notification" implies something to raise it
to. `xmip-core-observe` is the closest existing module.

## Open

- Which module owns the two queues.
- Whether a Publication with zero Journeys is an error condition for alerting purposes, or a
  configuration signal. It is not retryable either way.
- Ordering. Nothing here says whether Journeys from one Publication may run concurrently.
  They are independent, which suggests yes, but an ordered Send Port would need otherwise.

## Provenance

Sections 3 and 4 record the owner's model directly: a Stream not taken care of goes to a Dead
Stream queue as-is, a Message not taken care of goes to a Dead Message queue, both with
notification. Sections 5 and 6 are derived from that model plus the existing immutability
rules, and are the parts most likely to need correction.
