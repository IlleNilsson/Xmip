# ADR-0065: Events are subscribed from any language, in process and over the wire, from one model

- Status: Accepted
- Accepted: 2026-09-26, the owner, from the options named below
- Date: 2026-09-26
- Related: ADR-0012 (the module boundary is a C ABI), ADR-0019 (Parties and
  identity), ADR-0027 (the operator boundary, `xmip_operate.h`), ADR-0052
  (code placed once), ADR-0062 (every tool audits), ADR-0063 (Xmip's own
  TLS), `doc/architecture/runtime-model.md` section 17 (Eventing),
  `doc/architecture/observability-model.md`

## In brief

- Theme: What Xmip is at runtime
- Subject: How a program in another language learns what Xmip did
- Name: Events are subscribed from any language
- Order: 15
- Concepts: Event; subscription; the Event wire form; language binding

**One Event model and one subscription rule, in Rust, in `xmip-core-event`.
A program subscribes two ways, both through that one rule: in process,
through a subscribe call in the runtime's C library — C and C++ through the
header, .NET through `Xmip.Abi`, Java through its foreign-function API,
Python through ctypes, and any language that can call C — or over the wire,
in the Event wire form delivered through Xmip's own transports, which any language's
ordinary client receives. Every subscriber is a Party, authorized for what it
may see, and every delivery is audited.**

## Context

The owner, 2026-09-26: *observe and event need some love. Events have to be
subscribable from several languages, like dotnet, java, c, cpp and more.*
`xmip-core-event` was a type and a `publish` trait in 57 lines, with no
subscription and no delivery; `runtime-model.md` section 17 already required
an Event for every Receive, Xmip Process and Send outcome, and receivers
identified, authorized and audited.

## Decision

### 1. Both ways, one model

The owner, from three (both from one model, the C ABI only, the network
only): **both, one model.** A subscription names the Events it wants — by
type, outcome, scope, Party — and the rule that decides whether an Event
matches, and whether this subscriber may see it, is written once in
`xmip-core-event`.

### 2. In process: the C ABI

`xmip_operate.h` gains a subscription: subscribe with a filter, receive
Events (a bounded queue the subscriber drains, or a callback it registers),
unsubscribe. The runtime forwards to `xmip-core-event`, as it forwards every
rule (ADR-0052). Each language binds it once: C and C++ include the header;
.NET's binding is `Xmip.Abi`; Java's is a small package over the
foreign-function and memory API; Python's over ctypes; others as they are
asked for. No binding decides what an Event means.

### 3. Over the wire: the Event wire form on Xmip's transports

An Event leaves Xmip in its wire form, which follows CloudEvents 1.0 (the
CNCF specification, its JSON format and its HTTP, Kafka and AMQP bindings) so
that any language's ordinary client reads it; the standard is named here and
in the event crate's wire module only, and is otherwise hidden, sent by Xmip's own
transports (ADR-0063's rule: Xmip uses its own toolchain) — HTTP (a
webhook), Kafka, AMQP first. The subscriber is a Party with its identity on
the Send side, and delivery is at least once, retried by the resilience
guards.

### 4. Authorized and audited

Every subscriber, in process or remote, is a Party; authorization decides
which Event types, scopes and metadata it may receive (runtime-model section
17). Every delivery and every refusal is audited (ADR-0062).

## Consequences

- `xmip-core-event` grows the Event taxonomy section 17 names, the
  subscription and its matching, and delivery.
- `xmip_operate.h` grows an event section; `Xmip.Abi`, and new Java and
  Python bindings, bind it once each.
- The event capability gains technologies for the wire: the Event wire form over
  HTTP, Kafka and AMQP, each riding the transport of that name.

## Built, 2026-09-26

- **The model and the rule.** `xmip-core-event`: `Event` with the section 17
  taxonomy (`outcome::Outcome`, eight outcomes; `xcore::EventId`), references
  and never content; `filter::Filter::matches`, the one rule, its scope by
  `observe::Scope::contains`. Built by the assistant, 2026-09-26.
