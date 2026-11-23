# ADR-0042: A contract holds well-formedness always, and conformance when it is named

- Status: Accepted
- Date: 2026-09-07
- Related: ADR-0010 (contract and transport repository boundaries), ADR-0016
  (submodule composition, amended 2026-09-07), ADR-0011 (naming), ADR-0028 (the
  System Tests), doc/development/creating-transports-contracts-and-processes.md,
  ADR-0018 (amendment 2026-10-05: no other runtime in an Xmip process unless
  invited)

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
A contract is authored in Rust or .NET; no other runtime is hosted in an Xmip
process unless configuration invites it (amendment 2026-10-05).**

## Context

By 2026-09-07 the contract capability held one technology, `csv`, against
twenty-three declared, and the System Tests carried their own JSON and XML checks
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

### 3. A contract of one's own is an external module

The technologies under `xmip.core.contract` are formats; none is a language.
A contract of one's own is an external module behind the C ABI (ADR-0012),
compiled by its author (the amendment of 2026-11-05).

## Consequences

- Nine contract technologies exist after this record, each its own repository
  mounted directly under `xmip-core-contract` (ADR-0016 as amended): `csv`,
  `json-schema`, `xml-schema`, `regex`, `schematron`, `fixed-width` over COBOL
  copybooks, `edi-edifact`, and the `dotnet` template. Each documents the subset
  of its schema language it reads and refuses the rest by name at bind time, so
  an operator learns at configuration, not from a Stream that passed.
- The System Tests validate JSON and XML through the estate's own technologies
  and exercises every contract technology over every transport (ADR-0028); its
  stand-in checks are gone.
- `json-schema` asserts `pattern` and `format`, which it could not before the
  regex technology existed; the two lean on the same engine.
- A contract technology that cannot yet check conformance for a bound schema
  says so at bind time rather than passing silently. `edi-edifact` holds a
  message type today and its directories' segment tables are the next layer in
  the same repository.
- Still declared and unbuilt: `edi-x12`, `hl7-v2`, `fhir`, `wsdl`, `openapi`,
  `asyncapi`, `avro`, `protobuf`, `graphql-schema`, `sql`, and the two
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

## Amendment, 2026-10-05: no other runtime in the Xmip Host Process

The owner, 2026-10-05, ruled on runtimes inside Xmip's own processes
(ADR-0018, amendment 2026-10-05): *Read it as InProcess with threads is
default true, any other runtime has to be opt in by configuration*; *I said
that dotnet runtime was invited unless excluded*; and *I do not want other
runtimes to interfere with potential perfect Rust code.*

A contract module is loaded into the Xmip Host Process, so decision 3 follows
that ruling:

- Rust runs on threads within the Xmip Host Process, and .NET is invited
  unless excluded: `xmip-core-contract-rust` and `xmip-core-contract-dotnet`
  stay.
- The C, C++, Go, Java and Python contract technologies hosted a JVM, a Go
  runtime, a CPython interpreter or unchecked native code inside that
  process: the JVM through JNI and CPython through a C shim, Go through
  cgo, C and C++ as native code with no Rust checks. They are gone, with
  their repositories' mounts under `xmip-core-contract`, their
  `architecture.toml` entries, the probe that drove them, xgit's `verify.ps1`
  gate that existed only for them, and the Go toolchain in
  `prerequisite.toml`.
- The reserved transform and process entries in C, C++, Go, Java, Lua,
  PowerShell and Python went with them for the same reason; the .NET ones
  stay.
- A program in another language at the perimeter, calling Xmip from outside
  in its own process, needs no invitation; ADR-0065's Event bindings are
  such programs and stay.

The owner's 2026-09-07 ruling, *contracts can be formed by other languages
than dotnet*, is superseded for contracts loaded in process.

## Amendment, 2026-11-05: an external module handles its own compilation

The owner, 2026-11-05: *The core, the runtime shall be Rust. Rust can call or
be called up on by other languages in their compiled form. No JavaScript*, and
*The external modules, assemblies handles their own compilation, not up to
Xmip.*

- Xmip defines the C ABI (ADR-0012) and loads what is behind it; it neither
  compiles an external module nor lists its language. Decision 3 says so.
- The language entries are gone: `xmip-core-contract-dotnet`, with its
  repository, and the reserved `transform` entries `dotnet`, `rust` and
  `wasm`. A language is how a module was built, not a technology of a
  capability.
