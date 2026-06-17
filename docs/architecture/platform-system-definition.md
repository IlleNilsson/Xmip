# Xmip Platform System Definition

Xmip is not an application.

Xmip is a distributed integration platform system.

Modern wording: Xmip is a platform.

System wording: Xmip is a distributed system running across servers, nodes, clusters, edge locations, and purpose-built endpoint runtimes.

## Platform responsibility

Xmip owns platform-level behavior:

- distributed runtime execution,
- stream-first message handling,
- inter-node and inter-cluster communication,
- persistence and replay,
- audit, tracing, and tracking,
- handler loading and execution,
- process execution,
- send port execution,
- management and monitoring,
- deployment and desired state configuration.

## Distributed responsibility

Xmip runs distributed across servers.

A node participates in a cluster.

A cluster owns its runtime persistence and management state.

Nodes coordinate work according to capability, configuration, identity, and policy.

## Rule

Documentation and code comments shall avoid describing Xmip as a simple application.

Xmip shall be described as:

- a platform,
- a distributed system,
- an integration runtime platform,
- or an integration platform system.
