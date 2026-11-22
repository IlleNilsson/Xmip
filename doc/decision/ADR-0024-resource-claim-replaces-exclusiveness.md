# ADR-0024: A claim at the endpoint, not a lease inside Xmip

- Status: Accepted
- Date: 2026-08-27
- Amended: 2026-09-26 — a file is claimed by an atomic rename
- Amended: 2026-10-01 — a Message is claimed through Xmip Storage
- Amended: 2026-10-13 — one winner for every Receive Location; the file
  family's claim extends to FTP, FTPS and SFTP
- Amended: 2026-10-19 — a listing claims no more than there is room for; a
  sent file not yet in place is its node's, and its node removes it as it
  starts
- Amended: 2026-10-20 — a file Send Location's address names a directory; a
  drop directory tells, and a file is finished when no writer holds it
- Amended: 2026-11-19 — an object store's read and delete hold to the
  version listed
- Amended: 2026-11-20 — an object store's object is won by one node's claim
  beside it
- Amended: 2026-11-22 — a claim names its node and that start of it, and a
  start lets go only of what its node's earlier starts left
- Supersedes: ADR-0017 (Exclusiveness)
- Related: ADR-0010 (contract and transport boundaries), ADR-0012 (the module boundary),
  ADR-0018 (amendment 2026-10-01: a Host Service claims Journeys through the
  Xmip Storage), ADR-0056 (amendment 2026-10-01: the Storage role)

## In brief

- Theme: What Xmip is at runtime
- Subject: A claim at the endpoint, not a lease inside Xmip
- Name: A claim at the endpoint
- Order: 7
- Concepts: Change notification, a drop directory told; Claim, claimable
  artifact; Exclusiveness, leases, renewal (retired); Journey claim
- Note: supersedes ADR-0017

`xmip-core-exclusiveness` is retired — the module, the repository, the four
scopes, the lease and its renewal. `ResourceClaim` in `xmip-core-transport`
replaces it, and it answers a question the lease could not: **a lease knew what
Xmip was doing; a claim knows what everyone is doing.** A file another process
holds open includes a producer still writing it, and no amount of Xmip-internal
bookkeeping sees that.

A Receive Location claims the individual artifact, never the location it polls.
Every Receive Location, whatever its protocol, has exactly one winner per
artifact: a listener because a sender reaches one node, a broker by its own
one-consumer delivery, the file family — file, FTP, FTPS, SFTP — by taking
the file's turn and renaming it, object stores and databases by their own
exclusive step, and a protocol with none, such as IMAP, through Xmip Storage
as a Message is claimed. Several nodes may poll one directory; the stability
check stays where the system cannot say whether a writer holds a file. A
drop directory tells the Location of a file as it lands, and its poll is a
recovery sweep (amendment 2026-10-20).

## Context

ADR-0017 answered "how does Xmip stop two nodes taking the same file" by
building a lease store: `ExclusiveScope`, `ExclusiveLease`, `Exclusiveness`, and
a repository to hold them.

It never finished the answer. Clause 8 put leases in `xmip-core-persist`, which
is per node — and a lease visible only in the holder's own store proves nothing
to anyone else. `ExclusiveScope::Cluster` was therefore declarable and
unservable, which open problem 18 recorded and left open with four options and
no decision.

Every one of those options was bad in the same way:

| option | why it fails |
|---|---|
| One node holds the cluster lease store | a single point of failure, and a shared write path for exactly the thing that must not have one |
| Consensus among nodes | correct, and a distributed-consensus implementation, which ADR-0017 spent its whole argument avoiding |
| An external store — consul, etcd, redis, zookeeper | Xmip depends on somebody else's cluster to answer a question about its own |
| Cluster scope is not offered | leaves FTP, SFTP and IMAP with nothing |

The mistake is upstream of the options. **Xmip was trying to keep a fact that
already had an owner.**

## Decision

### 1. `xmip-core-exclusiveness` is retired

The module, the repository, the four scopes, the lease and its renewal. All of
it.

### 2. `ResourceClaim` in `xmip-core-transport` replaces it

ADR-0017 clause 3b already specified the trait and it was never implemented. It
is the whole answer rather than a companion to one:

```rust
pub trait ResourceClaim: Send + Sync {
    fn is_available(&self, artifact: &Artifact) -> Result<bool>;
    fn claim(&self, artifact: &Artifact) -> Result<Claimed>;
    fn release(&self, claimed: Claimed) -> Result<()>;
}
```

**The endpoint is one thing however many nodes are asking.** A claim taken
there is cluster-wide without a lease, a store, or anything for Xmip to keep
consistent across nodes — because the shared write path is the Party's
storage rather than Xmip's, and it is already there:

| family | native claim |
| --- | --- |
| local file, SMB | share-mode open, mandatory on Windows, advisory on Unix |
| Azure Blob | a renewable blob lease |
| S3 | `PUT` with `If-None-Match: *` on a claim key |
| Google Cloud Storage | a generation precondition |
| POP3 | the session locks the maildrop |
| SQL | `SELECT … FOR UPDATE SKIP LOCKED` |

Every one is atomic and none is Xmip's to operate.

*For S3, Azure Blob and Google Cloud Storage, superseded by the amendment
of 2026-11-20: each claims by a claim object beside the object, written
only where none lies, and Azure Blob takes no lease.*

### 3. It answers a question the lease could not

A lease knew what Xmip was doing. **A claim knows what everyone is doing.** A
file another process has open includes a producer still writing it, and no
amount of Xmip-internal bookkeeping sees that. The mechanism that was supposed
to be the safety net was blind to the most common cause of a half-read file.

### 4. The artifact, not the location

Carried unchanged from ADR-0017 clause 3, because it was right. A file Receive
Location claims the individual file, never the directory it polls. Two nodes may
poll one directory at the same time and take different files; claiming the
directory is what leaves the second node with nothing to do.

### 5. Where a protocol has no claim, it says so

FTP, SFTP and IMAP have no locking. `NoNativeClaim` is that answer in the type
rather than three stubs written per transport, one of which eventually returns
something else.

They are **not** made safe by renaming the artifact at claim time — ADR-0017
clause 3c, and it still holds. That puts a second mechanism in the one place
nothing is supposed to move, to defend against a non-Xmip client polling the
same directory, which no mechanism defends against anyway.

What they need is a **stability check**: an artifact whose size and timestamp
are unchanged across two consecutive listings, or a producer that writes to a
temporary name and renames on completion.

*Superseded for FTP, FTPS and SFTP by the amendment of 2026-10-13, which
claims them by the turn and the rename; the stability check stays.*

### 6. Two nodes on a lockless protocol is a placement question

With no lease and no native claim, nothing stops two nodes polling the same
SFTP directory from both taking `order.edi`.

**That is answered by running one of them, not by locking.** It is a
configuration decision about where a Receive Location executes, and it belongs
with Host Services in ADR-0018 rather than in a coordination service. Xmip does
not need a distributed lock to express "this Receive Location runs here".

The shape of that placement is not decided by this record. What is decided is
that it is a placement question and not a locking one.

*Superseded for FTP, FTPS and SFTP by the amendment of 2026-10-13: several
receiving nodes may share one remote directory.*

### 7. The sequence, simplified

ADR-0017 clause 3a had five steps and an ordering argument about which of two
mechanisms to signal first. With one mechanism there is no ordering to get
wrong:

```text
1. Claim the artifact at the endpoint. Refused, move to the next artifact.
2. Process.
3. Consume: delete, rename or move, so it no longer matches the Receive
   Location's configuration and is never detected again.
```

Nothing moves at claim time. The artifact is read where it lies.

A node that dies mid-claim leaves nothing behind: the endpoint releases its own
claim on its own terms — a closed handle, an expired blob lease, a rolled-back
transaction — and the artifact is simply free again. That is the same property
lease expiry was invented to provide, obtained without inventing it.

## Consequences

- `xmip-core-exclusiveness` is removed from `architecture.toml`, from the root
  `Cargo.toml` features and dependencies, from `server-profile`, and from
  `.gitmodules` — it was mounted at `modules/platform/exclusiveness`. The
  repository is archived rather than deleted; ADR-0017 is part of the record.

  *The submodule was added to this list on 2026-08-29, two days late. The first
  four were done together and the estate still checked out a module the manifest
  said was retired, because retiring a repository and unmounting it are separate
  actions and only one of them was written down. A retirement that names every
  place but one is how the one becomes permanent.*
