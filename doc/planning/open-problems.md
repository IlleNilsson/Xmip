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

# Runtime safety

## 13. Nothing bounds a publication chain — **option A landed**

*Option A landed 2026-09-03 as ADR-0026. B and C stay open, which is what
the lean below said would happen.*

Every Journey carries a depth, a node configures a ceiling, and
`Journey::following` — the only way a chain grows — refuses the link that
would pass it, naming the Subscription and the Work Process rather than a
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

# The Ledger

## 17. How does work reach another node?

**Answered 2026-10-01.** The owner, validated part by part with the
assistant: *There is nothing local about either RocksDB or SQLite, they are
cluster services running on one or more nodes*, and *All DB records have to
be central and clusterable, if one node fails another one should be able to
pick up*. The work store, renamed the Ledger, belongs to the cluster: every
node reaches it through Xmip Storage, the nodes declaring the Storage role,
round robin, and behind them is a database server IT runs (option A, chosen)
or, on a single machine, an embedded Storage node; work moves by a
time-limited claim in that database (`runtime-model.md` section 3,
`deployment-model.md` sections 7 and 9). Of the options below it is nearest
B — a shared write path — with the difference that no node writes the
database directly, only Xmip Storage's operations do. The database server's
failover and the balancing of incoming traffic are IT's. Built since: a
node's work reaching another node through Xmip Storage over the wire in the
assembled service, a Message a receiving node published sent by a sending node, and
embedded Storage nodes as a primary and its standbys (2026-10-22; problems
45 and 46); the database server is not. The question as it
stood before the ruling:

The work store was per node and written only by its owner, which was meant to
remove the shared write path BizTalk's MessageBox never escaped. The cost was
that a Message in node A's store was node A's work, and nothing moved it.

That is fine for an estate where each node owns its own Receive Locations. It is
not fine when a Receive node should hand processing to an Executing node, which
`deployment-model.md` node capabilities explicitly anticipate.

| option | effect |
|---|---|
| **A. Nodes hand off over the Xmip node-to-node protocol** | explicit, auditable, and the Journey records the hop. Needs that protocol to exist — see problem 18 |
| **B. Receive nodes write directly into the target node's store** | fewest moving parts, and it reintroduces the shared write path this design exists to avoid |
| **C. Work stays where it lands; placement decides at receive time** | no movement at all. Requires the receive-side configuration to know the whole topology, and a saturated node cannot shed load |

**Lean: A.** B is the BizTalk shape wearing a different name. C is defensible
for edge estates where the device that receives is the device that processes,
and it is probably right for the purpose-compiled runtime — but it cannot be the
only answer for a server cluster.

2026-09-26: ADR-0067 gives a node one address with operate, sync and alive as
listeners on it; option A's protocol is the sync listener.

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

- **Journey replay end to end.** No store exists to replay from: the RocksDB
  runtime store of 2026-06-14 was dropped from the build on 2026-06-26 and
  deleted on 2026-08-20, and the SQLite store did not move when the monolith
  was distributed on 2026-08-26, so `xmip-core-persist` holds the types and
  no engine (corrected 2026-09-25; which engine is ADR-0015's open question).
  The replay model is not implemented, and interchange history is not yet
  queryable. Related to problem 17 and to ADR-0024's open consequence on
  Journey recovery across nodes.
- **Cluster coordination.** No inter-node protocol, no failover execution.
  ADR-0024 dissolved the lease half; the placement half is ADR-0025's clause 6
  question and ADR-0018's Host Services, still undesigned between nodes.
- **A typed configuration loader.** `xmip-core-configure` exists;
  full validation against what the manifests declare does not. The format
  half is decided: one `xmip.toml` per cluster, sliced to each node
  (ADR-0031, amendment 2026-10-03).
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

Since 2026-10-13 the packages register through `xmip-service --install`
(ADR-0015, amendment 2026-10-13), which refuses where `ServiceManager::None`
holds; it answers nothing here.

---

## 23. Recovery is decided but undemonstrated, and unbuilt below the contracts

A power cut during a Playground run on 2026-09-06 asked the plain question: what
survives a shutdown, a network drop, or an attached device going away. The model
is decided and recorded; almost none of it is built, and nothing demonstrates it.

**Decided (recorded, coherent).** *Durability precedes execution*
(`runtime-model.md`): nothing runs on arrival, every Stream, Message and Journey
is written to the Ledger, synced, before anything acts on it, so an accepted
Message cannot be lost to a crash: a write counts only once the database
behind Xmip Storage has it durably (2026-10-01). A Message not yet delivered resumes from its last
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
— a Journey mid-flight in node A's store is node A's work, and moving it to node B
when A dies ("work does not move by itself", Problem 17) is undesigned.
*Decided 2026-10-01, not built:* the Ledger is the cluster's, and a dead node's
time-limited claims lapse so another node resumes (ADR-0024, amendment
2026-10-01); a kill test at each step and the failover tests are the proofs
owed (`runtime-model.md` section 3). A device
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

## 24. There is no serial bus, so no serial protocol is proved on one — **option A landed**

*Option A landed 2026-09-24, on the owner's "get it done":
`serial::bus::Bus`, an in-process multi-drop bus with addressed devices,
silence, collision, turnaround, unsolicited frames, a lost character and a
break condition. M-Bus meters and HART field devices are devices on it, two of
each proved on one bus; their stand-in lines are gone. The frame line both
declared for themselves is one trait, `transport::line::Line`, in the
capability they share (ADR-0044), and wireless M-Bus uses it too. A serial
port reads a protocol's frames by the length the protocol says
(`Framing::Measured`), so a real port and the bus are the same boundary. Two
of the four riders named below are not on a serial line: DNP3 is implemented
over TCP only, and WirelessHART is radio with a time-slotted `Radio` of its
own. Option C, a real port behind com0com or a pty, stays open.*

*The same day the CAN bus followed, into the SDK as `sdk::broadcast`, a
medium every node hears: every other node gets each frame, the sender does
not, and a frame nobody hears is not acknowledged. The CAN riders had faked one
bus with two one-way queues per exchange; each party is a node on one bus now.
What it showed at once: ISO-TP takes any frame that arrives, and so UDS and
OBD-II above it would read another node's traffic on a bus that carried any.
CANopen filters by identifier and J1939 parses it. ISO-TP filtering by the
peer's identifier is open.*

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
| **A. A multi-drop bus in `serial`, modeled on `can-bus`'s** | the four riders drop their own stand-ins and gain addressing, silence and turnaround; the pattern is proved and the parallel is exact |
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
| b | A node's configuration | modeled four times: two trees in `configure`, a subset in `runtime/execution_tree.rs`, and the editor's own in C#, which defaults a location's `start` and `transport` where the runtime requires them, never unescapes, and matches keys by prefix | **Resolved 2026-09-24:** `configure::XmipConfigurationDocument` is the one model; the runtime's execution tree is built from it and the second tree and the runtime's startup types are gone; the desktop editor edits the document's syntax tree through `TomlDocument`, keeping comments and layout, matching keys whole, adding no `start` or `transport`, and takes its only verdict from `xmip_validate_v1`; a Work Process's lists default to empty (ADR-0031, amendment 2026-09-24) |
| c | Protocol Buffers wire rules | contract refused groups and checked only field 0; message accepted groups and capped the field number | **Resolved 2026-09-24:** one walk, `message::protobuf`, with the encoders beside it; the contract checks the schema over it, tag before value |
| d | CSV | contract split on lines, refused a quoted line break and took a quote anywhere as opening one; message follows RFC 4180 | **Resolved 2026-09-24:** the contract reads `message::record`, and refuses a NUL byte as the shape does |
| e | A path lexer | FHIRPath and the predicate language consume whitespace as one byte and panic on U+00A0 | **Resolved 2026-09-24:** `codec::char_reader::CharReader` is the one character reader, every position on a character boundary; the FHIRPath, predicate, JSONPath, GraphQL, SQL-contract, proto and SQL-archive lexers read through it, each tested with U+00A0, U+3000 and non-ASCII names and strings |
| f | TOML string quoting | the node declaration escapes three characters; archive's copy escapes all | **Resolved 2026-09-24:** `codec::toml::{quote, unquote}` is the one TOML basic string, every control character escaped; the node's declaration and the file archive's sidecar use it, and the archive now reads a quoted key holding `=` |
| g | msmq over https | always writes `http://`; its `tls` feature does nothing | **Resolved 2026-09-24:** msmq sends through `http::endpoint` as as2, as4 and webdav do; `msmqs://`, `https://` and `DIRECT=HTTPS://` queues go over the one TLS behind `tls`, are refused rather than sent in the clear without it, and a test holds both |
| h | A null context value | route's `X` reads null as present, `context:X` as absent | **Resolved 2026-09-24:** `route::routable`, beside `text_of`, is the one reading; `X`, `context:X`, `header:`, `party:`, `regex:` and `content:` read a missing value and a Null as absent and refuse bytes, a test holds both spellings, and ADR-0046 records the owner's ruling |
| i | A node's capability | parsed three ways: Playground and PowerShell refuse an unknown word, the surface drops it silently and is case-sensitive | **Resolved 2026-09-24:** `node::Stage::declared` is the one parse and `Stage::WORDS` the one word list, exact lowercase only (the owner, 2026-09-24); the runtime's library forwards both (`xmip_stage_words_v1`, `xmip_stage_declared_v1`, `xmip_operate.h` section 7), `Xmip.Surface` and the script module call them through the operator module, and no copy is kept anywhere (ADR-0056, amendment 2026-09-24, corrected the same day; ADR-0052). Since 2026-10-01 a node declares its roles instead, `node::NodeRole::declared` the one parse, forwarded as `xmip_role_declared_v1` (ADR-0056, amendment 2026-10-01). |
| j | A health color | `SegmentRender.Traffic` maps Paused yellow and Holding red, the prompt grey and orange | **Resolved 2026-09-24:** the prompt paints `English.Color`'s name in posh-git's palette (`SegmentRender.Paint`); `Traffic` holds no table of its own and `PromptMonitor.Paint` is gone (ADR-0041, clarified) |
| k | Scope containment | `observe` compares text, `ScopeTree` strips scheme and authority first | **Resolved 2026-09-24:** `observe::Scope` is the one implementation of containment and a scope's parts; the runtime's library forwards it (`xmip_scope_contains_v1`, `xmip_scope_parts_v1`) and `ScopeTree` calls it, so the snapshot and every surface answer by one rule; the two-writer ruling and `scope-vector.toml` are struck by the owner (ADR-0052, amendments 2026-09-24) |
| l | Landing a pin | `Publish-XmipPin` checked only the push, so a failed commit followed by an empty push reported success | **Resolved 2026-09-23:** `Invoke-XmipGit` is the one way the module runs git, and a test refuses any other |
| m | Reading TOML in PowerShell | three readers assume one of the two shapes PSToml has returned | **Resolved 2026-09-24:** every reader goes through `Get-TomlValue`, `Get-XmipDeclaredText` is gone, and `test/Toml.Test.ps1` holds the readers on both shapes and refuses a reader that asks for one |
| n | Promotion at arrival | `runtime/src/arrival.rs` routes with `Promoted::from_context` rather than `route::promote`, so in a running node bytes under a bare `X` decline as nothing promoted instead of being refused, and no prefixed property (`header:`, `party:`, ...) is read at arrival | **Resolved 2026-09-25:** arrival promotes every name its Subscriptions' filters use through `route::Gathering`, compiled once with the Runtime, before the Journey opens; a Null is absent, and bytes under a bare `X` or a prefix no loaded technology provides refuse the Message (`Refused::Promotion`), and the runtime's tests hold a bare `X` of bytes, a Null and `party:sender` read at arrival (ADR-0046) |
| p | The operator surfaces' rules | the CLI and `Xmip.PowerShell` each wrote which surface to read, the runtime override, wildcard selection, the acts, the validation verdict, status meaning, the ABI boundaries, probe conformance and the mood, figure and nothing-at wording; five of them disagreed (the cmdlets took scopes literally, never used the discovery rule, reported one boundary, never judged a probe, and said `Unknown` where the CLI said `unknown`) | **Resolved 2026-09-24** (the owner: *CLI and PowerShell shall share*; *code shall be uniquely placed*): each rule is written once — in its Rust crate where the runtime owns it (scope, stage, mood word and color, worst-first order, called through `xmip_operate.h` section 7), else in `Xmip.Abi` or `Xmip.Surface` — and tested there; the cmdlets take `-Remote`, `-Snapshot`, an optional `-Library` and wildcard scopes as the executable does, and the script module loads the operator module and keeps no capability words, snapshot reader or mood ranking of its own (ADR-0052, amendments 2026-09-24) |
| q | Where a node sits in a scope | `ScopeTree.Node` takes segment 0, so the Monitor's rows name the cluster as a record's node, and the prompt's `SegmentRender.At` reads the literal `node` segment itself: the scope's shape known in two surfaces (found 2026-09-25) | **Resolved 2026-09-25:** `observe::Scope::node` and `Scope::stage` are the one reading — the node the segment after the `node` marker beneath the cluster, never the cluster, the stage the first stage word beneath it — forwarded as `xmip_scope_node_v1` (`xmip_operate.h` section 7) and bound once in `RuntimeRules.Node`; `ScopeTree.Node`, `ScopeTree.Stage`, `ScopeIndex` and the prompt's `SegmentRender.At` call it, and a Monitor row names the node, not the cluster (ADR-0027, ADR-0052, amendments 2026-09-25) |
| r | Headers into the Message Context | `<protocol>.header.<name>` is one name (`context::property::header`, case folded per protocol), but `transport::Arrived` carries only an origin and bytes, so no header reaches a Message | the owner, 2026-09-25: the runtime writes them at arrival from properties the transport hands with `Arrived` (ADR-0046, amendment) |
| s | Tests that fail under load | google-pub-sub's brim (10 MiB in a debug build against a 2 s loopback timeout), the Playground's `cluster::a_silent_node_is_restarted_and_the_restart_is_a_yellow` and `low_latency::spikes_push_a_pair_over_its_budget` fail when the machine is busy and pass alone; they stopped two landings on 2026-09-25 | a test judges what it tests, not the machine's speed: a deadline scaled to the payload or measured from the work itself, never a wall-clock guess |
| t | Slow where it should not be | Xmip's own, the Rust: a brutal node's first round far past 10 s (the millisecond rule, CONTRIBUTING). The estate's tooling: the estate suite takes 11 minutes idle, `EstateMap.Test.ps1` 104 s idle and 1,170 s under load, `Dependency.Test.ps1` 104 s, `Start-XmipTest` 2.5 to 4.8 s to return, importing the module seconds (PSToml); `transport::socket::accept_tcp` with a timeout sleeps 2 ms between polls, adding up to 2 ms to every bounded accept (found 2026-09-26) | the Rust measured and fixed to the millisecond rule; the tooling made quick enough that a developer does not wait on it — the owner, 2026-09-26: *CLI, PowerShell and Web operation tools are built on .NET for the tooling and ease of development* |
| u | Xmip's tools not using Xmip | the .NET surfaces use the platform's TLS (problem 29 step 6); the .NET side reads TOML with Tomlyn and the PowerShell module with PSToml, where `configure` and `codec` are Xmip's; the web host serves HTTP with Kestrel where `net::http` and `net::http2` are Xmip's | the owner, 2026-09-26: *Xmip shall use its own tool chain, dog fooding as much as possible* (CONTRIBUTING) — each moved onto Xmip's own implementation through the runtime's library, or its reason recorded |
| v | Observation lags, or never arrives | what a node observes reaches the surfaces as a TOML publication written once per round, re-read and re-parsed; and in the runtime itself `start_published` (`runtime/src/start.rs`) publishes once, at start, while Receive, Work Process and Send never call `record_count` (outside tests it is called only in `ffi/operate.rs`'s fixtures) — so nothing a node does after it starts reaches an operator, a surface or an exporter (found 2026-09-26 building OTLP and Prometheus) | the owner, 2026-09-26: *everything — stream, message, receive, process, send, observe, event — has to be near, very near real time* (CONTRIBUTING) — every Receive, Work Process and Send outcome records its figure as it happens, the runtime publishes on change to the surfaces' change feed and to observe's exporters (`offer(Arc<Snapshot>)`, measured at a lock and a handle), and a file written per round becomes a record, not the channel |

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

**Done 2026-09-24, phase B's first wave.** `xmip-core-library-codec` holds the one hex, base64 and base64url, SHA-1, parameterised CRC, byte cursor and writer, varint with zig-zag, civil calendar, character reader, TOML string and SQL delimiter, and every copy is gone (transport's cursor, hex and CRC among them). `xmip-core-transport-aws` and `xmip-core-transport-azure` exist and hold SigV4, the Query API, JSON 1.1, SAS and Shared Key; http holds HTTP (ADR-0044, amendment 2026-09-24). `rabbitmq` rides the one AMQP 0-9-1 in `amqp`; the three SQL row archives are one `archive::sql::SqlArchive<D>`. Identity reads Kerberos, NTLM type 3, JOSE keys, the clock and window, and the names crossing the gates each in one place, and the 2026-09-22 `ber`/`der` shims are gone (ADR-0050, amendment 2026-09-24). Found by it and fixed: hex took a sign, AS2's base64 a `=` anywhere, SAML and asn1 30 February, the MariaDB and PostgreSQL far ends a doubled delimiter as an end, and jwt, oidc and oauth2 a token at its `exp`.

**Done 2026-09-24, phase B's second wave.** The transport capability holds the one far-end rig (`Listening`, `Bound`, `Held`, `Standing`, `both_ends`, `poke`, `ceiling::within`), and 84 technologies keep only what their far end does (ADR-0051, amendment). `xmip-core-library-ntlm` is the NTLM layout for identify, both gates and SMB; `context::property` holds every name one layer writes and another reads; `authenticate::secret` is the one secret store (ADR-0050, ADR-0019, amendments). `xmip-core-library-net` holds the authority, the minimal HTTP/1.1 client, MAC notation, percent-encoding and a path as a URI; codec gained MIME and UTF-16. dns owns the DNS codec, canopen the SDO, http the message webdav writes; `archive/sqlite` is `SqlArchive<Sqlite>`. The rollup, counted words, stage facts, capability evidence, topology, run header and the publication, history and activity formats are each written once in `observe` or `node`, and the surfaces read them through `xmip_operate.h` sections 7 and 8 (ADR-0052, ADR-0027). Found and fixed: percent-decoders took a sign, the snapshot reader counted an unknown kind as streams, msmq split MIME mid-line, EtherCAT cut an SDO to four bytes, the topology drew parents in a leaf's mood.

**Still to do in phase B:** row r (headers at arrival).

**Done 2026-09-27 and 2026-09-28:** one body ceiling `net::MAX_BODY` and one refusal `net::ceiling::within`; one TCP connect `net::connect`; one target reading `net::Target`, technologies declaring their `Schemes` (no `as_http`, websocket and `msmq::queue_url` read through it); one form and query reader `net::percent::decode_pairs`, which `aws::query` calls; redpanda through `http::endpoint::Connections` and `http::status::judge`; as2 and as4 answering through `http::server::serve_one_from`, which hands them the peer; Receive Locations keep their listener (`transport::kept`, `transport::serving`) and connected sessions share one pool (`transport::pool`).

**Done 2026-09-25:** the `Loopback` trait learned `exchanges_in_order` and `FarEnd::datagram`, and 16 `round` and 26 `unblock` overrides are gone (ADR-0051); HTTP/1.1 is one codec, `net::http`, with `net::Endpoint` and `net::head`, and http keeps TLS, serving and status (ADR-0044); the CAN pair is one `can_bus::loopback::Session`; `xmip-core-library-ssh` holds RFC 4251's types (ADR-0050); a header is `<protocol>.header.<name>` with case folded per protocol (ADR-0046).

**Owned by the wrong crate.** The Playground holds the snapshot format the
surfaces read, the topology and run header they draw, retention's policy,
node capability and placement, and a claim by rename it documents elsewhere
as unsafe; the runtime holds Message treatment presets `message` owns.

**Wired, 2026-09-28** (the owner: *The runtime starts on a node, loading all
modules needed to work according to dependencies and configuration. […] No
code should be duplicated*). `running::Running::start` runs ADR-0018's nine
phases and serves the message path: `host.rs` plans the Host Services by one
host-type rule, `capability_registry.rs` registers each capability once,
`library.rs` opens each started library through `ffi/loaded_module.rs` and
`ffi/loaded_contract.rs`, `catalogue::carry` is called as each technology
loads, the `Runtime` is built once and every Receive Location runs
`arrival::arrive` and `departure::depart` through `message_path::carry`.
Deleted as second copies: the runtime's `ModuleRegistry`,
`plan_host_services`, `RuntimeDispatcher` and `RuntimeNode` (with `abi`'s
`HandlerInvocation`, `HandlerResult` and `HandlerStatus`, which served only
that dispatcher), the host-type rule in `HostService::from_manifest`,
`host::dynamic::verify_dynamic_module` and `compatibility.rs` (one check,
`abi::accepts` beside `abi::validate_module_abi`), `service.rs`'s phases-1-3
plan, `receive`'s `ReceiveLocation`, `ReceiveTransport` and
`ReceivePublisher` and `send`'s `SendLocation` and `SendTransport` (the
Location is `configure`'s `ConfiguredLocation`, the transport trait is
`transport::Transport`), and `promote`'s code (route's `Gathering` is the one
promotion; whether `xmip-core-promote` stays mounted is the owner's).
`assign` reads a missing or `Null` source as absent (ADR-0046). Still
unwired, each waiting on something not built: `registration.rs` (the
installer, problem 28), `generation.rs`'s assignment and transformation and
the `assign`, `demote`, `prepare`, `process` and `transform` traits (a
Work Process or a transform compiled at design time, ADR-0066 clause 4), and the
`xmip-service` executable that would start a node outside a test (ADR-0018,
amendment 2026-09-26).

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

