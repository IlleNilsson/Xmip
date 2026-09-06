# ADR-0040: Xmip retains and archives; it does not delete

- Status: Accepted
- Date: 2026-09-06
- Related: ADR-0013 (the Journey model), ADR-0028 (the Xmip Playground),
  docs/architecture/observability-model.md, `xmip-core-retain`

## In brief

- Theme: What Xmip is at runtime
- Subject: Retention ends at archiving; deleting data is not Xmip's responsibility
- Name: Xmip retains and archives, it does not delete
- Order: 11
- Concepts: Retention; archiving; the archive owner; no deletion

**Xmip gets data, transforms it, waits for business decisions, and sends one or
more outputs. For the data it holds, it does exactly two things over time: it
**retains** it while it is live, and **archives** it when its retention window
passes. It never deletes. Once archived, what becomes of the archive is the
archive owner's decision, not Xmip's.**

## Context

The owner, 2026-09-06, watching the Playground's secretary scenario, which had
grown a third stage called *purge*: *First keep retention, then archive. If all
fails, archive. Do not delete — that is not Xmip's responsibility. Xmip gets
data, transforms, waits for business decisions, sends one or multiple data. Xmip
does not delete; retention and archiving. Then the user of the archive decides
what to do about the archive.*

The word *purge* was the assistant's, introduced without the owner's say-so and
absent from terminology.md. Worse than the word, it implied an action Xmip does
not take. The estate's own `xmip-core-retain` crate carried a `RetentionAction::
Delete`, so the drift was in the code, not only the label.

## Decision

### 1. Two retention actions, not three

`RetentionAction` is `Keep` and `Archive`. `Delete` is removed. Retention keeps
data live while it is young and archives it once it passes its window; there is
no third action, because deleting is not a thing Xmip does.

### 2. Archiving is terminal for Xmip

Archiving is the last thing Xmip does with a piece of data it is holding. The
archive is a handoff: once an item is in the archive store, Xmip's
responsibility for it is discharged. It does not later revisit the archive to
remove anything.

### 3. Deletion belongs to the archive owner

Whether, when and how archived data is deleted is decided by whoever owns the
archive — a records office, a compliance regime, a downstream system — not by
Xmip. Xmip provides the archive; the owner disposes of it. This keeps the
platform clear of a responsibility (destroying a partner's records) that is
theirs to hold and theirs to answer for.

### 4. The scenario matches

The Playground's secretary is two stages — **retain**, then **archive** (ADR-0028).
Archived items accumulate; the scenario never purges them, because Xmip never
does. A missed sweep under pressure still surfaces as a retention or archive
leak, which is the property the scenario exists to prove.

## Consequences

- `xmip-core-retain`'s `RetentionAction` loses `Delete`; only the playground
  consumed it, so the change is contained.
- The secretary scenario drops its `purge` stage and its "delete by age" path.
- terminology.md's retention vocabulary stays *retention* and *archiving*; no
  *purge*, no *delete*, is introduced.
- A reviewer treats any future "Xmip deletes data" path as a defect against this
  record, whatever it is called.
- If a deployment needs archived data destroyed on a schedule, that is the
  archive owner's mechanism to build against the archive Xmip produced, and a
  separate decision if it ever touches Xmip at all.

## Provenance

The ruling is the owner's, 2026-09-06: *Xmip does not delete; retention and
archiving; then the user of the archive decides.* The two-action framing, the
archive-as-handoff wording and the crate/scenario consequences are the
assistant's drafting of it, on the instruction to write it down, having first
introduced the *purge* the owner corrected.
