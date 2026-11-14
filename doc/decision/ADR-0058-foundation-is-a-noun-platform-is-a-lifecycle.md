# ADR-0058: Foundation is a noun; Platform is a lifecycle

- Status: Accepted
- Accepted: 2026-09-20, the owner, on being shown what each record named
  as his to strike. Nothing was struck.
- Date: 2026-09-19
- Related: ADR-0011 (module naming), ADR-0012 (the module boundary), ADR-0016
  (submodule composition), ADR-0018 (service and host; the runtime owns the
  execution tree), ADR-0044 (a technology shares through its capability),
  ADR-0048 (a resilience technology is a guard on the attempt), ADR-0049 (a
  host crate keeps its source in `.src`), ADR-0013 (the Journey model),
  `doc/architecture/repository-model.md` sections 1 and 4

## In brief

- Theme: The shape of the estate
- Subject: What separates a Foundation repository from a Platform one
- Name: Foundation is a noun; Platform is a lifecycle
- Order: 13
- Concepts: the Foundation-Platform test; a definition has no verb; Platform is not the default

**Foundation is what Xmip is: a definition, with no verb of its own, true of
the traffic whether or not anything is running. Platform is what a running
node needs to keep those definitions alive: it acts — it reads a document,
opens a store, spawns a host, fires a timer — and the subject of that verb is
the node itself. A Foundation crate depends only on Foundation. Platform is
not the default: a crate that answers to the message-path test or the
observation test is placed there first, and only what is left is Platform.**

## Context

Repository-model.md section 1 has had a test between Capability and Operation
since 2026-08-26, and it works: *if a Message waits for it, it is a
Capability* (worded so since ADR-0013's amendment of 2026-10-29: the Message
travels, the Journey is its metadata). It moved `xmip-core-retain` out of the wrong domain within a day
of being written, and it is the sentence people quote when the question comes
up.

Between Foundation and Platform it has nothing. The table says Foundation
holds *things Xmip is* and Platform holds *platform-wide runtime services*,
which is not a test — it is two descriptions that overlap for anything with a
type in it. With no test, the placement rule in practice was: **anything that
looked runtime-shaped went to Platform and stayed there.** Nothing ever moved
out, because nothing said what would move it.

What that produced, measured on 2026-09-19:

- `xmip-core-resilience`, 1763 lines, sitting in Platform with the exact shape
  of a Capability: a `.src/` host crate (ADR-0049) with six technologies
  mounted beside it — retry, timeout, circuit-breaker, rate-limit, bulkhead,
  fallback — which is the shape of `xmip-core-authenticate` and of no platform
  service. ADR-0048 calls each of the six a technology in as many words.
- `xmip-core-runtime`, 4332 lines over fourteen files, with `generation.rs`
  among them — a file whose own first line reads *"What a Message generation
  is, and the three treatments an artifact declares"*, which is a definition
  and not a service.
- `xmip-core-schedule`, six lines and no public API, which nothing had
  revisited since it was named.

The owner, 2026-09-19: *Let's consolidate, refactor and re-engineering.
Especially between platform and foundation. It seems to me that there is too
much in platform.*

He is right, and the reason there is too much in Platform is that Platform is
where a thing lands when nobody has written down what would keep it out.

## Decision

### 1. Foundation is a definition, and a definition has no verb

A Foundation repository answers *what is this?*. It declares a shape and the
invariants that make it that shape: a Message, a Stream, a Journey, a Party, a
Node, a Cluster, an Event, an identifier, the binding over the module
boundary. Nothing in it starts, opens, spawns, reads a file or waits on a
clock. Its subject is the traffic and the parties — what Xmip carries — and it
is true of them whether or not a node is running anywhere.

Pure functions over those shapes are still definitions. `apply_transformation`
does not become a service by being a `fn`; the test is whether something has
to be *running* for the code to mean anything, not whether the code computes.

### 2. Platform is a lifecycle, and a lifecycle has a subject

A Platform repository answers *what does this node need in order to run?*. It
acts on the node's behalf — it reads a configuration document from disk, opens
a durable store, plans and spawns host services, registers what was loaded,
fires a timer — and **the subject of that verb is the node, not the traffic.**
Something starts it, supervises it and stops it, even where the supervisor is
not written yet.

