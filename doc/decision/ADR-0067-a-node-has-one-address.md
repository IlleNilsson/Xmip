# ADR-0067: A node has one address, and its planes are listeners on it

- Status: Accepted
- Accepted: 2026-09-26, the owner, after discussion
- Date: 2026-09-26
- Related: ADR-0018 (service and host), ADR-0045 (offline is the default),
  ADR-0063 (Xmip encrypts its traffic), ADR-0065 (a subscriber hears the
  cluster), open problem 17 (how work reaches another node)

## In brief

- Theme: What Xmip is at runtime
- Subject: How many network addresses a node needs, and which
- Name: A node has one address
- Order: 17
- Concepts: Node address; listener; plane; alive; sync; operate; second link

**A node needs one IP address, and by default it is the host's own. Its
planes — operate (the operator surfaces), sync (node to node: claims, state,
Events) and alive (the heartbeat) — are separate listeners on that address,
each its own port and socket, so none waits behind another. An operator may
give Xmip a dedicated address, or any listener its own, and may add a second
link for the heartbeat; nothing requires either. There is no floating cluster
address: the cluster is reached through a name that lists its nodes, and any
node answers.**

## Context

The owner, 2026-09-26, proposed three addresses per node — the node, sync and
alive, and events — and asked to be argued with: *I'm a cluster guy and
tainted.* The classic failover cluster keeps its heartbeat on its own network
so traffic cannot starve it. The assistant argued that the separation that
matters is of sockets, not addresses; that a separate heartbeat network lets a
node answer beats while its data path is dead, alive but unable to work and
holding its claims; and that three addresses break the container, the hosted
virtual machine and the laptop running the Playground. Events belong to the
cluster, not a node (ADR-0065). The owner: *so let's go with one IP*, and, of
the host's address or an additional one, agreed the host's by default.

## Decision

### 1. One address, the host's by default

A node listens on one IP address. Unless configured otherwise it is the
host's own; nothing extra is assigned to run Xmip. Several nodes on one host
are told apart by port.

### 2. The planes are listeners

Operate, sync and alive are separate listeners on that address, each with its
own port and socket. The heartbeat is tiny and never shares a connection with
sync or payload traffic, so a large transfer cannot make a healthy node look
dead. Receive Locations keep the endpoints their technologies configure; they
are the node's work, not its planes. Every plane rides Xmip's TLS (ADR-0063).

### 3. Separation and redundancy are the operator's to add

An operator may give Xmip a dedicated address, or put any listener on its own
address or network. For the one real risk a single address carries — one
network card or switch — the heartbeat may be given a second link the cluster
uses when the first fails. Neither is required.

### 4. No floating cluster address

A subscriber or an operator reaches the cluster through a name that lists its
nodes; whichever answers serves the request. A virtual address moved between
nodes would depend on the platform and the network, which a running Xmip does
not (ADR-0045).

## Consequences

