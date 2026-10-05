# ADR-0013: Message disposition and the Journey model

## Status

Proposed. Records the runtime lifecycle from `doc/Xmip-Architecture-Specification-v1.2.md`
section 2, and extends `doc/architecture/message-disposition.md` with disposition at each
point of refusal.

## In brief

- Theme: What Xmip is at runtime
- Subject: Message disposition and the Journey
- Name: The Journey model
- Order: 2
- Concepts: Deduplication, duplicates; Dismiss, Dismissed; Previous journey; Disposition; Dead Message Queue; Journey, Journey states; Publication, Subscription matching; Subscription, paused and resumed

A Journey is a line, not a tree: a Publication produces one Journey per matched
Subscription, and zero matches means no Journey at all. A Journey exists only
after Validation. Every point of refusal has a defined disposition, so nothing
accepted disappears silently.

Terminal states are `Completed`, `Failed` and `Dismissed` — the last added
2026-08-26 so that an operator's deliberate stop is distinguishable from a
fault.

An operator pauses and resumes a Subscription, and never removes one: a
paused Subscription holds what it matches in the Ledger, and a resume picks
it up oldest first; a Subscription is added and removed in the TOML
configuration (amendments 2026-09-30 and 2026-10-01). An accepted Message no
Subscription matched is Dead Message Queue state in the Ledger, replayed by
an Operator, and the sender is acknowledged after the whole receive cycle
(amendment 2026-10-01).

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

An implied identity is still authenticated. A Receive Location configured as a Party's drop
presents no credential, so authentication verifies the circumstance that implies it — the
path, the permissions, the source address. "No credential" means different evidence, not
absent verification.

`poll` inverts who initiates: Xmip fetches, the caller sends nothing, and identity is
therefore almost always implied.

### Identity is ADR-0019's

Identity travels on the transport, on the message, or on both; the line between them, the
per-layer authorization, and the alignment policy when they disagree are all specified in
**ADR-0019**. They were written here first and moved once they outgrew a record about
disposition. `doc/architecture/identity-by-technology.md` sorts the estate by that rule.

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
authenticated and authorized. There is someone answerable who can correct their serializer and
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

### 4b. A Journey names the Journey before it, and a Message names none

Two corrections recorded 2026-08-26, both about which record owns the link.

**A Journey carries `previous_journey_id`.** When a Process splits a Message, or
publishes back into Xmip, the Journeys that follow reference the one they came
from. `runtime-model.md` section 23 conflict 8 left this open — *"what remains
to be named is the link from a Publication to the one that caused it"* — and
this names it.

It is called *previous*, not *parent*. Parent implies containment and reads as
a contradiction of clause 5's *a Journey is a line, not a tree*. It is not one:
**each Journey is a line; the relationships between Journeys form a chain.**
Several Journeys may share one previous Journey, which is simply what happens
when one Publication matches several Subscriptions.

`journey` unqualified always means the current Journey.

**A Message carries no `journey_id`.** Both implementations have one today —
`src/journey_model.rs` and `module/foundation/message` — and it is backwards.
A Message is published; *then* subscribers pick it up and open Journeys. A
Message owning a single Journey identity cannot be picked up twice, which
contradicts clause 5 directly. Journeys reference Messages, never the reverse.

**Known limit.** `previous_journey_id` names the causing Journey, not the
causing event. A Journey that publishes twice leaves a successor able to say
*which Journey* started it and not *which publication within it*. That is the
identifier question in section 23 conflict 5 and it stays open.

*Half closed by ADR-0026 on 2026-09-03.* A caused Journey now also carries a
`cause` — the Subscription that matched and the Xmip Process it started — so a
successor names the event as well as the Journey. What is still open is telling
two identical publications within one Journey apart. The same record gives every
Journey a `depth` and a ceiling, because this clause describes the chain and
nothing bounded it.

### 4c. Xmip does not deduplicate. A Process decides

