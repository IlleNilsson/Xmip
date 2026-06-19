# ADR-0004: Handler universe

## Status

Accepted.

## Decision

Xmip shall organize handler support by technology, protocol, and industry space.

Handlers that are not Xmip core shall live in their own handler repositories and shall be represented in the submodule plan.

The handler universe is expandable, but the baseline shall cover integration, business, cloud, healthcare, industrial, energy, finance, logistics, government, database, file, network, messaging, and device spaces.

## Rule

Every handler repository must follow ADR-0001:

```text
xmip-handler-<technology-or-family>
```

Every handler must be visible in:

```text
docs/architecture/handler-taxonomy.md
src/handler_taxonomy.rs or src/handler_universe.rs
.gitmodules.planned
```

## Baseline spaces

```text
File and transfer
Network and web
Messaging and streaming
Healthcare
Industrial and IoT
Energy and utilities
Finance and payments
Business documents and EDI
Databases and storage
Email and collaboration
Enterprise SaaS and line-of-business systems
Identity and directory
Government and public sector exchange
Geospatial
```

## Principle

Xmip core owns message, interchange, audit, persistence, runtime, and handler contracts.

Handler repositories own protocol-specific and technology-specific implementation.
