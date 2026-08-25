# ADR-0004: Handler universe

## Status

Superseded by ADR-0010.

ADR-0010 replaced the handler universe with the contract and transport
repository boundaries, and ADR-0011 retired `handler` as a repository-name
segment. This record is kept because the reasoning below produced the
technology lists that architecture.toml now carries, but nothing in it is
current. Do not implement from it.

The previous header read "Superseded by ADR-0005 when ADR-0005 is accepted",
which was conditional, never resolved, and named an ADR about refactor
discipline rather than the one that actually replaced this.

## Decision

Xmip shall organize handler support by technology, protocol, and industry space.

Handlers that are not Xmip core shall live in their own handler repositories and shall be represented in the submodule plan.

The handler universe is expandable, but the baseline shall cover integration, business, cloud, healthcare, industrial, energy, finance, logistics, government, database, file, network, messaging, and device spaces.

## Rule

The historical handler repository rule below is superseded by the capability-specific repository prefixes in ADR-0005:

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
