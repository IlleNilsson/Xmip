# ADR-0008: Xmip Entities as Actors

## Status
Accepted.

## Context
ADR-0007 introduced Actors and Communication Domains as the recursive communication model for Xmip.

This does not replace the previously defined Xmip entities. Receive Ports, Receive Locations, Processes, Send Ports, Send Locations, Handlers, Nodes, Host Processes, Clusters and related artifacts remain part of the Xmip architecture.

## Decision
Previously defined Xmip entities are Actors when they communicate, publish, subscribe, own work, report status, or transfer responsibility.

They are not removed or renamed away. They gain actor semantics.

## The mapping, in one table

Folded in from `docs/planning/artifact-actor-mapping.md` on 2026-08-30 — the
table said in nine lines what the examples below say in prose, and a mapping
belongs in the record that decided it.

```text
Receive Location -> Actor reporting to Receive Port
Receive Port     -> Actor owning received message until ownership transfer
Process          -> Actor that may orchestrate, assign, transform, publish or subscribe
Send Port Group  -> Actor grouping related send ports
Send Port        -> Actor owning send-side preparation and delivery decisions
Send Location    -> Actor performing actual target delivery
Handler          -> Actor when executing or reporting capabilities
Node             -> Actor inside Cluster
Cluster          -> Actor inside a larger domain
```

## Examples
A Receive Location is an Actor that receives external input and reports to its parent Receive Port.

A Receive Port is an Actor that owns the message after receive until another Actor takes ownership of the message, or until a new derived message is created by assignment or transformation.

A Process is an Actor that may take ownership of a message, perform orchestration, create assignments, create transformed messages, publish, subscribe, or route.

A Send Port is an Actor that owns send-side preparation and delivery decisions.

A Send Location is an Actor that performs actual target delivery and reports result back to its Send Port.

A Handler is an Actor when it participates in runtime communication, execution, capability reporting, or delivery.

A Node is an Actor inside a Cluster.

A Cluster is an Actor inside a larger Xmip or organizational domain.

## Message ownership
A message has an owning Actor at each stage of its lifecycle.

Ownership may transfer between Actors.

Assignments and transformations do not mutate a message. They create a new message form with a new messageId and the same interchangeId. The new message form may have a new owning Actor.

The old message remains immutable and auditable.

## Receive analogy
A Receive Location is like a crew member reporting to a Captain.

The Receive Port is the Captain of the message after receive.

Later Actors may take ownership of the message or a derived form of the message.

## Rule
Actor semantics must not erase Xmip artifact semantics.

Xmip artifacts remain explicit, named, versioned, configurable and deployable.

Actor semantics explain how those artifacts communicate and transfer responsibility.
