# ADR-0061: A provider builds against the capabilities; the SDK simulates

- Status: Accepted
- Accepted: 2026-09-24, the owner, answering each question below as asked
- Date: 2026-09-24
- Amended: 2026-09-24, later — the SDK holds simulators, emulators and the
  test ACME server only; every trait stays in its capability
- Related: ADR-0012 (the module boundary and the C ABI), ADR-0016 (submodule
  composition: what starts Xmip mounts without a provider), ADR-0021 (latest
  everywhere until the first release), ADR-0023 (AGPL-3.0-or-later, and no
  second license), ADR-0044 (a technology shares through its capability),
  ADR-0057 (a vtable is a promise, only a loader is a saving), ADR-0059 (a test
  suite carries its provider), doc/planning/open-problems.md problem 26

## In brief

- Theme: Modules and the boundary
- Subject: What a provider other than core builds against, where its license
  ends, where it declares what it ships, and what the SDK is
- Name: A provider builds against the capabilities; the SDK simulates
- Order: 11
- Concepts: SDK; provider; license boundary; simulator

**A provider builds against the capability its module belongs to — a
contract against `xmip-core-contract`, a transport against
`xmip-core-transport` — as core's own technologies do: every trait and
interface lives in the repository it belongs to. A Rust contract becomes a
library a node loads through the C ABI by one line, the contract capability's
`export_contract!`. A module loaded through the ABI is a separate work under
any license; a module linked into Xmip is AGPL-3.0-or-later. A provider
declares its modules in core's `architecture.toml`. The SDK, `xmip-core-sdk`
at the estate root, `sdk/`, holds only what a module is tested on:
simulators, emulators and, for now, the local ACME server.**

*As first decided the same day, the SDK held the traits and the export; the
owner then ruled that it holds simulators only. Decisions 1, 2, 4, 8 and 10
below record the first ruling and are superseded by the amendment at the
end; 3, 6, 7 and 9 stand.*

## Context

The owner, 2026-09-24: *put yourself in a provider's position — would you be
pleased with the documentation, tools and opportunities?* The answer was no,
and the reasons were checked in the estate that day (open-problems.md,
problem 26):

- Every crate is `publish = false` and every dependency `branch = "main"`.
  A provider had nothing stable to build against: its build broke whenever
  core moved, with no version to hold core to.
- The traits a provider implements live in the capability crates, among the
  code capabilities share with their own technologies, and change with it.
- CONTRIBUTING said *the boundary is the trait* and that an extension may carry
  any license. A Rust technology links the AGPL trait crates into itself, so
  the sentence promised what the license does not obviously give.
- Only contracts could be loaded through the ABI, and nothing loaded them.

The owner then said: *So fix it*, and answered each question below.

## Decision

**1. One crate, `xmip-core-sdk`, is what a provider builds against.** It holds
every trait a provider implements — a transport, a contract, a message shape,
a path, a guard, an archive store, an identity gate and the rest — and the one
export that wraps a Rust implementation of a trait in the table the C header
declares for it. It is a new repository (the owner, 2026-09-24).

**2. Core's capabilities depend on it too.** The trait moves out of the
capability crate into the SDK; the capability keeps what its technologies
share (ADR-0044). There is one definition of each trait, and core implements
the same one a provider does. Nothing re-exports a trait under an old path.

**3. It mounts at the estate root, `sdk/`**, beside `module/`, `test/` and
`template/`, with no provider in the path: a node cannot load a module
without the traits and the tables, so it is needed to start Xmip (ADR-0016,
amended 2026-09-23 and corrected 2026-09-24). It was first mounted at
`module/foundation/sdk`; the owner, the same day: *that is not the place for
the SDK, it should be mounted at the root.* It is what a provider reads first,
so it stands where a provider opens the estate. Its manifest entry declares
`mount = "sdk"`.

**4. It depends on `xmip-core-abi`, which stays the C boundary.** `abi` keeps
the header, the Rust mirror of the tables and the .NET binding; the SDK adds
the traits and the export over them. Nothing is duplicated between the two.

**5. A provider takes the SDK by a versioned git tag**, `sdk-v<major>.<minor>.<patch>`
on the repository's own GitHub. Nothing is published to a registry. The
version follows the traits and the tables: a change a built module would not
survive is a new major. ADR-0021's latest-everywhere stays the rule for core's
own crates, which keep `branch = "main"`; the SDK is the one crate a party
outside the estate pins, so it is the one that is versioned.

**6. The ABI is the license boundary.** A module loaded through the C ABI —
built against the SDK's export, shipped as its own library, opened by a node
at run time — is a separate work, and its provider may license it as they
choose. A module linked into Xmip at build time is part of Xmip and is
AGPL-3.0-or-later, as ADR-0023 says. No license text changes. CONTRIBUTING's
*the boundary is the trait* becomes *the boundary is the ABI*.

