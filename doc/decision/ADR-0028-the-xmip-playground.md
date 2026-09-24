# ADR-0028: The Xmip Playground

- Status: Accepted
- Date: 2026-09-05
- Amended: 2026-09-09, decision 3a — a seventh scenario, filing, drives every
  archive technology the way pingpong drives every transport
- Amended: 2026-09-09, decisions 2 and 3a — difficulty: a stress level every
  scenario runs at, an eighth scenario, storm, and nodes that are processes
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
nodes as System Processes on one machine — no virtualization — and drives every
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
Playground runs on. Nothing is virtualized and nothing is containerized —
process isolation is what the operating system provides, and it is what
Development nodes get. A process that hangs is killed and restarted like any
other Host Service.

### 3. One test, over everything, over time

The **RoundTrip test** is a single integration test whose subject is every
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
udp and websocket joined 2026-09-05**, each round-tripping over a real loopback
connection (bind, send from a second thread, receive, compare) and each carrying
both the bytes and text contracts whole. Two needed a transport change first,
both landed the same day: udp gained the bind/receive split so the sender could
learn the bound address, and websocket was built from nothing — a hand-rolled
RFC 6455 handshake (SHA-1 and base64 by hand, to keep `xmip-core-transport`
standard-library only) and framing. **Every transport the estate implements is
now in the matrix.** The transports declared but not yet built join by adding an
adapter, no change to the scenario. Clause 5 governs them all.

### 3a. More than one scenario, and two time limits

2026-09-19, the owner: the old scenario wording is replaced by the test names
everywhere (round-trip, low-latency, heavy-load, retention, filing,
exclusive-claim, daily-backlog).

RoundTrip is the first test, not the only one; each asks a different
question of the same estate over the same adapters, and every roll honors
a wall-clock maximum and a factor on simulated time. What the scenarios are
and how the limits work is the Playground's own manual,
`test/playground/README.md`, since 2026-09-12 (ADR-0020 clause 6: a record
decides, a document describes).

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
implementers over mutual-TLS, so a fault is a genuine `Refusal` or
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
  `test/playground`.
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
Virtualization would add a dependency to the one tool whose job is to have none.

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
protocols and content contracts*, spinning processes with no virtualization,
called the Xmip Playground. Clauses 1 to 6 are the assistant's drafting of it,
on the instruction to proceed.

## Amendment, 2026-09-09: difficulty

The owner: *incorporate higher difficulty, stress on all tests; we need about
10–40 processes emulating nodes.*

The stress level, the ceiling every transport declares, the tests at every
level, the half-of-what-is-free budget of 2026-09-11, the far end's move into
the transport under ADR-0051 and the cluster's node processes are decided
here and described in `test/playground/README.md`, where they moved on
2026-09-12.

The decisions, in one line each: **the level** is one axis, `calm`,
`realistic`, `harsh`, `brutal`, read once, and every scenario takes its
numbers from it; **a ceiling** is a fact about a protocol, written where it
comes from, never set to make a test pass; **the suite** stays minutes, the
brutal runs are what a roll is for; **the budget** is half of what is free of
other work, measured again before every round; **the far end** is the
transport's own; **a node is a process**, and a cluster's nodes are spawned,
merged and restarted by the roll.

2026-09-19, the owner: what the Playground spawns is a cluster and its nodes;
the word fleet is retired **here**.

Retired from the rig, not from the estate. The assistant wrote the same day
that fleet *"is in no record of the estate's vocabulary"*, and that was
false: ADR-0007's communication domain model opens its Actor hierarchy with
*Fleet owner* → *Ship owner* → *Ship* → *Captain* → *Crew*, and
`runtime-model.md` repeats it as the recursion that lets one architecture
serve a fleet operator and a sensor on a bus. ADR-0019 asks whether a fleet
certificate authenticates a ship. Fleet is the estate's word for a customer
who owns many of a thing.

What was wrong was borrowing it for a group of test node processes, which
is a cluster and was already called one. The owner, noticing the word gone
from the suites: *I used Fleet in an example.* His example stands, in
ADR-0052 and in the Playground's README; the word keeps its own meaning
everywhere it had one.

