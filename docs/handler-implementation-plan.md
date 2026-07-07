# Handler implementation plan

Xmip handlers are built from the technology tree. The tree is used to understand reuse and dependencies, not to pretend all transports are the same.

## First executable handler wave

```text
file-system
    file
    file-watch
    file-poll

ip
    tcp
        http
            soap
            rest
            webhook
            grpc
        ftp
        sftp
        mllp
        mqtt
    udp
        dns
        syslog
```

## Implementation rule

A handler starts as a buildable Rust crate that implements the Xmip TransportHandler contract.

The first version may only pass through stream references and promote transport facts. That is still useful because it proves:

- the crate builds,
- the Xmip contract is implemented,
- the module manifest is valid,
- the ABI descriptor is exported,
- receive/send invocation shape is stable.

Protocol-specific behavior is added incrementally from the official specifications.

## Specification anchors

- HTTP: IETF RFC 9110 and related RFC 9112 / 9113 / 9114 documents.
- TCP: IETF RFC 9293.
- UDP: IETF RFC 768.
- MQTT: OASIS MQTT 5.0.
- File watching: platform file-system events plus Rust notify crate behavior.

## Do not fake completeness

A handler must not claim protocol compliance until it has protocol-level tests.

For now the generated handlers are scaffolds. They are valid Xmip modules, not complete protocol implementations.
