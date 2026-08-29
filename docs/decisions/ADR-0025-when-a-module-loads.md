# ADR-0025: When a Module loads

- Status: Accepted
- Date: 2026-08-29
- Related: ADR-0018 (the Xmip Service and the Host Service), ADR-0012 (the module boundary), ADR-0022 (identity contexts and host processes)

## Context

ADR-0018 clause 4 gives startup nine phases and puts `load-modules` at phase 6,
"its own Modules, ABI-verified per ADR-0012". Phase 5 says Host Services start
"in configured order".

An order is not a schedule. It says which Module loads before which, and says
nothing about whether the node may begin working before all of them are loaded.
Read literally, phase 9 — `accept-work` — waits for every Module the node
declares, including the ones that only ever produce a report.

That is the wrong trade for the estate this replaces. **A node that cannot
receive is down.** A node that can receive but cannot yet render a report is
working, and the difference matters most at the moment it matters least to the
reporting Module: a cluster coming back after an outage, where every second
before `accept-work` is a second of partner traffic refused.

`xmip-core-runtime`'s `host.rs` already carries `mod dynamic` behind a
`dynamic-loading` feature. It has never compiled, because `xmip-core-abi`
exports the manifest types and not the loading surface its own
`include/xmip_module.h` defines. The code was written to a decision that was
never recorded, against an ABI that was never finished, behind a feature nothing
builds — which is how a compiler never once looked at it.

## Decision

### 1. Configuration decides, and the domain is the default

Load timing is configuration, per Module. Nothing about a Module's technology
implies when it should load, and an operator who depends on an audit sink being
up before the first Message arrives must be able to say so.

**The default comes from `architecturalDomain`, which every repository already
declares in `architecture.toml`:**

| domain | default | why |
| --- | --- | --- |
| Foundation, Capabilities, Platform | eager | on the path a Message travels |
| Operations | delayed | observes the path; does not carry it |

Nothing new to maintain and nothing new to declare. The manifest already sorts
the estate along exactly the line this decision needs, because the line is the
same one: `xmip-core-archive`, `xmip-core-audit`, `xmip-core-diagnose`,
`xmip-core-observe` and `xmip-core-report` are Operations precisely because they
are not what moves a Message.

An explicit setting overrides the default in either direction. A default that
cannot be overridden is a rule pretending to be a default.

### 2. The node is ready when the eager set is loaded

Phase 9 waits for the eager set and no more. Receive Locations poll, Send
Locations are ready and Xmip Processes are runnable while Operations Modules are
still unloaded, because none of those three needs one.

This is what "the cluster is ready at once" means operationally: **ready is a
statement about carrying work, not about having finished starting.**

### 3. Delayed means delay-loaded, not lazily started

A delayed Module is loaded on the first call that needs it — the Windows
delay-load semantics, and deliberately that rather than a background load after
phase 9.

A background load has a window in which the Module is neither loaded nor
loading-on-demand, and something must decide what a call arriving in that window
does. Delay-load has no such window: the first caller loads it, subsequent
callers find it loaded, and there is one path rather than two.

The first caller pays the load. That is the right party — it is the only one who
has expressed an interest.

### 4. A delayed Module that fails to load degrades the node; it does not stop it

An eager Module that fails to load fails the Host Service, and phase 3 already
refuses a configuration that names a Module the node cannot load at all.

A delayed one cannot fail at phase 3, because nothing has tried to load it. When
it fails at first use, the caller gets the failure, the node is reported
degraded per ADR-0018 clause 12, and **work continues**. A node that stopped
receiving because a report could not be rendered would have inverted the whole
decision.

### 5. `xmip-core-abi` exports the loading surface its header already defines

`include/xmip_module.h` is the contract and it is complete. The Rust crate is
behind it, and that gap is what this record closes:

| header | Rust |
| --- | --- |
| `XMIP_ABI_VERSION 1u` | `pub const XMIP_ABI_VERSION: u32` |
| `XMIP_ENTRYPOINT "xmip_create_module_v1"` | `pub const XMIP_ENTRYPOINT: &str` |
| `XmipModuleDescriptor` | `ModuleDescriptor` |
| the `abi_version` check described at section 7 | `validate_module_abi` |

**The Rust names follow the header, less the `Xmip` prefix the crate already
supplies.** C has no namespaces and spells the prefix into every symbol; Rust
does not, and `xmip_abi::XmipModuleDescriptor` says Xmip twice —
`rust-style.md` section 5 on a name repeating its crate.

`host.rs` currently imports `ModuleAbiDescriptor` and `XMIP_MODULE_ENTRYPOINT`,
neither of which is the header's name nor this one. It moves.

### 6. Load timing is not placement

ADR-0022 clause 3 gives a host process the work of one identity context, and
that decides *which* host process a Module is loaded into. This record decides
*when*. The two are independent and neither constrains the other: a delayed
Module loads into the host process its identity context already determined,
whenever it is first called.

## Consequences

- The `dynamic-loading` feature compiles for the first time. It has been dead
  since it was written — the third file in this estate found that way, after
  `technology.rs` and `disposition.rs`, and all three for the same reason:
  nothing ever built the configuration they lived in.
- `Test-XmipModule` gains `cargo build --all-features`. Default-features testing
  cannot see a feature-gated module, so a feature nobody builds is a feature
  nobody compiles, and this ADR would otherwise be the fourth instance rather
  than the last.
- ADR-0018 clause 4 phase 6 reads "its own Modules" and now means "its own eager
  Modules". Phase 9 is reached without the delayed set.
- `architecture.toml` gains an optional per-module load timing. Absent, the
  domain decides, so 43 modules need no edit.
- Startup time becomes a function of the eager set rather than of the estate's
  size. A node that adds a reporting Module does not start more slowly.

## Alternatives considered

**Load everything at phase 6, as ADR-0018 reads today.** Simple, one code path,
and it makes `accept-work` wait on Modules that no arriving Message needs. The
cost lands exactly when a cluster is recovering and every node is loading
everything at once.

**Background load after phase 9.** Everything is loaded shortly after startup
and a failure is discovered without waiting for a caller. Rejected in clause 3:
it needs a second path for calls arriving mid-load, and a second path exists to
be got wrong.

**Criticality named in configuration with no default.** Explicit, and it makes
43 modules declare something the manifest already knows. A default that reads
from `architecturalDomain` cannot drift from the domain, because it is the
domain.
