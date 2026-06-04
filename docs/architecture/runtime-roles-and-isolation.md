# Xmip Runtime Roles and Isolation Boundaries

## Purpose

This document defines a reduced runtime role model and the isolation principle used to reduce cross-process infection risk.

Runtime roles describe what a Xmip runtime component is trusted or allowed to do.

They do not describe every concrete capability.

Concrete capabilities are supplied by modules and Artifact Definitions.

## Runtime role model

Xmip starts with three runtime roles:

```text
Executor
Reader
Writer
```

These roles may be combined depending on deployment target and trust boundary.

## Executor

An Executor runs Artifact Instances and performs Xmip work.

Examples of work include:

- receive,
- deserialize,
- transform,
- promote,
- publish,
- process/orchestrate,
- serialize,
- send.

Executor does not mean unrestricted access.

Executor permissions must be scoped by trust boundary and isolation boundary.

## Reader

A Reader can inspect runtime state.

Examples include:

- message context,
- artifact state,
- lineage,
- logs,
- metrics,
- health,
- publication history,
- Subscription Instance history.

Reader must not execute artifact behavior merely because it can observe runtime state.

## Writer

A Writer can change runtime state or operational outcome.

Examples include:

- claim work,
- checkpoint,
- preserve state,
- acknowledge,
- retry,
- resume,
- suspend,
- terminate,
- move a message,
- change operational state.

Writer does not imply permission to load or execute arbitrary module code.

## Capabilities are not runtime roles

Do not create one runtime role for each capability.

The following are capabilities or responsibilities, not core runtime roles:

- receive host,
- send host,
- process host,
- preservation host,
- recovery coordinator,
- cluster coordinator.

These may be implemented by Artifact Instances, modules, deployment profiles, or operational responsibilities, but they do not change the reduced role model.

## Deployment target examples

A small edge deployment may combine roles in one runtime component:

```text
Edge node = Executor + Reader + Writer
```

A monitoring component may only need:

```text
Monitor component = Reader
```

A recovery component may need:

```text
Recovery component = Reader + Writer + Executor
```

A cloud worker may need:

```text
Cloud worker = Executor + Writer
```

These are deployment choices, not separate runtime models.

## Isolation boundary

Runtime roles do not solve cross-process infection risk by themselves.

Xmip also needs isolation boundaries.

A core principle is:

```text
Executor is not one trust level.
Executor is scoped by isolation boundary.
```

Untrusted or less-trusted modules should run in isolated processes, containers, sandboxes, or equivalent isolation mechanisms.

Artifact Instances should not share process memory unless explicitly trusted to share that boundary.

## Trust boundary rules

Initial trust rules:

1. Reader cannot execute artifact behavior.
2. Writer cannot load arbitrary module code.
3. Executor cannot automatically affect other Executors.
4. Untrusted modules run isolated.
5. Artifact Instances share process memory only within an explicit trust boundary.
6. Inbound and outbound permissions must be explicit.
7. Edge deployments should use the smallest practical permission and isolation footprint.

## Human roles are separate

Runtime roles are separate from human/user roles.

Human roles include, but are not limited to:

- Monitorer,
- Operator,
- Developer,
- Administrator,
- Architect.

A scoped human role such as Edge Operator may exist later, but it should be treated as a scoped Operator role rather than a new universal role.

## Summary

Runtime role answers:

```text
What may this runtime component do?
```

Trust boundary answers:

```text
What may it touch?
```

Isolation boundary answers:

```text
What can it infect if compromised?
```
