# Repository Refactor Purpose

## Status

Active pre-alpha refactor plan.

## Purpose

Align the GitHub repository landscape with ADR-0007 and ADR-0008.

Xmip entities remain explicit artifacts, but they are also Actors when they communicate, publish, subscribe, own work, or transfer responsibility.

## Repository categories

```text
xmip-core
    Stable platform contracts.

Xmip
    Planning, ADRs, executable kernel prototype, repository catalog, and integration tests.

xmip-handler-*
    Technology-specific handler implementations.

xmip-runtime
    Runtime executable packaging when split from prototype.
```
