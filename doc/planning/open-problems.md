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

"Capability" means *things Xmip does*, and these do things — but nothing about them is
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
to avoid: it puts a judgment back into the name, which is exactly what the manifest exists
to prevent.

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

And `resilience` had no plugin surface in practice, despite six declared
implementations — until ADR-0048 (2026-09-10) gave it the guard trait the six
implement. The tier question below stays as it was.

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
| **A. Move to a GitHub organization, add a second owner** | survives one person stopping | an afternoon |
| **B. DCO on contributions** | clean provenance for a future transfer | a file and a CI check |
| **C. Register the trademark** | protects the name specifically | money, jurisdiction-by-jurisdiction |
| **D. Written statement of intent** | says what should happen; not binding alone | an hour |

**Lean: A first, then B.** An organization with two owners is the single cheapest thing that
changes the outcome if you stop — everything else protects assets that an organization is
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

2026-09-19: the Playground hands work R -> P -> S between node processes through
per-node inboxes in the cluster's shared directory, each hop recorded. This is
option A rehearsed in the rig only; it rules nothing for the runtime, which stays
the owner's to decide.

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
| **A. One module carrying every runtime identifier** | one artifact, works offline, and every operator downloads five platforms to use one |
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

## 23. Recovery is decided but undemonstrated, and unbuilt below the contracts

A power cut during a Playground run on 2026-09-06 asked the plain question: what
survives a shutdown, a network drop, or an attached device going away. The model
is decided and recorded; almost none of it is built, and nothing demonstrates it.

**Decided (recorded, coherent).** *Durability precedes execution*
(`runtime-model.md`): nothing runs on arrival, every Stream, Message and Journey
is written to per-node persistence before anything acts on it, so an accepted
Message cannot be lost to a crash. A non-terminal Journey resumes from its last
checkpoint, position and Message generation together (ADR-0013). Exactly-once is
internal — one runtime owns a unit of work by the durable claim (ADR-0024),
checkpoints bound reprocessing — so delivery is at-least-once and edge effects
must be idempotent (`DeduplicationRecord`). A dropped connection is a transport
error over already-durable state, retried under `resilience`. An inbound claim is
an atomic rename, so a schedule finds an artifact claimed-or-gone and moves on.

**Built (thin).** `xmip-core-persist` is types and a trait only —
`DurableRecordIdentity`, `DurableExecutionCheckpoint`, `DurableJourneyState`,
`RecoveryLease`, `DeduplicationRecord`, the `RuntimeStore` trait — with **no
backend implementing it**. `schedule` is a stub — unmounted 2026-09-19, the
repository kept on GitHub (ADR-0058, amendment); `resilience` is types. So
recovery is not executable today: the contracts exist, the durable store behind
them does not.

**Open (recorded as open).** Cross-node Journey recovery is left open by ADR-0024
— a Journey mid-flight in node A's ToDo is node A's work, and moving it to node B
when A dies ("work does not move by itself", Problem 17) is undesigned. A device
mount that vanishes after a claim-rename but before completion is the same gap in
the attached-device case. Single-node restart recovers; failover does not.

**Undemonstrated.** The Playground is a harness — in-memory scenario state,
temp dirs rebuilt each run — so a power cut just re-rolls it and it proves
nothing about recovery. A **blackout** scenario (kill a node mid-Journey,
restart, assert resume from checkpoint with no loss and no double-effect) is the
missing proof, and it only becomes real once a `RuntimeStore` backend exists.

| option | effect |
|---|---|
| **A. Build a minimal file-backed `RuntimeStore`, then the blackout scenario** | makes recovery executable and demonstrable at the smallest cost; the file backend is also the on-device default |
| **B. Blackout scenario against an in-memory store first** | proves the resume *logic* now, but not durability across a real process death — the thing the power cut actually tested |
| **C. Leave until the runtime queue reaches persistence** | honest sequencing, but recovery stays prose until then |

**Lean: A**, small and it unblocks the demonstration.

**Disaster & Recovery is a separate, later concern** — this problem is *runtime*
recovery (a node coming back to its own durable state). D&R is *host* recovery:
standing a node's operating system, dependencies and configuration back up on
new hardware, to be done with **DSC and Ansible** as the provisioning surface,
not by anything inside the runtime. Parked deliberately; recorded here so the two
are not conflated when D&R is taken up.

Filed 2026-09-06, prompted by a power cut mid-test.