**Decided 2026-09-24, ADR-0061 and its amendment the same day:** a provider
builds against the capability its module belongs to, as core does — every
trait stays in the repository it belongs to; the SDK, `xmip-core-sdk` at the
estate root, `sdk/`, holds only simulators, emulators and the test ACME
server; the ABI is the license boundary; a provider declares its modules in
core's manifest. Whether anything is taken at a versioned tag is open again.

**The work, in order** — each step one change, and each moves every copy:

| step | what | closes |
|---|---|---|
| 1 | the SDK repository created and mounted at the root; ADR-0061; CONTRIBUTING's boundary sentence — **done 2026-09-24** | 3 |
| 2 | the export that wraps a Rust contract in its table, in the contract capability — **done 2026-09-24**: `contract/rust` is the worked example, and the runtime's loader opens it (the trait moved into the SDK that morning and back the same day) | 2, first trait |
| 3 | an export for each other table the header declares — transport, message, path — in the capability each belongs to; the transport trait's shape and the table's differ, and neither gives: ADR-0057 clause 9, accepted 2026-09-20, keeps the published tables and the ergonomic Rust traits, and the export absorbs the difference | 2 |
| 4 | the runtime loads every table the header declares, from the library a node's configuration names — **the contract table since 2026-09-28**: a node opens each `[[modules]]` library it starts and drives its lifecycle; transport, message and path wait on step 3 | 1 |
| 5 | the tag: a test holding `sdk-v…` to the traits it describes, and the landing tagging the SDK when it changes | 2 |
| 6 | a provider quick start in the SDK's README, and a module of provider `example` built outside core's crates, loaded by a node | 4, 5 |
| 7 | packaging a provider's module with its declaration of which SDK it was built against | 6 |

The `trait_minor` disagreement is settled (the owner, 2026-09-26): a node
refuses a module newer in `trait_minor` than itself, as ADR-0012 and now
`specification.md` say (ADR-0057, amendment of 2026-09-19).

## 27. A running node obtains no certificate yet, and identity is tested once

The owner, 2026-09-24: *The identity test has to be split into two. One local,
on-prem version and one using ACME when a node is online* — and then *ACME has
to be incorporated both locally and internetwise for Xmip* — an online node uses
Let's Encrypt, any other the CA its end user chooses, and step-ca is for tests
only. Decided the same day, ADR-0034 amendment 2026-09-24: provisioning is a
capability, `xmip-core-provision`, ACME one of its technologies for both
reaches, and two tests, `identity-local` and `identity-online`.

What exists: certificate **usage** — mutual TLS on Receive and Send, a stand-in
certificate authority, the certificate authenticators — and, since 2026-10-13,
the sources that **obtain** one, proved in their own tests. What does not: a
running node using them, and the Playground's two identity tests; identity is
still a stage inside `round-trip`.

| step | what | state |
|---|---|---|
| 1 | `xmip-core-provision` declared and created, its trait in the capability (a provider may ship a certificate source) | done 2026-10-13 |
| 2 | `xmip-core-provision-acme`: RFC 8555 — directory, nonce, an account key and JWS, order, challenge, a CSR finalized, the chain fetched, renewal before expiry — against any directory a node's configuration names | done 2026-10-13: http-01 on any port, dns-01 through a provider's `DnsWriter`; tls-alpn-01 not built |
| 3 | `self-signed` and `internal-ca` beside it, so an offline node has a source without ACME | done 2026-10-13; `internal-ca` also serves ACME to the cluster |
| 4 | `identity-local`: a node not online provisions by ACME and presents the result on mutual TLS | proved 2026-10-13 in `internal-ca`'s tests against its own ACME server, offline, nothing installed; the Playground test is not built, and whether it runs step-ca (the SDK, `prerequisite.toml`) is the owner's |
| 5 | `identity-online` on nodes that declare online, against Let's Encrypt | configuration only; open below |

The owner, 2026-10-13: Let's Encrypt for Receive Locations and between nodes
*as an option* — never required, never a default — and the validation *on any
port*. Let's Encrypt has issued no client authentication since 2026-07-08, so
between nodes the cluster's authority issues (ADR-0033, amendment
2026-10-13). Not built yet: `xmip-service` starts no provisioner or
authority — since 2026-10-19 it reads `[provision.receive]` from an
operator's own files as it starts, for the TLS a tcp Receive Location
terminates (problem 33), refuses that table naming a `source`, renews
nothing while running and reads no other purpose's table; a provisioned key is a PEM file, not
sealed under the key home; no DNS writer or lookup ships. A person's
certificate, purpose `operator`, is requested and signed since 2026-10-15
(ADR-0034, amendment 2026-10-15) over the folder `internal-ca` keeps its
authority in; since the same day the phone's and the desktop's key is made
in the platform's keeper and never leaves it — the Android Keystore, the iOS
keychain's Secure Enclave, Windows CNG and the TPM — the request signed
there in two halves the runtime writes, and every handshake signed there
(`Identity::from_signer`, `xmip_remote_open_kept_v1`). The Android keeper is
built and not run on a phone; the iOS keeper is written and not built.
Revocation of an operator's certificate is not decided. Until a node
provisions its own, a node an environment template puts on a machine of its
own is issued its key and certificate on the operator's machine, from the
cluster's authority kept in a folder (`provision::node::issue_into`,
`xmip_operate.h` section 22, `New-XmipCertificate -Node`; ADR-0015,
amendment 2026-10-21), and given them by the template: a key made away from
the node it is for, which a node's own provisioner ends.

