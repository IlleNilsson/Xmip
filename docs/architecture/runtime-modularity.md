# Xmip Runtime Modularity

Xmip runtime capabilities shall not be compiled into the Xmip Kernel as fixed source modules.

The Xmip Kernel is responsible for:

- loading module metadata,
- validating module compatibility,
- loading runtime binaries,
- isolating module execution when required,
- enforcing ownership, identity, authorization, audit, tracing, and tracking rules,
- calling modules through stable contracts.

Runtime capabilities are delivered as loadable components.

Examples include:

- receive technologies,
- send location technologies,
- content handlers,
- logic handlers,
- transformations,
- process handlers,
- custom extensions.

## Loadable binary model

A loadable Xmip component may be packaged as a platform-specific binary such as:

```text
Windows: .dll
Linux:   .so
macOS:   .dylib
```

The end user shall not need to compile Xmip Kernel to install or use a new runtime capability.

A component is installed by placing its package and manifest where the Xmip runtime can discover it, or by registering it through Xmip deployment tooling.

## Kernel boundary

The Kernel must not know implementation details of HTTP, file, queue, FTP, SFTP, FTPS, SOAP, REST, WebHook, MLLP, EDI, HL7, FHIR, or future technologies.

The Kernel knows stable contracts and runtime policies.

Technology-specific behavior belongs in loadable components.

## Manifest

Each loadable component shall provide metadata describing:

- component id,
- component kind,
- component version,
- supported Xmip contract version,
- platform,
- binary path,
- required capabilities,
- supported technologies,
- trust requirement,
- isolation requirement.

## Isolation

A component may run:

- in-process,
- out-of-process,
- in a trusted host process,
- in an untrusted host process,
- in a 32-bit host process,
- in a 64-bit host process,
- in a low-latency host process.

The Kernel decides where a component may run based on Host Type, Artifact Definition, component manifest, trust, platform, and configured policy.

## Principle

Xmip Kernel is stable runtime infrastructure.

Xmip modules are replaceable runtime capabilities.

Adding or replacing a module must not require recompiling Xmip Kernel.