`xmip-core-node` is the case that shows the two clauses are one rule and not
two: a Node is a definition, so it is Foundation, although its subject is a
node. It is `xmip-core-persist` that is Platform, because a store is *opened*.

### 3. Foundation depends only on Foundation

This was implied and never stated, and it is the clause that decides the hard
cases. Section 4 of repository-model.md forbade Foundation depending on
Technology and said nothing about Capability or Operation. It is now the whole
direction: a Foundation crate may depend on Foundation crates and on
third-party crates, and on nothing else in the estate.

The consequence is worth stating plainly, because it reads as a defeat the
first time it is met: **a definition whose meaning quotes a Capability's
verdict cannot be moved to Foundation.** It stays in the crate that already
composes those Capabilities, which is ADR-0044's rule read upward — shared
code goes to the nearest crate that already has both.

### 4. Platform is not the default

A repository is tested in this order: the message-path test first (if a
Message waits for it, it is a Capability), then the observation and governance
test (ADR-0014 clause 4 keeps observation out of the message path, so audit,
observe, report, archive and the operator surfaces are Operation), then this
record's two clauses. **What is left is Platform.** Nothing is Platform for
want of a better idea.

### 5. What this decides, crate by crate

**Foundation — all ten stay.** `xmip-core` (identifiers, clocks, the error
declaration), `xmip-core-abi` (the Rust binding over the normative header),
`xmip-core-stream`, `xmip-core-message`, `xmip-core-context`,
`xmip-core-journey`, `xmip-core-node`, `xmip-core-cluster`, `xmip-core-party`,
`xmip-core-event`. Each declares a shape; none of them starts anything; and
every one of them depends on Foundation alone, so clause 3 is already true of
the domain and is a ratchet rather than a migration.

**Platform — four stay, one leaves.**

- `xmip-core-runtime` **stays.** It plans host services, spawns them, loads
  Modules, registers their capabilities and answers the operator boundary. It
  is the clearest Platform crate in the estate.
- `xmip-core-configure` **stays.** It reads a node's TOML and returns the
  configured service (ADR-0031). The types are shapes, and the act — parsing a
  document that describes this node's own start-up — is the node's, not the
  traffic's.
- `xmip-core-persist` **stays.** A `RuntimeStore` is opened, written through
  and closed. Its types quote `xmip-core-journey`, which is the correct
  direction and not the reverse.
- `xmip-core-schedule` **stays, and is on notice.** See clause 7.
- `xmip-core-resilience` **moves to Capability**, mounting at
  `module/capability/resilience` with its six technologies. Both tests agree:
  a Message waits for a retry and for a timeout — the guard runs inside the
  attempt and nothing proceeds until it decides (ADR-0048) — and nothing
  starts, supervises or stops the crate itself. **The repository name, the
  crate name and the URL do not change** (ADR-0011: the domain explains a
  repository and does not name it). `xmip-core-resilience` it remains; only
  its mount path and its `architecturalDomain` move.

### 6. What this decides inside `xmip-core-runtime`

A file is tested the same way a repository is.

- `generation.rs` **stays, and the reason is the interesting one.** It
  defines what a Message generation is and the three treatments an artifact
  declares, so clause 1 reads it as Foundation, and `xmip-core-message`
  already owns `Message::generation`, `MessageCreationSource` and
  `MessageTreatment`. The move was made and then undone, because it made
  `xmip-core-message` depend on `xmip-core-journey`, and
  `xmip-core-message`'s own first page says *"Journeys reference Messages,
  never the reverse."* The edge is acyclic and clause 3 permits it —
  Foundation on Foundation — so nothing here is broken. It is the estate's
  stated direction pointed the other way at crate level, which is not a
  thing to do for a hundred lines of tidying while nobody is looking.

  What the file actually shows is that `ReceivedWork` is a **pair** and
  belongs wholly to neither crate, which is why it sat in the runtime in the
  first place. Two honest ways out, for the owner: split it, the three
  treatment constructors to `message` and `ReceivedWork` with the two
  `apply_*` functions to `journey`, which matches the stated direction
  exactly at the cost of a file named for two things; or rule that a crate
  edge from `message` to `journey` is not what that sentence was about, and
  move it whole. Until then it stays where it is, and this record says so
  rather than leaving a reader to wonder why the rule did not bite.
