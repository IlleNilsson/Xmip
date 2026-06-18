# ADR-0001: Repository naming rules

## Status

Accepted.

## Decision

Repository names are derived from rules.

Handler repositories use:

```text
xmip-handler-<technology-or-family>
```

Core repositories use:

```text
xmip-<core-area>
```

The current core repository is:

```text
xmip-core
```

## Valid examples

```text
xmip-core
xmip-handler-canbus
xmip-handler-file
xmip-handler-ftp
xmip-handler-grpc
xmip-handler-http
xmip-handler-kafka
xmip-handler-mqtt
xmip-handler-opc-ua
xmip-handler-soap
xmip-handler-web-api
xmip-handler-websocket
```

## Invalid examples

```text
mip-handler-canbus
handler-canbus
xmip-canbus
```

## File handler

The canonical repository name is:

```text
xmip-handler-file
```

This handler is responsible for local or shared file system receive and send behavior.

FTP, FTPS, and SFTP remain in:

```text
xmip-handler-ftp
```

## Rule

Before a repository is created, documented, or added as a submodule, the name must pass this ADR.