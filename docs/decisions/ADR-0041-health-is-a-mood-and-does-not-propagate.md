# ADR-0041: Health is a mood, and the worst one does not propagate

- Status: Accepted
- Date: 2026-09-06
- Related: ADR-0027 (the operator boundary, amendment 2026-09-05 "three states,
  no fourth"), ADR-0028 (the Playground), docs/architecture/observability-model.md

## In brief

- Theme: What Xmip is at runtime
- Subject: Health names a mood, in four states, and the worst does not roll up
- Name: Health is a mood and does not propagate
- Order: 12
- Concepts: Health as a mood; Fine, Working, Stressed, Exhausted, Done; Holding
  the rollup; a leaf's mood does not propagate

**Health is a mood, not a colour — it names what a human gets out of a thread,
process, node or cluster (the resource under load, not the machine) and what to
do when results stop. A surface paints it. Five leaf moods, worsening: `Fine`
(results flowing), `Working` (handling the load), `Stressed` (strained — change
the load), `Exhausted` (spent — replace the hardware), `Done` (blocked or failed
— the pain: a cert, a password, a folder). And a leaf's mood does not propagate:
in a perfect world everything is `Fine`, and the moment anything below is not,
the parent is displeased and reports `Holding` — drill in. A parent is only ever
`Fine` or `Holding`; `Fine` up the tree still means every leaf beneath is
`Fine`.**

## Context

The owner, 2026-09-06, watching a Playground board go a sea of red: a rollup that
propagated the worst state upward meant one red leaf turned its transport, its
scenario and the cluster all red, so the top of the tree screamed the moment
anything anywhere failed. *The severity on lower levels must not propagate to a
red for the cluster; one has to drill down through the yellows to find the red
ones.*

And the states were named as colours — Green, Yellow, Red — which fixed the
rendering into the model. The owner's correction: *Health is a mood — Fine,
Average, Holding, Done. It is not colours.* A colour is how a surface shows a
mood, not what the mood is.

This revises ADR-0027's 2026-09-05 amendment, which fixed three states and named
them as colours. The owner set both in motion; this records where they land.

## Decision

### 1. Health is a mood — what a human gets from the resource

`Health` is not the machine's state; it is what a human gets out of the resource
under load. Five leaf moods, worsening: `Fine` (results flowing), `Working`
(handling the load), `Stressed` (strained — the operator's action is to change
the load), `Exhausted` (spent — the action is to replace the hardware), `Done`
(blocked or failed — the one thing to fix: a cert to renew, a password, a missing
folder). Each mood is *actionable*: it either says results are fine or points at
what to change. The word is the model; a surface renders it — the GUIs paint Fine
green, Working blue, Stressed yellow, Exhausted burnt, Done red, and that mapping
lives in the stylesheet, nowhere else.

### 2. A leaf's mood does not propagate

In a perfect world everything is `Fine`. The moment anything below a scope is not
`Fine`, that parent is displeased and reports `Holding` — the rollup mood:
drill in. So a parent — transport, scenario, node, cluster — is only ever `Fine`
or `Holding`; the leaf that owns the trouble carries the real mood, and an
operator drills down through the `Holding` scopes to it. The worst a single
trouble among thousands can do to the cluster is turn it `Holding`. `Fine` still
propagates as the strong guarantee it was — `Fine` at a scope means every leaf
beneath it is `Fine`.

### 3. Validation still reads the leaves

Where the runtime uses health to *validate* rather than to display — a
configuration is invalid if any leaf is `Done` — it inspects the leaf records,
not the rolled-up scope, since the root now reads `Holding` over a `Done` below.
The dashboard softens; the gate does not.

## Consequences

- `xmip-core-observe` owns the four-mood `Health` and the capping rollup in
  `Snapshot::worst`. `Done` is never returned for a scope above the leaf.
- `xmip-core-abi` and `xmip_operate.h` carry six wire values, `FINE=0`,
  `WORKING=1`, `STRESSED=2`, `EXHAUSTED=3`, `DONE=4`, `HOLDING=5`, and the header
  calls them moods.
- The GUIs render each mood to a colour (Working blue, Stressed yellow, Exhausted
  burnt, Holding orange, …); the mapping is theirs alone.
- The Playground publishes moods (`fine`/`average`/`holding`/`done`) as its
  state, and its board and terminal readout read as moods.
- observability-model §6 is corrected to four moods and the non-propagating
  rollup; ADR-0027's three-state amendment is superseded here.
- A node that does not answer is `Done` at that node, with "no answer" as its
  evidence — unchanged in substance, renamed with the rest.

## Provenance

Both moves are the owner's, 2026-09-06: *the worst must not propagate to the
cluster — drill through to find it*, and *Health is a mood: Fine, Average,
Holding, Done, not colours*. The rollup-cap mechanism, the leaf-versus-rollup
split for validation, and the colour-in-the-GUI-only framing are the assistant's
drafting of it, on the instruction to write it down.
