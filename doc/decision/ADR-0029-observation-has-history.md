# ADR-0029: Observation has history

- Status: Accepted
- Date: 2026-09-05
- Related: ADR-0027 (the operator boundary), ADR-0028 (the Xmip Playground),
  ADR-0013 (the Journey model), observability-model.md section 6

## In brief

- Theme: Operating Xmip
- Subject: The operator boundary reads observation over time, not only its latest
- Name: Observation has history
- Order: 6
- Concepts: History, an observation series; Observation point; Retention window

**An operator reads history, not only the present.** ADR-0027's boundary reads
the latest snapshot; this record adds a **bounded series over time** beside it,
so every surface — the ABI, the CLI, the web UI and the desktop GUI — can show
how a scope's health and throughput moved, not just where they are now. It is
**monitoring history**, distinct from message retention (ADR-0013,
observability-model.md): retention holds the actual Message for replay; this
holds numbers and states for watching.

## Context

The owner's requirement, 2026-09-05: *abi, cli, ui and gui shall have history.*
While watching the playground roll, the present tense is not enough — an
operator needs to see a pair that flickered red an hour ago, or throughput
climbing over a shift. ADR-0027 already carries a **window** on every
measurement and versions the boundary independently, so history is an addition,
not a redesign.

Two producers exist. The runtime retains history in memory and answers the ABI;
the Playground, which has no runtime yet, writes its history to a file the file
surface reads. Both hold the same shape, so a surface reads history the same way
whichever is behind it.

## Decision

### 1. History is a bounded series of observation points

Per scope, the observation layer keeps a series of points over time. A point is
what a snapshot already carries at one instant: a health state and severity, and
the throughput counts. The series is **bounded** — a fixed capacity per scope,
oldest dropped — so a node that runs for a week does not grow without limit.
`xmip-core-observe` owns the type, `History`, beside `Snapshot`.

### 2. The series is read by scope and range

A surface asks for a scope's history over a time range, or its last N points.
Health history and throughput history are the two shapes, because a state
timeline and a numeric series read differently — one shows when it broke, the
other shows the curve.

### 3. The ABI gains a history entry point

`xmip_operate.h` grows a history query beside `health` and `measure`, versioned
with the boundary (ADR-0027 clause 2). It reads retained history and never
computes on demand (clause 6): the runtime retains as it publishes, the boundary
reads what was retained.

### 4. Every surface presents it

- **CLI** — a `Get-XmipHistory` reads the series for a scope.
- **Web UI** — a sparkline per scope and a throughput curve on the cluster.
- **Desktop GUI** — the same, plus history in the configuration view.

A surface with no history to show says so, as it does for a missing snapshot.

### 5. The Playground writes history to a file

Until a runtime retains it, the Playground writes its snapshot and its history
to files beside each other, and the file surface reads them. The files are
**TOML**: on disk the estate is TOML, and JSON is reserved for what lives in
memory or on the wire (the owner's rule, 2026-09-05 — the same reason
`architecture.json` was deleted for `architecture.toml`). They are bounded the
same way the in-memory series is: the writer keeps the last N points.

## Consequences

- `xmip-core-observe` gains `History`; `xmip-core-abi` a history entry point;
  `xmip-core-runtime` retains and answers it; the CLI and both GUIs read it.
- Retention capacity is a number with a home in configuration later; until then
  a sensible default (a few thousand points per scope) lives in the code.
- This is not message retention. History here never holds content; content that
  must be preserved is `xmip-core-retain`'s, unchanged.

## Alternatives considered

**A metrics database (Prometheus, a TSDB).** Rejected as a default: Xmip is
on-premises first and must run on a laptop with no dependency. An in-memory ring
and a bounded file are enough to watch a node; exporting to a TSDB is an optional
target, not the boundary.

**History only in the UI.** What a chart library would give for free. Rejected:
the owner's requirement names all four surfaces, and the CLI and ABI are how an
operator without a browser, and another program, read the same history.

## Provenance

The requirement is the owner's, 2026-09-05: *abi, cli, ui and gui shall have
history.* Clauses 1 to 5 are the assistant's drafting of it, on the instruction
to proceed.

## Amendment, 2026-09-19: a point is the measurement at the scope it names

**What was wrong.** Clause 1 says a point is what a snapshot carries at one
instant, and clause 5 says the Playground writes its history to a file. Neither
said at **which scope** the file's points are counted, and the two halves
disagreed in the code. A snapshot file carries the node's throughput as
`Snapshot::measure` rolls it up — every count at and beneath the node, summed.
A history keeps a series per scope exactly as it was recorded, and reads one
exact scope back. The Playground's scenarios record beneath the node, each
under its own subtree, and nothing was ever recorded at the node itself, so the
series for the node was empty.

**What it cost.** Every `*-history.toml` the Playground ever published held
`points = []` — from the day this record was accepted, 2026-09-05, to the day
it was found, 2026-09-19. `Get-XmipHistory` emitted nothing, the ABI's series
held nothing and the GUI drew no curve. Nobody noticed for a fortnight because
no test asserted that a history file holds points and no surface said that the
one it read was empty.

**What now holds.**

- **A history point is the same counted measurement the snapshot publishes, at
  the same scope**: the rollup at and beneath the scope named, not only what
  happened to be recorded at that exact scope. The producer retains it that
  way, so the boundary still reads what was retained and computes nothing
  (clause 3, ADR-0027 clause 6).
- **The Playground records it each round**: `test/playground/src/curve.rs`
  records the snapshot, which keeps every scope's own series, and beside it the
  node's rollup, which is the curve the file carries. Its tests assert that a
  round driven the way a roll drives one leaves points in the file — and that
  recording the snapshot alone leaves none, which is the defect kept as a test.
- **A surface with no history says so** (clause 4, ADR-0055).
  `Get-XmipHistory` warns, naming the file, when the history it read holds no
  points, rather than emitting nothing and looking like a quiet node.

The file format is unchanged: the reader was right and the producer was wrong.
The other defect of that day, a running roll made unfindable by a rebuild, is
ADR-0028's.