- `outcome.rs` **stays, deliberately.** `Arrived` is a definition and clause 1
  would send it to Foundation, but it quotes `authenticate::Refusal`,
  `authorize::Decision` and `route::Routing` at once. `xmip-core-context`
  cannot hold it without a cycle — all three already depend on context — and
  `xmip-core-journey` could hold it only by inverting the estate's direction.
  Clause 3 decides it: it stays with the crate that composes the three. This
  is an answer, not an omission.
- `wire.rs` **stays, and this is the second time that has been decided.**
  `xmip-core-abi`'s own `operate.rs` ruled on 2026-09-06 that the one
  conversion between observe's enums and the header's integers lives at the
  runtime bridge, *the single place that has both*. The rule agrees: moving it
  to `abi` would make a Foundation crate depend on `xmip-core-observe`, which
  is Operation, and clause 3 forbids that outright.
- `execution_tree.rs` **stays.** It is the plan of what this node starts,
  built from the node's configuration and validated before anything is
  spawned. Clause 2 places it, and ADR-0018 already did: the runtime is where
  Service and Host were folded together *because it already owns
  `ExecutionTree`, `HostServicePlan` and `HostBitness`*.

The rest of the crate — `arrival`, `departure`, `engine`, `host`,
`registration`, `capability_registry`, `service`, `start`, `operate` — is the
node acting, and stays without further argument.

### 7. `xmip-core-schedule` stays, and what it waits for is now written down

A six-line crate with no public API is either a placeholder with a purpose or
clutter, and the estate's own records say which. Open problem 23 names it in
the same breath as persistence: *`xmip-core-persist` is types and a trait only
— with no backend implementing it. `schedule` is a stub; `resilience` is
types.* Its `architecture.toml` maturity is `planned`, not `reserved`, and the
recovery model already depends on it — *an inbound claim is an atomic rename,
so a schedule finds an artifact claimed-or-gone and moves on.*

So it is committed work that has not started, and the honest record is that it
**waits on a `RuntimeStore` backend**: a trigger that fires with nowhere
durable to record that it fired is a demonstration, not a scheduler. It is
retired only if problem 23 is answered without it. **Nothing is deleted by
this record**; a repository is never deleted by tooling or by an assistant
(repository-model.md section 8).

## Consequences

- Repository-model.md section 1 carries the test beside the Capability and
  Operation one, which is where anyone looking for it will look.
- `module/platform/` holds four mounts instead of five, and
  `module/capability/` nineteen instead of eighteen. `.gitmodules` gets a new
  `path` for resilience; **the submodule section name is left at its
  historical `modules/platform/resilience`**, because the name is what
  `.git/modules/` is keyed by and renaming it breaks the checkout. Every
  section name in that file is already historical — they are all plural where
  the paths are singular — and the tooling reads `path` and `url` and never
  the name.
- `architecture.toml` moves resilience to `architecturalDomain = "Capability"`
  and `repositoryRole = "common-capability"`, which is the pairing all
  eighteen other Capabilities use. `Sync-XmipEstate -Compose` computes the
  mount from that field, so the manifest and the tree agree again.
- `xmip-core-message` gains a dependency and four tests; `xmip-core-runtime`
  loses a file. Dependencies track `main` (ADR-0005), so message lands before
  runtime can be verified against it, and `Publish-XmipChange` already orders
  that.
- **Clause 3 is a ratchet on ten crates that already satisfy it.** The day a
  Foundation crate is offered a Capability dependency, this clause is what
  refuses it, and the alternative — composing in the crate that already has
  both — is named here rather than discovered under pressure.
- **Not decided here.** Whether Technology deserves the same treatment (it has
  ADR-0010 and section 5b and has not gone wrong), and whether a sixth domain
  is ever warranted. Named so the gap is on the record.

## Alternatives considered

**Leave the test unwritten and move resilience anyway.** It is the smaller
change and it fixes today's instance of a recurring failure. The recurrence is
the point: `retain` was misplaced for a month, resilience for longer, and both
for the same reason — the estate had no sentence to check a repository
against. A move without a rule is a move that will be re-argued.

**"Platform is what has no domain model."** Tempting, and it puts `configure`
and `persist` in Platform immediately. It also puts `abi` there, which is a
binding and plainly Foundation, and it gives no answer at all for a crate that
is types today and a service next month. It describes the current contents
rather than testing a candidate.