## 24. There is no serial bus, so no serial protocol is proved on one

The owner, 2026-09-20: *I guess Xmip is missing a serial bus simulator to test
serial transport protocols.* He is right, and the shape of what is missing is
sharper than the guess.

**What exists.** `SerialTransport::loopback()` is a line, not a bus. Its
`round` is `round_in_order` — write the frame, then read it back, one thread,
no second party. It proves framing: delimited frames end at the delimiter, a
fixed frame is exactly its length, a partial match inside a payload is not a
frame boundary. That is real and it is all of it. The `serialport` crate is
behind the `port` feature and nothing in any test opens a port.

**What rides on it.** Four technologies declare `xmip-core-transport-serial`:
`dnp3`, `m-bus`, `hart` and `wireless-hart` through `hart`. Each stood up its
own device stand-in on top of that line — `m-bus/src/loopback.rs` has a
loopback meter, `hart/src/loopback.rs` a loopback field device. This is the
same duplication `transport/.src/loopback.rs` was written to end one level up,
where the dance had been written in the Playground *forty-two times over*
(ADR-0051). It has reappeared below, per protocol, unremarked.

**What none of them can prove.** A serial bus is multi-drop: several devices
on one pair of wires, each with an address, a master that polls one of them,
and turnaround between the two directions. M-Bus addresses a primary; HART
addresses a polling address; DNP3 carries a link-layer source and destination.
Against a line that echoes, every one of those is written and none is
exercised — nothing can show that a device at the wrong address stays silent,
that a second device does not answer over the first, or that a master that
polls before turnaround reads its own frame back. The line cannot lose a
character, hold a break condition or run at the wrong baud either, so the
error paths a field bus exists to survive are unreached.

**The shape already exists in the estate.** `can-bus` did this properly:
`Loopback` there is an in-process *bus* held behind `Arc<dyn Bus>`, with
`CanTransport` a participant on it and the bus a thing in its own right. Three
technologies — `j1939`, `obd-ii` and `uds` through `iso-tp` — sit on it. A
serial bus would be the same object: an addressed multi-drop line in
`xmip-core-transport-serial`, with `SerialTransport` a party on it and the
present echo kept as the one-party case.

| option | effect |
|---|---|
| **A. A multi-drop bus in `serial`, modelled on `can-bus`'s** | the four riders drop their own stand-ins and gain addressing, silence and turnaround; the pattern is proved and the parallel is exact |
| **B. Leave the per-protocol stand-ins and add addressing to each** | four places to keep true, which is the duplication ADR-0051 named |
| **C. A real port behind `com0com` or a pty** | proves the driver, needs a machine set up for it, and cannot run in the gate — a later addition, not the first one |

**Lean: A**, with C named as what it does not replace: a bus in process proves
the protocol, never the port. Filed 2026-09-20 on the owner's observation,
verified the same hour.

---

# Consolidation

## 25. The estate still says one thing in several places

The owner, 2026-09-23: *Let's consolidate, refactor and re-engineer if needed.
Look at competition, what do we need for Xmip.* Four read-only audits that day,
each finding checked in the code before it was written here. The 2026-09-22
list of homes was **a third done**: of its 32 items, 7 done, 10 partial, 15 not
started, and every adapter written that day to save call-site edits still in
place. `xmip-core-library-codec` is described in the manifest as holding hex,
base64, checksums, cursors, varints, civil dates and lexers; it holds XML
escaping and nothing else.

**Copies that behave differently — bugs, first:**