- `xmip-core-schedule` depended on `xmip-core-exclusiveness`. It depends on
  `xmip-core-transport` instead: a schedule that fires and finds the artifact
  already claimed moves on, which is the same behavior with nothing to
  coordinate.
- `Transport` gains `claims()`, defaulting to `None`. A listening socket or a
  broker topic has no artifact to claim and correctly answers nothing.
- Open problem 18 is closed. Not answered — **dissolved**. There is no
  cluster-scope lease to place because there is no lease.
- `RecoveryLease` in `xmip-core-persist` stops being the second of two lease
  types, since there is no longer a first. ADR-0017 clause 9 folded them the
  other way round; that folding is now unnecessary.
- **Journey recovery across nodes is left open, and this record does not close
  it.** `deployment-model.md` said the same Journey must never be recovered by
  two nodes at once and pointed at ADR-0017's cluster lease for the guarantee.
  Claiming an artifact settles arrivals and settles nothing here: a Journey
  mid-flight is Xmip's own state and has no endpoint to claim it at. It is the
  same problem as *work does not move by itself* — a Message in a store one
  node wrote was that node's work — under a second name, and it belongs with
  however that is eventually designed rather than with a lease reinstated for
  one case. *Closed by the amendment of 2026-10-01: a Message is claimed
  through Xmip Storage.*
- The acquisition queue, fairness and acquisition timeout of ADR-0017 clauses 13
  and 14 go too. Nothing queues for an artifact: a node that finds one claimed
  takes the next one, which is clause 4's point about not claiming the
  directory.

## Alternatives considered

**Keep exclusiveness for the lockless protocols only.** A coordination service,
a lease store and a repository, existing solely for FTP, SFTP and IMAP — three
protocols whose real problem is a half-written file, which a lease does not
solve. Clause 6 costs one configuration field.

**Keep `ExclusiveScope::Cluster` and refuse it at runtime.** Honest, and it
leaves a type that can express a request the system will always deny. A
vocabulary that names impossible things gets used to describe them.

## Amendment, 2026-09-26: a file is claimed by an atomic rename

Clause 2 claimed a local file by opening it with exclusive sharing and
holding the handle, and clause 5 rejected renaming at claim time; the
Suggested order and problem 23 said the opposite. Asked to settle it, the
owner, 2026-09-26, chose from two (the exclusive open, or an atomic rename):
**an atomic rename.** A node claims a file by renaming it, in one step, to a
name that says which node took it; whichever rename succeeds owns the file,
on a local disk and on a network share alike, where locks are unreliable.
Clauses 2 and 5 are superseded on this point.

What the rename costs, and so what it carries: a node that dies after the
rename leaves a claimed file behind. The claimed name records the node and
the time, and a node that starts, or the cluster, returns a claim whose
owner is gone to the inbox — a recovery the exclusive open never needed.
`transport/.src/claim.rs` and the file transport follow in phase C's first
slice.

