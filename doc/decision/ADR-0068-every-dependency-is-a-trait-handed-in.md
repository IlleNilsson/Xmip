# ADR-0068: Every dependency is a trait, handed in

- Status: Accepted
- Accepted: 2026-10-05, the owner, in the words quoted below
- Date: 2026-10-05
- Related: ADR-0012 (the module boundary), ADR-0044 (a technology shares
  through its capability), ADR-0057 (a vtable is a promise, only a loader is
  a saving), ADR-0018 (amendment 2026-10-05: other runtimes run out of
  process), the dependency-injection audit of 2026-10-05

## In brief

- Theme: The shape of the estate
- Subject: How one part of Xmip reaches another
- Name: Every dependency is a trait, handed in
- Order: 18
- Concepts: Trait; interface; dependency injection; provider

**Every dependency between parts of Xmip goes through a trait in Rust or an
interface in .NET, and the implementation is handed to the part that uses
it — never constructed, looked up by name or found by path inside it. A part
depends on a capability's trait, not on the technologies that implement it,
and a provider's implementation enters through the same trait as Xmip's
own.**

## Context

The owner, 2026-10-05, while the estate was landing an external review's
fixes, two of which had come from parts reaching a concrete implementation
— the runtime's tests opening another module's library by a path into its
build output, and the runtime unable to ask a transport what it holds
because the `Transport` trait had no way to say it: *I'm not shure what you
are doing, but traits/interfaces via Dependeny Injection might be a god
thing*; and then: *I thing whe need trait/interface Dependency Injection
everywhere. It is a whay to loosen up the dependecncy tree and also let int
providers, previosly known as 3'rd party or acme.*

The estate already holds the rule at its main seams — `Transport` for every
transport, `Engine` behind Xmip Storage, `ContractFactory` for contracts,
the module ABI that loads a module through its table (ADR-0057) — and not
everywhere else.

## Decision

1. **A part depends on a trait or interface, never on a concrete
   implementation of another part.** In Rust, a consumer takes the
   capability's trait — a generic or a trait object — and its Cargo
   dependency is the capability crate, not a technology crate. In .NET, a
   consumer takes an interface through its constructor.
2. **The implementation is handed in.** Whoever composes — the runtime as it
   starts a node from its configuration (ADR-0018's phases), a .NET host's
   service registration, a test's fixture — chooses the implementation and
   passes it. A consumer never constructs one, never looks one up by a
   technology's or crate's name, and never finds one by a path into another
   module's build output. What composes may read configuration;
   what consumes may not choose.
3. **A trait says everything its consumers need.** Where a consumer would
   need a downcast or a side channel to reach a technology's own method, the
   method belongs on the trait, with a default for technologies it does not
   concern.
4. **Providers come in through the same traits.** A provider's
   implementation of a capability — what the estate earlier called a third
   party — is handed in exactly as Xmip's own are; nothing in a consumer
   tells them apart.
5. **Tests are composers.** A test hands the part under test the
   implementation it needs, a fake or a real one, through the same trait;
   it does not reach for one by path or environment variable.

## Consequences

- The dependency tree loosens: a change to one technology rebuilds and
  re-checks what composes it, not every consumer of its capability.
- The audit of 2026-10-05 lists where the estate breaks this rule; each
  finding is work, landed as the rule says, and none is kept as an
  exception.
- The module boundary (ADR-0012) and the vtable (ADR-0057) are the same rule
  across a language and a library boundary: a module is handed through its
  table.

## Provenance

The owner's words, quoted above; the clauses and their wording are the
assistant's, from the owner's rule. Not yet applied everywhere.

## Amendment, 2026-10-19: a policy set up from configuration, and TLS handed to a transport

Two seams added for open problem 33, each clause 2 as written. **A policy
the composer links is set up from what the node starts**: the program
hands the runtime a constructor (`Linked::receive_policies`, a
`fn(&[ReceiveGate]) -> Box<dyn Authorizer>`), and the runtime, composing,
calls it with the gates of the Receive Locations its configuration starts;
the runtime names no policy technology. **The TLS a node terminates its
receives with is handed to every transport once, as it is built**
(`transport::Configured::guarded_by`, after `on_node`): the composer reads
it from `[provision.receive]`, the transport keeps it where its Location's
settings ask for TLS, and no technology reads a certificate of its own.
The assistant's, 2026-10-19.

## Amendment, 2026-10-20: the policy is set up from every Location the node starts

`Linked::receive_policies` is renamed `Linked::location_policies`, a
`fn(Started<'_>) -> Box<dyn Authorizer>`: the runtime, composing, hands it
the gates of the Receive Locations and the Send Locations its
configuration starts (`linked::Started`), so the `location` policy admits
at each Send Location the node starts (the owner, 2026-10-19; ADR-0050,
amendment 2026-10-20). The old name is deleted with every use. The
handshake of the TLS handed to a transport is read under its own bound,
`[tuning] receive_handshake`, which the runtime gives the guard as it
builds it (`transport::Guard::handshaking_within`; ADR-0033, amendment
2026-10-20). The assistant's, 2026-10-20.
