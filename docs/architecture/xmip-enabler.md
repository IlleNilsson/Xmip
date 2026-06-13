# Xmip.Enabler

`Xmip.Enabler` replaces the old term `Artifact`.

This is primarily a terminology and mental-model change.

An Enabler is a configured Xmip capability that enables runtime work.

## Core terms

```text
Xmip.Enabler.Definition
Xmip.Enabler.Instance
```

## Xmip.Enabler.Definition

An Enabler Definition is a named Xmip configuration object defined in TOML.

It declares:

- enabler name,
- enabler kind,
- Handler reference where applicable,
- Handler configuration where applicable,
- runtime-affecting configuration values,
- contracts or contract references where applicable,
- security requirements where applicable,
- audit, tracing, and tracking settings where applicable.

An Enabler Definition describes what a node can handle.

An Enabler Definition does not process a message by itself.

## Xmip.Enabler.Instance

An Enabler Instance is the runtime execution of an Enabler Definition.

An Enabler Instance is created when Xmip runtime uses an Enabler Definition to handle a specific message, stream, action, or execution scope.

An Enabler Instance handles the message it was given.

An Enabler Instance is auditable and may be traceable and trackable according to policy.

Runtime persistence records Enabler Instance state, outcome, failure, retry, and recovery information where applicable.

## Enabler kinds

Examples of Enabler kinds:

```text
Xmip.Receive.Port
Xmip.Receive.Location
Xmip.Subscription
Xmip.Process
Xmip.Send.Port
Xmip.Send.Location
Xmip.Contract
```

## Retired term

`Artifact` is retired.

Use `Enabler`.

```text
Artifact Definition -> Enabler Definition
Artifact Instance   -> Enabler Instance
```

## Rule

Where older documents or code still use `Artifact`, they should be treated as legacy wording and renamed to `Enabler` as the architecture is consolidated.
