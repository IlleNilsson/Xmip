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

Each Handler technology shall live in its own sub-repository.

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

Each Handler technology has a corresponding sub-repository.

Examples:

- handler-file,
- handler-ftp,
- handler-sftp,
- handler-ftps,
- handler-http,
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
        HTTP
            REST
            SOAP
            WebHook
        gRPC
        raw TCP
    UDP
        raw UDP
        IoT and industrial protocols where applicable

File transfer
    File
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

## Rule

Branches are for development and release flow.

Sub-repositories are for architectural ownership and package boundaries.

Runtime architectures are release variants with compiled binaries.
