# Xmip terminology

Xmip uses explicit terms when a word has more than one valid meaning in the platform.

## Process terminology

The bare word **Process** is ambiguous in Xmip and should be avoided in code, configuration, documentation, and diagnostics unless the meaning is already explicit from the immediate context.

Use these terms instead:

| Term | Meaning |
| --- | --- |
| **System Process** | An operating-system process managed by Windows, Linux, macOS, or another operating system. |
| **Xmip Process** | An integration process defined and executed by Xmip. It may include receive, assignment, transformation, routing, execution, and send behavior. |

When the intended meaning is unclear, ask for clarification instead of assuming.

## Module and Extension terminology

| Term | Meaning |
| --- | --- |
| **Module** | Compiled code loaded during Xmip Service startup according to configuration. A module registers capabilities with the runtime. |
| **Extension** | Code referenced by an artifact and verified during startup as far as possible, but loaded only when execution requires it. |
| **Host Process** | A System Process created or managed by Xmip to host modules and extensions under a specific trust, runtime, bitness, or latency boundary. |
| **Artifact** | A configured Xmip definition such as a receive port, receive location, Xmip Process, assignment, transformation, send port, or send location. |

Xmip validates what it can during startup. It cannot own every bad decision in configuration or extension code, but it should mitigate avoidable failures by building and validating a clear execution tree before runtime execution begins.
