# Xmip Handler Taxonomy

## Status

Proposed by ADR-0005.

## Purpose

Handler describes a runtime module role. Repository ownership follows the architectural capability implemented by the module.

## Repository families

```text
xmip-transport-<technology>       Stream movement
xmip-message-<representation>     Serialization and materialization
xmip-contract-<technology>        Contract implication and evaluation
xmip-path-<language>              Structured addressing
xmip-logic-<technology>           Method and operation semantics
```

The prefix `xmip-handler-` is retired for repositories.

## Transport

Transport implementations are direction-neutral. Each implementation declares receive, send or bidirectional support.

The authoritative transport list is in `architecture.toml`. The initial implementation wave is:

```text
xmip-transport-file
xmip-transport-tcp
xmip-transport-http
xmip-transport-websocket
xmip-transport-mllp
```

FTP includes FTP and FTPS modes. SFTP remains a separate SSH-based transport.

## Content representation

Content representation implementations are independent of transport:

```text
xmip-message-json
xmip-message-xml
xmip-message-csv
xmip-message-protocol-buffers
xmip-message-apache-avro
```

## Contract

Contract implementations evaluate a declared standard, schema, profile or code contract. They do not own transport or Path execution.

The first Contract wave is JSON Schema and XML Schema.

## Logic

Method-oriented semantics are independent of transport and representation:

```text
xmip-logic-http-api
xmip-logic-soap
xmip-logic-grpc
```

SOAP may use HTTP, XML and WSDL without becoming any one of those concerns. gRPC may use HTTP and Protocol Buffers while retaining separate operation semantics.

## Rule

A repository may be added, removed or renamed only through an architecture change that updates the specification, manifest and affected ADRs together.
