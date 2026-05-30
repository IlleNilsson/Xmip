# Xmip Feature Folder Convention

This document defines how Xmip source code is organized.

The goal is not source-code neatness.

The goal is architectural consistency and deployable capability boundaries.

## Principle

Xmip is organized around features and capabilities.

Not technical layers.

Not framework conventions.

Not language-specific conventions.

## Primary organizing rule

A feature should look familiar regardless of where it exists.

The same conceptual shape should repeat through the architecture.

Examples:

```text
Repository
Module
Feature
Subfeature
```

Each level should preserve the same organizational philosophy.

## Deployment capability first

The primary organizational unit is a deployable capability.

Examples:

```text
receive-http
receive-mqtt
receive-file

send-http
send-smtp
send-file

transform-json
transform-xml

process-orchestration

cluster-runtime
```

A feature folder should correspond to a meaningful capability.

## Preferred internal structure

Not every feature requires every folder.

Use only what the feature actually needs.

Preferred structure:

```text
feature/
├── contracts/
├── runtime/
├── configuration/
├── preservation/
├── observability/
└── tests/
```

Small features may contain only:

```text
feature/
├── contracts/
├── runtime/
└── tests/
```

The structure should remain recognizable.

## Recursive application

The same idea applies at multiple levels.

### Repository level

```text
Xmip/
├── kernel/
├── modules/
├── tooling/
├── samples/
└── docs/
```

### Kernel level

```text
kernel/
├── execution/
├── preservation/
├── recovery/
├── publish/
├── subscription/
└── contracts/
```

### Module level

```text
receive-http/
├── contracts/
├── runtime/
├── configuration/
└── tests/
```

## Language independence

This convention applies regardless of implementation language.

Examples:

- Rust,
- C#,
- Java,
- Python,
- PowerShell,
- Node.js.

The organizational principle remains the same.

## Architectural rule

Do not organize around technical layers such as:

```text
controllers
services
repositories
models
utils
helpers
```

unless those names represent actual capabilities.

Instead organize around what Xmip does.

## Outcome

A developer should be able to open any Xmip feature and immediately understand:

- what capability it provides,
- where contracts live,
- where runtime behavior lives,
- where preservation concerns live,
- where observability concerns live,
- where tests live.

The structure should remain predictable throughout the platform.