**Offline, both ways, since 2026-10-22** (ADR-0034, amendment 2026-10-22;
the owner: *There has to be tools, aid, to support 'Let's encrypt', ACME
when being offline* — both cases). The premises' own ACME service: the node
whose `[provision.node]` names `internal-ca` and `serve` answers ACME in
`xmip-service`, with ACME Renewal Information (RFC 9773) and revocation, its
accounts kept, its revocation list and certificate published over plain
HTTP at the address every certificate it signs names; a standard client,
lego 5.5.2, obtains, is told when to renew, revokes and renews against it,
nothing installed; dns-01 is checked against a DNS server on the premises.
The authority keeps a register of everything it signed, and every surface
sets it up, inspects, revokes from, exports and backs up (`xmip
certificate`, `New-` and `Get-XmipCertificate`, the desktop's Authority
page; `xmip_operate.h` section 23). Across an air gap: a node writes its
request to a file, the authority signs it where it is kept, the node imports
the chain, each step checking the file it is given, and the node's health
says when the next request is due (`<node>/certificate/<use>`). Node
certificates last ninety days (the owner, 2026-10-22), and a node's always
comes from the cluster's authority: Let's Encrypt serves the public server
side alone. Still open here: Xmip's own provisioner does not ask renewal
information, and `xmip-service` starts no provisioner for its own
certificates; win-acme and certbot are not tested.

**Open for the owner before step 5:** Let's Encrypt validates that the node
controls a name — `http-01` needs the name's public port 80 reaching the
node's answer, which may listen on any port behind forwarding; `dns-01` needs
write access to the name's DNS, through a DNS provider's `DnsWriter`, and no
port. A laptop has neither. `identity-online` needs one of them named: a
domain and the way its DNS is written, or a public host and its port 80 the
Playground may use. Its configuration is `[provision.receive]` with `source =
"xmip-core-provision-acme"`, `directory` Let's Encrypt's, `names` that domain,
`agree_terms = true` and the challenge chosen (`node-configuration.md`).

## 28. A node cannot run under a group Managed Service Account

The owner, 2026-09-25: *where it exists it should be supported* (ADR-0019,
amendment 2026-09-25). Nothing installs a node as a service yet, so nothing
runs under any Service Identity, a gMSA least of all.

| step | what |
|---|---|
| 1 | the node installs as a Windows service under a gMSA (`DOMAIN\name$`, no password), refusing in words when the host cannot retrieve the account's password |
| 2 | the technologies that reach a counterparty as the node — mssql integrated security, smb, ldap, http's Negotiate — authenticate with the service's own Kerberos ticket, and a test proves each on a domain |
| 3 | Windows containers and Kubernetes Windows pods: the credential spec a deployment names |
| 4 | Linux: an AD-joined host with a gMSA ticket fetched by a daemon (e.g. `credentials-fetcher`), verified on AlmaLinux before it is claimed |

**Open for the owner before step 2 can be proven:** a test domain — a domain
controller Xmip's tests may use, or one the Playground stands up.

## 29. Xmip stores nothing, encrypts nothing at rest, and has no home for keys

The owner, 2026-09-25, chose RocksDB for the runtime store and SQLite for
management (ADR-0015, amendment) and required Xmip's own traffic and storage
encrypted (ADR-0063). Since 2026-08-20 `xmip-core-persist` has held the types
and no engine.

| step | what |
|---|---|
| 1 | the key home, **decided 2026-09-25** (ADR-0063 clause 4): `xmip-core-secret`, a new capability, created and declared; the platform key store its first technology per platform (DPAPI/CNG, the kernel keyring or a service-only file, the keychain), PKCS#11 and vaults after. **Built 2026-09-25:** `KeyStore`, `DataKey` (the one AES-256-GCM, HKDF and HMAC), `dpapi` tested on Windows, `file` on AlmaLinux, `keychain` built and not run on macOS; `pkcs11`, `vault`, `azure-key-vault`, `aws-kms` reserved; `keyring` reserved, because the kernel keyring forgets a key at a restart — the owner decides what it is for |
| 2 | `persist` gains its encryption layer: AES-256-GCM per record, lookup keys by keyed hash, a record that fails its tag audited as a failure. **Built 2026-09-25:** `EncryptedStore` over the `Engine` trait, and a `RuntimeStore`; a failed tag is `PersistError::Refused` with scope and reason, audited by the caller — wiring that caller to `xmip-core-audit` is open |
| 3 | `persist-rocksdb`, a technology under `persist`, the runtime store; the C++ toolchain and libclang in `prerequisite.toml`; built and tested on the AlmaLinux guest. **Built 2026-09-25**, Windows and AlmaLinux |
| 4 | `persist-sqlite`, the management store. **Built 2026-09-25**, Windows and AlmaLinux |
| 5 | the web host and the remote surfaces over TLS; the node-to-node protocol (problems 17, 18) mutual TLS from its first line. **Web host and remote surfaces built 2026-09-25:** `SecureSurface` in `Xmip.Surface` (PEM certificate, key and anchors; HTTPS always, plain HTTP on loopback only), `SurfaceBinding` in `Xmip.Surface.Relay` (plain HTTP beyond loopback refused before listening, the loopback binding logged and audited, a client certificate checked and required at the hub), `RemoteOperator` presenting and checking; `Start-XmipOperationWeb -Certificate -PrivateKey -TrustAnchor`; proved over mutual TLS on a loopback port, wrong certificates refused. The TLS is the platform's through Kestrel, not `xmip-core-library-tls`; the node-to-node protocol is open |
| 6 | the .NET programs' TLS through `xmip-core-library-tls`, not the platform's (the owner, 2026-09-26; ADR-0063, amendment): the web host's and the remote surface's connections terminate in the Rust library — through the runtime's library as a stream the .NET side reads and writes, or a Rust front in the web host's process — so the hybrid exchange holds on every Xmip connection |

## 30. HTTP/3 is declared and not built

`architecture.toml` declares the http technology over *IETF RFC 9110, with
the applicable HTTP/1.1, HTTP/2 and HTTP/3 documents*. HTTP/1.1 is
`net::http` and HTTP/2 `net::http2` since 2026-09-25 (ADR-0043 and ADR-0044,
amendments 2026-09-25), the version chosen per connection by ALPN or prior
knowledge. HTTP/3 is not: it does not ride TCP at all.

| step | what |
|---|---|
| 1 | QUIC, RFC 9000, over UDP: packets and their numbers, connection IDs, streams and their flow control, loss detection and congestion control (RFC 9002) — a transport in its own right, and where it lives decided first (a library beside `net`, or a transport technology) |
| 2 | QUIC's TLS, RFC 9001: the TLS 1.3 handshake carried in CRYPTO frames and packet protection, through `xmip-core-library-tls`, hybrid key exchange kept (ADR-0063) |
| 3 | HTTP/3, RFC 9114: its frames on QUIC streams, the control and unidirectional streams, and `Alt-Svc` or HTTPS records to discover it |
| 4 | QPACK, RFC 9204: the header compression HTTP/3 uses in place of HPACK, with its encoder and decoder streams |
| 5 | the http transport offers `h3` where a service advertises it, and falls back to HTTP/2 or HTTP/1.1 over TCP where UDP is blocked |

**Decided 2026-09-26, the owner, from three (hand-written, quinn with tokio,
not now): QUIC is hand-written** — synchronous, like the rest of the estate,
tested against RFC 9000, 9001 and 9002, with no async runtime brought in.

**Where it lives, decided 2026-09-28 (the owner: *do what you think is best;
the developer, the end user, should not need to write code unless they really
need to*): a library, `xmip-core-library-quic` under `module/core/library`,
beside `tls` and `ssh`** — not a transport technology. QUIC is a layer other
technologies ride, as TLS and SSH are: the http transport takes `h3` from it,
and a later technology on QUIC does the same. An operator never sees it as a
thing to pick; they configure the http transport, and `h3` is offered where a
service advertises it (step 5). No one writes code to get HTTP/3.

## 31. No Xmip path places a node's slice on a remote node

The owner, 2026-10-05 (ADR-0031, amendment): *When editing is done, the
cluster TOML file is sliced into node TOML files and shipped to each node on
save.* The Operation Desktop slices on save through `xmip_cluster_slices_v1`
and writes each slice to `<SliceDirectory>/<node>/xmip-node.toml`; only its
own node, `xmip.gui.toml`'s `Node`, counts as shipped, and every other node
shows *sliced, not shipped*. Desired state slices on the node itself
(`xmip-service --slice --cluster`; the environment templates of ADR-0015,
amendment 2026-10-21). Missing: an operate-plane act that places a
node's configuration through the node's listener over Xmip's TLS,
authorized by role and audited — the operate listener it would ride is
built (ADR-0067, built 2026-10-12: reads, a follow and the operator's acts;
no act places a configuration yet) — and each node's address known to the
desktop.

**Decided 2026-10-05** (ADR-0031, amendment): the Xmip Service on the
editor's machine pushes each slice to the node's Xmip Service over gRPC on
TCP; the node validates and answers.

## 32. Every dependency is a trait, handed in — where the estate breaks it

