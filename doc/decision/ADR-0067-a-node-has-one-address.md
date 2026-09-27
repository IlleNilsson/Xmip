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