**A Stream may be published into Xmip twice, and Xmip accepts it twice.** Two
Streams, two Messages, two sets of Journeys, all correct. Xmip does not own the
consequences of a client sending the same thing more than once.

**Two identical byte sequences are not the same event.** A retry and a genuine
resubmission are indistinguishable at the wire. Only the domain knows whether
the second invoice is a duplicate or a correction, so a platform that
deduplicates has guessed — and it will be wrong in one direction silently,
which is the worse direction.

So duplicate detection is a **business decision**, and business decisions
belong in an Xmip Process.

This is the inbound counterpart to the delivery semantics in
`runtime-model.md` section 15. That clause says what Xmip promises when
*sending*: exactly-once where the endpoint permits, at-least-once otherwise.
This says what Xmip promises a client *sending in*: nothing, deliberately.

**It is also where `Dismissed` earns its place.** A duplicate is not refused at
a gate — it authenticates, it validates, it is a perfectly good Message, and it
gets Journeys. A Process then decides *this one has already been handled*. That
outcome is neither `Completed` nor `Failed`, and collapsing it into `Failed`
would make every duplicate read as an error.

**Two consequences.**

A Process needs to query prior Messages and Journeys — by promoted property,
correlation or business key — to decide *already seen*. History lookup is a
first-class Process capability and the Process model does not yet provide one.

Protocol-level deduplication is not this. Where a transport's specification
defines duplicate semantics — a Kafka idempotent producer, an AS2 message-id, a
JMSMessageID — the transport Module honors them, because that is conformance
rather than judgment. Same word, two layers.

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

## Amendment, 2026-08-26: `Dismissed` is a terminal state

`Dismiss` was a command with nowhere to land. A dismissed Journey was recorded
as `Failed`, so an operator's deliberate decision was indistinguishable from
the fault it was responding to.

**`JourneyState` gains a `Dismissed` terminal variant.** Dismissal is not
recorded outside the state.

Three reasons, in the order they carried weight:

**It was in the design before it was lost.** The earliest Xmip design — the
`_origins` export, recovered 2026-08-26 — defined four runtime lanes: Receive,
Process, Send and **Void**, with `Receive → Void` and `Receive → Process → Void`
as valid flows. Void is a terminal path for work that deliberately does not go
out, reachable from both a processed and an unprocessed Message, and separate
from failure. So the distinction existed from the beginning and was dropped in
translation. That makes this a recovery rather than an invention, which is a
much easier thing to be confident about.

**Every failure count is otherwise wrong.** If dismissal is `Failed`, then the
failure rate on any dashboard is inflated by every deliberate intervention, and
the more competently an estate is operated the worse its numbers look. A metric
that punishes correct operator behavior will be worked around rather than
fixed.

**The alternative puts one terminal outcome somewhere else.** Recording
dismissal only as an audited disposition means a Journey's own state never says
what became of it, and anything reading `JourneyState` has to join against the
audit record to find out. Two of the three terminal outcomes would live in the
enum and the third somewhere else, which is the kind of asymmetry that is
correct once and misread forever.

Terminal is now `Completed`, `Failed` or `Dismissed`. `src/journey_model.rs`
carries `is_terminal()` and `is_incomplete()`, the second covering `Failed` and
`Dismissed` together, because most reporting wants "stopped without finishing"
and only some of it needs to know which.

This resolves conflict 2 in `runtime-model.md` section 23. `Created` remains
absent for the reason recorded there: a Journey exists only after Validation.

### There is no Dismissed queue

The follow-on question was whether a dismissed Journey lands somewhere — a DJQ
for Journeys, or a DMQ reinterpreted as Dismissed rather than Dead.

**Neither. Dismissal is a state, not a destination.** The Xmip DMQ stays what it
is: Dead Message Queue, holding accepted Messages that no Subscription matched.

**A queue holds what is homeless.** A Message in the DMQ has no Journey. Nothing
owns it, nothing knows where it was, because it never went anywhere — so it
needs a place to be kept. A dismissed Journey is not homeless. It exists, it is
terminal, it is persisted, and it knows its last checkpoint.