**Split the difference: make Platform a layer rather than a domain.** Every
crate is Foundation, and Platform becomes a marker for what the node starts.
It is tidier on paper and it loses the thing the domains are for — a
navigable tree an operator and a newcomer can read (section 7). Forty-four
mounts in one folder is the wall that grouping exists to prevent.

**Retire `xmip-core-schedule`.** Six lines, no API, no consumer. Open problem
23 says otherwise: the recovery model already leans on a schedule, and the
manifest calls it `planned` rather than `reserved`. Retiring it would delete
the only place that work is declared and would be re-declared within the
quarter.

## Provenance

The instruction is the owner's, 2026-09-19: *Let's consolidate, refactor and
re-engineering. Especially between platform and foundation. It seems to me
that there is too much in platform.* — and, when offered a list of candidates
to strike instead of an action, *Give it one more go.* Both are quoted above
in his words.

The test itself, the four clauses, the crate-by-crate verdicts and the two
*stays, deliberately* answers are the assistant's drafting. Two of the
findings are the estate's own and only had to be read: `xmip-core-abi` had
already decided where the observe conversion lives, on 2026-09-06, and
ADR-0018 had already decided that the runtime owns `ExecutionTree`. Neither is
reopened here.

The record is Proposed rather than Accepted until the owner says so, and the
move it describes is on disk and uncommitted for him to read first.

## Amendment, 2026-09-19: clause 7 is superseded — three empty mounts are gone

The owner, 2026-09-19, told that `module/platform/schedule` is a six-line
stub: *So delete what we do not need, we are in a design phase.*

**Clause 7 above is superseded.** It kept `xmip-core-schedule` *on notice*,
and the alternative it rejected — *Retire `xmip-core-schedule`* — is the one
now taken. The reasoning of clause 7 was that retiring it would delete the
only place that work is declared. That is not what happened and not what the
clause weighed: the work is declared in open problem 23 and in the recovery
model, and those declarations are untouched. What is gone is the mount.

Three repositories go, not one. Each held a single `lib.rs` whose entire body
was a doc comment ending *"No public ... API is implemented yet"*, and nothing
in the estate depended on any of them in code:

- `xmip-core-migrate`, mounted at `module/capability/migrate`, with ten
  technologies declared under it and none written.
- `xmip-core-diagnose`, mounted at `module/operation/diagnose`.
- `xmip-core-schedule`, mounted at `module/platform/schedule`.

**A repository that holds no implementation is a name the estate pays for on
every clone, every landing and every survey** — a recursive submodule update
fetches it, `Publish-XmipChange` orders it, `Get-XmipStatus`
reports it, and the Rust style rule measures it. It buys nothing back, because
the name it reserves is already kept by the record that plans the work.
Declaring a thing and mounting a thing are two acts, and only the second one
has a running cost.

**The three GitHub repositories still exist and are untouched.** Only their
mounts and declarations are gone, and while they exist on GitHub
`Sync-XmipEstate` reports them as unexpected, which is true: the manifest's
list of retired repositories that once hid them is gone too (ADR-0060,
amendment 2026-09-26). Nothing in this record deletes a repository;
repository-model.md section 8 still holds, and whether these three should be
deleted on GitHub is the owner's call and nobody else's.

**What brings each back is a first implementation.** Write one, and
`Sync-XmipEstate` re-creates the declaration and `-Compose` re-mounts it at the
domain the manifest gives it. For `schedule` that first implementation waits on
a `RuntimeStore` backend, exactly as clause 7 said — a trigger with nowhere
durable to record that it fired is a demonstration, not a scheduler.

Counts, against the Consequences above: `module/platform/` holds three mounts,
not four; `module/capability/` eighteen, not nineteen; `module/operation/`
seven, not eight. The estate is forty-one submodules, not forty-four. The
manifest declares 330 repositories, not 343 — the ten unwritten `migrate`
technologies go with their parent.

Status stays Proposed. This amendment is the assistant's drafting on the
owner's instruction, which is quoted above in his words.

## Amendment, 2026-09-22: three repositories are the homes of three capabilities

On 2026-09-21 the owner ruled that nothing is released and there is no point
holding on to old repositories, and `xmip-core-exclusiveness` and
`xmip-core-webapi` were deleted on GitHub. The three this record unmounted
were not: each is retained as **the only home for Xmip's own code of its
capability**, and each stays unmounted until the first of that code is
written, because the rule keeps the name and not an empty mount.

