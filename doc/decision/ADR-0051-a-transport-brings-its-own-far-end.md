# ADR-0051: A transport brings its own far end

- Status: Accepted
- Date: 2026-09-11
- Related: ADR-0028 (the Playground: clause 5, the far end is Xmip; the
  amendment of 2026-09-09, every transport declares its ceiling), ADR-0044
  (a technology shares through its capability), ADR-0010 (one protocol,
  both directions)

## In brief

- Theme: Operating Xmip
- Subject: Where the dance that makes a transport its own counterparty is
  written, and who drives it
- Name: A transport brings its own far end
- Order: 9
- Concepts: Loopback; far end; near end; the one adapter

**A transport that can be both ends of one exchange on this machine says so
in its own crate, by implementing the capability's `Loopback` trait: stand
up the far end, say where it listens, send from a fresh near end, take the
one arrival, and declare the ceiling and the refusals that are facts about
the protocol. The Playground drives every transport through one adapter over
that trait and writes no dance of its own. A new transport is a `loopback()`
constructor in its crate and one line in the Playground's list.**

## Context

ADR-0028 clause 5 made Xmip its own far end: wherever a transport ships both
a server's worth of protocol and a client, the Playground uses them as the
counterparty and stands up nothing external. What that takes is one dance
per protocol — bind, learn the address, send on one thread while the far end
accepts on another, poke a listener whose sender failed so the round is
judged rather than waited on. By 2026-09-11 that dance was written in the
Playground forty-two times, once per transport, in thirteen files, around
the very session and client each technology already ships for its own tests;
the technology's tests did the same dance a forty-third time. Thirty-six more
transports landed on 2026-09-11 with no adapter at all, and the Playground
went on exercising forty-two of eighty-four.

The ceiling and the refusals sat in the adapters too — one datagram's 65 507
bytes in the Playground's `roundtrip.rs`, the SNMP and DHCP ceilings in its
`management.rs` — although the amendment of 2026-09-09 says a ceiling is a
fact about the protocol, written where it comes from.

The owner asked on 2026-09-11 to consolidate, refactor and re-engineer where
needed. This is the re-engineering.

## Decision

### 1. `Loopback` is the capability's

`xmip-core-transport` gains `loopback.rs`: the `Loopback` trait and the
`FarEnd` it stands up. A technology implements `Loopback` on its transport
type and hands out a configured instance from a `loopback()` constructor —
an ephemeral local port, the capability's `LOOPBACK_TIMEOUT` — the way it
already hands out `new`. The trait has a provided `round`: the two-thread
dance with the poke, written once. A protocol whose two ends do not need two
threads — a directory, an in-process bus — overrides `round` and goes in
order.

Shared code goes up, never sideways (ADR-0044): the dance is code every
transport needs, so it lives in the crate every transport depends on.

### 2. The ceiling and the refusals move with it

`Loopback::ceiling` and `Loopback::refuses` are answered by the technology.
The number for a datagram is in the udp crate; the number for an SNMP
message is in the snmp crate. The Playground reads them; it no longer holds
them.

### 3. The Playground has one adapter

`Looped<L: Loopback>` implements the Playground's `RoundTrip` over any
loopback, and `all_transports` lists loopbacks. The `RoundTrip` trait stays:
it is the scenarios' view, and a transport the Playground cannot yet drive
both ends of is still answered one-sided through it. The per-transport
adapter files go as each transport moves; `listen_exchange` goes with the
last of them.

### 4. The technology's tests drive the same round

A technology's own round-trip test calls `loopback().round(payload)` rather
than writing the dance a third time. What the test asserts beyond the round
— the origin URI, the peer, a protocol's acknowledgment — stays the test's.

### 5. Applied in waves

file, tcp, udp and http move with this record. The remaining thirty-eight
adapters move, and the thirty-six transports of 2026-09-11 gain their
loopbacks, in waves of agents each inside its crates, the way the
technologies were built; the Playground's list grows to eighty-four as they
land. A transport with only one side keeps answering one-sided until it has
both.

## Consequences

- The Playground's adapter code — some two and a half thousand lines across
  thirteen files — leaves it, and the Playground's Cargo manifest still names
  every transport, because a loopback is a dependency.
- A technology's crate is the one place its protocol dance, ceiling and
  refusals are written; its tests and the Playground read the same one.
- Wiring a new transport into the Playground is a constructor and a line, so
  an assistant building a technology wires it in the same change.
- ADR-0028 clause 5 and its ceiling amendment are amended to point here.

## Alternatives considered

**Keep the adapters in the Playground and write thirty-six more.** Rejected:
it is the duplication ADR-0044 exists to stop, at the estate's largest
multiplier.

**Grow the `Transport` trait until it can round-trip.** Rejected: `Transport`
is one protocol both directions for the runtime (ADR-0010) and mirrors the C
ABI's vtable; a listen-and-accept far end is a test concern and does not
belong on the runtime's contract.

**A `loopback` feature flag per crate.** Not needed: a loopback is a few
dozen lines over what the crate already ships for its tests, and a runtime
that never calls it pays nothing.

## Provenance

The re-engineering was asked for by the owner on 2026-09-11 — *let's go bold
and consolidate, refactor and re-engineer if needed* — after the Playground
rolled over forty-two of eighty-four transports. The trait, its home and the
waves are the assistant's drafting.
