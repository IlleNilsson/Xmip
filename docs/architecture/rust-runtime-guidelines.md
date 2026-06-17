# Xmip Rust Runtime Guidelines

Xmip uses Rust language guarantees as part of the runtime design.

## Rules

- Message values are immutable after creation.
- Changed content creates a new message.
- Runtime stages pass work by ownership.
- Channels are preferred for stage handoff.
- Shared mutable message state is avoided.
- Runtime failures return `Result`.
- Panics are not normal runtime control flow.
- Handler boundaries are traits.
- Configuration is loaded into typed structures.
- Core runtime avoids unsafe code.

## Concurrency

Xmip stages should own the work they process.

A stage may receive a message, persist state, create an outcome, and pass the outcome to the next stage.

The next stage receives ownership of that outcome.

This keeps thread and task boundaries clear.

## Persistence

A stage persists state when replay requires it.

Runtime persistence is the source of truth for replay.

Management persistence is the source of truth for administration.
