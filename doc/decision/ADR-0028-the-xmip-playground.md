# ADR-0028: The Xmip Playground

- Status: Accepted
- Date: 2026-09-05
- Amended: 2026-09-09, decision 3a — a seventh scenario, filing, drives every
  archive technology the way pingpong drives every transport
- Amended: 2026-09-09, decisions 2 and 3a — difficulty: a stress level every
  scenario runs at, an eighth scenario, storm, and nodes that are processes
- Amended: 2026-09-30 — a test run can be hidden, by what it declares
- Amended: 2026-10-13 — the Parties built, and flows named as an ERP's
- Amended: 2026-10-19 — `accept.party` built in the node
- Related: ADR-0018 (the Service and the Host Services), ADR-0027 (the operator
  boundary), ADR-0010 (contract and transport boundaries), ADR-0025 (when a
  Module loads), ADR-0052 (the views' "show test clusters" box, its
  amendment 2026-09-30), ADR-0053 and ADR-0062 (a hidden run's declarations
  and audit records say so, since 2026-09-30)

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

**Exercising against external systems.** Real Parties, real brokers. Rejected
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
  asking its resolver whether `alpha` is a machine on this network is neither
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

## Amendment, 2026-09-30: a test run can be hidden, by what it declares

The owner, 2026-09-29: *If you need a cluster for test purposes that is fine,
call it CT. When tests are run it's got to be hidable. Like when tests are run
include a checkbox if CT cluster should be shown or not in the operation
tools.*

