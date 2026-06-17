# Xmip Module Loading

Xmip modules are loaded according to Xmip configuration.

A Module may declare Handlers and Extensions.

Handlers provide technology-specific runtime behavior.

Extensions provide reusable utilities available inside the Xmip runtime.

## Startup discovery

The runtime receives one or more module roots from node configuration.

The ModuleLoader scans those roots for module manifests named:

```text
xmip-module.toml
```

Each manifest describes:

- component id,
- module kind,
- version,
- Xmip contract version,
- platform,
- binary path,
- isolation mode,
- handler lineage,
- communication layering,
- supported technologies.

## Handler registration

The ModuleLoader registers Handler declarations in the HandlerRegistry.

The core runtime uses the HandlerRegistry to resolve configured handler names.

The runtime talks to Handler traits, not concrete handler implementations.

## Extension registration

Extensions are registered in the ExtensionRegistry.

Extensions are runtime utilities and are not Handlers.

Handlers perform technology-specific receive, send, content, or logic work.

Extensions provide reusable support capabilities available to runtime components.

## Current implementation stage

Implemented now:

- manifest model exists,
- module manifest path discovery exists,
- handler registry exists,
- manifest-to-registry registration exists,
- TOML manifest DTO exists,
- extension registry exists.

Still missing:

- TOML manifest conversion into the runtime manifest model,
- dynamic binary loading,
- host process isolation,
- signature and trust validation.