*Built 2026-10-03.* An external review found the file transport listing and
opening files with no claim, so two nodes could take the same file and a
reader could take a producer's unfinished one. How the transport learns its
node, the owner chose the same day: *Option A* — the runtime gives every
transport its node's identity once, as it builds it, placed once in the
transport contract, not a node argument on every technology's constructor.
`transport::Configured::on_node` takes the node's location
(`transport::NodeLocation`, written by the runtime's one
`running::publication::location`). The file transport takes a file only
where clause 5's stability check holds — its length and modification time
unchanged since the listing before — and claims it by renaming it to
`<dropped name>.xmip-claim.<the node's location, percent-encoded>.<nanoseconds>`;
`Accepted` deletes the claimed file, `Refused` and `Failed` link it back
under its dropped name, never over a file dropped since. A node being built
returns every claim its own name records. One finding changed the
mechanism, not the decision: two renames of one file are not exclusive on
Windows, which renames through a handle opened on the file first, so two
nodes both succeed and the second moves the file from under the first. The
rename is therefore made holding the file's turn, `<dropped
name>.xmip-claim`, created only where it does not exist — the exclusive step
every file system offers alike, and the one the Essentials' claim already
used. A claim left by a node that is gone and does not start again is not
returned yet: the cluster's half of the recovery is open.

## Amendment, 2026-10-01: a Message is claimed through Xmip Storage

**Provenance.** The owner, 2026-10-01, validated part by part with the
assistant, and re-decided later the same day: *to have one or more Xmip Nodes
with role Storage would be a safety… Xmip could just do a round robin over
Xmip Nodes roled Storage*; *The storage node may or may not carry the SQL
storage, it is an IT-infrastructure question… How IT-infrastructure designs
their Database servers is their concern*; and, on a shared database server
IT runs, option A, *Go ahead*. Also *All DB records have to be
central and clusterable, if one node fails another one should be able to
pick up*; and on the split, *Now we are getting into failover and load
balancing which will be IT-infrastructure functionality, unless you think it
is easy to implement*. The owner recalled the mechanism as the old
exclusiveness; the word is this record's, a claim.

The Consequences left Journey recovery across nodes open, because a Journey
mid-flight is Xmip's own state and has no endpoint to claim it at. Every node
now reaches the Ledger through Xmip Storage, the nodes declaring the Storage
role, and behind them one database — a server IT runs, or one embedded
Storage node (`runtime-model.md` section 3). **A Message is claimed there**:
a conditional update — set the owner where the owner is empty or lapsed —
time-limited, renewed while the work runs. A dead node's claims lapse, and
another capable node claims and resumes from the last finished step.

**Why a time-limited claim, when this record retired leases.** The lease was
retired because it lived in per-node persistence, which proves nothing to
another node, and because an artifact already had an owner — the endpoint —
that knew more than Xmip did. Neither holds for a Journey. Its state has no
endpoint; the database behind Xmip Storage is the one place every node's
claim is decided, so a conditional update there is seen by all of them, as a
claim at the endpoint is. And the holder may die without a word, so the
claim must end on its own: the endpoint's claims do that on the endpoint's
terms (clause 7), and a claim in the database does it by its time limit. For
an artifact at an endpoint this record stands unchanged.

The database server's failover is IT's (`deployment-model.md` section 9). Epoch
fencing belongs to option C, recorded for later in `deployment-model.md`
section 7, and is not part of this decision.

## Amendment, 2026-10-13: one winner for every Receive Location

**Provenance.** The owner, 2026-10-13, of the Essentials' drop box:
*induce multiple files for FILE and (S)FTP(S) so I can see that it holds
up*, and *only one Rn should win*. Then *(S)FTP(S) has a near problem to
FILE, it has been discussed*, and *We have a thing for it, I called it
Exclusiveness for a while*. Told exclusiveness was replaced by
`ResourceClaim`, and asked whether to give FTP, FTPS and SFTP a real
`ResourceClaim` the same way as FILE: *Yes*. Then *And FILE I hope* — the
file transport moves onto the same claim, not beside it — and *And for any
Receive Location, regardless of protocol.*

**The principle.** Every Receive Location guarantees exactly one winner per
artifact, whatever its protocol, each kind by the exclusive step it has:

| kind | the one winner |
| --- | --- |
| listening — a socket, a server Xmip runs | a sender reaches one node; nothing is shared |
| a broker | the broker's own one-consumer delivery is the claim |
| the file family — file, FTP, FTPS, SFTP; SMB, NFS and WebDAV where the same applies | the turn, then the rename (below) |
| object stores and databases | their own exclusive step: a conditional write, `SELECT … FOR UPDATE SKIP LOCKED`, a conditional update |
| a protocol with no exclusive step at all — IMAP, POP3 | the claim through Xmip Storage, as a Message is claimed (amendment 2026-10-01) |

The exclusive step each technology of the last two rows has today, checked
for this amendment:

- **S3**: `PutObject` with `If-None-Match: *` writes only where no object of
  the key exists, `412 Precondition Failed` otherwise (Amazon S3 User Guide,
  *conditional writes*, generally available since 2024-08-20; RFC 9110
  section 13.1.2).
- **Azure Blob**: `Put Blob` with `If-None-Match: *` (the Blob service's
  conditional headers), or `Lease Blob` with `acquire` — clause 2's
  renewable lease.
- **Google Cloud Storage**: an upload with `ifGenerationMatch=0` succeeds
  only where the object does not exist (Cloud Storage, *request
  preconditions*).
- **PostgreSQL**: `SELECT … FOR UPDATE SKIP LOCKED`, since 9.5.
- **MariaDB**: `SELECT … FOR UPDATE SKIP LOCKED`, since 10.6.
- **SQL Server**: no `SKIP LOCKED`; the same is the `UPDLOCK`, `READPAST`
  and `ROWLOCK` table hints together, or a conditional `UPDATE … OUTPUT`.
- **SQLite**: no row locks; a conditional `UPDATE … WHERE` under the
  database's one write lock, which `xmip-core-transport-sqlite` already
  claims a row with.
- **SMB**: `CREATE` with `FILE_CREATE` fails where the name exists
  (MS-SMB2 2.2.13), and `FileRenameInformation` with `ReplaceIfExists = 0`
  never replaces (MS-FSCC 2.4.37): the turn and the rename.
- **NFS**: `CREATE` in `GUARDED` or `EXCLUSIVE` mode (RFC 1813 section 3.3.8;
  `OPEN` with `EXCLUSIVE4`, RFC 7530) and `RENAME`: the turn and the rename.
- **WebDAV**: `MKCOL` fails where the name exists (RFC 4918 section 9.3.1)
  and `MOVE` with `Overwrite: F` never replaces (section 10.6); today the
  transport claims with an exclusive write `LOCK` (section 9.10).

**Built now: the file family.** Amendment 2026-09-26's claim — the turn,
then the rename to `<dropped name>.xmip-claim.<node location,
percent-encoded>.<nanoseconds>`, `Accepted` deleting, `Refused` and
`Failed` returning the file under its dropped name never over a newer one,
a starting node returning its own claims — extends to FTP, FTPS and SFTP.
Clauses 5 and 6 are superseded for them: several receiving nodes may share
one remote directory, and whichever rename succeeds has the file. The
stability check stays: a file is taken by the listing after the one that
found its size and modification time unchanged. The exclusive turn, per
protocol:

- **file**: a file `<name>.xmip-claim`, created only where none exists,
  holding its claimant's name; the claim is a rename; a return is a hard
  link where the dropped name is free.
- **FTP and FTPS**: `MKD <name>.xmip-claim`, which a server refuses where
  anything of the name exists, and inside it a directory named for its
  holder, so a starting node finds its own; the claim is `RNFR` and `RNTO`.
  A return asks `SIZE` of the dropped name and renames back only where
  nothing lies there; a server whose `RNTO` replaces an existing file could
  still lose one a producer drops between the two, which no FTP command
  prevents. FTPS is FTP over the estate's TLS (RFC 4217, `AUTH TLS`,
  `PROT P`; ADR-0033).
- **SFTP**: `OPEN` of `<name>.xmip-claim` with `CREAT` and `EXCL`, holding
  its claimant's name; the claim is `RENAME`, and so is the return, which
  version 3 refuses onto an existing name (draft-ietf-secsh-filexfer-02,
  section 6.5).

The sequence, the names, the stability check, the return and the recovery
are written once, in `xmip-core-transport` (`claim/`), over the few
operations each technology implements — `ClaimSite`: list, take a turn,
rename, restore, delete — and the endpoint's `ResourceClaim` for one
artifact is written once over them too (`Sited`). File, FTP and SFTP each
implement only those operations; `claims()` answers the real claim. A
remote node returns its own claims at its first receive that reaches the
server, so a server out of reach never stops a node starting.
`NoNativeClaim` remains for IMAP and for the technologies whose own step is
not taken yet.

**Recorded as the next step**, not built: the brokers' one-consumer
delivery declared per technology; the object stores' and databases'
exclusive steps above; SMB, NFS and WebDAV onto the file family's claim;
and the claim through Xmip Storage for IMAP, POP3 and the polled reads that
consume nothing at the far end.

Proved by `xmip-core-transport`'s `claim` tests (two claimants racing over
one location: exactly one wins; recovery; a return held from a newer
file), the file, FTP (with and without `tls`) and SFTP transports' tests of
two receiving nodes over one directory or server, and the Essentials' drop
box (ADR-0028, amendment 2026-10-13).

Provenance: the owner's words above. The FTP turn's holder directory, the
remote recovery at the first receive, and the table of each technology's
exclusive step are the assistant's drafting, for the owner to overrule.

## Amendment, 2026-10-19: a listing claims no more than there is room for

**Provenance.** `open-problems.md` problem 38, raised by the performance
review of 2026-10-12: *the file transport claims a whole directory listing
at once, so what waits in memory grows with the batch; excess should stay
at its durable source.* The coordinator's brief of 2026-10-19 asked for it
built.

The claim above is unchanged; how much of a listing one receive takes is
bounded. The runtime asks a transport for at most as many arrivals as the
Receive Location's pool and the node have room for
(`Transport::receive_up_to`; ADR-0018, amendment 2026-10-19), and the file
family's claim, written once (`claim::Claiming::take`), claims no more of
a listing than that: the rest stay unclaimed under their dropped names,
remembered as found, and the next listing takes them as it takes any
finished artifact — the stability check is kept, not restarted. So several
nodes share a large directory a room's worth at a time, and a node that
stops leaves unclaimed what it never had room for. File, FTP, FTPS and SFTP
take it through the claim; an object store's listing (`listed::listed`), a
SQL query's rows (`sql::accept::arrivals`), SMB's and NFS's listings, a
WebDAV collection and a POP3 maildrop hand over no more, the rest left where
they lie.

Proved by `xmip-core-transport`'s `claim` test of a listing claiming no
more than asked, and the file transport's test of a receive that claims no
more than its room and leaves the rest as dropped.

## Amendment, 2026-10-19: a sent file not yet in place is its node's

**Provenance.** `open-problems.md` problem 39, found 2026-10-12 making the
file transport's send atomic: a send writes its file beside its target and
renames it into place, so a reader sees the old file or the whole new one,
and a process that dies between the two leaves that file in the directory
for good — receive never takes it, nothing removed it, and its name carried
the process, so no node could say it was its own. The owner decided it on
2026-10-19: **the temporary file's name carries the node's identity, not the
process's, and at its start the node removes its own leftovers while it
recovers its claims. It removes no other node's file.**

**The name.** The node's identity is the one a claimed name carries
(amendment 2026-09-26, *Option A*): the node's location the runtime gives a
transport as it builds it (`transport::Configured::on_node`), percent-encoded
(`claim::Claimant::of`), compared whole and never read for meaning. A send
writes under

```text
<target>.xmip-sending.<the node's location, percent-encoded>.<count>.<nanoseconds>
```

the count being the process's sends so far, so two sends at once never
share a name. Such a name is never an arrival. The name and its removal are
written once, in `xmip-core-transport`'s `claim/unfinished.rs`
(`Claimant::sending`, `Claimant::remove_unfinished`), and a technology that
writes beside its target calls them.

**The removal.** A starting node's recovery of its claims removes, of what
the listing it already makes finds, the sent files its own name records
(`Claimant::recover`). A send in flight is never removed: a node builds a
Location's transport while its other Locations may be sending into the same
directory, so every name stays in the process's set of sends in flight from
before its file is created until it is renamed or removed
(`claim::Unfinished`), and the removal passes over every name the set holds.

**Where.** The file transport is the family's one technology that writes
beside its target: FTP stores with `STOR`, SFTP opens with `TRUNC`, SMB
creates and NFS creates and writes, each in place, and WebDAV, S3, Azure
Blob and Google Cloud Storage put an object whole. The runtime sends a
Send Location's Messages to its address (`xmip-core-runtime`'s
`departure`), so a file Send Location's address names the file it writes,
while a Receive Location's names its drop directory. The transport learns
which as it is built (`Configured::sided`, called once by
`Configured::open`, keeping nothing by default): a Receive Location recovers
its claims and removes its node's sent files in its drop directory; a Send
Location claims nothing and removes them beside its target. Until now a Send
Location's start read its address as a drop directory, so a node whose file
Send Location had sent once could not start again.

Proved by `xmip-core-transport`'s `claim::unfinished` tests (a node's own
left file removed and another node's kept; one in flight kept until its send
lets it go; never an arrival; the removal no more than a millisecond beyond
the far end's own listing and removals over a hundred names) and the file
transport's (a starting Receive Location and a starting Send Location each
remove their node's and no other's; a node starting while a send writes
leaves it whole).

Provenance: the owner's words above. `Configured::sided`, the set of sends
in flight and the place each side removes in are the assistant's drafting,
for the owner to overrule.

## Amendment, 2026-10-20: a file Send Location's address names a directory

The owner, 2026-10-19: **a file Send Location's address names a directory,
with each Message's file name taken from the Message's context (its
received file name). Fix the relative-path bug (`addr/addr`) on the way.
Keep the atomic write and the node-named temporary file** (the amendment of
2026-10-19).

- **The name the file was dropped under travels with the Message.** A file
  Receive Location writes it on the arrival as `file.name`
  (`context::property::FILE_NAME`), and the runtime writes it into the
  Message Context beside the headers, once, at arrival
  (`context::property::KEPT`, the one list of what a transport says that
  the Message keeps). Departure hands the transport the Message's context
  with its body (`transport::Outgoing::carrying`), and the file transport
  writes the file under that name in the directory the address names.
- **Refused in words, never guessed.** A name naming a path rather than a
  file of the directory (`..`, `sub/order.edi`, empty) is refused at the
  send, permanently, and nothing is written; a Message carrying no
  `file.name` is named as the amendment of 2026-10-21 below says. A test or
  a tool that sends bytes it holds, with no Message behind them, names the
  file itself.
- **The relative-path bug is gone with the reading that made it.** The
  address had been read as the file, and the directory a send wrote beside
  it was found by joining the address to itself, so a relative address
  `out` wrote under `out/out`. The directory is now the address, as it is
  for a Receive Location, and a starting Send Location removes its node's
  unfinished sends there.
- **Kept:** the write beside the target, its sync and its rename into place,
  and the temporary file named for its node.

Proved by the file transport's tests (a Message written under its received
name in the directory a relative or absolute address names; a Message with
no name, or a path for one, refused and nothing written; a dropped file
saying its name) and by `.src/test/measured/carried.rs` in the assembled
service.

Provenance: the ruling is the owner's, 2026-10-19; `file.name`, the `KEPT`
list, handing the context with the body and the refusals' words are the
assistant's, 2026-10-20. What a file Send Location writes for a Message that
carries no file name was decided on 2026-10-21 (below).

## Amendment, 2026-10-20: a drop directory tells, and a file is finished when no writer holds it

A file dropped on the getting-started node waited about 1.7 seconds for its
claim (`doc/getting-started.md`), and 64 to 77 ms at a 50 ms poll in
`.src/test/measured/carried.rs`: the Location listed its directory at its
poll interval, and took a file only at the listing after the one that found
it unchanged. The owner, 2026-10-20: *make the file Receive Location react to
the file system's change notification, and keep the stability check
correct: a file being written must never be taken half-written. Keep
polling only as a recovery sweep. Its cadence is a default in `[tuning]`,
set per cluster and node in the Cluster TOML.*

- **The drop directory tells.** A polled technology whose far end tells of
  a change says where (`transport::Transport::notice`, `transport::Notice`);
  the file transport names its drop directory. The runtime watches it with
  the operating system's change notification (`runtime::directory_watch`,
  which tells now also of a file grown or written and closed, on Windows),
  and a Location that found nothing rests until the word comes
  (`stopping::Nudge`). A drop directory not there yet is polled until it is.
- **The poll is a recovery sweep.** Where no word comes, the rest lasts
  `[tuning] receive_sweep`, a second by default, set per cluster and per
  node as every `[tuning]` value is (ADR-0031, amendment 2026-10-03): for
  a file that lay there before the watch began, or a word missed.
  `receive_poll` stays the rest of a Location nothing tells.
- **A file is finished when no writer holds it, where the system says.**
  The claim asks its site whether a writer still holds a file
  (`transport::claim::ClaimSite::finished`). On Windows the file transport
  opens the file sharing reading and deleting and not writing, which the
  system refuses while any handle writes it: a file a producer writes in
  place — paused or not — is never taken, and one renamed in whole or
  closed is taken by the listing its change wakes. Where the system cannot
  say — Linux, macOS, the file family's remote sites — clause 5's stability
  check decides as before, its second listing at the next change or sweep.
  Either way a file is claimed only if its stamp is still what the listing
  found once its turn is held.
- **A listing asks the file system nothing more per file** than the
  directory read carries, its length and time.

Measured after (2026-10-20, three runs): a file waits 1.57 to 1.79 ms, the
fastest of five, from its drop to its claim — the word, the listing, the
probe, the turn and the rename on the file system — and `carried.rs` holds
it under ten milliseconds, never the sweep's second.

Provenance: the ruling is the owner's, 2026-10-20; the writer's probe and
the sweep's name are the assistant's, for the owner to confirm or strike.
**Decided by the owner, 2026-10-21:** `receive_sweep`'s default of a
second. Taking a file at once on Linux and macOS — a close
after writing the watch already hears, told by name — is open (open problem
33).

## Amendment, 2026-10-21: on Windows a dropped file's turn is the file held open

**Provenance.** The assembled service's file-drop test once waited 14 ms
for a dropped file's claim against its ten while another build ran on the
machine (open problem 33). The owner's terms: fix what a busy machine or
disk slows, never loosen the test.

- **What was slow.** Timed step by step inside the node, a claim on an
  idle machine took about 3.0 ms, the fastest of five: the word and the
  wake, the listing (0.35 ms), the open asking whether a writer still held
  the file (0.35 ms), the turn file created, written and closed (0.85 ms),
  the stamp read again by its path (0.2 ms), the rename (0.7 ms) and the
  turn removed (0.5 ms). Each is a change to the directory or an open the
  file system and its virus guard work through, and each grows with a busy
  disk: beside four processor-bound jobs and two jobs writing and removing
  files, 4.6 to 5.3 ms.
- **On Windows the turn is the dropped file held open**
  (`xmip-core-transport-file`, `holding.rs`): opened to write and sharing
  reading and deleting, never writing. No other claimant opens it so while
  one holds it, and no producer still writing it lets it be opened at all,
  so the same open says the file is finished (the amendment of 2026-10-20);
  the stamp is read through the handle; the rename, which opens the file to
  delete it, goes through; nothing is written through it, and the turn ends
  with the handle, so a node that dies leaves none behind. Exclusive as the
  turn file was: whichever claimant holds the handle renames the file, and
  one that finds it held leaves it to its next listing. Where the open is
  refused for anything but another's handle — a file the node's account may
  not write — and on every other system, the turn is a file as before.
- **What stays.** The claimed name, the rename, the return and a starting
  node's recovery are unchanged; `ClaimSite` is unchanged, the file system
  taking its turn in its own words as FTP takes it by `MKD`.

Measured after (2026-10-21): the claim took 2.0 to 2.2 ms on an idle
machine and beside the same jobs and disk; the assembled service's suite,
five runs back to back beside four processor-bound jobs, passed every test
with the claim at 1.60 to 1.99 ms, the fastest of five, and three runs
beside eight at 1.90 to 2.72 ms.

Provenance: the defect and the terms are the owner's; the turn held open
is the assistant's, 2026-10-21, for the owner to confirm or strike. Linux
and macOS keep the turn file, and take a file at the second listing (the
amendment of 2026-10-20).

## Amendment, 2026-10-21: a Message without `file.name` is named by the Send Location's pattern

The owner, 2026-10-21: **a Message without `file.name` is named from a
pattern configured on the file Send Location, falling back to the Message's
identifier.** Every surface that configures a Send Location gets the
pattern.

- **The pattern is the Send Location's `name` setting**, declared by the
  file technology (`xmip-core-transport-file`'s `SETTINGS`, `Applies::Send`):
  `{message}` in it is the Message's identifier, so
  `name = "order-{message}.edi"` writes `order-<identifier>.edi`. A Location
  that gives none writes the identifier alone. A name the Message carries,
  `file.name`, goes first; a name the pattern makes is held to what every
  name is — one file of the directory, never a path — and refused in words
  otherwise.
- **The runtime hands every send the Message's identifier** beside its
  context (`transport::Outgoing::of_message`, `Outgoing::message`), as it
  hands the Journey's as the deduplication key.
- **Every surface has it from the declaration**, the one place it is
  written: the API's `xmip_technology_catalogue_v1` and `xmip_validate_v1`,
  `xmip-cli validate`, `Test-XmipNodeConfiguration`, and the VS Code
  designer's completion, hover and Location form, all read the technology's
  declaration through the runtime, so none holds a word of its own about it.

Proved by the file transport's tests (named by the identifier, by the
pattern, by `file.name` first; a pattern naming a path refused; `name`
refused on a Receive Location). Provenance: the ruling is the owner's,
2026-10-21; the setting's name and `{message}` are the assistant's, for the
owner to overrule.

## Amendment, 2026-10-22: Correlations are cluster-wide, and one Sequence orders over the claims

The owner, 2026-10-22, having read this record again: *As long as the
correlation sets are cluster wide*, and *when a stream arrives, it might
need exclusiveness from the point it is read to when it leaves Xmip via
Send, or it does not, it just might need some parameter to work in
parallel.* Then, simplifying the drafts he was shown: *I think you are
overcomplicating things. On receive, the default is one journey per stream
at a time. If I decide to open up for multiple streams (messages) I will
tell Xmip by defining values that work can be spread over, like Message
Contexts values, Promoted values. Like for instance, Xmip receives an order.
That can be processed per client requesting an order. Xmip gets an update
of all the merchandise, that Xmip should process one at a time because the
person updated all the merchandise is hacking away not knowing of the
consequences*; corrected to *every receive location should by default be end
to end treated. Not the receive port, unless opened up by Correlations
to support multiple processing through Xmip*; and settled as *A default
correlation set is its receive location name. There might be more streams,
files, pushing at that receive location. Default one stream, message,
journey at a time. Put it in the ledger if it is not processed now. If I
want to open up for parallelism I can use context values like Receive Port,
Work Process, Send Port, Message and Journey context values. I can widen
and strangle parallelism at any configurable point*, and *Equal values in a
correlation set (aka hashtable) go in the same queue, different values go
parallel depending on the value in the correlation set.*

- **A claim is still a claim.** This record's rule stands: a claim says one
  holder at a time, at the endpoint where one exists and through Xmip
  Storage where none does, and says nothing about order.
- **A Sequence orders over the claims** (`xmip-core-runtime`'s `sequence`;
  ADR-0066, amendment of this date, clause 5). A Correlation is declared
  once for the cluster, `[[correlations]]`, and named at a point — a
  Receive Location, a Receive Port, a Work Process, a Send Port — by
  `correlation`. Each key, the full tuple of the set's values, is one
  queue in the Ledger, its places in the order they were written; work at
  the point goes on only while it holds the first place. A Journey is still
  claimed before it is worked on; a claimed Journey that does not head its
  sequence gives its claim back and waits in the Ledger, holding no thread.
- **The default is the Receive Location's own sequence**: one Stream at a
  time, end to end — from its Publication until the last Journey born from
  it, its sends among them, has ended. The merchandise update needs nothing
  configured; orders per client name a set keyed by the client,
  `keys = ["context:Client"]`, and run side by side, each client's in order.
- **What a failure does is the set's**: `on_failure`, `block` by default — a
  Message that failed, waiting for an operator, keeps its Stream at the head until
  Retry or Dismiss — and `skip` as the option that lets the rest pass (the
  owner, 2026-10-22). The Send Port's own `execution_style`, `order_key` and
  `on_failure` are deleted with every use.
- **Cluster-wide by construction.** A sequence is a Ledger queue, named by
  the point and the key's values, read and written through Xmip Storage by
  whichever node takes the work, the same primary every node writes to — no
  lease, no consensus, no store of its own. A node that dies leaves its
  claims to lapse and its places in the Ledger; another node takes up the
  Journey, and the order is the Ledger's.

Provenance: the rulings quoted are the owner's, 2026-10-22; the queue's
naming and the origin counting are the assistant's, the owner's to strike.

## Amendment, 2026-10-27: Correlations are Xmip's exclusiveness

The owner, 2026-10-27: *So let's work on that, that is exclusiveness! Way
more important than parallelism.* This record replaced ADR-0017's lease
with the claim at the endpoint; exclusiveness itself is the correlation
sets of the amendment of 2026-10-22 and the claim through Xmip Storage.
The owner confirmed this picture the same day:

- **One winner per artifact**: the claim at the endpoint, and one holder of
  a Journey through Xmip Storage.
- **By default one Stream, Message or Journey at a time per Receive
  Location**, cluster-wide, from read until it leaves through Send, the
  rest waiting in the Ledger in arrival order.
- **Correlation sets open or narrow it at any point**: a Receive Location,
  a Receive Port, a Work Process, a Send Port and a Send Location.
- **A failure blocks until Retry or Dismiss, or skips**, as the set's
  `on_failure` says.

What makes it hold, built 2026-10-27:

- **A Send Location names a set** (`correlation` on a node's own Send
  Location or a binding's). A Journey bound for a Send Port takes its place
  in the Port's sequence and in the sequence of every Send Location the
  Port may leave by, Port first, in one write (`Journey.sequences`). Every
  Send Port of every bound Application and every Send Location the
  document holds counts, so a Journey published on a node that does not
  send it takes its places all the same — before, it took none.
- **Journey Context keys**: `journey:origin`, `journey:subscription` and
  `journey:previous`. The artifact words (`receive-location`,
  `receive-port`, `work-process`, `send-port`) are the only spelling of
  what they read.
- **Places are taken once a Stream heads its own sequences.** A Stream
  behind the head of its Receive Location's sequence is not being
  processed, so its Journeys take no place at their destinations until it
  heads; they are taken in the write that first takes each up then
  (`runtime::sequence::take_late`), and only by the step that reads the
  destination's queue in its order — the send scan, or the work scan
  turning a Work Process that names a Correlation one Journey at a time —
  so they follow the Ledger's order and no two threads race for them. A Stream's Journey a Work Process
  publishes later never waits behind a Stream that waits for it
  (`tests/ledger/stream_order.rs`).
- **A dead holder's key passes on, fenced.** A claim's `fence` is the
  Storage epoch in the high 32 bits and the Journey's holder count in the
  low 32, set by Xmip Storage as it takes the claim; a renew, release or
  hand-on whose token and fence are not the current ones is refused, and
  the far end is told the fence beside the deduplication key
  (`transport::Outgoing::fenced`). Proved by killing the holder mid-send
  (`tests/ledger/fenced.rs`) and by failing over the Storage primary with a
  claim held: the new epoch's fence is above every fence before it.
- **Sets taken in crossing order are refused** at validation and as a node
  starts, in words naming both sets, a path taking each order and the fix
  — *take X before Y on both paths* (`configure::correlation::crossing`).
- **A Send Port Group names a set.** The owner, 2026-10-27:
  *Correlations should be set in TOML by Receive Location, Receive Port,
  Work Process, Send Port Group, Send Port and Send Location*; *a send
  port group does not have to send in order, it is a spread solution.
  Success should be audited as each send port does, failures should be
  audited as they should*; and *The result is a set of ports that
  succeeded or failed … one has to accumulate the results. Report the
  results as a set.* So `correlation` on a Send Port Group holds the
  Group's key for a delivery — the member Journeys one Subscription opens
  through the Group in one Publication — until the set is complete: every
  member has succeeded or failed. The members go side by side; the next
  delivery of the same key waits. Where the set holds a failure, the key
  follows `on_failure`: held until an operator retries or dismisses the
  failed member (`block`), or let go (`skip`). Each member is still
  audited on its own. The key word `send-port-group` reads the Group's
  name. The path order is Receive Location, Receive Port, Work Process,
  Send Port Group, Send Port, Send Location: a member takes the Group's
  place first and its Port's and Locations' once its delivery heads the
  Group's sequence. Xmip Storage counts a delivery's open members as it
  counts a Stream's open Journeys and lets the place go with the last
  (`JourneyFacts::group_delivery` and `group_open`; `Journey.group`, a
  `GroupDelivery` of its name, delivery, queue, `skips` and members;
  `tests/ledger/group_correlation.rs`).

## Amendment, 2026-10-28: the verdict decides what becomes of a file read

The owner, 2026-10-28, agreeing the address-only Locations (ADR-0064,
amendment of this date): FTP's `delete_after_retrieve` is deleted, so the
file, FTP, FTPS and SFTP Locations all do what the verdict says, and
nothing else: `Accepted` deletes the claimed file, `Refused` returns it
under its dropped name and remembers it while it is unchanged, `Failed`, or
an arrival let go without a verdict, returns it to be read again. The
claim's `consume` argument, which only that setting ever made false, is
deleted with it (`transport::claim::Claiming::told` and `acknowledgement`).

## Amendment, 2026-11-19: an object store's read and delete hold to the version listed

**Provenance.** An outside review of 2026-11-19 found it, and it was
confirmed against the source the same day. `transport::listed::listed`,
the one receive the S3, Azure Blob and Google Cloud Storage transports
share, listed each object with its stamp but got it and deleted it by its
name alone. So clause 7's step 3, *Consume*, deleted whatever lay under
the name when the verdict came: an object a producer wrote again under
that name after the cycle read it was deleted unread, against the runtime
model's rule (section 16, *Delivery semantics*): *Where Xmip cannot
guarantee exactly-once, it guarantees at-least-once and says so.* An
object written again between the listing and the first read was read under
the stamp the listing gave the one before, and an accepted object another
client deleted meanwhile failed its acknowledgement where the store answers
a delete of nothing with 404.

**What stands.** An object store's get and delete each name the object as
it was listed: its name and the stamp its listing gave it, sent as the
store's precondition on the request the receive already makes — no extra
request. S3 and Azure Blob send the `ETag` in `If-Match` on the get and the
delete; Google Cloud Storage lists each object's generation as its stamp
and sends it as `ifGenerationMatch`. The store's answer is
`transport::listed::AsListed`: `Held` with what was asked, or `Changed`
where the object was written again or deleted since — `412 Precondition
Failed` or `404 Not Found`, and on an S3 delete `409 Conflict` too. Each
technology's client has the conditional get and delete only; the delete by
name alone is deleted from all three.

- **A body changed since its listing is not read.** Its read fails,
  *changed since it was listed: the next listing takes it as a new
  arrival*; the cycle fails, nothing is deleted, and the next listing takes
  what lies there now, under its own stamp. That failure is retryable
  through every reader, because `transport::error::classify` keeps the
  judgment of a `TransportError` an `io::Error` carries, where until
  2026-11-19 it judged one by its kind, `Other`, as permanent (before the
  fix, `cargo test --lib a_transport_failure_read_through_a_body_keeps_its_judgment`
  in `module/core/capability/transport` answered `message: "reading what
  arrived: changed since it was listed (retryable)", retryable: false`).