The name is the owner's advice to whoever tests beside him; what hides the
cluster is not. Nothing at runtime reads meaning from a name (ADR-0053; the
owner's rule, capability not name), so a cluster called CT is shown like any
other, and a run is hidden because it said so when it was started.

- **The declaration.** `Start-XmipTest -Hidden` declares the run hidden. It
  belongs to the Playground alone, as `-Cluster` does. The run record says
  `hidden = true`; `XMIP_PLAYGROUND_HIDDEN` tells the roll, whose cluster and
  nodes inherit it; the roll's `[run]` table says `hidden = true`
  (`observe::Run::hidden`, crossing section 8's head as `hidden`); the roll,
  its cluster and every node add `hidden = "true"` to their process
  declarations (ADR-0053 clause 3) and say it on every audit record they
  make (`ProgramAudit::hide`, beside `locate`; ADR-0062 clause 5). A run
  started without it declares nothing and is shown.
- **The rule, once.** Whether something a run made is shown is
  `observe::run::shown`: always where the run declared nothing, and where it
  declared itself hidden only when the reader asks to include what is
  hidden. The audit capability's query applies it to records (`hidden`,
  `include` or `exclude`); the runtime forwards it as `xmip_run_shown_v1`
  (`xmip_operate.h` section 7), `RuntimeRules.Shown` binds it, and
  `Xmip.Surface`'s `ClusterSurfaces`, `Get-XmipTestStatus` and
  `Stop-XmipTest` call that.
- **Hidden by default, everywhere.** `Get-XmipTestStatus` lists a hidden run
  only with `-IncludeHidden`, so `Get-XmipTestStatus | Start-XmipOperationWeb`
  never follows one unasked, the prompt never follows one, and a plain
  `Stop-XmipTest` leaves it running; `Stop-XmipTest -Cluster CT
  -IncludeHidden` or `-Id` stops it. `Get-XmipAudit -IncludeHidden` and
  `xmip-cli audit --include-hidden` read its records. The views are ADR-0052's
  amendment of the same date.
- **How the assistant's test cluster is started, always:**
  `Start-XmipTest -Suite Core.Playground -Cluster CT -Test RoundTrip
  -Nodes R1, P1, S1 -NodeCapability @{ R1 = 'receive'; P1 = 'process'; S1 =
  'send' } -Hidden`, and stopped with `Stop-XmipTest -Cluster CT
  -IncludeHidden`.

`test/HiddenRun.Test.ps1` holds the tooling's side: the declaration reaches
the roll, a hidden run is listed only when asked, and a run called CT that
declared nothing is listed like any other.

Provenance: the requirement, CT and the checkbox are the owner's, quoted
above. Hiding by declaration rather than by name is the lead's ruling under
the owner's standing rule; the word `-Hidden`, `-IncludeHidden`, the fields
and the default of hidden everywhere are the assistant's drafting, for the
owner to overrule.

## Amendment, 2026-10-06: Parties, good and bad days, and a fault every 50 seconds

The owner, 2026-10-06, on the word (there are providers and Parties, and
nothing else) and on the tests: *we are missing parties in the tests. The
tests need to cover possible scenarios and also look real*; on the scenarios
first proposed —
one Party that only fails, another always refused: *that is a bad scenario
you painted. All parties has mostly good communication there are good and
bad days over parties, transports and streams*; and: *The Monitoring &
Topology view, during tests has to show that everyting is at some time.
Have a time span filter of 1 minute and inject faults every 50 seconds
would work. Then one could pause, expand the time span to investigate the
historical errors.*

- **Several Parties, each on several transports and streams, both
  directions.** No Party is the failing one: every Party communicates well
  most of the time.
- **A fault every 50 seconds**, moving across Parties, transports and
  streams — one Party's transport on one turn, another's stream on the
  next — so within any one minute the board shows trouble somewhere and,
  between faults, everything green. Clause 4a's kinds of fault and its
  determinism stand; the cadence and the spread are new.
- What an operator does with it is ADR-0052's amendment of the same date:
  a one-minute span, paused and widened to investigate. Not built.

## Amendment, 2026-10-13: the Parties built, and flows named as an ERP's

The owner, 2026-10-13, watching his Playground run: *You have not
Implementet more Parties than Party-X. It is better, but not good enough.*
Of its Locations and Ports, one Application named after the test: *just do
not make sense*, and, asked whether to name them as an ERP's documents:
*Yes, use ERP names.* And of a name that carried its protocol: *The
protocol shall not be in the Send or Receive Port, Location. That is
infered information, which one should se in the operation tools.*

The amendment of 2026-10-06 is built:

- **The Parties are configuration.** The Playground's `configuration/xmip.toml`
  declares them as `[[parties]]`, each with `name` and `identities`, in the
  shape `runtime-model.md` gives (ADR-0031, amendment 2026-10-01) —
  `Party-A` to `Party-E` as shipped, renamed there. The parse is placed once,
  in `xmip-core-configure` (`configure::party`; the node document's
  `parties`), which open problem 33 named as missing: a Party without a
  name or an identity, a name twice, or an identity two Parties hold is a
  problem every node's binding reports. The cluster designer has a Party
  view (`configure::views`). Nothing in the Playground's code or tests names
  a Party; a test reads them from the file.
- **Several Parties, each on several transports and streams, both
  directions** (`src/parties.rs`): the Party at a transport's place in the
  list sends into its Receive Locations and the next Party is delivered to
  over its Send Locations, so every Party sends and receives, over
  different transports, and every stream of a transport is its Party's.
  The identity pipeline runs per Party: the arrival claims the Party's
  certificate subject, the Receive Location accepts that Party alone and
  resolves the claim through every Party's identities, and a Send Location
  presents the same; another Party's subject is refused at authentication.
- **The fault every 50 seconds** (`src/rotation.rs`): each turn of fifty
  wall-clock seconds strikes one target for its first ten — one Party's
  transport on one turn, one stream of the next Party's on the next — round
  the Parties in order, alternating the side they send into with the side
  delivered to, with clause 4a's transport, addressing and contract faults.
  The turn is the clock's, so every node of a run agrees on it, and its
  target the turn's alone. At `realistic` nothing else is injected, so
  between faults the board is green; `harsh` and `brutal` add the realistic
  table scaled as before; `calm` injects nothing. `file` carries no fault
  at any level, as before.
- **Drawn and named per Party.** `observe::topology::party::draw` takes the
  Parties and, for each, the transports it is reached over on each side; a
  link counts what its stage counted over the Party's transports and its
  mood is the worst of the Party's endpoints. The Playground's ledger counts
  per stage and transport, `<node>/<stage>/<transport>`, which a stage's
  figure sums. A running node still draws `any-party` over every endpoint:
  no Location says which Party it serves until `accept.party` is read. The
  roll's first lines and its `start` record name the Parties.
- **Flows named as an ERP's.** Two Xmip Applications, *Order to cash* and
  *Procure to pay*: sales orders, purchase order responses, goods receipts,
  inventory reports and remittance advices received from Parties; order
  responses, despatch advices, invoices — a second Send Location for
  failover — purchase orders, item master and payments sent to them. Their
  Subscriptions together pick up every content contract once. A name says
  the document and the Party, never the transport: that is each Location's
  configuration, and the operation tools show it — the Topology draws an
  endpoint per transport beneath each stage. The bindings are written from
  the sections, so no Location, Port or Subscription is named in code.

- **The drop box: many files, one winner each** (`src/drop_box.rs`). The
  owner, the same day: *induce multiple files for FILE and (S)FTP(S) so I
  can see that it holds up*, and *only one Rn should win.* Each Party has
  one directory per protocol, shared by every receiving node: its own file
  Receive Location under the cluster's shared directory, and an FTP, an
  FTPS and an SFTP server of its own that the roll stands up for the whole
  roll (`src/drop_box/far_ends.rs`) — Xmip's own server sides, each serving
  every receiving node at once (`transport::concurrent`), FTPS over Xmip's
  TLS with a certificate from the estate's own self-signed source — and
  whose addresses it writes beside the drop box. The roll drops a burst of
  eight files for each Party over each protocol through that transport's
  send: every round over file, every fifth over the servers, whose every
  FTP transfer and listing is a data connection and a local port of its
  own. Every node that declared receive reads every Party's directories
  through the same transports' receive — FTP and FTPS every second round —
  whose claim is the file family's turn and rename (ADR-0024, amendments
  2026-09-26 and 2026-10-13), so whichever node's rename succeeds has the
  file. The winner accepts and signs it; each node counts what it took at
  `<node>/drop-box/<protocol>/<party>`, so the board shows the split
  between the receiving nodes Location by Location; and the roll judges
  every file ten seconds after it was dropped, saying per protocol at
  `<root>/drop-box/<protocol>` and in its `stop` record either *every file
  taken by exactly one receiving node*, with the split, or each file taken
  twice and by whom and each never taken.

