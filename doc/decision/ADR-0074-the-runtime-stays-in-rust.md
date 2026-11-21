# ADR-0074: The runtime stays in Rust

- Status: Accepted
- Date: 2026-11-20
- Related: ADR-0012 (the module boundary), ADR-0014 (the operator
  surfaces), ADR-0016 (submodule composition, amendment 2026-11-20),
  ADR-0018 (service and host, amendment 2026-11-20), ADR-0021 (current
  platforms only)

## In brief

- Theme: The shape of the estate
- Subject: Whether Xmip's runtime moves from Rust to .NET to save build and landing time
- Name: The runtime stays in Rust
- Order: 19
- Concepts: Rust; .NET; build time; landing time; garbage collection; millisecond rule

**The runtime, the command line and every rule the surfaces share stay in
Rust. .NET keeps what it has: the PowerShell module, the GUI and the
management tooling. Build time and landing time are won in how the work is
done, never by changing the runtime's language.**

## Context

The owner, 2026-11-20, while the one-workspace change (ADR-0016, amendment
2026-11-20) took the evening to land: *I'm seriously thinking of ditching
Rust in favor of dotnet, prove me wrong.* Then: *So give me an estimate on
what we can gain on going full dotnet*, and, given it: *And comparing that
to runtime values. I choose Rust for runtime values.* And last: *So I'll
keep the design as it is. I have to be patient and you have to be smarter,
faster.*

What a landing cost that day, measured on the Windows landing machine: the
Pester part about 12 minutes, the timing programs, run alone, about 8; the
code checks of a change to a few crates 5 to 10 minutes, and of a change
touching every crate's manifest about an hour, which is what that evening
paid.

## The comparison

Measured is marked as such; everything else is the assistant's estimate of
the same day.

| | Rust | All .NET |
| --- | --- | --- |
| Xmip's own share of a carried file | 0.35 to 0.5 ms on Windows, 0.35 ms on Linux (measured) | a similar median; a garbage collection pause takes the slowest past 1 ms, and the collector is not tuned |
| Under load | no collector: no pause Xmip does not control | pauses Xmip does not control |
| Reach | `xmip-core` builds with no operating system, down to a microcontroller | only a board that carries a .NET runtime |
| Memory of a node | no runtime carried | about 30 to 70 MB more |
| A normal landing | about 20 to 25 minutes | about 15 to 20 minutes |
| A landing touching every crate | about an hour | about 10 to 15 minutes |
| The move itself | none | about 496,000 lines and 5,518 tests rewritten: 4 to 8 weeks, past the demo in December 2026 |

What .NET would bring besides time: one language, with no C ABI between
the runtime and the surfaces, and engines Xmip lacks today, XSLT 1.0 and
CMS, in its own library.

## Decision

1. **The runtime stays in Rust**, with `xmip-core`, the command line
   (ADR-0014, rule 8) and every rule the surfaces share (ADR-0014). Across
   languages the boundary stays the C ABI (ADR-0012).
2. **.NET keeps what it has**: the PowerShell module, the GUI and the
   management tooling. Nothing moves either way.
3. **The time is won in the work.** The estate builds as one workspace
   (ADR-0016, amendment 2026-11-20); debug builds compile its own crates at
   opt-level 1 with line tables, and the millisecond rule is measured in an
   optimized build of its own (ADR-0018, amendment 2026-11-20); a landing
   runs its Rust, .NET and Pester parts side by side. A change is planned
   with its build and landing time before it is started.

## Why

The saving is minutes a landing, paid once at a desk. Rust's gains are
paid back on every Message, on every node, at every installation: a
share well under the millisecond with no pause Xmip does not control
(ADR-0018), and a runtime that reaches a board with no operating system.
Most of a normal landing is Pester and the timing programs, which a
change of language does not shorten.

## Provenance

The question and the decision are the owner's, 2026-11-20, quoted above.
The landing times, the shares on Windows and on Linux and the line and
test counts are measured on the estate that day. The .NET column, the
rewrite's length and the memory figure are the assistant's estimates, the
same day.
