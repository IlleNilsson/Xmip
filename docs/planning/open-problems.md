# Xmip — Open Problems and Possible Solutions

Options per problem, with a lean. Nothing here is decided.

---

# Blocking now

## 1. Eight orphaned tests hold the build red

Every `.rs` file in `tests/` imports `xmip_linear_kernel`, the crate's pre-narrowing name.
They reference modules `src/lib.rs` does not publish. One, `xmip_message_model`, names a
module that no longer exists in `src/` at all.

| option | effect | cost |
|---|---|---|
| **A. Delete all eight** | build green today | loses nothing that currently runs; git keeps the history |
| **B. Move to `attic/`** | build green, files stay visible | a folder of code that compiles against nothing |
| **C. Restore them** | keeps the coverage | must publish ~40 modules from `lib.rs`; one test is unfixable regardless |

**Lean: A.** Eleven unit tests inside `journey_model`, `transport_technology` and
`vertical_slice` still run and cover the live architecture. B only makes sense if you want to
read the old design without `git log`.

## 2. Roughly forty files in `src/` are published by nothing

`src/lib.rs` exposes four modules — `contracts`, `journey_model`, `transport_technology`,
`vertical_slice`. `src/` holds about forty-five files.

**First, one command**, because it decides everything:

```powershell
Select-String -Path src\main.rs -Pattern '^\s*(pub )?mod ' | ForEach-Object { $_.Line }
```

| if main.rs... | then | option |
|---|---|---|
| declares them | they are live, owned by the binary | leave, or move the shared ones into the library |
| does not | forty files compile in nothing | **A.** delete · **B.** move to `attic/` · **C.** publish incrementally from `lib.rs`, fixing as you go |

**Lean: B if orphaned.** Deleting forty files of design work outright is harsher than parking
them. Moving them out of `src/` stops them reading as live code, which is the actual harm.

## 3. Edition mismatch

`cratePolicy` says edition 2024. The workspace `Cargo.toml` says 2021. Toolchain is 1.94.1,
so both are available.

| option | effect |
|---|---|
| **A. Move the workspace to 2024** | matches stated policy; a real migration with borrow-checker and prelude changes |
| **B. Change `cratePolicy` to 2021** | one-line honesty fix; policy follows reality |

**Lean: B now, A later.** Do not attempt an edition migration while the build is red. Make
the manifest tell the truth today, migrate deliberately once green.

---

# Structural — naming and boundaries

## 4. `assign`, `promote`, `demote` sit in Capabilities with zero implementations

"Capabilities" means *things Xmip does*, and these do things — but nothing about them is
pluggable, so they have no vendor and no trait to implement.

| option | effect |
|---|---|
| **A. Reclassify to Foundation** | honest about what they are; no code change |
| **B. Give them a plugin surface** | an assignment strategy becomes pluggable — real, but nobody has designed it |
| **C. Fold into `xmip-core-path`** | they are all path-driven operations |

**Lean: A.** C is tempting but wrong — they are artifact-level verbs in the journey, and
`path` is an addressing capability. B is the long-term answer if a second assignment strategy
ever appears; until then it is speculation.

## 5. `transport` carries 44 of the 246 implementations

One repository per protocol is correct. It also means one module owns a third of the build
and support burden permanently.

| option | effect |
|---|---|
| **A. Leave the naming, tier the execution** | declare 44, build six, mark the rest `maturity: reserved` |
| **B. Group families into shared repositories** | `aws-*` in one repo — fewer repos, breaks one-repo-one-release |
| **C. Split by transport kind** | `transport-queue`, `transport-file`, `transport-stream` — reintroduces classification into names |

**Lean: A.** The manifest already has `maturity`, and declaring is not building. C is the one
to avoid: it puts a judgement back into the name, which is exactly what the manifest exists
to prevent.

## 6. `logic` has three implementations and an unclear trait

Smallest capability with a plugin surface. Arrived via PR #32 and has not been stress-tested.

**The test:** state the trait in one sentence. If it can't be stated without describing
`process`, it isn't a capability.

| option | effect |
|---|---|
| **A. Fold into `process`** | one fewer module; `process` gains method semantics |
| **B. Keep and define the trait** | needs the one-sentence answer first |

**Lean: run the test before choosing.** This is the module most likely to be a feature
wearing module clothes.

## 7. The Operations tier is five near-identical modules

`audit` 9, `report` 6, `observe` 5, `retain` 5, `archive` 5 — and their technology lists
overlap heavily: postgres, s3, elasticsearch and otlp keep reappearing.