- **An accepted object changed since is done with.** Its delete answers
  `Changed` and the acknowledgement is OK: one written again stays for the
  next listing, one deleted since is gone already.
- Clause 7's step 3, for an object store, is therefore the delete of the
  version read, never of the name.

The vendors' own words, read 2026-11-19:

- Amazon S3, [conditional deletes in general purpose
  buckets](https://aws.amazon.com/about-aws/whats-new/2025/09/amazon-s3-conditional-deletes-s3-general-purpose-buckets/),
  posted 2025-09-16: *Amazon S3 now supports conditional deletes in S3
  general purpose buckets, which verify that an object is unchanged before
  deleting it.*
- Amazon S3, [DeleteObject](https://docs.aws.amazon.com/AmazonS3/latest/API/API_DeleteObject.html),
  `If-Match`: *Deletes the object if the ETag (entity tag) value provided
  during the delete operation matches the ETag of the object in S3. If the
  ETag values do not match, the operation returns a `412 Precondition
  Failed` error.* And: *The `If-Match` header is supported for both general
  purpose and directory buckets.*
- Amazon S3 User Guide, [conditional
  deletes](https://docs.aws.amazon.com/AmazonS3/latest/userguide/conditional-deletes.html):
  *You can also receive a `409 Conflict` error response in the case of
  concurrent requests if a `DELETE` or `PUT` request to an object succeeds
  before a conditional delete operation on that object completes.* And:
  *To perform conditional deletes with the `If-Match` header with the
  `ETag` value, you must have the `s3:DeleteObject` and `s3:GetObject`
  permissions.*
- Amazon S3, [GetObject](https://docs.aws.amazon.com/AmazonS3/latest/API/API_GetObject.html),
  `If-Match`: *Return the object only if its entity tag (ETag) is the same
  as the one specified in this header; otherwise, return a `412
  Precondition Failed` error.*
- Azure Blob Storage, [specifying conditional headers for Blob service
  operations](https://learn.microsoft.com/en-us/rest/api/storageservices/specifying-conditional-headers-for-blob-service-operations):
  `If-Match`, *An ETag value. Specify this header to perform the operation
  only if the resource's ETag matches the value specified. For versions
  2011-08-18 and newer, the ETag can be specified in quotes.* Get Blob and
  Delete Blob both take it, and an unmet `If-Match` answers *Precondition
  Failed (412 (Precondition Failed))* for a read and for a write alike.
  [Delete Blob](https://learn.microsoft.com/en-us/rest/api/storageservices/delete-blob):
  *This operation also supports the use of conditional headers to delete
  the blob only if a specified condition is met.*
- Google Cloud Storage, [request
  preconditions](https://docs.cloud.google.com/storage/docs/request-preconditions):
  *Request proceeds if the `generation` of the target resource matches the
  value used in the precondition.* And: *If the values don't match, the
  request fails with a `412 Precondition Failed` response.* Its
  [objects.get](https://docs.cloud.google.com/storage/docs/json_api/v1/objects/get)
  and [objects.delete](https://docs.cloud.google.com/storage/docs/json_api/v1/objects/delete)
  each take `ifGenerationMatch`: *Makes the operation conditional on
  whether the object's current generation matches the given value.*

**What it does not close**, open problem 72: an S3-compatible endpoint
that ignores `If-Match` on a delete deletes by the name, so the race above
stays open there; and two nodes listing one bucket may both read one
object under one stamp, the second accepted delete answering `Changed`:
the object is received twice, at least once, because the object stores'
exclusive step of the amendment of 2026-10-13 is still not built.

Proved by `xmip-core-transport`'s `listed` tests, over an in-memory store
that honors the stamps as the three vendors do:
`a_replacement_between_read_and_acceptance_stays_for_the_next_listing`,
`a_replacement_between_listing_and_first_read_is_not_read_under_the_old_stamp`
and `an_object_gone_before_acceptance_is_told_done`. The same three, written
against the code before this amendment — a get and a delete by name, the
delete of a gone object answering 404 as Azure Blob and Google Cloud
Storage do — each fail. Run 2026-11-19 on Windows in
`module/core/capability/transport`, `cargo test --lib listed`, before:

```text
test listed::tests::a_replacement_between_listing_and_first_read_is_not_read_under_the_old_stamp ... FAILED
test listed::tests::a_replacement_between_read_and_acceptance_stays_for_the_next_listing ... FAILED
test listed::tests::an_object_gone_before_acceptance_is_told_done ... FAILED
not the object listed: Taken { origin_uri: "aws-s3://inbox/a.edi", bytes: [116, 119, 111], observed: [] }
removal index (is 0) should be < len (is 0)
nothing left to delete is done: TransportError { message: "404 BlobNotFound", retryable: false }
test result: FAILED. 5 passed; 3 failed; 0 ignored; 0 measured; 155 filtered out; finished in 0.25s
```

and after:

```text
test listed::tests::a_replacement_between_listing_and_first_read_is_not_read_under_the_old_stamp ... ok
test listed::tests::a_replacement_between_read_and_acceptance_stays_for_the_next_listing ... ok
test listed::tests::an_object_gone_before_acceptance_is_told_done ... ok
test result: ok. 8 passed; 0 failed; 0 ignored; 0 measured; 155 filtered out; finished in 0.18s
```

Each technology's own tests drive the first two sequences over the wire and
map `412`, `404` and S3's `409` to `Changed`: `xmip-core-transport-aws-s3`,
`xmip-core-transport-azure-blob` and
`xmip-core-transport-google-cloud-storage`.

## Amendment, 2026-11-20: an object store's object is won by one node's claim beside it

**Provenance.** Open problem 72, found 2026-11-19 with the amendment
above: two nodes listing one bucket could both read one object under one
stamp, the second accepted delete answering `Changed`, so the object was
received twice, because the object stores' exclusive step of the
amendment of 2026-10-13 — the owner's *only one Rn should win* and *for
any Receive Location, regardless of protocol* — was still not built. The
coordinator's brief of 2026-11-20 asked for it built, modeled on the file
family's claim, the shared logic once in `transport::listed` behind a
trait each store implements.

**What stands.**

- **The claim is an object beside the object.** A listing claims each
  object it hands over by writing `<name>.xmip-claim` — the file family's
  turn name (`claim::turn_of`) — only where no object of that name lies,
  in one request the store decides alone: S3 `PutObject` with
  `If-None-Match: *`; Azure Blob `Put Blob` with `If-None-Match: *`;
  Google Cloud Storage an upload with `ifGenerationMatch=0`. The claim
  holds the claimed name the file family records,
  `<name>.xmip-claim.<node location, percent-encoded>.<nanoseconds>`
  (`claim::Claimant::claimed`, now the one place that name is written,
  the file family's rename included). The node whose write the store takes
  has the object. A node that finds a claim listed beside an object passes
  it over without a request; one whose write the store refuses (`412`, or
  Azure Blob's `409 BlobAlreadyExists`) passes it over. Nothing is renamed:
  an object store has no rename, and the object is read where it lies, as
  the amendment above reads it.
- **The claim is let go however the cycle ends.** `Accepted` deletes the
  object as listed, then the claim as it was written — the stamp its write
  answered: S3's and Azure Blob's `ETag`, Cloud Storage's `generation`;
  `Refused` and `Failed` delete the claim alone; an arrival let go without
  a verdict lets its claim go too. The object goes first, because a claim
  let go before the delete would let another node read it again. A claim
  whose delete the store does not answer is kept, and let go at the node's
  next listing before anything is claimed.
- **A node that starts again lets go of every claim its name holds.** At
  its first listing that reaches the store (`Configured::on_node`, as FTP
  and SFTP return theirs) it reads each claim listed and deletes, as
  listed, every one whose claimed name names its own location; another
  node's is read and left.
- **How a claim of a node that died is returned, and why so.** By its own
  node as it starts, as the file family's claimed file is (amendment
  2026-09-26), because only the claimant knows that a claim of its own is
  from before it started and that nothing holds it now. Not by its age: a
  claim ended by a time limit is a lease inside Xmip, which clause 1
  retired, and a receive cycle that outlived the limit would let a second
  node take an object the first still holds — the twice this amendment
  closes. Not by an Azure blob lease either, which clause 2's table named:
  a lease *creates and manages a lock on a blob for write and delete
  operations*, so the Party's producer could not write the blob again
  while Xmip held it, a lease lasts *15 to 60 seconds, or can be infinite*
  and so needs renewing through a long cycle or breaking after a death,
  and S3 and Cloud Storage have none: the one claim serves all three. A
  node gone for good leaves its objects in place and claimed, never lost,
  each claim saying who holds it and since when; returning those is the
  cluster's half of the recovery, open for the file family since
  2026-09-26 and now for the object stores.
- **Written once, and open.** `transport::listed::Store` is what each
  store implements — list, get as listed, delete as listed, create only
  where nothing lies, and its origin — and `transport::listed::Claims` is
  the sequence above, the claims not yet let go, the recovery and the
  claim of one object by its address: `xmip-core-transport-aws-s3`
  (`bucket::Bucket`), `xmip-core-transport-azure-blob`
  (`container::Container`) and `xmip-core-transport-google-cloud-storage`
  (`bucket::Bucket`) implement `Store` and nothing more, and each answers
  `Transport::claims` with that claim, where `NoNativeClaim` answered
  before. Any store whose write can be made only where nothing lies
  implements `Store` and has the claim. Each client's `put_new` now hands
  back the stamp it wrote, which the archives of ADR-0040 read as before:
  written, or there already.
- **What it costs.** Per object handed over, the claim adds one
  conditional write at the listing — the one exclusive request — and one
  delete at its verdict, its letting go; nothing is read before the write
  and nothing renewed while the cycle runs, and an object another's claim
  holds costs no request at all. Xmip's own share is writing one name.
  A starting node reads each claim listed, once. The Location's credentials
  must now write beside what it takes: `s3:PutObject`, which AWS asks of
  `If-None-Match`; Azure Blob write; Cloud Storage `storage.objects.create`.

**What remains.** A node whose listing came before another node took an
object whole — the other's claim, read, delete and letting go all between
the first node's listing and its claim — wins a claim on nothing: its read
finds the object gone, its cycle fails retryably, its claim is let go, and
nothing is received twice. An S3-compatible endpoint that ignores
`If-None-Match: *` (open problem 75) stores every claim, writing over
another node's, so two nodes may both receive one object there — twice,
never lost, as before this amendment. And as the amendment above says, an
endpoint that ignores `If-Match`, and whether Azurite honors the
conditions, are not checked.

The vendors' own words, read 2026-11-20:

- Amazon S3, [PutObject](https://docs.aws.amazon.com/AmazonS3/latest/API/API_PutObject.html),
  `If-None-Match`: *Uploads the object only if the object key name does
  not already exist in the bucket specified. Otherwise, Amazon S3 returns a
  `412 Precondition Failed` error.* And: *If a conflicting operation occurs
  during the upload S3 returns a `409 ConditionalRequestConflict` response.
  On a 409 failure you should retry the upload.*
- Amazon S3 User Guide, [conditional
  writes](https://docs.aws.amazon.com/AmazonS3/latest/userguide/conditional-writes.html):
  *If multiple conditional writes or copies occur for the same object name,
  the first write operation to finish succeeds. Amazon S3 then fails
  subsequent writes with a `412 Precondition Failed` response.* And: *To
  perform conditional writes with the HTTP `If-None-Match` header you must
  have the `s3:PutObject` permission.*
- Azure Blob Storage, [specifying conditional headers for Blob service
  operations](https://learn.microsoft.com/en-us/rest/api/storageservices/specifying-conditional-headers-for-blob-service-operations),
  `If-None-Match`: *Specify the wildcard character (\*) to perform the
  operation only if the resource doesn't exist, and fail the operation if
  it does exist.* Put Blob and Delete Blob both take it, and an unmet one on
  a write answers *Precondition Failed (412 (Precondition Failed))*.
- Azure Blob Storage, [Lease
  Blob](https://learn.microsoft.com/en-us/rest/api/storageservices/lease-blob):
  *The `Lease Blob` operation creates and manages a lock on a blob for
  write and delete operations. The lock duration can be 15 to 60 seconds,
  or can be infinite.* And, of Put Blob and Delete Blob among others: *If
  the lease ID isn't included, these operations fail on a leased blob, with
  `412 – Precondition failed`.*
- Google Cloud Storage, [request
  preconditions](https://docs.cloud.google.com/storage/docs/request-preconditions):
  *When a generation-match precondition with a value of `0` is included in
  a request, the request only proceeds if no object with the specified
  name exists in the bucket or if there are only noncurrent versions of the
  object in the bucket. If there is a live version with the specified name,
  the request fails with a status code of `412 Precondition Failed`.*

Proved by `xmip-core-transport`'s `listed` tests, over an in-memory store
that honors each condition as the three vendors document it
(`listed/memory.rs`): two nodes listing one object, both reading before
either is told, receive it once; two nodes racing over three hundred
objects receive each exactly once; a dead node's claim is let go as that
node starts again and by no other; every verdict, and an arrival let go
unheard, lets its claim go; a claim the store did not let go is let go at
the next listing; a claim another holds is passed over unasked, and one
whose write the store refuses is passed over. The two-node test, written
against the code before this amendment — each node a Location of its own,
the receive as it was — fails. Run 2026-11-20 on Windows in
`module/core/capability/transport`, `cargo test --lib listed`, before:

```text
test listed::tests::two_nodes_listing_one_object_never_both_receive_it ... FAILED
assertion `left == right` failed: one node receives it
  left: [[111, 110, 101], [111, 110, 101]]
 right: [[111, 110, 101]]
test result: FAILED. 8 passed; 1 failed; 0 ignored; 0 measured; 156 filtered out; finished in 0.01s
```

and after:

```text
test listed::claims::tests::two_nodes_listing_one_object_never_both_receive_it ... ok
test listed::claims::tests::two_nodes_racing_over_one_store_take_every_object_exactly_once ... ok
test listed::claims::tests::a_dead_nodes_claim_is_let_go_as_it_starts_again_and_by_no_other ... ok
test listed::claims::tests::an_object_another_claims_is_passed_over_and_its_claim_is_never_an_arrival ... ok
test result: ok. 17 passed; 0 failed; 0 ignored; 0 measured; 156 filtered out; finished in 0.02s
```

Each technology's own tests drive two nodes over one far end
(`two_nodes_listing_one_bucket_never_both_receive_one_object` in aws-s3
and google-cloud-storage,
`two_nodes_listing_one_container_never_both_receive_one_blob` in
azure-blob): the first's claim is written, the second, starting, reads it,
leaves it and receives nothing, and once the first accepts, the object and
its claim are gone.

Provenance: the owner's words above, and the brief's. The claim object
beside the object, its delete as written, the claims kept and let go at the
next listing, and putting the Azure blob lease aside are the assistant's,
2026-11-20, for the owner to confirm or strike.

## Amendment, 2026-11-22: a claim names its node and that start of it

**Provenance.** Open problem 96, found 2026-11-22 by a review of the estate
(its finding 3) and confirmed in the source: a claim named its node alone
(`claim::Claimant::of`), and each Location's transport let go of every
claim in its node's name at its first receive — the object stores' recovery
of the amendment above (`listed::Claims::recover`) and the file family's of
the amendments of 2026-09-26 and 2026-10-13 (`claim::Claimant::recover`)
alike. A node builds each Location's transport itself, so two Receive
Locations of one node over one prefix or one directory, or one Location
built again while its node runs, let go of claims a live receive held, and
the object was taken again beside it. The conditional delete kept a claim
written again; it could not tell a claim of an earlier start of the node
from a live one. Offered the start of the node in the claim or one recovery
per node and store, the owner chose the first, 2026-11-22: *"Do them all"*,
option a — **the claim names the node and that start of it.**

**What stands.**

- **A start is the process its node's membership row is keyed by**
  (ADR-0056, amendment 2026-11-13: *`process`, drawn new at each start*): a
  random 128-bit number, never zero, from the operating system's random
  source (`runtime::membership::process`). It is drawn once in
  `Running::start`, before startup phase 9 builds the Locations, where
  `Running::join` drew it at activation; `Running` keeps it, and the row and
  every Location's transport carry the one, so a claim says which start,
  and so which row, holds it. Nothing reads meaning from it: it is compared
  whole.
- **The runtime hands it to each transport with the location.**
  `transport::Configured::on_node` takes `transport::NodeStart` — the
  node's `NodeLocation` and that start — where it took the location alone
  (*Option A*, amendment 2026-09-26, stands), built once per start in
  `startup::open`, so every Location of one start is given the same, and
  the claimant is made from it (`claim::Claimant::of`). The file, FTP, SFTP,
  S3, Azure Blob and Google Cloud Storage transports keep it, and the
  Essentials' drop box, which builds a node's receives of its own, draws a
  start as a node does.
- **It is written into the claimant**: the location percent-encoded as
  before, `~`, and the start in 32 hexadecimal digits.

  ```text
  <name>.xmip-claim.<node location, percent-encoded>~<start>.<nanoseconds>
  <target>.xmip-sending.<node location, percent-encoded>~<start>.<count>.<nanoseconds>
  ```

  The encoding keeps only letters, digits, `-` and `_`, so `~` parts node
  and start in one way; it is unreserved in a URI, allowed in every far
  end's names, and no `.`, so a claimed name, a turn's holder, a sent file's
  name and an object's claim read back as before.
- **A start lets go only of what its node's earlier starts left**
  (`claim::Claimant::is_earlier_start`): a claimant naming the same node and
  not this start, since a node runs one start at a time. A claim of this
  start, whichever of its Locations made it, is left, and another node's is
  left as before. The one rule is called by the object stores' recovery, by
  the file family's — claimed names, and turns, each turn now removed as
  its holder's, which FTP's `RMD <turn>/<holder>` needs — and by the removal
  of sent files not yet in place (`Claimant::remove_unfinished`), where the
  set of sends in flight still guards a send of an earlier start that the
  same process is still writing. The delete as listed stays.
- **A claim written before names its node alone**, with no `~`, and reads as
  an earlier start of it, so a node upgraded across this amendment lets go
  of what it held before, as it did.

**What remains.** Two processes running as one node at once, a
configuration started twice, each read the other's claims as an earlier
start's, as before this amendment each read them as its own. A node gone
for good still leaves its claims: the cluster's half of the recovery is
open, and the start in a claim is what it needs, since a claim whose
start's membership row says it stopped is held by nobody.

Proved by `xmip-core-transport`'s tests: a Location's arrival held
unacknowledged while another Location of the same start starts over the
same prefix is not taken again and its claim is left (`listed::claims`),
and the same over a directory of the file family, the live Location's
claimed file and turn left (`claim`); a claim of an earlier start of the
node, and one naming the node alone, are let go as the node starts again,
and another node's is left; a sent file of this start is kept and an
earlier start's removed (`claim::unfinished`). Each object store drives two
Locations of one start over one far end
(`two_locations_of_one_start_listing_one_bucket_never_both_receive_one_object`
in aws-s3 and google-cloud-storage,
`two_locations_of_one_start_listing_one_container_never_both_receive_one_blob`
in azure-blob), the file transport two over one drop directory, and the
runtime's `tests/running/sharing.rs` sees both Locations of a start handed
one start and the node started again handed another. The new tests,
written against the code before this amendment, fail. Run 2026-11-22 on
Linux, `cargo test -p xmip-core-transport --lib -- a_location_starting_beside`,
before:

```text
test listed::claims::tests::a_location_starting_beside_a_live_one_of_its_start_leaves_its_claims ... FAILED
test claim::tests::a_location_starting_beside_a_live_one_of_its_start_leaves_what_it_holds ... FAILED
panicked at module/core/capability/transport/.src/listed/claims.rs:664:9:
not taken again
panicked at module/core/capability/transport/.src/claim.rs:377:9:
not taken again
test result: FAILED. 0 passed; 2 failed; 0 ignored; 0 measured; 173 filtered out; finished in 0.00s
```

and each object store's, before:

```text
test tests::two_nodes_listing_one_bucket_never_both_receive_one_object ... ok
test tests::two_locations_of_one_start_listing_one_bucket_never_both_receive_one_object ... FAILED
test result: FAILED. 1 passed; 1 failed; 0 ignored; 0 measured; 18 filtered out; finished in 0.00s
test tests::two_nodes_listing_one_container_never_both_receive_one_blob ... ok
test tests::two_locations_of_one_start_listing_one_container_never_both_receive_one_blob ... FAILED
test result: FAILED. 1 passed; 1 failed; 0 ignored; 0 measured; 16 filtered out; finished in 0.00s
test tests::two_nodes_listing_one_bucket_never_both_receive_one_object ... ok
test tests::two_locations_of_one_start_listing_one_bucket_never_both_receive_one_object ... FAILED
test result: FAILED. 1 passed; 1 failed; 0 ignored; 0 measured; 14 filtered out; finished in 0.00s
```

and after, every test of each crate passing: `xmip-core-transport` 177,
aws-s3 20, azure-blob 18, google-cloud-storage 16, file 33, ftp 18, sftp 28.

Provenance: the owner's choice above. The membership row's process as the
start, drawing it before phase 9, `NodeStart`, `~` and the hexadecimal
digits, and reading a claim of the old form as an earlier start's are the
assistant's, 2026-11-22, for the owner to confirm or strike.
