# ADR-0070: An audit record holds what it audits

- Status: Accepted
- Accepted: 2026-10-09, the owner, in the words quoted below
- Date: 2026-10-09
- Related: ADR-0062 (every Xmip tool audits), ADR-0063 (data at rest),
  `runtime-model.md` section 16 (Audit, retention and archiving)

## In brief

- Theme: Operating Xmip
- Subject: What an audit record shows of the Message and Stream it audits
- Name: An audit record holds what it audits
- Order: 21
- Concepts: Audit; tamper evidence; Stream digest; retention hold

**An audit record spells out the Message it audits, in full, as it was at
the audited event, and its Stream's bytes with their digest, so the copy is
verified when it is read (amendment 2026-10-09). Each audit record carries
the digest of the one before it, so a deleted, changed or reordered record
is found.**

## Context

The owner, 2026-10-09: *In an Audit you can't have references, it should be
spelled out. So no references, if not needed* — and the same day, of the
kept audit table: *I can't see that the audit record contains the actual
message and stream. … If authorities want to do Auditing, they need to see
the untarnished data in the Audit log, what do you propose?* Until then
`runtime-model.md` said Audit *uses retention to show Messages and their
Streams at audited events*: a reference to content nothing guaranteed was
still there, or unchanged. The proposal below was accepted: *So lets go with
that for now.*

## Decision

1. **The Message is spelled out.** An audit record of an act on a Message
   carries that Message in full — its context, promoted properties,
   sections and generation — as it was at the audited event.
2. **The Stream is sealed, not copied.** The record carries the Stream's
   SHA-256 digest and its length. A Stream is written once and never
   changed (`runtime-model.md` section 1), so the digest names exactly
   those bytes; copying a payload into every audit record of every step is
   not done.
3. **A Stream named by an audit record is held** for as long as that record
   is kept: retention does not remove it.
4. **A Stream read for an audit is verified** against the digest its record
   carries; a Stream that does not match is reported as not the audited
   one, in words.
5. **The audit log is a chain.** Each audit record carries the digest of the
   record before it; a verification reports the first place the chain
   breaks.

## Not decided

- what "the record before it" is when several programs and nodes audit at
  once — one chain per program, per node or per cluster;
- the verification's surface (command, cmdlet, view);
- what an auditor is given to read a held Stream, and under which role.

## Consequences

- The kept `audit` table gains the Stream's digest and length and the
  previous record's digest; the Message travels in the audit record.
- The writer computes the digest as it writes the Stream, from the bytes
  that pass through it once.
- Built, 2026-10-09: clauses 1, 2 as amended and 4. A record of an act on a
  Message — a Publication, a Replay — carries the Message in its one binary
  form (`persist::storage::Audited`); the writer keeps the digest in the
  Stream's own record (`ledger::write_stream`); the audit keeper copies the
  chunks of every Stream the Message's Sections are over beside the kept
  record, one at a time and a shared Stream once, into the
  `audit_stream_chunk` table, and keeps each Stream's digest and length in
  the record's body, since a Message has a Stream per Section and a column
  holds one value; a read is held to both (`persist::storage::ChunkReader::audited`). Nothing runs the
  keeper outside tests and no surface reads a kept record
  (`estate-map.md`, `audit-through-storage`). Clause 5 is not built.

## Provenance

The owner's words of 2026-10-09, quoted in Context, recorded the same day.

## Amendment, 2026-10-09: the Stream is spelled out too

The owner, the same day: *Go ahead Audit has to be spelled out, could be in
another storage solution if that helps.* Clause 2 is replaced: an audit
record carries its Stream's bytes, not a digest of them; the digest stays,
so the copy can be verified. Clause 3 falls away: the audit no longer needs
retention to hold a Stream. Where audit is kept may be a storage of its own
if that helps; today it is the administration database
(`runtime-model.md` section 16), and nothing here moves it.
