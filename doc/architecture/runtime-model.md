# Xmip runtime model

What Xmip does at runtime: how a Stream becomes a Message, how a Message
becomes Journeys, and what an operator can do to them afterwards.

This is the architecture specification. It replaces
`Xmip-Architecture-Specification-v1.0.md`, `-v1.1.md`, `-v1.2.md` and
`Xmip-Architecture-Baseline-Current.md`, which were four documents wearing
version numbers that suggested a lineage they did not have. Sections 9 to 15 of
v1.2 were about the estate rather than the runtime and are now in
`repository-model.md`. Their history is in git.

Where those documents conflicted with each other or with an accepted ADR, the
conflict is resolved in section 23 rather than silently.

It also absorbs the live content of the pre-ADR-0020 documents in
`doc/architecture/` — the Definition/Instance model, the Process model, and
the validation gates — which described subjects the four specifications never
covered. Those documents conflicted too, and those conflicts are in section 23
as well.

**This document states the decided design, and much of it is not built.**
How much of each capability is built — in the assembled service, built but
not in it, decided and not built, or open — is said once, in the
[estate map](estate-map.md#what-is-built), and cited beside a promise here as a link
whose words are that state.

## 1. Purpose

Xmip reliably receives, moves, understands, validates, processes, delivers,
observes and recovers information over time.

Xmip is:

- Stream-centric at its foundation.
- Stream- and Message-centric in processing.
- Journey-centric in execution and operations.
- Immutable by design.

## 2. Stream, Message, Section, Journey

**Stream** — immutable data received by, or produced within, Xmip.

**Message** — a processing unit over immutable content, with a message id,
accumulating metadata, and one or more Sections. An XML, JSON, CSV, EDI, HL7 or FHIR instance, or text or
binary payload, may be *represented* by a Message. **A representation is not a
Contract.**

**Section** — a stream within a Message, with a section id, metadata and a
stream reference. Sections reuse stream references when content is unchanged.

**Journey** — one line of execution carrying a Message through Xmip, with its
history, audit events and lineage.

A new Message is created when Xmip performs an operation producing a new
message state — Assignment or Transformation. **Routing alone creates no new
Message.**

**Prepare keeps its Message** (the owner, 2026-10-09: *I think the message
should be the same before and after Prepare, the stream changes, and it will
be in the message history*). On the Receive and the Send side, Prepare
changes the Message's Stream and not the Message: the Message is the same
before and after, and the Stream it had stays in its history. Not built.

## 3. Immutability

**The Stream is immutable. The Message and the Journey are not.**

A Stream is never modified, ever. What arrived is what is kept, byte for byte,
and that is what makes replay, audit and preservation mean anything.

A **Message** accumulates. Context, promoted properties, validation results,
Contract metadata, execution history — all of it grows as the Message is
handled. What does not change is the content it refers to: its Sections point
at Streams, and those Streams stay exactly as they were.

A **Journey** accumulates too: execution history, audit events, lineage. Its
historical record is appended to, never rewritten.

**Content changes only through Assignment or Transformation**, and those create
a new Stream and a new Message generation rather than editing anything. So there
are two distinct things happening and they are easy to conflate:

```text
metadata changes   the same Message, carrying more
content changes    a new Stream, a new Message generation
```

*Corrected 2026-08-26. This section read "Streams and Messages are never
modified", which is true of Streams and false of Messages — a Message that
could not accumulate context could not carry promoted properties or validation
results at all. The error was load-bearing: it kept being read back as evidence
that Messages are immutable envelopes, which sent the same question round more
than once.*

### Nothing executes on arrival

**Every Stream, Message and Journey is durably queued until it completes or
retention applies, and is archived before either**
(archiving by retention window:
[built, not in the assembled service](estate-map.md#retention-archiving)). Xmip is queue-driven end to
end. Arrival enqueues; it does not execute.

The reason is stated best plainly: **you never know when the hardware has time.**
A receive burst does not get to decide how much CPU exists, an edge device does
not get to assume it can keep up, and a node that is saturated must be allowed
to fall behind rather than fail. A queue is what converts "too much work right
now" into "work that takes longer", which is the difference between a slow
estate and a broken one.

Three consequences that are otherwise surprising:

**Backpressure is the normal state, not an incident.** A growing queue means
the estate is absorbing more than it can process this second, which is what it
is for. Alerting on queue depth alone reports weather.

**Ordering is a property of the queue, not of the code.** Anything needing
sequential processing gets it from queue discipline, never from work happening
to be executed in the order it arrived. See *A claim is not ordering*
below — they are constantly confused and are not the same guarantee.

**Durability precedes execution.** A Message is on disk before anything acts on
it, which is what makes replay from a checkpoint meaningful and what makes
"an accepted Message shall never disappear" achievable rather than aspirational.

### The Ledger

The queue has a name: **the Ledger** (the owner, 2026-10-01: *ToDo is a bad
name, propose a better one*; the assistant proposed Ledger; the owner:
*Ledger is good*). It holds every Stream, written in chunks, every Message
and every Journey, with the state of each Work Process, retry, failure and
replay state, and the Messages a paused Subscription holds.

**A Work Process's state is two tables of its own** (built 2026-10-22,
section 22): **Process Instance**, each Instance's state whole, by its
identifier, with how many turns it has taken and whether it has ended; and
**Correlation**, each correlation set's key — named from the Work Process,
the set and the key's values in full — and the Instance it belongs to. Both
are written in a turn's one write and nowhere else, and an Instance only over
the turn it was read at. Beside them, each Stream that holds a place in a
sequence end to end has its count of open Journeys, kept by the writer in the
writes that open and end them (*Sequences*, below).

**The Ledger belongs to the cluster, not to a node** (the owner, 2026-10-01:
*There is nothing local about either RocksDB or SQLite, they are cluster
services running on one or more nodes*; and *All DB records have to be
central and clusterable, if one node fails another one should be able to
pick up*).

**Xmip Storage is the doorway to it.** The nodes declaring the **Storage**
role (`deployment-model.md` sections 3 and 7) serve every storage operation —
write a Stream chunk, write a Message, claim a Journey, hand it on, write an
audit record — and every other node calls those operations, never a database
directly. A node reaches the Storage nodes
round robin, from the list of their addresses in its TOML, and more than
one Storage node is the safety (the owner: *to
have one or more Xmip Nodes with role Storage would be a safety… Xmip could
just do a round robin over Xmip Nodes roled Storage*). The round robin is
per statement, not per operation (the owner, 2026-10-03: *When accessing
storage, it should be the same storage node through out a statement, even if
it is repetitive. Writing chunk 1 to n should be regarded as one statement,
one call against StorageN* — and the Publication and its Journeys are the
same statement): a receive cycle's chunks, its Publication and its Journeys
are asked of one Storage node, and one that stops answering mid-statement
fails the statement rather than moving it to another.

**Only a node with the Storage role stores** (the owner, 2026-10-20). A node
keeps Xmip Storage itself only where its roles declare `storage`; every
other node calls a Storage node through `[storage] nodes`. A one-machine
node carries the Storage role, and is its own embedded Storage node; a node
declaring neither the role nor `[storage] nodes` is refused as it starts,
in words naming both (ADR-0056, amendment 2026-10-20). Every other node
reaches them over Xmip's mutual TLS with the certificate, key and anchors
`[storage]` names, and a Storage node serves them at `[storage] listen`
(ADR-0056 and ADR-0067, amendments 2026-10-22).

**Embedded Storage nodes are a primary and its standbys** (drafted:
ADR-0056, amendment 2026-10-22, the owner's design of 2026-10-01 brought
forward from option C below). Round robin over Storage nodes in front of
one database server shares one Ledger; embedded Storage nodes each keep
their own, so a cluster's are one **primary**, serving every operation, and
its **standbys**, each copying the primary's engine writes behind it, in
the order written, asynchronously. A standby serves no operation and says
so, and a node asks the next listed. The Storage nodes settle which is the
primary themselves, the first listed the first: a standby is promoted once
the primary is gone — at once where every one listed before it answered,
else once it heard no primary for `[tuning] storage_silence` — and each
promotion raises the **epoch**, a primary of an earlier one asked by no node
that met the later. A primary stopped in order hands on everything it
wrote; one killed loses what it had not handed on, which the owner accepted
on 2026-10-01.

**What is behind the Storage nodes is decided per site** (the owner, later on
2026-10-01: *The storage node may or may not carry the SQL storage, it is an
IT-infrastructure question… How IT-infrastructure designs their Database
servers is their concern*). Two forms are decided:

- **A shared database server** that IT runs on the internal network —
  PostgreSQL first, SQL Server and MariaDB later — chosen as option A (the
  owner: *Go ahead*). Its clustering, failover and backup are IT's.
- **One embedded Storage node**, RocksDB and SQLite through
  `xmip-core-persist`, for a single machine and an edge site. **It has no
  failover**: when that node is gone, so is the site's storage until it
  returns. A sensor gateway is its own Storage node, declaring the Storage
  role, so it has a Ledger, no
  broker, and the same execution model as a forty-node estate.

**Either way Xmip Storage keeps three databases**, one to each data domain.
The ruling of 2026-10-01 kept two (the owner: *We still need the
distinction between runtime and administration databases, regardless of
backend database technology*): the **runtime database**, which is the
Ledger, and the **administration database**. It is extended, not
contradicted, by a third, the **audit database** (the owner, 2026-10-10:
*The audit part might be better of in its own database so it can be hosted
on a different set of nodes, different storage*; ADR-0070, amendment
2026-10-10). Each is a table of its own in the configuration,
`[runtime]`, `[administration]` and `[audit]`, its `storage` and its
`connection` (the owner, 2026-10-10: *i would do it like runtime, storage,
connection string. Same for audit and administration*), so each may be on
another technology and another server: on an embedded Storage node RocksDB
and two SQLite stores, under the data directory where a table is left out;
on IT's servers behind option A, three separate databases
(`deployment-model.md` section 7). Runtime matter is central there,
so another node with matching node roles can pick up; the administration
database keeps what must be shared and kept over time — operator state,
deployment state, cluster membership — and the Subscriptions each Host
Service writes from its TOML as it starts
([decided, not built](estate-map.md#shared-subscriptions)); the audit
database keeps the audit history.

**Proposed 2026-10-09: what the Ledger is searched by.** A record's body
is sealed and found by a keyed hash, which leaves an operator nothing to
search by. The proposal lays out every single value of each Journey,
Message, held Journey, Dead Message Queue entry, kept audit record and
administration record in a column of its own table, in the clear (the
owner, 2026-10-09: *Store it in the clear*; *All columns shall be laid
out*); a list stays in the body. They are written in the record's own
write, so the index never disagrees with the data, and asked through
`XmipStorage::query`, one typed question per table (`deployment-model.md`
section 7).

**Configuration is TOML, read as a Host Service starts; the Subscriptions
are shared through Xmip Storage** (the owner, 2026-10-02: *Routes are
defined in TOML, read into Storage at Xmip Host Service startup, read from
Storage when needed and kept in memory until "not used for a while"*, and
*They are shared*; [decided, not built](estate-map.md#shared-subscriptions): a node
routes by the Subscriptions it binds,
[built, in the assembled service](estate-map.md#subscription-routing)). Each node reads its TOML configuration as it starts and
holds its Locations, Work Processes and Send Ports as its **execution
tree**, which `build_execution_tree` in `xmip-core-runtime` builds. Its
Subscriptions it writes into Xmip Storage's administration database, so any
node with a routing role routes a Message another node received; routing
reads them from Xmip Storage when it needs them, compiles their filters and
keeps them in memory until they have not been used for a while. The
operation tools and editors change the TOML file, never a database, and a
changed TOML file takes effect when the Host Service that reads it is
started again, never mid-flight (ADR-0031, amendments 2026-10-01 and
2026-10-02).

**Encryption** (the owner, 2026-10-01: *Xmip encrypts to Xmip Node with
Role/Type Storage, from there it is the IT infrastructure/operations to
decide*; and for the embedded Storage node, *Well then Xmip has to support
encryption of that*): everything between a node and a Storage node travels
over Xmip's own TLS; behind a database server IT runs, encryption at rest is
IT's and operations' decision — SQL Server's Transparent Data Encryption or
encrypted disks, for example; on an embedded Storage node, test nodes
included, Xmip encrypts its own files at rest itself (ADR-0063, amendment
2026-10-01; `deployment-model.md` section 7).

**The comparison is BizTalk's MessageBox, and so is the warning.** The
MessageBox was a shared SQL database holding every message and every
subscription for the whole group, and it was where BizTalk went to die under
load — every scale-out story ended in "add another MessageBox and partition
across them", which is an admission that the design put a cluster-wide write
hotspot at the center of the runtime. Said honestly, option A is a shared
database too, and its write rate is the cluster's limit. What differs is the
doorway: no node writes the database directly, so Xmip Storage's operations
are the only access pattern the database meets, and how the database is
built, clustered and tuned for them is IT's. If A's latency proves too slow,
two forms are recorded for later, and only for then
(`deployment-model.md` section 7): C, an embedded engine per Storage node
with Xmip copying from a claimed primary to standbys, and D, C for the hot
Ledger with A for history. C is built for embedded Storage nodes, drafted on
2026-10-22 while A is not built (*Embedded Storage nodes are a primary and
its standbys*, above); its witness is not.

**Every Ledger write counts only once the database has it durably** (the
owner, 2026-10-01: *Safe way*), the hand-ons between steps included. Behind a
database server that is its commit; on the embedded Storage node it is a sync
to disk, and group commit lets many concurrent writes share one sync.

**One sync per receive cycle.** A Stream's chunks are written without a sync
of their own, and the Publication's durable write makes them durable with it:
on the embedded Storage node one sync of `RocksDB`'s write-ahead log covers
every write before it, and the Storage node a node reaches syncs the same way
at the Publication. Nothing is acknowledged before the Publication commits, so
a crash before it leaves at most chunks no Message refers to, which the
sender, never acknowledged, sends again; an acknowledged Message has its
Stream, its Message record and its Journeys in the Ledger. The chunks and the
Publication are one statement, asked of one Storage node (*Xmip Storage is
the doorway to it*, above), so the sync that covers them is that node's (the
owner, 2026-10-03). The embedded Storage node's writer answers a Publication
once it is written and decided, and syncs it right after: the answer carries
when it is durable (`persist::storage::Durable`), what the receive cycle and
every send of its Journeys wait on before anything is acknowledged or seen
by a far end (section 10; ADR-0018, amendment 2026-10-20). Every other write
is answered once durable. The write-ahead log is written to its file by the
sync alone (`RocksDB`'s `manual_wal_flush`): a write before it is kept in
`RocksDB`'s own buffer of the log, so a Stream's chunks never wait while
another thread syncs the log — on Windows a write to a file waits while the
file is flushed, and each Message's chunks waited out the previous
Message's sync — and a write not yet synced goes with its process, as
nothing anyone was told of does (ADR-0018, amendment 2026-10-20).

**Work moves by claim.** A node takes a Journey by
a claim through Xmip Storage: a conditional update in the database — set the
owner where the owner is empty or lapsed — time-limited, and renewed while
the work runs. A node that dies stops renewing, its claims lapse, and any
other node capable of the work claims it and resumes from the last finished
step. Every hand-on is one atomic write — the step's result, the next Journey
and the claim released together — so a lapse never finds half a step. What
Xmip does and what IT's infrastructure does is `deployment-model.md`
section 9.

*It used to cost two things.* The first was that work did not move by itself:
a store written by one node was that node's, and moving its work was an act
nobody had designed — the contradiction with section 22's *Process State
belongs to the cluster*, resolved in section 23 note 12. The second was
cluster-wide exclusiveness for arrivals, which ADR-0024 removed by claiming
the artifact at the endpoint, where the Party's storage is the shared write
path. A Journey's claim is the other case: Xmip's own state has no endpoint,
and the database behind Xmip Storage is where it is claimed (ADR-0024,
amendment 2026-10-01). The owner recalled it as the old exclusiveness; the
word is ADR-0024's, a claim.

### The queue is the store, not a broker

**Xmip has no message broker and needs none.** The Ledger is not a broker.
It is the shape of the persistence model:

```text
Stream written to the Ledger, in chunks
    Message record created, referencing that Stream
        Journey record created when the Message reaches a Receive Port
```

Each of those carries state. Selecting work is a query over state, and
completing work is a state transition. That is a queue in every sense that
matters — durable, ordered where ordering is configured, survives restart — and
it is MSMQ, MQ Series or RabbitMQ in none of them.

Xmip already requires a durable store, and a broker beside it would be a
second system to run for a question the store already answers. That holds
offline, and offline means no internet — the internal network and a site's
own servers are fine (the owner's correction, 2026-10-01; ADR-0045). So a
database server a site runs on its own network, behind Xmip Storage, is the
site's infrastructure, as its network and its disks are, and not a
dependency on somebody else's cloud. Xmip still needs no broker. The access
pattern is a work queue's — high write volume, read by key, replay from a
known state — which is what the embedded Storage node's RocksDB is chosen for
and what Xmip Storage's operations ask of a database server
(`deployment-model.md` section 7).

**The manifest will mislead someone about this.** `xmip-core-transport-msmq`,
`-rabbitmq`, `-kafka`, `-ibm-mq` and a dozen more exist — as **integration
targets**, things Xmip talks to on somebody else's behalf. None of them is
infrastructure Xmip runs on. An estate can use Xmip with no broker anywhere,
and a purpose-compiled runtime on a small device does exactly that.

### A claim is not ordering

Two different guarantees, routinely treated as one:

**A claim** says *one holder at a time*. It says nothing whatever about which
item that holder takes, or in what sequence. ADR-0024 owns it, and the holder is
established at the endpoint rather than by a lease inside Xmip.

**Ordering** says *these items are processed in this sequence*. It is declared
on the artifact, not inherited from the claim.

The relationship is one-way. **A claim is necessary for ordering and does not
provide it** — two concurrent processors reorder work by definition, so ordering
requires exclusive possession first; but a single holder taking items in
whatever sequence it likes is perfectly exclusive and completely unordered.

Ordering needs three things a claim does not supply:

**A key.** Ordered *by what*? A correlation set says: the values work is
spread over, per Party, per client, per device, so that unrelated sequences run
in parallel while each sequence stays intact (ADR-0024 and ADR-0066,
amendments 2026-10-22). Where nothing is configured, a Receive Location orders
its own Streams as one sequence, end to end — the owner, 2026-10-22: *A default
correlation set is its receive location name. … Default one stream, message,
journey at a time.*

**In-sequence selection.** The holder takes the next item for that key, not the
next available item: each key is a queue of its own in the Ledger, and work
goes on only while it holds the first place there (*Sequences*, below).

**A failure policy, which nobody thinks about until it happens.** When an
ordered item fails, either the sequence blocks behind it — order preserved,
head-of-line blocking, one bad Message stops a Party's traffic until an
operator intervenes — or it is set aside and the sequence continues, which
breaks the ordering that was the point. Both are defensible; **neither is a
default that can be chosen silently**, because the first surprises an operator
with a stall and the second surprises them with reordering. The owner chose,
2026-10-22: block by default, skip as an option — a failed Journey waiting for
an operator keeps its Stream at the head until Retry or Dismiss, and a set's
`on_failure = "skip"` lets the rest pass. It is a key of the set, placed once
(section 20, *Where the runtime's settings are configured*).

### Sequences

The owner, 2026-10-22: *If I want to open up for parallelism I can use context
values like Receive Port, Work Process, Send Port, Message and Journey context
values. I can widen and strangle parallelism at any configurable point*, and
*Equal values in a correlation set (aka hashtable) go in the same queue,
different values go parallel depending on the value in the correlation set.*

```text
[[correlation_sets]]                 declared once, cluster-wide
  name, keys, on_failure            keys: receive-location, receive-port,
                                    work-process, send-port, context:<name>
correlation_set = "<set>"           at a Receive Location, Receive Port,
                                    Work Process or Send Port
```

- **One queue per point and key.** A sequence is a queue in the Ledger named by
  the point and the key's values in full,
  `<cluster>/sequence/<point>/<name>/<set>/<values>`; equal tuples share it,
  different tuples run in parallel. Its identifier is named from that text and
  the text is kept beside every place, so a collision is told apart.
- **A place is taken in the write that brings work to the point** — the
  Publication, a hand-on that publishes — and work there goes on only while it
  holds the first place. What does not waits in the Ledger, its claim given
  back, holding no thread; a step that ends a sequenced Journey reads its
  queues again at once.
- **A Receive Location's and a Receive Port's sequence is end to end.** The
  Stream's origin — the Message it was received as — holds the place until the
  last Journey born from it ends, its sends and what a Work Process published
  from it among them. Each Journey's record says its origin and whether it is
  still open, and Xmip Storage counts the open ones in the writes that open
  and end them; the last to close lets the places go in that same write.
- **A Work Process's and a Send Port's sequence holds the Journey** while it is
  at that point: until it is handed to its Instance, or sent.
- **The default costs no write.** A Receive Location that names no set holds
  its own sequence, keyed by its name, its place taken in the Publication's
  own write. Whether a Stream heads its sequence is one Ledger read, once per
  Stream on each node that takes a step of it: a place that heads its sequence
  heads it until it is let go, so a node remembers what it has seen head and
  never asks again (`sequence::heads`). No Location keeps the promise end to end
  alone, as its Stream's send may run on another node, so none passes the
  Ledger's sequence by.

**Sequence enforcement is state-based and durable.** The sequence position,
by key, lives in the Ledger, not in the memory of whatever is currently
running it. A node that dies mid-sequence loses nothing: the position is
behind Xmip Storage, its claim lapses, and another node claims it and
continues from it. Enforcing order through in-memory
state would mean a restart either replays or skips, and neither is acceptable
for something whose entire purpose is that the order held.

Recovered 2026-08-26 from the `_origins` design export, where the execution
styles — Sequential, Parallel, Concurrent, deleted 2026-10-22 for correlation
sets — and the durability rule were recorded and had been carried into none of
the consolidated documents.

This is not new. It was recorded in the earliest architecture, carried in
`Xmip-Exclusiveness-Architecture.md`, retired with ADR-0017 — which is why it speaks of
tasks being *durably queued* — and was dropped from every consolidated
document. Restored 2026-08-26 after the owner noticed its absence.

### Threads, pools and chunks

Decided by the owner, 2026-10-01, validated part by part with the assistant.

**Threads, not fibers.** The owner asked *What about using Fibers instead of
Threads?*, and threads were agreed; fibers are revisited only if measurement
shows thread switching dominating.

**A dynamic, bounded pool per step** (the owner: *Go with the dynamic,
bounded pool*). Each step of the message path — receive per Receive Location,
with routing inside it (*How routing runs*, section 9), the Work Process
step, send — runs on a pool of its own. A
CPU-bound step's pool is capped at the machine's core count. An I/O-bound
step's pool grows while work waits, up to a configured maximum — the
bulkhead, ADR-0018 clause 11 — and never below one thread; it shrinks after
a configured idle time. Threads are started ahead of need, never per
Message.

**Steps hand on through the Ledger.** A step's result is serialized into
the Ledger through Xmip Storage, and the next step's thread deserializes it
from there. The owner's
description: *every sub action starts a new thread, in between the stream
shall be serialized and then on every sub a new thread deserializes the
message from RocksDB* — realized as pools, which the owner accepted. **A
waiting Work Process and a retry waiting for its backoff hold no thread**:
their state and due time are in the Ledger, and a pool's thread picks them up
when they are due.

**A Stream is written in chunks, never whole in memory** (the owner: *A
stream can't be written completely to memory and then into the RocksDB
Ledger. It has to be done in calculated chunks depending on how much memory
is available*), and every gate — preparation, promotion, deserialization,
validation, transformation, serialization, demotion — reads chunk by chunk.
**The chunk is a fixed whole number of TCP segments** (the owner,
2026-10-03: *The chunk size would be sized according to IP/TCP chunks with a
multiple since IP/TCP is the major transport protocol. If useful one can do
it per transport*; *Do it fixed*): 44 segments of 1460 bytes — Ethernet's
1500-byte MTU less the IP and TCP headers — 64,240 bytes, just under TCP's
classic 64 KiB window, so a Stream in flight holds about 128 KiB, the chunk
it writes and the one it reads ahead (`xmip-core-runtime`'s `ledger::CHUNK`,
over `xmip-core-transport`'s `TCP_SEGMENT`). A transport may declare a unit
of its own where that is useful; none does yet. **A Stream ends where it has
no further chunk.** **A Stream is a record of its own** (the owner,
2026-10-09: *a Message refers to a stream, a stream is stored in chunks*;
*A new message might refer to the same stream*): written once, with its
last chunk, and never changed, it is the one home of its length and its
chunks, and every Message that refers to it — the one received, one assigned
from it — refers to it by its identifier; a Message given a new Stream,
assigned or transformed, refers to that one. A reader holds what it read to
the length the Stream's record keeps, so a chunk lost after Publication,
damaged or deleted, is refused in words, never read as a shorter Stream. An
empty Stream is one empty chunk.

**Built for receive, 2026-10-02.** Each Receive Location carries what
arrives on a pool of its own (`xmip-core-runtime`'s `pool`): one thread
carries one arrival through the whole receive cycle and tells its far end
the verdict, and the arrivals of one receive are told in the order they came,
all of them before the transport is asked again, as the transport's contract
has it. So a transport that hands over one arrival a receive — TCP takes one
connection — carries one at a time, and concurrent senders share no sync
until a transport hands over several at once. The Stream is read from the
transport's reader into the Ledger in chunks and held as kept there, read
back a chunk at a time. **A Receive Location's pool is calculated from the
machine** as the node starts (the owner, 2026-10-03: *make a calculation
according to CPU cores/threads*): at most twice the hardware threads the
platform allots the process (`pool::Limits::receive`), since a receive
thread waits on the Ledger's sync as well as working. A thread idle for a
minute ends — the assistant's drafting, for the owner to overrule. A
polled Location rests between receives that found nothing (section 5,
*How a receive runs*): a second, and five seconds after a failure that may
mend — the assistant's drafting, 2026-10-12, for the owner to overrule. No
configuration caps a pool yet.

**Built for send, 2026-10-03.** The node's Send pool is calculated the
same way (`[tuning] send_threads_per_hardware_thread`, two by default, and
`send_idle`), and the send step dispatches on it (section 10, *How a send
runs*): a Journey's hand-on — Completed, Failed with why, or Recovering
with its due time — is one atomic write through Xmip Storage, and a retry
waiting for its backoff holds no thread, no claim and no place in the pool,
its due time kept at its place in its queue (section 10, corrected
2026-10-16).

**A node's budget beside its pools, built 2026-10-19** (`open-problems.md`
problem 38). A pool bounds threads, not what they hold, and each Receive
Location's pool is its own — its isolation — so a node of many Locations
had no ceiling of its own, and the Send pool admitted a count of Journeys
whatever their size. Beside every pool the node keeps budgets
(`xmip-core-runtime`'s `budget`): the arrivals it carries at once across
all its Receive Locations (`[tuning]
node_receive_threads_per_hardware_thread`, four per hardware thread by
default, twice one Location's pool — the assistant's drafting, for the
owner to overrule); the bytes of Streams those carries hold
(`receive_chunks_per_thread`, eight chunks for each arrival carried at once,
what one carry is counted as holding — the chunk it writes, the one it reads
ahead and what Xmip Storage encodes and seals of it, measured at seven
chunks at most for a 64 MiB Stream, more than the two this section's
chunks paragraph designs for — so by default the carries bound the bytes,
and a node set lower holds fewer);
and the bytes of Messages its sends hold (`send_chunks_per_thread`, sixteen
chunks for each thread of the Send pool — the assistant's drafting, for the
owner to overrule; section 10, corrected 2026-10-19). A receive asks its
transport for no more arrivals than its Location's pool has threads free
and the node has places, waiting for a place where the node has none, and
what it does not take stays at its far end (section 5). A carry holds its
place until it is told, and its bytes while it carries, let go of before
its turn to tell, so an arrival waiting to tell never holds back one
carrying. A holder with no room waits for one: nothing is dropped, refused
or taken from a far end, and a charge above a whole budget waits until it
is alone and holds all of it, so nothing is too large to go. Every budget
is a default only, set per cluster and node as every `[tuning]` value is.

**Executing keeps the hops in one process.** A node declaring the executing
role runs receiving, processing and sending in one Host Service for low
latency (ADR-0056 and ADR-0018 clause 10a, amendments 2026-10-01); the steps
still hand on through the Ledger.

**Platforms.** The code and its tests are as operating-system agnostic as
they can be (the owner: *it has to be as OS agnostic as it can*). Test runs
on Windows alone are temporary (the owner: *We are temporarily only running
Windows tests, for time reasons. When we are over this hurdle we will run at
least Windows & Linux. I do not have an OS X machine*).

### What proves it

The tests the design is held to, decided with it on 2026-10-01. A test's
Storage node keeps its administration and audit databases in SQLite in
memory and its runtime database in RocksDB, on disk in the test's directory,
so the kill test still proves the runtime database durable (the owner: *for
testing purposes the Xmip Nodes of Storage type can use SQLite in memory for
administration and RocksDB for runtime*).

- a kill at each step: nothing lost, and a repeat only where at-least-once
  allows one (section 15);
- node failover by a lapsed claim: another node resumes from the last
  finished step;
- Storage round robin: a Storage node stopped, and every other node carries
  on through the next one (`deployment-model.md` section 9);
- a Stream far larger than the memory allowed passes, with memory bounded;
- pools grow to their maximum and shrink when idle, and a CPU-bound pool
  never exceeds the core count;
- the sync's latency measured idle and under load, and reported; the sync is
  load, as the network is (the owner, 2026-10-03: *Go for A*), so a Message
  carried one at a time may cost its sync and its connections, measured beside
  it, and a millisecond more, never beyond;
- the Dead Message Queue and its replay (section 9).

Written so far, for Xmip Storage alone (the estate root's `cargo test --test
storage`, and `xmip-core-persist`'s own): a Storage node process killed hard
loses no write it acknowledged, and a hand-on killed at any moment is all
there or not at all; two claimants, one wins, a lapsed claim is taken over
and a release frees it; a Storage node stopped or killed, and a node carries
on through the next; the audit keeper moves each record once; and a
write's latency, measured idle, in process and over TLS. And for the
assembled service, built 2026-10-22 (the root's `failover` and `wire`
tests): a receiving and a sending node, keeping no Storage, carry every
file dropped once while the primary Storage node is stopped mid-run and its
standby promoted; and a call over the wire to the primary, its standby
copying, costs less than a millisecond beyond the same call in process — a
read about 80 µs against 6 µs, a write and its sync about 1.2 ms against
1.1 ms. And for the receive
path through the Ledger (`xmip-core-runtime`'s `tests/ledger.rs`): a receive
killed after its Stream's chunks were written and before its Publication
leaves the chunks and no Message, and every Message whose receive cycle
completed before a kill is in the Ledger after it, with its Journeys, and
reads back as it was received. And for the send step, built 2026-10-03
(`tests/ledger/send.rs` and `send_killed.rs`): a node killed after its
Publications and before it sent leaves every Journey it acknowledged to
another node, which takes each up once its claim lapses and sends it; a node
killed mid-send has every Journey it acknowledged sent once it is restarted,
the one cut short again — at least once, never lost; a send that fails is
written Failed with why while its sender was acknowledged all the same; a
retry's backoff holds no thread, and a stop gives its claim back; and a
Send Port naming a correlation set keeps its order, blocking behind a
failure or setting it aside as the set's `on_failure` says. And, built 2026-10-04 (`tests/ledger/
send_group.rs`, `journey_act.rs` and `send.rs`): a Send Port Group's
Subscription opens one Journey per Port, each in its Port's queue and sent
or failed alone; every send carries its Journey's identifier as its key,
the same on every try; a retry's count is kept in the Ledger and survives a
restart; an Operator's Retry sends a failed Journey again — in its order
where its sequence blocks behind it — and Dismiss ends it Dismissed and
lets its sequence go, each audited. And, built 2026-10-22
(`tests/ledger/work_process.rs`): a client's Messages make one Instance and
its Batch holds them in the order received; two clients carried at once,
the Work Process step dispatching meanwhile, never see one of their Messages
overtake another; a node killed mid-process is started again and finishes
its Instance from the Ledger. And, built 2026-10-19 (`tests/ledger/
send_streamed.rs` and `roomed.rs`, what the process allocated counted): a
64 MiB Message sent to four Send Ports held 1.1 MB at most, read a chunk
at a time and never whole; four departures at a far end's pace read an
8 MiB Stream's 132 chunks 132 times, each chunk once; sends that gather a
Message as large as the byte budget went one after another; two Receive
Locations of 32 threads on a node of 16 places never had more than 16
arrivals taken and untold; and 32 Streams of 4 MiB, 128 MiB whole, held
2.3 MB at most under a receive byte budget of 4.1 MB.

## 4. Actors and Communication Domains

Xmip is not fundamentally an integration engine. Its responsibility is to move
authenticated, authorized, immutable information between communicating actors,
and the same communication pattern recurs at every scale.

An **Actor** is any entity that can communicate. A **Domain** is an Actor that
contains other Actors. The recursion is the point:

```text
Fleet owner
  └── Ship owner
        └── Ship
              ├── Captain
              │     └── Crew
              └── Ship control
                    ├── Navigation system
                    ├── Engine system
                    └── NMEA 2000 network
                          └── Devices
                                └── Sensors
```

Every Domain follows the same rules. A parent informs, delegates and commands
its children; children report, acknowledge and escalate to their parent; peers
communicate when authorized; external communication is policy controlled.

**The runtime does not distinguish between these entity types.** It understands
Actors, Domains, Identities, Policies and Messages, and nothing else. That is
what lets one architecture serve a fleet operator and a sensor on a bus.

### Xmip artifacts are Actors

Actor semantics do not replace or rename anything. Receive Ports, Receive
Locations, Work Processes, Send Ports, Send Locations, Handlers, Nodes and
Clusters remain explicit, named, versioned, configurable and deployable
artifacts. They *gain* actor semantics when they communicate, publish,
subscribe, own work, report status or transfer responsibility.

| Artifact | As an Actor |
| --- | --- |
| Receive Location | receives external input and reports to its parent Receive Port |
| Receive Port | owns the Message after receive, until another Actor takes ownership or a derived Message is created |
| Work Process | may take ownership, orchestrate, assign, transform, publish, subscribe or route |
| Send Port | owns send-side preparation and delivery decisions |
| Send Location | performs delivery and reports the result to its Send Port |
| Handler | an Actor when it participates in execution, capability reporting or delivery |
| Node | an Actor inside a Cluster |
| Cluster | an Actor inside a larger Xmip or organizational domain |

A Receive Location is a crew member reporting to a Captain. The Receive Port is
the Captain of the Message after receive.

> Actor semantics explain how artifacts communicate and transfer
> responsibility. They must never erase artifact semantics.

### Message ownership

**A Message has one owning Actor at every stage of its lifecycle**, and
ownership transfers. Assignment and Transformation do not mutate: they create a
new message form with a new message id, which may have a new owning Actor. The
previous form stays immutable and auditable.

Ownership is what makes "who is responsible for this right now" answerable at
any instant, which is the operational question underneath *Show me the
Journey*.

### Capabilities are not roles

Two dimensions that read alike and are not:

| | Describes | Examples |
| --- | --- | --- |
| **Security role** | what a user or security principal may do in Xmip | Observer, Operator, Developer |
| **Actor capability** | what an Actor can do in communication and runtime execution | Publish, Subscribe, OwnMessage, Report, Command, Execute, Route, Transform, Send, Receive |

A Receive Port has the capability `OwnMessage`. A person has the role
`Operator`. **Do not call an actor capability a role**, and do not mix user
authorization with runtime communication modeling — ADR-0009 exists because
the two collapse into each other the moment anyone stops paying attention.

This is also why a Party is not a role: a Party is recognized, a role is
granted, and a capability is what an Actor can do. Three dimensions.

### The test for Xmip Core

> If a feature does not improve communication between Actors or Domains, it
> probably does not belong in Xmip Core.

## 5. The receive chain

```text
External Stream
    -> Receive Location      physical ingress: transport, security, acceptance
    -> Receive Port          logical ingress: creates the Message
    -> Publication           the Message is made available
    -> Routing               evaluated against Subscriptions
    -> Journey               one per matched Subscription
```

> Receive Locations receive Streams. Receive Ports create Messages. Publication
> offers them. Routing decides where they continue. Journeys carry them.

**The receive order** (the owner, 2026-10-22: *Every received stream must
check in, from what Receive Location, Receive Port. It has to propose its
identity, be authenticated, authorized, promoted, Correlation Set populated,
then we can queue the message in the fashion it needs to be queued*, and
*Identify, Authenticate and Authorize. Those are different uses*). Every
Stream goes through eight steps, in this order:

1. **Check in**: the Receive Location and Receive Port it came through,
   recorded with it (`journey::Received`).
2. **Identify**: the identity it proposes, read at the transport and again in
   the Message (ADR-0019).
3. **Authenticate**: that identity proved.
4. **Authorize**: what it may do, decided by policy.
5. **Prepare, Message creation, Contract and validation.**
6. **Promotion**.
7. **The correlation set's key populated**, from the Message's context: its
   Receive Location's own sequence, or the set the Location and its Port name
   (section 3, *Sequences*).
8. **Queued** in the Ledger, as its set says: its place taken in each
   sequence in the Publication's own write.

Nothing joins a sequence before step 7: a Stream refused at any step before
it holds no place and keeps nothing waiting behind it.

**Failures before Publication are audited receive failures, not Dead Journeys.**
There is no Journey yet to be Dead. This is the single most important boundary
in the model and the one earlier drafts got wrong.

The gate sequence inside acceptance is specified in ADR-0013 and is not
optional or reorderable:

```text
Incoming Stream
    -> transport identification
    -> transport authentication
    -> transport authorization
    -> Message creation
    -> default promotion
    -> configuration may inspect Stream and Message Context
    -> optional message identification
    -> optional message authentication
    -> optional message authorization
    -> Contract implication
    -> optional deserialization
    -> Validation
    -> Publication
```

Transport security is mandatory and precedes Message creation, so **Xmip never
parses content from an unauthorized sender**. Message-level security is
separate and optional and follows Message creation, so configuration can
inspect the Stream and Context before deciding whether it applies. Identity,
Parties and the two layers are ADR-0019's; what Xmip *retains* at each refusal
is ADR-0013's.

### How a receive runs

Decided by the owner, 2026-10-01, validated part by part with the assistant.

Each Receive Location has a bounded pool of I/O threads (section 3), and one
thread carries a Stream through the whole receive call:

```text
transport identification, authentication, authorization
                         refused: nothing is kept
-> the Stream into the Ledger, in chunks, through Xmip Storage
-> Preparation Steps     the Location's, then the Port's;
                         a prepared Stream is a new Stream
-> Message creation and default promotion
                         configuration may inspect Stream and Context
-> optional message identification, authentication, authorization
-> the Location's        Contract implication, optional deserialization,
                         Validation, promotion, Transformation
-> the Port's            the same, in the Port's one format
                         processing depth decides how far (section 7)
-> Publication           the Message record in the Ledger, audited
-> acknowledgement
```

Each step at each level is optional and configured on its artifact
(section 20, *Prepare, Contract, Promote, Transform and Demote at both
levels*). Holding a Stream to a Contract at a Location or Port is
[decided, not built](estate-map.md#arrival-validation): a node refuses to start a
Location that names a Contract until it is.

**The sender is acknowledged after the whole receive cycle** (the owner: *On
arrival each Stream is written to the node's Ledger and then when the Receive
cycle is complete, Promote, Validate and what not then the sender is
acknowledged*). Data Transfer and Batch Load are acknowledged once the Message
is accepted and validated; a Composite interaction holds the call until the
response a Work Process produced (section 11).

**A polled Location rests; a waiting one is asked again at once**
(built 2026-10-12). Every transport declares whether its receive waits for
what arrives — a listener's accept, a socket's read, a broker drained
until quiet, a long poll — or looks and returns at once — a directory, an
object store or a maildrop listed, a query run, a register read
(`xmip-core-transport`'s `Waiting`, no default, its reason in words). A
waiting one is asked again the moment its receive returns, so an arrival
is taken as it lands; its own wait running out is told as a failure asking
again may mend, and is asked again at once too. A polled one that found
nothing rests `[tuning] receive_poll` (a second by default) before it is
asked again, and one that failed in a way asking again may mend rests
`[tuning] receive_backoff` (five seconds), each measured from when that
receive began, set per cluster and per node as every `[tuning]` value is
(ADR-0031, amendment 2026-10-03). A rest is waited on the node's stop,
which ends it at once. Until 2026-10-12 every Location was asked again at
once, and an idle
polled one listed its directory or ran its query without pause.

**A polled Location whose far end tells of a change waits for that word**
(built 2026-10-20, ADR-0024, amendment 2026-10-20). A technology says where
its far end tells (`Transport::notice`): the file transport, its drop
directory. The runtime watches it with the operating system's change
notification (`runtime::directory_watch`), and a Location that found
nothing rests until the word comes or its recovery sweep is over,
`[tuning] receive_sweep` (a second by default), for what lay there before
the watch began or a word missed. A drop directory not there yet is polled
until it is, then watched. So a file is listed the moment it lands: a
file dropped waited about 1.7 seconds for its claim on the getting-started
node until then, and waits about two milliseconds now, the listing and the
claim's turn and rename on the file system — on Windows the turn is the
dropped file held open, one open where a turn file took four changes to the
directory (ADR-0024, amendment 2026-10-21). A database's `LISTEN` is not
built.

**The far end sees a send only once its Message is durable, and the send
is prepared meanwhile** (built 2026-10-20, ADR-0018, amendment 2026-10-20).
The embedded Storage node's writer answers a Publication once it is decided
and written, before its sync, and syncs it then (`persist::storage::Durable`);
the receive cycle hands the Journeys it claimed to the send step at once and
ends — the sender acknowledged — only once the Publication is durable. A
technology whose send keeps what its far end sees back (`Transport::holds_back`)
is handed the Message at once: the file transport writes and syncs its file
beside the target while the Ledger syncs, and renames it into place only once
`Outgoing::kept` says the Message is durable. Every other technology is handed
it once durable, as before. Nothing reaches a far end that the Ledger could
lose.

**A receive takes no more than there is room for** (built 2026-10-19,
`open-problems.md` problem 38). A Location asks its transport for at most
as many arrivals as its pool has threads free and the node's carry budget
has places (section 3, *A node's budget beside its pools*;
`Transport::receive_up_to`), and what the transport does not take stays at
its far end for a later receive: the file family claims no more of a
directory listing than that, the rest left as dropped and taken by the
next listing; an object store's listing, a SQL query's rows and a kept
subscription drained hand over no more. Until 2026-10-19 a receive took
every arrival its transport handed over — the file transport claimed a
whole listing at once — and queued what the pool had no thread for, so
what waited in memory grew with the batch.

**A stop drains what the far end already let go of** (built 2026-10-15,
ADR-0018, amendment 2026-10-15). A far end that keeps what it hands over
until it is told — a file in its directory, a leased message, a caller
waiting for its answer — loses nothing when its Location stops taking: it
sends it again. One whose protocol cannot defer
(`transport::Acknowledgement::at_most_once`) has let go already: raw TCP's
sender is done once its kernel took the bytes, so a connection the
operating system completed and queued in the listener's backlog before the
stop is a Stream its sender was told went through, and so is a datagram in
a socket's buffer. A Location whose receive waits and whose far end let go
of what it handed over therefore goes on receiving after the stop until a
receive finds nothing — which its own wait bounds, as it bounds every
receive — and never past `[tuning] receive_drain` (a second by default)
from the stop, so senders that never pause cannot hold it. A polled
Location, and one whose far end is told, stops once its current receive
returns. Until 2026-10-15 every Location did, and the listener was closed
with its backlog in it.

Refusals before Publication are audited receive failures. From Message
creation on the Stream is kept; a Message failing Validation is kept and
answered where the protocol can; no Journey exists (ADR-0013 clauses 1 to 3).

**Where it is configured.** A Receive Port (section 6), a Receive
Location's interaction type and processing depth (section 7), and retention
and audit policy per Port and Location (section 16) are configured as
section 20, *Where the runtime's settings are configured*, says.

## 6. Receive Port and Receive Locations

A **Receive Port** is the logical common ingress for information of one
purpose — Invoices, Purchase Orders, Customers, Laboratory Results. It owns
common actions, Message creation and Publication.

A **Receive Location** defines how a Stream reaches its parent Receive Port. It
owns the transport binding and endpoint, the accepted identities and
mechanisms, the interaction type, the response behavior, and any
location-specific Content and Contract configuration.

```text
HTTP Receive Location ─┐
FILE Receive Location ─┼─> Invoices Receive Port ─> Publication ─> Routing
FTP  Receive Location ─┘
```

The Receive Port executes with the context of the originating Receive Location.

**The Location speaks the format of its Party; the Port speaks the one
format of its purpose.** Two Receive Locations of different formats meet in
one format at their Receive Port: each Location may prepare, hold to a
Contract, validate, promote and transform what it receives, and the Port
may do the same in its own format before Publication (section 20).

## 7. Interaction and processing depth

These are two independent characteristics and are constantly conflated.

**Interaction** — what the caller expects back:

| | |
| --- | --- |
| **Composite** | the caller expects a response composed through configured Xmip work. The Receive Location may wait for a Process-produced response. SOAP, Web API, gRPC. |
| **Data Transfer** | the caller transfers information and is acknowledged once acceptance succeeds. The Journey then continues asynchronously. |
| **Batch Load** | a batch or large workload is accepted and acknowledged for later processing. Configuration decides whether it becomes one Journey or many. |

**Processing depth** — how far Xmip interprets the content:

| | |
| --- | --- |
| **Transfer** | move a trusted, often very large Stream with no deserialization and no payload inspection. |
| **Light** | route on trusted sender, Receive Location, declared type and other metadata. |
| **Context** | interpret through Content, Contract and Path for content-aware Routing. |

The same transport may serve more than one interaction type. Transfer and Light
require no Path evaluation, which is what makes them cheap.

## 8. Preparation Steps

A **Preparation Step** prepares a Stream before or after normal Content
processing. It is Xmip's term for the useful part of what BizTalk Pipelines
did, and it exists because external standards are not always followed.

```text
Decrypt / Encrypt          Decode / Encode
Decompress / Compress      Convert character encoding
Extract / create archives  Normalize line endings
Unwrap / wrap              Digitally sign or verify
Repair explicitly configured Party quirks
Custom Preparation Step
```

**Preparation Steps contain no Process decision logic and perform no
Assignment.** That restriction is what keeps them composable.

Preparation Steps are configured on a Location and on its Port, and work on
the Stream at both: on receive the Location's run first and the Port's
after, before Message creation; on send the Port's run first, after the
Location serializes and demotes, and the Location's last. The Port's are
the inner layer — what every Location's Stream shares — and the Location's
the outer, what its transport or Party adds.

## 9. Publication and Routing

Publication is part of Routing, not a separate platform concern.
`xmip-core-route` owns Publish, Path, Subscription evaluation and Dispatch.

A **Publication** is not an attempt. It is the act that makes a Message
available for Routing, and **every Publication is audited**.

**Routing** evaluates a Publication against Subscriptions. A Subscription may
target a Work Process, a Send Port or a Send Port Group.

A Subscription's **filter** is one line of Xmip's expression language
(ADR-0066, `xmip-core-path`'s `expression`) — `MessageType = 'Order' and not
Amount > 1000` — compiled once, when the Application holding it is read, and
decided from the compiled tree for every Publication. A property it names is
read by the route technology its prefix names (ADR-0046); a value that is
not there is *unknown*, with its reason, never a silent false, and only a
filter that holds matches.

```text
Publication              one event, one identity, immutable
  └── Journey            one per matched Subscription
```

A Journey is one line of execution, **not a tree**. A Publication is finished
when all its Journeys are terminal — not when they all succeed. "3 matched,
2 delivered, 1 failed" is expressible without any record having to lie.

Journeys are independent because the world is. If a Process succeeds and an
SFTP Send fails, the file cannot be un-sent. There is no transaction across a
Send Location, so there is none across a Publication.

**Zero matches produces zero Journeys**, and the Message goes to the Dead
Message Queue with its receive context, validation results, correlation and
trace references, audit references, failure reason, timestamps, artifact
identities and subscription evaluation metadata. That metadata is the point:
when nothing matched, the operator's question is "what were the promoted
properties, and which Subscription nearly matched?" — not "what was in the
body".

### How routing runs

Decided by the owner, 2026-10-01, validated part by part with the assistant.

Routing runs inside the receive cycle, on the thread carrying it, before the
sender is acknowledged (the owner, 2026-10-03: *Go with A*): the Message's
promoted properties are matched against the compiled Subscription filters,
one Journey per match, and the Publication — its Message and its Journeys —
is one atomic write, in the receive cycle's one statement on one Storage node
(section 3). No routing pool and no claim on a Publication: a node that dies
before that write has acknowledged nothing, and the sender sends again. The
write is kept by its Message: asked again after its answer was lost, it
writes nothing and answers the claims its node still holds of it, so a
Journey another node has moved on since is never reset (section 10,
*Corrected 2026-10-06*). A
paused Subscription's Journey is written and held until the Subscription is
resumed, and the held ones are picked up oldest first. The chain is recorded
and bounded (ADR-0026). A sequence's position, by its key, is in the
Ledger (section 3, *Sequences*), its places taken in the Publication's own
write. Nothing is deduplicated.

**The Dead Message Queue is Ledger state**, not a place beside it: a
Publication that matched nothing is kept in the Ledger with its receive
context, validation results, promoted properties and, for each Subscription,
its reason for declining. An operation view, **Dead Message Queue**, lists it
per cluster and node, opens one to show its properties and the declines, and
offers Replay as an Operator act once a Subscription is added or fixed
(ADR-0052, amendment 2026-10-01).

Built 2026-10-03. Each node has one queue in the Ledger, found by the
name-based identifier of `<node>/dead-message-queue`; the entry — the
Message's identity and Stream, its node, Receive Location and time, what its
gates concluded (the transport identity, the message identity where one was
carried, their alignment; Contract validation adds its results when it
lands), its promoted properties and every Subscription's decline in the
order asked — is written in the Publication's one write, so a Message nothing
matched is kept with why or not at all, and its sender acknowledged only
then (`persist::storage::DeadMessage`). The queue is numbered as it is
written and read oldest first, a page at a time, as a paused Subscription's
is. **Replay** reads the entry, routes its promoted properties against the
node's Subscriptions of now and, where something matches, writes the
Journeys it opens — every one held at the end of its Subscription's queue,
since no receive cycle is left to depart from, and picked up from there as a
resume picks up — its audit record, and the entry taken out, as one write;
the entry is remembered as replayed, so a Replay asked again after a lost
answer, or a Publication asked again, writes nothing twice. A Message that
still matches nothing stays, and the refusal names every decline. Replay
reaches a node as Pause does, an order its node takes (`observe::Noun::
DeadMessage`, `observe::Act::Replay`), audited; the node publishes the oldest
hundred of its queue in its snapshot (`[[dead_messages]]`).

**Routing matches against the cluster's Subscriptions, read from Xmip
Storage when needed and kept in memory, their filters compiled, until they
have not been used for an hour, or a Host Service has written changed
Subscriptions, which every node learns from the generation Xmip Storage
answers with each Ledger write** (section 3; ADR-0031, amendment
2026-10-02) — decided by the owner, 2026-10-02: *They are shared*
([decided, not built](estate-map.md#shared-subscriptions)). What runs today matches
against the Subscriptions of the Applications the node itself binds,
compiled as it starts
([built, in the assembled service](estate-map.md#subscription-routing)).

### Duplicates are a business decision

**A Stream may be published into Xmip twice, and Xmip accepts it twice.** Two
Streams, two Messages, two sets of Journeys, all correct. Xmip does not own the
consequences of a client sending the same thing more than once.

Two identical byte sequences are not the same event. A retry and a genuine
resubmission look the same on the wire, and only the domain knows whether the
second invoice is a duplicate or a correction. A platform that deduplicates has
guessed, and it will be wrong silently.

So a Work Process decides. A duplicate is not refused at a gate — it authenticates,
validates, becomes a Message and gets Journeys — and a Process that recognizes
it stops the Journey as `Dismissed`, not `Failed`. See ADR-0013 clause 4c.

Where a transport's own specification defines duplicate semantics, the transport
Module honors them. That is conformance, not judgment.

### Subscription Instances form a chain

A Subscription Instance is one evaluation that came out true, and it becomes
part of the Message's history. Because a Process may publish back into Xmip,
those instances **form a chain, much like a call stack**: this publication
happened because that Subscription matched, which happened because an earlier
Process published, which happened because an earlier Subscription matched.

The chain is what makes a Journey explainable after the fact. Without it, a
Message that arrived somewhere unexpected has no answer to "how did it get
here" beyond a list of things that happened near each other in time.

**The chain is bounded by a ceiling on its depth**, and it is worth saying
what that does and does not catch. A Process that publishes a Message which
matches a Subscription that starts the same Process is a loop, and it is the
classic way an integration platform takes itself down. Every Journey carries
a depth, a node configures a ceiling, and the constructor that makes a caused
Journey refuses the link that would pass it — naming the Subscription and the
Process rather than a number. ADR-0026.

**This is a depth limit and not cycle detection.** Near the ceiling a loop and
a long legitimate chain look identical. Cycle detection over artifact
identities is the better answer, and an execution budget per originating
Message is what an operator ultimately wants; both stay open problems.

### Promotion has no counterpart for Transformation

**There is no separate concept of transformed properties.** Promotion extracts
values into runtime context; Transformation changes content. When a
Transformation makes new values worth routing on, they are promoted, using the
same mechanism as any other promotion.

This is stated because the symmetry is tempting and wrong. A second property
namespace fed by Transformation would mean Subscription evaluation had two
places to look, and the first question about any promoted property would become
"which kind is it".

### Path

Format-native Path technologies are expected and supported: XPath, JSONPath,
JSON Pointer, FHIRPath, EDI selectors, HL7 selectors, and stakeholder-defined
technologies. A Message retains its applicable Content, Contract and Path
technologies until Assignment or Transformation creates a new Message.

**Path addresses materialized content.** It is the tool for a Transformation
that has a document in hand.

### Content Selectors, promotion and demotion

Promotion and demotion cannot use Path: promotion runs against a Stream that
has deliberately not been materialized. Xmip therefore has its own selector
language for the two, evaluable without materialization because every
selector declares how far into the Stream it must reach. **Promote** extracts
selected properties as far and as fast as needed, then stops; **demote** is
its send-side counterpart, writing configured properties into the outgoing
Stream. The language, its four segment kinds and three evaluation modes are
`module/core/capability/promote/doc/content-selector.md`.

## 10. Send model

**Send Port Group** — a named collection of Send Ports and nothing more. It
owns no delivery behavior. A Subscription targeting a Group dispatches to
every Send Port in it, and each executes independently.

**Send Port** — the logical outbound artifact. Several Subscriptions may
dispatch to the same Send Port. It may receive a routed Message, Transform it,
select and invoke ordered Send Locations, apply retry and failover policy, and
audit its actions.

**A Send Port cannot perform Assignment.** Receive and Send artifacts hold only
the current Message and cannot make Process decisions or create assigned
Messages. Assignment belongs to a Work Process. Transformation may happen in a
Receive Location or Port, a Work Process or a Send Port or Location.

**Send Location** — one physical outbound endpoint, owning the concrete
transport, destination, presented identity, serialization, demotion, optional
outgoing Contract validation, delivery and optional response transport.

The reverse of receive: **the Send Port speaks the one format of its
purpose, each Send Location its endpoint's.** The Port may hold to a
Contract, validate, transform, demote and prepare; the Location may
transform, hold to a Contract and validate before it serializes, demote and
prepare. Port first, then Location, the Port's Preparation Steps inside the
Location's (section 20).

A Send Port succeeds when one of its Send Locations succeeds. Retries apply to
the active Send Location; failover moves to another per Send Port policy. If
all Send Locations fail, the Journey fails.

The identity a Send Location presents resolves per ADR-0006:

```text
Send Location -> Send Port -> Send Port Group -> Xmip Sending Process
```

First one found wins, and it is resolved independently of any receive-side
identity.

### How a send runs

Decided by the owner, 2026-10-01, validated part by part with the assistant.

A Send pool — I/O-bound, bounded as a bulkhead (section 3) — claims a Journey
destined for a Send Port. A Send Port Group is only a named set: routing
already made one Journey per Send Port in it. The Send Port may transform,
never assign, and picks its Send Locations in configured order. The Send
Location validates the outgoing Contract while the Message is still
structured, serializes and demotes in chunks, presents the identity found
first along the chain above, and delivers on a kept connection.

Retries are on the active Send Location; failover follows the Send Port's
policy. When every Send Location has failed the Journey is `Failed` and its
Message stays with it — it does not go to the Dead Message Queue. A response
from the far end is an ingress — identified, authenticated, authorized and
audited — and continues the same Journey (section 11). The Journey's end is
written with its outcome, an Event is produced per outcome (section 17), and
its audit is written through Xmip Storage (section 16).

The owner accepted four additions:

- **A retry waiting for its backoff holds no thread.** Its due time is
  written to the Ledger, and the Send pool picks it up when it is due.
- **The deduplication key is the Journey id**, not the Message id: one
  Message may have several Journeys, each delivered once (section 15).
- **A sequence's failure policy is its correlation set's**, block by
  default, skip as the option (section 3; the owner, 2026-10-22).
- **A large Message's outgoing Contract validates streaming**, chunk by
  chunk, or that Send Location refuses to start.

**Built 2026-10-03** (`xmip-core-runtime`'s `send_step`), closing the
review finding that inline sends recorded no outcome and nothing took up
an unfinished Journey. **The receive cycle sends nothing**: it ends at the
Publication's durable write and the acknowledgement (section 5). Its claimed
Journeys are handed to the Send pool as soon as the Publication is decided,
before its sync, and a far end sees one only once the Publication is
durable: a technology that holds its delivery back (the file transport,
which renames its file into place last) prepares the send meanwhile, and
every other is handed it once durable (ADR-0018, amendment 2026-10-20). The
Publication keeps every Journey that is not held in the queue of where it
leads — a Send Port's, found by the name-based identifier of
`<cluster>/<kind>/<name>`, the same on every node — and, where this node
sends that Port and it names no correlation set, claims it in the same write and
hands it to the Send pool in memory, so the send costs no sync of its own
before it starts — where the pool admits it (*Corrected 2026-10-06*
below). Each pass tries the Port's Send Locations in configured
order (`send_locations`, or the Location bound under the Port's name),
`retry` on the active one and `failover = "next"` to the next, and hands on
in one write: **Completed** and out of its queue; **Failed** with why in
words, its Message with it, kept in its queue for an operator — where its
sequence's `on_failure` is `block` it stops the sequence behind it, and
otherwise it lets its place go; or **Recovering**, its due time kept at its place in
its queue and its claim released, a scan passing over it until it is due
(corrected 2026-10-16, below; until then its claim was kept to its due
time and the node kept the Journey in memory to start it again).
**Recovery** is a scan: as a node starts and every `[tuning] send_scan`
after, what is due in each queue it sends is read, in the order it fell
due (corrected 2026-10-21, below; until then the whole queue, oldest
first), and every Journey no live claim holds is claimed (`[tuning]
send_lease`) and sent — one a dead node
left, one whose send was cut short, one no node sending its Port held;
claims of work in flight are renewed, and a stop gives back the claims of
what waits. A Send Port naming a correlation set has one Journey of each
key in flight at a time, the oldest first, and every Journey waits until its
Stream heads the sequences it holds end to end (section 3, *Sequences*): a
pass that finds it does not gives its claim back, tries nothing, and is taken
up again once it does. A paused Subscription's resume moves each Journey it
held to its Send Port's queue in one hand-on, and the send step sends it
from there. The node's snapshot publishes, at `<node>/send/<Port>`, what
was sent, what failed — the last Journey that did, and why — and what
waits for its due time.

**Built 2026-10-04**, closing what the send step left:

- **One Journey per Send Port of a Send Port Group.** A Subscription to a
  Group opens a Journey for each Port of the Group, in the Group's order,
  each led to its Port (the Journey's `send_port`) and queued in its Port's
  queue, in the Publication's one write; each Port is sent, retried, failed
  and acted on alone. A paused Subscription holds each, and a Replay from the
  Dead Message Queue opens them the same way. A Group no Application of the
  publishing node declares opens one Journey to the Group, which no node
  sends.
- **A retry's count is in the Ledger.** The active Send Location and how
  often it was tried are the Journey's `attempts`, written with every
  hand-on of a send, so a node restarted, or another taking the Journey up,
  counts on from them rather than from zero.
- **The deduplication key reaches the endpoint.** Every send carries the
  Journey's identifier as the key of what the transport contract's
  `send_from` is handed (`Outgoing::key`, `xmip-core-transport`; until
  2026-10-19 `send_keyed`); a technology whose protocol has an identifier its
  far end deduplicates by puts it there, its README says where, and every
  other sends as before, at least once (section 15). Thirteen carry it:
  HTTP (`Idempotency-Key`), AMQP and RabbitMQ (`message-id`), ActiveMQ
  (`_AMQ_DUPL_ID`), IBM MQ (`MsgId`), MSMQ (the SRMP message id), Kafka and
  Redpanda (the record key), Azure Service Bus (`MessageId`), NATS
  JetStream (`Nats-Msg-Id`), AS2 (`Message-ID`), AS4 and Peppol
  (`eb:MessageId`).
- **Retry and Dismiss** (section 13) are an Operator's acts on a Journey
  that failed, through the node's orders as Pause and Replay are, audited
  with who acted and gated by role on every surface (`xmip_operate.h`
  section 16). Each is one hand-on under a claim: Retry writes the Journey
  Active, its tries begun anew, and moves it to the end of its Send Port's
  queue — keeping its place in its sequence, so the sequence goes on in
  order from it; Dismiss writes it Dismissed, its history kept, and takes it
  out of the queue, so the next of its key goes. An act is taken by a node that sends the Journey's
  Port, the one whose `<node>/send/<Port>` showed it failed.

**Corrected 2026-10-05**, after an external review of the send step:

- **A read is acted on only under its claim.** An operator's Retry or
  Dismiss reads the Journey, takes its claim, and reads it again: where
  another writer moved it between the two — another operator's act, a node
  that sent it — the act is refused in words and nothing is written, so an
  act never writes back a state the Journey has left. A scan reads a
  Journey again under its claim with its place in the queue, and sends it
  only where it is still there and still to be sent.
- **A send whose thread panics is settled.** It is written Failed with why —
  kept in its queue for an operator, as every Journey that failed is — its
  claim ended, counted and audited; it is never left owned, its claim
  renewed and passed over by every scan.
- **A scan claims no more than the Send pool can take.** A backlog waits
  unclaimed in its queue rather than claimed behind the pool, and the
  claims of work in flight are renewed on a thread of their own, every
  third of a lease, so no scan of a backlog, however long, holds a renewal
  back.
- **The Journeys that failed are discoverable.** A scan that reads a
  Journey Failed — one that failed before the node restarted, or on another
  node — keeps it as its Send Port's evidence; a read of the whole queue
  forgets one dismissed or sent again elsewhere. The snapshot publishes a
  record at `<node>/send/<Port>` for every Send Port the node sends, apart
  from its Send Locations — until now the figures were looked up by each
  Send Location's name, so a Port of several Locations had none — with how
  many failed wait in its queue; and, beside its records, how many and the
  oldest hundred of them with why (`[tuning] failed_window`, corrected
  2026-10-16, below). Every one is read from Xmip Storage a
  page at a time (`xmip_operate.h` section 16), and every surface lists them
  at the Port's scope with Retry and Dismiss on each.

**Corrected 2026-10-06**, after a review of the same:

- **Admission is the one door to the Send pool.** A Publication, a resumed
  Subscription's move and a scan each claim a Journey only under a place
  the pool admits: its most threads, less every Journey the node owns —
  handed, queued, sending, or waiting for a retry's due time — and every
  place admitted and not yet owned. What has no place stays durable and
  unclaimed in its queue, and the queue is read again the moment a place
  frees, so a slow far end leaves its backlog in the Ledger and what the
  node holds in memory is bounded by the pool's threads. Until now only a
  scan asked: a Publication claimed every Journey it opened for a Port the
  node sends and handed it on, and the pool queued whatever came. A retry
  waiting for its due time holds no thread but holds its place, so a far
  end failing every send slows its node's admissions rather than filling
  its memory.
- **A scan claims on the send threads.** What a scan finds unclaimed in a
  queue is claimed and read on the send thread its
  place was admitted for, so a backlog's claims share their commits; until
  now the dispatching claimed them one by one, a commit's sync each, which
  a backlog refilled through the scan would have paid for every Journey.
- **A Send Port with failed Journeys waiting is Done.** Its record at
  `<node>/send/<Port>` is Done — blocked or failed, the pain an operator's
  Retry or Dismiss solves (`observability-model.md` section 6) — while any
  waits in its queue, the most severe of the Done where one blocks its
  Send Port's sequence, and Fine once none does; what failed before
  and was acted on is history in its figures and leaves it Fine. Until now
  it was Fine whatever waited, and left out of what needs attention.
- **Now and history are published apart.** Every Send Port the node sends
  publishes its failed Journeys (`observe::FailedJourneys`) — `count` now,
  zero where none, so a surface says *none now* from the record and never
  from its absence; `blocked`; the oldest hundred — and, apart from them,
  `last_failure`, the last Journey that failed there since the node
  started, which may since have been retried or dismissed.
- **A Publication is written once, by its Message.** Its write keeps, in
  the same batch, that it was written and the digest of what was asked; a
  Publication asked again — a node's request repeated after its answer was
  lost, which a Storage client asks of the next Storage node — writes
  nothing and answers the claims of it its node still holds under their
  tokens, and the node sends only those. Until now a repeated Publication
  wrote its Message and every Journey again: a Journey another node had
  completed meanwhile was written back to where the Publication left it,
  queued again and claimed again, completion lost and sent a second time.
  Another Publication of a Message published before is refused; a business
  Message published again is another Message (*Duplicates are a business
  decision*, section 9).
- **A renewal's answer is acted on.** A renewal that finds a claim another's
  — it lapsed, and another node took the Journey up — stops the send: no
  further Send Location is tried from this node, nothing is written, and
  the loss is counted at its Send Port and audited. A renewal Xmip Storage
  does not answer leaves the claim unconfirmed, and the Send Port is Done
  from the first, its evidence naming Xmip Storage as what did not answer
  and since when — the owner, 2026-10-06: *Storage is not here is a
  flat-out error*; until then it was Stressed. The window below bounds
  attempts and softens nothing: a claim is surely held a lease from when the
  request that last confirmed it was asked — the Storage node counts it
  from its own later now — so the node tries Locations only until then, on
  its own clock, never comparing two clocks, and past it presumes the claim
  lost, audits it once, and tries nothing more until a renewal is answered;
  whatever it writes after is decided by the claim in Xmip Storage. The
  claim is asked before a Location is tried and again once its Message is
  authorized and the bytes its send holds have room (corrected 2026-10-19,
  below), and once more as its first byte would go, after a transport that
  gathers has read it whole (`transport::Outgoing::checked`), so a claim
  lost while a send waited or a large payload was read starts no send
  (2026-10-12, after a review). A send
  already under way is not called back: it carries the Journey's
  identifier, the key the far end deduplicates by, so another holder's send
  of the same Journey is the same delivery (section 15). Until now every
  renewal's answer was dropped, and a node that had lost its claim went on
  trying Locations.

**Corrected 2026-10-08**, after a second review of the same:

- **A renewal's answer speaks only for the claim it asked about.** Every
  answer — renewed, lost or unanswered — is applied only while the node
  still holds the Journey under the token the renewal asked with. Until
  now only a renewed answer was checked: a late lost or unanswered answer
  for a claim whose send had ended marked the claim an operator's Retry had
  taken since lost or unconfirmed, stopping a valid retry and misreporting
  its Port.
- **A renewal never shortens a deadline.** A claim kept to a retry's due
  time and a lease past it keeps that deadline: Xmip Storage renews a
  claim to the later of now and a lease, or the deadline it holds, and the
  node's own reckoning does the same. Until now a renewal asked before a
  retry's hand-on and answered after it cut the claim back to a lease, so
  another node could take the Journey up and retry it before its backoff
  ended.
- **A round of renewals is one request.** The node renews every claim in
  flight in one request to Xmip Storage, a third of a lease after the last
  round began, so a slow answer costs the round one wait, never one per
  claim, and a round ends well inside a lease however many claims it holds.
  Until now each claim was its own request, one after another, so
  unanswered requests added up across claims and could use up the lease
  of healthy work.
- **A queue that cannot be read is said.** A scan whose read of a Send
  Port's queue Xmip Storage does not answer marks the Port Done, its
  evidence saying since when and Xmip Storage's answer, audited once, and
  Fine again at the first read answered. Until now the failed read ended
  the scan silently, and a Port with no claims and no failures known was
  published Fine while what waited in its queue could not be found.
- **The failure backlog is indexed.** A Journey read Failed again is found
  by its Journey at once, and a whole read of a queue forgets every place
  passed over that has left it; until now each read looked through every
  Failed Journey of the Port, and what a scan passed over was never
  forgotten. The node still keeps each Failed Journey of the queues it
  sends in memory; keeping the count in Xmip Storage is open
  (`open-problems.md` problem 34).

**Corrected 2026-10-16** (`open-problems.md` problem 34):

- **Xmip Storage keeps the failure backlog, the node a window of it.** The
  hand-on that writes a Journey Failed names its queue and why, and Xmip
  Storage enters it at the end of that queue's index of failed Journeys
  and marks its place in the queue failed, in that one write; an
  operator's Retry or Dismiss takes it out in its own. The index is
  numbered as it is written, as every queue is, so how many wait is one
  read of its places and the oldest are its first entries. The node keeps,
  per Send Port, that count and the oldest `[tuning] failed_window` (a
  hundred by default), read again only where the index's places moved;
  the snapshot publishes that window, and a surface pages the rest from the
  index, each page one read. A scan passes over a place marked failed
  without reading its Journey; whether it blocks a sequence is the
  sequence's, which keeps its place. Until now the node kept every Journey a scan had read Failed,
  with why, and every place passed over, so its memory grew with the
  failures, and every node read each failed Journey once after a restart
  to find it again.
- **A Journey waiting for a retry holds no place** (the owner, 2026-10-16;
  `open-problems.md` problem 43). The hand-on that writes it Recovering
  keeps its due time at its place in its queue — Xmip Storage's now and the
  backoff, on Xmip Storage's clock — and releases its claim, so it holds no
  claim, no place in the Send pool and no memory. A read of a queue answers
  with Xmip Storage's clock beside the entries, so a node tells how long an
  entry still waits as a duration and never compares two clocks; a scan
  passes over an entry not yet due without claiming it — its place in a
  sequence kept, so the sequence waits behind it — and claims it, on any
  node, once it is due, its tries counted on from its `attempts`. The node
  keeps per queue only the earliest due time and how many wait, as the
  queue's last read showed and as each hand-on Xmip Storage took since
  that read began noted, and wakes for that time — within a millisecond
  apart from load, through `xcore::wake`, on Windows a high-resolution waitable timer where
  a `Condvar` ended on the system tick up to 14 ms late (the owner,
  2026-10-16; ADR-0050, amendment 2026-10-17): a read that passed a
  Journey's place before its hand-on landed keeps its due time, where at
  first it dropped it and the retry waited for the next `send_scan`, a
  second by default, after it was due. Until now a waiting
  Journey stayed owned, its claim kept to its due time, and counted against
  the places every Port shares, so one far end that failed every send
  filled them and the healthy Ports sent nothing until its retries ended.
- **A pass that tried nothing writes nothing.** A pass whose claim is not
  surely this node's when it begins — its last confirmation older than a
  lease, though no renewal found it another's — gives the claim back and
  asks for its queue to be read, where a scan claims it afresh. Until now
  it was written Recovering: an entry and a backoff for a try never made,
  which a node under load showed as a send entry too many.

**Corrected 2026-10-17**, a race the change above brought in:

- **A scan's claim reads the place again, its due time with it.** Every
  claim a scan takes, on any Send Port, reads the Journey's place in its
  queue again under the claim: it is sent only where the place is still
  there, still this Journey's and due, and its Journey still to be sent;
  a place whose retry is not yet due gives the claim back and is woken for
  at its due time. Releasing a waiting Journey's claim (problem 43, above)
  let a scan that had read the queue before that Journey's hand-on landed —
  no due time at its place then, and the Journey no longer owned when the
  scan looked — take a claim nobody held and send the Journey again at
  once: a far end received it twice from one node. Until then only an
  ordered scan read the place again, and it did not look at the due time. Xmip Storage's claim stays as section 3 has it — *set the
  owner where the owner is empty or lapsed* — and already refuses any claim
  held under another token, whoever holds it: in the race no claim was
  held, so only the read under the claim can tell, and the same holds for a
  scan of another node.

**Corrected 2026-10-19** (`open-problems.md` problem 38):

- **A send takes its Message a chunk at a time.** Departure hands the
  transport the Message as the Ledger keeps it (`xmip-core-transport`'s
  `Outgoing`, through `Transport::send_from`): its length known before its
  first byte, read a chunk at a time, opened from its start by every read —
  so a kept session that fails on reuse and carries the exchange again
  reads it again — and held to its length, a body ending short or running
  on refused in words. A technology that sends as it reads writes it on
  (`Outgoing::write_to`, or `Outgoing::pieces` in requests of its
  protocol's own size): file, TCP, a Unix domain socket, a named pipe,
  MLLP, WebSocket, FTP, SFTP, SMB and NFS. One whose protocol needs the
  whole body first — a datagram, a frame, a record with its digest, a
  signature over all of it — gathers it (`Outgoing::gather`). Every
  technology declares which, with why (`transport::Sending`, no default).
  Until now departure read each Message whole before its transport sent
  it, since `Transport::send` took a byte slice.
- **A fan-out's departures read each chunk once.** The departures of one
  Stream in flight on a node — one Journey for each Send Port a Message
  reaches, sent side by side — share one read of it: the first opens it
  from Xmip Storage, and every other takes each chunk from that read, lent,
  never copied, while it keeps up (`xmip-core-runtime`'s `stream_share`).
  The read keeps the last chunk it took for a departure reading alone and
  five more for each other departure reading it — the room each one's own
  read of Xmip Storage would have held (`stream_share::KEPT_PER_READER`).
  A departure about to let go of the chunk another of its read takes next
  waits for that one to take it — a thread kept from its processor on a
  loaded machine — for at most what the kept chunks take the read to pass
  at its pace, over the whole Stream for each departure waited for, so a
  slower Send Port holds the others back no longer than that, once
  (ADR-0018 clause 11, the bulkhead). A departure further behind — a
  slower far end, a send begun later — asks Xmip Storage for the chunks it
  missed, from the chunk it reached
  (`persist::storage::ChunkReader::shared_from`), from a read of its
  Stream that reaches its place where there is one and from one of its
  own, which the next behind shares, where there is none; before each
  chunk it moves to a read that reaches it and that more departures read,
  so the reads of a Stream come together as their places meet (ADR-0018,
  amendments 2026-10-20). Until now each departure read the Stream whole.
- **A send holds its bytes within the node's budget.** Beside the Send
  pool's count of Journeys (*Corrected 2026-10-06*, above), what a send
  holds is held from the node's byte budget for sends (section 3, *A node's
  budget beside its pools*; `[tuning] send_chunks_per_thread`): the whole
  Message besides where its transport gathers it, and where it streams what
  reading it holds — what Xmip Storage reads, opens and decodes of a chunk,
  the chunk lent and the piece written on, measured at a little over five
  chunks for a 64 MiB Message and counted as six (`budget::STREAM_CHUNKS`). A send with no room waits for one before the
  transport's I/O, its claim renewed, and its claim is asked again after
  the wait; a Message larger than the whole budget waits until it is alone.
  So sends that gather large Messages go one after another rather than
  growing the node.

**Decided 2026-10-19** (the owner; `open-problems.md` problem 39, ADR-0024,
amendment 2026-10-19): **a sent file not yet in place is its node's.** A
send that writes its file beside the target and renames it into place — the
file transport's, so a reader finds the old file or the whole new one —
names it for the node writing it, `<target>.xmip-sending.<the node's
location, percent-encoded>.<count>.<nanoseconds>`, as a claimed name carries
the node (`xmip-core-transport`'s `claim::Claimant::sending`). A process that
dies between the write and the rename leaves it; its node removes it as it
starts, while it recovers its claims — a Receive Location in its drop
directory, a Send Location beside its target — and removes no other node's,
nor one a send of the same process is still writing. Until 2026-10-19 the
name carried the process, and such a file stayed for good.

**Corrected 2026-10-19** (the owner agreed the proposal; `open-problems.md`
problem 40, ADR-0013, amendment 2026-10-19): **a queue is read in its order
by an index.** Every queue in the Ledger — a Send Port's, a paused
Subscription's, a node's Dead Message Queue, and a Send Port queue's index
of failed Journeys — is indexed on its queue and place, written with each
entry and taken out with it; on a database server that index is the table's
primary key. A page of a queue is one ordered range of the index from its
place and a read of each entry it finds, and the queue's first place is
found by the read that asks for it, so the one writer never walks a gap
when an entry is taken out. Until now an entry, kept under a keyed hash, was
found by asking each place in turn: a gap with an entry held on each side of
it was read place by place, by a page and by the writer moving the first
past it. Measured over a gap of a million places, in memory, a debug
build, the fastest of five rounds: a page of the two entries either side
of it 16 µs in three key reads and one range, and the writer's part of
taking out the first 20 µs in three key reads and no range, where each
read the million places.
An embedded store made before the index lacks it, and before the first
release nothing migrates it.

**Corrected 2026-10-21** (the owner, 2026-10-19; `open-problems.md`
problems 40 and 43, ADR-0013, amendment 2026-10-21): **a send scan reads
only what is due.** A Send Port's queue is indexed, too, on whether each
entry failed, when it is due — a retry's due time, or the epoch for one due
since it was held — and its place (`held_due`); what is due now is one
range of it. A scan reads only that, a page at a time, in the order it fell
due, and stops where the Send pool is full; what holds a sequence behind it
is the sequence's (corrected 2026-10-22, section 3, *Sequences*: until then
an ordered Port's scan read its whole queue in order, the one place order
was kept, now deleted). How many wait for a retry, and when
the earliest is due, Xmip Storage keeps and tells (`held_due_places`); a
scan no longer reads what waits to learn it. A Journey that failed waits
for no retry: its due time goes with the mark. Each queue's first entry of
each part is kept by the one writer, so a read never steps over what was
taken out before it, which `RocksDB` keeps as marks until it compacts
them. Until now every scan read every entry its queue held, waiting or
not. Of 11,003 held, three due, a read of what is due reads four keys and
two ranges where the whole queue read 11,176 keys.

**Where it is configured.** The Send Port's policy — the order of its Send
Locations, retry and failover — is configured as section 20, *Where the
runtime's settings are configured*, says.

## 11. Responses, in both directions

The symmetry is exact, and it is the clearest statement of what Ports and
Locations are for:

> Locations exchange Streams with the outside world. Ports exchange Messages
> with Xmip.

**Receive side.** A Receive Location may return a response. Data Transfer and
Batch Load acknowledge as soon as the Message is accepted and validated. Xmip
does not wait for the Journey unless a Composite interaction requires a
Process-produced response. The Receive Port produces the logical response
Message; the originating Receive Location transports the response Stream back
to the caller.

**Send side.** A Send Location may receive a response Stream. The Send Port
accepts it and creates the response Message, which continues **the same
Journey**:

```text
Send Location receives the physical response Stream
Send Port accepts it and creates the response Message
Response Message continues the same Journey
```

A response ingress is an ingress. It is identified, authenticated, authorized
and audited before acceptance, exactly as a Receive Location is.

There is a runtime consequence for responding protocols: everything up to
Validation must complete **inside** the receive call. It cannot be deferred to
a worker without losing the ability to answer.

## 12. Journey state

A Journey is Active, Waiting, Suspended, Recovering, Completed, Failed or
Dismissed. Completed, Failed and Dismissed are terminal. Suspended and
Recovering are the operator-recoverable path. ADR-0013 clause 7 records the
vocabulary, and the code is `JourneyState` in `xmip-core-journey`
(`module/foundation/journey`); this document does not repeat the enum, which
drifted from the crate once already.

Earlier drafts named a different set — Created, Running, Paused, Waiting, Dead,
Completed, Dismissed. The mapping, and what happened to the two that had no
equivalent, is in section 23.

**A Failed Journey** cannot continue automatically. Causes include Transport
Handler, Content Handler, Contract, Process, Send Location, response and
technical failure. Authentication or authorization can cause it **only once the
Journey exists**; failures during pre-Publication acceptance are audited receive
failures.

A Failed Journey retains its Message, Stream, Receive Port, Receive Location,
failure stage, failure reason and the audit and retention references needed to
diagnose it. The state answers *where* the Journey is; the cause answers *why*.

**A failed Journey does not send its Message to the Dead Message Queue.** If a
Message matched three Subscriptions and one Journey failed, the Message *was*
routed. Only a Message matching zero Subscriptions is undeliverable.

## 13. Journey control

Commands operating on the same Journey:

```text
Start   Pause   Continue   Retry   Stop   Dismiss
```

**Retry** resumes from the failed audited stage of the same Journey. Xmip may
retry automatically per resilience policy; an authorized operator may retry
after automatic retries are exhausted and the underlying fault is fixed.
Successful prior actions are not repeated unnecessarily.

**Stop** prevents further execution. The resulting state depends on reason and
policy.

**Dismiss** intentionally terminates a Journey without deleting its history,
Messages, Streams, retention or audit.

Built 2026-10-04 for a Journey that failed at its Send Port (section 10):
Retry and Dismiss are Operator acts on it, by its identifier, through the
node's orders, audited and gated by role (`xmip_operate.h` section 16).
Since 2026-10-05 each is decided on the Journey as read under its claim —
refused in words where another writer moved it after it was first read —
and every Journey that failed at a Send Port is listed at the Port's scope,
a page at a time from Xmip Storage, with the two acts on each (section 10).
Since 2026-10-12 an operator on another machine takes them over the node's
operate listener (ADR-0067; ADR-0014, amendment 2026-10-12): gRPC inside
Xmip's mutual TLS, the act the certificate's subject's, admitted by the role
the node's `[operate]` grants and applied by the same one apply as an order
(`applied::apply`). Since 2026-10-13 an operator on the node's own machine
takes them over the same listener's local endpoint — a named pipe on
Windows, a Unix domain socket elsewhere — the act the user's the operating
system proves (ADR-0014, amendment 2026-10-13): every .NET surface operates
a node over gRPC, here and elsewhere alike. Start, Pause, Continue and Stop on one Journey are not
built.

## 14. Replay

**Replay is not a Journey command and is not Retry.** It creates a *new*
Journey from a selected historical source:

```text
a historical Receive Location event
a historical Receive Port event or Publication
a historical Journey starting point
```

Replay uses the Message, corresponding Stream, artifact context and
configuration identity retained at the audited source. The new Journey records
lineage to that source and to the original Journey where one exists.

- Replay what entered a Receive Location during a period.
- Replay a Message as it entered a Receive Port, before its actions and
  Publication.
- Replay a whole Journey from its original starting point.

**The historical source is unchanged, and the Replay is itself audited.**

Replay and detailed inspection are possible only while the required retained or
archived evidence can be restored.

## 15. Resilience

`xmip-core-resilience` owns the guards on an attempt (ADR-0048); its README
names them ([built, not in the assembled service](estate-map.md#resilience-guards):
the Event forwarder runs them, and a Message send does not). A send has its
Send Port's retry
([built, in the assembled service](estate-map.md#send-port-retry)); the guards an
operator configures on a Send Port Group, Send Port and Send Location, and
a timeout that interrupts an attempt, are
[decided, not built](estate-map.md#send-resilience) (ADR-0048, amendments
2026-10-06).

**Handlers report Success, Retryable Failure or Non-retryable Failure. They do
not own retry loops.** A handler with its own retry loop cannot be governed by
policy, and two of them compound multiplicatively.

Once configured retries are exhausted the Journey fails, and an operator may
retry later. The same primitives are to supervise Host Services, per
ADR-0018.

### Delivery semantics

Retry raises the question retry always raises, and it needs answering here
rather than per transport.

**Xmip is exactly-once where the endpoint permits it, and at-least-once
everywhere else.** Which one applies is a property of the endpoint, not a
setting, and Xmip does not offer a switch that promises otherwise.

Internally, exactly-once holds: a claim through Xmip Storage (section 3)
means one node owns a unit of work, and every hand-on is one atomic write;
execution checkpoints in `xmip-core-persist` mean a recovered Journey resumes
rather than restarts, and Messages are immutable so a resumed Journey cannot
half-produce one.

Externally it depends on what the far side supports. A queue with
acknowledgment and a deduplication window can be delivered to exactly once. An
FTP `PUT` cannot: the connection may drop after the bytes land and before the
server answers, and no amount of Xmip correctness tells the two cases apart.

The rule that follows, and the reason this is stated at all:

> **Where Xmip cannot guarantee exactly-once, it guarantees at-least-once and
> says so.** It never silently degrades to at-most-once by treating an
> unacknowledged send as delivered.

A Journey is marked delivered only after the far end confirms. Where the far
end can deduplicate, the key Xmip hands it is the **Journey id**, not the
Message id (the owner, 2026-10-01): a Message matched by two Subscriptions to
one endpoint is two deliveries, and a retry of one Journey is the same
delivery. A retry waiting for its backoff holds no thread, no claim and no
place; its due time is in the Ledger, at its place in its queue (section
10).

At-most-once — losing a Message to avoid duplicating it — is never a default. An
integration platform that quietly drops work is worse than one that occasionally
repeats it, because a duplicate is visible and a loss is not.

The effective guarantee per Send Location is derivable from its transport, and
belongs in the operations reporting of `observability-model.md`: an operator
should be able to ask which of their endpoints can duplicate, and get a list
rather than an opinion.

Recovered from the `_origins` design export, 2026-08-26, where the
exactly-once/at-least-once split was stated and had been carried nowhere since.

## 16. Audit, retention and archiving

**Audit** is the authoritative record of significant Xmip interactions and
boundaries. Audited by default:

```text
Receive Location    Receive Port          Receive Port actions
Publication         Routing               Work Process entry and result
Assignment          Transformation        Send Port Group
Send Port           Send Location         Response ingress
Authentication      Authorization         Automatic Retry result
Operator Retry      Replay                Dismissal
Success             Failure
```

**Entry and outcome are audited; execution internals are not.** Custom code and
Extensions may emit additional audit events at any meaningful stage.

**An audit record is written through Xmip Storage** (section 3), to the
runtime database first, and the audit keeper moves it to the administration
database, where it is kept over time — on every backend (the owner,
2026-10-01: *RocksDB is the first storage for audit records, then transferred
to SQLite, RocksDB for speed, SQLite for persistence over time*). The
operating system's log stays the fallback when it cannot be written
(ADR-0062, amendment 2026-10-01;
[decided, not built](estate-map.md#audit-through-storage)). Every program writes its
records to its `audit.toml` today
([built, in the assembled service](estate-map.md#program-audit)).

**Retention** (`xmip-core-retain`) holds Messages, Streams or durable Stream
references, lineage, Journey execution positions, artifact and Handler
outcomes; Audit no longer needs it to show what it audited (ADR-0070,
amendment 2026-10-09). Policy may apply by Receive Location, Receive
Port, Publication, Journey, Message, Stream, Event, Audit category or retention
category, using time, size, count, state or hold rules.

**Archiving** (`xmip-core-archive`) moves, represents, stores and restores
retained history. Targets may include CSV, SQL, JSON, Parquet, XML, Avro, file
systems, object stores and custom providers. Both are
[built, not in the assembled service](estate-map.md#retention-archiving): the
Playground drives them, a node does not.

Audit comes first conceptually. An audit record spells out the Message it
audits, as it was, and its Streams' bytes with their digests, so the copy is
verified when read and the audit needs nothing else kept (ADR-0070). The
Message travels in the record in its one binary form (`Message::record`). The
digest is SHA-256, taken by the writer from the bytes as they pass once
(`ledger::write_stream`) and kept in the Stream's own record, its one home;
the audit keeper, moving a record to the audit database, copies the
chunks of every Stream the Message's Sections are over beside it, one at a
time, each unsynced and made durable by the record's own synced write as a
receive cycle's chunks are by its Publication (section 3), and a shared
Stream once — the `audit_stream_chunk` table, by the
record's identifier, the Stream's and their number — and writes, with the
record, each Stream's row of the `audit_stream` table: its length, its chunks,
its digest and when it was written, in the clear, found by the Stream. A read of a copy is held to both, and one that does not match is refused in
words (`persist::storage::ChunkReader::audited`). It is part of the audit
through Xmip Storage above,
[decided, not built](estate-map.md#audit-through-storage): nothing runs the
keeper outside tests, and no surface reads a kept record. The record's body —
its record and the Message in full — is kept as a Stream is, in chunks of
the runtime's chunk in the `audit_body_chunk` table beside its row, its
length, chunks and digest in the row, read back a chunk at a time and held to
them (ADR-0070, amendment 2026-10-10: *The audit body has to be like the
stream, in chunks*).

**The audit log is a chain, one per writer** (ADR-0070 clause 5, amended
2026-10-10): every record carries its number in its writer's chain — the
node's, or the program's where no node writes it — and the SHA-256 digest of
the record before it there, and its own over its canonical form. The file
sink forms a program's chain as it appends to `audit.toml`; the audit keeper
forms a node's as it keeps each record, the `audit` table laying out the
writer, the number and both digests. One walk says the first place a chain
breaks — a record deleted, changed or out of order — or that it is whole:
`xmip audit --verify`, `Get-XmipAudit -Verify` and the Audit view for the
file, `ledger::verify_audit_chain` for Xmip Storage. A record whose write to
`audit.toml` was interrupted is kept as written: the next append seals it
with a comment line and a blank line before its own record, so it is in no
chain and the next record continues from the last complete one, and a
verification reports it per file apart from the chain verdict — FAILED once
sealed, UNFINISHED while it is the file's end (built 2026-10-12, decided
by the owner the same day, ADR-0070). Retention
also supports Replay.

## 17. Eventing

`xmip-core-event` is separate from internal Routing, and the distinction is one
question each:

> **Routing** — where should this Message continue?
> **Eventing** — who is allowed to know that an action completed, and what may
> they receive?

Every completed Receive, Process and Send action produces a signalable Event
for every outcome: success, failure, rejection, waiting, pause, timeout,
exhausted retries, failure or dismissal where applicable.

An Event carries event identity and type, timestamp, action and outcome,
Journey reference where a Journey exists, Message and Stream references,
Endpoint, Module and Artifact, Party context, and safe diagnostic information.
For large Messages and Transfer workloads it carries metadata and durable
references rather than copying the Stream.

Event receivers are identified, authenticated and authorized, preferably as
Parties communicating through Endpoints. Authorization controls which Event
types, Messages, Streams, Journeys and metadata a receiver may access. **Event
delivery and its security outcome are audited.**

ADR-0065 decides how a receiver subscribes, from any language: one Event model
and one subscription rule in `xmip-core-event`, reached in process through
`xmip_operate.h` section 11 and over the wire in the Event wire form on Xmip's own
HTTP, Kafka and AMQP transports, at least once. An Event reaches an in-process
subscriber within about a millisecond of being published. Any node is the
cluster's door (ADR-0065, amendment 2026-10-02): a subscriber on any node hears
the matching Events of every node, each pushed one hop over the sync listener
(ADR-0067) and Xmip's mutual TLS, only where a subscriber's filter wants it; a
member that cannot be reached is said to be unheard, never silently missing.

## 18. Parties and Endpoints

A **Party** is an organization, stakeholder, system, service or other entity
Xmip interacts with. `xmip-core-party` connects Parties to identities,
permissions, contacts, agreements and Endpoints, and holds the identities a
Party is recognized by on receive and the ones Xmip presents on send. ADR-0019.

**Endpoint** is the public, non-technical collective term for Receive Port,
Receive Location, Send Port Group, Send Port and Send Location.

> Artifacts are Xmip's precise internal model. Endpoints are Xmip's public
> operational model.

Internally they remain distinct Artifacts with precise responsibilities;
externally they are observed, reported and administered as Endpoints.

## 19. The security path

```text
xmip-core-identify      establishes the claimed identity
xmip-core-authenticate  proves it
xmip-core-authorize     determines what the proven identity may do
xmip-core-party         provides stakeholder context and connects identities,
                        permissions and Endpoints
```

**The first three depend on `xmip-core` and never on `xmip-core-party`.** The
gates answer with a `PartyId` and the Party is resolved elsewhere, so no gate
can read a Party's identities, associations or permissions even by accident.
The identity vocabulary they share — mechanism, layer, class, assurance,
purpose — therefore lives in `xmip-core` rather than with the Party that holds
identities configured under it.

This is not packaging tidiness. Proving a credential and knowing whose it is are
different questions, and a gate able to see the answer to the second would
eventually decide something with it. ADR-0019 clause 4 says the same in
prose: **a Party is a shortcut to an Identity, not a permission.**

**What the assembled service sets up from configuration** (2026-10-19;
ADR-0019 and ADR-0033, amendments 2026-10-19). A tcp Receive Location
saying `tls = true` terminates TLS with the node's `[provision.receive]`
certificate and verifies a client's against the anchors given there, before
a byte of content is read; the transport writes what the handshake proved;
the first gate presents the certificate's subject as `mutual-tls`, and
`mutual-tls` records the transport's proof; the Parties of `[[parties]]`
resolve the verified value; the Location's `accept` closes the set —
mechanisms and Parties — at authentication; and the `location` policy
admits, at each Receive Location the node starts, what its `accept` takes.
An authenticator that needs a credential store, and a policy that speaks
for a Send Location, are not set up by configuration yet (open problem 33).

All access through Xmip follows this path. **Development uses permissive
configuration; it does not bypass security.** A developer installation
bootstraps four identities:

```text
Developer   Me   Myself   I
```

and two Parties:

```text
Nice     Me
Greedy   Myself, I
```

They exist to make development immediately usable. Permissions stay
configurable, and every other environment requires precise identification,
authentication, authorization, Party and Endpoint configuration.

> Environment profiles change policy, never the security architecture.

Secrets and certificates are referenced through providers and never embedded in
configuration, logs, retention or audit. Xmip supports ACME-compatible
certificate provisioning and renewal
([built, not in the assembled service](estate-map.md#certificate-provisioning)). **All access results are audited without
recording secret values.**

## 20. Artifacts, Content, Contract and Configuration

**Artifacts** are configured objects that compose Modules:

```text
Receive Port   Receive Location   Work Process   Assignment
Transformation   Send Port   Send Port Group   Send Location
```

**Content** describes how a Message is represented and how it can be
identified, partially deserialized, serialized, promoted and demoted: XML,
JSON, CSV, EDI, HL7, FHIR, text, binary, custom. **Content is independent of
Transport** — the same XML Message may arrive by FILE, FTP, HTTP or MQ.

**A Contract** is executable validation and structural knowledge applied to a
Message:

```text
Schema     XML Schema, JSON Schema, RegEx, Avro, Protobuf
Standard   EDI, HL7, FHIR and other standardized validation systems
Custom     stakeholder, project and Party contracts, and contracts derived
           from standard or other custom contracts
```

Contract derivation is a design-time and build-time concern using the
underlying contract technology — XML Schema import and restriction, JSON Schema
`$ref`, EDI implementation guides, HL7 conformance profiles, FHIR profiles,
custom validation code. **Runtime TOML selects a completed, versioned Contract;
runtime configuration never constructs Contract inheritance.**

**Configuration** is TOML and composes already-implemented, versioned Modules
and Artifacts. A Receive Location selects, by reference: Transport Handler,
Content Handler, Contract, accepted identities and mechanisms, authorization,
interaction type, response behavior, and audit and retention policy.

### Where the runtime's settings are configured

Six things the runtime needs had no place in configuration: Receive Ports,
a Receive Location's interaction type and processing depth, the Send Port's
policy, the order key and a failure policy, Parties on a node,
and retention and audit policy per Port and Location. The owner,
2026-10-01: *sort it and present a solution*. The assistant presented one;
the owner: *If there are no questions, write it down.* Two points were then
asked one at a time, and the owner answered each *Yes*: interaction type,
and processing depth with it, sit on the Receive Location, as section 6
says; and audit policy works like retention, a node default overridable per
Port and per Location.

In an Xmip Application's document:

```toml
[[receive_ports]]
name = "Invoices"

[[receive_locations]]
name         = "InvoicesHttp"
receive_port = "Invoices"         # a Location without a Port is refused
interaction  = "data-transfer"    # composite | data-transfer | batch-load
depth        = "light"            # transfer | light | context

[[send_ports]]
name            = "ErpOut"
send_locations  = ["ErpPrimary", "ErpBackup"]       # tried in order
retry           = { attempts = 3, backoff = "5s" }  # on the active Location
failover        = "next"          # next | none
correlation_set = "PerParty"      # one at a time per key, as the set says
```

In the cluster's `xmip.toml`, once for the whole cluster (ADR-0024 and
ADR-0066, amendments 2026-10-22):

```toml
[[correlation_sets]]
name       = "PerParty"
keys       = ["context:Party"]   # receive-location | receive-port | work-process |
                                 # send-port | context:<name>, in order
on_failure = "block"            # block where it says nothing | skip
```

- **A Receive Port** is named, and keeps Message creation and Publication
  (section 6). Each Receive Location names its `receive_port`; a Location
  without one is refused.
- **A Receive Location** states its `interaction`, which decides when the
  sender is acknowledged (section 5), and its `depth`, which decides how far
  the receive gates read (section 7).
- **A Send Port** names its `send_locations`, tried in order; `retry`
  applies to the active Location; `failover` is `next` or `none`
  (section 10). It may name a `correlation_set`: its Journeys pass it one
  at a time per key (section 3, *Sequences*).
- **A correlation set** is declared once for the cluster and named at a point
  — a Receive Location, a Receive Port, a Work Process or a Send Port — by
  `correlation_set`. A Receive Location that names none goes one Stream at a
  time, keyed by its own name. A set not declared, declared twice, with no key
  or with a key that is no key word is refused at validation and as a node
  starts. The Send Port's `execution_style`, `order_key` and `on_failure`
  were deleted for it on 2026-10-22.

In a node's configuration:

```toml
[[parties]]
id         = "..."                # a UUIDv7, written once with the Party
name       = "Supplier"
identities = [                    # ADR-0019, amendment 2026-10-20
  { mechanism = "mutual-tls", purpose = "receive", value = "..." },
]

[receive_locations.accept]
party = ["Supplier"]

[retention]
default = "30d"                   # overridable per Port

[audit]
default = "..."                   # overridable per Port and per Location
```

- **Parties** are named with their identities (ADR-0019), so a Receive
  Location's accepted Parties read as names. `[[parties]]` is read since
  2026-10-13 (`configure::party`; ADR-0028, amendment 2026-10-13), and a
  Location's `accept.party` since 2026-10-19: a verified identity resolves
  to the Party holding it, and a Location naming Parties refuses at
  authentication one that resolves to another or to none (ADR-0019,
  amendment 2026-10-19). A name no `[[parties]]` declares is a problem the
  node's binding reports.
- **Retention** has a node default, overridable per Port (section 16).
- **Audit policy follows retention**: a node default, overridable per
  Receive or Send Port and per Location (section 16). The policy's words are
  the audit capability's.

Recorded in ADR-0031, amendment 2026-10-01, the configuration's record.

### Prepare, Contract, Promote, Transform and Demote at both levels

Decided by the owner, 2026-10-05, weighed against BizTalk, whose Pipeline
Components are Xmip's Preparation Steps and whose Maps are its
Transformations: *one want to be able to perform all these steps on the
Port & Location.* Each of the Receive Port, Receive Location, Send Port and
Send Location may configure Prepare, a Contract and Transform, the receive
pair Promote and the send pair Demote, every one optional, so a designer
places each where it belongs for the case at hand. Receive runs the
Location, then the Port; send the Port, then the Location; Preparation
Steps work on the Stream at both levels (section 8).

**Validation is the artifact's choice, not the Contract's.** A Contract may
serve only to deserialize and promote. Where a receive artifact names one,
it validates unless it says `validate = false`; where a send artifact names
one, it validates only where it says `validate = true`. The designer writes
the same defaults. [Decided, not built](estate-map.md#arrival-validation): a node
refuses a Location naming a Contract, and reads none of these keys yet.

```toml
[[receive_ports]]
name     = "Orders"
contract = "xmip-core-contract-json-schema"     # the Port's one format
contract_settings = { reference = "schemas/order.json" }
promote  = { OrderNumber = "order.number" }     # Content Selectors

[[receive_locations]]
name         = "OrdersEdi"
receive_port = "Orders"
contract     = "xmip-core-contract-edifact"     # the Party's format
validate     = false                            # receive: true unless said
transform    = "EdifactOrderToOrder"            # compiled at design time

[[receive_locations.prepare]]                   # in order
step     = "xmip-core-prepare-decompress"
settings = { format = "gzip" }

[[send_ports]]
name      = "ErpOut"
transform = "OrderToErpOrder"
demote    = { OrderNumber = "order.number" }

[[send_locations]]
name     = "ErpPrimary"
contract = "xmip-core-contract-xml-schema"
validate = true                                 # send: off unless said
demote   = { OrderNumber = "headers['X-Order']" }
```

Startup checks the chain — what a Location hands its Port, a
Transformation's output, what a Send Port hands its Send Location — against
the next Contract named, and refuses a mismatch; and refuses a
Transformation, validation or promotion that needs materialized content on
a Receive Location at `transfer` or `light` depth. Recorded in ADR-0031,
amendment 2026-10-05; the key names are the assistant's drafting. Not
built.

### Validation gates

The `Validation` step in section 5 is the receive gate. It is not the only
one. Validation belongs at every meaningful boundary where Xmip can decide
whether a Message may continue:

```text
receive / Stream boundary          deserialize boundary
transform boundary                 Process input
Process output                     pre-serialization boundary
outgoing representation boundary   (optional)
```

Each is a gate: **a Message failing a required gate must not continue through
that passage as if it were valid**, and the outcome is audited. Validation is
not required after every runtime activity — only where a boundary is crossed.

**Promotion and Publication are not validation gates.** Promotion extracts
values into context; Publication offers a Message for Routing. Neither asserts
anything about correctness, and treating them as gates forces work Xmip may
not need to do.

What can be checked depends on what is knowable. At the Stream boundary Xmip
may not know the internal structure at all, and validation uses envelope and
identity only — sender and service identity, certificate, source address,
Receive Location and Port, content type, subject, file name and attributes,
headers, metadata. After deserialization it may check structure, required
fields, data types, allowed values, schema rules and domain constraints.

> **Structured validation must happen before serialization.** Xmip cannot
> validate serialized bytes as structured message data.

After serialization only representation checks remain: that a serialized form
exists, that content type and encoding are assigned, that destination contract
metadata and send identity requirements are present. Those are outgoing
representation checks, and calling them validation is how a system ends up
believing it validated something it did not.

Every validation gate participates in audit, carrying correlation and
sub-correlation references, the event name and purpose, node, address and
service identity, start and end time, and outcome. A failure records its reason
as metadata. **Validation logs and traces never store payloads** — where the
Message itself must be kept, that is retention's job, per section 16.

## 21. Definition and Instance

Every configurable Xmip object exists twice, and the two must not be confused.

A **Definition** is configured intent, declared in TOML. It describes what
should happen and references the module capability needed to realize it. A
Definition does not execute.

An **Instance** is the runtime execution of a Definition, created when the
kernel binds it to loaded module code satisfying the required contracts:

```text
Definition + Module Instance + Validated Contracts + Runtime Context
    = Instance
```

An Instance is active, not a passive record. It is responsible for starting,
executing its capability, ending successfully or unsuccessfully, and reporting
its due audit — at start including why it started, during execution when
something meaningful happens, and at completion with the outcome.

**"Artifact" is a collective noun for prose, not a name in code.** This
document says "Artifacts" when it means all of them at once. Type names, TOML
keys and log fields use the concrete concept: `ReceivePortDefinition`,
`ProcessInstance`, `SubscriptionDefinition`. There is no `ArtifactDefinition`
type, and no AD/AI/MD/MI acronyms outside a diagram.

### Identity survives implementation

**Identity belongs to the Definition and its runtime lineage, not to the
module implementation or the transport technology.**

```text
OrdersInbound
    version 1 -> xmip-core-transport-http
    version 2 -> xmip-core-transport-mqtt
```

`OrdersInbound` is the same Receive Location throughout. Newer Instances use
the new module after restart or redeployment. Lineage, audit, retention and
deployment history must therefore never be anchored to the concrete
implementation technology — that is precisely what makes a transport
replaceable.

### Startup

This is the estate's one account of startup; `module-model.md` section 8 and
`terminology.md` point here. ADR-0018 clause 4 decided the nine phases and
which of the two services owns each:

```text
Xmip Service
 1. read-configuration       the node's configuration, whole
 2. build-execution-tree     the Definitions this node is supposed to run
 3. validate-startup         the gate: fail here, before anything starts
 4. plan-host-services       which Host Services, with what character and Modules
 5. start-host-services      register what is missing, start in configured order
Xmip Host Service, each within itself
 6. load-modules             ABI-verified per ADR-0012, eager or delayed per ADR-0025
 7. register-capabilities    Handlers and Extensions into its registries
 8. verify-extensions        verified, not loaded
 9. accept-work              Receive Locations poll, Send Locations ready,
                             Work Processes runnable
```

Phase 3 validates every Definition against the capability contracts it
requires and every reference between Instances, so a configuration error is a
startup failure, not a first-message failure: a Receive Location naming a Send
Port that does not exist is refused before a Stream ever arrives. The phases
are `StartupPhase` in `xmip-core-runtime`
(`module/platform/runtime/src/service.rs`), and `running::Running::start`
runs them (`module/platform/runtime/src/running.rs`): it loads each Module a
node's configuration names once, from what the program starting the node
linked or from its library, and serves every Receive Location until the node
stops.

## 22. The Work Process

An **Work Process** is a Definition started by a Subscription. It is not an
operating-system process, and it is not a human workflow unless that workflow
is represented by Xmip configuration and runtime state.

A Process may validate, promote, assign, transform, execute Extensions, use
other Xmip concepts, publish, send requests, wait for responses, resume,
time out, complete, fail or cancel. **It does not receive external Streams
directly and does not deliver to external targets directly** — those are
Receive and Send concerns.

Assignment belongs to a Process alone. Transformation may happen in a Receive
Location or Port, a Process or a Send Port or Location. Section 10 states the same rule from the Send
side.

### Process State belongs to the cluster

**A Process Instance must not use thread, Host Service or node memory as its
source of truth.** Its state is persisted through cluster persistence and
holds what is needed to continue after a wait, a timeout, a host restart, a
node restart, a node failure, a failover or a recovery.

> Execution ownership may move between valid nodes. The state does not move,
> because it already belongs to the cluster.

That is the whole reason a waiting Process is not a long-running thread. A
Process waiting three days for a response occupies no thread and survives
every restart in between.

**The cluster persistence is the Ledger** (section 3), behind Xmip Storage
(the owner, 2026-10-01, validated part by part with the assistant). A pool
for the Work Process step (section 3) claims a Journey destined for one
Work Process. Its state is in the Ledger, never in thread memory, and is
checkpointed at every turn. Waiting releases its thread; a Message of its key
in a correlation set resumes it on any capable node. Assignment belongs to a Work Process alone.
New content is a new Stream, written in chunks, and a new Message
generation. Validation gates stand at its input and output (section 20).
Publishing back goes through routing again, with the chain recorded
(section 9). A Composite response returns through the Receive Port to the
Receive Location holding the call (section 11). The end of every execution
scope is audited with its outcome.

**Built 2026-10-22** (ADR-0066, amendment 2026-10-22). The owner, 2026-10-22:
*I would like a Work Process to be designed in VS Code, but at the end of the
day it is a compiled piece executed when called upon.*

- **Designed, then compiled.** A Work Process is drawn in BPMN 2.0, the
  default design format (`xmip-core-process-bpmn`), in Xmip's own VS Code
  designer, and saved as standard BPMN XML with BPMN DI. It is compiled at
  design time to the one `process::Program` — a graph of typed steps, its
  flows resolved and its subprocesses laid flat — and generated as a Rust
  crate exporting it, built into a library: the Work Process unit, declared
  `capability = "work-process"`, `stages = ["process"]`, `offline = true`.
  A `[[work_processes]]` entry names its flow by `module` and `unit`. The
  node never reads a design.
- **Loaded through the C ABI** (`xmip_module.h` section 13): `declared`, what
  the unit declares — its name, the correlation sets it follows, the names
  its decisions read — and `advance`, one turn. A unit compiled from a user's
  design ships apart from Xmip, so a change to a process never rebuilds the
  node.
- **A turn** takes the Instance as the Ledger holds it and one event — a
  Message of its key arrived, the work it asked for done or thrown, its time
  due — and answers the acts the runtime carries out: work on a Message (a
  unit's call, an Assignment, a split), Messages made one, a Message
  published back through routing, how it ended (`process::flow`).
- **The Work Process step** (`xmip-core-runtime`'s `work_step`) claims a
  Journey from its Work Process's queue, waits while its Stream does not head
  its sequences, finds its Instance through the Correlation table — or the
  one it starts — advances it, carries out its acts, and hands it all on in
  one write (`XmipStorage::turn`): the Journey, the new Messages, the
  Journeys published with their places, the Instance, its correlation keys
  set or let go, and, where a timer waits, the Journey kept at its place with
  its due time. An Instance is written only over the turn it was read at, so
  two nodes taking a turn of one Instance never both write; the later gives
  its claim back and takes the turn again from the Instance as it now is.
- **Nothing waits on a thread.** An Instance waiting for a Message is a
  record in the Process Instance table and its keys in the Correlation
  table; one waiting for a time is the due time of the Journey whose turn
  started the timer, taken up by a scan when it is due, on any node.
- **Correlate, Wait, Batch, Debatch.** A start or a receive step names the
  correlation set it takes Messages by: the start initializes it, a later
  step follows it, and the Messages of one key are handed to their Instance
  in the order the Ledger wrote them (section 3, *Sequences*). A Batch
  collects Messages of the key until it has its `most` or its `within` is due
  and makes them one Message, their Sections in order; a Debatch splits the
  current Message by a splitting unit and publishes each part.
- **Try and catch.** An error boundary event catches an error of its code
  thrown inside its task or subprocess — by a failed unit call, or an error
  end event — and leads on; one no scope catches fails the Instance. A timer
  boundary event interrupts its task or subprocess once due. Compensation is
  not built: the owner, 2026-10-22, *Compensation can mostly be handled with
  try/catch*.

**Decided, not built:** the `settings` a Work Process gives its unit; unit
calls through the standard units' registry (a node calls none yet, and a call
throws `no-unit`); a Journey published on one node woken on another at once
(open problem 46); a Send Location naming a correlation set; human tasks
(open problem 47).

### Stages

A **Stage** is a named phase inside a Process Instance. **Stages are not
required to be linear.** A Process may move forward, wait, resume, branch,
revisit earlier logic, or reach different outcomes depending on the messages,
timeouts and decisions it meets.

### Starting and resuming

> A Subscription decides when work **starts**.
> A correlation set decides when waiting work **resumes**.

A Subscription Instance may correlate an incoming Message to a waiting Process
Instance. Where the correlation and the wait condition both match, Xmip
resumes that Instance from persisted state. What that looks like from the
Message's side — one Instance handling many Messages over time, each still one
immutable Stream — is `module/core/capability/process/doc/process-instances.md`.

### Execution scope

```text
None   Transactional   BusinessProcess
```

`ExecutionScope` describes execution semantics and applies whether the work
happens inside a Process or in a publish/subscribe path. When a scope ends,
Xmip must produce an explicit outcome — a published Message, a sent Message,
completed work, a failure, or placement in the Dead Message Queue. **The end
of an execution scope is always audited.**

### Process outcome

```text
Completed   CompletedWithWarnings   Failed   Canceled   TimedOut   Abandoned
```

**How this relates to `JourneyState` — DRAFTED 2026-10-22, for the owner.** A
Process is one step inside a Journey rather than the Journey itself, so the two
vocabularies stay distinct. What is built: an Instance that ends `Completed`
leaves the Journey of its last turn `Completed`; one that ends `Failed` — an error
no scope caught — leaves it `Failed` with the code and why, kept in its Work
Process's queue for an operator's Retry or Dismiss. A Journey whose turn only
hands its Message to a waiting Instance is `Completed`; one whose turn starts a
timer is `Waiting` until it is due. `CompletedWithWarnings`, `Canceled`,
`TimedOut` and `Abandoned` are not produced yet.

## 23. Conflicts resolved

Four substantive disagreements existed between the four source documents and
the accepted ADRs. Recording them because each was load-bearing, and because a
merge that hides them is worse than four documents that disagree visibly.

**1. Who creates the Message, and when a Journey begins.**
v1.0 said every Stream reaching a Receive Location creates a Journey, Message
and Stream, "even when authentication, authorization, handling, validation or
routing later fails". Baseline-Current reassigned this: the Receive Location
receives, the Receive **Port** creates the Message, and Publication starts the
Journey. ADR-0013 went further: Message creation follows transport
authorization, and Journey creation follows successful Validation.

*Resolved:* Baseline-Current and ADR-0013, which agree. v1.0's rule would mean
Xmip creates a Journey for every unauthenticated connection attempt, which is
both a liability and a denial-of-service surface. Section 4 states the result.

**2. Journey states — two different enums.**
v1.0 named seven operational states. The root's `src/journey_model.rs`
implemented six when this conflict was written; it merged into
`xmip-core-journey` on 2026-08-27 (`doc/planning/allocation.toml`), which
implements seven, and ADR-0013 clause 7 records the code.

*Resolved:* the code. The mapping, and the two that had no equivalent:

| v1.0 | Now | |
| --- | --- | --- |
| Created | — | a Journey exists only after Validation, so there is nothing to be Created in |
| Running | `Active` | |
| Paused | `Suspended` | operator-initiated |
| Waiting | `Waiting` | |
| Dead | `Failed` | |
| Completed | `Completed` | |
| Dismissed | `Dismissed` | added 2026-08-26; see below |
| — | `Recovering` | a Retry in flight, which v1.0 could not express |

`Dismissed` is the loss, and it is real: Dismiss is a command in section 13 with
no state to land in, so a dismissed Journey is currently indistinguishable from
one that simply Failed. Either `JourneyState` gains a `Dismissed` terminal
variant, or dismissal is recorded outside the state as an audited disposition.
**Not decided here — it needs a ruling and belongs in ADR-0013.**

***Resolved 2026-08-26: `JourneyState` gains a `Dismissed` terminal variant.***
The ruling and its reasoning are in the ADR-0013 amendment; `is_terminal()` now
covers `Completed`, `Failed` and `Dismissed`. What follows is the evidence that
decided it.

The `_origins` design export defines four runtime lanes — Receive, Process
(optional), Send and **Void** — with four valid flows:

```text
Receive → Send
Receive → Process → Send
Receive → Void
Receive → Process → Void
```

Void is a terminal lane for work that deliberately does not go out. It is
reached from both a processed and an unprocessed Message, and it is not the
failure path — failure is a separate concern in that model, as it is in this
one.

That is the earliest Xmip design, and it had somewhere for a Message to end
without delivery and without failure from the beginning. The distinction was
intended before it was lost, which made this a recovery rather than an
invention.

The lane vocabulary itself is not adopted: Receive, Process and Send are
capabilities in the current model, not lanes, and only Void named something the
model lacked.

**3. What happens when no Subscription matches.**
v1.0 and Baseline-Current both said the Journey becomes Dead with a Routing
cause. ADR-0013 says a Publication produces zero, one or N Journeys, so zero
matches means no Journey exists to become Dead, and the Message goes to the
Dead Message Queue.

*Resolved:* ADR-0013. Baseline-Current had already hedged toward it — "when no
Subscription matches *after a Journey has begun*" — which is a sentence written
by someone noticing the same problem.

**4. One ABI or one per Module.**
Baseline-Current proposed that each extensible Module owns its own ABI rather
than relying on one broad `xmip-abi`. ADR-0012 decided one normative C ABI,
`xmip_module.h`, in `xmip-core-abi`.

*Resolved:* ADR-0012. Per-module ABIs multiply the version-negotiation surface
by the number of Modules, and the compatibility matrix by its square.

**5. Whether the interchange identifier is stable across message generations.**
Not from the four specifications — from the ADRs and the retired glossary, and
found while adding the Actor model.

ADR-0008 says Assignment and Transformation create "a new message form with a
new messageId and the **same** interchangeId". `architecture/glossary.md` said
the opposite: a **child** Interchange with a **new** interchange id, referencing
its parent, so that a Message carries a chain `I1 -> I2 -> I3`.

*Resolved:* ADR-0008, which is Accepted and later. The interchange identifier is
**stable** across every generation descended from one reception. It is a
correlation identifier, not a lineage chain, and generation is tracked by
message id.

That leaves a naming question rather than a modeling one, since "Interchange"
is retired vocabulary. A stable identifier over one reception and all its
descendants is what ADR-0013 calls the **Publication** — one event, one
identity, immutable. Whether the two are the same identifier is undecided and
recorded in `terminology.md`.

Two further differences were vocabulary rather than substance. **Tracking** is
now `xmip-core-audit` for the authoritative record and `xmip-core-retain` for
what it shows — the split survives, the name did not. All Module names in the
source documents predate ADR-0011 and are `xmip-core-*` here.

### From the pre-ADR-0020 architecture documents

Six more disagreements surfaced when those 25 documents were read against each
other and against this one. Four were ruled; two were defects.

**6. Whether "Artifact" is a legal umbrella term.**
`artifact-model.md` mandated `ArtifactDefinition` / `ArtifactInstance` and an
AD/AI/MD/MI acronym convention. `definition-instance-model.md` explicitly
forbade it — *"Xmip shall not use a generic parent term such as Artifact"*.

*Resolved:* by scope rather than by winner. Artifact is a collective noun in
prose and diagrams; code, TOML keys and log fields use the concrete concept.
Section 21 states the rule. Both documents were half right: a document needs a
word for "all of them", and a log field needs to say which one.

**7. Send retry order.**
Section 10 retries the active Send Location and then fails over.
`xmip-send.md` moved to the next Send Location on any error and retried the
whole ordered list once all had failed.

*Resolved:* section 10. Retry the location, then fail over. Failover-first
sends every message through the backup the moment the primary is merely slow,
which converts a latency problem into a routing change and hides the fault.
Endpoint affinity is worth more than shaving one attempt, and a transient blip
is the common case.

**8. Whether one Message may be published more than once.**
Section 9 calls a Publication *"one event, one identity, immutable"*.
`message-runtime-context.md` published a Message repeatedly, each time with
richer context after deserialization, transformation or promotion.

*Resolved:* both, without contradiction. **A re-publication is a new
Publication** — its own event, its own identity, its own immutable record,
carrying more context than the one before. The recursion lives in the sequence
of Publications, not inside any one of them, so *a Journey is a line, not a
tree* still holds. What remains to be named is the link from a Publication to
the one that caused it, which is the same identifier question as conflict 5.

**9. Process outcome versus Journey state.** `Xmip.Process.Outcome` has six
values, `JourneyState` has six, they share two names, and no document states
the relationship.

*Open, deliberately.* The Process model reached this document only now, and a
mapping invented at the same time as the model it maps would be a guess
wearing a table. A Process is one step inside a Journey rather than the Journey
itself, which argues for two vocabularies and an explicit mapping — but that is
a ruling for ADR-0013, next to `Dismissed`, not a paragraph here.

**10. Whether SFTP belongs to the FTP family.** `handler-lineage.md` and
`protocol-landscape.md` derived SFTP from FTP; `handler-taxonomy.md` said it
does not.

*Resolved as a defect in the first two.* SFTP is the SSH File Transfer
Protocol. It shares a purpose with FTP and nothing else — not the wire
protocol, not the port, not the security model, not the command set. FTPS is
FTP with TLS and does belong to the family. Grouping SFTP with FTP is the
error that leads to configuration screens with an "FTP mode" dropdown
containing something that is not FTP.

**11. Whether Node.js is a target module technology.** `artifact-model.md` and
`foundations.md` said explicitly not; `feature-folder-convention.md` listed it
among supported languages.

*Resolved as a defect in the third.* Node.js and JavaScript server solutions
are not a target module technology.

### Within this document

**12. Whether the work store is a node's or the cluster's.** Noted
2026-10-01. Section 3 said *a ToDo belongs to one node and is written only by
that node*, *an embedded store is per-node by definition*, and *work does not
move by itself*. Section 22 said *Process State belongs to the cluster*, its
state persisted *through cluster persistence*, and execution ownership *may
move between valid nodes*. Both could not hold: state in a store one node
writes cannot be continued by another node when that node fails.

*Resolved:* the cluster, by the owner, 2026-10-01: *There is nothing local
about either RocksDB or SQLite, they are cluster services running on one or
more nodes*, and *All DB records have to be central and clusterable, if one
node fails another one should be able to pick up*. The ToDo is renamed the
Ledger; every node reaches it through Xmip Storage, the nodes declaring the
Storage role, in front of a database server IT runs or, on a single machine,
an embedded Storage node; and work moves by a time-limited claim in that
database. Section 3 is rewritten accordingly; section 22 stands.

## 24. Governing principles

1. Streams are immutable. Messages and Journeys accumulate context and history;
   their content does not change without a new generation.
2. Receive Locations receive Streams; Receive Ports create Messages;
   Publication offers them; Routing decides where they go; Journeys record them.
3. Failures before Publication are audited receive failures, not Dead Journeys.
4. Transport, Content and Contract are independent concerns.
5. Every Publication is audited.
6. A Publication produces zero, one or N Journeys — one per matched
   Subscription. A Journey is a line, not a tree.
7. Zero matches means the Dead Message Queue, not a failed Journey.
8. Retry continues the same Journey from the failed audited stage.
9. Replay creates a new Journey from an audited historical source, unchanged.
10. Audit uses retention to inspect and replay retained Messages and Streams.
11. Every Xmip artifact is an Actor when it communicates, and every Message has
    one owning Actor at every stage. Actor semantics never erase artifact
    semantics.
12. A security role, an actor capability and a Party are three dimensions, and
    none of them is the others.
13. Xmip owns the public contracts; stakeholders own implementations.
14. Development may be permissive; production is hardened by policy. Neither
    bypasses the security path.
15. Xmip never parses content from an unauthorized sender.

## 25. Design goal

Xmip shall make every Journey understandable, auditable, retryable, replayable
and dismissible, from the first received Stream until completion or intentional
dismissal.

The operational question Xmip must always be able to answer is:

> Show me the Journey.
