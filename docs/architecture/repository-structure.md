# Xmip Repository Structure

Xmip Continuum is the source umbrella.

Xmip Linear is the packaged supported release.

Runtime architectures are not branches.

Runtime architectures are compiled release variants.

## Responsibility

The Xmip project is responsible for:

- Xmip Continuum,
- Xmip Linear.

Anyone may fork from Continuum or Linear.

The Xmip project does not take responsibility for external forks.

## Sub-repositories

Xmip shall be organized as logical sub-repositories.

The main runtime shall live in its own sub-repository named `xmip-runtime`.

Handler technologies shall live in logical handler sub-repositories.

A handler sub-repository may contain multiple closely related protocol variants when they share more than they differ.

## Main runtime sub-repository

The main runtime sub-repository is:

```text
xmip-runtime
```

The runtime sub-repository contains:

- kernel,
- runtime execution,
- persistence boundary,
- management boundary,
- module loading,
- handler registry,
- subscription evaluation,
- process execution,
- send port execution.

## Handler sub-repositories

Each logical Handler technology or tightly related Handler family has a corresponding sub-repository.

Examples:

- xmip-handler-file,
- xmip-handler-ftp-family,
- xmip-handler-tcp-base,
- xmip-handler-udp-base,
- xmip-handler-http,
- xmip-handler-web-api,
- xmip-handler-soap,
- xmip-handler-websocket,
- xmip-handler-grpc,
- xmip-handler-queue-stream-common,
- xmip-handler-rabbitmq,
- xmip-handler-kafka,
- xmip-handler-msmq,
- xmip-handler-ibmmq,
- xmip-handler-azure-service-bus,
- xmip-handler-azure-event-grid,
- xmip-handler-industrial-device-common,
- xmip-handler-canbus,
- xmip-handler-opc-ua,
- xmip-handler-modbus,
- xmip-handler-mqtt,
- xmip-handler-data-exchange-common,
- xmip-handler-hl7,
- xmip-handler-fhir,
- xmip-handler-edi.

## Network investigation alignment

The handler repository structure shall follow the protocol and technology tree discovered in the network investigation.

Network and protocol families should have logical repository groupings.

Examples:

```text
IP
    TCP base
        raw TCP repository
        HTTP base repository
            shared HTTP functions
            shared HTTP security
            Web API repository
            SOAP repository
            WebSocket repository
        gRPC repository
    UDP base
        raw UDP repository
        UDP based device and IoT repositories where applicable

File transfer
    File repository
    FTP family repository
        FTP
        FTPS
        SFTP

Queueing and streaming common
    MSMQ repository
    RabbitMQ repository
    Kafka repository
    AWS SQS repository
    NATS repository
    Redis Streams repository

Industrial and device common
    CAN bus repository
    OPC UA repository
    Modbus repository
    MQTT repository

Data exchange common
    EDI repository
    HL7 repository
    FHIR repository
```

## HTTP family rule

HTTP support lives in its own base handler repository.

The HTTP base repository owns shared HTTP functions and shared HTTP security.

Web API support lives in its own repository derived from the HTTP base repository.

SOAP support lives in its own repository derived from the HTTP base repository when transported over HTTP.

WebSocket support lives in its own repository derived from the HTTP base repository because the connection starts as an HTTP upgrade, but its runtime behavior is long-lived and bidirectional.

## Queue and stream family rule

Queue and stream handlers share a common base repository.

The common base owns shared queue and stream concepts such as connection lifecycle, producer and consumer behavior, acknowledgement, batching, ordering, metadata mapping, and stream handoff to Xmip.

Specific technologies such as MSMQ, RabbitMQ, Kafka, AWS SQS, NATS, and Redis Streams live in derived repositories.

## Industrial and device family rule

Industrial, edge, device, and IoT handlers share a common base repository.

Specific technologies such as CAN bus, OPC UA, Modbus, and MQTT live in derived repositories.

## Data exchange family rule

EDI, HL7, and FHIR share a data exchange common base repository where parsing, contract mapping, validation hooks, and message metadata mapping can be reused.

Each standard still lives in its own derived repository.

## TCP and UDP family rule

TCP and UDP each have a base repository for shared socket-level behavior.

Higher-level protocols live in derived repositories.

## Rule

Branches are for development and release flow.

Sub-repositories are for architectural ownership and package boundaries.

Runtime architectures are release variants with compiled binaries.
