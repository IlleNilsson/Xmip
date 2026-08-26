# ADR-0012: The module boundary

## Status

Accepted. Implementation follows in separate reviewed changes.

## Context

`crates/xmip-module-abi` defines the loading boundary today:

```rust
pub const XMIP_MODULE_ABI_VERSION: u32 = 1;
pub const XMIP_MODULE_ENTRYPOINT: &str = "xmip_create_module_v1";

#[repr(C)]
pub struct ModuleAbiDescriptor {
    pub abi_version: u32,
    pub module_kind: ModuleAbiKind,
}

#[repr(C)]
pub enum ModuleAbiKind {
    TransportHandler = 1,
    ContentHandler   = 2,
    LogicHandler     = 3,
    StoreProvider    = 4,
    ManagementModule = 5,
}
```

The foundation is sound. It is `#[repr(C)]`, it is versioned, and it loads through a named entrypoint symbol — a genuine dynamic boundary, language-neutral by construction. That matches `artifact-model.md`, which lists Rust, C, C++, COM, .NET, Java, PowerShell and native binaries as module technologies.

Three things no longer fit.

**Five kinds cannot describe seventeen traits.** Each core module owns its own trait and loads its own implementations. `xmip-core-transform-xslt`, `xmip-core-path-xpath`, `xmip-core-authenticate-oauth2` and `xmip-core-exclusiveness-redis` are none of Transport, Content, Logic, Store or Management. `StoreProvider` and `ManagementModule` correspond to no current module. The enum is vocabulary from an earlier model.

**One global version cannot carry seventeen contracts.** `XMIP_MODULE_ABI_VERSION` is a single number for the whole platform. Seventeen traits will evolve at different rates. Under one number, any change to any trait invalidates every module in the system — which makes independent runtime upgrade of a sub-module impossible, and that is the property the repository and sub-module split exists to provide.

**The Rust convenience crate has become the specification.** `crates/xmip-module-api` does this:

```rust
pub use xmip_core::contracts::*;
pub use xmip_abi::{ ... };
```

Re-exporting Rust types means a module author compiles against Xmip source. That pulls every implementer into Rust, and because Xmip is AGPL-3.0-or-later it pulls their module into AGPL with it. Xmip's position is that a third party brings their own licence and their own support. A boundary that only works by linking Xmip code cannot deliver that.

## Amendment, 2026-08-26: the boundary faces both ways

This record was written about Modules plugging **in**. `xmip-core-abi` is also
the interface Xmip is driven **from outside** — configuration, runtime,
observing, eventing, auditing — and ADR-0014 now has `cli`, `powershell` and
`gui` as its clients.

Everything below still holds: one C header, `#[repr(C)]` function pointers, no
`dyn Trait` across it, no unwinding, ownership and error representation
specified rather than conventional. Those properties are what make it usable by
a .NET surface through P/Invoke at all.

**What changes is who it must stay stable for.** Clause 6 versions each core
module's trait independently, which was sized for module authors. An operator
surface is a second audience with its own compatibility expectations, and the
two now share one header. That needs a versioning answer this record did not
have to give when the boundary faced one direction.

## Decision

1. The normative module boundary is a written ABI specification and a C header. Not a Rust crate.
2. Rust bindings remain available as convenience. A module author is never obliged to use them, and conformance is judged against the specification.
3. The interface is a `#[repr(C)]` table of `extern "C"` function pointers, defined and versioned by Xmip.
4. Rust traits are an implementation ergonomic on the Xmip side only. `dyn Trait` never crosses the boundary — Rust trait objects have no stable layout, and passing one across a toolchain change is undefined behaviour.
5. `ModuleAbiKind` is removed. The descriptor carries the module name as a string.
6. Each core module versions its own trait independently.
7. Ownership, lifetime and error representation are part of the specification, not left to convention.
8. Unwinding never crosses the boundary.

9. The boundary carries no licence exception. The header is AGPL-3.0-or-later like the rest of Xmip. A user takes Xmip under Xmip's licence and may additionally have to satisfy the licences of what Xmip itself depends on; reconciling that is the user's business, not Xmip's.

10. The binding crate is `xmip-core-abi`. It replaces `crates/xmip-module-abi` (whose package is actually named `xmip-abi`) and `crates/xmip-module-api`. Neither parses under ADR-0011 — there is no provider named `module` — and the first disagrees with its own package name.

11. `abi`, `cli` and `powershell` are surface modules, open to any provider. Xmip publishes `xmip-core-abi`; a provider extends it with `xmip-<provider>-abi`, and may ship `xmip-<provider>-cli` and `xmip-<provider>-powershell` for the command line. They take a provider and stop, because there is no external standard to name.

## The descriptor

