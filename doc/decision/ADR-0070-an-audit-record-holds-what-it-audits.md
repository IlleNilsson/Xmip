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
- Concepts: Audit; tamper evidence; Stream digest; retention hold; audit database

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

- what an auditor is given to read a held Stream, and under which role;
- whether a node's records in its program's `audit.toml` and those Xmip
  Storage keeps for it are one chain: they are two, one in each log, today;
- that a record deleted from the end of a chain is found: nothing outside
  the chain holds where it ends;
- a surface for the chains Xmip Storage keeps: no surface reads a kept
  record yet.

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
  (`estate-map.md`, `audit-through-storage`).
- Built, 2026-10-10: clause 5 as amended, one chain per writer, and the body
  in chunks (amendment below). The writer is `Origin::writer` in
  `xmip-core-audit`: the location a process declared where it is a node's,
  else the program's name. A record carries its number in its writer's
  chain, the SHA-256 digest of the record before it there (none, zeros, for
  the first) and its own, taken over its canonical form, which holds the
  number and the digest before it. In a program's `audit.toml` the file sink
  forms the chain as it appends, holding `audit.lock` beside the file, and
  reads where the writer's chain stands from the file's end — so a restarted
  program goes on from its last record; the canonical form is the record's
  TOML table without the line of its own digest. In Xmip Storage the audit
  keeper forms it as it keeps each record, once by its identifier and in
  the order written, the head of each writer's chain kept in the
  `audit_chain_head` table in the record's own write; the canonical form is the kept row — every column but its own
  digest and the keeper's time — and the record of every Stream it carries,
  the body inside it through its digest (`persist::storage::chain_digest`).
  The `audit` table lays out `writer`, `position`, `previous_digest` and
  `digest`, indexed on the writer and the number. One walk,
  `xmip-core-audit`'s `audit_chain::walk`, says the first place a chain
  breaks — a record deleted, changed or out of order — or that it is whole,
  in words; `xmip-cli audit --verify`, `Get-XmipAudit -Verify` and the Audit
  view's *verify chains* walk the chains in the file, through
  `xmip_audit_read_v1`'s `verify`, and the runtime's
  `ledger::verify_audit_chain` walks one Xmip Storage keeps. Verifying reads
  no payload, so an Observer may: it is a reading, and ADR-0009's amendment
  of 2026-09-06 lets an Observer read every monitoring surface.

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

## Amendment, 2026-10-10: the body is kept in chunks

The owner: *The audit body has to be like the stream, in chunks.* A kept
audit record's body — its record and the Message it carries in full — is
kept as a Stream is: beside the record's row in a chunk table of its own,
`audit_body_chunk`, by the record's identifier and the chunk's number, in
chunks of the size the runtime writes a Stream in (`ledger::CHUNK`), written
in the keeper's write, its length, chunks and SHA-256 — taken as the chunks
pass — laid out in the row, and read back a chunk at a time, held to its
length and digest, never whole (`persist::storage::ChunkReader::audit_body`).
The record's digest in its writer's chain covers the body through that
digest.

The owner, the same day: *every type of data goes into dedicated tables,
dedicated columns.* The body's chunks are a table of their own, never
shared with `audit_stream_chunk` or the Ledger's `stream_chunk`; what is
shared is the code that reads chunks (`ChunkReader`), not a table.

## Amendment, 2026-10-10: audit is a database of its own

The owner: *The audit part might be better of in its own database so it can
be hosted on a different set of nodes, different storage*, and *So the
02-databases.sql script has to be re-engineered into statements per data
domain.* The first amendment of 2026-10-09 allowed audit *a storage of its
own if that helps*; this takes it up. Audit is a third data domain beside
the runtime and the administration databases: the **audit database**,
`xmip_audit`, holds every kept audit table — `audit`, `audit_chain_head`,
`audit_body_chunk`, `audit_stream` and `audit_stream_chunk` — and the
administration database holds none of them. The audit keeper moves each
record from the runtime database, where it is first written, into the audit
database (`persist::storage::schema`, `Database::Audit`).

- **On an embedded Storage node** the audit database is a store of its own
  on the administration database's engine, SQLite (ADR-0015, amendment
  2026-10-01; `deployment-model.md` section 7: *RocksDB is the first
  storage for audit records, then transferred to SQLite*), beside the
  other two, `<data>/storage/audit.sqlite`, unless its configuration says
  otherwise (the next amendment).
- **IT's scripts are per data domain** (`deploy/database/<server>/`):
  `01-roles.sql` on every server, then `02-<domain>-database.sql` and
  `03-<domain>-schema.sql` for each domain a server holds;
  `02-databases.sql` is deleted.

`deployment-model.md` section 7's "two databases" is extended to three, not
contradicted: the runtime and the administration databases stay separate,
and audit leaves the second for a database of its own. Not decided: whether
the audit database is served by a separate set of Storage nodes, which a
node would reach by a list of its own.

## Amendment, 2026-10-10: each data domain is a table of its own

Asked how the three data domains are configured in the Cluster TOML, the
owner: *i would do it like runtime, storage, connection string. Same for
audit and administration*; shown the form, *Yes, better.* Each domain is a
table of its own, `[runtime]`, `[administration]` and `[audit]`, each with
`storage`, the technology its database is kept on — `rocksdb`, `sqlite`,
`postgresql` or `mssql`, the ones Xmip Storage has today
(`persist::storage::database::Technology`) — and `connection`: on an
embedded engine the store's path, relative to the configuration file; on a
database server the server's own connection string, PostgreSQL's
`host=… port=… dbname=… user=…` and SQL Server's
`Server=…,<port>;Database=…;User Id=…`.

- **Each domain may be on another technology and another server.** The
  rule that the databases are on one kind of server is deleted; two
  domains naming one database on one server are still refused.
- **A table left out keeps the default it had**: the embedded Storage
  node's own, `rocksdb` at `<data>/storage/runtime`, `sqlite` at
  `<data>/storage/administration.sqlite` and at
  `<data>/storage/audit.sqlite`.
- **The connections leave `[storage.database]`**, which keeps the secret
  the password is kept under and the trust anchor; `[store]` keeps the key
  store.
- **Embedded, the engines stay as ADR-0015 rules**: `rocksdb` for the
  runtime database, `sqlite` for the other two; another is refused in
  words.
- **A database server's backend is not built yet**, so a node naming one
  for a domain is refused as it starts, in words.

Not decided: whether one `[storage.database]` secret serves domains on
different servers, or each domain names its own.