ADR-0068 (the owner, 2026-10-05). The audit of 2026-10-05 found, outside the
one composition root (the root crate's features and `.src/service/built.rs`):

| wave | what | size |
|---|---|---|
| A | traits that lack a method a consumer needs: `Transport` cannot say what it holds; `IOperatorSurface` has no liveness, forcing `is ListenerOperator` and `is SnapshotOperator`; observe has no exporter trait; `ProgramAudit` cannot be handed an `AuditSink`; CAN `Bus` and Ethernet `Link` live in technology crates | 6 |
| B | Rust singletons and names in place of injection: `ProgramAudit`'s fixed file sink and `XMIP_AUDIT_DIRECTORY`; `Hub::process()`; `catalogue::CARRIED`; `send_step`/`pickup` registries, `operator::PUBLISHED`; technology names in `configure::store` and `runtime::storage`; persist's closed `Server` enum where a dialect trait belongs; bus and link factories inside technologies; a mechanism matched by name in authorize-transport | ~25 sites |
| C | technology-to-technology Cargo edges: observe, archive backends and every HTTP-shaped, cloud and field-bus technology on a sibling technology, and across capabilities (mllp on hl7-v2, http-api on openapi, route-regex on path-regex, toon on json-schema, ubl on message-xml); shared parts belong in a library or the capability, behavior handed in as a trait | 62 edges |
| D | .NET: one interface in the estate; `RuntimeLibrary.Rules` static (61 sites), `new ConfigurationRuntime` in three hosts, `SurfaceChoice`'s closed switch, concrete `RoleContext`, `ProgramAudit`, `RuntimeCommands` registered and injected; PowerShell and CLI statics | ~30 classes |
| E | tests reaching implementations by path, name or environment variable: runtime dev-dependencies on concrete technologies, the contract library by sibling path, fixtures by relative path, assertions keyed on technology names | ~30 |

Kept as they are: the composition root, `Linked`, the core traits
(`Transport`, `Engine`, `XmipStorage`, `KeyStore`, the gates), canopen's
handed-in `Bus`, archive's `Dialect`, audit's `AuditSink`, event's
`Membership` and `Wire`, `IOperatorSurface` and the hosts' DI containers.

## 33. The assembled service authenticates by two mechanisms alone, and keeps no credentials

Found 2026-10-06 while documenting what is built: `xmip-service`
(`.src/service/built.rs`) links no authenticator and no authorization policy,
so every Receive Location refuses every Stream at authentication; it serves no
Storage node and refuses a configuration listing `[storage] nodes`; and no
PostgreSQL or SQL Server client exists. The message path is built and tested
inside the runtime's tests, which hand it stand-in gates; the program an
operator installs runs none of it. Needed: the identity technologies of
ADR-0050 linked into the service and chosen by configuration (ADR-0068: handed
in), a Storage node in the service, and the first database server client.
`architecture.toml` `[implementation]` says the same per capability.

*Narrowed the same day.* The owner: *The first stream will come from
somewhere, it will carry its identity via transport or on its message*, and
*that goes for all streams*. The runtime drops nothing a transport hands
over: what it observed of the sender, under `context::property`'s names, and
its headers reach the first gate, and the headers the Message Context
(`receiving/received.rs`); every receiving technology says what its arrival
carries (`transport::ArrivalIdentity`), held by its own loopback rounds. The
service links the identify technologies that need no configuration — `ip`,
`jwt`, `api-key`, `username` — so a Stream's transport claim reaches the
gate, and a refused attempt is audited with the claim, its layer and how it
was established (ADR-0013 clause 1). What remains of the first part:
`accept.party` — the Parties themselves are configuration since 2026-10-13,
`[[parties]]` (ADR-0028, amendment 2026-10-13) — the `location` policy, an
authenticator the configuration sets up with its credential store, and a
receiving transport that terminates TLS so `mutual-tls` has a peer
certificate to verify. A message identity — an X12 `ISA06` — reaches the
gate only after transport authentication passes and a contract or the
`message` identifier is configured, so the service cannot show one yet; the
runtime's tests do (`arrival.rs`).

*Repaired 2026-10-19: the service receives from a configured Party.*
`accept.party` is read (`configure::Accept`), each name a `[[parties]]`
Party, and a name none declares is a problem the binding reports; a
verified identity resolves to the Party holding it (the runtime's
`Recognized`, `configure::party::holding`), and a Location naming Parties
refuses at authentication one resolving to another or to none
(`Refusal::NoParty`, new; clause 1 of ADR-0019, amendment 2026-10-19). The
`location` policy is set up from the Receive Locations a node starts
(`Linked::receive_policies`) and admits at each what its `accept` takes.
`xmip-service` links `identify/certificate`, `authenticate/mutual-tls` and
`authorize/location`, and its tcp terminates TLS where a Receive Location
says `tls = true`: the node's `[provision.receive]` certificate, read from
the operator's files as it starts, presented, and a client's verified
against the anchors given there before a byte of content is read
(`transport::Guard`, `tls::peer`; ADR-0033, amendment 2026-10-19). Proved in
the assembled service by `.src/test/service/accepted.rs`: a configured
Party's Stream received over TLS with `mutual-tls`, another Party's refused
at authentication and audited with its claim, a stranger's certificate
refused in the handshake; and in each module changed.

*Repaired 2026-10-20: one node carries a file in to a file out.* The
owner's rulings of 2026-10-19, each built and recorded:

- *The `location` policy also admits each Send Location the node starts,
  as it admits Receive Locations* — set up from every Location the node
  starts (`Linked::location_policies`, `linked::Started`; ADR-0050 and
  ADR-0068, amendments 2026-10-20), so a Message routed onward is sent.
- *Each `[[parties]]` entry gets an `id` key holding a UUIDv7 written once
  with the Party* — `configure::PartyConfiguration::id`, minted by
  `PartyConfiguration::new` and by the designer's `AddEntry`; a Party
  without one is refused in words; `configure::party::id`, the place, is
  deleted (ADR-0019, amendment 2026-10-20).
- *Identities state their mechanism and purpose* — `{ mechanism, purpose,
  value }`, `purpose` `receive` or `send`; a verified identity resolves by
  the mechanism that verified it, for `receive` (the same amendment).
- *A file Send Location's address names a directory*, each Message written
  under the name it was received under, `file.name` in its context
  (`context::property::FILE_NAME`, kept by the runtime at arrival); the
  `out/out` of a relative address is gone; the atomic write and the
  node-named temporary file are kept (ADR-0024, amendment 2026-10-20).
- *A drop folder's implied identity is linked into the service and chosen
  by configuration* — `xmip-core-authenticate`'s `Circumstance`, in every
  build (`authenticate` is a required feature of `xmip-service`), taken
  where a Receive Location's `accept.mechanism` names `circumstance`
  (ADR-0019, amendment 2026-10-20).

Beside them: the TLS handshake a Receive Location terminates is read under
its own bound, `[tuning] receive_handshake`, apart from the Location's
wait, and the service test is back to the Location's tenth of a second,
passing at `RUST_TEST_THREADS=4` across six runs (ADR-0033, amendment
2026-10-20); and every one-machine example site declares `storage`
(ADR-0056 and ADR-0015, the amendments of 2026-10-20). Proved in the
assembled service by `.src/test/service/carried.rs`: one node, roles
executing and storage, a file Receive Location accepting by circumstance,
the Loopback Application's Subscription, a file Send Port; ten files
dropped one after another each arrive whole in the send directory under
their names, counted in the node's audit.

**Measured against the millisecond rule.** From the node's claim of a
dropped file to the file whole in the send directory — read, the three
gates, the Ledger's write, the route, the Journey, the send step and the
sent file — took 6.2 ms, the fastest of five, on 2026-10-20, of which the
sent file's own write, sync and rename took 2.8 ms; and a file waited 64 to
77 ms for its claim at a 50 ms poll, about 1.7 s at the default. Repaired
the same day: the drop directory tells the Location of a file the moment it
lands, a file is finished once no writer holds it, and the poll is a
recovery sweep (`[tuning] receive_sweep`; ADR-0024, amendment 2026-10-20);
a Publication is answered before its sync, its sends prepared meanwhile and
let out only once it is durable (ADR-0018, amendment 2026-10-20). After:
the claim waits 1.57 to 1.79 ms; the carry takes 3.68 to 3.87 ms, the sent
file's own work 2.06 to 2.08 ms and the Ledger's durable copy of the payload
0.98 to 1.06 ms beside it, so Xmip's own share is 0.60 to 0.83 ms, held
under a millisecond beside the machine's own wake for each of its five
hand-offs between threads by `.src/test/service/carried.rs`, run alone.

*Repaired again 2026-10-20, under load.* The runtime's loopback node test
(`running.rs`, `a_node_carries_every_message_…`) went 0.8 to 1.2 ms over
its load alone and up to 2.8 ms beside the rest of the suite: each
Message's Stream chunk, written unsynced, waited out the previous
Message's Journey hand-on sync, since on Windows a write to the
write-ahead log's file waits while another thread flushes it. `RocksDB`
now writes its log at a sync alone (`manual_wal_flush`), a write not yet
synced going with its process; beside four processor-bound jobs the
Message took 0.23 ms less to 0.02 ms more than its load in six runs. The
same day a stop's one wake connection, lost with the machine's ports in
use, held the library tests 41 minutes; every listener's stop now knocks
until its accept has heard (`net::accepting`; ADR-0018, amendment
2026-10-20, *one kept from its processor*).

*Repaired 2026-10-21, run after run.* The machine ran out of ports after
many runs: one run of the runtime's library tests left 1,259 connections
waiting to close, every one a raw TCP Stream's sender, which closes first
since the connection frames the Stream. *Repaired again the same day, as
the owner ruled:* a tcp arrival closes normally again, the reset drafted
for it deleted; the runtime's eight senders carry their Messages over HTTP
on kept connections, the Xmip technologies whose protocol carries many
Messages on one connection keep theirs at both ends, and a connection
freed while a receive waits is waited on at once (`serving::Freed`). A run
of the runtime suite leaves 522 to 526 waiting to close where it left
1,306 (ADR-0018, amendment 2026-10-21); the loopback node test, still on
raw TCP, leaves 480 of them. A test process now holds its block of ports
(`net::fixture`), so
two test programs never share one, the plane test's race; a passed local
deadline cancels until its call has ended (`plane::deadline`), and the
local-endpoint tests join their stand-in's accept by knocking, two hangs
beside eight jobs. The loopback node's Message is held back by Xmip's own
processor time on the path, not its hand-offs: a plain wake beside it took
17 to 19 µs at the median, the path some 0.5 ms of processor time more
than its load in the test build. Beside four jobs it passed five runs in
five, 0.16 to 0.92 ms over its load; beside eight, six in ten (ADR-0018,
amendment 2026-10-21).

*Repaired again 2026-10-21, where the processor time went.* Sampled thread
by thread, the Storage node's writer took about 40 percent of the node
test's processor time: two batches a Message, its Publication and its
Journey's hand-on, each deciding (the due places half of it), sealing and
writing, and syncing. The test build was not the cause — built whole at
`opt-level = 3` a Message took 2.96 ms of processor time against 3.1 to 3.5
— so no profile changed. The defect was a wait: the writer synced each
batch before taking the next, so a Message's Publication waited out the
previous Message's hand-on sync, answered in 1.2 ms back to back against
0.53 ms apart. The sync is a thread of its own now, one sync for every
batch written meanwhile (`persist::storage::commit::Syncer`), and a data
key sets its cipher and keyed hash up once (`secret::DataKey`), where it
did so some sixty times a Message (ADR-0018, amendment 2026-10-21). The
node test beside four jobs and the suite, five runs: 0.47 ms less to 0.32
ms more than its load; beside eight, five runs in five, 0.52 ms less to
0.23 ms more. And the file-drop test's claim, 14 ms once beside a build:
on Windows a dropped file's turn is now the file held open, one open where
a turn file took four changes to the directory and an open more (ADR-0024,
amendment 2026-10-21); the claim takes 1.60 to 1.99 ms beside four jobs,
1.90 to 2.72 ms beside eight, from about 3 ms idle and 5 ms beside jobs and
a busy disk before.

What remains of it, the owner's to decide:

- **The path's processor time.** The writer's own work stands: about
  0.25 ms deciding and 0.24 ms sealing and writing per batch, two batches a
  Message, a fifth of it the heap; the due places found again
  (`due::settle`) are the largest single part. The test process still
  spends 2.8 to 2.9 times its load's processor time on a Message. Over
  kept HTTP connections, its load down to what the path's two requests
  cost, the loopback node's receive cycle took 1.0 to 1.3 ms over its load
  in three runs in four, the Publication's write through the writer 0.65 to
  1.1 ms of it (2026-10-21), so that test stays on raw TCP and its 480
  connections a run (ADR-0018, amendment 2026-10-21). On Linux, in the
  AlmaLinux guest, the node test fails by about 4 ms; the eight senders,
  over HTTP now, and the deadline test, with `/run/xmip` made, pass.
- **Seen under load the same day, not this problem's** — and repaired on
  2026-10-21, both of the plane's: a surface connected to the local
  endpoint twice through the pipe library, which the runtime no longer
  uses (ADR-0014, amendment 2026-10-21). The named pipe transport
  (`xmip-core-transport-named-pipe`) accepted and read through that
  library too; closed the same day: the runtime's calls moved down to
  `net::pipe`, which the runtime's local endpoint and the transport both
  make their pipes through, one client one connection and an accept
  returning only with a client, on Windows and as a FIFO on Unix, and
  `interprocess` is deleted from the estate (ADR-0014, amendment
  2026-10-21, *the named pipe is placed once*). Beside four or
  eight jobs, `plane`'s
  `a_connection_on_this_machine_is_proven_and_answered_within_the_millisecond`
  took 1.24 to 1.60 ms of processor time and failed one or two runs in five
  beside four, four in five beside eight (problem 35's); the library's
  `a_caller_lends_its_account_for_identification_alone` read nothing from
  its client three times in some twenty runs beside four; and the paced
  fan-out read 277 and
  304 chunks for 132 twice in 23 runs of the Ledger tests beside four
  (none in eight runs before the sync's thread, at most 221).

- **Decided by the owner, 2026-10-21:** the Ledger's disk sync counts as
  load for the millisecond rule, as `carried.rs` counts it; the bounded
  fan-out wait (ADR-0018, amendment 2026-10-20, *one kept from its
  processor*); unsynced writes are lost with the process; the defaults —
  `[tuning] receive_sweep` 1 s, five kept chunks per other departure. Not
  decided, still drafted: the Storage node's sync on a thread of its own,
  and on Windows a dropped file's claim held open (ADR-0018 and ADR-0024,
  amendments 2026-10-21).
- **Linux and macOS take a file at the second listing**, at the next change
  or the sweep, since the system does not say whether a writer holds it;
  the watch hears a close after writing there, and telling it by name
  would let the claim take that file at once.

What remains of the first part:

- **The secrets a Location presents are kept, repaired 2026-10-29.** A
  Location names its proof with `secret = "<name>"` and the secret is kept
  in the Administration Database's own `secret` table, its value sealed by
  Xmip whatever store keeps it, read as the Location connects, set with
  `Set-XmipSecret` and never read back out (ADR-0019, ADR-0015, ADR-0063,
  ADR-0064 and ADR-0014, amendments 2026-10-29); SFTP presents a password
  or a key, FTP, FTPS, HTTP and HTTPS a password, and SQL Server,
  PostgreSQL, MySQL, MariaDB, Oracle Database and IBM DB2 the login's
  password. Built in pieces by the owner's order of the same day, the command
  line's `xmip secret` with them, and the GUI's Secrets page and the VS Code
  extension's `secret` on 2026-10-30 (ADR-0014, amendment 2026-10-30): the
  extension reaches no node, so it suggests the key and not a node's secret
  names. Not built: a `certificate`
  secret presented by any technology (a client certificate over HTTPS or
  FTPS); the other technologies that log in — AMQP, MQTT, RabbitMQ,
  ActiveMQ, IMAP, POP3, SMB, S3 and the vendors' — which refuse a Location
  naming a secret as the node starts; and one key the Storage nodes in
  front of one database server share, so a value one seals another opens:
  each seals under its own administration data key today, and no server
  backend is built (ADR-0063, amendment 2026-10-29). An authenticator a store of verifiers
  sets up on receive (`password`, `basic`, `digest`, `scram`, against
  `authenticate::store`; `api-key` and `bearer` against
  `authenticate::secret`) is still not linked, so a Location accepting one
  is refused as the node starts. What the owner agreed on 2026-10-28 and is
  not built: a probe asking the far end which proof it takes; Xmip issuing
  a key pair or a client certificate from the cluster's authority, `accept`
  defaulting from the Party's identity (step 4); and a hand-out per Receive
  Location telling a Party the address to use and how to trust Xmip, on
  every surface (step 5).
- **Decided by the owner, 2026-10-21:** the `location` policy admits
  whoever the Location's mechanisms authenticated, at a Receive and at a
  Send Location; a TLS handshake read waits five seconds by default; a
  drop folder's circumstance value stays the whole file path — the folder
  was considered and declined (ADR-0019, amendment 2026-10-21); a Message
  without `file.name` is named from a pattern configured on the file Send
  Location, falling back to the Message's identifier — built the same day,
  the Location's `name` setting, `{message}` in it the identifier (ADR-0024,
  amendment 2026-10-21). Still drafted: the certificate a TLS handshake
  verified is the first claim the first gate takes, and the circumstance's
  verifier lives in the authenticate capability, not a repository of its
  own (ADR-0050, amendment 2026-10-20).
- **Not reported or not published:** the peer's chain (`tls.peer.chain`),
  so `certificate` over a terminated handshake has nothing to walk; a
  failed handshake, which no audit records; which Parties a Location takes,
  which the node's publication and the Topology do not show (one Party per
  side, `any-party`); renewal of the `receive` certificate while a node
  runs (problem 27).

The second part, a Storage node in the service: a node declaring the
`storage` role is its own embedded Storage node in the assembled service
(ADR-0056, amendment 2026-10-20) — RocksDB and SQLite under its data
directory, sealed under the key store `[store]` names (`embedded-storage`,
assembled) — and since 2026-10-22 it serves the others at `[storage]
listen`, and a node whose `[storage] nodes` lists Storage nodes reaches them
with the identity `[storage]` names (`storage-nodes` and `storage-standby`,
assembled; ADR-0056, amendment 2026-10-22). The third part, the first
database server client, is not built: each data domain's table is read and
checked, and a node naming a server is refused as it starts
(`database-server`, decided).