```c
typedef struct {
    uint32_t    abi_version;      /* handshake version — currently 1        */
    const char* provider;         /* "core", "saxon", "acme"                */
    const char* module;           /* "transport", "path", "contract"        */
    const char* standard;         /* "http", "xpath" — null for none        */
    uint32_t    trait_major;      /* trait version built against            */
    uint32_t    trait_minor;
    uint32_t    module_major;     /* the module's own version               */
    uint32_t    module_minor;
    uint32_t    module_patch;
} XmipModuleDescriptor;
```

`provider`, `module` and `standard` are the three parts of the repository name from ADR-0011. The name and the declaration state the same fact once.

## Compatibility

A core module accepts an implementation when all hold:

```text
abi_version   equals the host handshake version
module        equals the loading core module
trait_major   equals the core module trait major
trait_minor   is less than or equal to the core module trait minor
```

Semver-major on the trait is the minimum that makes independent sub-module upgrade real. Exact matching would force every implementation to rebuild whenever any trait changed, which defeats the purpose. Capability negotiation was considered and rejected for now: it is more flexible and much harder to diagnose when a module fails to load.

Each of the seventeen traits therefore carries a public compatibility promise. That is a real maintenance commitment and should be sequenced deliberately rather than accrued by accident.

## Boundary rules

**Ownership.** Every pointer crossing the boundary declares who allocates, who frees, and how long it remains valid. Rust ownership does not survive the crossing. The architecture baseline already names buffer ownership as part of the minimal module foundation; this is that.

**Unwinding.** A Rust panic crossing `extern "C"` is undefined behaviour, as is a C++ exception, a C# exception or a Java throwable. An implementation catches at its own boundary and returns an error code. The host treats an unwind as a fatal module defect.

**No Rust types in the interface.** No `String`, no `Vec`, no `Box<dyn Trait>`, no enum without `#[repr(C)]`. Slices cross as pointer and length.

## Consequences

`xmip-module-abi` becomes the reference implementation of a specification that lives beside it as a document and a header. Publishing that header is what makes "their licence, their support" true in practice rather than in principle.

A module written in C#, PowerShell or Java never links Xmip code at all. A module written in Rust may use the bindings for ergonomics, or declare the same `extern "C"` signatures itself, exactly as a C author would.

`xmip-module-api` stops re-exporting `xmip_core::contracts::*`. What a module needs from the domain model is expressed in the specification, in C-compatible form.

The existing `module_kind` values disappear. `xmip-handler-file`, the one concrete implementation, migrates to `xmip-core-transport-file` under ADR-0010 and adopts the new descriptor at that point.

## The specification

Written. It is `docs/architecture/module-abi-specification.md`, with the header at `include/xmip_module.h`.

It covers the universal boundary — primitives, status codes, the descriptor, streams, the host table, the module handle, the entrypoint and the vtable header — and four trait tables: transport, message, path and contract. Those four are creation wave one.

The other thirteen traits are deliberately unspecified. The reasoning above still holds for them: a trait table designed without an implementation in front of it is a guess, and a guess published as `v1` becomes a permanent compatibility promise. Each is written when its first implementation is.

## The licence of the boundary

Clause 9. `include/xmip_module.h` is AGPL-3.0-or-later, like the rest of Xmip.

A permissive header was considered and rejected. The case for it: the header is the one file a third party must copy into their own build, so under AGPL it carries AGPL with it, and an implementer inherits Xmip's licence by the act of `#include`. The case against, and the one that decided it: Xmip does not undertake to resolve anyone's licensing position. A user takes Xmip under Xmip's licence, and may additionally have to satisfy the licences of what Xmip itself depends on. Reconciling that is the user's business.

What this ADR set out to make possible is unaffected. A module author is not obliged to write Rust, is not obliged to link Xmip code, and compiles against a C ABI rather than against Xmip source. That is a technical boundary and it stands. It was never a licence exemption, and "the boundary is the trait, not the licence" describes where Xmip stops dictating design.

## The binding crate and the surface modules

Clauses 10 and 11. `abi` is a core module with a plugin surface, not internal plumbing. Xmip publishes `xmip-core-abi`. Any provider may extend it.

```text
xmip-core-abi      xmip-core-cli      xmip-core-powershell
xmip-acme-abi      xmip-acme-cli      xmip-acme-powershell
```

These are **surface** modules under ADR-0011: a provider extends Xmip's own surface rather than implementing someone else's specification, so there is no standard to name and the name stops at the provider. That is the one case where a non-`core` provider may omit the last slot.

A binding is a convenience over the header, never the definition of the boundary and never normative. A module that skips every binding and writes `extern "C"` by hand is exactly as conformant — which is the point of specifying the boundary in C rather than in a language.

`xmip-module-api` collapses rather than moves. Its entire content is `pub use xmip_core::contracts::*` plus a re-export of the other crate; once the first goes, as clause 2 and the Consequences section require, nothing is left worth renaming.

## Open

Nothing in this ADR. What remains is implementation: a first module built against the specification, and a conformance suite able to drive the seven rules in its section 11 from outside a module.
