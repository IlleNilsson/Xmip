# ADR-0002: Saved state and way forward

## Status

Accepted.

## In brief

- Theme: How the work is done
- Subject: Memory lives in the repository
- Name: Saved state and way forward
- Order: 4

Xmip's project memory is stored in the repository, never in conversation
history. Every significant decision becomes an artifact. This document exists
because of that rule.

## Decision

Xmip project memory shall be stored in the repository, not in conversation history.

Every significant decision shall be captured as a project artifact.

## State anchor

The project source of truth is now:

```text
docs/decisions/
docs/architecture/
docs/planning/must-remember.md
.gitmodules.planned
```

*Historical. Two of the four anchors have since been retired:
`.gitmodules.planned` became the real `.gitmodules` when the 43 repositories
were created, and `must-remember.md` was deleted on 2026-08-30 after most of it
went false — its surviving items are `docs/planning/open-problems.md`
problem 19. The first two anchors stand.*

## Current direction

Xmip is a distributed integration platform system.

Xmip Continuum is the umbrella and source composition repository.

`xmip-core` is the core contract and platform model repository.

Handler repositories contain technology-specific implementation.

## Runtime flow baseline

```text
Receive stream
Identify sender
Authenticate and authorize
Transform and promote
Create or update message and interchange metadata
Evaluate subscription or orchestration decision
Execute process or send port
Optionally transform and promote on send side
Send
Audit all significant actions
```

## Refactor direction

Stop growing Xmip Continuum as a mixed prototype.

Move stable core concepts into `xmip-core`.

Move technology-specific code into `xmip-handler-*` repositories.

Keep decisions and architecture in the Continuum repository until a separate documentation repository is justified.

## Next work

1. Create missing handler repositories using ADR-0001 naming rules.
2. Patch `.gitmodules.planned` to match created repositories.
3. Create ADR-0003 for the runtime flow.
4. Move core contracts to `xmip-core`.
5. Continue module loading from the core contract model.