## Amendment, 2026-09-19: even clusters are spawned as processes

The owner: *even clusters have to be spawned as processes during tests.*

Decision 2 says the Playground spawns processes. Until this day the cluster
was not one of them: `xmip-playground-roll` was both the test and the cluster
— it declared itself at `xmip:///<Cluster>` and spawned the node processes
itself. It is now three deep, and each of the three declares itself
(ADR-0053):

- **the roll is the test.** It chooses the scenarios, sets the stress, runs
  the tests that stay in its own process, judges, draws the board, and
  publishes `<Cluster>-snapshot.toml` — the one file the prompt, the CLI and
  the GUI read, unchanged in path and in shape.
- **the cluster is a process the roll spawns**, one per roll (this record's
  rule is untouched: a roll is one cluster). It owns the store its nodes
  share, spawns and supervises them, restarts one that hangs, merges what each
  published, adds the rollup at `xmip:///<cluster>/node` that no node can say
  about itself, and publishes all of it to `<Cluster>-cluster.toml`, which the
  roll merges.
- **the nodes are processes the cluster spawns**, as decision 2 and the
  2026-09-09 amendment already say.

The `stop` file in the shared directory stops the whole tree, and a cluster
stops its own nodes before it goes, however it is ended; `Stop-XmipTest` ends
the tree from the leaves up. Nothing is orphaned: `Get-Process xmip-*` is
empty afterwards.

The details are `test/playground/README.md`, as 3a says.

## Amendment, 2026-09-19: a real node is used, a simulated one is the fallback

The owner, the same day: *if there are actual DNS names for clusters and
nodes, the test shall use them instead of spawning test processes.*

Spawning is not the point of the Playground; having something to test against
is. A simulated node exists because there is no real one, and where a real one
exists the rig has no business inventing a second.

- **What is resolved, and only that.** The names the operator already named,
  `-Cluster` and `-Nodes`, through the machine's own resolver. Nothing else,
  and never a name the operator did not type. ADR-0045 clause 1 governs a
  node's own path and forbids resolving a **public** name at runtime; a test
  asking its resolver whether `R1` is a machine on this network is neither
  the runtime path nor a public name.
- **Resolving is not trusting.** A name that resolves gives an address, and
  the rig still has to find Xmip there: the node must answer and declare
  itself (ADR-0053) and say what it can do (ADR-0056). A name that resolves
  to something that is not an Xmip node is REFUSED by name, not quietly
  replaced with a spawned process — the operator meant that machine.
- **The fallback is today's behavior exactly.** A name that does not resolve
  is a node the rig spawns, as it does now. An estate with no DNS, or a
  machine with no route, behaves as it does today and says so. Offline stays
  the default (ADR-0045).
- **The run says which is which.** `[run]` and the board name, per node,
  whether it is real or simulated, because a green board means two different
  things in the two cases and an operator must never have to guess which.
- **What a real node is not asked to do.** The rig does not spawn, configure
  or stop it; in a real environment an orchestrator owns a node's life, never
  Xmip (ruling 8 of ADR-0052). The rig sends it work and reads what it
  publishes.

Agreed 2026-09-19, not yet built. Nothing resolved on the owner's machine the
day it was agreed — `C1`, `R1` and their kin were checked and there is no
search suffix — so the rig's behavior is unchanged until an estate has names.

## Amendment, 2026-09-19: a run is found by what it declared, not by the file

Two defects, found the same day the cluster became a process of its own.

**What was wrong.** `Get-XmipTestStatus` and `Get-XmipTestNode` judged a
process by the file on disk: the image the operating system reports it running
had to be the Playground binary under `test/playground/target/debug`, and a
process that failed that test was dropped without a word. The owner rebuilt the
Playground while his roll was rolling. Twenty-one processes — a roll, its
cluster and its nodes — went on running, and every cmdlet meant to manage
them answered with nothing. `Get-XmipProcess` found all twenty-one, because it
asks what each process declared of itself (ADR-0053) rather than what is on
disk.

