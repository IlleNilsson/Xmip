# ADR-0017: Exclusiveness

- Status: Accepted
- Date: 2026-08-25
- Related: ADR-0013 (Journey model), ADR-0016 (submodule composition)

## Context

Exclusiveness is an internal Xmip concern. A Receive Location polling a
directory, a Process draining a queue, a Send Location writing to a share:
each can collide with another instance of itself on another node. Whether it
can is a property of the resource being addressed, not of the wire protocol.
A file is a discrete thing two nodes can both reach for. A SQL query is not.

The manifest carried seven implementation repositories under
`xmip-core-exclusiveness` — `consul`, `etcd`, `redis`, `zookeeper`,
`database`, `file-lock` and `local`. Sitting beside `transport-ftp` and
`transport-kafka` they read as protocol variants, which they never were: they
are places to keep a lease. Worse, five of them imply Xmip needs somebody
else's coordination service in order to say "only one of you at a time".

It does not. Xmip already requires a durable store.

The model in `crates/xmip-exclusiveness` was already right:

```rust
pub enum ExclusivenessScope { Cluster, Node, Process, Resource }
pub enum ExclusiveAction   { Receive, Process, Send }
pub struct ExclusiveOwner  { cluster_name, node_name, host_process_name }
pub struct ExclusiveLease  { acquired_at, expires_at }
pub trait  ExclusivenessStore { … }
```

Scopes and actions. No protocol anywhere. What was missing was the rules that
say when it applies, and who owns the lease.

One word to get right first. This is not locking. A lock protects concurrent
access to shared state: it is taken around a critical section, callers block
on it, and it is released when the section ends. Runtime exclusiveness decides
which running instance owns a unit of work. Nobody blocks on it: a node that
does not get it moves on and looks for other work. It spans the whole unit —
the receive of that file, the run of that Process, that send — not a section
inside it. And it is asserted by a live runtime and kept alive by renewal,
which is why a runtime that stops being live stops being the owner.

That is also why the answer is a lease and not a mutex. A mutex held by a
process that has died is held forever.

## Decision

**1. Receive Locations, Processes and Send Locations are treated alike.**
`ExclusiveAction::Receive`, `::Process` and `::Send` already name the three.
None of them is a special case.

**2. The transport declares whether it is exclusive by default, and the default
follows the resource.** A transport that addresses a discrete claimable
artefact — a file, an FTP or SFTP path, an object in a bucket, a message in a
mailbox — is exclusive by default, because two nodes can both see `order.edi`
and both reach for it. A transport that does not — SQL, a queue, a broker
topic, a listening socket — is not, because there is no artefact to claim and
the endpoint has usually solved it already. Defaulting a Kafka or SQS Receive
Location to exclusive would serialise the one thing built to scale out.

**3. The resource is the artefact, not the location.** A file Receive Location
is exclusive over the individual file, not over the directory it polls. Two
nodes may poll the same directory at the same time and take different files.
Making the location exclusive instead is what leaves the second node with
nothing to do, and is the behaviour this decision exists to avoid.

**3a. The sequence, in order.** A node that has detected an artefact:

1. Check exclusiveness. Held by someone else, move on to the next artefact.
2. Check the resource is not held at the endpoint's own level — for a local
   file or an SMB share, a filesystem lock. A locked file is one another
   process has open, which includes a producer still writing it.
3. Take that endpoint-level lock.
4. Signal exclusiveness.
5. Process.
6. Consume: delete, rename, or move, so the artefact no longer matches the
   Receive Location's configuration and is never detected again.

Exclusiveness first, because it is the Xmip-wide signal and the cheap check.
The endpoint lock second, because it answers a question exclusiveness cannot:
whether something outside Xmip is using the file. The lock is taken before
exclusiveness is signalled so that a node dying between the two leaves nothing
behind — the operating system releases the lock with the process, and no
exclusiveness was ever recorded, so the artefact is simply free again.

Nothing moves at claim time. The artefact is read where it lies and only
changes name or place once it has been consumed.

**3b. Exclusiveness defines the contract; the transport implements it.** Step 2
is protocol knowledge — how to claim an FTP path, whether a blob supports a
lease, what a share-mode open means on this platform. That knowledge belongs in
the transport. `xmip-core-exclusiveness` declares a contract and never learns
what FTP is:

```rust
pub trait ResourceClaim {
    fn is_available(&self, artefact: &ArtefactId) -> Result<bool, ClaimError>;
    fn claim(&self, artefact: &ArtefactId) -> Result<Claimed, ClaimError>;
    fn release(&self, claimed: Claimed) -> Result<(), ClaimError>;
}
```

The alternative — protocol modules inside `xmip-core-exclusiveness` — would
make a Platform service depend on Technology, which `[policy]` forbids:
*"Platform services must not depend on specific Technology repositories."* The
shape here is the one ADR-0012 already uses: the boundary is declared centrally
and implemented outwards.

What each family can offer:

| family | native claim | result |
| --- | --- | --- |
| local file, SMB | share-mode open, mandatory on Windows, advisory on Unix | real endpoint lock |
| Azure Blob | blob lease, renewable | the identical model, used directly |
| S3 | `PUT` with `If-None-Match: *` on a claim key | atomic |
| Google Cloud Storage | generation precondition | atomic |
| POP3 | the session locks the maildrop | free, the protocol is single-consumer |
| SQL | `SELECT … FOR UPDATE SKIP LOCKED` | native, when `exclusiveness = true` |
| FTP, SFTP, IMAP | none. Neither protocol has locking | exclusiveness alone |
| queues and brokers | consumer groups | not exclusive by default at all |

