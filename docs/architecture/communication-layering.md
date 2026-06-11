# Xmip Communication Layering

Xmip shall not model all communication technologies as one inheritance tree.

The correct model separates communication medium, transport, protocol, interaction pattern, and capability.

## Layer model

```text
Communication Medium
    -> Transport
        -> Protocol
            -> Interaction Pattern
                -> Capability
```

Not every technology uses every layer.

Not every technology is IP-based.

## Communication Medium

A communication medium describes the broad way Xmip reaches or is reached by the outside world.

Examples:

```text
IP Network
CAN Network
Serial
Wireless / IoT
File System
Broker / Cloud Service
```

## Transport

A transport is below application protocols when the medium supports such a layer.

Examples:

```text
IP Network
    TCP
    UDP

CAN Network
    CANBUS

Serial
    RS-232
    RS-485
```

CANBUS is not below TCP.

CANBUS is not below UDP.

CANBUS is a transport/bus under the CAN Network communication medium.

## Protocol

A protocol sits above a transport or medium-specific access mechanism.

Examples:

```text
TCP
    HTTP
    FTP
    AMQP
    MQTT
    MLLP

UDP
    DNS
    SNMP
    Syslog
    CoAP
    Discovery protocols

CANBUS
    J1939
    OBD-II
    CANopen
```

## Interaction Pattern

Interaction pattern describes how the protocol is used.

Examples:

```text
HTTP
    REST
    SOAP
    Web API
    WebHook

Queue / Broker protocols
    Queue
    Topic
    Subject
    Stream

File protocols
    Polling
    Event based
```

## Capability

Capability describes what the handler can do.

Examples:

```text
Receive
Send
Poll
Publish
Subscribe
Acknowledge
Replay
Track offset
Read file
Write file
Move file
Delete file
Monitor directory
Broadcast
Multicast
Read telemetry
Write command
```

## Principle

Handler lineage expresses useful family relationships.

Layering prevents false inheritance.

The Xmip Kernel shall use explicit metadata for:

- communication medium,
- transport,
- protocol,
- interaction pattern,
- capabilities.

The Kernel must not assume that CANBUS, TCP, UDP, HTTP, queues, files, or industrial protocols belong to the same hierarchy.
