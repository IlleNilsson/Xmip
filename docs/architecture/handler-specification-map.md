# Xmip Handler Specification Map

## Status

Working reference.

## Purpose

This document maps Xmip handler repositories to the external specifications or technology documentation that should guide implementation.

## File and transfer

```text
xmip-handler-file
    Local and shared file system behavior.

xmip-handler-ftp
    FTP
    FTPS
    SFTP
```

## IP and network

```text
xmip-handler-tcp-base
    Shared TCP behavior.

xmip-handler-udp-base
    Shared UDP behavior.

xmip-handler-raw-tcp
    Direct TCP stream handling.

xmip-handler-raw-udp
    Direct UDP datagram handling.
```

## HTTP family

```text
xmip-handler-http
    HTTP server and client primitives.
    TLS, headers, methods, status codes, routes, identity handoff.

xmip-handler-web-api
    Web API and HTTP API behavior.

xmip-handler-soap
    SOAP over HTTP behavior.

xmip-handler-websocket
    HTTP upgrade and long-lived bidirectional connections.

xmip-handler-grpc
    gRPC over HTTP/2 behavior.
```

## Queue, stream, and broker

```text
xmip-handler-queue-stream-common
    Common queue and stream concepts.

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

## Healthcare and data exchange

```text
xmip-handler-data-exchange-common
xmip-handler-edi
xmip-handler-hl7
xmip-handler-fhir
xmip-handler-mllp
```

MLLP is a transport used with HL7 message flows.

FHIR is a healthcare exchange standard based on resources and commonly uses JSON, XML, RDF, REST, and HTTPS.

## Industrial, device, and IoT

```text
xmip-handler-industrial-device-common
xmip-handler-canbus
xmip-handler-opc-ua
xmip-handler-modbus
xmip-handler-mqtt
```

CANBUS should follow ISO 11898 family concepts and CAN FD where applicable.

OPC UA should follow OPC Foundation / IEC 62541 concepts.

Modbus should follow the Modbus Application Protocol.

MQTT should follow the OASIS MQTT specification.

## Rule

Implementation starts from official specifications or official vendor/project documentation where available.

External references are guidance for handler implementation. Xmip contracts remain authoritative for runtime behavior, message immutability, interchange lineage, audit, tracking, and replay.
