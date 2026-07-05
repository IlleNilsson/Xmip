# Xmip Continuum

This repository's `main` branch represents **Xmip Continuum**.

Xmip Continuum is the forward-moving architecture and runtime line where the Xmip platform is shaped, corrected, expanded, and consolidated.

## Repository shape

Xmip is a modular platform. The normal architecture is not a single binary.

```text
xmip-core                 shared message, artifact, protocol, handler, and runtime models
crates/xmip-plugin-api    stable contracts for dynamically loaded modules
crates/xmip-runtime       runtime registry, dispatch, node, and host-process planning
crates/xmip-host          host-process lifecycle and dynamic-module validation
crates/xmip-handler-file  first transport-handler module example
xmip-tiny-device          compact binary proof for IoT/embedded targets only
```

The tiny-device binary remains useful for constrained devices and recovery demonstrations, but it is not the shape of the server, desktop, edge, or full platform runtime.

## Branch strategy

- `main` is Xmip Continuum.
- Xmip Linear belongs on a release branch.
- Fixes made on the Xmip Linear release branch shall be merged back into Xmip Continuum `main` when applicable.
- Continuum may move beyond Linear, but Linear fixes must not be lost.

In short:

```text
Xmip Linear release branch
    -> fixes merge forward into
Xmip Continuum main
```

## Runtime direction

Xmip runtime is built around separately loadable capability modules:

```text
Cluster Node
    -> Runtime Registry
    -> Host Process Plan
    -> Host Process
    -> Dynamic Module / Handler
    -> Transport, Content, Logic, Store, or Management capability
```

Transport handlers, content handlers, logic handlers, stores, and management extensions are separate modules. The host process exists to isolate trust, bitness, latency, and runtime technology requirements.

## Current executable proof

The current Rust executable started as the Xmip Linear Kernel proof.

It is now carried inside Xmip Continuum as executable evidence and as the `xmip-tiny-device` binary, not as the branch or repository identity.

The proof models runtime ideas such as:

```text
External Stream
    -> Receive
    -> Identify / Authorize
    -> Accept
    -> Promote
    -> Publish
    -> Process / Send outcome
```

It also contains early code for:

- receive endpoint claims,
- receive acquisition modes,
- receive transport/protocol hints,
- receive identity and authorization,
- send ports and send locations,
- outbound send identity,
- cluster identity,
- runtime persistence records.

## Build examples

```powershell
cargo build --workspace
cargo test --workspace
cargo build --workspace --no-default-features --features iot-profile
cargo build --workspace --no-default-features --features embedded-profile
```

Run the tiny-device proof:

```powershell
cargo run --bin xmip-tiny-device
```

The older linear recovery demo may intentionally crash after `Publish` on the first run and continue after checkpoint reload on the next run.

Reset demo state:

```powershell
Remove-Item .\execution-context.pb, .\crash-once.marker -ErrorAction SilentlyContinue
```

## Important

This is not the full Xmip platform.

This repository is currently the Xmip Continuum design and executable proof line.

Xmip Linear is a release-line concern, not the identity of `main`.