## 34. The failure backlog lives in the node's memory

Found by the outside review of 2026-10-08. The send step keeps every
Journey that failed waiting in a queue it sends, with its reason
(`send_step::figures`), so a Port's failed count and its oldest hundred
can be published; admission bounds what is in flight, not this. Repaired the
same day: a Journey read Failed again is found by its Journey at once, not
by looking through all of them, and a whole read of a queue forgets every
place passed over that has left it. What remained: memory still grew with
the number of failed Messages kept. Needed: the count, and an index of
the failed Journeys of each queue, kept by Xmip Storage in the Ledger and
read from it, with the node keeping a bounded window of the oldest.

Repaired 2026-10-16. The hand-on that writes a Journey Failed names its
queue and why (`HandOn::failed`), and Xmip Storage enters it at the end of
that queue's index of failed Messages — the `failed_message` and
`failed_message_places` tables, numbered as every queue is — and marks its
place in the queue failed (`held.failed`), in that one write; an operator's
Retry or Dismiss takes it out in its own (`HandOn::cleared`). How many wait
is one read of the index's places (`XmipStorage::read_failed`). The node
keeps per Send Port that count and the oldest `[tuning] failed_window` (a
hundred by default), read again only where the index's places moved, and
publishes them; `xmip_failed_messages_v1` pages the rest from the index,
each page one read, its `next` a place in the index. A scan passes over a
place marked failed without reading its Journey, except where it blocks a
Sequential Port's sequence (`runtime-model.md` section 10, corrected
2026-10-16; `tests/ledger/send_bounded.rs`). What remains: a Journey
written Failed before this change, or by a writer that does not name its
queue, is in no index — before the first release nothing migrates it; and
a publication's list (`SnapshotOperator`,
`PublicationReading.FailedMessagesWithin`) still pages by the place in the
Send Port's queue while a node's own list pages by the place in the index:
a publication carries no index places. Said so precisely, the same day, in
`IOperatorSurface.FailedMessages`, `xmip message --offset` and
`Get-XmipScope -Offset`; making the two one would mean publishing each
Journey's place in the index.

## 36. A green root CI run is not evidence for the composed estate

Raised by the outside review of 2026-10-08. The root workflow
(`.github/workflows/rust.yml`) resolves the dependencies from the branches
ADR-0005 tracks, not the module revisions the root pins, and the .NET
operator surfaces' workflows (`module/foundation/abi/.github/workflows/verify.yml`)
run only by hand. A green root run therefore does not show that Desktop,
Web, CLI and PowerShell work together at the estate's recorded revisions;
`xgit` verifies that locally before it pushes, and leaves no record of it.
The review asks that each landing publish an identifiable verification
result beside root CI: the revisions it resolved and the surface checks it
ran.

## 37. A configuration has no revision a node accepts or runs

Raised by the outside review of 2026-10-12. Repaired the same day: a
save's write and its slices' delivery are one step under the cluster
file's lock, a delivery whose cluster text a newer save replaced delivers
nothing, and every slice is written through a file of its own and renamed
into place. What remains is a design question, the owner's: no
configuration carries a revision, so no surface can say which revision is
saved, which each node accepted, and which is running, and saved,
delivered and applied are told apart only in each screen's own words
(*takes effect when the node starts again*). The review asks for an
immutable revision carried from save through validation, slicing,
delivery and the node's acceptance (problem 31's push), a node refusing
one older than it holds, and the four surfaces answering the same four
questions: saved, accepted, running, and what resolves the failure.

## 38. Admission bounds Journeys, not bytes

Raised by the outside review of 2026-10-12. The send pool admits a bounded
number of Journeys, and each reads its Message whole before its transport
sends it, since `Transport::send` takes a byte slice
(`transport/.src/protocol.rs`), so resident memory grows with the sizes
of what is in flight. The audit file reader kept every record it had read
(repaired for audit 2026-10-16, below); problem 34's backlog, which grew with the
failures, is kept by Xmip Storage since 2026-10-16, the node holding a
bounded window of it. Needed: a send that streams through the transport capability,
taking the Message a chunk at a time as `runtime-model.md` section 10
already allows; a byte budget beside the pool's count; audit queries read
a page at a time from Storage.

Widened by the performance review of 2026-10-12. A fan-out's departures
each read the same Stream whole. Receive takes every arrival a transport's
`receive` returns before it waits for room (`receiving.rs`), and the file
transport claims a whole directory listing at once, so what waits in memory
grows with the batch; excess should stay at its durable source. Each
Receive Location has a pool of its own, at most twice the hardware threads
by default, so a node of many Locations has no ceiling of its own: needed
is a node-wide execution and memory budget beside each Location's
isolation. The audit file reader filtered, grouped and sorted the whole
history it kept for every query, whatever page it returned, and the
keeper's inbox was unbounded.

