# Xmip Audit Architecture

Status: Agreed architectural decision

## Purpose

Auditing is a cross-cutting Xmip capability. Every architectural action is auditable, including Receive, Prepare, Contract resolution, validation, Path execution, Promotion, Demotion, Routing, Assignment, Transformation, Process, Send, authentication, authorization, resilience, exclusiveness, persistence, observation, reporting and external event delivery.

Auditing is not a stage placed before or after the execution chain. It is available throughout the whole chain.

## Audit lifecycle

Every audited action follows one of two lifecycles:

```text
Begin
  -> Execute
  -> Finished
```

or:

```text
Begin
  -> Execute
  -> Failure
```

`Finished` and `Failure` are mutually exclusive for the same execution attempt.

## Severity

Audit severity is independent from lifecycle phase:

```text
Information
Warning
Error
```

- `Information` records normal execution and successful completion.
- `Warning` records a recoverable, degraded or exceptional condition where execution may continue or complete.
- `Error` records failure or a condition that prevents execution from continuing.

Examples:

```text
Transform / Begin / Information
Transform / Execute / Information
Transform / Finished / Information
```

```text
Send / Begin / Information
Send / Execute / Warning
Send / Finished / Warning
```

```text
Process / Begin / Information
Process / Execute / Error
Process / Failure / Error
```

## Configuration hierarchy

Every Xmip action is auditable, but the effective audit policy determines what is recorded.

Audit policy is configurable from broad scope to the most specific scope:

```text
Xmip
  -> Cluster
  -> Node
  -> Artifact type
  -> Artifact
  -> Action
  -> Phase
  -> Severity
```

The most specific configured policy wins. Unspecified settings inherit from the containing level.

The policy may select:

- enabled or disabled;
- lifecycle phase: Begin, Execute, Finished or Failure;
- severity: Information, Warning or Error;
- action type;
- artifact type;
- individual artifact;
- node;
- cluster;
- detail level;
- sampling or throttling for high-volume Information records.

This allows configurations ranging from detailed Path execution auditing on one development artifact to Error-only auditing for high-volume production artifacts.

## Performance and delivery

Auditing must not unnecessarily become the execution bottleneck.

Normal execution should emit a small audit envelope to a bounded asynchronous channel. `xmip-audit` may batch and persist audit records independently from the action that produced them.

When audit capacity is exhausted, configured policy determines whether Xmip:

- discards selected Information records;
- reduces audit detail;
- throttles or samples records;
- blocks the audited action;
- fails the audited action.

Warning and Error records normally require stronger delivery guarantees than Information records.

Some conditions may be configured as non-suppressible, including audit subsystem failure, security-critical failure, configuration corruption and persistence failure that risks loss of required audit evidence.

## Ownership

`xmip-audit` owns:

- the audit record model;
- lifecycle phases;
- severity;
- policy definition and resolution;
- audit envelopes;
- buffering and back-pressure behavior;
- audit persistence contracts;
- querying and inspection contracts.

Each other Xmip module reports its action lifecycle and outcome through the `xmip-audit` public contract. Individual modules do not invent incompatible audit models or persistence mechanisms.

## Invariant

> Every Xmip action is auditable. What is actually recorded is determined by the effective audit policy from Xmip scope down to the individual action, lifecycle phase and severity.
