# Xmip.Process

`Xmip.Process` is an Xmip runtime artifact.

It is not a generic operating-system process.

It is not a human or organizational process unless that real-world process is represented by Xmip configuration and runtime state.

## Core rule

```text
Xmip.Interchange flows through Xmip.Process.
Xmip.Process owns state.
Xmip.Interchange owns lineage.
Xmip.Message owns data.
```

A Process consumes Messages and may produce new Messages.

When a Process produces a new Message, Xmip creates a child Interchange and appends it to the Message's Interchange Chain.

## Xmip.Process.Definition

`Xmip.Process.Definition` is the TOML-defined process artifact.

It declares:

- process name,
- stages,
- expected incoming messages,
- expected awaited responses,
- correlation rules,
- possible outcomes,
- timeout behavior,
- retry behavior where applicable,
- audit/tracing/tracking settings,
- extension usage where applicable,
- send/receive artifact usage where applicable.

The definition does not execute by itself.

## Xmip.Process.Instance

`Xmip.Process.Instance` is the runtime execution of a Process Definition.

It is created when a subscription or configured entry point starts a process for a Message.

A Process Instance may:

- receive a Message,
- update Process State,
- create assignments,
- create transformations,
- call Extensions,
- use other Artifacts,
- send requests,
- wait for responses,
- resume when correlated messages arrive,
- timeout,
- complete,
- fail,
- cancel.

A Process Instance is auditable.

A Process Instance is persisted through cluster persistence.

A Process Instance must not rely on thread, host process, or node memory as its source of truth.

## Xmip.Process.State

`Xmip.Process.State` is the persisted state of a Process Instance.

It contains the information required to continue the Process after:

- wait,
- timeout,
- host restart,
- node restart,
- node failure,
- failover,
- recovery.

Process State belongs to cluster persistence.

Execution ownership may move between valid nodes.

The state does not move because it already belongs to the cluster.

## Xmip.Process.Stage

`Xmip.Process.Stage` is a named state or phase inside a Process Instance.

Stages are not required to be linear.

A Process may move forward, wait, resume, branch, revisit earlier logic, or reach different outcomes depending on received messages, timeouts, and decisions.

## Xmip.Process.Outcome

`Xmip.Process.Outcome` is the terminal or intermediate result of process execution.

Typical terminal outcomes:

```text
Completed
CompletedWithWarnings
Failed
Cancelled
TimedOut
Abandoned
```

Intermediate outcomes may create new Messages and therefore child Interchanges.

## Process and Interchange relationship

A Process does not replace Interchange tracking.

The Interchange Chain travels through the Process.

When the Process creates new work, Xmip creates new child Interchanges.

Example:

```text
Receive
    Message M1
    Interchange I1

Process P1 starts
    consumes M1 / I1

Process P1 sends request
    creates Message M2
    creates Interchange I1 -> I2

Response arrives
    Message M3
    Interchange I1 -> I2 -> I3

Process P1 resumes
    updates Process State

Process P1 completes
    produces final outcome
```

## Boundary rule

`Xmip.Process` owns state.

`Xmip.Interchange` owns lineage.

`Xmip.Message` owns immutable data.

`Xmip.Artifact.Instance` performs work.

No thread, host process, or node owns durable process truth.