**Replay is what settles it, and replay needs both halves.**

A Journey accumulates a story: execution history, audit events, lineage, the
Subscription Instance chain, checkpoints, state transitions, retry history. A
Message accumulates one too: envelope and receive context, promoted properties,
validation results, Contract metadata, section metadata, stream references, and
its generation lineage.

**Neither story is sufficient alone.** Because Messages are immutable and
Transformation and Assignment create new ones, a Journey's execution position
implies a *particular Message generation* — resuming needs to know both where
the Journey was and what it was holding at the time. And a Message without its
Journey has no account of what has already been attempted on its behalf.

So replay operates on the pair. The two cases differ in what the pair contains,
not in whether both halves are needed:

| | Replay means |
| --- | --- |
| DMQ Message | **re-publish** — re-run Subscription matching against the Message *with the context it already accumulated*. Not a re-receive: the envelope context, promoted properties and validation results are preserved and reused. What changed is the Subscription set. |
| Dismissed or Failed Journey | **resume** — from the last checkpoint before it stopped, restoring the Journey position together with the Message generation current at that position. |

One queue holding both would put one operator verb over two meanings, and the
operator would have to know which kind of thing they were looking at before they
could know what the button did.

**What this obliges the runtime to keep.** A DMQ entry preserves the Message's
accumulated context, which the preservation list above already requires. A
checkpoint preserves the Journey position *and* a reference to the Message
generation at that point — and that second part is the one most likely to be
built wrong, because it is easy to persist a position and assume the current
Message will do.

**A dismissal queue could only ever hold Journeys, and then it is redundant.**
One Message may have several Journeys, one per matched Subscription. Dismissing
one must not queue a Message that the others are still working on — so it cannot
be Message-level. And once it is Journey-level, `Dismissed` and `Failed` are
structurally identical: both terminal, both holding a position, both resumable.
A DJQ would need an FJQ beside it, where one query serves both — terminal
Journeys, filtered by state.

So: **one queue, for Messages that never lived.** Everything else is a Journey
in a terminal state, found by query and resumed from its checkpoint.

## Amendment, 2026-09-30: a Subscription is paused and resumed, never removed by an act

The owner, 2026-09-30: *We actually need a Subscription view, for all
subscriptions per cluster, with pause and resume, but not remove. That is
handled with the TOML configuration files.* And the same day, on where a
running node finds them: *During runtime I assume you can get the
Subscriptions from the RocksDB or SQLite.* What the code showed:
`xmip-core-persist` (`runtime_store.rs`, `EncryptedStore` over the `rocksdb`
and `sqlite` engines) held runtime records — Journeys, checkpoints, leases,
deduplication — and no Subscription; the Subscriptions are the TOML
configuration's, taken up into the runtime's execution tree
(`execution_tree.rs`, through `configure::bind`). So, as the owner then
steered: the Subscriptions are listed from the running node's execution tree
— its configuration — and what an operator's pause leaves, each
Subscription's standing and the Messages it holds, is kept in the runtime
store through persist, the one `EncryptedStore` over whichever engine the
node's program linked, never a side file.

- **What an operator sees of one.** A Subscription is named by its node and
  its configured name, unique on the node (`configure::bind` refuses two).
  The node publishes each as `observe::Subscription`: the Xmip Application
  that draws it, the file that Application was read from and its
  `[[subscriptions]]` entry there as the file says it
  (`configure::subscription_entry`, the developer's layout and comments
  kept), its filter as configured, where it leads
  (`configure::application::destination_words`), active or paused and who
  paused it (`observe::PauseState`), what it picked up since the node
  started, what it holds, and since when its state stands. A publication
  writes them as `[[subscriptions]]`.
