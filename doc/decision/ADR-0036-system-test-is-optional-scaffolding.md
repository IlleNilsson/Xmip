# ADR-0036: The System Tests are optional scaffolding, mounted at the estate root

- Status: Accepted
- Date: 2026-09-06
- Amended: 2026-11-23 — named the System Tests and the Systems Tests (ADR-0028,
  amendment of that date)
- Related: ADR-0016 (submodule composition), ADR-0028 (the Xmip System Tests),
  ADR-0011 (module and repository naming), doc/architecture/repository-model.md

## In brief

- Theme: The shape of the estate
- Subject: A repository may declare its mount and mark itself optional
- Name: The System Tests are optional scaffolding
- Order: 8
- Concepts: Mount, declared versus computed; optional repository; test scaffolding

**The System Tests are a repository of their own (`xmip-test-system-test`), and they are
not a capability the runtime loads — they are what exercises Xmip. So they mount at the
estate root as `test/system-test`, not under `module/`, and they are declared
optional: the estate builds and runs without them.** Two new manifest keys carry
this: `mount` overrides the computed path, `optional` marks a repository the core
gate does not require.

## Context

The owner, 2026-09-06: the System Tests *should be in its own repository, mounted
as an optional submodule.* They were already a repository of their own, but mounted at
`module/operation/system-test` — the domain-grouped path `Get-XmipMountPath`
computes from `architecturalDomain`. That path says "a module the runtime loads
under Operations", which the System Tests are not: they spawn nodes and drive every
transport and contract through them (ADR-0028). Their provider namespace is already
`test` (`[xmip.test.system-test]`), so the mount was the part still saying the
wrong thing.

## Decision

### 1. Mount is declared when computing it is wrong

`Get-XmipMountPath` computes `module/<domain>/<leaf>` for a module, which is
right for a capability. A repository that is not a capability may declare
`mount`, and the declared value wins. The System Tests declare
`mount = "test/system-test"`: the estate root, beside the estate's own tests,
not under `module/`. This is the first non-`module/` submodule mount, and the
mechanism is general — any future non-module repository uses the same key.

### 2. Optional is declared, and recorded now

`optional = true` marks a repository the estate builds and runs without. The
System Tests are the first: nothing in the runtime depends on them, and a checkout
without them is a complete Xmip. The flag is **recorded now**; the tooling that
acts on it — not cloning it by default, excluding it from the core landing gate —
is deferred (the owner's call, 2026-09-06). Recording it first means the manifest
states the intent before the machinery arrives, which is the estate's habit.

### 3. The provider namespace was already right

`[xmip.test]` is the namespace for what exercises Xmip, open to other providers
(ADR-0028's note). Nothing there changes. Only the mount and the optional flag
are added; the repository, its name, and its dependencies are untouched.

## Consequences

- `architecture.toml` gains `mount` and `optional` on `[xmip.test.system-test]`;
  `Resolve-XmipNodeFacts`, `Expand-XmipEstate` and `New-XmipRepositoryEntry` carry
  them onto the manifest, and `Get-XmipMountPath` honors `mount`.
- `.gitmodules` mounts the submodule at `test/system-test`; the working tree moves
  there by `git mv`.
- ADR-0028's path reference is updated to `test/system-test`.
- No module repository changes: this is a superproject move plus the resolver.

## Provenance

The requirement is the owner's, 2026-09-06: the System Tests in a repository of their own,
mounted as an optional submodule, at the estate root under a test path. The
`mount`/`optional` mechanism and the deferral of the optional tooling are the
assistant's drafting of it, on the instruction to proceed and write it down.