| # | Concept | Where it diverges | One home |
|---|---|---|---|
| a | A Journey across a restart | `persist::DurableJourneyState` dropped `previous_journey_id`, `cause`, `depth` and entries, so a recovered Journey restarted its chain depth at zero and loop protection was off | **Resolved 2026-09-24:** persist stores `journey::Journey` whole, and a test writes and reads one two links deep |
| b | A node's configuration | modelled four times: two trees in `configure`, a subset in `runtime/execution_tree.rs`, and the editor's own in C#, which defaults a location's `start` and `transport` where the runtime requires them, never unescapes, and matches keys by prefix | the one document in `configure`; the editor validates through `xmip_validate_v1` |
| c | Protocol Buffers wire rules | contract refused groups and checked only field 0; message accepted groups and capped the field number | **Resolved 2026-09-24:** one walk, `message::protobuf`, with the encoders beside it; the contract checks the schema over it, tag before value |
| d | CSV | contract split on lines, refused a quoted line break and took a quote anywhere as opening one; message follows RFC 4180 | **Resolved 2026-09-24:** the contract reads `message::record`, and refuses a NUL byte as the shape does |
| e | A path lexer | FHIRPath and the predicate language consume whitespace as one byte and panic on U+00A0 | one character reader in codec, every lexer on it |
| f | TOML string quoting | the node declaration escapes three characters; archive's copy escapes all | codec |
| g | msmq over https | always writes `http://`; its `tls` feature does nothing | `http::endpoint`, as as2, as4 and webdav already do |
| h | A null context value | route's `X` reads null as present, `context:X` as absent | one `routable` beside `text_of` |
| i | A node's capability | parsed three ways: Playground and PowerShell refuse an unknown word, the surface drops it silently and is case-sensitive | `node` parses, `cluster` places |
| j | A health colour | `SegmentRender.Traffic` maps Paused yellow and Holding red, the prompt grey and orange | `English.Color` |
| k | Scope containment | `observe` compares text, `ScopeTree` strips scheme and authority first | a scope type in `observe` |
| l | Landing a pin | `Publish-XmipPin` checked only the push, so a failed commit followed by an empty push reported success | **Resolved 2026-09-23:** `Invoke-XmipGit` is the one way the module runs git, and a test refuses any other |
| m | Reading TOML in PowerShell | three readers assume one of the two shapes PSToml has returned | one reader in the module |

**One concept, several copies, the same behavior.** Loopback rigs in 51
transports over a parent that shares only the traits; `rabbitmq` rewriting
`amqp`; three SQL archives that are one type; Kerberos AP-REQ and SPNEGO read
twice; NTLM type 3 twice; two JOSE key types; a clock in ten authenticate
crates; evidence names declared on both sides of the identity gate; dns and
mdns message codecs; CANopen and EtherCAT SDO; webdav's own HTTP codec; three
MIME writers; seven lexers; three hand-written HTTP clients; SQL quoting five
times; hex twelve times, base64 three, SHA-1 two, CRC four, byte readers
fourteen, civil dates six — one of them inside `library/asn1`; SigV4, AWS Query
and Azure SAS still in `transport/http`, where the owner ruled on 2026-09-22
they leave for `xmip-core-transport-aws` and `-azure`, neither yet created;
four time types; record-then-sink written four ways with three error
contracts; three models of a location; two predicate languages; two resilience
models; two host-type rules and two module registries in the runtime; three
transport traits for one concept, two of them with no implementation outside
a test.

**Owned by the wrong crate.** The Playground holds the snapshot format the
surfaces read, the topology and run header they draw, retention's policy,
node capability and placement, and a claim by rename it documents elsewhere
as unsafe; the runtime holds Message treatment presets `message` owns.

**Dead.** Nothing depends on persist, event, audit, report, process,
prepare, transform, assign, promote, demote, cluster or resilience; the
runtime's `capability_registry`, `HostService`, `registration.rs`,
`ModuleRegistry`, `RuntimeDispatcher` and the generation presets run only
under their own tests.

| option | effect |
|---|---|
| **A. Divergences first, then one home per concern, then the runtime** | what is wrong stops being wrong before anything is built on it; the order the owner set on 2026-09-22 |
| **B. The runtime first, consolidating what it touches** | a node runs sooner, over copies that disagree |

**Lean: A**, because (a) and (b) sit on the runtime's own path: a node
started on today's configuration model and recovered by today's persist would
inherit both. Every row was checked in the code on 2026-09-23; the change that
resolves a row names the paths it touched, and the row moves to Resolved with
it.

## 26. A provider other than core cannot plug in

The owner, 2026-09-24: *Put yourself in a provider's position — would you be
pleased with the documentation, tools and opportunities?* No, and in this
order of how soon a provider would stop:

1. **Nothing to plug into.** No node runs a technology; only contracts can be
   loaded through the ABI, and nothing loads them.
2. **Nothing stable to build against.** Every crate `publish = false`, every
   dependency `branch = "main"`; the ABI's `trait_minor` rule reads one way in
   ADR-0012 and the other in `specification.md`.
3. **The license boundary was unclear**: *the boundary is the trait*, while a
   Rust technology links the AGPL trait crates into itself.
4. **Documentation written for the estate's maintainer**: the provider guide
   was twenty lines of pointers into records.
5. **Tooling for one owner**: the templates on one account, and nothing that
   starts a provider's module.