**What it cost.** `Stop-XmipTest` reads the same lookup, so the roll could not
be stopped by its own cmdlet: the nodes had to be killed by pid. Reproduced on
cluster Y1 the same day — with the binaries replaced underneath it,
`Get-XmipTestNode` gave every node an empty `Parent`, `Get-XmipTestStatus` gave
the run an empty `Nodes`, and `Stop-XmipTest -Cluster Y1` stopped the cluster
and the roll and left three orphaned node processes behind. **A process Xmip
started and cannot find is a process Xmip cannot stop.**

**What now holds.**

- **The declaration is the truth, the name is the rule.** A process is looked
  up by the binary it declared it started from (ADR-0053 carries it), then by
  the image this machine reports, then by its name — and every System Process
  Xmip owns is named `xmip-<what>` and nothing else is. A running process is
  never dropped because the file it came from was rebuilt, renamed, moved or
  deleted under it.
- **A disagreement is said in words** (ADR-0055). Where the image is not the
  binary expected, the cmdlet warns, naming the pid, the image and the file,
  and lists the process anyway. Silence is what made this invisible.
- **A parent is named by its pid.** This machine names a parent process after
  the image file's *current* name, so renaming the binaries renamed every
  parent and no node belonged to a roll any more. Parentage is now resolved
  through the pid and the declaration, never through the file.
- **A process that declared itself is found even when this machine no longer
  calls it by that name**, and that, too, is said.

The lookup lives in `Xmip/Get-XmipPlaygroundProcess.ps1`; it moved out of
`Xmip/Start-XmipTest.ps1` with this change. `test/XmipTest.Test.ps1` holds the
tests, over the judgment itself rather than over a running binary — the suite
still starts nothing.

The other defect of that day, a history file that had never held a point, is
ADR-0029's: the rule it broke is what a history point is, not what the
Playground spawns. It is recorded there.

## Amendment, 2026-09-23: the Playground is core's, and says so

The owner, reading the estate map: *there is no room for 3rd parties there is
test/playground. It should be test/core/playground so there is room for
test/3rd party/playground. Corresponding repos would be
xmip-core-test-playground and xmip-<3rd party>-test-playground.*

He is right, and the reason is in the name. A repository is
`xmip-<provider>-<module>` (repository-model.md, section 2), so
`xmip-test-playground` read as *provider `test`, module `playground`* — and
the manifest said as much, calling `test` a provider namespace others may
join. But that left a second provider only the provider's own slot to take:
`xmip-<provider>-playground` claims a module named playground rather than saying
is test scaffolding, and the path `test/playground` had no room at all.

- **`test` is the kind of work, not the provider.** The repository is
  `xmip-core-test-playground`, declared at `xmip.core.test.playground`,
  mounted at `test/core/playground`. A second provider's is
  `xmip-<theirs>-test-playground` at `test/<theirs>/playground`, declared the
  same way under their own provider, and every rule here applies to it
  unchanged.
- **Core's own paths do not move.** A path without a provider in it means
  core, so `module/capability/transport` stays as it is; a provider other
  than core mounts under a subtree of its own. The rule is written down now
  rather than invented when the first third-party module arrives.
- **The rename kept its history.** GitHub redirects the old name, the
  submodule moved with `git mv`, and the crate is `xmip-core-test-playground`.
  Clause 1 above still holds: one repository, optional, ADR-0036.

## Amendment, 2026-09-24: the Playground stays at test/core/playground

For a day the Playground was moved to `module/core/test/playground`, on a
reading of the owner's *provider before purpose* as putting everything a
provider ships under `module/`. The owner, 2026-09-24, asked where it belongs,
and answered: `test/core/playground`, as placed above. A second provider's is
`test/<theirs>/playground`.

The second bullet above no longer holds, for a different reason. Core's modules
did move: the owner's rule of 2026-09-23 is that what starts a node mounts with
no provider — `module/foundation/…`, `module/platform/…` — and everything else
with its provider first, `module/core/capability/transport`. ADR-0016,
amendment 2026-09-23, corrected 2026-09-24.
