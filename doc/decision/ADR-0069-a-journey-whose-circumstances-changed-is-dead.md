# ADR-0069: A Journey whose circumstances changed is a Dead Message

- Status: Accepted
- Accepted: 2026-10-09, the owner, in the words quoted below
- Date: 2026-10-09
- Related: ADR-0013 (the Journey model), ADR-0052 (amendment 2026-10-01: the
  Dead Message Queue and Replay), `runtime-model.md` section 9 (the Dead
  Message Queue is Ledger state)

## In brief

- Theme: What Xmip is at runtime
- Subject: What a Replay or a Retry does when what the Journey ran under has
  changed
- Name: A Journey whose circumstances changed is a Dead Message
- Order: 18
- Concepts: Replay; Retry; Dead Message; configuration change

**Xmip does not replay or retry a Journey whose circumstances have changed.
Where a Work Process, or the Pub/Sub configuration, changed between when the
Journey stopped and its Replay or Retry, its Message is a Dead Message.**

## Context

The owner, 2026-10-09: *We are not trying to be able to replay a journey if
the circumstances has changed. Lets say that a Work Process got shut down
waiting for another stream/message. Before the replay or retry the Work
Process or Pub/Sub configuration changed, Xmip shall call that a Dead
Message(es). BizTalk and other solutions to my knowledge can't get that
right anyway.*

## Decision

1. A Replay or a Retry continues a Journey only under the circumstances it
   stopped under.
2. Where the Work Process the Journey was in, or the Pub/Sub configuration
   it was routed by, changed before its Replay or Retry, Xmip does not
   continue it: its Message, or Messages, are Dead Messages.
3. The example the owner gave: a Work Process shut down while it waited for
   another Stream or Message, and its configuration changed before the
   Replay or Retry.

## Not decided

The owner's words do not say these; each is open until he does:

- how Xmip tells that a Work Process or the Pub/Sub configuration changed;
- what of the configuration counts as a change;
- what state the Journey is left in;
- whether its Messages join the Dead Message Queue as it is
  (`runtime-model.md` section 9) or are told apart there;
- what an Operator sees, and what a Replay of such a Dead Message does once
  it is in the Dead Message Queue.

## Consequences

- Today the Dead Message Queue holds what no Subscription matched
  (`terminology.md`, *Dead Message Queue*); this decision adds a second way
  in. The terminology entry says so.
- Nothing is built.

## Provenance

The owner's words of 2026-10-09, quoted in Context, recorded the same day.
