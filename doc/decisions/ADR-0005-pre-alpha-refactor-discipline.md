# ADR-0005: Pre-alpha refactor discipline

## Status

Accepted.

## In brief

- Theme: How the work is done
- Subject: Pre-alpha refactor discipline
- Name: Pre-alpha refactor discipline
- Order: 2
- Concepts: Refactoring freely, pre-alpha

Code may be moved, split, renamed and reshaped aggressively where that improves
correctness, modularity or alignment with the specification. **When the
implementation conflicts with the specification, the implementation is wrong.**
And where the assistant is unsure, disagrees, drifts from the specification or
suspects it is hallucinating, it must say so before continuing.

## Decision

Xmip is in pre-alpha. Code may be moved, split, renamed, and reshaped aggressively when that improves correctness, modularity, loadability, or alignment with the original specification.

The original Xmip specification and accepted ADRs remain authoritative.

When implementation conflicts with the original specification, the implementation is wrong.

When the assistant is unsure, disagrees, floats away from the specification, or suspects hallucination, that must be stated directly before continuing.

## Engineering rules

Keep the platform:

```text
simple
modularized
compartmentalized
loadable as needed
```

Prefer small modules over large mixed files.

Prefer stable core contracts over handler-specific shortcuts.

Prefer explicit runtime contracts over implied behavior.

Do not introduce new Xmip terminology unless it is accepted by decision.

## Runtime direction

Xmip core owns:

```text
message model
interchange model
audit model
runtime flow
module loading
handler contracts
cluster and node contracts
persistence contracts
```

Handlers own technology-specific implementation.

Send-side and receive-side runtime must stay independently executable because Xmip is pub/sub.

## Build discipline

After meaningful code changes, compile and run tests when possible.

When compilation fails, capture and report the useful error details.

Formatting is important, but formatting must not hide compile or test errors during active pre-alpha refactoring.
