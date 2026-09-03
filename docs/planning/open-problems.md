# Xmip — Open Problems and Possible Solutions

Options per problem, with a lean. Nothing here is decided.

**A problem keeps its number for life.** The numbers are cited from outside
this file — ADR-0024 cites 18, ADR-0014 cites 16, ADR-0002 and
`allocation.toml` cite 19 — so renumbering would silently repoint a citation at
someone else's problem. Sections are ordered so the numbers ascend; they are
not renumbered to make them.

There is no problem 12, and nothing is missing. A renumbering pass moved its
subject to 14 and Succession to 15 while the register was still small enough
for that to be safe. It is not any more, which is what the paragraph above is
for.

**Resolved problems stay**, at the end, with what resolved them. A register
that deletes its answers cannot be told from one nobody has read.

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

---

# Runtime safety

## 13. Nothing bounds a publication chain — **option A landed**

*Option A landed 2026-09-03 as ADR-0026. B and C stay open, which is what
the lean below said would happen.*

Every Journey carries a depth, a node configures a ceiling, and
`Journey::following` — the only way a chain grows — refuses the link that
would pass it, naming the Subscription and the Xmip Process rather than a
number. It was cheap because the chain did not exist yet: `following` was
called nowhere outside its own tests, so nothing publishes back into Xmip and
nothing can loop today. The bound shipped with the chain, exactly as the lean
said to do it.

What is still true below: a depth limit cannot tell a loop from a long
legitimate chain, cycle detection needs the chain persisted and cheap to walk,
and an execution budget needs traffic to measure. The trailing paragraph is
untouched by ADR-0026.

A Process may publish back into Xmip. A Subscription may start a Process. So a
Process that publishes a Message matching a Subscription that starts the same
Process is a loop. Before ADR-0026 the runtime had no depth limit, no cycle
detection and no execution budget; it now has the first of the three.

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

---

# Carried in from must-remember.md

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
- **The management plane.** `webapi` and `gui` are empty repositories.
  `powershell` no longer is — three cmdlets over the ABI and eighteen tests
  since 2026-09-03, seven of which hold the C# binding to `xmip_module.h`
  itself. ADR-0014 decided the shape of all of them; one of the four now has
  something behind it.

---

# The operator surfaces

## 20. An operator session is a host process, and nobody has said which

ADR-0014's amendment of 2026-08-26 made every operator surface a client of
the ABI, loaded in-process. So a PowerShell session calling it holds runtime
state, which makes it a host process — and ADR-0022 clause 3 says different
identity contexts must not share one.

The amendment recorded this in one sentence and left it: *that needs settling
before anything ships*. It was never filed here, so the register did not carry
it while two records were written on top of it. ADR-0027 adds a second reason
and settles nothing.

An operator is a person with a Kerberos ticket, or a service account, or a
shared secret in a script. The node they are operating runs identity contexts
of its own. Whether the session may sit beside them is exactly the question
ADR-0022 exists to answer, and it does not answer this one.

| option | effect |
|---|---|
| **A. The session is its own identity context, always isolated** | simple, and honest about what a session is; an operator surface can never run inside a Host Service, so a local GUI is a separate process |
| **B. The session inherits the context it authenticated as** | matches what an operator expects; makes co-residency depend on who is logged in, which is the property ADR-0022 says must be derived and never configured |
| **C. The surface holds no runtime state; it talks to the Xmip Service** | dissolves the question by reversing the amendment, and reintroduces the chokepoint the amendment removed |

**Lean: A, and it is close.** ADR-0022 derives a class from *how an identity is
proven*, and a session proves the operator, not the node. B is what people will
assume and it makes an isolation rule depend on a login. C is the one to argue
about properly, because it is the only one that questions the amendment rather
than working under it.

## 21. Packaging does not cover a surface that ships native libraries

The .NET surfaces P/Invoke a C ABI, so `powershell` and `gui` carry native
libraries per platform and per architecture — Windows, Linux, macOS, x64 and
arm64, and arm64 is not optional under ADR-0015.

ADR-0015 packages the **node**: MSI through winget, `.deb` and `.rpm`, an OCI
image, a portable archive. A PowerShell module is none of those. It is
installed from a gallery or a file share, by someone who is not installing
Xmip, onto a machine that may not have it.

Recorded by ADR-0014's amendment in one line — *ADR-0015 packages the node and
does not yet cover a PowerShell module shipping native binaries* — and filed
here on 2026-09-03, with the other two consequences it left loose.

| option | effect |
|---|---|
| **A. One module carrying every runtime identifier** | one artefact, works offline, and every operator downloads five platforms to use one |
| **B. A meta-module with per-platform packages** | what .NET tooling already does; needs a gallery that resolves them, which an air-gapped estate does not have |
| **C. The surface requires a local Xmip install and loads its libraries** | nothing to package; makes the PowerShell module useless on an administrator workstation, which is where it is most wanted |

**Lean: A, revisit if size becomes real.** Air gaps are a stated target and B
fails them. C is the tidiest and it defeats the point: an operator surface that
only runs on the server is a shell prompt with extra steps.

## 22. Nothing starts Xmip on a device

`deployment-model.md` section 6 says the installer registers the Xmip Service
**where services exist**, and section 8 says a configured node has the service
**registered and running where services are supported**. Both sentences are
carefully true and neither says what happens where they do not.

A Meadow-class board has no service manager. There is no SCM, no systemd, no
launchd — the runtime *is* what the board runs, and it is entered from reset
rather than started by anything. ADR-0018 gives the Xmip Service nine startup
phases and a supervisor that registers and deregisters Host Services by name,
and on a microcontroller there is nobody to register with and nobody to
supervise it in turn.

