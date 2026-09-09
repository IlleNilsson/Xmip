# ADR-0044: A technology shares through its capability

- Status: Accepted
- Date: 2026-09-09
- Related: ADR-0010 (contract and transport repository boundaries), ADR-0016
  (submodule composition, amendment 2026-09-07), ADR-0033 (one TLS stack),
  doc/architecture/repository-model.md section 4 (dependency rules),
  doc/planning/open-problems.md problem 7

## In brief

- Theme: The shape of the estate
- Subject: Where code two technologies both need lives, and where it never
  does
- Name: A technology shares through its capability
- Order: 11
- Concepts: Shared code; the capability crate; the carrier technology; copied files

**Code that two technologies both need lives in the crate both already
depend on: their parent capability, or the technology they both ride on. A
technology never copies a sibling's file. The playground's adapters follow
the same rule through the playground's own shared modules.**

## Context

Sixty-five technology repositories were written between 2026-09-07 and
2026-09-09, most of them by assistants working in parallel, each inside one
repository with no view of the others. The result was correct and duplicated.
On 2026-09-09 a scan found: the same HTTP request-and-answer file, byte for
byte, in the s3, azure-blob and google-cloud-storage transports, with the same
endpoint and percent-encoding files beside it; the same flat-XML scan in two of
them; the same RFC 3339 clock in five archive technologies; the same object
layout in three; the metadata pair encoding in all ten. The
transport capability had already absorbed one such case on 2026-09-08 —
`socket.rs`, "opens every socket once" — without the rule being written down,
which is why it happened again the next day.

The owner, 2026-09-09: *So then it is time. Let's consolidate, refactor and
re-engineer if needed.*

Repository-model.md section 4 already fixes the direction: a technology may
depend on its parent capability; a capability never depends on its
technologies; a technology sibling dependency needs a declared justification.
What was missing was the consequence for shared code.

## Decision

### 1. Shared code goes up, never sideways

When two technologies need the same code, it moves to the nearest crate both
already depend on:

- **The parent capability**, when the code is about the capability's own
  subject. `xmip-core-archive` holds the metadata text, the timestamp, the
  name-keyed layout and the receipt checksum — every archive technology's
  item looks the same to an operator because of them. `xmip-core-transport`
  holds sockets, wire framing and the flat-XML scan a protocol document is.
- **The carrier technology**, when the code is about the protocol the two
  ride on. A REST API over HTTP shares HTTP's request-and-answer, endpoint
  and percent-encoding through `xmip-core-transport-http`, which s3,
  azure-blob and google-cloud-storage already carry as their declared
  sibling dependency (ADR-0033 put TLS there for the same reason).

Nothing moves *down* into a technology for another to import, and nothing is
copied. A file with the same content in two repositories is a defect, found
by the scan in `.ai-interaction` and, from this record on, fixed by moving
it up.

### 2. What stays in the technology

The dialect. A `PostgreSQL` row and a SQL Server row share the column set and
the metadata text through the capability; they keep their own quoting, their
own bytes literal and their own way of reading an id back. The rule moves what
is *the same*, not what is *similar*.

### 3. The playground follows the rule through its own modules

Every adapter file in the playground — `industrial.rs`, `broker.rs`,
`storage.rs`, `remote.rs` and the rest — shares through `roundtrip.rs`,
`cabinet.rs` and `support.rs`, never by repeating a helper. The scan runs
over the playground as well.

### 4. Problem 7's lean, applied

Open problem 7 leaned to *keep five modules, share a store trait* so the
`postgres` adapter is not written five times. The archive technologies do it
one step further: archive-postgresql, -mssql, -mysql, -s3, -azure-blob and
-gcs each ride on the transport technology of the same name for their wire
client, and hold only the archive's own shape. When audit, report and observe
grow technologies, they ride on the same transports.

## Consequences

- `xmip-core-archive` gains `metadata`, `timestamp`, `layout`, `checksum` and
  a `sha2` dependency; ten archive technologies lose their copies.
- `xmip-core-transport-http` gains `message`, `endpoint`, `percent`;
  `xmip-core-transport` gains `xml`; three object-store transports lose theirs.
- The duplicate scan (`.ai-interaction/dupscan.py`) is the assistant's tool,
  not a gate; the gate is the reviewer reading a new technology against this
  record. If the scan finds a second wave, it becomes a test.
- A shared module changes for every technology at once. That is the point,
  and it is why the change lands capability first, technologies after — the
  order `xgit` already keeps.

## Provenance

The rule is the assistant's drafting of the owner's instruction of 2026-09-09
to consolidate, on the direction repository-model.md section 4 already fixed.
The socket.rs move of 2026-09-08 is its first instance, recorded here after
the fact.