- **Authorized and audited (clause 4).** `subscriber::Subscriber` is a Party;
  the gate is `authorize::authorize`, asked once at subscribe as a Send at
  the scope reached, each type as the Contract; `SameProcess` admits a
  program in this process. Every subscription, delivery, refusal and forward
  is recorded through `ProgramAudit` on one keeping thread
  (`audit_queue.rs`), so no Event waits for a disk; unsubscribing settles it.
- **In process (clause 2).** `hub::Hub` fans out through a bounded queue per
  subscription and never waits for one; `next` wakes on arrival; `listen`
  calls back on its own thread. `xmip_operate.h` section 11 (ADR-0027,
  amendment 2026-09-26) forwards to `Hub::process` from the runtime's
  `src/ffi/event.rs`; bound once in `Xmip.Abi` (`RuntimeEvents`, and
  `Xmip.Surface`'s `EventFeed`), and beside it in `xmip-core-abi`: C (`c/`),
  C++ (`include/xmip_event.hpp`), Java 21 over the foreign function API with
  `--enable-preview` (`java/`), Python over ctypes (`python/`).
- **Over the wire (clause 3).** `wire::WireEvent` (the JSON format)
  and `binding::Binding` (HTTP, Kafka and AMQP, structured and binary) in
  the event crate; `forward::Forwarder`, at least once, in order, under the
  resilience guards; each of the http, kafka and amqp transports carries a
  `event_wire.rs` presenting the identity configured for the Party.
  The Event Grid transport uses the event crate's wire form. On AMQP 0-9-1 the standard's attributes ride the headers
  table, the equivalent of AMQP 1.0's application properties.
- **Near real time.** Measured on the owner's Windows machine, debug build:
  a publish costs about 1 µs to one subscription; publish to receipt is a
  median of about 40 µs in Rust, 70–100 µs through the C ABI, 0.2–0.3 ms in
  .NET, Java and Python, and 0.3–0.5 ms over loopback HTTP, Kafka and AMQP.
  Every test holds its median under a millisecond beside a plain thread wake
  measured under the same load.
- **Not yet.** The runtime does not publish its own action Events from the
  message path yet, so no operator surface subscribes (`Get-XmipEvent` and
  `xmip event` wait for it); a Forwarder is not yet run by a node from
  configuration.

## Amendment, 2026-09-26: a subscriber hears the cluster

Asked whether a program in a node's own process is admitted for being there,
the owner answered wider: *a program subscribing to events shall receive
events from the cluster, not just a node*, and then: *of course a subscriber
to events has to listen to something. But it is the cluster, not nodes.* A
subscriber listens to the cluster — the cluster's own address, in process
through the cluster's side of the runtime library, over the wire at the
cluster's endpoint — never to a node, and never names one. It receives the
Events of every node in the cluster that match its filter and that its Party
may see; which node answers it is the cluster's business. Two things
follow. Events cross between nodes, so they ride the node-to-node protocol
(problems 17 and 18), mutual TLS as ADR-0063 requires; and no subscriber is
admitted for its place — `SameProcess` goes, and every subscriber, in process
or remote, names its Party and is authorized as one (clause 4).

## Amendment, 2026-09-26: the wire form is hidden

The owner, 2026-09-26: *cloud is not a word we want within the Xmip world*,
and *just hide, encapsulate it. We are offline first.* The standard stays on
the wire (clause 3) and is encapsulated: everywhere Xmip speaks — code, help,
surfaces, records — it is the Event wire form. Delivery assumes no network
beyond the ones the cluster is configured with.

## Provenance

**The owner's**, 2026-09-26: the requirement quoted in Context and clause 1,
chosen from the three options named there.

**The assistant's**: clauses 2 to 4's means — the queue or callback shape,
the bindings named, the wire form's standard, at-least-once — each
the owner's to strike.
