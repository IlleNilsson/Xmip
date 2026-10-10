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
  `audit_stream_chunk` table, and writes each Stream's row of the
  `audit_stream` table — its length, chunks, digest and when it was written,
  in clear columns — in the record's own write; a read is held to both (`persist::storage::ChunkReader::audited`). Nothing runs the
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

## Amendment, 2026-10-09: the whole of it goes to audit

The owner, asked whether each audited Stream's digest and length should be
visible rather than sealed in the record: *Yes, when the Xmip Core or its
Providers uses the Audit functionality the whole shebang goes to audit. How
else could a serious government, bank or insurance company work?* An audit
written by Xmip's core or by any provider's module carries everything it
audits, laid out where a column can hold it: each audited Stream is a row of
its own beside its bytes, with its identifier, length, digest and chunk
count.

## Amendment, 2026-10-10: the chain follows what is audited

The owner, asked whether clause 5's chain runs per program, node or
cluster: *I guess it has to be per journey, thread, program, node & cluster
depending on what is being audited.* There is no single chain: an audit
record chains to the record before it within the scope of what it audits —
a Journey, a thread, a program, a node or the cluster. Which act belongs to
which scope, and whether a record sits in more than one chain, is not yet
decided.

## Amendment, 2026-10-10: one chain per writer

Asked what the majority of auditing rules say, the owner chose to follow
them: *Go with that.* PCI DSS requirement 10, ISO/IEC 27001 control 8.15,
NIST SP 800-92 and SP 800-53 (AU-9, AU-10) and SEC 17a-4 prove a log's
integrity and completeness per log source, and AWS CloudTrail, Certificate
Transparency and RFC 5848 chain or sign per writer; none keeps a chain per
transaction. So every audit record sits in exactly one chain, its writer's —
the node's, or the program's where no node writes it — and a Journey's, a
thread's or the cluster's trail is found by its identifier across those
chains, each proven intact. This replaces the amendment above it.