| option | effect |
|---|---|
| **A. Leave** | five policies genuinely differ, even if adapters repeat |
| **B. Merge into one `record` module with modes** | fewer modules; conflates retention policy with audit semantics |
| **C. Keep five modules, share a store trait** | the adapters stop being written five times |

**Lean: C.** The duplication is `postgres` appearing five times, not the modules. A shared
store trait in `xmip-core` — or a `store` surface module — removes the repetition without
pretending archive and audit are the same concern.

## 8. Cloud vendor prefixes are inconsistent

`aws-sqs` and `azure-blob` carry a vendor. `s3` and `gcs` do not.

| option | effect |
|---|---|
| **A. Always name the vendor** | `aws-s3`, `google-gcs`, `azure-blob` — consistent, slightly longer |
| **B. Never, where the product name is unique** | `s3`, `sqs`, `blob` — shorter, but `blob` alone is meaningless |
| **C. Vendor only on collision** | shortest, but requires knowing the whole namespace to name one thing |

**Lean: A.** "One meaning per token" is much easier to hold when the vendor is always present.
C fails the test that a namer should not need global knowledge.

## 9. `resilience` and `exclusiveness` are alone in the Platform tier

And `resilience` has no plugin surface in practice, despite six declared implementations.

| option | effect |
|---|---|
| **A. Leave** | the tier is small but the definition fits |
| **B. Move both to Capabilities** | dissolves the Platform tier |
| **C. Move Operations' shared store concern here** | gives the tier a third member with a real reason |

**Lean: A, revisit with 7.** If C happens, the tier earns its place.

---

# Repositories and code

## 10. Three modules declared with no repository

`xmip-core-abi`, `xmip-core-transport`, `xmip-core-logic`.

| option | effect |
|---|---|
| **A. Create all three** | manifest and reality agree |
| **B. Create `abi` only** | it is needed by the boundary; the other two are undesigned |

**Lean: B.** Do not create repositories for capabilities whose traits are unsettled — see 6.
Run `Sync-XmipEstate.ps1` with `-WhatIf` first regardless.

## 11. `xmip-module-api` and `xmip-module-abi` still exist

`xmip-module-api` re-exports `xmip_core::contracts::*`, which is what pulls implementers into
Rust and into AGPL by linkage. `xmip-module-abi` still carries `ModuleAbiKind`, removed by
clause 5 of ADR-0012. Its package is named `xmip-abi`, disagreeing with its directory and
with `cratePolicy.primaryCrateMatchesRepository`.

| option | effect |
|---|---|
| **A. Consolidate into `xmip-core-abi` now** | one crate, correct name, boundary matches the header |
| **B. Wait for the first real module** | avoids churn, but the contradiction stays in the tree |

**Lean: A, once the build is green.** Blast radius is small — two consumers,
`xmip-handler-file` and `xmip-host`. And you can now verify it with `cargo build`, which you
could not before.

---

# Runtime safety

## 13. Nothing bounds a publication chain

A Process may publish back into Xmip. A Subscription may start a Process. So a
Process that publishes a Message matching a Subscription that starts the same
Process is a loop, and today the runtime has no depth limit, no cycle detection
and no execution budget.

Recovered from `message-runtime-context.md` during the ADR-0020 consolidation,
2026-08-26, where it sat as two of six unanswered questions: how are
Subscription Instance chains bounded, and how are repeated publication chains
controlled. Neither was ever answered.

This is the classic way an integration platform takes itself down, and it does
it at three in the morning with a message that looked ordinary.

| option | effect |
|---|---|
| **A. Depth limit on the Subscription Instance chain** | simple, cheap, catches the direct case; a long legitimate chain and a loop look identical near the limit |
| **B. Cycle detection over artifact identities** | precise — the same Subscription firing twice for one lineage is the actual signal; needs the chain persisted and walked on every publication |
| **C. Execution budget per originating Message** | covers loops and runaway fan-out together, in one number an operator can reason about; the number is arbitrary until someone has production data |
| **D. Publication generation counter with a ceiling** | cheapest to implement, and it is A wearing a different name |

**Lean: A now, B later, C eventually.** A is one integer on the chain and can
ship with the chain itself. B is the correct answer and needs the chain to be
persisted and cheap to walk, which is a `xmip-core-persist` question. C is what
an operator actually wants — "this Message has cost enough" — but the budget
number is unguessable before there is traffic to measure.

Whichever wins, the failure must name the cycle, not just refuse: the operator
needs the Subscription and the Process that formed the loop, or they are
reading configuration files at three in the morning.

**Also unanswered from the same document**, and smaller: what exactly is
preserved, what exactly is recovered, the canonical representation of Message
content at each lifecycle stage, and whether a Message Contract is a first-class
Artifact Definition or a module-provided validation capability.

---

# The ToDo

