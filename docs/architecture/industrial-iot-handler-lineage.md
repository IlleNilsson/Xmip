# Xmip Industrial and IoT Handler Lineage

Xmip targets server-side integration, IoT, and industrial integration.

Therefore UDP, CANBUS, and industrial protocols are first-class handler families in the Xmip architecture.

They are still loadable handlers, not Kernel features.

## Transport families

Xmip shall support transport families such as:

```text
TCP family
UDP family
CANBUS family
```

TCP is suitable for reliable business messaging and request/response protocols.

UDP is suitable for datagrams, discovery, broadcast, multicast, telemetry, and low-overhead industrial communication where the protocol or handler owns reliability semantics if required.

CANBUS is suitable for vehicle, machine, embedded, and industrial device communication.

## Industrial protocol families

Industrial and IoT handler families may include:

```text
Industrial / IoT family
    CANBUS
    OPC UA
    Modbus
    MQTT
    Profinet
    EtherNet/IP
    BACnet
    LoRaWAN
    CoAP
    DDS
```

Not every industrial protocol uses UDP.

Not every industrial protocol uses TCP.

Not every industrial protocol is message-oriented in the same way as business integration protocols.

Xmip models them as loadable handlers with explicit declared capabilities.

## UDP use in Xmip

UDP handlers may be used for:

- discovery,
- device announcement,
- telemetry,
- sensor events,
- broadcast,
- multicast,
- industrial protocols,
- low-latency datagrams.

UDP does not provide ordered reliable delivery by itself.

If a UDP-based handler needs reliability, ordering, de-duplication, acknowledgement, replay, or persistence, the handler must declare and implement those capabilities or bind to Xmip persistence semantics where appropriate.

## Kernel rule

The Xmip Kernel does not implement UDP, CANBUS, OPC UA, Modbus, MQTT, Profinet, EtherNet/IP, BACnet, LoRaWAN, CoAP, or DDS protocol behavior.

The Kernel enforces:

- module loading,
- compatibility,
- trust,
- isolation,
- ownership,
- identity,
- authorization,
- audit,
- tracing,
- tracking,
- persistence,
- execution policy.

The handler owns technology behavior.

## Principle

Industrial and IoT support is part of the Xmip target market.

The Kernel remains generic.

Industrial and IoT capabilities arrive through loadable handlers with explicit metadata, lineage, and capability declarations.
