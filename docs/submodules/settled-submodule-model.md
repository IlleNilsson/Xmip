# Settled Xmip Submodule Model

## Decision

Xmip uses nested Git submodules, Cargo workspaces, crates, packages and feature profiles.

Git repositories define ownership boundaries.

Cargo defines build boundaries.

Feature profiles define deployment boundaries.

## Root repository

`Xmip` is the architecture and orchestration repository.

It should contain only root-level family submodules plus root-level architecture, Forge, scripts and integration tests.

```text
Xmip
  core
  handlers/common
  handlers/messaging
  handlers/device
  handlers/industrial
  handlers/marine
  handlers/healthcare
  handlers/business
  handlers/desktop
  runtimes
  platforms
```

## Family repositories

Family repositories group related implementation modules.

Examples:

```text
xmip-handlers-common
xmip-handlers-messaging
xmip-handlers-device
xmip-handlers-industrial
xmip-handlers-marine
xmip-handlers-healthcare
xmip-handlers-business
xmip-handlers-desktop
xmip-runtimes
xmip-platforms
```

A family repository may contain nested submodules and may also be a Cargo workspace.

## Implementation repositories

Implementation repositories contain concrete handlers or runtime/platform implementations.

Examples:

```text
xmip-handler-file
xmip-handler-http
xmip-handler-grpc
xmip-handler-canbus
xmip-handler-nmea2000
xmip-runtime-iot-minimal
xmip-platform-windows-service
```

## Large device build model

Servers and desktop clients may use a full Cargo workspace and dynamically load modules when appropriate.

## Constrained device build model

Edge, IoT and embedded targets should compile only the required crates and features into one binary.

## Checkout rule

Always use recursive submodule checkout.

```powershell
git clone --recurse-submodules https://github.com/IlleNilsson/Xmip.git
```

For an existing clone:

```powershell
git submodule update --init --recursive
```

## Current implementation status

The model is settled.

The existing connector cannot create new GitHub repositories and cannot safely create gitlink entries without subrepository commit SHAs.

The actual submodule transition must be performed locally by the provided scripts, then committed.
