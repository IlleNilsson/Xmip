# ADR-0001: Repository naming rules

## Status

Superseded by ADR-0011.

## In brief

- Theme: The shape of the estate
- Subject: Repository naming, first attempt
- Name: The original naming rules
- Order: 3

Names are derived from rules rather than chosen. The original scheme was
`xmip-handler-<technology-or-family>`.

**Superseded by *One naming rule for the whole namespace***, which retired
`handler` as a name segment. Kept because the rule it states — a name is
derived, never chosen — survived the scheme that expressed it, and ADR-0011
is that same rule with the segment removed.

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