## 17. How does work reach another node?

A ToDo is per node and written only by its owner, which is what removes the
shared write path BizTalk's MessageBox never escaped. The cost is that a Message
in node A's ToDo is node A's work, and nothing moves it.

That is fine for an estate where each node owns its own Receive Locations. It is
not fine when a Receive node should hand processing to an Executing node, which
`deployment-model.md` node capabilities explicitly anticipate.

| option | effect |
|---|---|
| **A. Nodes hand off over the Xmip node-to-node protocol** | explicit, auditable, and the Journey records the hop. Needs that protocol to exist — see problem 18 |
| **B. Receive nodes write directly into the target node's ToDo** | fewest moving parts, and it reintroduces the shared write path this design exists to avoid |
| **C. Work stays where it lands; placement decides at receive time** | no movement at all. Requires the receive-side configuration to know the whole topology, and a saturated node cannot shed load |

**Lean: A.** B is the BizTalk shape wearing a different name. C is defensible
for edge estates where the device that receives is the device that processes,
and it is probably right for the purpose-compiled runtime — but it cannot be the
only answer for a server cluster.

## 18. Where does a Cluster-scope exclusiveness lease live? — **Resolved**

*Resolved 2026-08-27 by ADR-0024, and by dissolving the question rather than
answering it.*

There is no cluster-scope lease to place because there is no lease.
`xmip-core-exclusiveness` is retired and `ResourceClaim` in
`xmip-core-transport` replaces it: the endpoint's own atomic claim is
cluster-wide already, because the endpoint is one thing however many nodes are
asking, and the shared write path it needs is the partner's storage rather than
Xmip's.

All four options recorded here shared one assumption — that Xmip had to keep
the fact. It did not; the fact already had an owner.

Two nodes on a lockless protocol (FTP, SFTP, IMAP) is what remains, and
ADR-0024 clause 6 makes it a placement question: run one of them. The shape of
that placement is undecided and belongs with Host Services.

---|---|
| **A. One node holds the cluster lease store** | simple; that node is now a single point of failure and a shared write path for exactly the thing that must not have one |
| **B. Consensus among nodes** | correct and honest about the problem. It is also a distributed-consensus implementation, which ADR-0017 spent its entire argument avoiding |
| **C. Cluster scope requires an external store, declared as such** | the five coordinators ADR-0017 removed, readmitted for one narrow purpose and only when Cluster scope is actually used |
| **D. Cluster scope is not offered** | Node scope and resource-native claims cover more than expected — the file case is already handled by claiming the artefact itself |

**Lean: D first, C as the escape hatch.** ADR-0017 clause 2 already says a
transport addressing a discrete claimable artefact claims the artefact, and that
claim is cluster-wide without any lease at all. The remaining need for true
Cluster scope may be small enough to make B's cost absurd. Worth counting the
real cases before building anything.

---

# Capabilities

## 16. Can a Receive Location bind to a discovered endpoint?

**Not a filing question.** `mdns`, `ssdp`, `dns` and `dhcp` are transports and
that is settled — `repository-model.md` section 5 explains why what a Stream
carries does not decide which capability moves it. Receiving an mDNS
announcement as a Stream that becomes a Message is transport, plainly.

The open question is the other feature, which uses the same protocols and is
not transport at all: **the runtime using discovery to find an endpoint and
bind a Receive Location to it.**

Today a Receive Location is configured with an address. On an edge or
industrial node the address is frequently not knowable in advance — the PLC,
the camera, the sensor gateway appears on the network and announces itself.
Configuration that requires a fixed address cannot express that.

| option | effect |
|---|---|
| **A. Nothing. Addresses stay static** | works for every estate where someone can write the address down. Rules out the edge case Xmip explicitly targets |
| **B. A Receive Location may declare a discovery predicate instead of an address** | *bind to whatever announces service type `_opcua._tcp` on this subnet*. Expressive, and it makes the set of Receive Location Instances change at runtime |
| **C. Discovery produces Messages; a Process creates the binding** | uses only what exists — an mDNS announcement is a Message, a Process reacts. No new configuration model, and the estate becomes self-modifying, which is worse |

**Lean: B, and it is a decision record when it happens.** It changes what a
Definition means: today a Receive Location Definition yields a known set of
Instances at startup, and under B the set is discovered and mutable. That
touches the Definition and Instance model in `runtime-model.md` section 21, the
execution tree built at startup in ADR-0018, and identity — an endpoint that
announced itself has claimed nothing, so ADR-0022's classes apply as
`anonymous` until something proves otherwise.

C deserves naming because it will look attractive: it needs no new concepts.
That is exactly its problem — an estate that reconfigures itself through its own
message flow has no configuration anyone can read.