Filed 2026-09-03, when `registration.rs` landed and had to name the case it
does not handle. `ServiceManager::None` is that name. The three platforms
that do have a service manager are answered; this is the fourth deployment
target the owner named — cloud, on-prem, computer, device — and it is the one
with no answer.

| option | effect |
|---|---|
| **A. The runtime is the entry point; supervision is the hardware watchdog** | honest about the platform: reset is the only restart a board has. Host Services stop being separate processes and become tasks, so ADR-0018 clause 3 means something different here than on a server |
| **B. A tiny supervisor task inside the firmware** | keeps ADR-0018 shape — something registers and restarts the rest — at the cost of writing a scheduler Xmip does not otherwise need |
| **C. Devices run the purpose-compiled runtime and no Service concept at all** | `deployment-model.md` section 2 already has the purpose-compiled runtime, and this says the Service is a server idea. Cleanest, and it makes one word mean two things across the range |

**Lean: A, and it needs ADR-0018 amended rather than reinterpreted.** The
watchdog is what actually restarts a stuck board and pretending otherwise buys
nothing. What A costs is that *Host Service* stops meaning a registered
operating system service and starts meaning a supervised unit of work, which
is a terminology change and terminology.md does not permit that quietly.

C is the tempting one and should be resisted for the reason the deployment
model already gives: **the runtime semantics are identical on all of them.**
A device that has no Service has different semantics, not fewer modules.

---

# Suggested order

Rewritten 2026-08-30. The previous list was complete fossils — create
xmip-core-abi (exists), fix main.rs (deleted), orphaned tests (gone) — which
is what an order costs when nothing retires its entries.

```text
0. Verify the .NET modules            Test-XmipModule looks for a Cargo.toml, so
                                       cli, powershell and gui are skipped and
                                       land only under -All, unverified. ADR-0014
                                       puts all four surfaces in .NET, so this
                                       gate has to grow before the operator
                                       boundary carries weight
1. The GUI                             market-position.md calls this the widest
                                       gap; the repository is empty and ADR-0014
                                       has already decided its shape. The
                                       PowerShell module came off this line on
                                       2026-09-03: three cmdlets over the ABI
                                       and eighteen tests, seven of them holding
                                       the binding to xmip_module.h
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

---

# Resolved

Kept because a problem and its answer are one document. Each says what resolved
it and when. Nothing below is work.

## 1. Eight orphaned tests hold the build red — **Resolved**

*Resolved by option A before 2026-08-30, recorded here 2026-09-03.*

`tests/` holds no `.rs` file. The eight went with the crate move of 2026-08-26
that emptied `src/`, and the Suggested order recorded them gone on 2026-08-30.
This entry did not move with it, so the register went on opening with a red
build for four days after the build was green.


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

## 2. Roughly forty files in `src/` are published by nothing — **Resolved**

*Resolved 2026-08-26 by neither option, recorded here 2026-09-03.*

`src/` holds one file. The forty went to the repositories that own them rather
than to `attic/`, and `src/lib.rs` names every destination in its own header.
The command this problem opens with cannot be run: `src/main.rs` is deleted,
which answers the question it was meant to ask.


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

## 3. Edition mismatch — **Resolved**

*Resolved by option B, recorded here 2026-09-03.*

`architecture.toml` and the workspace `Cargo.toml` both say edition 2021. The
manifest key is `[crate]`; `cratePolicy` appears nowhere in its history, so the
name below was already wrong when it was written.

Option A — the migration to 2024 — is undone and unfiled. It is a migration
rather than a mismatch, and it needs its own entry the day someone wants it.


`cratePolicy` says edition 2024. The workspace `Cargo.toml` says 2021. Toolchain is 1.94.1,
so both are available.

| option | effect |
|---|---|
| **A. Move the workspace to 2024** | matches stated policy; a real migration with borrow-checker and prelude changes |
| **B. Change `cratePolicy` to 2021** | one-line honesty fix; policy follows reality |

**Lean: B now, A later.** Do not attempt an edition migration while the build is red. Make
the manifest tell the truth today, migrate deliberately once green.

## 11. `xmip-module-api` and `xmip-module-abi` still exist — **Resolved**

*Resolved by option A, recorded here 2026-09-03.*

`crates/` does not exist. Both crates are gone and `xmip-core-abi` is real —
seven files at `modules/foundation/abi`, with the specification beside them.
What remains are citations inside ADR-0012 and ADR-0016, and those are correct
as they stand: a record says what was true when it was written.


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
The four options as they were recorded:

| option | effect |
|---|---|
| **A. One node holds the cluster lease store** | simple; that node is now a single point of failure and a shared write path for exactly the thing that must not have one |
| **B. Consensus among nodes** | correct and honest about the problem. It is also a distributed-consensus implementation, which ADR-0017 spent its entire argument avoiding |
| **C. Cluster scope requires an external store, declared as such** | the five coordinators ADR-0017 removed, readmitted for one narrow purpose and only when Cluster scope is actually used |
| **D. Cluster scope is not offered** | Node scope and resource-native claims cover more than expected — the file case is already handled by claiming the artefact itself |

**Lean: D first, C as the escape hatch.** ADR-0017 clause 2 already says a
transport addressing a discrete claimable artefact claims the artefact, and that
claim is cluster-wide without any lease at all. The remaining need for true
Cluster scope may be small enough to make B's cost absurd. Worth counting the
real cases before building anything.
