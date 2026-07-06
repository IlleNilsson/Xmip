# Xmip Continuum

This repository's `main` branch represents **Xmip Continuum**.

Xmip Continuum is now implementation-first. Architecture is captured in code by executable vertical slices and refined only when implementation proves the need.

## Repository shape

Xmip is a modular platform. The normal architecture is not a single binary.

```text
xmip-core                    core Journey, Message, Stream, Event and execution model
crates/xmip-module-abi       stable binary boundary for loadable Modules
crates/xmip-module-api       module and handler contracts during prototype convergence
crates/xmip-configuration    TOML configuration model and configuration-to-runtime mapping
crates/xmip-runtime          runtime registry, dispatch, node, execution tree, and Host Process planning
crates/xmip-service          Xmip Service startup planner
crates/xmip-host             Host Process lifecycle and dynamic-module validation
crates/xmip-persistence      Journey recovery, checkpoint, deduplication, and runtime store contracts
crates/xmip-tracking         tracking event contracts
crates/xmip-cli              prototype command-line surface
crates/xmip-handler-file     first transport-handler Module example
xmip-tiny-device             compact executable proof for constrained targets only
```

The tiny-device binary is now an executable proof of the current model, not the old Linear Kernel proof.

## Core runtime vocabulary

```text
Journey
    Long-lived work over time.

Message
    Immutable state in a Journey.

Stream
    Immutable payload referenced by a Message.

Event
    Something happened.

Handler
    Configured code that handles Events or content according to contracts.

Module
    Compiled loadable code unit containing one or more cohesive Handlers.
```

Xmip avoids the bare word **Process** where it can mean more than one thing.

- **System Process** means an operating-system process.
- **Host Process** means a System Process started or managed by Xmip.
- **Xmip Process** means a configured process definition that can progress a Journey.

## Executable proof

The current executable proof models:

```text
Event
    -> Journey
    -> Message
    -> Stream
    -> Assignment
    -> Message
    -> Transformation
    -> Message + Stream
```

It also models Message treatment independently from format and size:

```text
Priority
Execution Profile
Durability
```

Examples:

```text
Conversation    immediate, tiny, low-latency intent
Business        validated/promoted/transformed/process-starting intent
PassThrough     move efficiently with minimal inspection
```

## Build examples

```powershell
cargo build --workspace
cargo test --workspace
cargo run --bin xmip-tiny-device
cargo run -p xmip-cli --bin xmip
```

## Implementation rule

No new architectural concept should be added until the current implementation fails to express the need.

Architecture follows working vertical slices.