6. **No route to a customer**: nothing packages, signs or distributes a
   provider's module, or says which node it works with.

**Decided 2026-09-24, ADR-0061:** one versioned crate, `xmip-core-sdk` at
`module/foundation/sdk`, over `abi`; a provider takes it by git tag; the ABI is
the license boundary; a provider declares its modules in core's manifest.

**The work, in order** — each step one change, and each moves every copy:

| step | what | closes |
|---|---|---|
| 1 | the SDK repository created and mounted; ADR-0061; CONTRIBUTING's boundary sentence — **done 2026-09-24** | 3 |
| 2 | the contract trait moves into the SDK, every contract technology imports it from there, and the export that wraps a Rust contract in its table — **done 2026-09-24**: `contract/rust` is the worked example, and the runtime's loader opens it | 2, first trait |
| 3 | the other traits a provider implements, one capability per change: transport, message shape, path, guard, archive store, the identity gates | 2 |
| 4 | the runtime loads every table the header declares, from the library a node's configuration names | 1 |
| 5 | the tag: a test holding `sdk-v…` to the traits it describes, and the landing tagging the SDK when it changes | 2 |
| 6 | a provider quick start in the SDK's README, and a module of provider `example` built outside core's crates, loaded by a node | 4, 5 |
| 7 | packaging a provider's module with its declaration of which SDK it was built against | 6 |

The `trait_minor` disagreement is the owner's to settle before step 4 relies on
it; `specification.md` and ADR-0012 name the two readings.

## 27. Xmip cannot obtain a certificate, and identity is tested once

The owner, 2026-09-24: *The identity test has to be split into two. One local,
on-prem version and one using ACME when a node is online* — and then *ACME has
to be incorporated both locally and internetwise for Xmip.* Decided the same
day, ADR-0034 amendment 2026-09-24: provisioning is a capability,
`xmip-core-provision`, ACME one of its technologies for both reaches, and two
tests, `identity-local` and `identity-online`.

What exists: certificate **usage** — mutual TLS on Receive and Send, a stand-in
certificate authority, the certificate authenticators. What does not: anything
that **obtains** a certificate. ACME appears in the estate only as a simulated
fault string, and identity is a stage inside `round-trip`.

| step | what |
|---|---|
| 1 | `xmip-core-provision` declared and created, its trait in the SDK (ADR-0061: a provider may ship a certificate source) |
| 2 | `xmip-core-provision-acme`: RFC 8555 — directory, nonce, an account key and JWS, order, challenge, a CSR finalized, the chain fetched, renewal before expiry — against any directory a node's configuration names |
| 3 | `self-signed` and `internal-ca` beside it, so an offline node has a source without ACME |
| 4 | the Playground runs a local ACME server — Pebble, Let's Encrypt's test server, declared in `prerequisite.toml` — and `identity-local` provisions from it and presents the result on mutual TLS |
| 5 | `identity-online` on nodes that declare online, against the internet |

**Open for the owner before step 5:** Let's Encrypt validates that the node
controls a name — `http-01` needs a public address on port 80, `dns-01` needs
write access to the name's DNS. A laptop has neither. `identity-online` needs
one of them named: a domain and the way its DNS is written, or a public host the
Playground may run on.

---

# Suggested order

Rewritten 2026-09-23. The owner asked what Xmip needs against the
competition; the answer, surveyed that day with sources, is in
`market-position.md` section 8. It sorts into four phases, and the phases are
the order:

```text
A. Divergences          problem 25 (a)-(m): copies that disagree are bugs
B. One home each        problem 25's list; the 2026-09-22 shims removed;
                        transport-aws and transport-azure created (approved
                        2026-09-22); dead code deleted or wired
C. A node runs          the 2026-09-05 item 1 below, in the smallest honest
                        sequence: the Xmip Process vocabulary settled; subscriptions
                        and location bindings in the configuration; file
                        claims by rename (ADR-0024); one transport trait; a
                        file-backed store that writes the Stream and Message
                        before execution; an xmip-service executable doing
                        phases 4-9 with technologies linked by feature (the
                        purpose-compiled runtime, deployment-model.md); a
                        Xmip Process branch in departure; checkpoint, resume
D. What a buyer checks  transformation (XSLT first: BizTalk maps are XSLT);
                        tracking, message search and resubmit; EDI
                        acknowledgements and trading-partner agreements;
                        sign, encrypt, compress (prepare); secrets; an
                        OpenTelemetry exporter; a signed release with an SBOM
                        (the Cyber Resilience Act's reporting duties began
                        2026-09-11); BizTalk artifact import
```

