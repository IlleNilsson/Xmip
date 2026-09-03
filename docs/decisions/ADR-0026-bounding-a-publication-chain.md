# ADR-0026: A publication chain has a depth, and a ceiling

- Status: Accepted
- Date: 2026-09-03
- Related: ADR-0013 (the Journey model), ADR-0018 (the Service and the Host
  Services), ADR-0012 (the module boundary)

## In brief

- Theme: What Xmip is at runtime
- Subject: Nothing bounded a publication chain, and now something does
- Name: Bounding a publication chain
- Order: 8
- Concepts: Publication chain, depth, ceiling; Loop, cycle, runaway publication

A Process may publish back into Xmip and a Subscription may start a Process, so
a Process that publishes a Message matching a Subscription that starts the same
Process is a loop. Neither half is wrong on its own, which is why nothing
catches it.

Every Journey carries a **depth**: zero when it arrived from outside Xmip, one
more than its predecessor when a Publication caused it. A **ceiling** is
configured per node, and `Journey::following` — **the only way a chain grows** —
refuses the link that would pass it. A runtime cannot get round the bound by
taking another path, because there is no other path.

The refusal names the **Subscription and the Xmip Process** that would have
formed the next link, because an operator at three in the morning needs the pair
that made the loop and not a number. It is a value, not a panic: declining to
start the next Journey does not lose the Message, and what happens to it is a
disposition like any other.

This is a depth limit and **not cycle detection**. It cannot tell a loop from a
long legitimate chain. Cycle detection over artifact identities is the better
answer and it needs the chain persisted and cheap to walk, which is a
`xmip-core-persist` question nobody has answered.

## Context

Recovered from `message-runtime-context.md` during the ADR-0020 consolidation on
2026-08-26, where it sat as two of six unanswered questions: how are Subscription
Instance chains bounded, and how are repeated publication chains controlled.
Neither was ever answered. It has been open problem 13 since.

`runtime-model.md` states the hazard plainly and does not solve it: *a Process
that publishes a Message which matches a Subscription that starts the same
Process is a loop, and the runtime has no depth limit, no cycle detection and no
budget.*

**The chain did not exist yet, and that is why this is cheap.** `Journey`
carried `previous_journey_id` from ADR-0013 clause 4b, and
`Journey::following` — the constructor for a caused Journey — was called nowhere
outside its own tests on 2026-09-03. The runtime creates exactly one Journey,
at arrival. Nothing publishes back into Xmip, so nothing can loop today.

The lean recorded against problem 13 said it: *A is one integer on the chain and
can ship with the chain itself.* Doing it now costs a field and a signature.
Doing it after the publication path is built costs a retrofit through every
caller, and the retrofit is the kind that gets deferred until the night it is
needed.

**The Module boundary is not involved.** `HandlerInvocation` carries a
`journey_id` inward and `HandlerResult` carries a status, a payload reference
and promoted properties back. There is no publish call across the ABI: a Module
returns a result and the runtime decides what to publish. So the chain is built
entirely on the Xmip side, the depth is a runtime fact no Module sees, and
ADR-0012 is untouched by this record.

## Decision

### 1. A Journey has a depth

`depth: u32`. Zero for a Journey that arrived from outside Xmip. One more than
its predecessor for every Journey a Publication caused.

Depth counts **links, not Journeys**. Several Journeys may share one previous
Journey — that is one Publication matching several Subscriptions, ADR-0013
clause 5 — and they are siblings at one depth rather than a chain of three.

### 2. A Journey names why it exists

`cause: Option<ChainCause>`, holding the Subscription that matched and the Xmip
Process it started where it started one.

`previous_journey_id` says *which Journey*; this says *which event*. ADR-0013
clause 4b already recorded the gap as a known limit — a Journey that publishes
twice leaves a successor able to say which Journey started it and not which
publication within it. This closes half of it: the successor now names the
Subscription, though not yet which of two identical publications.

### 3. The ceiling is configured, with a default

`ChainLimit`, per node, defaulting to **32 links**.

**The number is a starting point and is recorded as one.** No estate has run
long enough to measure what a legitimate chain reaches, and a default chosen
before there is traffic is a guess whatever it is set to. Thirty-two is
deliberately far above any chain anyone has described and far below the depth at
which a loop becomes expensive. Revise it with production data, not with
argument.

