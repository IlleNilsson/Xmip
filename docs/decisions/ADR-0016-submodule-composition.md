# ADR-0016: Submodule composition

- Status: Accepted
- Date: 2026-08-25
- Supersedes: `.gitmodules.planned`, `Invoke-SynchronizeSubmodules` in `Sync-XmipEstate.ps1`
- Related: ADR-0010 (direction-neutral transport), ADR-0011 (naming), ADR-0015 (packaging)

## In brief

- Theme: The shape of the estate
- Subject: Submodule composition mirrors ownership
- Name: Submodule composition
- Order: 2
- Concepts: Submodules

Two levels, each owned by the repository that pins it. `Xmip` pins
`modules/transport`; `xmip-core-transport` pins `modules/kafka`. A parent pins
commits, and reconciliation never uses `git submodule update --remote`.

## Context

`architecture.toml` schema 2.0 makes the tree the data. A repository name is
derived from its position:

```
provider.core.module.transport                        -> xmip-core-transport
provider.core.module.transport.implementation.kafka   -> xmip-core-transport-kafka
```

Thirty-six modules, two hundred and sixty-eight implementations. Composition
has to come from the same tree, or the name and the layout drift the moment
someone edits one and not the other.

Three things already in `main` disagree with that:

1. `.gitmodules.planned` describes a superseded `xmip-handler-*` plan and
   contains no entries.
2. `Invoke-SynchronizeSubmodules` reads a flat `repositories[]` array with
   per-repository `submodule.enabled` and `submodule.path` — schema 1, which
   `architecture.toml` does not have and should not grow.
3. `modules/` was occupied by sixteen README files under the abandoned .NET
   taxonomy (`modules/ip/tcp/http/Xmip.Handler.Soap/`), while also being the
   value of `default.submoduleRoot`. Cleared in `a3b001e` along with
   `handlers/`, `docs/submodules/` and `.gitmodules.planned` — sixty-nine
   files in all.

## Decision

**1. Two levels, each owned by the repository that pins.**

```
Xmip                     modules/transport   -> xmip-core-transport
xmip-core-transport      modules/kafka       -> xmip-core-transport-kafka
```

A `.gitmodules` file belongs to the repository doing the pinning. The root
never reaches past its own children; a module repository composes its own
standards. Recursion is git's job, not the manifest's.

**2. The path is the manifest key, not the repository name.**

`modules/transport`, not `modules/xmip-core-transport`. The path mirrors the
TOML tree exactly, so a reader who knows one knows the other. The submodule
*name* stays the full repository name, which is what `git config` keys on.

**3. Composition is gated by existence, not by maturity.**

`maturity` decides whether `Sync-XmipEstate` creates a repository. It has
nothing to say about pinning: you cannot pin what does not exist, and anything
that does exist is worth pinning. `Sync-XmipRepository -Submodule` reports the absent
ones and carries on.

**4. How Cargo sees `modules/` is UNRESOLVED and blocks the rest.**

Two decisions taken separately turn out to contradict each other.

*Exclude from the workspace* was chosen so root CI stays fast and independent:

```toml
[workspace]
exclude = ["modules"]
```

*Path dependencies through submodules* was chosen so a recursive clone builds
with no publishing step:

```toml
[dependencies]
xmip-core-route = { path = "modules/route" }
```

These pull opposite ways. A path dependency means the root cannot compile
without the submodules present, so CI must check out recursively and a broken
submodule breaks the root — precisely what the exclusion was meant to prevent.

Resolve it one of two ways, and this ADR is not final until it is:

- **Path dependencies win.** `modules/*` become workspace members, CI checks
  out with `--recurse-submodules`, the exclusion goes. The assembly always
  builds; root CI is slower and coupled to thirty-six repositories.
- **Independence wins.** Module crates are consumed as versioned dependencies
  from a registry, not paths. Root CI stays fast; publishing has to exist
  before anything compiles, and iteration across two modules gets slow.

Everything else in this ADR holds either way.

**5. Submodules track `main`; the pin is still a commit.**

`git submodule add -b main` records a branch so that
`git submodule update --remote` has somewhere to go, but what is committed in
the superproject remains a specific SHA. Release builds resolve to those SHAs
and nothing moves under them.

**6. `modules/` is cleared before anything is mounted. Done.**

Sixty-nine files removed in `a3b001e`: `modules/` (16), `handlers/` (35),
`docs/submodules/` (11), `docs/architecture/handler-submodules-*.md` (6) and
`.gitmodules.planned`. Every leaf under `handlers/` was checked against the
199 implementation entries in `architecture.toml` first; the only six that did
not match were aliases of entries that do exist — `apache-kafka` for `kafka`,
`edi` for `edi-x12`, `hl7` for `hl7-v2`, `raw-tcp` for `tcp`, `raw-udp` for
`udp`, `web-api` for `openapi`. Nothing was lost.

Eight handler-era documents were deliberately left behind pending a decision:
`handler-taxonomy.md`, `handler-lineage.md`, `handler-specification-map.md`,
the three `*-handler-lineage.md`, `content-handlers.md` and
`handler-implementation-plan.md`. `ADR-0004-handler-universe.md` stays and
should be marked superseded rather than deleted.

## Consequences

- A fresh `git clone` of `Xmip` gets source and manifest and no submodules.
  `git submodule update --init` is an explicit act, and `--recursive` reaches
  the implementations.
- Composition belongs to `Sync-XmipRepository`, not to a script of its own.
  `Invoke-SynchronizeSubmodules` and its schema-1 `repositories[]` reader are
  out of `Sync-XmipEstate`. The intermediate `Sync-XmipSubmodule.ps1` existed for
  one day and was deleted on 2026-08-25: the command that clones, pulls and
  branches the estate is already the command that should mount it, and a
  second script reading the same manifest is a second thing to keep in step.
- `.gitmodules.planned` is deleted. It planned nothing.
- Level two waits. Zero of the 249 implementation repositories exist, so
  today's run pins the 42 modules only.
- `crates/` still carries pre-ADR-0011 names (`xmip-module-abi`,
  `xmip-handler-file`, `xmip-module-api`) against manifest names
  (`xmip-core-abi`, `xmip-core-transport`, `xmip-core-api`). Submodules do not
  fix that and it is not this ADR's business. `docs/planning/allocation.toml`
  now decides each of them: `xmip-handler-file` folds into
  `xmip-core-transport` as an implementation module rather than becoming the
  first level-two repository.

## Alternatives considered

**One flat `.gitmodules` in the root pinning all 292 repositories.** One file
to read, and `--recursive` becomes unnecessary. Rejected: it puts the root in
charge of what a module contains, which is exactly the coupling the tree
removes, and it makes every clone of a module repository useless on its own.

**Submodules as full workspace members.** Cross-crate breakage caught in one
`cargo check`. Rejected: thirty-six clones per CI run, and a red submodule
turns the root red for something the root did not do.

**Keep `Invoke-SynchronizeSubmodules` and teach it schema 2.0.** Rejected: it
is entangled with repository creation and reporting. Composition is a
separate job from reconciliation, and it reads better beside the other git
operations than beside the GitHub API calls.