- **A pause holds, and loses nothing** (`xmip-core-runtime`'s
  `pickup::Pickup`). Every Message routing matches to a paused Subscription
  is held: no Journey opens for that Subscription (clause 5) and nothing
  departs; the Message is kept as persist's `HeldMessage`, numbered in the
  order it was held, and counted as held. A keyed store keeps no order, so
  the Subscription's `SubscriptionHold` carries the range of what it holds.
  Nothing is deleted (ADR-0040): a held record is released only once its
  Subscription has picked the Message up. The other Subscriptions a Message
  matched pick it up as they would have. ADR-0041's pause of a scope is a
  mood on a stage's published health and holds no Message, and a
  Subscription has no stage scope for it to pause; this is not a second
  pause of that one, but the first that holds Messages.
- **A resume picks up what was held, oldest first.** Each held Message is
  picked up as if routing had just matched it, and a Journey opens for it
  then; while a resumed Subscription still has held Messages to pick up,
  what it matches joins the end of them, so it picks up in the order it
  matched. On a running node the runtime picks them up on a thread of its
  own and departs each where its Subscription leads (`held_work.rs`):
  departure authorizes again, now, as it always does (clause 8); the
  identity arrival concluded is held in its words and read back through the
  mechanism this node's authenticators declare under that name — a
  mechanism is never built from a record — and a Message whose mechanism
  the node no longer carries does not depart, in words.
- **A pause survives a restart.** The records said nothing of a pause
  outliving its process: a scope's pause lives in the published snapshot and
  is gone with it. The owner's steer settles it for a Subscription: its
  `SubscriptionHold` — paused, by whom, since when, the range it holds — is
  written on every act and every hold and read back as the node takes its
  Subscriptions up, so one paused before a restart is paused after it,
  holding what it held, and one resumed whose held Messages were not all
  picked up when the node stopped picks them up as it starts. A node whose
  program linked no runtime store holds in memory, for the node's life.
- **No remove.** A Subscription is configuration, drawn in an Xmip
  Application (ADR-0064) and added and removed in its TOML. `observe::Noun`
  says which acts each noun takes — a Subscription pause and resume, an
  Event subscription those and remove — and a remove of a Subscription is
  refused in words on every path, naming the TOML configuration. No
  surface offers one, and each says why.
- **Who acts, and the record of it.** An Operator and above act (ADR-0009);
  an Observer sees the list and no act. Every act is recorded in the node's
  audit (ADR-0062) as `subscription.pause` or `subscription.resume`, with
  the node, the Subscription, who acted and what it held, and in the host's
  audit by the surface that asked. An act on a Subscription the node is not
  configured with is refused in words.
- **How an act reaches the node** is the Event subscriptions' way
  (ADR-0065, amendment 2026-09-29), generalized rather than copied: a
  surface over a live node calls the runtime's library in the node's
  process (`xmip_subscriptions_v1`, `xmip_subscription_act_v1`,
  `xmip_operate.h` section 14); a surface over a snapshot leaves an
  `observe::Order` where the publication says its publisher takes orders
  (`xmip_order_v1`), and the node takes it at its next round. The order,
  its file and the acts' words moved from `xmip-core-event` to `observe`,
  one for both nouns; `xmip_order_v1` replaced
  `xmip_event_subscription_order_v1`. A read publication's Subscriptions are
  `xmip_publication_subscriptions_v1`, the plain name now this noun's, and
  its Event subscriptions `xmip_publication_event_subscriptions_v1`.
- **The Playground configures real ones.** Its RoundTrip test is an Xmip
  Application, a section of the Playground's `configuration/xmip.toml`
  (ADR-0064, amendment 2026-10-03): four
  Subscriptions, one per family of content contracts, each to the Send Port
  the send stage serves. The node that declared process writes it and a
  node configuration binding it into the run's shared directory, reads both
  through `runtime::start::read` and the execution tree as a node does,
  routes every pair its process stage hands on through the runtime's
  pickup, keeps what a paused one holds in a `RocksDB` runtime store sealed
  under the machine's key store (DPAPI on Windows, a private file on Unix),
  and publishes its Subscriptions with its snapshot. A paused one is seen to
  hold; a resumed one is seen to drain.
