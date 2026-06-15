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

The main runtime shall live in its own sub-repository.

Handler technologies shall live in logical handler sub-repositories.

A handler sub-repository may contain multiple closely related protocol variants when they share more than they differ.

## Main runtime sub-repository

The main runtime sub-repository contains:

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

- handler-file,
- handler-ftp-family,
- handler-http,
- handler-web-api,
- handler-soap,
- handler-grpc,
- handler-tcp,
- handler-udp,
- handler-rabbitmq,
- handler-kafka,
- handler-msmq,
- handler-ibmmq,
- handler-azure-service-bus,
- handler-azure-event-grid,
- handler-canbus,
- handler-hl7,
- handler-fhir,
- handler-edi.

## Network investigation alignment

The handler repository structure shall follow the protocol and technology tree discovered in the network investigation.

Network and protocol families should have logical repository groupings.

Examples:

```text
IP
    TCP
        HTTP base
            shared HTTP functions
            shared HTTP security
            Web API repository
            SOAP repository
        gRPC
        raw TCP
    UDP
        raw UDP
        IoT and industrial protocols where applicable

File transfer
    File
    FTP family
        FTP
        FTPS
        SFTP

Queueing and streaming
    MSMQ
    RabbitMQ
    Kafka
    AWS SQS
    NATS
    Redis Streams

Industrial and device
    CANBUS
    OPC UA
    Modbus
    MQTT
```

## HTTP family rule

HTTP support lives in its own base handler repository.

The HTTP base repository owns shared HTTP functions and shared HTTP security.

Web API support lives in its own repository derived from the HTTP base repository.

SOAP support lives in its own repository derived from the HTTP base repository when transported over HTTP.

## Rule

Branches are for development and release flow.

Sub-repositories are for architectural ownership and package boundaries.

Runtime architectures are release variants with compiled binaries.
