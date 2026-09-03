# ADR-0009: Security Roles vs Actor Capabilities

## Status
Accepted.

## In brief

- Theme: Identity and security
- Subject: Security roles are not Actor capabilities
- Name: Security roles versus Actor capabilities
- Order: 4
- Concepts: Security roles

Two separate concepts that look alike and are constantly conflated. A security
role is what a human or Service Identity is permitted to do. An Actor capability
is what a runtime entity is able to do. Neither implies the other.

## Decision

Xmip security roles and actor capabilities are separate concepts.

## Security roles

Xmip user/security roles remain:

```text
Developer
Operator
Executer
```

These describe what a user or security principal may do in Xmip.

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
