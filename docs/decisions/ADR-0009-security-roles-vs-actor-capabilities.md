# ADR-0009: Security Roles vs Actor Capabilities

## Status
Accepted.

## In brief

- Theme: Identity and security
- Subject: Security roles are not Actor capabilities
- Name: Security roles versus Actor capabilities
- Order: 4
- Concepts: Security roles; Observer, a read-only role

Two separate concepts that look alike and are constantly conflated. A security
role is what a human or Service Identity is permitted to do. An Actor capability
is what a runtime entity is able to do. Neither implies the other.

## Decision

Xmip security roles and actor capabilities are separate concepts.

## Security roles

Xmip user/security roles remain:

```text
Observer
Operator
Developer
```

These describe what a user or security principal may do in Xmip, least first.

## Actor capabilities

Actor capabilities describe what an Actor can do in communication and runtime execution.

Examples:

```text
Publish
Subscribe
OwnMessage
Report
Command
Execute
Route
Transform
Send
Receive
```

These are not user/security roles.

## Rule

Do not call actor capabilities roles.

Do not mix user/security authorization with runtime communication capability modeling.

A Receive Port can have the capability OwnMessage.

A user can have the role Operator.

Those are different dimensions.

## Amendment, 2026-09-06: the Observer role

The role set gains **Observer**, the least-privileged role: a principal who may
**watch and not act**. An Observer reads every monitoring surface — cluster
health, drill-down, history, recent activity — and performs no configuration and
no execution.

The owner's observation, 2026-09-06: the desktop Application offers **Monitor**
and **Configure**, and both are ways to interact, so the role set needs one that
observes only. It did — Operator was the floor, and Operator acts.

This aligns the roles with a distinction the estate already drew elsewhere.
ADR-0027 separates **observing from configuring at the boundary** — "an observer
watches, a configurer acts" — the read-only `XmipOperate` table versus the
separate configuration symbols. That was a distinction in the *code*; Observer
makes it a distinction in *who is at the keyboard*.

Mapped to the operator surfaces (ADR-0014):

| Surface | Observer | Operator |
| --- | --- | --- |
| Web (monitoring only) | yes | yes |
| Desktop **Monitor** | yes | yes |
| Desktop **Configure** | no | yes |

The roles are cumulative in what they may read and do: Observer watches;
Operator also configures; Developer also builds. Each includes what the one
before it can do.

The set is three — **Observer, Operator, Developer** — the owner's wording,
2026-09-06. The former **Executer** security role is retired: running work is a
node's job, described by the **Executor** *node role* (Reader / Writer /
Executor, `deployment-model.md`), not something a person is granted. The two were
one letter apart and one idea apart; only the node role remains.

**Shown and assigned, not yet identity-gated.** The role is **assigned, never
chosen in the UI** — a person cannot promote themselves. The desktop
(Xmip.Operations) reads its role from configuration (`Xmip:Role`, defaulting to
Observer so a missing value grants nothing) and shows it as a read-only badge; it
offers Configure only to an Operator and up, and an Observer who reaches
`/configure` directly is sent back to Monitor. The web surface, being monitoring
only (ADR-0014), is always Observer. This makes the concept real — an Observer
cannot configure — with the assigned role standing in until a proven identity
gates it (ADR-0022/ADR-0027).

**Not yet enforced.** No surface gates on role today — a surface holding runtime
state in-process is a host process, and ADR-0022 clause 3 with the identity
question ADR-0027 flags as *blocking shipping* must be settled before a role is
enforced rather than merely defined. This records the role and its surface map;
the gate is future work behind that settlement.
