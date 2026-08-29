# ADR-0024: A claim at the endpoint, not a lease inside Xmip

- Status: Accepted
- Date: 2026-08-27
- Supersedes: ADR-0017 (Exclusiveness)
- Related: ADR-0010 (contract and transport boundaries), ADR-0012 (the module boundary)

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
    fn is_available(&self, artefact: &Artefact) -> Result<bool>;
    fn claim(&self, artefact: &Artefact) -> Result<Claimed>;
    fn release(&self, claimed: Claimed) -> Result<()>;
}
```

**The endpoint is one thing however many nodes are asking.** A claim taken
there is cluster-wide without a lease, a store, or anything for Xmip to keep
consistent across nodes — because the shared write path is the partner's
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

### 4. The artefact, not the location

Carried unchanged from ADR-0017 clause 3, because it was right. A file Receive
Location claims the individual file, never the directory it polls. Two nodes may
poll one directory at the same time and take different files; claiming the
directory is what leaves the second node with nothing to do.

### 5. Where a protocol has no claim, it says so

FTP, SFTP and IMAP have no locking. `NoNativeClaim` is that answer in the type
rather than three stubs written per transport, one of which eventually returns
something else.

They are **not** made safe by renaming the artefact at claim time — ADR-0017
clause 3c, and it still holds. That puts a second mechanism in the one place
nothing is supposed to move, to defend against a non-Xmip client polling the
same directory, which no mechanism defends against anyway.

What they need is a **stability check**: an artefact whose size and timestamp
are unchanged across two consecutive listings, or a producer that writes to a
temporary name and renames on completion.

### 6. Two nodes on a lockless protocol is a placement question

With no lease and no native claim, nothing stops two nodes polling the same
SFTP directory from both taking `order.edi`.

**That is answered by running one of them, not by locking.** It is a
configuration decision about where a Receive Location executes, and it belongs
with Host Services in ADR-0018 rather than in a coordination service. Xmip does
not need a distributed lock to express "this Receive Location runs here".

The shape of that placement is not decided by this record. What is decided is
that it is a placement question and not a locking one.

### 7. The sequence, simplified

ADR-0017 clause 3a had five steps and an ordering argument about which of two
mechanisms to signal first. With one mechanism there is no ordering to get
wrong:

```text
1. Claim the artefact at the endpoint. Refused, move to the next artefact.
2. Process.
3. Consume: delete, rename or move, so it no longer matches the Receive
   Location's configuration and is never detected again.
```

Nothing moves at claim time. The artefact is read where it lies.

A node that dies mid-claim leaves nothing behind: the endpoint releases its own
claim on its own terms — a closed handle, an expired blob lease, a rolled-back
transaction — and the artefact is simply free again. That is the same property
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
  `xmip-core-transport` instead: a schedule that fires and finds the artefact
  already claimed moves on, which is the same behaviour with nothing to
  coordinate.
- `Transport` gains `claims()`, defaulting to `None`. A listening socket or a
  broker topic has no artefact to claim and correctly answers nothing.
- Open problem 18 is closed. Not answered — **dissolved**. There is no
  cluster-scope lease to place because there is no lease.
- `RecoveryLease` in `xmip-core-persist` stops being the second of two lease
  types, since there is no longer a first. ADR-0017 clause 9 folded them the
  other way round; that folding is now unnecessary.
- **Journey recovery across nodes is left open, and this record does not close
  it.** `deployment-model.md` said the same Journey must never be recovered by
  two nodes at once and pointed at ADR-0017's cluster lease for the guarantee.
  Claiming an artefact settles arrivals and settles nothing here: a Journey
  mid-flight is Xmip's own state and has no endpoint to claim it at. It is the
  same problem as *work does not move by itself* — a Message in node A's ToDo is
  node A's work — under a second name, and it belongs with however that is
  eventually designed rather than with a lease reinstated for one case.
- The acquisition queue, fairness and acquisition timeout of ADR-0017 clauses 13
  and 14 go too. Nothing queues for an artefact: a node that finds one claimed
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
