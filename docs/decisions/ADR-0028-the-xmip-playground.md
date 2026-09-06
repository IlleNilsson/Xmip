# ADR-0028: The Xmip Playground

- Status: Accepted
- Date: 2026-09-05
- Related: ADR-0018 (the Service and the Host Services), ADR-0027 (the operator
  boundary), ADR-0010 (contract and transport boundaries), ADR-0025 (when a
  Module loads)

## In brief

- Theme: Operating Xmip
- Subject: The Playground exercises everything, all the time
- Name: The Xmip Playground
- Order: 5
- Concepts: Playground, exercise, verdict; Development node

**`xmip-test-playground` exercises Xmip continuously.** It spawns Development
nodes as System Processes on one machine — no virtualisation — and drives every
transport and every content contract through them: a Receive Location for each
transport fed with generated Streams for each contract, a Send Location watched
for what arrives, and a **verdict per (transport, contract) pair** — arrived,
routed, delivered, contract held — published as health on its own scope. The
pair that breaks turns red on the same page as everything else, and is named.

It is a **node role, not a test suite**. `NodeRole::Development` already exists
beside Operational, Monitoring and Executing; a Playground node is a Development
node and the role is the isolation — it never touches a production node.

It is also **the source of real measurement**: Streams in, Journeys through,
Messages out, per stage and per pair, into the snapshot the operator boundary
reads. Until it runs, a throughput card shows a dash.

## Context

ROADMAP section 7 lists contract and conformance tests, failure and recovery
tests, and performance and overload tests, all as things a release does. The
owner's requirement, 2026-09-05, is the same thing running all the time: *a test
playground, constantly activating receive locations, monitoring send, for all
transport protocols and content contracts.*

Two facts make it cheap. `xmip-core-transport` already carries http, smtp, tcp,
udp and file as both server and client, so Xmip's own transports are the far
end of every exchange — a Receive Location is fed by an Xmip Send Location and
nothing external is stood up. And `registration.rs` already generates what a
System Process needs, so spawning a node is what the runtime does anyway.

The operator boundary landed the day before this record, with a card per stage
and nothing to count. The Playground is what counts.

## Decision

### 1. One repository, `xmip-test-playground`

Operations domain, an operational capability. The name is the owner's and the
proper noun is **Xmip Playground**, in terminology.md.

**The provider segment is `test`, not `core`** — the owner's call, 2026-09-05,
renamed the same day it was created. `core` is what Xmip is; `test` is what
exercises it, and it is a namespace another provider may join with a playground
of their own, `xmip-<theirs>-playground`, under the estate's rules unchanged.
The `xmip.test` root is reserved: there is no `xmip-test` crate, only what sits
beneath it.

### 2. It spawns processes

Nodes, generators and watchers run as System Processes on the machine the
Playground runs on. Nothing is virtualised and nothing is containerised —
process isolation is what the operating system provides, and it is what
Development nodes get. A process that hangs is killed and restarted like any
other Host Service.

### 3. One test, over everything, over time

The **pingpong test** is a single integration test whose subject is every
transport the estate declares by every content contract it declares — not a
test per protocol or per contract, but one test across the whole matrix at
once. Its scenario is a round trip: send an actual Stream, catch it, check it
came back whole **and** that the contract holds over what arrived — a pair is
delivered only if both are true, which is the difference between testing a
transport and testing an integration. It runs on a Schedule and never stops;
each round folds into a running tally per pair, so a pair is judged by its
record over time rather than its last round, and one failure among thousands
stays visible until a round passes again. A pair not exercised in the last
window is stale, and the snapshot shows staleness.

The contract axis is real, not a byte comparison: bytes (no structural claim),
text (UTF-8), json (well-formed, via a real parser), xml (well-formed) and html
(markup), each a `Contract` in the estate's own trait so that when the
`xmip-core-message-*` and `xmip-core-contract-*` modules land, the probe
validates against those instead — a move, not a rewrite. A malformed Stream is a
violation, red with the parser's own reason, not a pass.

Named by the owner, 2026-09-05: *the pingpong test, an integration test over
time, for all protocols and contracts.* The scenario drives a small `RoundTrip`
adapter — send a payload, get back what returned or why it could not — and each
transport implements that adapter however its own shape demands, so the scenario
is one thing over all of them and a new transport is a new adapter, not a new
test. File was first — self-contained, no port to coordinate; **tcp, http, smtp,
udp and websocket joined 2026-09-05**, each ping-ponging over a real loopback
connection (bind, send from a second thread, receive, compare) and each carrying
both the bytes and text contracts whole. Two needed a transport change first,
both landed the same day: udp gained the bind/receive split so the sender could
learn the bound address, and websocket was built from nothing — a hand-rolled
RFC 6455 handshake (SHA-1 and base64 by hand, to keep `xmip-core-transport`
standard-library only) and framing. **Every transport the estate implements is
now in the matrix.** The transports declared but not yet built join by adding an
adapter, no change to the scenario. Clause 5 governs them all.

### 3a. More than one scenario over the same adapters

Pingpong is the first scenario, not the only one. Each scenario asks a different
question of the same estate over the same [`RoundTrip`] adapters, and publishes
under its own subtree of `xmip:///playground`, merged into one snapshot so the
rollup covers them all and an operator drills scenario → detail → the failing
leaf. Named in the shortest singular form, the owner's convention:

