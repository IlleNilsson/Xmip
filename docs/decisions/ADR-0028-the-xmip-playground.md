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
once. Its scenario is a round trip: send a payload, catch it, check it came
back whole. It runs on a Schedule and never stops; each round folds into a
running tally per pair, so a pair is judged by its record over time rather than
its last round, and one failure among thousands stays visible until a round
passes again. A pair not exercised in the last window is stale, and the
snapshot shows staleness.

Named by the owner, 2026-09-05: *the pingpong test, an integration test over
time, for all protocols and contracts.* The first implementation runs the file
transport — self-contained, no port to coordinate — over the bytes and text
contracts; ADR-0028 clause 5 governs the socket transports as they join.

### 4. A verdict is health

Per pair: green when Streams arrived, were routed, were delivered and the
contract held; red when any of those failed, with the failure as evidence;
yellow when the pair was exercised and something was slow or degraded. Scope
`xmip:///<playground-node>/exercise/<transport>/<contract>`, so the GUI shows
it where it shows everything else.

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
  `modules/operations/playground`.
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
