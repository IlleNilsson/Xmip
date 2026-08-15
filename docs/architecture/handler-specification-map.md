# Xmip Handler Specification Map

## Status

Proposed by ADR-0005.

## Purpose

This document anchors implementation work to authoritative external specifications while preserving Xmip repository boundaries.

## Initial Transport implementations

```text
xmip-transport-file
    Platform file-system behaviour and Rust file-system APIs.

xmip-transport-tcp
    IETF RFC 9293.

xmip-transport-http
    IETF RFC 9110 and the applicable HTTP/1.1, HTTP/2 and HTTP/3 specifications.
    Depends explicitly on xmip-transport-tcp for the initial implementation.

xmip-transport-websocket
    IETF RFC 6455 and applicable extensions.
    Depends explicitly on xmip-transport-http.

xmip-transport-mllp
    MLLP framing over TCP.
    Depends explicitly on xmip-transport-tcp.
```

## Initial Contract implementations

```text
xmip-contract-json-schema
    JSON Schema specifications and vocabularies.

xmip-contract-xml-schema
    W3C XML Schema specifications.
```

Their representation and Path collaborators are separate repositories:

```text
xmip-message-json
xmip-path-json-pointer
xmip-message-xml
xmip-path-xpath
```

## Initial Logic implementations

```text
xmip-logic-http-api
xmip-logic-soap
xmip-logic-grpc
```

## Rule

Protocol compliance must be claimed only after conformance evidence exists. Xmip contracts remain authoritative for immutability, Journey lineage, audit, tracking and replay.
