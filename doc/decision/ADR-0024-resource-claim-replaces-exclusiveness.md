# ADR-0024: A claim at the endpoint, not a lease inside Xmip

- Status: Accepted
- Date: 2026-08-27
- Amended: 2026-09-26 — a file is claimed by an atomic rename
- Amended: 2026-10-01 — a Journey is claimed through Xmip Storage
- Amended: 2026-10-13 — one winner for every Receive Location; the file
  family's claim extends to FTP, FTPS and SFTP
- Amended: 2026-10-19 — a listing claims no more than there is room for; a
  sent file not yet in place is its node's, and its node removes it as it
  starts
- Supersedes: ADR-0017 (Exclusiveness)
- Related: ADR-0010 (contract and transport boundaries), ADR-0012 (the module boundary),
  ADR-0018 (amendment 2026-10-01: a Host Service claims Journeys through the
  Xmip Storage), ADR-0056 (amendment 2026-10-01: the Storage role)

## In brief

- Theme: What Xmip is at runtime
- Subject: A claim at the endpoint, not a lease inside Xmip
- Name: A claim at the endpoint
- Order: 7
- Concepts: Claim, claimable artifact; Exclusiveness, leases, renewal (retired);
  Journey claim
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
as a Journey is claimed. Several nodes may poll one directory; the stability
check stays.

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
  one case. *Closed by the amendment of 2026-10-01: a Journey is claimed
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
every file system offers alike, and the one the Playground's claim already
used. A claim left by a node that is gone and does not start again is not
returned yet: the cluster's half of the recovery is open.

## Amendment, 2026-10-01: a Journey is claimed through Xmip Storage

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
Storage node (`runtime-model.md` section 3). **A Journey is claimed there**:
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

**Provenance.** The owner, 2026-10-13, of the Playground's drop box:
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
| a protocol with no exclusive step at all — IMAP, POP3 | the claim through Xmip Storage, as a Journey is claimed (amendment 2026-10-01) |

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
two receiving nodes over one directory or server, and the Playground's drop
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
- **Refused in words, never guessed.** A Message carrying no `file.name` —
  one received over another transport — or one naming a path rather than a
  file of the directory (`..`, `sub/order.edi`, empty) is refused at the
  send, permanently, and nothing is written. A test or a tool that sends
  bytes it holds, with no Message behind them, names the file itself.
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
saying its name) and by `.src/test/service/carried.rs` in the assembled
service.

Provenance: the ruling is the owner's, 2026-10-19; `file.name`, the `KEPT`
list, handing the context with the body and the refusals' words are the
assistant's, 2026-10-20. What a file Send Location writes for a Message that
carries no file name is open (open problem 33).