- `xmip-core-contract-rust` was an external module the runtime's loader is
  tested against (ADR-0057), not a slot for a language: it is
  `xmip-core-test-module` at `test/core/module`, beside the System Tests.
- Which runtimes may enter an Xmip process stays as the amendment of
  2026-10-05 and ADR-0018 say.

## Amendment, 2026-11-19: a JSON Schema that never ends is refused at bind, and a check is bounded

An outside review found, and the source confirmed, that `json-schema` held a
Stream to a bound schema by recursion with nothing to stop it. Its compiler
read each schema object once, so a schema referring to itself compiled, and
holding a Stream to it recursed until the thread's stack was gone: a stack
overflow is no Stream's failure, it ends the whole Xmip Host Process.
`{"$ref": "#"}` did it, so did two schemas referring to each other and a
`$ref` back to the root from under `allOf`, `anyOf`, `oneOf` or `not`; and
a schema whose forty levels each held the place to the next level twice
walked 2^40 schemas for one Stream. `toon` holds its documents to the same
compiled schema and carried the same defect.

What stands now, in `module/core/capability/contract/json-schema`:

- **Refused at bind.** `$ref`, `allOf`, `anyOf`, `oneOf` and `not` hold the
  same place in the instance to another schema. When a schema is bound,
  those edges are ordered by Kahn's algorithm, without recursion: a cycle
  among them is refused, the refusal naming the `$ref` that closes it (one
  does, as only a `$ref` reaches a schema outside the one naming it), and so
  is a chain of more than 512 schemas at one place. The compiler works from
  a worklist, so a long schema is read in the stack a short one is. This is
  the bind-time refusal the Consequences ask of every technology.
- **Bounded when held.** A check goes at most 512 schemas deep, and at most
  the schema's size, its compiled schema objects, times the Stream's bytes
  plus one steps, a step for each schema a place is held to. Past either it
  stops with one issue coded `bound`, where it stopped, after the issues
  found so far. `Schema::check` takes the bytes the instance was read from,
  and the `json-schema` and `toon` contracts pass them. The 512 is not
  `codec::depth`'s 64: that counts the levels a reader parses from bytes,
  this the schemas a walk holds at once over a document already parsed, two
  or more a level. A check at its depth bound took between 256 and 512 KiB
  of stack built optimized, and between 1 and 1.25 MiB unoptimized, within
  the 2 MiB Rust gives a thread; the tests bind and hold on such a thread.
- **Cost.** A comparison and a count for each schema object held to. The
  module's timing program, one conforming order held to its schema ten
  thousand times, alone, is unchanged under its bound of 500 µs.

Evidence, 2026-11-19, on the owner's Windows computer. The six tests, run
one at a time against the committed sources (`cargo test --lib -- --exact
tests::<name>`, in a copy of the crate under the working area with only the
tests added):

```text
a_schema_referring_to_itself_without_descending_is_refused_at_bind
  thread 'bound-and-held' (56872) has overflowed its stack
  (exit code: 0xc00000fd, STATUS_STACK_OVERFLOW)
mutual_references_without_descending_are_refused
  thread 'bound-and-held' (23804) has overflowed its stack
a_cycle_through_allOf_anyOf_oneOf_or_not_is_refused
  thread 'bound-and-held' (57228) has overflowed its stack
a_chain_of_1000_references_is_refused_at_bind_without_overflow
  thread 'bound-and-held' (56376) has overflowed its stack
a_recursive_tree_that_descends_holds_100_levels_and_names_a_departure_at_depth
  assertion `left == right` failed: []  left: []  right: ["bound"]
a_schema_reevaluating_exponentially_stops_at_its_bound
  bound and held within the deadline: Timeout
  test result: FAILED. 0 passed; 1 failed; ... finished in 10.02s
```

After the change, `cargo test` in the crate, then with `--config
profile.dev.opt-level=0`, and in `toon`; then both crates in the AlmaLinux 10
guest:

```text
test result: ok. 22 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.16s
test result: ok. 22 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.61s
test result: ok. 11 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.06s
Linux: test result: ok. 22 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.04s
Linux: test result: ok. 11 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.05s
```

The timing program, `cargo test --test measured -- --test-threads=1
--nocapture`, before and after, and after in the guest:

```text
before: a conforming order validated: the fastest of five 3µs; median 3.4µs, p99 10.6µs
after:  a conforming order validated: the fastest of five 3.1µs; median 3.4µs, p99 7.3µs
Linux:  a conforming order validated: the fastest of five 2.9µs; median 3.3µs, p99 9.5µs
```