A limit of zero is meaningful and not degenerate: it is how a node says a
Process may not publish back into Xmip at all.

### 4. The bound is enforced at the only door

`Journey::following` returns `Result<Journey, ChainRefused>` and is the only way
a chain grows.

This is the whole reason the ceiling is worth anything. A bound checked by
convention in each caller is a bound that the next caller forgets. A bound in
the constructor cannot be forgotten, because there is no second constructor.

### 5. The refusal names the pair that formed the loop

`ChainRefused` carries the limit, the depth reached, the previous Journey and
the `ChainCause` that would have formed the next link.

*The failure must name the cycle, not just refuse: the operator needs the
Subscription and the Process that formed the loop, or they are reading
configuration files at three in the morning.* That sentence is problem 13's and
it is a requirement, not a nicety.

### 6. A refusal is a disposition, not a fault

`ChainRefused` is a returned value. The Journey that published is untouched, and
the Message that would have started the next Journey is not lost by declining to
start it.

What happens to that Message — retention, the DMQ, an operator's queue — is a
disposition, and it is decided where every other disposition is decided. This
record does not choose it, because ADR-0013 owns dispositions and is still
Proposed.

### 7. This is not cycle detection, and does not pretend to be

A depth limit cannot distinguish a loop from a long legitimate chain. Near the
ceiling the two look identical, and the estate should expect a false refusal
before it expects a caught loop.

Cycle detection over artifact identities is the correct answer — the same
Subscription firing twice for one lineage is the actual signal — and it needs
the chain persisted and cheap to walk on every publication. That is an
`xmip-core-persist` question and it is not answered. An execution budget per
originating Message is what an operator ultimately wants, and its number is
unguessable before there is traffic to measure.

Both stay open. Clause 2 is what either will read.

## Consequences

- `xmip-core-journey` gains `chain.rs`: `ChainLimit`, `ChainCause`,
  `ChainRefused`. `Journey` gains `depth` and `cause`.
- `Journey::following` changes signature and returns a `Result`. Nothing outside
  the crate's own tests called it, so the blast radius is zero — which is the
  argument for doing it now rather than after.
- The ceiling has no configuration surface yet. `xmip-core-configure` gains one
  when the node configuration format is settled, which is open problem 14. Until
  then a caller passes `ChainLimit::DEFAULT`.
- Whoever builds the publication path passes through `following` and therefore
  through the bound. That is the point of clause 4 and it is the one consequence
  worth checking in review.
- Open problem 13 keeps its options B and C. What closed is A.
- The trailing questions filed under problem 13 — what exactly is preserved,
  what exactly is recovered, the canonical representation of Message content at
  each lifecycle stage, and whether a Message Contract is a first-class Artifact
  Definition — are untouched by this record.

## Alternatives considered

**A publication generation counter with a ceiling.** Recorded against problem 13
as option D and dismissed there in one line: it is a depth limit wearing a
different name. Agreed, and it is this record.

**Cycle detection over artifact identities.** Option B, and the right answer.
Deferred for the reason above, not rejected. Clause 2 exists so that it has
something to read when it lands.

**An execution budget per originating Message.** Option C. Covers loops and
runaway fan-out in one number an operator can reason about, and the number is
arbitrary until someone has production data. Deferred.

**Enforcing the bound in the runtime rather than in the Journey.** Rejected. The
runtime is where the chain is *used*; the constructor is where it is *made*, and
a rule enforced anywhere but at the point of construction is a rule with a
second path round it. It would also put a Journey invariant in a crate that does
not own Journeys.

**Carrying the whole walk on the Journey** so a refusal could print the entire
chain. Rejected as speculation. The requirement is the Subscription and the
Process that formed the loop, and clause 5 satisfies it from one step. A bounded
`Vec` per Journey costs storage on every Journey to serve the refusal path, and
the walk is what option B will need persistence for anyway.

## Provenance

Clauses 1 to 7 are the assistant's, drafted 2026-09-03 and approved by the owner
in the same session, on the instruction to solve open problem 13 and update the
documents.

The requirement in clause 5 — that a refusal names the Subscription and the
Process rather than a number — is the owner's, written into open problem 13
before this record existed. The lean this record follows, *A now, B later, C
eventually*, is the owner's from the same place.

The default of 32 in clause 3 is the assistant's and is the weakest thing here.
It is recorded as a starting point rather than a finding, and it is the one
number in this record that should be expected to change.
