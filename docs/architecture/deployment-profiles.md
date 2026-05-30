# Xmip Deployment Profiles

Xmip must support a broad deployment range without changing the core runtime semantics.

The kernel remains the same. The loaded modules, persistence providers, observability providers, and cluster capabilities vary by deployment profile.

## Deployment range

Xmip must be able to run as:

```text
IoT device
Edge node
Single on-prem server
On-prem server cluster
Cloud node
Cloud cluster
Hybrid on-prem/cloud
```

The same runtime laws apply across all profiles:

- receiveLocation is where Xmip starts working,
- receivePort binds incoming streams into Xmip topology,
- analyze/detect format precedes deserialization,
- deserialization precedes property promotion,
- promoted properties drive publish/subscription,
- process and delivery paths are subscription-driven,
- sendPort resolves to sendLocation(s),
- preservation, lineage, checkpoints, logging, and recovery span the runtime.

## Profile: IoT device

Smallest possible deployment.

Intended for constrained hardware or embedded/industrial gateway scenarios.

May include:

- Xmip kernel,
- one receive module,
- one analyzer/deserializer/promoter module,
- one send module,
- local preservation/checkpoint provider,
- minimal observability.

Should not require:

- cluster coordination,
- full process/orchestration engine,
- broad adapter catalog,
- heavy database server,
- cloud services.

## Profile: Edge node

A small but more capable node close to systems or devices.

May include:

- Xmip kernel,
- multiple selected receive/send modules,
- local or lightweight embedded persistence,
- limited process execution,
- local observability export,
- optional buffering for intermittent connectivity.

Should remain deployable without full cluster services.

## Profile: Single on-prem server

A standalone server deployment for enterprise integration workloads.

May include:

- Xmip kernel,
- multiple receive and send modules,
- process/orchestration modules,
- transformation modules,
- stronger persistence provider,
- local operational reporting,
- observability exporters.

This profile must be useful without requiring a cluster.

## Profile: On-prem server cluster

A multi-node on-prem deployment.

May include:

- Xmip kernel on each node,
- cluster persistence provider,
- lease/claim coordination,
- recovery orchestration,
- deterministic placement,
- host/process isolation,
- shared preservation model,
- distributed observability.

The cluster owns execution truth. Nodes are temporary execution hosts.

## Profile: Cloud node

A single cloud-hosted runtime node.

May include:

- Xmip kernel,
- selected cloud-compatible receive/send modules,
- cloud identity integration,
- cloud persistence provider,
- cloud observability exporter.

This profile should not require distributed cluster semantics unless explicitly configured.

## Profile: Cloud cluster

A distributed cloud deployment.

May include:

- cluster coordination,
- cloud persistence,
- distributed recovery,
- scaling/placement modules,
- cloud observability,
- cloud identity and secret providers.

The cloud cluster profile must not redefine kernel semantics.

## Profile: Hybrid on-prem/cloud

A mixed deployment where on-prem nodes and cloud nodes participate in a broader topology.

May include:

- on-prem server or on-prem cluster,
- cloud node or cloud cluster,
- explicit trust boundaries,
- explicit connectivity boundaries,
- preservation and recovery semantics appropriate to the boundary.

Hybrid does not mean implicit shared trust. Boundaries must be explicit.

## Architectural rule

A deployment profile selects modules.

A deployment profile does not redefine Xmip.

The same Xmip execution semantics must remain valid from IoT device to on-prem cluster to cloud cluster.
