# Repository and crate implementation plan

## Status

Proposed by ADR-0005.

## Rule

Repository creation, crate scaffolding, compilation, linking, test execution and packaging are separate operations.

A repository may be reserved or scaffolded without claiming that its implementation is complete. No automatic verification trigger is enabled by the repository template.

Every repository has one primary Rust crate whose name matches the repository name unless an accepted ADR defines an exception.

## Architecture before implementation

Before a repository or crate is created:

1. Its responsibility and classification must exist in `xmip-architecture.json`.
2. Its dependencies must be explicit and acyclic.
3. Representation, Contract, Path, Transport and Logic responsibilities must remain separate.
4. The architecture specification and manifest must agree.

## First Contract vertical slices

```text
JSON
    xmip-message-json
    xmip-path-json-pointer
    xmip-contract-json-schema

XML
    xmip-message-xml
    xmip-path-xpath
    xmip-contract-xml-schema
```

The common `xmip-message`, `xmip-path` and `xmip-contract` crates must first expose compatible boundaries. Structural reading and writing must not remain owned by `xmip-contract`.

## First Transport wave

```text
xmip-transport
xmip-transport-file
xmip-transport-tcp
xmip-transport-http
xmip-transport-websocket
xmip-transport-mllp
```

`xmip-transport` owns the direction-neutral contract. Receive and Send adapt their orchestration to that contract. The existing monorepo `xmip-handler-file` crate is migration input for `xmip-transport-file`; it is not a second implementation.

## Logic follows its dependencies

```text
xmip-logic-http-api
xmip-logic-soap
xmip-logic-grpc
```

Logic scaffolding begins only after its declared Transport, representation and Contract dependencies exist.

## Later families

EDI, HL7 and code-contract families remain reserved until their explicit shared-family dependencies are represented and reviewed in the manifest.

## Completeness

A scaffold is not a protocol implementation. Protocol compliance requires implementation against authoritative specifications and conformance evidence.