- The node configuration names one address (default: the host's) and a port
  per plane; the second heartbeat link is an optional entry.
- The node-to-node protocol (problem 17, option A) is the sync listener.
- The operator surfaces show a node's address and its planes' ports.

## Provenance

**The owner's**, 2026-09-26: one IP; the host's by default, a dedicated one
optional.

**The assistant's**: the argument in Context, the three planes' names, the
second heartbeat link and the cluster reached by a name that lists its nodes
— each the owner's to strike.

## Built, 2026-10-12: the operate listener

The operate plane is built (ADR-0014, amendment 2026-10-12):
`xmip-core-runtime`'s `plane::Listener`, gRPC on the estate's own HTTP/2
inside Xmip's mutual TLS, answering the node's publication, a wait on its
next revision and an operator's acts, each admitted by the role the node's
`[operate] role` grants the subject of the caller's certificate, and
audited. `xmip-service` starts it from `[operate]` (`listen`,
`certificate`, `key`, `anchors`, `role`) and refuses to start where it
cannot listen; a node whose `[operate]` names no `listen` serves no
network listener. The address and port are the configuration's; no port is
assumed.

Built 2026-10-13 (ADR-0014, amendments of that date): the operate plane also
listens on the node's own machine, always, at a local endpoint named
`xmip-<node>` unless `[operate] local` names it — a named pipe on Windows, a
Unix domain socket in `/run/xmip` on Linux and `/var/run/xmip` on macOS —
which is no address on the network and needs none of clause 1's.

## Amendment, 2026-10-13: a listener per purpose, always; an address per purpose where the network has one

**Amends clauses 2 and 3.** Decided by the owner, 2026-10-13: *Each node
has separate listeners per purpose — IT operators (the operating system's:
SSH, PowerShell Remoting, Remote Desktop), Xmip operators (operate), the
heartbeat (alive), Xmip Storage, node to node (sync) — and the Receive and
Send Locations for communication. Separate addresses where the network
allows; separate listeners always (ADR-0067). The local pipe stays the
service account's and Administrators'.* And of a beginner's machine, the
same day: *For a beginner setup we can't demand mulitple IP adresses, port
segmentation have to due.*

- **A listener per purpose, always.** IT operators reach the machine on
  the operating system's own listeners — SSH, PowerShell Remoting, Remote
  Desktop — which Xmip neither serves nor replaces. Xmip operators reach
  the node on operate, the heartbeat is alive, Xmip Storage is its own
  listener, node to node is sync, and the Receive and Send Locations keep
  the endpoints their technologies configure. No two of them share a
  listener.
- **The default is one address and a port per purpose**: Xmip operators,
  the heartbeat, Storage, node to node and the ACME challenge each on its
  own port of the node's one address, which a beginner's machine with a
  single address always satisfies. Clause 1 stands as that default.
- **Separate addresses are an option, never required**: where the network
  has them, an operator puts any purpose on an address — or a network — of
  its own. Nothing in Xmip demands one.
- **The local endpoint stays the service account's and Administrators'**
  (ADR-0014, amendment 2026-10-13): the operate plane's local endpoint, a
  named pipe or a Unix domain socket, admits the node's account, the
  system and the machine's administrators, and is no address on the
  network.
- **The sections are shaped alike** — decided by the owner, the same day:
  *`[operate]` keys kept (`listen`, `certificate`, `key`, `anchors`,
  `role`, `local`); `[sync]`, `[alive]` and `[storage]` sections shaped
  the same.* Each purpose's section names where it listens and what it
  presents and trusts, as `[operate]` does.

**Built**: the operate plane, its local endpoint always (ADR-0014,
amendment 2026-10-13, *the local endpoint always starts*) and its network
listener where `[operate] listen` names one. **Decided, not built**: the
sync, alive and Storage listeners and their sections
([`node-listeners`](../architecture/estate-map.md#node-listeners)).

Provenance: the owner's decisions, quoted, and the default of one address
with a port per purpose — the ACME challenge among them — as his beginner
ruling was recorded the same day; the wording of the bullets is the
assistant's, for the owner to overrule.

## Amendment, 2026-10-22: the Storage listener is built

The Storage listener of the amendment of 2026-10-13 is built, its section
shaped as `[operate]` is: `[storage] listen`, the node's address and the
Storage plane's port, where a node declaring the Storage role serves Xmip
Storage to the nodes reaching it; `certificate`, `key` and `anchors`, all
three or none, what the node presents and trusts over Xmip's mutual TLS —
serving, and reaching the Storage nodes `[storage] nodes` lists. A node
without the Storage role reads no `listen`, so one cluster-wide `[storage]`
table serves every node of a cluster's file. `xmip-service --listening`
says `<port>/tcp storage` for a node with the role, so an environment opens
its firewall for it (ADR-0015, amendment 2026-10-21). The one reading of a
plane's certificate, key and anchors is the runtime's `presented::identity`,
which `[operate]` and `[storage]` both read through; `[sync]` and `[alive]`
stay decided, not built
([`node-listeners`](../architecture/estate-map.md#node-listeners)). The
assistant's, 2026-10-22 (ADR-0056, amendment of this date).
