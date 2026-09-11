# ADR-0049: A crate that hosts technologies keeps its source in `.src`

- Status: Accepted
- Date: 2026-09-10
- Related: ADR-0016 (submodule composition, as amended: a Technology is
  mounted directly under its Capability), ADR-0044 (a technology shares
  through its capability), doc/architecture/repository-model.md

## In brief

- Theme: The shape of the estate
- Subject: Where a Capability crate's own source lives once its directory
  also holds the Technology repositories mounted under it
- Name: A crate that hosts technologies keeps its source in `.src`
- Order: 12
- Concepts: Host crate; `.src`; directory of many usages

**A directory that holds more than one kind of thing does not put its own
source in `src`. `module/capability/transport` is eighty-four transport
repositories and, beside them, the crate that defines what a transport is.
The crate's source steps aside as `.src`, so the listing reads as the
technologies it mounts and the one directory that is not a technology says
so by its name. A crate that hosts nothing keeps `src`.**

## Context

ADR-0016 as amended mounts every Technology directly under its Capability:
`transport/as2`, `route/content`, `message/json`. The Capability's own crate
is at the same level, and its `src` sat among the mounts as one more short
name. With eighty-four mounts under `transport`, twenty-seven under
`contract` and nineteen under `identify`, `src` was the one entry in each
listing that was not a repository and looked exactly like one: a directory
of many usages with one entry named as if it were the only usage.

The owner ruled on 2026-09-10: *I do not want a src directory within a
directory containing multiple usages. Like `module/capability/src`, it should
be called `.src` if it needs to be there.*

## Decision

### 1. The rule

A crate whose directory also mounts Technology repositories — one with a
`.gitmodules` of its own — is a host crate. A host crate keeps its source in
`.src`, declared in `Cargo.toml` as `[lib] path = ".src/lib.rs"`. A crate
that mounts nothing keeps `src`, the Cargo default, and says nothing.

### 2. Who this is today

Twelve crates host technologies: `authenticate`, `authorize`, `contract`,
`identify`, `logic`, `path`, `route`, `transport` under capability;
`message` under foundation; `archive` and `gui` under operation;
`resilience` under platform. Each moves `src` to `.src` in one commit that
changes nothing else. A crate that begins hosting later moves when its first
Technology is mounted.

### 3. What does not change

The style gates read a file's crate from its path, `module/<domain>/<crate>/`,
and are indifferent to the name of the directory below. The line and file
limits, the one-subject-per-file rule and the naming rule apply to `.src`
exactly as they did to `src`. Technology repositories keep `src`: each is a
directory of one usage.

## Consequences

- Twelve `Cargo.toml` files gain a `[lib] path`; twelve directories are
  renamed; every reference to a host crate's `src/` in the records, the
  recipe sheet and the playground's local patches follows.
- A listing of a Capability is its Technologies. The one directory that is
  not one is named as an aside.
- The rule is applied after the batch of technology repositories in flight
  on 2026-09-10 lands, so that the agents building them read paths that
  exist.

## Provenance

The rule is the owner's, 2026-09-10, quoted in Context. The scope — a crate
with a `.gitmodules` of its own, and no other — and the decision to apply it
after the batch in flight are the assistant's readings of *if it needs to be
there* and of the owner's *after that*.

## Amendment, 2026-09-11: any directory of many usages, not only a host

The scope in clause 1 was too narrow. The owner's rule in Context names *a
directory containing multiple usages*, and a `.gitmodules` is one way a
directory comes to hold many things, not the only way. The rule applies to
every crate whose directory holds, beside its own source, anything that is
not the crate's manifest, licence, readme, toolchain file, build output or
Cargo's own `tests`, `benches` and `examples`:

- the platform repository itself, whose `xmip` assembly crate sat as `src`
  beside `Xmip`, `asset`, `deploy`, `doc`, `install`, `module`, `template`
  and `test`;
- `module/foundation/abi`, whose source sat beside `docs`, `dotnet` and
  `include`;
- `module/operation/gui/vscode`, whose `xmip-lsp` source sat beside
  `extension`;
- `module/capability/process`, whose source sat beside `docs`.

Each moves to `.src` with the same `[lib] path` — or `[[bin]] path` for
`xmip-lsp` — as clause 1. A Technology repository, or any crate whose
directory is its source and Cargo's conventions and nothing else, keeps `src`
as before: `contract/c` beside its `tests` is one usage.

The eleven Rust hosts of clause 2 moved on 2026-09-11 after the batch landed.
`module/operation/gui` moves as soon as the editor holding its projects open
lets go; the four above move in the same change as this amendment.

The owner asked on 2026-09-11 to check the code base again after the eleven
had moved, and these four are what that check found.