- **The surfaces.** A view in both GUIs, *Subscriptions*, before *Event
  subscriptions* (ADR-0052, amendment 2026-09-30); `xmip-cli subscriptions`
  and `Get-XmipSubscription` list, and pause or resume one named by its
  node and name. `Xmip.Surface`'s `SubscriptionQuery` is the one drill,
  filter and order they ask, `SubscriptionAct` holds pause and resume and
  nothing else, and `IOperatorSurface.Subscriptions` and `.Act` are the
  calls every surface makes. So that each noun has one name, every name that
  meant the Event kind says Event now (ADR-0065, amendment 2026-09-30).

Provenance: the owner's requirement and steer, quoted; what the code
showed; the record's form — the hold's place in the runtime, the persisted
shapes, the order in pickup, the restart rule, the order's move to
`observe`, the Playground's Application — is the assistant's drafting, for
the owner to overrule.

## Open

- **"An accepted Xmip Message shall never disappear" versus retention.** Per
  `message-disposition.md`, Accept is Message creation — which happens before Validation. So a
  Validation-failed Message is an *accepted* Message, and clause 3 stores it only until
  retention rules apply. Either "never disappear" means "never silently lost", and governed
  expiry under audited policy satisfies it, or Validation-failed Messages need a rule of their
  own. **This needs a ruling; it is not resolved here.**
- **Which module owns the Xmip DMQ.** Retention ages things out on policy; an accepted Message
  shall never disappear. Those pull in opposite directions.
  *Where it lives is answered 2026-10-01: Ledger state (amendment of that date). Which module
  owns it is still open.*
- **"Final disposition" versus replay.** An operator who adds the missing Subscription will
  want to replay from the DMQ, where a faulty Stream is replayable. Either "final" means its
  Journey ends there, or the asymmetry needs a reason.
  *Answered 2026-10-01: Replay from the Dead Message Queue is an Operator act (amendment of
  that date).*
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

## Amendment, 2026-10-01: the Dead Message Queue is Ledger state, and the sender is acknowledged after the receive cycle

**Provenance.** The owner, 2026-10-01, validated part by part with the
assistant; his words are quoted where they decided.

- **Acknowledgement after the whole receive cycle** (the owner: *On arrival
  each Stream is written to the node's Ledger and then when the Receive cycle
  is complete, Promote, Validate and what not then the sender is
  acknowledged*). The lifecycle above runs inside the receive call, with the
  Stream written to the Ledger in chunks through Xmip Storage right
  after transport authorization and before Preparation Steps; Publication
  writes the Message record, audited; then the sender is acknowledged. Data
  Transfer and Batch Load are acknowledged once accepted and validated; a
  Composite interaction holds the call until the response an Xmip Process
  produced (`runtime-model.md` section 5). Clauses 1 to 3 stand: a refusal
  at the transport keeps nothing, the Stream is kept from Message creation
  on, and a Message failing Validation is kept and answered where the
  protocol can, with no Journey.
- **The Dead Message Queue is Ledger state** (clause 4). A Publication that
  matched nothing is kept in the Ledger (`runtime-model.md` section 3) with
  its receive context, validation results, promoted properties and each
  Subscription's reason for declining — not in a store of its own. This
  answers where it lives; which module owns it stays open below.
- **Replay from it is an Operator act**, once a Subscription is added or
  fixed, from a new view, **Dead Message Queue** (ADR-0052, amendment of this
  date). That answers the open question *"final disposition" versus replay*:
  the Message is re-published by an Operator's Replay, as the amendment of
  2026-08-26 describes re-publishing.
- **Routing writes atomically.** The Publication is marked routed and its
  Journeys created in one atomic write; nothing is deduplicated (clause 4c).
- **A paused Subscription's Journey is written and held** until the
  Subscription is resumed, and picked up oldest first. This supersedes the
  amendment of 2026-09-30 where it said no Journey opens for a paused
  Subscription until it resumes; the rest of that amendment stands.

