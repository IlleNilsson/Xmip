# Module loading model

Xmip modules are compiled components loaded by a Host Process during Xmip Service startup according to configuration.

A module may be implemented in Rust or another supported technology, but the runtime boundary must remain stable.

## Execution thread

Loading a dynamic library does not create a new thread.

When a Host Process calls a module entrypoint or handler function, the module code runs on the calling thread unless Xmip explicitly schedules that call on another worker thread.

```text
Host Process thread
    -> calls Module function
    -> Module code executes on that same thread
    -> returns to Host Process
```

If isolation is required, Xmip uses a separate Host Process. If concurrency is required, Xmip schedules work on a worker thread or thread pool.

## ABI boundary

Rust traits are not the raw dynamic-library boundary.

The safe model is:

```text
Dynamic library boundary
    -> stable ABI entrypoint
    -> versioned module descriptor / function table
    -> Xmip-owned safe wrapper
    -> Rust traits inside the Host Process
```

The `xmip-module-api` crate defines the contracts that module authors implement and Xmip wrappers rely on. The dynamic ABI must be explicit, versioned, and checked before a module is accepted.

## Lifecycle

```text
Xmip Service
    -> reads configuration
    -> builds execution tree
    -> validates startup
    -> plans System Processes
    -> starts Host Processes
    -> Host Processes load configured Modules
    -> Modules register capabilities
    -> Extensions are verified, but not loaded until execution requires them
```

## Rule

Modules are loaded at startup.
Extensions are verified at startup where possible, but loaded only when needed.
