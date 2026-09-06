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
- Concepts: Health as a mood; Fine, Average, Holding, Done; rollup does not
  propagate the worst

**Health is a mood, not a colour — it names how a scope is doing, and a surface
paints it however it likes. Four moods, worsening: `Fine`, `Average`, `Holding`,
`Done`. And the worst does not propagate: `Done` is a leaf's mood, and any scope
above a `Done` leaf reports `Holding` — attention, drill in — so one fault deep
in the tree cannot carry the whole cluster to `Done`. `Fine` up the tree still
means every leaf beneath is `Fine`.**

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

### 1. Health is a mood, in four states

`Health` is `Fine`, `Average`, `Holding`, `Done`, in worsening order. The word is
the model; a surface renders it — the desktop and web GUIs paint `Fine` green,
`Average` yellow, `Holding` orange, `Done` red, and that mapping lives in the
GUI's stylesheet, nowhere else.

### 2. The worst does not propagate

A `Done` is the mood of the leaf that owns the fault. Every scope *above* that
leaf — transport, scenario, node, cluster — reports `Holding`, the rollup mood:
something below needs attention, drill in. So the worst a single `Done` among
thousands can do to the cluster is turn it `Holding`, and an operator drills down
through the `Holding` and `Average` scopes to the `Done` itself.

`Holding` is a rollup mood: a leaf is `Fine`, `Average` or `Done`; an aggregating
scope is `Fine`, `Average` or `Holding`. `Fine` still propagates as the strong
guarantee it was — `Fine` at a scope means every leaf beneath it is `Fine`.

### 3. Validation still reads the leaves

Where the runtime uses health to *validate* rather than to display — a
configuration is invalid if any leaf is `Done` — it inspects the leaf records,
not the rolled-up scope, since the root now reads `Holding` over a `Done` below.
The dashboard softens; the gate does not.

## Consequences

- `xmip-core-observe` owns the four-mood `Health` and the capping rollup in
  `Snapshot::worst`. `Done` is never returned for a scope above the leaf.
- `xmip-core-abi` and `xmip_operate.h` carry four wire values, `FINE=0`,
  `AVERAGE=1`, `HOLDING=2`, `DONE=3`, and the header calls them moods.
- The GUIs render the mood to a colour, adding orange for `Holding`; the mapping
  is theirs alone.
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
