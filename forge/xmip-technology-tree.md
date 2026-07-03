# Xmip Forge Technology Tree

This is the prospecting model for repository families, Cargo crates, feature gates and nested submodules.

## Root

```text
Xmip
  core
  runtimes
  platforms
  handlers
  contracts
  content
  tools
```

## Runtime profiles

```text
server
  large device
  full workspace
  dynamic modules allowed

client-desktop
  large device
  local UX and tools
  selected handlers

edge
  constrained but service-capable
  mostly static binary

iot
  constrained device
  compile only required crates/features

embedded
  minimal runtime
  static binary
```

## Handler families

```text
common
  file
  ftp
  http
  grpc
  soap
  web-api
  websocket
  tcp-base
  udp-base

messaging
  kafka
  rabbitmq
  azure-service-bus
  azure-event-grid
  aws-sqs

industrial
  modbus
  opc-ua
  profinet
  ethernet-ip
  bacnet
  dnp3
  iec-60870-5-104
  iec-61850

device
  canbus
  serial
  bluetooth-le
  zigbee
  lorawan
  mqtt-sn

marine
  nmea2000

healthcare
  hl7
  fhir
  mllp

business
  edi
  x12
  edifact
  swift
  sap

desktop
  clipboard
  local-notification
  local-file-watch
```

## Cargo rule

Every module family can be a Cargo workspace.

Every implementation handler can be a crate/package.

Large profiles may load modules dynamically.

Small profiles compile required crates and features into one binary.

## Git rule

Root Xmip should use family submodules.

Family repositories should use nested implementation submodules.