---

# Configuration

## 14. The node configuration format

Two shapes are in the tree and they disagree. `[[modules]]` in the node TOML
against the Ansible template in `deploy/ansible/roles/xmip_node/templates/`,
which composes a different structure.

The `_origins` design export, mined 2026-08-26, proposed a third — and it is
the most complete of the three, so it belongs in the comparison rather than in
the bin:

```text
template.xmip.toml   reusable definitions
cluster.xmip.toml    the artifacts the whole cluster runs
xmip.toml            the node slice: what runs here
```

with the rule that a node slice declares *placement*, and templates and cluster
files declare *definition*.

| option | effect |
|---|---|
| **A. Flat node TOML with `[[modules]]`** | simplest; every node file repeats what the cluster already knows |
| **B. Ansible template composes it** | node files are generated, not authored; couples configuration shape to one deployment tool |
| **C. Three-file split, per the origin design** | definition and placement separate cleanly; three files to keep in step, and a resolution order to specify |

**Lean: C, but not by importing it.** The separation is right — a cluster-wide
definition repeated in forty node files is forty places to drift — and it is
what `xmip-core-configure` and desired state in `deployment-model.md` are
already reaching for. What C does not yet have is a resolution order: when the
cluster file and the node slice disagree, one of them wins, and nothing says
which.

**Explicitly not decided by finding it written down.** It arrived in an early
ChatGPT draft alongside the Artifact vocabulary and a Rust-only claim, both
rejected. Adopting one side of an open question because a draft happened to
answer it is how a question gets closed without being decided.

Recorded here rather than acted on. `_origins/` is deleted; git holds it.

---

# Governance

## 15. Succession

AGPL protects the code. The name, the GitHub account, the manifest registry and conformance
have no successor. Everything currently depends on one personal account.

| option | effect | cost |
|---|---|---|
| **A. Move to a GitHub organisation, add a second owner** | survives one person stopping | an afternoon |
| **B. DCO on contributions** | clean provenance for a future transfer | a file and a CI check |
| **C. Register the trademark** | protects the name specifically | money, jurisdiction-by-jurisdiction |
| **D. Written statement of intent** | says what should happen; not binding alone | an hour |

**Lean: A first, then B.** An organisation with two owners is the single cheapest thing that
changes the outcome if you stop — everything else protects assets that an organisation is
already holding. C matters only once someone else wants the name.

---

## 19. What `must-remember.md` still knew when it was retired

Carried in on 2026-08-30, when that file was deleted. Most of it had gone
false — it said the submodules were planned when 43 were real, that no module
loading existed when ADR-0025 had landed, that no identity implementation
existed when the three gates did. A next-steps list that is mostly wrong is
worse than none, because it is trusted exactly when nobody is checking.

Four of its items were still true, and this register is where they belong:

- **Journey replay end to end.** RocksDB and SQLite stores exist; the replay
  model over them is not implemented, and interchange history is not yet
  queryable. Related to problem 17 and to ADR-0024's open consequence on
  Journey recovery across nodes.
- **Cluster coordination.** No inter-node protocol, no failover execution.
  ADR-0024 dissolved the lease half; the placement half is ADR-0025's clause 6
  question and ADR-0018's Host Services, still undesigned between nodes.
- **A typed configuration loader.** `xmip-core-configure` exists;
  full validation against what the manifests declare does not — problem 14 is
  the format half of this.
- **The management plane.** `webapi` and `gui` are empty repositories,
  `powershell` carries a README. ADR-0014 decided their shape; nothing yet
  implements it.

---

# Suggested order

Rewritten 2026-08-30. The previous list was complete fossils — create
xmip-core-abi (exists), fix main.rs (deleted), orphaned tests (gone) — which
is what an order costs when nothing retires its entries.

```text
1. The GUI and the PowerShell module   market-position.md calls this the widest
                                       gap; both repositories are empty and
                                       ADR-0014 has already decided their shape
2. Protocol implementations            file, http, tcp, udp, smtp exist in the
                                       transport crate; 79 technology
                                       repositories are declared and empty
3. Journey replay end to end           problem 19, and the half of ADR-0024
                                       that stayed open
4. Cluster coordination and placement  problems 17 and 19; ADR-0025 clause 6
                                       says where it belongs, not what it is
5. xmip-core-webapi                    declared, mounted nowhere, one orphan
                                       gitdir — decide it lives or retire it
6. Cross-compilation                   four declared targets, verified on host
                                       only
7. Organisation and second owner       problem 15, independent of all the above
```

Problems 4, 5, 7, 8 and 9 remain naming judgements with no deadline. They cost
nothing to leave open and should not block the build work.