**3c. Where there is no endpoint claim, exclusiveness stands alone.** FTP, SFTP
and IMAP have nothing to offer at step 2, and `is_available` answers true. They
are not made safe by renaming the artefact at claim time: that would put a
second mechanism in the one place clause 3a says nothing moves, to defend
against a non-Xmip client polling the same directory — which no mechanism
defends against anyway. Exclusiveness is cluster-wide and authoritative, and it
is enough. What these transports do need is a stability check, because a
producer still uploading looks exactly like a finished file: an artefact whose
size and timestamp are unchanged across two consecutive listings, or a producer
that writes to a temporary name and renames on completion.

**4. Anything can be made exclusive, whatever its default.** Any Receive
Location, Process or Send Location carries `exclusiveness = true|false`, and
the transport's declared default is only the default. SQL is the obvious case:
a query the operator knows must not run twice is marked `exclusiveness = true`
and Xmip does not argue. Not defaulting to exclusive is not the same as
refusing it.

**5. Exclusiveness is released two ways, and only one of them waits.**
Completing the work releases it immediately and explicitly: the artefact is
processed, the holder gives it up, the next one can be taken at once. A
graceful shutdown does the same. Nothing waits for a timer in the normal
case, or a Receive Location would manage one file per lease duration.

Crashing, being killed, losing the network or being powered off releases it by
expiry instead: the holder stops renewing and the lease lapses. Release is not
an action a dying process has to successfully perform, because a dying process
performs nothing reliably. The lease duration is therefore the worst-case
delay before failed work can be picked up, and nothing else.

**5a. Nobody queues.** A node that asks for exclusiveness already held gets
`AcquireOutcome::TimedOut` and moves on to look for other work. It does not
block, and it does not wait its turn. Exclusiveness answers who owns this, not
who is next.

**6. Released work may be taken by any other node, and is exclusive there
too.** Failover never means two holders. Acquisition goes through the same
boundary key wherever it happens.

**7. Scope is `Cluster`, `Node`, `Process` or `Resource`.** The boundary key
identifies what is being held, not who holds it.

**8. No implementation repositories.** `Process` scope is served by the
in-memory store inside the module. `Cluster` scope is a lease in
`xmip-core-persist`, which Xmip already requires for execution checkpoints and
Journey recovery. Consul, etcd, redis, zookeeper and file locks are removed;
nobody asked for them and each one would make Xmip dependent on another
system's cluster to answer a question about its own.

Several modules inside `xmip-core-exclusiveness` are fine — scopes, the store
contract, the lease — provided none of them is a protocol. And a provider may
ship `xmip-<provider>-exclusiveness` building on the core one, on the same
terms ADR-0012 clause 11 grants the surface modules: their licence, their
support, no approval.

**9. One lease type.** `ExclusiveLease` in `xmip-core-exclusiveness` is the
lease. `RecoveryLease` in `xmip-core-persist` is the same idea under a second
name and folds into it. Two lease types in two modules is how they drift.

## Consequences

- `xmip-core-exclusiveness` gains a dependency on `xmip-core-persist`. Both are
  Platform, so the dependency policy holds: a Platform service must not depend
  on a specific Technology repository, and `persist` is not one.
- Seven repositories are never created. The manifest goes from 301 derived
  names to 294.
- Every transport implementation has to state its default. That is one more
  thing each of the 44 declares, and it is the right place for it: the author
  of the FTP transport knows a remote path is claimable, and the author of the
  Kafka transport knows a consumer group already is one.
- The configuration has to show the effective setting and where it came from.
  An artefact silently running twice, or silently refusing to scale, are both
  failures this exists to prevent, and neither is visible without being shown.
- A single-node installation pays nothing. `Process` scope never reaches the
  store.
- The lease duration and renewal interval become operational settings that
  matter: too short and a busy holder loses work it is still doing, too long
  and failover waits. They belong in `xmip-core-configure` with defaults that
  are safe rather than fast.

## Alternatives considered

**Pluggable coordinators — consul, etcd, redis, zookeeper.** Familiar to
operators who already run them, and battle-tested. Rejected: no one asked, and
it makes Xmip's ability to run one Receive Location depend on a second
distributed system being healthy. Xmip already has a store; a platform that
cannot coordinate itself without external help is a platform with two single
points of failure instead of one.

**Opt-in exclusivity everywhere.** Simpler to implement and surprises nobody
at configuration time. Rejected for artefact-addressing transports: it is
BizTalk's shape of mistake, where the safe behaviour was available and had to
be remembered. The cost of a forgotten opt-in on a file location is
duplicate processing, which is the expensive kind of wrong; the cost of a
forgotten opt-out on a queue is a platform that cannot scale.

**Exclusiveness owned by each transport.** Every implementation decides for
itself, using whatever the protocol offers. Rejected: it puts the same
reasoning in 44 repositories, guarantees they disagree, and leaves an operator
unable to say "make this one exclusive" for a protocol whose author decided it
was unnecessary.
