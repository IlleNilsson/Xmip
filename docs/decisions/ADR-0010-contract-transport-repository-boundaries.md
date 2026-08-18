# ADR-0010: Contract, transport and handler repository boundaries

## Status

Accepted.

Renumbered from ADR-0005, which collided with ADR-0005 pre-alpha refactor discipline.

The repository naming patterns in clauses 3, 6, 7, 8 and 9 are superseded by ADR-0011. Every other decision in this ADR stands.

## Context

The architecture manifest, accepted handler taxonomy and existing Rust crates describe incompatible repository models.

The manifest declares separate `xmip-receive-*` and `xmip-send-*` technology repositories. Earlier handler documents declare `xmip-handler-*` repositories. The module API defines a direction-neutral `TransportHandler` that may receive and send. This produces duplicate technology repositories and unclear ownership.

The Contract crate also owns structural reading and writing even though Contract, representation and Path are independent architectural responsibilities.

## Decision

1. `xmip-receive` and `xmip-send` remain orchestration capabilities.
2. A new common capability, `xmip-transport`, owns direction-neutral transport contracts.
3. Transport technology repositories use `xmip-transport-<technology>`.
4. A transport implementation declares whether it supports receive, send or both.
5. Handler remains a runtime module role and is not a repository-name prefix.
6. Content representation repositories use `xmip-message-<representation>`.
7. Contract technology repositories use `xmip-contract-<technology>`.
8. Path repositories use `xmip-path-<language>`.
9. A new common capability, `xmip-logic`, owns method and operation semantics. Logic technology repositories use `xmip-logic-<technology>`.
10. Credential and identity presentation is not a transport technology.
11. Technology-to-technology dependencies are allowed only when explicitly declared in the manifest.
12. Each repository has one primary Rust crate whose name matches the repository name unless another accepted ADR defines an exception.

## Contract boundary

`xmip-contract` owns implication, evaluation coordination, descriptors, results and diagnostics.

Representation parsing and serialization belong to `xmip-message-*`. Path execution belongs to `xmip-path-*`. Representation-neutral structured access belongs at the Message boundary rather than inside Contract technology.

## Initial vertical slices

The first Contract slices are JSON and XML:

- `xmip-message-json`
- `xmip-path-json-pointer`
- `xmip-contract-json-schema`
- `xmip-message-xml`
- `xmip-path-xpath`
- `xmip-contract-xml-schema`

The first Transport slice is:

- `xmip-transport-file`
- `xmip-transport-tcp`
- `xmip-transport-http`
- `xmip-transport-websocket`
- `xmip-transport-mllp`

The existing `xmip-handler-file` code is migration input for `xmip-transport-file`; it must not be duplicated as a second implementation.

## Consequences

The two direction-specific technology groups are replaced by one transport group. SOAP and gRPC move to Logic. Security presentation entries leave the transport taxonomy. Legacy handler provisioning scripts are retired. Existing runtime source is migrated in later implementation pull requests after this architecture decision is accepted.