- **pingpong** — did it arrive whole and hold its contract, across the stages.
- **furious** — did it arrive in time: round-trip latency against a per-transport
  budget, judged on the p50/p99 of recent rounds (cold-start rounds skipped).
- **load** — a megabyte per pair: did it arrive byte-for-byte and still validate
  at size, and at what throughput. A UDP datagram cannot hold a megabyte, and
  that real ceiling shows as red with no injection.
- **secretary** — retention and archiving: keep, archive and purge by age,
  driving the estate's real `RetentionPolicy` and `ArchiveStore` over a logical
  clock; a missed sweep under pressure surfaces as a retention leak.

Each injects its own pressure (faults, latency spikes, dropped transfers, missed
sweeps) so the board is realistic rather than uniformly green; `file` is left
clean in every one.

**Queued:** **claim** — the exclusive single-reader test for the pollable
file-transfer transports (FILE, SFTP, FTPS, FTP): a file dropped for pickup is
read by exactly one reader across competing threads, processes and nodes
(ADR-0024, the claim at the endpoint). It waits on the SFTP, FTPS and FTP
adapters — only FILE is implemented today — and is built when all four exist
(the owner's call, 2026-09-06). The name is settled.

### 4. A verdict is health, per stage

Each round is expanded across the message path — **Receive, Process, Send** — so
the verdict is per `(stage, transport, contract)`, scope
`xmip:///<node>/<stage>/<transport>/<contract>`. The stage is the first segment
under the node, so the landing page's Receive/Process/Send cards light up and an
operator drills stage → transport → contract to the failing leaf. Green when the
stage delivered; red when it failed, with the failure as evidence; yellow when
it has failed before and passes now. Receive counts a Stream in, Process a
Journey through, Send a Message out — the three the stage cards count.

### 4a. The world does not run green: injected faults

Loopback never fails, so a Playground of nothing but loopback proves the
transports work and proves nothing about the monitoring. So the Playground
injects the faults a real integration suffers, on all three stages, of three
transport-and-content kinds an operator triages by: **transport** (reset,
timeout, port in use, lost datagram), **addressing** (unresolved host, no route,
rejected recipient) and **contract** (content that fails its schema). Firing is
deterministic per (stage, pair, round), so a run reproduces and a test can assert
it; rates are low, so the board is mostly green with faults surfacing over time.
`file`'s transport path carries no fault, one transport that stays green.
Identity faults are their own axis — clause 4b.

### 4b. Receive runs the identity pipeline; Send presents identity

A Receive Location does not only receive bytes: it **identifies** who is claimed,
**authenticates** the claim, and **authorizes** what it may do — the invariant
pipeline of ADR-0019, in that order. A Send Location **presents** an identity to
the far end (ADR-0033). The Playground exercises this by driving the estate's
real gates — `identify_transport`, `authenticate`, `authorize` — with stand-in
implementors over mutual-TLS, so a fault is a genuine `Refusal` or
`Decision::Denied`, not a fabricated string. Each Receive step publishes as a
child scope `.../receive/<transport>/<contract>/{identification,authentication,
authorization}`, and Send as `.../send/<transport>/<contract>/identity`, so an
operator drills past the transport verdict into the identity step that failed.
The pipeline stops at the first failing step; the rest report *not reached*.
Identity faults — a rejected or expired certificate, a Let's Encrypt renewal
pending, a party not permitted — live with the pipeline, not in the transport
fault plan, and `file` is exempt here too. Identity children do not double-count
throughput: a Stream is received once, not once per identity step.

### 5. The far end is Xmip

Wherever a transport has both a server and a client in `xmip-core-transport`,
the Playground uses them as the counterparty. A transport that has only one
side is exercised as far as that side allows and the verdict says so. No
external broker, server or service is a prerequisite for the Playground to run.

### 6. Measurement comes from it

The Playground's nodes publish counts per stage into the snapshot. That is
where the numbers on the operator's page come from before any production
traffic exists, and it is how a regression in throughput is seen as a number
rather than felt as a complaint.

## Consequences

- `xmip-test-playground` is declared in `architecture.toml` and created through
  `Sync-XmipEstate`, from the Rust template, mounted at
  `tests/playground`.
- **Xmip Playground** is a term in terminology.md.
- Phases four to nine of startup (ADR-0018) — actually starting processes,
  loading Modules, accepting work — are what the Playground needs first and
  does not have. Its first version spawns nodes that plan and validate, which is
  what the runtime can do today, and grows with the runtime.
- The 79 declared, empty technology repositories each get exercised the day
  they gain code. The matrix is the definition of done for a transport.

## Alternatives considered

**Containers or virtual machines per node.** Rejected by the owner: the
Playground spins processes, and the operating system already isolates them.
Virtualisation would add a dependency to the one tool whose job is to have none.

**A test suite run at release.** What ROADMAP section 7 describes. Not rejected
— it still happens — but it finds a regression at release rather than the hour
it landed, and it produces no measurement in between.

**Exercising against external systems.** Real partners, real brokers. Rejected
as the default: the Playground has to run on a laptop with no network. Xmip's
own transports are the counterparty, and an external system is an optional
extra target when one is available.

## Provenance

The requirement and the name are the owner's, 2026-09-05: *a test playground,
constantly activating receive locations, monitoring send, for all transport
protocols and content contracts*, spinning processes with no virtualisation,
called the Xmip Playground. Clauses 1 to 6 are the assistant's drafting of it,
on the instruction to proceed.