**7. A provider declares its modules in core's `architecture.toml`**, under its
own provider — `[xmip.<provider>.…]` — through a change to this repository, as
core's are. The mount follows ADR-0016: `module/<provider>/<domain>/<leaf>`,
and a Playground at `test/<provider>/playground`.

**8. The SDK may hold `unsafe`, confined to its export modules** (the owner,
2026-09-24). The export stands on the far side of the C boundary and must know
the trait, so it can live nowhere else. The SDK forbids `unsafe` everywhere
but there; each block carries a `SAFETY` comment, and tests drive the table as
a host would. A provider's own crate stays `forbid(unsafe_code)`: implementing
the trait and naming it in the export is all it writes.

**9. Simulators belong in the SDK** (the owner, 2026-09-24: *since we now have
an SDK, emulators/simulators belong in the SDK*). A shared medium a module is
tested on — the serial multi-drop bus, the CAN bus, the air a radio protocol
uses — is what a provider needs as much as the trait: a provider's M-Bus
meter or HART device is proved on the same bus core's is. So the simulators
move into the SDK beside the traits they are written in, and are selectable
by an end user as well as used by tests. A technology's own far end, its
`Loopback` (ADR-0051), stays with the technology: it is that protocol's, not a
medium's.

**10. The SDK depends on the libraries a transport's failures convert from**
(the owner, 2026-09-24). The transport error moved into the SDK with the
trait, and Rust allows a conversion only beside one of its two types, so the
SDK takes `xmip-core-library-codec` and `xmip-core-library-asn1`, and
`xmip-core-library-tls` behind its own `tls` feature, and keeps the
conversions beside the error. No call site changes, and a provider gets small
pure-Rust libraries with the SDK. The alternatives — the libraries converting
into the SDK's error, or every call site converting by hand — were put to him
and declined.

## Consequences

*Of the first ruling; the amendment at the end says what changed.*

- A provider has one crate, one tag and one license rule to read.
- Every technology in the estate changes the path it imports its trait from,
  in the change that moves that trait: no alias, no re-export (the owner,
  2026-09-22, on shims).
- A node must load every table, not only the contract's, before a provider's
  module is usable; that is phase C of open-problems.md's suggested order, and
  problem 26 holds the list.
- The SDK's version is a promise the estate did not make before. A test holds
  the tag to the traits it describes.

## Alternatives considered

The owner was asked each question with the alternatives beside it:

- **Version each capability's trait crate instead of one SDK.** Many things to
  keep stable instead of one, and each still mixed with its capability's
  shared code.
- **Publish to crates.io.** The Rust norm, but outward-facing and hard to take
  back; a git tag gives a provider the same pin without it.
- **A linking exception in the license, or no ruling at all.** The first
  changes license text ADR-0023 keeps single; the second leaves every
  provider's counsel to guess.
- **A provider's own manifest, read beside core's.** Declined: a provider's
  modules are declared in core's manifest, where every module is.
- **The SDK under `module/core/library/`, at `module/foundation/sdk`, or
  absorbing `abi`'s Rust side.** Declined for decisions 3 and 4.

## Amendment, 2026-09-24 (later): the SDK simulates; traits stay home

The owner, asked what the SDK now held — the contract trait and its export,
the transport trait on its way in — and shown where they fought: *The SDK shall
only contain simulator/emulators, local ACME server for now*, and
*Traits/Interfaces goes to the repos, modules where they belong.*

1. **Decisions 1 and 2 are superseded.** Each trait lives in its capability:
   the contract trait and its types in `xmip-core-contract`, as before the
   morning; the transport trait never left `xmip-core-transport` (its move was
   undone before it landed). A provider builds against the capability, as core
   does, and there is still one definition of each trait.
2. **Decision 4 is superseded.** The SDK does not depend on `abi`; the export
   over the ABI is the contract capability's, `contract::export_contract!`, and
   it depends on `abi`.
3. **Decision 8 moves with the export.** The contract capability denies
   `unsafe` everywhere but its `export` module, where each block carries a
   `SAFETY` comment and tests drive the table as a host would. A provider's
   crate still forbids `unsafe`, and `xmip-core-contract-rust` still shows it.
4. **Decision 10 lapses**: the transport error stayed in the capability, and so
   did its conversions.
5. **Decision 9 is the SDK's whole content**: the simulated media — the serial
   multi-drop bus first, moved from the serial technology — and the local ACME
   server the `identity-local` test uses (ADR-0034, amendment 2026-09-24). The
   SDK depends on the transport capability, whose `Line` a simulated bus is.
6. **Decisions 3, 6 and 7 stand**: the SDK mounts at the root, the ABI is the
   license boundary, and a provider declares its modules in core's manifest.
7. **Decision 5 is open**: whether a simulator crate is taken at a versioned
   tag was decided for an SDK of traits, and is the owner's to rule on again.
