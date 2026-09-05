# ADR-0032: Recent activity — the individual items, not only the counts

- Status: Accepted
- Date: 2026-09-05
- Related: ADR-0027 (the operator boundary), ADR-0029 (observation has history),
  ADR-0013 (the Journey model), observability-model.md section 6

## In brief

- Theme: Operating Xmip
- Subject: An operator drills past the counts to the individual items
- Name: Recent activity
- Order: 7
- Concepts: Activity, recent items; Stream, Message, Journey

**Beside health and throughput, the operator boundary publishes a bounded list
of the recent individual items — the Streams that arrived, the Messages that
were sent, the Journeys that ran.** Drilling down reaches not just a redder
number but the actual items behind it. It is **recent activity**, not retention:
a short, published, bounded list for watching, never the full Message for replay
(that stays `xmip-core-retain`'s).

## Context

The owner's requirement, 2026-09-05: *drill down and a view of individual
Streams, Messages and Journeys.* ADR-0027's boundary reads snapshots — aggregate
health and counts — and clause 6 forbids counting on demand. A count tells an
operator a stage is busy or stuck; it does not tell them *which* Message is
stuck. That is the gap this fills, without breaking clause 6: the items are
**published** as they happen, bounded, and the boundary reads what was
published, exactly as it reads health.

## Decision

### 1. Activity is a bounded list of recent items

`xmip-core-observe` gains `Activity` beside `Snapshot` and `History`: a bounded
ring of the most recent items, oldest dropped. An item is a **Stream**, a
**Message** or a **Journey** — the three units the estate already names — carried
with its scope, its identity, its size in bytes, when it was observed, and a
short line of detail (an outcome, a `JourneyState`).

### 2. It is published, not queried

Activity is written as items happen and read from what was written, the same as
health and throughput (ADR-0027 clause 6). No surface makes execution wait to
list items; the watcher cannot stop the watched.

### 3. It is recent, not retention

Activity is a short window for watching — the last N items. It never holds
content, and it is not the record an operator replays from; that is retention
(observability-model.md), which holds the whole Message and is governed
separately. Activity points at an item; retention holds it.

### 4. Every surface reaches it

Drilling to a scope in the UI lists its recent Streams, Messages and Journeys.
The CLI lists them for a scope; the ABI gains an entry point beside health and
history. A scope with nothing recent says so.

## Consequences

- `xmip-core-observe` gains `Activity`; producers push items as they observe
  them; the file surface and, later, the runtime publish them; the GUIs, CLI and
  ABI read them.
- The Playground publishes a Stream and a Message per round — the two ends each
  pingpong drives. It publishes **no Journeys**: it exercises transport and
  contract, not processing, so there is no Journey to show until a real node
  runs. The view says so rather than inventing one.
- Bounded like history, for the same reason: a node runs for weeks, and the list
  is memory proportional to how many items are kept, not how many have flowed.

## Alternatives considered

**Reading items on demand from the hot path.** The obvious way to always have the
latest. Rejected by ADR-0027 clause 6: a surface that queries execution can stall
it. Publishing keeps the watcher unable to stop the watched.

**Serving activity from retention.** Retention holds every Message; a view could
page through it. Rejected as the default: retention is content, governed and
often costly, and an operator watching a rolling estate wants the last few items
cheaply, not a query over everything ever kept. Retention is the drill *past*
this, when an item must be opened and replayed.

## Provenance

The requirement is the owner's, 2026-09-05: *drill down and a view of individual
Streams, Messages and Journeys.* Clauses 1 to 4 are the assistant's drafting of
it, on the instruction to proceed and to write the decision down.
