# GitHub Repository Inventory: Existing

## Existing valid repositories

```text
Xmip
xmip-core
xmip-handler-aws-sqs
xmip-handler-azure-event-grid
xmip-handler-azure-service-bus
xmip-handler-edi
xmip-handler-fhir
xmip-handler-file
xmip-handler-ftp
xmip-handler-grpc
xmip-handler-http
xmip-handler-soap
xmip-handler-tcp-base
xmip-handler-web-api
xmip-handler-websocket
```

## Existing invalid repositories

These repositories exist but violate ADR-0001 naming rules.

```text
mip-handler-canbus
xmip-handler-fil
xmip-handler-udp-bas
```

## Required corrections

```text
mip-handler-canbus -> xmip-handler-canbus
xmip-handler-fil -> remove or ignore; canonical is xmip-handler-file
xmip-handler-udp-bas -> xmip-handler-udp-base
```