Repaired for audit 2026-10-16. The reader keeps no record: `audit_store::ask`
keeps an index of each audit file (`audit_index`) — blocks of 64 records by
their bytes, each with its earliest and latest time and its count of each
kind, a kind being what a query asks by but time and identifier — extended
by what was appended since. The counts, groups and actions come from it;
the page from the few blocks it can be in, walked from the page's own end
and stopped where the page is found, read from the file and kept parsed
while they fit (`audit_cache`). What a process keeps of its audit is
bounded in bytes by `audit_store::BUDGET`, 16 MiB, half the indexes, half
the blocks read lately: an index over its half merges its older blocks, so
the newest stay short. A surface reads no node's configuration, so the
budget is a constant, not `[tuning]`. A verification and a page sorted by
the summary read the file through a piece at a time, holding the page
(`audit_scan`). The keeper's inbox holds at most 4,096 hand-overs and, full,
makes the writer wait: an audit record is evidence and is never dropped or
sent to the operating system's log for being late (ADR-0062 clause 3,
ADR-0070 clause 5; ADR-0062, amendment 2026-10-16). The pages are those a
whole read gives, held equal over every column, order, filter and time
window, and a page took 3.1 ms over 2,048 records and 3.5 ms over 204,800
on a machine at 96% load (`audit_store`'s tests). What remains: a deep
page into an old history reads a merged block, longer the longer the
history; a page sorted by the summary and a verification read the whole
file; a query naming a time counts the blocks within it; looking up a
record that is not there reads every block; and audit is read from the
program's file, not yet from Xmip Storage, where ADR-0062's amendment of
2026-10-01 puts it.

Repaired for sending and receiving 2026-10-19 (`runtime-model.md` sections
3, 5 and 10, corrected 2026-10-19; ADR-0018, ADR-0024 and ADR-0057,
amendments 2026-10-19; ADR-0031's `[tuning]` list).

- **A send streams through the transport capability.** `Transport::send`
  and `send_keyed` took a byte slice and are gone from what a technology
  implements: it implements `send_from`, handed an `Outgoing`
  (`transport/.src/outgoing.rs`) — the Message read from the Ledger a chunk
  at a time, its length known before its first byte, opened from its start
  by every read so a kept session's resend reads it again, held to its
  length, and its key — written once in the capability with what every
  technology needs of it: `write_to`, `pieces` in requests of a protocol's
  own size, `gather`, and `checked`, which keeps a send whose claim was lost
  while a large Message was read from starting. `send(target, bytes)` is
  `send_from` over bytes in memory, for a test or a tool. Every technology
  says whether it streams or gathers, and why (`Transport::sending`, no
  default). Ten stream: file, TCP, a Unix domain socket, a named pipe, MLLP,
  WebSocket, FTP, SFTP, SMB and NFS. The rest gather, most because their
  protocol needs the whole body first — a datagram, a frame, a record with
  its CRC, a signed or encrypted message, an INSERT's literal.
- **A byte budget beside the Send pool's count.** A send holds what its
  transport holds of the Message from the node's byte budget for sends
  (`runtime`'s `budget`, `[tuning] send_chunks_per_thread`), waiting for
  room before the transport's I/O: the whole Message where its transport
  gathers, six chunks of reading where it streams, as measured.
- **A fan-out's departures share their reads.** The departures of one
  Stream in flight on a node take each chunk from one read of it, lent,
  while they keep up (`runtime`'s `stream_share`, over
  `persist::storage::ChunkReader::shared_from` and `next_chunk`); one
  further behind reads on from Xmip Storage itself. *Repaired 2026-10-20* (the owner: *a departure that falls
  behind starts reading at the chunk it reached, catches up from Storage
  over only the chunks it missed, and rejoins the shared read; never from
  chunk 0 or the whole Stream*): the read kept two chunks, less than a
  millisecond of a far end's pace, and one behind read the Stream again
  from its first chunk and never came back, so on a loaded machine four
  paced departures read 264 or 528 chunks for 132. It now keeps one chunk
  for a departure alone and five for each other
  (`stream_share::KEPT_PER_READER`, the room each one's own read would
  have held), one behind reads from the chunk it reached
  (`ChunkReader::shared_from`) and rejoins once among the kept chunks;
  under the full runtime suite in parallel the same test read 132 to 176
  (ADR-0018, amendment 2026-10-20). *Repaired again 2026-10-20*: on the
  landing it read 425, since departures paced alike never close a gap a
  stall opened, and one behind came back only where the kept chunks came
  back to it. Now one about to be left behind holds the one ahead back for
  as long as it keeps taking, what is kept counted in chunks, and one that
  took nothing for `[tuning] stream_stall` is left behind, so a stalled
  Send Port holds the others back for that, once (ADR-0018, amendment
  2026-10-27); and
  one behind reads from a read of its Stream that reaches its place, or one
  of its own the next behind shares, the reads coming together as their
  places meet. Under the full suite in parallel beside four
  processor-bound jobs, six runs, it read 132 to 196 (ADR-0018, amendment
  2026-10-20, *one kept from its processor*). Left, the owner's: whether a
  bounded hold-back is the bulkhead he wants.
- **Receive takes no more than it has room for.** A receive asks its
  transport for at most as many arrivals as its Location's pool has threads
  free and the node has places (`Transport::receive_up_to`); the rest stay
  at the far end. The file family claims no more of a listing than that,
  the rest left as dropped for the next listing (`claim::Claiming::take`);
  an object store's listing, a SQL query's rows, a kept subscription, SMB,
  NFS, WebDAV, IMAP and POP3 listings, Kinesis, SQS, Pub/Sub, Service Bus,
  Kafka, Redpanda, Redis Streams and JetStream hand over no more.
- **A node-wide execution and memory budget.** Beside each Receive
  Location's own pool the node bounds the arrivals it carries at once
  across all its Locations (`node_receive_threads_per_hardware_thread`)
  and the bytes those carries hold (`receive_chunks_per_thread`), every one
  a default only in `[tuning]`, the defaults the assistant's drafting.

Measured (`runtime`'s `tests/ledger/send_streamed.rs` and `roomed.rs`, what
the test program allocated counted): a 64 MiB Message carried in and sent
to four Send Ports held 1.1 MB at most; four departures at a far end's pace
read an 8 MiB Stream's 132 chunks 132 times; sends that gather a Message as
large as the byte budget went one after the other; two Locations of 32
threads on a node of 16 places never had more than 16 arrivals taken and
untold at once; 32 Streams of 4 MiB, 128 MiB whole, held 2.3 MB at most
under a receive byte budget of 4.1 MB.

What remains:

- **Technologies that could stream gather.** The HTTP ones — http, WebDAV,
  Azure Blob, Google Cloud Storage — because the HTTP client
  (`net::http`) writes a request whole, its length counted from it; SMTP,
  to dot-stuff its `DATA` whole; Bluetooth, whose in-process link takes one
  write whole. Each says so in its `sending`, and its byte budget counts
  the whole Message.
- **Departures started apart read apart.** Four departures of a 64 MiB
  Message to far ends faster than Xmip Storage's read took 4,184 chunk
  reads for 1,045 chunks: a departure more than two chunks behind reads on
  by itself. Holding a fan-out's departures together would make one read
  of each chunk certain and would couple their far ends' pace, which the
  bulkhead forbids today; that is the owner's to decide.
- **A carry holds seven chunks, not two.** A carry of a 64 MiB Stream held
  seven chunks at most where section 3 designs for two, the chunk written
  and the one read ahead: Xmip Storage encodes and seals each chunk written
  in copies of its own. The budget counts what was measured, eight; the
  copies are not removed.
- **Some receives still take what they are handed.** A query's rows are
  all read before the bound is applied (the query itself is not bounded);
  a Kafka or Redpanda fetch brings more records than are taken, read again
  later; a technology that hands over a whole message holds it before its
  carry, bounded by the room it was asked for, not by bytes; and a
  connection whose far end let go of what it sent — COTP, SECS/GEM, syslog
  over TCP — is taken whole.
- **The C ABI's transport table** has no place for `sending` or for a
  receive's bound (ADR-0057, amendment 2026-10-19).

## 42. The setup packages are written and not yet built

The owner, 2026-10-13: *Leave it as a quest for later, but it has to be
done.* `xmip-service --install` and the portable archive are built and run on
Windows (ADR-0015, amendment 2026-10-13). What remains, each needed before a
release:

- **The Windows MSI and its winget manifest.** WiX 7 builds nothing until its
  Open Source Maintenance Fee terms are accepted — the owner's decision.
- **The Linux `.deb` and `.rpm`, and the macOS `.pkg`**: written under
  `deploy/package/`, never built; they need Linux and macOS builds, which the
  owner has switched off for now. Their systemd and launchd branches of
  `install.rs` have not been compiled.
- **Signing**: Authenticode, Apple Developer ID with notarization, Linux
  package signing.
- **The service account** (open problem 28) and whether the starter grants
  local tools more than Observer (ADR-0014, amendment 2026-10-13).

## 45. Embedded Storage nodes have no witness, and a standby behind is copied whole

Built 2026-10-22, drafted (ADR-0056, amendment 2026-10-22): embedded
Storage nodes are a primary and its standbys, settled among themselves, a
standby promoted once its primary is gone. Three things are left:

- **No witness.** The owner's design of 2026-10-01 had *a witness holding
  the claim on which node is primary*, and IT's infrastructure calling a
  promote. Without one, two sides of a network partition can each promote a
  primary; a node that met the later epoch never asks the earlier, and a
  primary that meets a later epoch steps down, but writes taken by the
  earlier one meanwhile are lost when it follows the later. Proposed: a
  witness of the cluster's own — any node, asked like a Storage node —
  whose word a standby needs before it is promoted; or the promote kept a
  command, with an Operator's act on every surface.
- **A standby behind is copied whole.** A standby that restarts after its
  primary did, or falls further behind than `[tuning] storage_kept`, is
  wiped and copied whole, every record read once over the wire; a primary
  restarting starts a history of its own, so every standby is copied whole
  then too. Proposed: the primary's numbering kept in each database, so a
  restarted primary goes on and a standby takes on from where it is.
- **The loss window of a kill.** The owner accepted it on 2026-10-01; it is
  unmeasured. Proposed: a kill test that says how many writes a killed
  primary had not handed on, under load.

## 46. A Journey published on one node waits for another's send scan

Measured 2026-10-22 in the Playground at level 1, every node a process
(ADR-0028, amendment 2026-10-22): a file received on one node and sent by
another took about 630 ms from its drop to its arrival, the median, where
one received and sent by the same node took about 7 ms. The sending node
learns of a Journey another node published only by reading its Send Port's
queue every `[tuning] send_scan`, one second, since Xmip Storage tells no
node of a write another made — beyond a millisecond and apart from load, so
a defect by the millisecond rule. Proposed: a wait on a queue asked of the
Storage node, answered as a Publication or a hand-on puts a Journey in it,
which the sending node's scan waits on instead of its interval; the
node-to-node sync plane (ADR-0067) is the other way, and decided, not built.
A Work Process's queue waits on the same scan (ADR-0066, amendment
2026-10-22): a Journey published for it on another node is taken up at the
next `WORK_SCAN`.

## 47. Debatching on receive is decided, not built

Decided 2026-10-22 and 2026-10-27 (ADR-0031, amendments of both dates;
ADR-0066, amendment 2026-10-27): debatching runs on receive and in an Xmip
Work Process, one splitting implementation called from both, a splitting
unit of the capability `debatch`; batching runs only in a Work Process
(the owner: *It is not stream friendly.*). A debatch is all or nothing,
its records in their inbound order, each written as soon as it is
complete and routed only once every record is split and validated, each
then a Journey of its own carrying three values that keep the records
together (drafted `debatch.message`, `debatch.position`, `debatch.count`).

**Built**: a Batch (`xmip:batch`) and a Debatch (`xmip:debatch`) run from
the Ledger in a Work Process (`xmip-core-runtime`'s `work_step`); the
splitting placed once, `xmip-core-runtime`'s `split`; a refused record
throwing `record-refused` with its position; the `debatch` capability,
`[[debatches]]`, the `debatch` attachment on a Receive Location or Port
and their refusals (`configure::step`).

**Open**, the receive's half: `arrival` calling `split::Splitting` after
Message creation, which needs three things not built — the Contract run on
receive, so each record is validated before any is routed; one write
routing several Messages, a Publication of many where Xmip Storage's
Publication holds one Message today; and removing the records written when
one fails, an Xmip Storage operation it does not have. And a splitting unit
loaded through the C ABI, which waits for compiled units to run (a node
gives a Work Process no unit yet, so a Debatch throws `no-unit`). Until
then a node refuses to start a Location or Port attaching a Debatch.

## 48. The surfaces' library carries no technology's declaration

Decided by the owner, 2026-10-22 (ADR-0064, amendment 2026-10-22): the
runtime library the surfaces load carries every technology's declaration —
names, settings, kinds and words, not the technologies' code — so every
Location's settings are suggested and checked on every surface. Not built:
today the library carries what a node in its process loaded, which for a
surface is nothing, so no transport, contract or setting — the file Send
Location's `name` among them — is suggested in VS Code or on the desktop.
Each declaration is a `const` in its technology's crate, beside the code.
The owner chose the way the same day, from two (the other a catalogue
generated at build time): a `declaration` feature in each technology
crate, its code and its dependencies behind the default feature, so the
declaration stays placed once. The plan, its own work after the current:

1. A test that a technology built with its declaration alone pulls in no
   heavy dependency.
2. The crates in batches, each landed in its own repository.
3. A gathering crate last, which the surfaces' runtime build links every
   declaration through, since a platform service depends on no technology
   (`architecture.toml`).

## 50. Validation and the path languages hold a Stream whole

The standard units stream (ADR-0066, amendment 2026-10-22), and the
contract technologies Validate calls, and the path languages Promote and
Demote call, mostly do not: they read `Stream::text` or `Stream::bytes`, so
what one holds grows with the payload. Recorded as the owner's rule asks
(*streamed, bounded in memory*), each with its bound and why:

| Technology | Holds | Why |
| --- | --- | --- |
| `json-schema`, bare | a piece and one string | streamed since 2026-10-22: well-formedness read through `serde_json`'s reader and discarded |
| `json-schema`, bound | the document | the schema's keywords look across it (`required`, `oneOf`); a streamed evaluation is a validator of its own |
| `xml-schema`, `schematron`, `wsdl` | the document, as `roxmltree`'s tree | the XML Schema subset and Schematron's XPath read a tree; well-formedness alone could stream through `quick-xml`, which checks less than `roxmltree` does |
| `csv`, `fixed-width` | the text | the record walk takes a slice; `message::record`'s streamed walk (2026-10-22) is what a streamed check reads through |
| `edi-edifact`, `edi-x12`, `hl7-v2` | the text and its segments | the envelope checks count segments across the interchange; a streamed reader keeps the counts and one segment |
| `yaml`, `toml`, `avro`, `protobuf`, `fhir`, `openapi`, `asyncapi`, `graphql-schema`, `sql`, `toon`, `regex` | the text or the bytes | each parser reads a slice |
| path languages (`xpath`, `jsonpath`, `dot`, `json-pointer`, `fhirpath`, `index`, `regex`, `edi`, `hl7-v2`) | the form they parse, once per Message | a path reads a parsed form shared by every path of the Message; a promotion that stops early (a Content Selector's `stream-prefix`) is a reader of its own |

Each is bounded by the payload and by nothing else, and each holds it once
however many gates read it (`Stream::load`, `path::Content`). The order is
the owner's to decide; the cheapest first are CSV through the streamed
walk and bare XML through `quick-xml`.

## 51. A module is updated only on the end user's request, and no surface asks yet

Decided by the owner, 2026-10-22 (ADR-0045, amendment 2026-10-22): *The
offline units may be updated, but on the end user's request, after a
review.* A module's version is pinned by the configuration
(`[modules.manifest.identity] version`) and nothing updates it by itself;
updating is an operator's act on every surface — showing what changes (the
version, the manifest, the dependencies, the offline declaration), taking the
end user's approval, audited (ADR-0062). Not built: no surface offers the
act, and no review is shown.

## 52. CMS and JOSE have no engine

Encryption and Signature take `format = "cms"` and `format = "jose"`
(ADR-0066, amendment 2026-10-22), and no engine implements either: a step
naming one is refused when it is opened, in words. OpenPGP's engine, `rpgp`,
is built. Neither format streams as its common forms are written — CMS in
DER needs its lengths before its content, so a streamed CMS is BER with
indefinite lengths, which `xmip-core-library-asn1` refuses; a JWS or JWE in
compact form spells its whole payload in one token — so each is a design of
its own, and the dependency (the estate's `aws-lc-rs` and asn1 reader, or a
third party's) is the owner's to choose. A key protected by a passphrase is
not opened by any engine yet: where a passphrase is kept is the secret
capability's (problem 29).

## 53. The XSLT engine pulls in url's DNS lookup

Stylesheet's first engine was `xrust` (XSLT 1.0, Apache-2.0), built as
`xmip-core-transform-xrust`. It depends on `url`, not optionally, and
`url`'s `Url::socket_addrs` resolves a host name through the standard
library's `ToSocketAddrs`: a name lookup over the network. The offline gate
(`test/Offline.Test.ps1`, ADR-0045, amendment 2026-10-22) admits no crate
that can reach a network, even where nothing calls it, so the engine is not
linked and Stylesheet has none: a step naming one is refused when it is
opened. The repository `xmip-core-transform-xrust` exists and is not
mounted. Open: an XSLT engine whose dependencies reach no network — `xrust`
without `url`, upstream or by its fetcher taking a path, or another
engine.

---

## 54. Human tasks and waiting on people

The owner, 2026-10-22, of the Work Process's BPMN 2.0 subset: *Human tasks,
waiting for an email, text or a phone call can wait.* A BPMN `userTask` or
`manualTask` is refused in words today (`xmip-core-process-bpmn`'s
`refused.rs`; ADR-0066, amendment 2026-10-22): Xmip runs no human workflow,
and a Work Process is not one unless that workflow is represented by Xmip
configuration and runtime state (`runtime-model.md` section 22). Later: what a
task for a person is in the Ledger, who may complete it and on which surface,
and how a reply by email, text or phone reaches the waiting Instance — most
likely a Receive Location whose Messages correlate to it like any other.

Beside it, recorded the same day: **other design formats come later**, each a
technology behind `process::DesignFormat`. WS-BPEL 2.0 is one. The Open
Workflow Specification is another only where a technology for it can be built
that explicitly works offline: its catalogs, `use` resources and endpoints may
name remote documents, and such a technology resolves locally only and
refuses a remote reference at design and compile time (the owner,
2026-10-22: *We can only use standards, code and compiled units that
explicitly work offline!*).

## 55. Failures are accumulated and reported as a summary with details

Decided by the owner, 2026-10-27 (ADR-0013, amendment 2026-10-27):
*Failures during processing (Receive, Promote, Transform, Processing,
Demote, Send) shall be accumulated. The caller shall get a summary and
detailed information of what failed. Each failure would be tedious to
handle*, and *The same goes for Prepare, summarize failures, then report
back.* So in Prepare, Receive, Promote, Transform, Processing, Demote and
Send, a stage goes on past an item that fails, gathers every failure, and
fails once. And the same day: *All failures in each stage through Xmip
shall report what, where and if possible why. Like a compiler, just
batched per stage.* Each failure says what (a code and a message), where
(the stage, the artifact, the place inside the data) and why where known;
a stage's report is a summary line, then a block per failure.

**Built**: the shape, `xcore::Outcomes`, `xcore::Succeeded`, `xcore::Failed`
and `xcore::Place` (the field names decided with the owner's leave: `stage`,
`item`, `total`, `succeeded`, `failed`; `position`, `artifact`; `code`, `message`, `stage`, `artifact`, `at`, `cause`;
`position`, `offset`, `line`, `column`, `path`), and debatching reporting
through it (`xmip-core-runtime`'s `split`: code `record-refused`, the
unit as the artifact, the record's position). A splitting unit says only
a reason today, so a record's finer place and cause wait for the unit
trait to carry them.

Also decided the same day: *Receive, stop with accumulated errors.*
*Process, stop with accumulated errors. Send, stop with accumulated errors.
Sometimes the error has to burst out, that is fine. But it is preferred to
get accumulated errors per stage.* A stage collects every error it can;
where it has any, the path stops at the end of that stage and reports
them, and no later stage runs, not even as a trial. A failure that cannot
go on may stop the stage at once, reported in the same form.

**Open**: every other stage. Which items a stage counts — a Preparation's
steps, a receive's Streams, a send's Locations — is each stage's to say.

## 56. A store capability has no module ABI section

Decided by the owner, 2026-10-27, resolving problem 7: *Why not use the
ABI, there shall not be any duplication of code unless it is modulewize.*
A store is a capability with a section of its own in `xmip_module.h`; each
store technology — postgres, s3, elasticsearch, otlp and the rest — is one
loadable module behind it, written once; audit, report, observe, retain
and archive stay five modules, each with its own policy and tables, and
each reaches its store through that section. Not built: the section, its
Rust mirror in `xmip-core-abi`, and the five moved onto it.

## 57. Cloud technologies named without their vendor

Decided by the owner, 2026-10-27, resolving problem 8: option A, always
name the vendor. Not done: `s3` renamed `aws-s3`, and every other cloud
technology that names no vendor renamed the same way, in
`architecture.toml`, the repositories, the crates, the configuration words
and every document that names them.

## 58. Resilience and exclusiveness are not pluggable

Decided by the owner, 2026-10-27, resolving problem 9: *I thought we left
exclusiveness behind us* (ADR-0024), and *There might be some else who want
to do better on 'resilience' and 'exclusiveness'.* Resilience and
exclusiveness — the Correlations and the claim through Xmip Storage —
become pluggable capabilities, each with a section in `xmip_module.h`, Xmip's
own the built-in default. Not built: both sections, and Xmip's own
resilience guards and Sequence behind them.

## 59. A claim no authenticator checked

The owner, 2026-10-29: *First you present your identity, then you get
identified. Then we look to authentication, do your identification hold
up. When authenticated we look for Authorization, then you may enter your
load, stream.* No claim may reach authorization, or be recorded as proven,
without an authenticator having checked it (ADR-0019, amendment
2026-10-30). The receive spine already was so. Landed 2026-10-30: the
Message Context's `proven` read from the gate's verdict, not the
mechanism's catalog; every claim beyond one a layer recorded as claimed
(`IdentityFacts::unchecked`).

Not built, the assistant's drafts:

- **The operate plane's caller, through the one gate.** The listener takes
  a certificate's subject (`plane::served`) or the local endpoint's
  account as a bare name, and `xmip_act_admitted_v1` takes a host's word
  for proof (`proven`, a byte); `GatedOperator.Proven` in `Xmip.Surface`
  calls any non-empty subject proven, in .NET's spelling of a subject. The
  draft: a `peer-credentials` authenticator beside `Circumstance`; the
  plane's claim run through `authenticate::authenticate`; `admitted`
  taking the authenticated identity; `xmip_caller_proven_v1` answering the
  proven caller of a secure session (section 21) in place of the byte; and
  `GatedOperator.Proven` deleted. The ADR-0009 amendment comes with it.
  Today's rule stays: a caller nothing proved acts on nothing.
- **The SSH and FTP servers check the password.** `ssh::userauth` admits
  any password and calls the result `Authenticated`; the FTP server
  answers any `PASS` with 230; the SFTP far end chooses a user's directory
  by that unchecked name. These are Xmip's server sides for the loopback
  and the Playground's far ends. The draft: `ssh::userauth::Offered`
  (user, secret) asked of a check the server is handed, the check
  `authenticate/password`'s, the fixtures given real secrets. To settle
  first: `architecture.toml` says identity presentation is not a
  transport's, so the server is handed the check rather than linking an
  authenticator; anonymous FTP; and the real nodes' far end
  (`far_end.rs`), whose Locations' secrets would have to be enrolled
  there.

Waiting on the owner:

- **May a claimed identity be authorized?** `authorize::Subject::matches`
  reads no verdict, so an X12 interchange or a drop folder's circumstance,
  both claimed, meets a rule naming its Party as a proven identity does.
  Asked: whether a rule may require proven.
- **A claim a broker vouches for** — `amqp.user-id`, which the broker
  checks against its connection, an SQS sender id — has no authenticator,
  so a Location accepting it is refused. Asked: whether a third party's
  word counts, and as what.

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
                        sequence: the Work Process vocabulary settled; subscriptions
                        and location bindings in the configuration; file
                        claims by rename (ADR-0024); one transport trait; a
                        file-backed store that writes the Stream and Message
                        before execution; an xmip-service executable doing
                        phases 4-9 with technologies linked by feature (the
                        purpose-compiled runtime, deployment-model.md); a
                        Work Process branch in departure; checkpoint, resume
D. What a buyer checks  transformation (XSLT first: BizTalk maps are XSLT);
                        tracking, message search and resubmit; EDI
                        acknowledgements and Party agreements;
                        sign, encrypt, compress (prepare); secrets; an
                        OpenTelemetry exporter; a signed release with an SBOM
                        (the Cyber Resilience Act's reporting duties began
                        2026-09-11); BizTalk artifact import
```

Phase D: the routes designer's first slice is built, 2026-09-26 (ADR-0064):
the Xmip Application document and the node's binding in `configure`, and
the designer in the VS Code extension; running Applications in the
Playground is the next slice.

Phase D's transformation and prepare are standard units since 2026-10-22
(ADR-0066, amendment 2026-10-22): XSLT through the engine a step chooses,
none linked yet; XML, JSON and CSV converted, streamed; compression,
character and transfer encoding; OpenPGP encryption and signature through
rpgp. A node runs none of them yet, and CMS, JOSE and XSLT have no engine
(problems 50 to 53).

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
1. Run a node for real                 the runtime runs all nine startup
                                       phases (2026-09-28):
                                       `running::Running::start` takes a
                                       node's configuration and the
                                       technologies the program starting it
                                       linked, loads each once (a library
                                       through the C ABI), and serves every
                                       Receive Location through arrival,
                                       routing and departure until it is
                                       stopped; a test starts a node over
                                       loopback tcp and carries two hundred
                                       Messages, about a millisecond each in
                                       a debug build. What is left is a
                                       program that does it outside a test —
                                       `xmip-service`, the root crate's
                                       executable (ADR-0018, amendment
                                       2026-09-26) — and the Playground
                                       running Applications on it; the
                                       surfaces' `xmip_start_v1` still plans
                                       and does not run (problem 20)
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
                                       Start-XmipTest -Cluster <cluster> (the
                                       playground topology, -Cluster and the
                                       chooser that moves a view between
                                       clusters are all landed, ADR-0052,
                                       amendment 2026-09-20); every
                                       surface drills to the leaf; every view
                                       names the Receive Location, the
                                       Work Process and the Send Location,
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
                                       is signaled, and crosses a network
                                       over gRPC to a node's operate
                                       listener — built, the runtime's
                                       remote surface (ADR-0014, amendment
                                       2026-10-12). The names
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

**The vocabulary is settled** (the owner, 2026-09-26, confirming
`terminology.md` as written): the Xmip Service rules a node and no Message
passes through it; Xmip Host Services do the work; a Work Process is the
integration process a Subscription starts. Phases 4-9 name their code after
it.

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
asking, and the shared write path it needs is the Party's storage rather than
Xmip's.

All four options recorded here shared one assumption — that Xmip had to keep
the fact. It did not; the fact already had an owner.

What remained was two nodes on a protocol with no claim of its own. ADR-0024's
amendment of 2026-10-13 answers it by the owner's principle — every Receive
Location has one winner per artifact, regardless of protocol — and builds the
file family's: FTP, FTPS and SFTP claim by the turn and the rename, as the
file transport does. The rest is recorded there as the next step: the
brokers' one-consumer delivery declared, the object stores' and databases'
own exclusive steps, SMB, NFS and WebDAV onto the file family's claim, and the
claim through Xmip Storage for IMAP, POP3 and the polled reads.
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

## 43. A Message waiting for a retry holds a place every Port shares — **Resolved**

*Resolved 2026-10-16 by the owner's decision of that day, built the same
day; recorded here 2026-10-16. What it left is problem 40 and the store
encoding below, which no release carries yet.*


Raised by the outside review of 2026-10-16. Admission counts every Journey
the node owns against one node-wide number of places
(`runtime/src/send_step/admission.rs`), a Message waiting for its retry's
due time included: `dispatch.rs` keeps it owned until its next pass ends.
That holds memory to the pool, as intended, and it lets one failing Send
Port fill every place with Journeys that only wait, so a scan finds no room
and the healthy Ports send nothing until the failing one's retries end.
Decided by the owner, 2026-10-16: a waiting Journey holds no place. Its
claim and place are released, Xmip Storage keeps its due time in its queue,
and a scan takes it again once it is due, so what waits stays in the Ledger
and a far end that fails cannot stop the others.

Built 2026-10-16. The hand-on that writes a Journey Recovering names its
queue and its backoff (`HandOn::waits`), and Xmip Storage keeps its due
time at its place in that queue — the `held` table's `due_at`, on Xmip
Storage's clock — and releases the claim, in that one write; nothing stays
owned, so its place in the Send pool frees with it. A read of a queue
answers with Xmip Storage's clock beside its entries
(`HeldQueue::read_unix_nanos`, `HeldQueue::due_in`), so a node tells how long
one still waits as a duration and never compares two clocks. A scan passes
over an entry not yet due without claiming it — on a Sequential Port
reading it, so its sequence waits behind it — and claims it once due, on
any node, its tries counted on from its `attempts`. The node keeps per
queue only the earliest due time and how many wait (`send_step::due`), as
the queue's last read showed and as each hand-on Xmip Storage took since
that read began noted, and wakes for that time; until that evening a read
of the whole queue that passed a Journey's place before its hand-on landed
dropped the due time the hand-on had noted, and a short backoff waited up
to a `send_scan`, a second by default, past its due time
(`send_step::due`'s tests hold the race); the list of every
waiting Journey in memory is gone, and with it the resume path and its
renewal. A pass whose claim was not surely the node's when it began now
tries nothing and writes nothing (`Ended::Untried`): it had been written
Recovering, a send entry and a backoff for a try never made, which a node
under load showed as one entry too many in
`send::a_retry_due_is_tried_again_on_the_active_location_and_sent`.
`tests/ledger/send_waiting.rs` proves a healthy Port sending all its
Journeys while three times as many as the pool has places wait on a far end
that always fails, no claim held by a waiting Journey, every due time kept
across a restart, and a pass that tried nothing leaving no entry. Releasing
the waiting claim brought in a race, found 2026-10-17 as that test failing
about one run in twelve: a scan that had read the queue before a Journey's
Recovering hand-on landed took the claim nobody held any more and sent it
again at once. Every claim a scan takes now reads the place again under it,
its due time with it (`send_step::scan`, `runtime-model.md` section 10,
corrected 2026-10-17), and
`send_waiting::a_scan_that_read_its_queue_before_a_retry_was_handed_on_never_sends_it_again`
holds the race open with `fixture::Failing::after`. What it left: an embedded store made before it reads no held entry, and before the
first release nothing migrates it; a scan still reads every waiting entry
of a queue at each `send_scan`, as it reads every entry, which is problem
40's, and problem 44's, resolved 2026-10-21.

## 39. A send the process did not finish leaves its file behind — **Resolved**

*Resolved 2026-10-19 by the owner's decision of that day, built the same
day (ADR-0024, amendment 2026-10-19).*

Found 2026-10-12, making the file transport's send atomic: a send wrote
`<target>.xmip-sending.<pid>.<count>.<nanos>` beside its target and
renamed it into place, so a reader sees the old file or the whole new one.
A process that died between the two left that file in the directory for
good. Receive never took it, and nothing removed it. Removing them at a
node's start, as it recovers its claims, needed a decision on whose they
are: the name carried the process, not the node.

Decided by the owner, 2026-10-19: the temporary file's name carries the
node's identity, not the process's, and at its start the node removes its
own leftovers while it recovers its claims. It removes no other node's
file.

Built 2026-10-19. The name is
`<target>.xmip-sending.<the node's location, percent-encoded>.<count>.<nanos>`,
the node's identity as a claimed name carries it, written once in
`xmip-core-transport`'s `claim/unfinished.rs` (`Claimant::sending`) and never
an arrival (`claim::may_arrive`). A starting node's recovery removes the
ones its own name records (`Claimant::remove_unfinished`, from
`Claimant::recover`), never one a send of the same process is still writing
(`claim::Unfinished` holds it in the process's set of sends in flight). The
file transport is the family's one technology that writes beside its
target; a Receive Location removes its node's in its drop directory, a Send
Location, whose address names the file it writes, beside that file — it
learns its side as it is built (`transport::Configured::sided`). Building it
found that a file Send Location's start had read its address as a drop
directory, so a node whose file Send Location had sent once could not start
again; it no longer does.

## 40. A queue's gap between two held entries is read place by place — **Resolved**

*Resolved 2026-10-19 by the owner's agreement that day to the proposal
below, built the same day (ADR-0013, amendment 2026-10-19).*

Found by the performance review of 2026-10-12, and repaired in part the
same day: a queue whose oldest entry is all it holds paged in two reads,
and taking its last entry out read none of the gap. What remained: a gap
with held entries on both sides was read one place at a time, by a page
and by the move of the queue's first place inside the one commit writer,
because an entry's key in the encrypted store is a keyed hash and so has no
order to scan. Proposed, and agreed by the owner on 2026-10-19 as written:
an index on (queue, sequence) in the held and dead-message tables, written
with the record like every other index; a page one ordered index scan from
its place; the first place found when a read asks for it, so no gap is
walked in the commit writer. An embedded store made before it lacks the
index, and before the first release nothing migrates it.

Built 2026-10-19. The schema definition (`persist::storage::schema`)
indexes each kind of queue on `(queue, sequence)`: `held_place`,
`dead_message_place`, and `failed_message_place` — the index of failed
Journeys is numbered and read by the same mechanics, so its gap was the
same (problem 34), and its record now carries its queue. On a database
server each is the table's primary key, so the scripts under
`deploy/database/<server>/` make no second index and are unchanged. The
embedded engines keep it as entries of their own, written and taken out
with each entry by the one writer (`storage/columns.rs`). A page is one
ordered range of the index from its place and a read of each entry found
(`queue::page`, `Columns::find_from`, `EncryptedStore::scan_index_keyed`);
the writer keeps as the first a place no entry is held before, moved only
when the queue empties, and the read finds the first. Over a gap of a
million places (`storage/queue.rs`'s tests, counted and timed in memory, a
debug build, the fastest of five rounds): a page of the two entries either
side of it is three key reads and one range, 16 µs; the writer's part of
taking out the first, three key reads and no range, 20 µs. An index entry's
key is in the clear as every index entry's is: it shows each entry's place,
the order of a queue and the size of its gaps, beyond what `held_time`,
`dead_message_time` and `journey_state` showed already.

What it left: on RocksDB a removed index entry is a tombstone until
compaction, so a range across a gap just emptied steps over its tombstones
inside the engine — no record read, none decrypted — and that was not
measured on RocksDB here; and a scan still reads every entry its queue
holds at each `send_scan`, waiting or not (problem 43's remainder), which
an index does not change. Both are problem 44's, resolved 2026-10-21.

## 41. A released database schema has no way to change — **Resolved**

*Resolved 2026-10-19 by the owner's agreement that day to the proposal
below, built 2026-10-20 (ADR-0015, amendment 2026-10-20).*

The owner, 2026-10-12: *The database creation scripts are very static,
that might be good since we have not published. But when we have they have
to alter databases and schema objects.* Until the first release nothing is
migrated (CONTRIBUTING: deleted, never deprecated), and
`deploy/database/<server>/` created each data domain's database whole from
the one schema definition (`persist::storage::schema`). Once a release is
installed, the next one has to alter what it made. Proposed: each database
records the schema version it was made or last altered to, and a Storage
node refuses one whose version it does not know, naming both; the upgrade
scripts are generated from the one schema definition as the difference
between two releases, `04-<domain>-upgrade-<from>-<to>.sql` for each
server, run in order; an upgrade only adds — a table, a column, an index.
The embedded engines need the same version and step, run by the Storage
node itself. Agreed by the owner on 2026-10-19 as written: *each database
records its schema version, and the upgrade scripts are generated as the
difference between releases, adding only*.

Built 2026-10-20. **Every database records its version** in a table of its
own, `schema_version` — `version` and `recorded_at`, a row for each version
it has held — in the runtime, the administration and the audit databases
alike; it holds the highest. `schema::VERSION` is the build's, 1 until the
first release. **The difference is what was added**: every table, column and
index of the definition says the version that added it (`since`), so the
schema at a version is what was added at or before it, and an upgrade from
one release to a later one makes the tables, adds the columns and makes the
indexes added between them, then records each version reached
(`schema::upgrade`, `schema/upgrade.rs`). The definition has no way to say
a drop or a rename, and what it may say is held by a test: a version from 1
to the build's, nothing older than its table, a column added to a table
already made one that may hold nothing, a key the table's from the first,
and each released schema's fingerprint unchanged (`RELEASED`, empty until
the first release). `03-<domain>-schema.sql` makes `schema_version` and
records the version it made; `scripts` writes one
`04-<domain>-upgrade-<from>-<to>.sql` for each release after the first, and
`cargo test --test database` holds `deploy/database/<server>/` to them.
**The embedded Storage node** reads each database's version as it opens,
records each version after it, and refuses a database newer than its build
in words naming both (`Embedded::over`, `embedded/versioned.rs`,
`PersistError::Schema`); a step needs nothing else there, since a table is a
kind of record and a column a value of the sealed body. **A node publishes**
each database it keeps at `<node>/storage/<domain>`, its evidence `schema
version <n> on <engine>`, so `xmip health`, `Get-XmipHealth`, the GUI's
tree and the publication itself show it, and the service says it as it
starts. **The tool act** is `xmip database <server> --from <version>
[--to <version>] [--out <folder>]` and `Get-XmipDatabaseScript -Server
-From [-To] [-Path]`, over `xmip_database_upgrade_v1` (`xmip_operate.h`
section 20); before the first release every upgrade is none and is refused
in those words.

Drafted 2026-10-20, each marked so in ADR-0015's amendment, and **decided
by the owner, 2026-10-21**, as drafted:
an index added to a table already made is refused by the definition's test
until the embedded engines can write its entries for the records they keep;
a database that recorded no version is recorded at the build's, since
before this every store was made at version 1 and none is released; on a
database server, whose login may not alter the schema, a Storage node will
refuse a database older than its build too, naming the scripts to run, once
that backend is built; and version 1's fingerprint is recorded at the first
release.

## 44. A send scan reads every entry its queue holds — **Resolved**

*Resolved 2026-10-21 by the owner's decision of 2026-10-19, built the
same day (ADR-0013, amendment 2026-10-21).*

What problems 40 and 43 left: at every `[tuning] send_scan` a scan read
every entry its Send Port's queue held to find what was due, so a far end
that failed for an hour made every scan read every Message waiting on it,
and a Journey that failed was read at every scan to be passed over.
Decided by the owner, 2026-10-19: *a send scan reads only what is due*,
through an ordered index on when each entry is due, written and removed
with the entry, as problem 40's index on queue and place is.

Built 2026-10-21. The schema definition (`persist::storage::schema`)
indexes `held` on `(queue, failed, due_at, sequence)`, `held_due`, at
version 1, and `held.due_at` holds a value in every row: a retry's due
time, or the epoch for a Journey due since it was held. What is due now is
one range of it; what waits for a retry and what failed are parts of their
own. Xmip Storage reads a part (`XmipStorage::read_due`, `DuePart`,
`DueQueue`, wire operation 28) and says beside it how many keep a retry's
due time and when the earliest not yet due is, which a table of its own
keeps with where each part's first is (`held_due_places`), so nothing
waiting is read to count it. A Journey marked failed waits for no retry:
its due time goes with the mark. The send step reads only what is due on a
Port that is not Sequential, a page at a time, in the order it fell due
(`send_step/reading.rs`); a Sequential Port's scan reads beside it what
waits for a retry and, where a failure blocks, what failed, since each
holds a sequence behind it, and keeps the queue's order; it reads what is
due first and again last, so a Journey that moves between the parts while
they are read — a send's verdict, an operator's Retry, the clock — is read
in one of them and its sequence never goes on without it (corrected
2026-10-21, `tests/ledger/message_act.rs`). On a database
server `held_due` is an index of its own, in the scripts under
`deploy/database/<server>/`.

Measured, in memory, a debug build, the fastest of five rounds
(`storage::due`'s tests): of 11,003 held — 10,000 waiting an hour, 1,000
failed, three due — a read of what is due reads four keys and two ranges,
finding four index entries, in 91 µs; a read of the whole queue, as a scan
read it, 11,176 keys.

**`RocksDB`'s marks, measured.** Problem 40 left them unmeasured: on
`RocksDB` an entry taken out of an index is a mark the engine steps over
until a compaction drops it, and a queue being sent takes out each entry it
sends, ahead of what it still holds. Measured 2026-10-21 (a release build:
100,000 marks before three entries, 8.5 ms a read in the memory table and
8.3 ms once flushed; `xmip-core-persist-rocksdb`'s test, a debug build:
199,997 marks, 15-20 ms through them, 5-8 µs from the first kept), about
85 ns a mark, which costs. Fixed two ways: a read of what is due starts
where each part's first is, which the one writer keeps — once a batch is
decided, each queue it wrote a held Journey of finds its first again by
one range of the index from where it was, stepping over each mark once
(`storage::due::settle`) — and `RocksDB`'s ranges are bounded at both
ends, so none steps past its end over what was taken out beyond it.

What it leaves: the place index (`held_place`, `dead_message_place`,
`failed_message_place`) still keeps its first only as a place no entry is
held before, moved when the queue empties, as problem 40 decided, so a page
of it from the first steps over the marks of what was taken out ahead of
the oldest entry; the pickup and the window on failed Journeys read it so.
Marks between two entries still held — a Journey slow to send while those
after it are sent — are stepped over until `RocksDB` compacts them. And
the index's keys show, in the clear, whether an entry failed and when its
retry is due, beyond what `held_place` showed.

## 35. Loopback proves where a caller is, not who — **Resolved**

*Resolved 2026-10-21 by the owner's decision of 2026-10-19, built the
same day (ADR-0009 and ADR-0014, amendments 2026-10-21).*

Raised by the outside review of 2026-10-08 as a decision to reconsider:
ADR-0009's exception (the owner's *Go with A* of 2026-10-03) made every
certificate-free caller over this machine's loopback the operating system
user the host runs as (`GatedOperator.Proven`). With a role stated for the
run, or a Playground host's tester directory, another local user acted as
that account, and a reverse proxy forwarding to loopback extended the same
trust to remote callers; the audit named the host's account. Decided by
the owner, 2026-10-19: *local callers are proven by the operating system*,
through a named pipe or a Unix socket's peer account, and *tcp loopback is
no longer trusted by itself*.

Built 2026-10-21. **The loopback trust is deleted**: `GatedOperator.Proven`
takes a client certificate's subject alone, and a browser or a remote
surface over loopback presents one like any other caller, or is no one.
**Every local surface reaches a node at its local endpoint** — xmip, the
PowerShell module and both GUIs, through the runtime's one connecting end;
the VS Code extension's language server reaches no node. **On Windows**
every surface opens the node's pipe lent for identification alone
(`net::pipe::connect`), and the node reads the caller's account
from its token; the pipe's security descriptor admits the node's account,
`SYSTEM`, the machine's administrators and whom `[operate] admit` names,
the admitted only to read and write it (`plane::local::windows::openers`).
**On Unix** the kernel names the peer (`SO_PEERCRED`, `getpeereid`) and the
node admits its own account, the superuser and whom `admit` names
(`plane::local::unix::Admitted`), in a folder only the node's account or
the superuser may write (`unix::guarded`). The account is what
authorization judges, by `[operate] role`.

Measured, Windows, a debug build: a surface's connection from nothing to
its first answer, the caller proven, about 0.28 to 0.45 ms the fastest of
five and 0.30 to 0.49 ms the median (`tests/plane/local.rs`), after four
costs were taken out on the way: a name Windows took 0.35 ms to give,
now kept by the identifier the token proved; a deadline thread per
surface, now one for the process (`plane::deadline`); a thread started
and ended per connection, now kept for the next (`plane::workers`); and
HTTP/2 compiled unoptimized in the runtime's tests, now asked where `net`
compiled it (`net::http2::BoxedClient`, `BoxedServer`; ADR-0014,
amendment 2026-10-21). On Linux, the AlmaLinux 10 guest under WSL, 0.70
to 0.82 ms the fastest of five and 0.78 to 0.97 ms the median.

Decided by the owner, 2026-10-21, and built the same day: *a Unix socket
0660 with a group, not 0666* — where `admit` names anyone the socket
belongs to `[operate] group`, the node's own group where it is left out,
and is `0660`, the node's peer check staying the second gate
(`plane::local::unix`; proved in the AlmaLinux 10 guest); an account's name
is kept until the node restarts; and *the Playground tester in the web GUI
acts with an operator certificate* — the roll's host serves https on
127.0.0.1 under the roll's authority, in Xmip's own TLS, the tester
presents a certificate from `New-XmipCertificate -Operator`, and the tester
directory knows that certificate's subject (ADR-0009 and ADR-0014,
amendments 2026-10-21). Still drafted: the key `[operate] admit` and its
reach; a surface stating no wait of its own, which lists the node
declarations to learn the node's (`deadline::declared`, 0.4 to 0.6 ms of
processor time on this machine's temporary folder).

## 49. A file kept whole on Windows is refused while another process holds it — **Resolved**

*Resolved 2026-10-23, the day it was found, in the same change.*

Found landing the Parties' far end (ADR-0028, amendment 2026-10-22): the
runtime's
`ffi::certificate::tests::a_request_is_written_for_a_person_and_a_distinguished_name_is_refused`
failed twice in a row under `xgit`, *Access is denied (os error 5)*, at its
second keep of `operator.pem` over the one it had just written, and passed
eight times run alone; `%TEMP%\xmip-ffi-request-43908` held another run's
`.operator.pem.<hex>.new`, left by the same failure. `secret::private_file`
keeps every key, certificate and chain by writing it beside its place and
renaming it over (`replace`, `replace_readable`), and on Windows another
process — a virus scanner reading a file just written — can hold either
file for a moment. A defect on every end user's machine, not only in tests.

The fix: a holder of the target with delete sharing, as a scanner reads,
is no obstacle — where the plain rename is refused, the standard library
renames again with POSIX semantics (`SetFileInformationByHandle`,
`FileRenameInfoEx`, `FILE_RENAME_FLAG_POSIX_SEMANTICS |
FILE_RENAME_FLAG_REPLACE_IF_EXISTS`), so it is not written a second time
here. A holder of the file just written, which no rename gets past, is
waited out: the switch and the removal of what it leaves are tried again a
millisecond apart while Windows says the file is held (`ERROR_ACCESS_DENIED`,
`ERROR_SHARING_VIOLATION`), five times at most, and a switch that fails
still removes the written file (`private_file::held_out`). Unix renames
over a reader and is unchanged. Held by
`a_file_another_process_holds_as_a_scanner_does_is_replaced_whole`,
`a_written_file_held_a_moment_is_waited_out_and_left_nowhere` (which fails
with one try) and `a_switch_that_fails_leaves_nothing_beside_its_target`.

## 4. `assign`, `promote`, `demote` sit in Capabilities with zero implementations — **Resolved**

Resolved by the owner, 2026-10-27: they are capabilities with units
(ADR-0066, amendments 2026-10-22 and 2026-10-27). Promote runs on receive
only and Demote on send only; Prepare runs at receive, process and send;
and assign is called by a
Work Process. Each is a capability a Module's compiled units declare, called
from the configuration's step entries.

## 5. `transport` carries 44 of the 246 implementations — **Resolved**

Resolved by the owner, 2026-10-27: *each transport should be in it's each
repo, in its own loadable module. There might be shared code, so stick that
in a shared repo module. If the shared code is stable.* One repository and
one loadable module per transport; code they share goes to a shared
module of its own once it is stable (ADR-0010, amendment 2026-10-27).

## 7. The Operations tier is five near-identical modules — **Resolved**

Resolved by the owner, 2026-10-27: *Why not use the ABI, there shall not be
any duplication of code unless it is modulewize.* A store capability with
its own module ABI section; each store technology is one loadable module;
audit, report, observe, retain and archive stay five modules with their own
policy and tables. Building the section is open problem 56.

## 8. Cloud vendor prefixes are inconsistent — **Resolved**

Resolved by the owner, 2026-10-27: option A, always name the vendor. The
renaming is open problem 57.

## 9. `resilience` and `exclusiveness` are alone in the Platform tier — **Resolved**

Resolved by the owner, 2026-10-27: *I thought we left exclusiveness behind
us* — ADR-0024 replaced it with the claim through Xmip Storage, and the
Correlations are how Xmip does exclusiveness (ADR-0024 and ADR-0066,
amendments 2026-10-27) — and *There might be some else who want to do
better on 'resilience' and 'exclusiveness'.* Both become pluggable
capabilities, each with an ABI section and Xmip's own the built-in default;
building them is open problem 58.

## 10. Three modules declared with no repository — **Resolved**

Stale, the owner, 2026-10-27: `xmip-core-abi` and `xmip-core-transport` have
their repositories, and `logic` was resolved under problem 6.