Phase D's secrets and BizTalk import have no home in the manifest, and a
visual mapper none in the surfaces; the owner decides each.

The 2026-09-05 order follows unchanged; its entries sit inside phases C and D.

Rewritten 2026-09-05. The 2026-08-30 list had gone stale the way its own
predecessor did: its first two entries — the .NET verification gate and the
GUI — were both done, and two of the session's largest pieces, the operator
boundary and configuration editing, were nowhere on it. An order nobody
retires entries from stops being an order.

**Done since the last rewrite, and off the list:**

- **The .NET verification gate.** `Test-XmipDotnetModule` builds and tests
  every `.csproj`; `cli`, `powershell` and `gui` land verified, no `-All`.
- **The GUI, both hosts.** One `Xmip.Gui` component library; a Blazor web host
  (monitoring) and the MAUI desktop host Xmip.Operations (monitoring and configuration), ADR-0014.
  Health tree, severity shading, pause and resume.
- **The operator boundary.** `xmip_operate.h`, ADR-0027: health, measurement,
  pause, resume, and the `xmip_start_v1` / `xmip_validate_v1` lifecycle exports.
- **Node configuration read and validated.** `xmip-core-configure` parses it,
  the runtime validates it (startup phases 1–3), `xmip_validate_v1` checks a
  document without applying it — the desktop editor's Validate.
- **The desktop configuration editor.** `Xmip.Operations` opens a node TOML,
  edits cluster, execution style, processes and locations as fields, and has
  Validate, Save and Start node (ADR-0014, amendment 2026-09-05). This entry
  stood as undone until 2026-09-08 while the screen existed; retired then.

```text
1. Run a node for real                 the runtime does startup phases 1-3 —
                                       read, build, validate. Phases 4-9 (start
                                       the host services, load modules, accept
                                       work) turn edge-01's rows from yellow to
                                       green, make the throughput cards real,
                                       and are what the Playground needs to
                                       exercise anything. Blocked on the
                                       vocabulary question below — and, since
                                       2026-09-19, on something larger that
                                       had never been stated: **a node cannot
                                       use a single technology.**
                                       `xmip-core-runtime` has sixteen Xmip
                                       dependencies and not one of them is a
                                       technology; the root assembly has none
                                       either; the only place the two hundred
                                       technologies are linked is
                                       `test/core/playground`, with one hundred
                                       and twenty-three. They can now be
                                       loaded instead: ADR-0057 step 2
                                       landed on 2026-09-19 and
                                       `xmip-core-runtime` opens a shared
                                       library, resolves
                                       `xmip_create_module_v1`, holds the
                                       descriptor to what the loading
                                       capability requires and drives the
                                       contract table through it, behind the
                                       `dynamic-loading` feature. It has
                                       opened the Rust and the C contract
                                       technology with the same code. What
                                       is still missing is a node that does
                                       it: `start.rs` performs phases 1-3
                                       and says in every record that 4-9 are
                                       not built, so nothing asks for a
                                       Module yet. Phases 4-9 still have
                                       nothing to start once the vocabulary
                                       is settled, for a smaller reason
                                       than before
2. Protocol implementations            eighty-two of eighty-four transports,
                                       every contract, message, route, logic,
                                       resilience, path and archive technology
                                       built (2026-09-11; twenty-seven of the
                                       transports had been reported built
                                       that morning over a template stub and
                                       were built for real that afternoon).
                                       Every transport is its own far end
                                       (ADR-0051). sftp and peppol joined
                                       them on 2026-09-19, and the fifty-one
                                       identity technologies ADR-0050 sorts
                                       are written (its amendment of that
                                       day says what writing them found).
                                       What is left is theirs to grow:
                                       principal names (ADR-0054), a second
                                       SSH cipher suite and known hosts,
                                       peppol's SMP lookup
3. The three views and the exact scope ADR-0052, amendment 2026-09-14:
                                       Configuration (the classic tree,
                                       landed as a first cut), Monitor (the
                                       default) and Topology; the tree is
                                       Cluster → Node → receive → process →
                                       send, open and still, reaching the
                                       configuration and the binaries (not
                                       yet published); Topology navigates
                                       to another cluster when allowed, a
                                       second named roll in the playground,
                                       Start-XmipTest -Cluster orders (the
                                       playground topology, -Cluster and the
                                       chooser that moves a view between
                                       clusters are all landed, ADR-0052,
                                       amendment 2026-09-20); every
                                       surface drills to the leaf; every view
                                       names the Receive Location, the
                                       Xmip Process and the Send Location,
                                       not the transport and contract
                                       beneath; the
                                       topology draws Xmip's own configured
                                       and observed communication; the
                                       drill reaches configuration, an
                                       Operator changes it and a Developer
                                       opens it, on the web as on the
                                       desktop; the prompt names the node
                                       when the session is remote; a role
                                       comes from a directory, the
                                       playground's is a fake one that
                                       allows the tester, and
                                       Start-XmipTest -Directory names
                                       which: kind, name and address
                                       (ADR-0009,
                                       amendment 2026-09-14). The surfaces
                                       are demonstrable over the playground
                                       and not yet testable for real (the
                                       owner, 2026-09-14 evening): the runtime
                                       module had no tests, the GUI none of
                                       its own, and the web offers no role.
                                       The runtime has them since, and the
                                       GUI since 2026-09-19 (Xmip.Gui.Test,
                                       the three views over a published
                                       fixture); the role is what is left. A surface
                                       is told, never asks: the change feed
                                       is signalled, and rides SignalR when
                                       it crosses a network — built, the
                                       remote surface and the web host's
                                       hub (ADR-0052, amendment
                                       2026-09-15). The names
                                       need item 1's
                                       configured node; the directory needs
                                       the role gate ADR-0027 blocks on
4. Journey replay end to end           problem 19, and the half of ADR-0024
                                       that stayed open
5. Cluster coordination and placement  problems 17 and 19; ADR-0025 clause 6
                                       says where it belongs, not what it is
6. xmip-core-webapi                    declared, mounted nowhere, one orphan
                                       gitdir — decide it lives or retire it
7. Cross-compilation                   four declared targets, verified on host
                                       only
8. Organization and second owner       problem 15, independent of all the above
```

