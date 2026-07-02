# Xmip Submodule Architecture

Submodules follow stable responsibility boundaries.

## Core runtime repositories

```text
Xmip
    Architecture, ADRs, kernel prototype and integration tests.

xmip-core
    Stable actor, message, policy and handler contracts when split out.

xmip-runtime
    Runtime executable packaging when split out.
```

## Handler repositories

Handler repositories remain technology specific:

```text
xmip-handler-<technology-or-family>
```

## Artifact rules

Receive Port, Process and Send Port remain Xmip artifacts.

Actor semantics are runtime behavior, not replacement names.

Assignment is Process-only.

Transformation is allowed in Receive Port, Process and Send Port.

Routing means pub/sub subscription matching.
