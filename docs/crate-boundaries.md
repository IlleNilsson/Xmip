# Crate boundaries

Xmip is currently a Rust workspace prototype. The repository is modular through workspace crates, not Git submodules.

## Foundation crates

```text
xmip-core
    Shared runtime/message/artifact concepts.

xmip-module-abi
    Small, stable, ABI-safe dynamic loading boundary.

xmip-module-api
    Module and extension contracts, manifests, handler traits, and DTOs.
    Re-exports ABI constants and descriptors for module authors.

xmip-configuration
    TOML configuration model and mapping into runtime startup configuration.

xmip-runtime
    Execution tree, capability registry, runtime node model, dispatch contracts.

xmip-service
    Xmip Service startup planner and typed startup phases.

xmip-host
    Host Process lifecycle and dynamic module verification.

xmip-persistence
    Durable checkpoint, deduplication, and store contracts.

xmip-tracking
    Tracking event contracts.

xmip-cli
    Prototype command-line surface.
```

## Module crates

```text
xmip-handler-file
    Example transport module.
```

More handlers, content modules, and store modules can be added as workspace crates first. When the module API boundary is stable, independently maintained modules can move to separate repositories.

## Rule

Platform foundation stays together while the architecture is still settling.

Loadable modules may later become independent repositories because they depend on contracts rather than internal implementation.
