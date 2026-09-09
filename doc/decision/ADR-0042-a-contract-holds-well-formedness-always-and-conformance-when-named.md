# ADR-0042: A contract holds well-formedness always, and conformance when it is named

- Status: Accepted
- Date: 2026-09-07
- Related: ADR-0010 (contract and transport repository boundaries), ADR-0016
  (submodule composition, amended 2026-09-07), ADR-0011 (naming), ADR-0028 (the
  Playground), doc/development/creating-transports-contracts-and-processes.md

## In brief

- Theme: Modules and the boundary
- Subject: What a contract technology claims, where its versions live, and
  who may author one
- Name: A contract holds well-formedness always and conformance when named
- Order: 5
- Concepts: Well-formedness; conformance; a bound schema; a contract version;
  contract languages

**Every contract technology makes two claims. Well-formedness is a given: a
Stream that reaches the contract is checked for being what it says it is — JSON
that parses, XML that is well-formed, a sound EDIFACT interchange, text — every
time, with no configuration. Conformance is also a given once the contract is
named: a Receive or Send Location that refers to a contract with a schema,
pattern, layout, rules or message type bound has every Stream validated against
it, and each departure is reported with where it happened and what refused it.
Versions of a contract language live together in that technology's repository.
A contract may be authored in any of the estate's declared languages; there is
no JavaScript.**

## Context

By 2026-09-07 the contract capability held one technology, `csv`, against
twenty-three declared, and the Playground carried its own JSON and XML checks
waiting for the estate's to land. Building the rest raised three questions the
manifest did not answer, and the owner answered each the same day.

The declared names — `json-schema`, `xml-schema`, `wsdl`, `openapi` — name
schema languages, while what existed checked well-formedness. ADR-0010 puts
well-formedness on the representation axis and conformance on the contract
axis, yet `csv` had landed under contract as exactly a well-formedness check.
The assistant asked which claim a contract technology makes.

The XML Schema language has a 1.0 and a 1.1; JSON Schema has drafts; EDIFACT
has a directory per release, D96A, D01B and the rest. The assistant proposed a
repository per version. The manifest also declares contract technologies named
for programming languages — `c`, `cpp`, `dotnet`, `go`, `java`, `python`,
`rust` — beside the format ones, and their standing was unclear.

## Decision

### 1. Two claims, both always

A contract technology validates in two layers, and a Location gets both:

- **Well-formedness is a given.** The Stream is what its representation says:
  JSON that parses, XML that is well-formed, a sound ISO 9735 interchange, UTF-8
  text, CSV rows of one field count. Checked on every Stream, bound or not, and
  a failure names the line, column, byte or segment.
- **Conformance is a given once the contract is named.** When a Receive or Send
  Location refers to the contract with something bound — a JSON Schema, an XML
  Schema, a Schematron, a regular expression, a COBOL copybook, an EDIFACT
  message type — every Stream is held to it, and each departure is reported
  with the path where it happened and the keyword, rule, field or segment that
  refused it.

A bare contract is the first claim alone. The `ContractFactory` reads the
binding off the reference the Location names: empty is bare, anything else is
the schema file, the pattern, the copybook, the message type.

This does not move well-formedness off the representation axis of ADR-0010; it
says the contract axis checks it too, because a contract that assumes
well-formed input and receives bytes has nothing to say, and an operator wants
"not JSON at line 3" from the same place as "qty below minimum".

### 2. Versions live with the technology

Every version of a contract language lives in that technology's repository:
XSD 1.0 and 1.1 in `xmip-core-contract-xml-schema`, every JSON Schema dialect
in `-json-schema`, every EDIFACT directory in `-edi-edifact`. A version is not a
repository. The owner corrected the assistant's proposal of a repository per
version on 2026-09-07.

### 3. A contract in any declared language, and no JavaScript

The language entries under `xmip.core.contract` — `c`, `cpp`, `dotnet`, `go`,
`java`, `python`, `rust` — stand. Each is the way to author a contract as a
module in that language over the ABI (ADR-0012), the counterpart of the format
technologies. JavaScript is absent by decision, not omission.

## Consequences

- Nine contract technologies exist after this record, each its own repository
  mounted directly under `xmip-core-contract` (ADR-0016 as amended): `csv`,
  `json-schema`, `xml-schema`, `regex`, `schematron`, `fixed-width` over COBOL
  copybooks, `edi-edifact`, and the `dotnet` template. Each documents the subset
  of its schema language it reads and refuses the rest by name at bind time, so
  an operator learns at configuration, not from a Stream that passed.
- The Playground validates JSON and XML through the estate's own technologies
  and exercises every contract technology over every transport (ADR-0028); its
  stand-in checks are gone.
- `json-schema` asserts `pattern` and `format`, which it could not before the
  regex technology existed; the two lean on the same engine.
- A contract technology that cannot yet check conformance for a bound schema
  says so at bind time rather than passing silently. `edi-edifact` holds a
  message type today and its directories' segment tables are the next layer in
  the same repository.
- Still declared and unbuilt: `edi-x12`, `hl7-v2`, `fhir`, `wsdl`, `openapi`,
  `asyncapi`, `avro`, `protobuf`, `graphql-schema`, `sql`, and the seven
  language entries. The owner's next set, stated 2026-09-07: the medical
  contracts over MLLP and HTTPS, then the industrial contracts and protocols.

## Provenance

The three rulings are the owner's, 2026-09-07: *well-formedness is a given in
any case; conforming to a specific contract is also given if the contract is
named, referred to by a Receive or Send Location, the message shall be
validated*; *different versions of xml-schema can be kept in the same
repository for all xml-schema versions and so on*; *contracts can be formed by
other languages than dotnet, you have the list, Python, Java and what not, just
not JavaScript*. The two-claim wording, the bind-time refusal and the
consequences are the assistant's drafting of them.
