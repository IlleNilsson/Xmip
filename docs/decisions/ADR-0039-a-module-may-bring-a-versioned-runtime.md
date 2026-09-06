# ADR-0039: A Module may bring a versioned language runtime

- Status: Accepted
- Date: 2026-09-06
- Related: ADR-0012 (the module boundary), ADR-0018 (the Xmip Service and the Host
  Service), ADR-0022 (identity contexts and host processes), ADR-0025 (when a
  Module loads), docs/architecture/module-model.md

## In brief

- Theme: Modules and the boundary
- Subject: Hosting a Module written in a managed language may require loading its
  runtime, and that is accepted
- Name: A Module may bring a versioned runtime
- Order: 4
- Concepts: Language runtime; managed Module; runtime version; native Module

**The module boundary is a C ABI, so a Module may be written in any language that
can produce or call a stable C entry point — Rust, C, C++, and equally .NET, Java
or Python (module-model.md). A Module written in a managed language needs its
language runtime present to run. Xmip accepts loading that runtime, and the
runtime is versioned: the Module declares which runtime and which version it
needs, and the node provides it. A native Module brings no runtime; a managed one
brings the runtime as a dependency.**

## Context

The estate already admits eight module languages (module-model.md): Rust, C, C++,
COM, DCOM, PowerShell, .NET and Java. The ABI specification is deliberate that the
boundary is a C ABI and language-neutral (ADR-0012). What had not been written
down is the plain consequence: a Module written in .NET, Java or Python cannot run
without the CLR, the JVM or a CPython interpreter, and something has to load it.

The owner, 2026-09-06, on wiring the first .NET technology into the manifest: *if
Xmip needs to load a versioned runtime, being dotnet, java or python, so be it.*
That settles the open cost. It also matches where the estate already is — `cli`,
`gui` and `powershell` are `.NET`/PowerShell surfaces over the ABI, and the
manifest now carries a `xmip-core-contract-dotnet` technology whose
`primaryCrate.language` is `dotnet`.

## Decision

### 1. A managed Module names its runtime and version

A Module that needs a language runtime declares it — the runtime family (.NET,
JVM, CPython, …) and the version it requires — the way any dependency is declared.
The version is part of the declaration, not left to whatever the host happens to
have, so a Module that needs .NET 11 says .NET 11 and fails closed on .NET 10
rather than misbehaving.

### 2. The node profile provides the runtime, or the Module does not load

Providing the declared runtime is the node's responsibility (ADR-0018 startup,
ADR-0025 load timing). A node whose profile cannot satisfy a Module's runtime does
not load that Module and says so — a missing runtime is a reported, actionable
absence, not a crash. A purpose-compiled or device profile that carries no managed
runtime simply hosts no managed Modules; the deployment model already allows a
node to host a subset.

### 3. A native Module remains the zero-runtime case

Rust, C and C++ Modules link to the boundary directly and bring no runtime. They
stay the lightest option and the only one available where no runtime can run
(a Meadow-class device, ADR-0018 / open problem 22). Choosing a managed language
is choosing its runtime footprint knowingly.

### 4. Isolation follows the existing rules

A loaded runtime runs under the identity-context and host-process rules already
set (ADR-0022): where a managed runtime must be isolated — its own process, its
own lifetime — that is the host-process boundary doing its job, not a new
mechanism. A Module that unwinds or corrupts its runtime must not take the Xmip
Service with it, exactly as the ABI specification requires of any Module.

## Consequences

- A technology Module may be authored in .NET, Java or Python and plugged in over
  the ABI; `xmip-core-contract-dotnet` is the first so declared.
- Such a Module's manifest and node profile must account for the runtime and its
  version; deployment for a node hosting managed Modules is heavier by that
  runtime.
- The runtime version is pinnable per deployment, so two nodes may run different
  runtime versions for the same Module family without one dictating the other —
  consistent with latest-everywhere until the first Linear release, then pinned.
- Nothing changes for native Modules, and nothing forces a runtime onto a node
  that hosts none.

## Provenance

The ruling is the owner's, 2026-09-06: *if Xmip needs to load a versioned runtime,
being dotnet, java or python, so be it.* The declaration/version, node-provision,
native-zero-runtime and isolation framing are the assistant's drafting of it, on
the instruction to write it down, grounded in ADR-0012, ADR-0018, ADR-0022,
ADR-0025 and module-model.md.
