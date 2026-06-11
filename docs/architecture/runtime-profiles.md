# Xmip Runtime Profiles

Xmip runs mainly on servers.

The normal server runtime loads capabilities according to Xmip configuration, normally TOML, and should load handlers on demand instead of requiring the Kernel to be recompiled.

Xmip shall also support purpose-built runtimes for smaller devices, endpoint sites, and special server-side deployments.

## Server runtime

The server runtime is the full Xmip runtime.

It supports:

- dynamic loadable modules,
- TOML-driven configuration,
- receive ports and receive locations,
- send ports and send locations,
- process execution,
- subscription matching,
- audit,
- tracing,
- tracking,
- persistence,
- clustering,
- management,
- updates,
- deployment tooling.

The server runtime should discover and load modules as needed based on configuration.

## Purpose-compiled runtime

A purpose-compiled runtime is a smaller Xmip runtime built for a specific target, site, endpoint, embedded use case, industrial use case, or constrained environment.

It may include only the capabilities required by that deployment.

Examples:

- a small endpoint collector,
- an industrial gateway,
- a CANBUS bridge,
- a telemetry forwarder,
- a field-site agent,
- a locked-down server-side appliance,
- an air-gapped special-purpose integration node.

A purpose-compiled runtime may statically include selected handlers instead of dynamically loading them.

This is allowed when the deployment target benefits from:

- smaller footprint,
- fewer files,
- simpler installation,
- stricter security,
- constrained hardware,
- offline deployment,
- deterministic behavior.

## Configuration

Both runtime profiles are configured by Xmip definitions.

The server runtime may load modules on demand according to TOML configuration.

The purpose-compiled runtime may compile selected capabilities into the executable, but it must still behave according to Xmip definitions and runtime contracts.

## Principle

Xmip Kernel modularity remains the default.

Purpose compilation is an allowed packaging strategy, not a replacement for modularity.

Small devices and endpoint-side deployments must not force the full server runtime footprint.