**Only home means Xmip's own.** The owner: *Third parties may create their own
repos regarding all repos.* A third party may keep migration, scheduling,
diagnosis — or any capability the estate has — in a repository of its own
under its own provider name, as ADR-0011 names them. What the rule forbids is
Xmip putting that code anywhere else in its own estate.

**`xmip-core-migrate` is the home of migration.** The owner: *xmip-core-migrate
is the home for migration code.* Migration is moving integrations built on
another platform onto Xmip. Searched on 2026-09-22, no code in the estate
does any.

**`xmip-core-diagnose` is retained, and diagnosis lives there.** The owner,
the same day: *xmip-core-diagnose shall also be kept and diagnosis code shall
be moved to it if there are any.* Diagnosis is explaining why a running
node, Journey or endpoint is in the state it is — ADR-0025's Operation
capability, which observes the path and does not carry it — and no
repository holds any. Searched on 2026-09-22, the nearest thing is
`ModuleProbe` in `xmip-core-abi`, behind `xmip probe` and the PowerShell
probe, and it is not diagnosis: its own summary calls it the first rule of
ADR-0012's section 11 conformance suite, which checks that a module honors
the boundary, and its home is the conformance repository the specification
names. A contract's `diagnostics` in the ABI are its findings about content,
which is validation. Nothing moves; the first diagnosis Xmip writes goes to
`xmip-core-diagnose` and brings the mount back.

**`xmip-core-schedule` is retained, and scheduling lives there.** The owner,
the same day: *xmip-core-schedule shall be retained and the scheduling code if
any done shall be in this repo.* Scheduling is what decides when work runs —
a timer, an interval, a polled pickup — and no repository holds any: searched
on 2026-09-22, the estate has none. `Arriving::Scheduled` in `xmip-core` is
not scheduling and stays where it is; it is the name of how a Stream arrived,
a noun the identifying capabilities read, and Foundation is where nouns live
(clause 1). The timer that will produce it is the first thing
`xmip-core-schedule` holds, and it brings the mount back.

## Amendment, 2026-11-13: `xmip-core-cluster` is Platform, and the layers are tested

**Provenance.** The owner agreed on 2026-11-07, the cluster's
consolidation put to him (open problem 19, *Cluster coordination*):
*xmip-core-cluster moves from Foundation to Platform — remounted at
module/platform/cluster, with an ADR-0058 section 5 amendment — because it
runs the sync plane (listener, member links, following). Its pure part,
Member, Membership, placement and Rotation, sits under
`default-features = false` for configure and persist. A feature `sync`
holds the running part. event keeps its Event conversation and stops
running a listener or depending on tls.* And, among the records of its
first piece, *a new test/Layer.Test.ps1 that checks layer direction and
that the graph is acyclic.*

- **Clause 5 is amended: Foundation keeps nine, Platform holds four.**
  `xmip-core-cluster` leaves Foundation by clause 2: a cluster that listens
  for the other nodes, keeps a link to each and follows who they are is
  started, supervised and stopped, and its subject is the node; the sync
  plane moved in from `xmip-core-event` the same day, behind the feature
  `sync`. `module/platform/` holds four mounts: cluster, configure,
  persist and runtime.
- **Remounted as resilience was** (the Consequences above):
  `Move-XmipSubmodule` moved the working tree from `module/foundation/cluster`
  to `module/platform/cluster`; `.gitmodules` carries the new `path` and
  keeps the historical section name `modules/foundation/cluster`, which
  `.git/modules/` is keyed by; `architecture.toml` says
  `architecturalDomain = "Platform"` and `repositoryRole =
  "platform-service"`, so `Sync-XmipEstate -Compose` computes the same
  mount. The repository, the crate and the URL do not change (ADR-0011).
  Every caller depends on it by its URL, so no caller's `Cargo.toml`
  changes for the move, and the local patch reads the new path from
  `.gitmodules` (`New-XmipLocalPatch`).
- **Its pure part opens nothing.** `Member`, `Membership`, `place` with its
  `Candidate` and `Unplaced`, `Rotation` and `ClusterError` start no
  thread, open no socket and read no clock, so `xmip-core-configure` and
  `xmip-core-persist` take them with `default-features = false` (ADR-0056,
  amendment of this date). `Member` and `Membership` moved from
  `xmip-core-event`'s `cluster` module, with no copy and no re-export left
  there. The timing the sync plane keeps is in it too (`Timing`, every
  bound a `[tuning]` key), so a node reads its `[tuning]` without the
  network.
