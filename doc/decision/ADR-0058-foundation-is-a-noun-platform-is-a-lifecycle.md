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
since 2026-08-26, and it works: *if a Journey waits for it, it is a
Capability*. It moved `xmip-core-retain` out of the wrong domain within a day
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
Journey waits for it, it is a Capability), then the observation and governance
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
  a Journey waits for a retry and for a timeout — the guard runs inside the
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
mounts are gone. `architecture.toml` moves each to `[[retired]]`, which is the
estate's own mechanism for a repository that is archived rather than deleted —
without it the retirement reports as drift forever (ADR-0024, and the
`xmip-core-exclusiveness` episode that taught the estate retiring and
unmounting are separate actions). Nothing in this record deletes a repository;
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

## Amendment, 2026-09-22: xmip-core-migrate stays

On 2026-09-21 the owner ruled that nothing is released and there is no point
holding on to old repositories, and `xmip-core-exclusiveness` was deleted on
GitHub. Of the three this record unmounted, the owner then set a condition
on one: *xmip-core-migrate shall stay if not migration from other platforms
is implemented in any other repo.*

Nothing implements it. No Rust, C# or PowerShell in the estate names BizTalk,
MuleSoft or any other platform to move from, so the condition holds and the
repository stays on GitHub. It stays unmounted as this record left it — the
rule is about keeping the name, not about paying for an empty mount — and it
is not to be deleted while the condition holds. The day another repository
implements migration from other platforms, the question is open again.

**`xmip-core-diagnose` is retained, and diagnosis lives there.** The owner,
the same day: *xmip-core-diagnose shall also be kept and diagnosis code shall
be moved to it if there are any.* Diagnosis is explaining why a running
node, Journey or endpoint is in the state it is — ADR-0025's Operation
capability, which observes the path and does not carry it — and no
repository holds any. Searched on 2026-09-22, the nearest thing is
`ModuleProbe` in `xmip-core-abi`, behind `xmip probe` and the PowerShell
probe, and it is not diagnosis: its own summary calls it the first rule of
ADR-0012's section 11 conformance suite, which checks that a module honours
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
