# ADR-0036: The Playground is optional scaffolding, mounted at the estate root

- Status: Accepted
- Date: 2026-09-06
- Related: ADR-0016 (submodule composition), ADR-0028 (the Xmip Playground),
  ADR-0011 (module and repository naming), docs/architecture/repository-model.md

## In brief

- Theme: The shape of the estate
- Subject: A repository may declare its mount and mark itself optional
- Name: The Playground is optional scaffolding
- Order: 8
- Concepts: Mount, declared versus computed; optional repository; test scaffolding

**The Playground is its own repository (`xmip-test-playground`), and it is not a
capability the runtime loads — it is what exercises Xmip. So it mounts at the
estate root as `tests/playground`, not under `modules/`, and it is declared
optional: the estate builds and runs without it.** Two new manifest keys carry
this: `mount` overrides the computed path, `optional` marks a repository the core
gate does not require.

## Context

The owner, 2026-09-06: the Playground *should be in its own repository, mounted
as an optional submodule.* It was already its own repository, but mounted at
`modules/operations/playground` — the domain-grouped path `Get-XmipMountPath`
computes from `architecturalDomain`. That path says "a module the runtime loads
under Operations", which the Playground is not: it spawns nodes and drives every
transport and contract through them (ADR-0028). Its provider namespace is already
`test` (`[xmip.test.playground]`), so the mount was the part still saying the
wrong thing.

## Decision

### 1. Mount is declared when computing it is wrong

`Get-XmipMountPath` computes `modules/<domain>/<leaf>` for a module, which is
right for a capability. A repository that is not a capability may declare
`mount`, and the declared value wins. The Playground declares
`mount = "tests/playground"`: the estate root, beside the estate's own tests,
not under `modules/`. This is the first non-`modules/` submodule mount, and the
mechanism is general — any future non-module repository uses the same key.

### 2. Optional is declared, and recorded now

`optional = true` marks a repository the estate builds and runs without. The
Playground is the first: nothing in the runtime depends on it, and a checkout
without it is a complete Xmip. The flag is **recorded now**; the tooling that
acts on it — not cloning it by default, excluding it from the core landing gate —
is deferred (the owner's call, 2026-09-06). Recording it first means the manifest
states the intent before the machinery arrives, which is the estate's habit.

### 3. The provider namespace was already right

`[xmip.test]` is the namespace for what exercises Xmip, open to other providers
(ADR-0028's note). Nothing there changes. Only the mount and the optional flag
are added; the repository, its name, and its dependencies are untouched.

## Consequences

- `architecture.toml` gains `mount` and `optional` on `[xmip.test.playground]`;
  `Resolve-XmipNodeFacts`, `Expand-XmipEstate` and `New-XmipRepositoryEntry` carry
  them onto the manifest, and `Get-XmipMountPath` honours `mount`.
- `.gitmodules` mounts the submodule at `tests/playground`; the working tree moves
  there by `git mv`.
- ADR-0028's path reference is updated to `tests/playground`.
- No module repository changes: this is a superproject move plus the resolver.

## Provenance

The requirement is the owner's, 2026-09-06: the Playground in its own repository,
mounted as an optional submodule, at the estate root under a test path. The
`mount`/`optional` mechanism and the deferral of the optional tooling are the
assistant's drafting of it, on the instruction to proceed and write it down.
