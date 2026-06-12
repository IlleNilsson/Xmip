# Xmip Glossary

Xmip architecture shall use one term for one concept.

## Kernel

The Kernel is the stable Xmip runtime core.

The Kernel loads Modules, applies runtime policy, controls execution, owns persistence boundaries, and enforces auditing, tracing, tracking, identity, authorization, and lifecycle rules.

The Kernel shall not hard-code technology behavior.

## Module

A Module is a loadable Xmip capability package.

A Module is loaded at startup according to Xmip TOML configuration.

A Module may define:

- Handlers,
- Extensions.

## Handler

A Handler is a technology-specific trait/interface implemented by a Module.

A Handler has a specific technology purpose.

Examples:

- HTTP Handler,
- FTP Handler,
- SFTP Handler,
- RabbitMQ Handler,
- Kafka Handler,
- File Handler,
- CANBUS Handler,
- FHIR Handler,
- HL7 Handler.

Handlers implement communication, protocol, format, or technology behavior.

Handlers are incorporated as contracts such as traits or interfaces so the Kernel can call them through stable boundaries.

## Extension

An Extension is a utility capability defined by a Module.

An Extension is loaded at startup according to Xmip TOML configuration.

An Extension may be used from anywhere within the Xmip runtime where policy allows it.

Extensions connect Xmip to external executable code, shared libraries, scripts, language runtimes, or utility behavior.

Examples:

- .NET Extension,
- Java Extension,
- Python Extension,
- Go Extension,
- Rust Extension,
- C/C++ Extension,
- PowerShell Extension,
- Bash Extension,
- company-specific utility Extension.

## Handler versus Extension

A Handler has a technology purpose.

An Extension has a utility purpose.

Handlers bind Xmip to external communication, protocol, format, or transport behavior.

Extensions provide reusable executable capability callable from within Xmip runtime.

## Retired terms

### Adapter

Retired.

Use Handler.

### Plugin

Retired.

Use Module, Handler, or Extension depending on the exact meaning.

## Terminology hierarchy

```text
Kernel
    Module
        Handler
        Extension
```

```text
Handler
    = technology-specific trait/interface
```

```text
Extension
    = reusable runtime utility capability
```
