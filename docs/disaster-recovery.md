# Disaster and Recovery

Xmip must be able to recover work after failure.

Xmip runs on computers. A computer has System Processes. The long-running System Process for the platform is the Xmip Service. The Xmip Service starts Host Processes and starts or resumes Xmip Processes according to configuration and Events.

An Xmip Process may be short-lived or may represent a journey over time. It may wait for more information, decisions, replies, timeouts, or other Events.

## Recovery principle

The Interchange travels through Xmip regardless of routing, processing, waiting, retries, or time.

Messages are immutable and reference immutable streams. Assignments and transformations create new Messages and new streams only when content changes. The Interchange continues to travel with the work until it leaves Xmip and the travel has been audited.

## Persistent state

Xmip must persist enough information to resume safely:

```text
Interchange state
    where the journey is

Checkpoint
    last safe execution point

Wait conditions
    what Events or correlations the journey is waiting for

Recovery lease
    which node is currently recovering the Interchange

Deduplication record
    which incoming source fingerprints and Messages were already accepted

Audit position
    how far the travel has been audited
```

## Recovery flow

```text
Xmip Service starts
    -> read configuration
    -> validate execution tree
    -> load modules
    -> register capabilities
    -> scan persisted active/waiting/suspended Interchanges
    -> acquire recovery lease per Interchange
    -> restore checkpoint
    -> resume or keep waiting
    -> continue audit
```

## Cluster rule

Recovery is cluster-scoped. Any capable node in the cluster may resume work if it can satisfy the required capabilities and acquire the recovery lease.

The same Interchange must not be recovered by multiple nodes at the same time.

## Failure rule

Xmip cannot own every bad decision in configuration or custom code, but it must mitigate avoidable loss:

- persist before acknowledging external completion where required,
- checkpoint before waiting,
- checkpoint before externally visible side effects when possible,
- use deduplication when receive or failover can replay work,
- audit the journey of the Interchange.
