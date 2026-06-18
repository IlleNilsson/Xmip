# Xmip Handler Taxonomy

## Status

Accepted working taxonomy.

## Purpose

This document preserves the handler scope from the original Xmip requirements and later repository decisions.

Handlers are grouped by technology family. Repository names must follow ADR-0001.

## Core file and transfer handlers

```text
xmip-handler-file
xmip-handler-ftp
```

`xmip-handler-file` covers local and shared file system receive and send behavior.

`xmip-handler-ftp` covers FTP, FTPS, and SFTP.

## IP base handlers

```text
xmip-handler-tcp-base
xmip-handler-udp-base
```

These repositories contain shared socket-level behavior for derived TCP and UDP handlers.

## HTTP family handlers

```text
xmip-handler-http
xmip-handler-web-api
xmip-handler-soap
xmip-handler-websocket
```

HTTP owns shared HTTP behavior and shared HTTP security.

Web API, SOAP, and WebSocket are separate derived handlers.

## gRPC handler

```text
xmip-handler-grpc
```

## Raw network handlers

```text
xmip-handler-raw-tcp
xmip-handler-raw-udp
```

These represent direct TCP and UDP stream or datagram handlers where no higher-level protocol handler applies.

## Healthcare and data exchange handlers

```text
xmip-handler-data-exchange-common
xmip-handler-edi
xmip-handler-hl7
xmip-handler-fhir
xmip-handler-mllp
```

MLLP is listed separately because it is a transport commonly used with HL7 flows.

## Queue, broker, and stream handlers

```text
xmip-handler-queue-stream-common
xmip-handler-msmq
xmip-handler-rabbitmq
xmip-handler-kafka
xmip-handler-ibmmq
xmip-handler-azure-service-bus
xmip-handler-azure-event-grid
xmip-handler-aws-sqs
xmip-handler-nats
xmip-handler-redis-streams
```

## Industrial, device, and IoT handlers

```text
xmip-handler-industrial-device-common
xmip-handler-canbus
xmip-handler-opc-ua
xmip-handler-modbus
xmip-handler-mqtt
```

## Derived or represented capabilities

The following are represented by the HTTP/Web API/SOAP family unless later split by decision:

```text
REST
WebHook
HTTP API
SOAP over HTTP
```

The following are represented by `xmip-handler-ftp`:

```text
FTP
FTPS
SFTP
```

## Repository rule

No handler repository may be added, removed, or renamed without updating this taxonomy and the relevant ADR.
