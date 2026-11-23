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
because the `Transport` trait had no way to say it: *I'm not sure what you
are doing, but traits/interfaces via Dependency Injection might be a good
thing*; and then: *I think we need trait/interface Dependency Injection
everywhere. It is a way to loosen up the dependency tree and also let in
providers, previously known as third party or acme.*

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

## Amendment, 2026-11-14: one clock

**The wall clock is a trait, `xcore::Clock`, and `xcore::SystemClock` is
its one production implementation and the estate's one reading of the
operating system's clock** (`SystemTime::now()`, in
`module/foundation/core/src/clock.rs`; `test/Clock.Test.ps1` holds it).
A part whose behavior a test must pin over time — Xmip Storage, the
Ledger, a Message's path — is handed a Clock, as clause 2 says; a part
that only stamps a wire with the moment — a claimed file's name, a
signature's date, a file's write time, an archived item's moment, an AS4
or syslog timestamp — reads `SystemClock` where the moment is taken and
hands the moment down as a parameter, so its test pins the moment. A
Library reads no clock: `codec::civil` converts, and `CivilTime::from_unix`
takes the seconds a caller read. This covers the wall clock alone: no
reading of the monotonic clock, `Instant::now()`, was moved, and none is
held by the test. The assistant's, 2026-11-14.

## Amendment, 2026-11-15: the monotonic clock

**A decision counts its span on the monotonic reading of the Clock it was
handed; a wait the operating system makes, and a span only reported, read
std's `Instant`.** Three kinds, told apart by one question each:

1. **It branches on the reading, or a test would assert its value: the
   Clock** (`Clock::monotonic_nanos` of the Clock handed in, clause 2). The
   part keeps each moment as that reading, adds a span with
   `xcore::clock::nanos` and reads the span between two readings with
   `xcore::clock::between`; where it must wait for what is due, it waits
   real time through `xcore::wake` and reads the Clock again.
2. **The operating system waits on it: `Instant`**, through `xcore::wake`
   where it is a timed wait. A stepped clock cannot shorten a socket's
   read, a handshake or a thread's end; a test controls these by the span
   it configures (`[tuning]`, or the call's own bound).
3. **It is only reported as how long work took: `Instant`.** Neither a
   test's control nor a virtual call on a path that only measures is
   wanted there.

**One test clock, `xcore::clock::Stepped`**, under xcore's `test-support`
(never in a node): wall and monotonic readings a test steps, held in
atomics so a node's threads read it as the test steps it. A test hands it
in, steps it past the edge of the span under test, and sleeps for nothing.
It replaces the test clocks each test wrote for itself: xcore's own and Xmip
Storage's four (`fixture/crowd.rs`, `storage/columns.rs`,
`storage/embedded.rs`, `storage/monotonic_clock.rs`); the runtime's move
with its decisions. Xmip Storage's own span-to-nanoseconds rule,
`claim::lease_nanos`, is deleted for `xcore::clock::nanos`.

Moved onto the Clock on 2026-11-15: the circuit breaker's open period and
the rate limit's refill (`CircuitBreaker::new` and `RateLimit::new` take the
Clock), Xmip Storage's client passing over a Storage node that did not
answer (`StorageClient::with_clock`), and a standby syncing what it copied
(`StorageNode::with_clock`, whose client and whose primary, once promoted,
tell time by the same Clock). `StorageClient::new` and `StorageNode::new`
hand in `SystemClock`, as `Embedded::open` does.

Moved onto the Clock next, the same day:

- **`net`**, a Library, reads no clock (the amendment of 2026-11-14): its
  watched connection takes a reading closure beside its `ending`
  (`Watched::new(reading, ending, now)`, `heard` that reading), and an
  HTTP/2 connection takes one at its handshake (`net::http2::Now`;
  `Server::handshake`, `Client::handshake`, their `_within` and boxed
  forms, `serve`, `exchange`), which the frames a span allows are counted
  on. A caller handed a Clock hands on `xcore::clock::reading(&clock)`.
