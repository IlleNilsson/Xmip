# Xmip TCP Handler Lineage

TCP is a handler family.

Many higher-level protocols and interaction styles are built on top of TCP.

Xmip shall model these as lineage relationships rather than kernel features.

Conceptually:

```text
TCP family
    Raw TCP
    HTTP
        Web API
            REST
        SOAP
        WebHook
```

UDP forms a separate transport family and is not derived from TCP.

## Family behavior

TCP-family handlers may share concepts such as:

- connection management,
- session handling,
- request/response,
- streaming,
- framing,
- timeout handling,
- keepalive behavior,
- connection pooling,
- TLS usage.

Not every derived handler supports every concept.

## Kernel rule

The Xmip Kernel does not implement HTTP, REST, SOAP, WebHook, or TCP protocol behavior.

The Kernel only understands:

- module contracts,
- ownership,
- identity,
- authorization,
- auditing,
- tracing,
- tracking,
- persistence,
- execution policy.

TCP-family handlers are loadable modules.

## Principle

Lineage expresses capability relationships.

Technology behavior belongs to handlers, not the Kernel.
