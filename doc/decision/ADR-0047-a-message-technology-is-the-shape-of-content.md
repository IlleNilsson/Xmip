# ADR-0047: A message technology is the shape of content

- Status: Accepted
- Date: 2026-09-10
- Related: ADR-0013 (the journey model, sections), ADR-0031 (configuration
  is TOML, JSON is transport), ADR-0042 (a contract holds well-formedness
  always and conformance when named), ADR-0043 (Logic is the method),
  ADR-0044 (a technology shares through its capability),
  doc/planning/open-problems.md problem 10

## In brief

- Theme: Modules and the boundary
- Subject: What the message technologies are, why TOML and YAML are not
  among them, and the trait they implement
- Name: A message technology is the shape of content
- Order: 8
- Concepts: Shape; part; message type; message technology; configuration
  format

**A transport delivers bytes. Before any contract validates them or any path
selects inside them, a shape says what they are: one JSON document, a
multipart body of parts, an EDI interchange of segments, a CSV of rows, or
bytes that are only bytes. A message technology is one shape. It turns a
Stream into the parts that become a Message's Sections and names the message
type the content announces, when it announces one. TOML and YAML are not
messages: they are configuration formats, and what the estate needs of them
is a contract, so they leave `message` and join `contract`.**

## Context

The manifest declared seventeen technologies under `message`, the Foundation
module, with no description, maturity or trait. Contract technologies already
validate most of the same formats and path technologies select inside them,
so the question was what job was left. The owner answered two things on
2026-09-10: TOML and YAML *do not belong as messages, they are configuration
file formats*, and *the contract has to be implemented but not as message*.
The reading of the other fifteen — the shape of received content — was put to
him and stood.

Other records already leaned on the shape without naming it: `as2` depends on
`xmip-core-message-multipart`, `soap` on `xmip-core-message-xml`. Those are
the shapes those protocols read their bodies through.

## Decision

### 1. The sentence

The one in brief. A shape does not validate — that is a contract's, and a
malformed document is a shape error only because nothing can be sectioned
from it. A shape does not select — that is a path's. A shape sections and
names.

### 2. The trait

`Shape` has four methods, and every technology implements all four:

- `technology()` — the manifest leaf.
- `media_types()` — the media types this shape claims, so that a transport
  that says `application/json` is believed.
- `recognizes(bytes)` — whether the bytes look like this shape, asked only
  when no media type says. `binary` says yes to everything and is asked last.
- `shape(&Stream)` — the parts and the announced type. A part has a name in
  the shape's own terms (a multipart name, a segment tag, a row number), its
  bytes and its media type. Ids are the runtime's to mint, so a shape hands
  back parts and the runtime makes Sections of them.

`choose(shapes, &Stream)` in the Foundation picks the shape: the one that
claims the media type, else the first in order that recognizes the bytes.

### 3. Fifteen technologies, each its own repository

`avro`, `binary`, `csv`, `edi-edifact`, `edi-tradacoms`, `edi-x12`,
`fixed-width`, `form-urlencoded`, `hl7-er7`, `json`, `multipart`, `protobuf`,
`text`, `ubl` and `xml`, mounted directly under `xmip-core-message`. `ubl`
is an XML vocabulary and depends on `xml`. Framing the formats share — the
EDI segment walk, the delimited record — goes up into the capability
(ADR-0044).

### 4. TOML and YAML are contracts

`xmip.core.message.toml` and `xmip.core.message.yaml` leave the manifest.
`xmip.core.contract.toml` and `xmip.core.contract.yaml` join it, on the terms
of ADR-0042: well-formed always, conformant to a named layout when one is
named. A node configuration is TOML (ADR-0031); the contract is how a TOML
document is checked for shape before `xmip-core-configure` reads it.

## Consequences

- `xmip-core-message` gains the trait and the choice; it still depends on
  nothing new.
- Two names leave `message`, two join `contract`; the manifest keeps its
  count of declared technologies.
- Problem 10's rule is honored: the trait landed before any repository.

## Provenance

The owner's two rulings of 2026-09-10 are quoted in Context. The shape
reading, the trait and the sentence are the assistant's, put to the owner
and not contradicted. The instruction to build is the owner's: *sort it all.*
