# Xmip terminology

Xmip terminology shall avoid ambiguous words in code, configuration, documentation, and diagnostics.

## Process terminology

The bare word **Process** is ambiguous in Xmip and should not be used alone unless the surrounding context makes the meaning unavoidable.

Use these terms instead:

| Term | Meaning |
| --- | --- |
| **System Process** | An operating system process managed by Windows, Linux, macOS, or another host operating system. |
| **Xmip Service** | The master long-running service on a node. One per node, started by the operating system. It reads the configuration, builds and validates the execution tree, then registers, starts and supervises the Xmip Host Services. It is never in the message path: no Stream, Message or Journey passes through it. |
| **Xmip Host Service** | A long-running service registered and started by the Xmip Service to host one or more Modules and, when required, execute Extensions. Many per node. It does the work — Receive Locations, Xmip Processes, Send Locations — and holds exclusiveness over what it is working on. Its service name and description are generated from configuration when it is registered, so an operator reading the service list can tell what each one does. |
| **Host Process** | The System Process an Xmip Host Service runs as. The service is the registered, managed thing; the process is what the operating system schedules. |
| **Xmip Process** | An integration process defined by Xmip configuration and artifacts. It belongs to Xmip runtime semantics, not to the operating system. |
| **Xmip Subprocess** | A configured child part of an Xmip Process. It is not an operating system child process unless explicitly stated as a System Process. |

When a person writes or says **Process** without qualification and the meaning is not clear, the correct response is to ask whether they mean **System Process** or **Xmip Process**.

## Module terminology

A **Module** is compiled code loaded during Xmip Service startup according to configuration.

A Module may provide capabilities such as:

- Transport Handler
- Content Handler
- Logic Handler
- Store Provider
- Management Module

Modules are discovered, verified, loaded, and registered during startup as far as configuration and available metadata allow.

## Extension terminology

An **Extension** is code referenced by an artifact and executed when needed.

Extensions are verified during startup as far as possible, but they are not loaded during startup unless Xmip later defines a specific preloading policy.

## Startup rule

Xmip Service startup builds a validated execution tree from configuration.

The tree identifies:

- Modules to load during startup.
- Xmip Processes to start.
- Xmip Subprocesses and their required Modules.
- Extensions to verify but not load.

Xmip cannot own every incorrect decision made in configuration or code, but it should mitigate predictable mistakes through validation, diagnostics, warnings, and clear failure boundaries.
