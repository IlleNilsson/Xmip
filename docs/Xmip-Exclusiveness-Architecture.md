# Xmip Exclusiveness Architecture

Status: Frozen architectural baseline

## Purpose

`xmip-exclusiveness` coordinates temporary exclusive access required by Receive, Xmip Process and Send work.

Exclusiveness is a scope, not a Boolean value:

```text
Cluster
Node
Process
Resource
```

A task declares its scope and exclusiveness key. When exclusiveness cannot be acquired immediately, the task is durably queued until it acquires exclusiveness or its configured acquisition timeout is reached.

## Responsibilities

`xmip-exclusiveness` owns:

- acquisition queues;
- atomic acquisition and release;
- leases and renewal;
- fairness;
- acquisition timeout;
- ownership transitions.

Receive, Xmip Process and Send declare the requirement and execute only after acquisition. `xmip-exclusiveness` never executes their work.

## Task states

```text
Requested
Queued
Acquired
Executing
Succeeded
TimedOut
LeaseLost
Failed
Cancelled
```

## Fairness

The default is first eligible queued task first. Priority may affect eligibility but must not cause permanent starvation.

## Frozen principle

> Receive, Xmip Process and Send may require exclusive execution at Cluster, Node, Process or Resource scope. When exclusiveness is unavailable, Xmip durably queues the task until exclusiveness is acquired or the configured acquisition timeout is reached.