- **The cluster's sync plane**: `Joining` carries the node's Clock, which
  a member's silence is counted on; only the cluster and its tests build
  one.
- **The transports' turn deadline**: a transport is handed its node's
  Clock once, as it is built (`Configured::timed_by`, after `on_node`); a
  technology serving through `transport::serving::Serving` hands it to its
  serving wait (`Serving::timed_by`), whose every accepted connection
  counts its turn on it and lends it to the protocol on it
  (`Within::clock`: HTTP/2's frames). The http transport hands it to its
  receives (`Inbound::timed_by`) and to the connections it sends on
  (`Connections::timed_by`); every technology riding on HTTP that listens
  hands it on likewise. A connection no serving wait accepted,
  `http::server`'s one-request path, and the connections of a technology
  that only sends over `Connections` (the cloud stores and queues,
  WebDAV, Redpanda) count on `SystemClock`.
- **The runtime**: the node makes its one Clock as it starts and hands it
  to its message path, its Locations (`linked::OnNode`), its pickup
  (`Pickup::timed_by`: a queue read again after `AGAIN`), its work step
  (`WorkStep::timed_by`: a scan and a timer due) and its revocation
  list's hour, and a try's span is read on it (`Sends::again` takes the
  span the try took). A Stream's stall (`StreamShare::timed_by`), the
  operate plane's nonces (`Fresh::timed_by`) and its HTTP/2 connections,
  and a surface's line silence and nonces (`Shared::clock`) are counted
  on a Clock their part holds, `SystemClock` where nothing hands it one
  yet: the operate listener, a surface.
- **The send step**: `SendStep::new` takes the node's Clock, hands it to
  its `StreamShare`, and every decision of the step reads it — a claim's
  lease (`Departure::until`) and its renewal's round and answer, a
  retry's due time and a scan's (`schedule::due::Due`, whose moments are
  the Clock's readings), when a page of a queue was asked and what is
  due in it, which of a read of a queue and a settle came first
  (`send_step::settles`), and when a claim's renewal went unanswered,
  said on the same Clock's wall reading. Its watch on its queues reads
  the step's Clock for when each wait was asked and answered
  (`QueueWatch::run` takes it; the work step's too). A wait of the
  dispatching or of the renewer waits real time through `xcore::wake`,
  the span between two readings of the Clock; the spans a send's steps
  only report (`send_step::Steps`) read `Instant`. One decision is an
  order and no span, and reads no clock at all: whether a read of a queue
  began before or after a sequence's head moved is told by a count of the
  moves the step was told of, kept under its lock (`send_step::behind`;
  ADR-0018, amendment 2026-11-15).

`test/Clock.Test.ps1` holds each file moved at no `Instant` at all, and
counts every other production `Instant::now` reading but `SystemClock`'s
origin: 148 on 2026-11-15 before the last four moves, 121 after them, 97
once the send step's moved, a ceiling that may fall as decisions move and
may not rise. The assistant's, 2026-11-15.

## Amendment, 2026-11-16: what a node starts tells time by its Clock

**What the amendment of 2026-11-15 left on `SystemClock` takes the node's
Clock through the seam it already had — `Configured::timed_by` for a
technology, a parameter from `Running::start` for the runtime — and a part
that is no node's is handed the operating system's by whoever makes it.**
No second seam was added.

- **The technologies that only send over `Connections`** — aws-s3, azure-blob,
  google-cloud-storage, aws-sqs, aws-kinesis, azure-event-hubs,
  azure-service-bus, google-pub-sub, WebDAV, and Redpanda's Admin API
  (`Admin::timed_by`) — hand the Clock `Configured::timed_by` gives them to
  their connections. Each speaks HTTP/1.1 under its signature, which counts
  no frame, so none decides on it yet; an HTTP/2 connection would.
- **`http::server`'s one-request path** (`answer_on`, `serve_one`,
  `serve_one_from`, `accept_one`) counts an HTTP/2 caller's frames in a
  span on the Clock its caller hands it: a technology's far end the one
  its transport was timed by, read back from its connections
  (`Connections::clock`), the Prometheus scrape endpoint the one it is
  started with (`Scrape::start`), and a simulated service's session,
  which is no node's, the operating system's.
- **The operate listener** (`Listener::start`, `Listener::local`) counts
  its connections' frames on the Clock it is started with, and the nonces
  a node issues its relays are fresh on the Clock `Relaying::new` is
  handed: the node's, from `Running::operate`. `Fresh` has no default.
- **A surface** (`Remote::open`, `retrying`, `local`, `local_retrying`)
  tells time by the Clock it is opened with: how long a call or the
  follow's try waited (`Shared::ran_out`, which `remote::asking` and
  `plane::follow` read where they read `Instant` until now), a line's
  silence and HTTP/2 frames, and the nonces it keeps. A monitoring node's
  surfaces of its members take the node's Clock; a program's surface or
  listener through the C ABI, which hands no Clock across the boundary,
  the operating system's (`ffi::remote::hosted_clock`), as the System Tests'
  rig and the root's tests hand theirs.
- **A Stream's stall**: `StreamShare::new` takes the Clock, and
  `StreamShare::timed_by` is deleted.

Each converted decision has a test that steps `xcore::clock::Stepped` and
sleeps for nothing: one request's frames and an operate connection's
counted either side of a span (the PING-flooding peer both use is
`net::fixture::pinging`, under net's `test-support`), a relay's nonce
fresh within its span on the node's Clock, a surface's try running out at
its patience, and a Stream's reader held back until its stall passed.
Still on `SystemClock`, no node handing them one yet: the OTLP exporter's
connections and the HTTP event wire's. `test/Clock.Test.ps1` holds
`plane/shared.rs`, `plane/remote/asking.rs`, `plane/follow.rs` and
`stream_share.rs` at no `Instant` at all, and counts 94 production
`Instant::now` readings, its ceiling now. The assistant's, 2026-11-16.

## Amendment, 2026-11-17: the exporter and the event wire are made with the Clock

**The two connections the amendment of 2026-11-16 left on `SystemClock`
take the Clock where they are made, with no default: the OTLP exporter at
its start (`Exporter::start(otlp, clock)`), as the Prometheus scrape
endpoint already did (`Scrape::start`), and the HTTP event wire at its
making (`EventWire::new(clock)`; its `Default` is deleted).** Each hands
it to the `Connections` it keeps (`Connections::timed_by`), which an
HTTP/2 collector's or webhook's frames in a span are counted on. No second
seam was added.

- **No node makes either yet.** Nothing in a program or the runtime starts
  an observe exporter — the runtime handing what it publishes to observe's
  exporters waits on the open problem *Observation lags, or never arrives*
  — and event delivery's forwarder is made over a wire only by tests
  (ADR-0065, amendment 2026-11-13). The call that makes each is the one
  place a node will hand its Clock, and with no default it cannot be left
  out; until then the exporter's and the wire's own tests, which are no
  node's, hand the operating system's.
- **Each has a test on `xcore::clock::Stepped` that sleeps for nothing**:
  an HTTP/2 collector and an HTTP/2 webhook flood `PING`s either side of a
  span stepped on the Clock the exporter was started with and the wire
  made with — sent where the span passed, calmed with `ENHANCE_YOUR_CALM`
  where it did not. The flooding server is written once beside the
  flooding client, `net::fixture::pinging::answering` under net's
  `test-support`, its second run sent only once the client has answered
  every `PING` of the first, so the step falls between them.
- **What stands.** No part the earlier amendments named is left on the
  operating system's clock. It is read, by design, by a part that is no
  node's — a simulated service's session, a program's surface across the
  C ABI (`ffi::remote::hosted_clock`), a test's far end — and by a
  `Connections`, a `Serving` or a transport until `Configured::timed_by`
  times it as the node opens it.

`test/Clock.Test.ps1` holds `otlp/src/exporter.rs` and
`http/src/event_wire.rs` at no `Instant` at all. Neither read it, so the
count does not move: 94 production `Instant::now` readings, its ceiling.
The assistant's, 2026-11-17.
