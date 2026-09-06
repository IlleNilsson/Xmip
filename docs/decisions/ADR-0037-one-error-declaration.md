# ADR-0037: One error declaration, in core

- Status: Accepted
- Date: 2026-09-06
- Related: ADR-0011 (naming), ADR-0012 (module boundary), ADR-0026 (retry and
  the resilience distinction), docs/governance/rust-style.md

## In brief

- Theme: The shape of the estate
- Subject: A message-carrying error type is declared once, not per crate
- Name: One error declaration
- Order: 9
- Concepts: Error types; shared declaration; consolidation

**Thirteen crates hand-rolled the identical error boilerplate — a
`{ message: String }` struct, a `Display` that writes the message, an empty
`Error` impl. That is now one macro in `xmip-core`: `declare_error!`, and
`declare_retryable_error!` for the two that also carry a `retryable` flag.** The
estate already centralises shared types in `foundation/core` (`Severity`,
`Mechanism`, the id types); these errors were the anomaly.

## Context

The consolidation survey, 2026-09-06, found the same three-item boilerplate in
authenticate, authorize, identify, contract, prepare, transform, receive, event,
archive and audit (a `String` message), and in send and process with an added
`retryable: bool`. `xmip-core-transport` has the one richer version (constructors
and `classify`) and keeps it. Thirteen copies of a pattern the estate otherwise
declares once is drift waiting to happen, and it read as an anomaly against the
"shared types live in core" habit.

## Decision

### 1. Two macros in core

`declare_error!(Name)` expands to the `{ message: String }` struct with `Display`,
`Error` (via `core::error::Error`, which no_std has) and a `new` constructor. The
`message` field stays public, so an existing `Name { message }` literal still
compiles — the migration is mechanical and behaviour-preserving. Doc attributes
pass through (`declare_error!(#[doc = "…"] Name)`).

### 2. Retryable errors get the sibling macro

`declare_retryable_error!(Name)` adds `pub retryable: bool` and `retryable` /
`permanent` constructors, matching what `transport` already offers. This is where
the "modelled three ways" `retryable` flag (the survey's finding) is reconciled
for send and process; the resilience distinction itself is ADR-0026's.

### 3. Transport keeps its own

`transport`'s error carries `classify` and a richer construction surface; it is
the good version, not the boilerplate, and it stays as it is rather than being
forced through the macro.

## Consequences

- `xmip-core` gains `declare_error!` and `declare_retryable_error!`, exported.
- The twelve boilerplate crates replace their hand-rolled type with one macro
  call; each lands on its own, tested, in dependency order behind core.
- New capability crates declare their error in one line instead of copying three
  impls, so the pattern stops spreading.

## Provenance

The finding is the consolidation survey's, 2026-09-06; the owner directed the
whole safe consolidation batch be run. The two-macro shape and the decision to
leave transport's richer error alone are the assistant's drafting of it.