**A decision blocks item 1.** The owner raised, 2026-09-05, that "Process" is
overloaded three ways — the Xmip Service that rules a node, the Host Service
that does the work, and the Xmip Process a Subscription starts. terminology.md
records a different split (Service rules, Host Service works, Xmip Process is
the integration process). The runtime's startup code names things after the
record. Before phases 4-9 name more of them, the record and the owner's model
have to agree. Not yet filed as a numbered problem because it is a terminology
correction, not an open design question — but it must be settled first.

Problems 4, 5, 7, 8 and 9 remain naming judgments with no deadline. They cost
nothing to leave open and should not block the build work.

---

# Resolved

Kept because a problem and its answer are one document. Each says what resolved
it and when. Nothing below is work.

## 1. Eight orphaned tests hold the build red — **Resolved**

*Resolved by option A before 2026-08-30, recorded here 2026-09-03.*

`test/` holds no `.rs` file. The eight went with the crate move of 2026-08-26
that emptied `src/`, and the Suggested order recorded them gone on 2026-08-30.
This entry did not move with it, so the register went on opening with a red
build for four days after the build was green.


Every `.rs` file in `test/` imports `xmip_linear_kernel`, the crate's pre-narrowing name.
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
seven files at `module/foundation/abi`, with the specification beside them.
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

## 6. `logic` has three implementations and an unclear trait — **Resolved**

*Resolved 2026-09-08 by ADR-0043, option B: the sentence was written and it
names process nowhere.*

A Logic technology turns a Stream that arrived on a transport into a named
operation with typed arguments, and an operation's result back into a Stream,
using a contract to type both. `xmip-core-logic` holds the trait, four methods
in both directions; `soap`, `http-api` and `grpc` implement it, each its own
repository under it.

The question as it was recorded: state the trait in one sentence; if it cannot
be stated without describing `process`, fold it into `process`. Options were A,
fold, and B, keep and define. The lean was to run the test first; it was run.

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
| **D. Cluster scope is not offered** | Node scope and resource-native claims cover more than expected — the file case is already handled by claiming the artifact itself |

**Lean: D first, C as the escape hatch.** ADR-0017 clause 2 already says a
transport addressing a discrete claimable artifact claims the artifact, and that
claim is cluster-wide without any lease at all. The remaining need for true
Cluster scope may be small enough to make B's cost absurd. Worth counting the
real cases before building anything.
