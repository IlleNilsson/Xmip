# Device and Platform Submodule Layout

Xmip is a cross messaging and integration platform. The repository layout must make room for common handlers and for handlers that are specific to servers, edge devices, IoT devices, desktop clients, operating systems, hardware buses and constrained runtimes.

## Layout

```text
handlers/
  common/
  server/
  edge/
  iot/
  desktop/
  device/
  industrial/
  marine/
  healthcare/
  finance/
  business/
  cloud/
  government/

runtimes/
  server/
  edge/
  iot/
  desktop/
  embedded/

platforms/
  windows/
  linux/
  macos/
  containers/
  kubernetes/
  baremetal/

contracts/
content/
tools/
deployments/
```

## Rule

A handler that works broadly belongs under `handlers/common` or the relevant technology family.

A handler that depends on device class, operating system, bus, hardware capability or constrained runtime belongs under a more specific path.

Examples:

```text
handlers/common/http
handlers/common/grpc
handlers/common/file
handlers/server/sql
handlers/iot/mqtt-sn
handlers/iot/lorawan
handlers/device/canbus
handlers/marine/nmea2000
handlers/desktop/clipboard
handlers/desktop/local-notification
platforms/windows/service
platforms/linux/systemd
platforms/macos/launchd
runtimes/iot/minimal
runtimes/server/cluster-node
```