## Amendment, 2026-10-03: routing runs inside the receive cycle

The owner chose where routing runs (*Go with A*): inside the receive cycle,
on the thread carrying it, before the sender is acknowledged. The Message's
promoted properties are matched against the compiled Subscription filters,
one Journey per match, and the Publication — the Message and its Journeys —
is one atomic write, in the receive cycle's one statement on one Storage
node (ADR-0056, amendment of this date). This supersedes the amendment of
2026-10-01 where it said the Publication is marked routed and its Journeys
created in one atomic write by a routing step that claims it: there is no
routing pool and no claim on a Publication, and a node that dies before the
write has acknowledged nothing, so the sender sends again. Zero matches is
still the Dead Message Queue, decided before the acknowledgement. The rest
of that amendment stands.

Built 2026-10-03 (`runtime-model.md` section 9): a Publication that matched
nothing carries its Dead Message Queue entry in the same atomic write, and
Replay — the Operator's act, an order as Pause is, audited — routes the
entry's promoted properties against the Subscriptions of now, holds each
Journey it opens in its Subscription's queue and takes the entry out, in
one write, once.

## Amendment, 2026-10-04: a Send Port Group's Journeys, and Retry and Dismiss of a failed Journey

**One Journey per Send Port.** Clause 5's *one Journey per matched
Subscription* holds for a Subscription that leads to a Send Port or to an
Xmip Process; one that leads to a Send Port Group opens a Journey for each Port of
the Group, in the Group's order, in the Publication's one write, each led to
its Port and kept in its Port's queue (`runtime-model.md` section 10: *A Send
Port Group is only a named set: routing already made one Journey per Send
Port in it*). So each Port is sent, retried, failed and dismissed alone, and
the deduplication key — the Journey's identifier — is one per delivery to
one endpoint, as section 15 of the runtime model has it.

**A failed Journey waits for an Operator in its Send Port's queue**, and
the Operator's acts on it are built: **Retry** writes it Active and sends it
again from the queue, its tries begun anew; **Dismiss** writes it
`Dismissed`, its history, Message and Stream kept, and takes it out of the
queue. Each is one hand-on under a claim, audited with who acted, and goes
through the node's orders as Pause and Replay do. This is not a queue of
failed Journeys, which *There is no Dismissed queue* above rules out: it is
the queue the Journey was always in, where a Sequential Send Port's order
needs it, and a Dismissed Journey leaves it.

**Protocol-level deduplication is honored** (clause 4c's second
consequence): every send hands the transport the Journey's identifier, and
a technology whose protocol has an identifier its far end deduplicates by
puts it there.

Built 2026-10-04 (`xmip-core-runtime`'s `send_step`, `xmip_operate.h`
section 16). Corrected 2026-10-05 after an external review: an act is
decided on the Journey as read again under its claim, and refused in words
where another writer moved it after it was first read, so it never writes
back a state the Journey has left; and every Journey that failed in a Send
Port's queue is listed at the Port's scope — how many, and a page at a time
from Xmip Storage — so an Operator acts on any of them, not only the last
the Port's evidence names (`runtime-model.md` sections 10 and 13).

## Amendment, 2026-10-05: the receive gates run at the Location, then the Port

The lifecycle's *Contract implication, optional deserialization,
Validation* run once per level that configures them: the Receive
Location's, in its Party's format, then the Receive Port's, in the Port's
one format, each optionally promoting and transforming after; Preparation
Steps run before Message creation, the Location's then the Port's. The
order of the security gates and Message creation is unchanged, and a
refusal at either level is a refusal before Publication: what clause 2 and
clause 3 keep for it is unchanged, and the audit names the level that
refused. Validation is the artifact's choice, on by default where a
receive artifact names a Contract. ADR-0031, amendment 2026-10-05, the
owner's ruling; `runtime-model.md` sections 5 and 20.