This supersedes ADR-0052's amendment of 2026-09-29 where it says a
Playground cluster has one Party, `party-x`.

Proved by `configure`'s `party.rs`, `section.rs` and `views.rs`, `observe`'s
`topology/party.rs`, and the Playground's `parties.rs`, `rotation.rs`,
`identity.rs`, `subscribing.rs`, `topology.rs`, `run.rs`, `drop_box.rs` and
`drop_box/judged.rs`.

Not built: the Receive Location's `accept.party`, so a Location named for a
Party is not yet held to it, and the `[run]` table carries no Parties.

Provenance: the owner's words above. The spread by place, the turn of ten
seconds in fifty, the alternation of sides and kinds, the ERP flows'
document names and which contract family each Subscription takes, and the
problems the Parties' parse reports are the assistant's drafting, for the
owner to overrule.

## Amendment, 2026-10-13: the build runs detached

The owner, 2026-10-13, of `Start-XmipTest` holding his console during the
first build of a roll: the build runs detached too. `Start-XmipTest` built
the roll, cluster and node binaries in the console before it spawned
anything, and a first build took minutes; the roll itself has run detached
from the start, and the estate's Pester suite since 2026-09-25.

- **`Start-XmipTest` returns at once.** It still refuses in the console,
  before anything starts — a choice it cannot run, and a cluster already
  rolling or still building — and writes the run's cluster file there. The
  build and the roll's spawn then run in a pwsh of their own
  (`Start-XmipPlaygroundBuild`), which spawns the roll once cargo has
  finished (`Start-XmipPlaygroundRollProcess`) and writes its run record as
  before.
- **Building is the run's state.** The build writes a record,
  `build-<start time>.toml`, beside the rolls' records, and its output to
  `build-<start time>.log`. `Get-XmipTestStatus` lists it as kind `build`,
  state `building`, with how many crates cargo has compiled and the last of
  them — cargo prints no total when its output is not a terminal, so the
  progress is counted, not estimated — until the roll is spawned and listed
  in its place.
- **A failed build says why.** It is listed `FAILED`, the reason cargo's
  first error, or that its pwsh was stopped or died, until that cluster is
  started again.
- **`Stop-XmipTest` stops a build** as it stops an estate run: the pwsh and
  everything beneath it, cargo and the compilers, then the record.

`Start-XmipTestNode` still builds the node in the console: the owner's words
were about `Start-XmipTest`. A first `Write-XmipAudit` in a session still
holds the console for the operator module's `dotnet build`, seconds rather
than minutes; that is not this amendment's.

Proved by `test/PlaygroundBuild.Test.ps1`.

Provenance: the owner's words above. The record's shape, the counted
progress and the refusal of a second start while building are the
assistant's drafting, for the owner to overrule.

## Amendment, 2026-10-19: `accept.party` is built

What the amendment of 2026-10-13 left unbuilt, a Receive Location held to
the Parties it names, is built in the node (ADR-0019, amendment
2026-10-19). The Playground's gates count a Party's identifier and resolve
a claim as a node does, through `configure::party::id` and
`configure::party::place_holding`, rather than each its own copy. The
`[run]` table carries no Parties still.

## Amendment, 2026-10-20: the Parties carry their ids and their identities' mechanism and purpose

Each of the Playground's `[[parties]]` is written with its `id`, a UUIDv7
minted once with it, and each identity as `{ mechanism = "mutual-tls",
purpose = "receive", value = "CN=…" }` (the owner, 2026-10-19; ADR-0019,
amendment 2026-10-20). The gates resolve a claim through
`configure::party::place_holding` by mechanism and purpose and know a
Party by the id it is written with (`Parties::id`), as a node does;
`configure::party::id`, the place counted from one, is deleted.
