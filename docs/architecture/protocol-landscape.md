# Xmip Protocol Landscape

Xmip targets servers, computers, devices, edge devices, IoT, and industrial integration.

The protocol landscape must therefore include business integration protocols, file protocols, broker protocols, cloud protocols, healthcare protocols, EDI protocols, industrial protocols, device protocols, and IoT protocols.

These protocols are not Kernel features.

They are targets for loadable handlers or purpose-compiled capabilities.

## Root view

```text
Communication
    IP
        IPv4
        IPv6
            TCP
            UDP

    CAN Network
        CANBUS

    Serial
        RS-232
        RS-485

    File System
        Local File
        Shared File

    Broker / Cloud Service
        Managed broker
        Managed event service
        Managed storage service

    Wireless / IoT
        Bluetooth
        Zigbee
        LoRaWAN
        Thread
```

## IP family

```text
IP
    IPv4
    IPv6
        TCP
            HTTP
                REST
                SOAP
                Web API
                WebHook
                gRPC over HTTP/2

            FTP
                FTPS
                SFTP

            AMQP
                RabbitMQ
                Azure Service Bus when AMQP is used

            MQTT

            Kafka protocol
                Apache Kafka
                Redpanda

            MLLP
                HL7 v2

            SMTP
            IMAP
            POP3

            TCP custom stream

        UDP
            DNS
            DHCP
            SNMP
            Syslog
            CoAP
            mDNS
            SSDP
            UDP custom datagram
            discovery protocols
            broadcast protocols
            multicast protocols
```

## Queue, broker, and event families

```text
Queue / Broker / Event
    MSMQ
    RabbitMQ
    IBM MQ
    Apache Kafka
    Redpanda
    Azure Service Bus
    Azure Event Grid
    AWS SQS
    AWS SNS
    NATS
        JetStream
    Redis Streams
    MQTT
```

Some of these are TCP protocols.

Some are cloud services.

Some expose HTTP APIs.

Some expose AMQP or proprietary protocols.

Xmip shall describe them by communication layer, protocol, interaction pattern, and capability rather than forcing all of them into one inheritance tree.

## File and remote file families

```text
File
    Local File
    Shared File
    Directory Watch
    File Polling

Remote File
    FTP
        FTPS
        SFTP
```

## Healthcare family

```text
Healthcare
    MLLP
    HL7 v2
    HL7 v3
    FHIR
    DICOM
```

## EDI family

```text
EDI
    X12
    EDIFACT
    TRADACOMS
    Peppol
```

## Industrial and device family

```text
Industrial / Device
    CANBUS
        J1939
        OBD-II
        CANopen

    OPC UA
    Modbus TCP
    Modbus RTU
    Profinet
    EtherNet/IP
    BACnet
    DDS
```

## IoT family

```text
IoT
    MQTT
    CoAP
    LoRaWAN
    Zigbee
    Bluetooth
    Thread
    Matter
```

## Principle

IP is the root for TCP and UDP networking.

Communication is the root for everything Xmip can touch.

The Kernel shall not hard-code protocol behavior.

Handlers declare:

- communication medium,
- transport,
- protocol,
- interaction pattern,
- capabilities,
- lineage,
- loadability,
- isolation,
- trust requirements.