- **The running part is the default feature `sync`**: the sync plane,
  moved the same day from `xmip-core-event`'s `cluster` module whole —
  the listener, the link to each member, the following
  (`xcluster::sync::Plane`; ADR-0065 and ADR-0067, amendments of this
  date). The dependency runs one way: `cluster`'s `sync` depends on
  `event`, which keeps its Event conversation, runs no listener and
  depends on neither `cluster` nor `tls`. While `Member` and `Membership`
  had moved and the plane had not, `event` depended on `cluster` for them,
  Foundation on Platform; the plane's move ended it the same day.
- **The layers are tested** (`test/Layer.Test.ps1`). A repository's layer
  is its domain, and a Technology's its parent's, so a Library's
  technologies are Library. Over what each mounted repository's build uses
  and what the manifest declares for the rest, the test holds: the graph is
  acyclic (repository-model.md section 4); Library depends only on Library;
  Foundation only on Foundation and Library (clause 3); a Capability on
  none of its own Technology children, and a Platform repository on no
  Technology but a Library's (repository-model.md section 4). **That
  clause 3 admits a Library is the assistant's reading**, drafted with the
  test: a Library is the estate's own third-party code, holding no noun of
  Xmip's, and five Foundation crates — `context`, `journey`, `message`,
  `node` and `event` — took `xmip-core-library-codec` with the manifest
  declaring it; read otherwise, clause 3 had been broken since before it
  was written.
- **What the test found, the day it was written.** Five dependencies
  break clause 3 and are listed in the test with the record each stands
  on; the list may shrink and never grow, and an entry for a breach that
  is gone fails too. Four are `xmip-core-event`'s: `audit`, `observe`,
  `authorize` and `resilience`, each taken after clause 3 called the
  domain clean — Events audited (ADR-0062), a subscriber authorized
  (ADR-0065 clause 4), a scope and an act observe's, a forwarder retrying
  under the guards (ADR-0065 clause 3) — and nothing said so, because
  nothing looked. The fifth is `xmip-core-sdk` on `xmip-core-transport`,
  whose simulators are a transport's far ends (ADR-0061, amendment
  2026-09-24). None is answered here. A sixth, `event` on `cluster`, was
  listed while the members had moved and the plane had not, and left the
  list with the plane.

Built 2026-11-13, the assistant's: the remount, the pure part
(`xmip-core-cluster`'s `member.rs`, `placement.rs`, `rotation.rs`,
`timing.rs`), the sync plane under `sync` (`sync.rs`, `sync/serving.rs`,
`sync/upstream.rs`) and `test/Layer.Test.ps1`.

## Amendment, 2026-11-13: membership is kept by persist, written and followed by the runtime, and said by the cluster

**Provenance.** The cluster consolidation the owner agreed on 2026-11-07:
*runtime implements cluster::Membership over* the administration database;
the design he approved on 2026-11-12, section 3.2 (ADR-0056, amendment of
this date, says what is built).

Each of the three Platform repositories holds one part, and none a second
copy of another's:

- **`xmip-core-persist` keeps the rows**: the administration database's
  `membership` table, its typed row `storage::MemberRecord`, the two
  operations that write a row and read the members now
  (`XmipStorage::write_member`, `read_members`, wire operations 44 and 45,
  answer 31), and the wait on the table (`Watched::Membership`, kind 6 of
  wire operation 37). It reads no word of a row: what a role or an
  evidence line means is `xmip-core-node`'s.
- **`xmip-core-runtime` writes and follows them**: a node activated writes
  its row and follows the table (`runtime::membership`, `Joined` and
  `Followed`), and `Followed` implements `xcluster::Membership`, reading a
  member's capability back from its evidence through `node::Capability`'s
  one reading. The flag on a save not its peers' (`peers_save`) is the
  runtime's, beside the rows it reads, since `Member` carries no save.
- **`xmip-core-cluster` says what a member is** (`Member`, `Membership`),
  as the amendment above placed it, and depends on neither of the other
  two.

## Amendment, 2026-11-13: `xmip-core-sdk` is a Capability, and its breach is gone

