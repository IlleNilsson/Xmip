# Xmip Glossary

Xmip architecture shall use one term for one concept.

## Kernel

The Kernel is the stable Xmip runtime core.

The Kernel loads Modules, applies runtime policy, controls execution, owns persistence boundaries, and enforces auditing, tracing, tracking, identity, authorization, and lifecycle rules.

The Kernel shall not hard-code technology behavior.

## TOML Configuration

TOML configuration defines set values that affect Xmip runtime behavior and the Artifacts a node can handle.

TOML configuration is not runtime state.

TOML configuration defines what may exist and how it should be configured.

Runtime persistence records what did happen, what is happening, and what must resume or be audited.

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

## Artifact Definition

An Artifact Definition is a named Xmip configuration object defined in TOML.

An Artifact Definition declares:

- artifact name,
- artifact kind,
- Handler reference,
- Handler configuration,
- runtime-affecting configuration values,
- contracts or contract references where applicable,
- security requirements where applicable,
- tracing and tracking settings where applicable.

An Artifact Definition describes what a node may handle.

An Artifact Definition does not process a message by itself.

## Artifact Instance

An Artifact Instance is the runtime execution of an Artifact Definition.

An Artifact Instance is created when Xmip runtime uses an Artifact Definition to handle a specific message, stream, action, or execution scope.

An Artifact Instance handles the message it was given.

An Artifact Instance is auditable and may be traceable and trackable according to policy.

Runtime persistence records Artifact Instance state, outcome, failure, retry, and recovery information where applicable.

## Definition versus Instance

Definition means configured in TOML.

Instance means running or previously run in runtime.

Examples:

```text
ReceiveLocation Definition
    -> ReceiveLocation Instance

SendLocation Definition
    -> SendLocation Instance

BusinessProcess Definition
    -> BusinessProcess Instance
```

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
TOML Configuration
    Runtime settings
    Artifact Definitions
```

```text
Artifact Definition
    references Handler
    contains Handler configuration
```

```text
Runtime
    Artifact Instance
        handles assigned message
```

```text
Handler
    = technology-specific trait/interface
```

```text
Extension
    = reusable runtime utility capability
```