**Provenance.** The owner, 2026-11-13: *Do we have all code in the modules,
repos that we should. This is a refactoring statement*, and, shown what the
placement review found: *Good that you found it, fix it*. The reading below
is the assistant's; ADR-0061, amendment of this date, holds it in full.

- **Clause 4 places it.** The manifest declared `xmip-core-sdk` Foundation,
  and its simulators depend on `xmip-core-transport`, a Capability: the
  fifth breach the amendment above listed. Asked in clause 4's order, the
  message-path test answers first. Every CAN technology opens its bus on
  `sdk::broadcast` where the build has no kernel CAN interface
  (`xmip-core-transport-can-bus`'s `open_bus`), and HART its `loopback`
  line on `sdk::serial`, in production code, so a Message on such a
  Location waits for the simulated medium: the SDK is a Capability. The
  code stays; `architecture.toml` says `architecturalDomain =
  "Capability"` and `repositoryRole = "common-capability"`, and the
  declared mount, `sdk/`, does not move (ADR-0061 decision 3).
- **What stands now.** Foundation is the nine the amendment above leaves
  it, and the manifest declares no other: `xmip-core`, `abi`, `stream`,
  `message`, `context`, `journey`, `node`, `party` and `event`.
  `test/Layer.Test.ps1` lists four breaches, all `xmip-core-event`'s; the
  SDK's dependency on the transport capability is a Capability's on a
  Capability, which the rules admit, and its entry left the list in this
  change.

## Amendment, 2026-11-13: `xmip-core-schedule` holds the estate's first scheduling, and is mounted again

**Provenance.** The owner, 2026-11-13: *Do we have all code in the modules,
repos that we should. This is a refactoring statement*; shown what the
placement review found, *Good that you found it, fix it*. The 2026-09-22
amendment above made `xmip-core-schedule` scheduling's only home in the
estate — *the scheduling code if any done shall be in this repo* — and
said that searched that day the estate had none. Searched again on
2026-11-13 it had two pieces, both in `xmip-core-runtime`, both written
after that search; this amendment takes the home up. The reading below is
the assistant's.

- **What moved, and nothing copied.** From `xmip-core-runtime`: the rest a
  Receive Location takes before it asks its transport again,
  `src/receiving/pace.rs` whole (`Pace` and its `rest`, `Asking`, `Ended`,
  and the `[tuning]` defaults `RECEIVE_POLL`, `RECEIVE_SWEEP` and
  `RECEIVE_BACKOFF`), with `RECEIVE_DRAIN` from `src/receiving/drain.rs`,
  the fourth default `Pace` holds, to `schedule::pace`; and when a Send
  Port queue's earliest retry is due, from `src/send_step/due.rs` — `Due`
  and its rules: the earliest kept, counted by the newest read, a due time
  a hand-on noted kept across a read under way, and the earliest the send
  step wakes for — to `schedule::due`. The runtime's `receiving.rs`,
  `send_step.rs` and their parts call it, by its own paths; there is no
  re-export.
- **What stays in the runtime is the waiting and the work.** The rest is
  waited on the node's stop and the drain run there (`receiving.rs`,
  `receiving/drain.rs`); the send step keeps one `Due` per queue under its
  lock, reads Xmip Storage for it and wakes (`send_step/due.rs`). The
  Work Process step's dispatch (`work_step/dispatch.rs`) stays whole: it
  decides with the runtime's pool, pickup, admission and turning, and
  moving it would make `schedule` depend on the runtime, which depends on
  `schedule` — a cycle (repository-model.md section 4).
- **A Capability, at `module/core/capability/schedule`.** By clause 4's
  order the message-path test answers first: a Message waits for the rest
  and for its retry's due time, so the repository is a Capability
  (`common-capability`), and not Platform, where it was mounted until
  2026-09-19 (`module/platform/schedule`). Clause 2's *fires a timer* is
  still Platform: the waiting is the runtime's. `schedule` decides and
  waits for nothing, opens nothing and depends on nothing. Declared in
  `architecture.toml` as `[xmip.core.schedule]` and mounted by
  `Sync-XmipEstate -Compose`; the runtime's dependency is optional and
  taken by its `node` feature.
- **The condition of the 2026-09-19 amendment is met.** It said the first
  implementation waits on a durable store, since a trigger with nowhere
  durable to record that it fired is a demonstration. A retry's due time
  is kept in the Ledger at its place in its queue (`runtime-model.md`
  section 10), and `schedule` holds only what a node decides from it.
- **What stands.** `Arriving::Scheduled` stays in `xmip-core` (the
  amendment of 2026-09-22). The timer that will produce it is not written;
  when it is, it is written here.

## Amendment, 2026-11-13: `xmip-core-node` opens no file, and a declaration's file is the runtime's

**Provenance.** The owner, 2026-11-13: *Do we have all code in the modules,
repos that we should. This is a refactoring statement*; shown what the
placement review found, *Good that you found it, fix it*. The reading below
is the assistant's.

- **Clause 1 found it.** `xmip-core-node` is Foundation, and nothing in a
  Foundation crate *starts, opens, spawns, reads a file*. Until this day
  its `declaration.rs` made a directory, wrote a System Process's
  declaration file and removed it when dropped, and its `standing.rs`
  listed a directory and read every file in it: the one writer and reader
  ADR-0053's amendment of 2026-09-27 placed there.
- **What moved, and nothing copied.** To `xmip-core-runtime`'s
  `src/declared.rs`: `DIRECTORY_VARIABLE` and `directory`, where every
  process on the machine meets; `declare` and `declare_in`, methods of
  `Declaration` until then and functions over one now; `Declared`, the
  declaration standing while it is held and taken away when it is dropped
  or `handed_over` across the C boundary; and `standing`, the listing of a
  directory. No re-export and no shim is left in node.
- **What stays in node is the definition**: `Declaration`, `Purpose` and
  `KEYS`, the refusal of a name that is no System Process's, `with`,
  `to_toml`, the text a declaration is written as, and `Standing` with
  `Standing::read`, the one reading of that text. Pure functions over the
  shape, as clause 1 admits.
- **Who calls the runtime for it.** Its own section 13 exports
  (`ffi::process`) and the wait a surface's local call learns from the
  node serving it (`plane::deadline`); `xmip-service`
  (`.src/service/run.rs`); and the Essentials, whose roll, cluster and
  nodes declare through one function, `process_audit::declared`, which now
  writes the declaration where each of the three had made the call itself.
  The .NET surfaces and the estate's PowerShell module reached the file
  only through section 13 and change nothing; the file's name, place and
  text are unchanged.
- **Held by a test.** `test/Foundation.Test.ps1` reads the production code
  of every crate mounted at `module/foundation` and fails on a line that
  reaches the file system. It found none once node's moved; clause 1's
  other verbs — start, spawn, wait on a clock — it does not read.

## Amendment, 2026-11-13: Event delivery is the cluster's, and the last of clause 3's breaches is gone

**Provenance.** The owner, 2026-11-13: *Do we have all code in the
modules, repos that we should. This is a refactoring statement*; *Good
that you found it, fix it*. Where delivery goes is the assistant's, in
the placement plan put to him the same day.

- **`xmip-core-event` is a noun again.** What an Event is stays
  Foundation: the Event and its taxonomy, the one subscription rule
  (`filter`), the wire form (`wire`, `json_format`, `binding`) and the
  `Wire` a transport carries it over. It depends on `xmip-core`,
  `xmip-core-node` and `xmip-core-library-codec` alone.
- **Delivering it is a lifecycle, so it is Platform's**, by clause 2: the
  hub a process holds and every subscriber is admitted to, the queue per
  subscription, the listener's thread, the forwarder pumping a
  subscription over a wire, an operator's acts and the audit of each are
  started, held and stopped for a node. They moved whole into
  `xmip-core-cluster`, beside the sync plane that already carried the
  cluster's Events: `delivery`, behind the feature of that name, on by
  default and included by `sync`, and the Event link's conversation as
  `sync::link`, compiled with `delivery` because the hub keeps its taps
  and carriers by it (ADR-0065, amendment of this date). No copy and no
  re-export is left in `event`.
- **The four breaches the layer test listed for `event` are gone**:
  `audit`, `authorize`, `observe` and `resilience` were delivery's, and
  `xmip-core-cluster` takes them, a Platform repository on a Capability
  and on Operation, which the rules allow. The scope rule an Event's
  filter asks is `xmip-core-node`'s since the same day (ADR-0027,
  amendment of this date), so the filter took none of them.
  `test/Layer.Test.ps1` lists no breach now.

Built 2026-11-13, the assistant's.
