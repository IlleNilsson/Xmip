# ADR-0005: Pre-alpha refactor discipline

## Status

Accepted. Amended 2026-11-28: an estate crate depends on another by path,
through the root's `[workspace.dependencies]`; the git-main form is retired.

## In brief

- Theme: How the work is done
- Subject: Pre-alpha refactor discipline
- Name: Pre-alpha refactor discipline
- Order: 2
- Concepts: Refactoring freely, pre-alpha; Estate crates depend by path

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

## Amendment, 2026-11-28: estate crates depend on each other by path; the git-main form is retired

**Provenance.** The owner, 2026-11-28, *Do as recommended*, to this: an
estate crate depends on another by path, through the root's
`[workspace.dependencies]`, in place of its git URL on `branch = "main"`
and the root's `[patch]`. The estate cited this record for that form, `x =
{ package = "xmip-core-x", git = "https://github.com/IlleNilsson/xmip-core-x",
branch = "main" }`, though its text never said it; it is retired here.
Every detail below that quotes no word of the owner's was decided by the
assistant while building, told to the owner.

**The defect.** Since every crate inherits its version, license, edition
and lints from the root (ADR-0016, amendment 2026-11-27), a crate's
manifest on GitHub, read alone, has no workspace root, and `[patch]` did
not keep cargo from reading it: for every dependency edge the lock did not
already hold, cargo fetched the git source the member named and read that
manifest, which failed with *failed to find a workspace root*. So a fresh
clone, which has no `Cargo.lock` (it is not committed), did not resolve;
the root's GitHub Actions workflow, which generates the lock, failed; and a
new edge between two estate crates failed even with a lock. Reproduced in a
workspace of two crates before the decision.

**The form.** The root's `[workspace.dependencies]` holds one entry for
each key a member names an estate crate by: its package where the key is
another name, and its path, the crate's mount as `.gitmodules` has it, or
its folder for a crate a repository holds without being one, never typed:

```toml
transport = { package = "xmip-core-transport", path = "module/core/capability/transport" }
```

A member takes it under the same key, which cargo requires, and says what
is its own, `features` and `optional`:

```toml
transport = { workspace = true, features = ["test-support"] }
```

One key names one package. A member that turns a crate's default features
off says `default-features = false` beside `workspace = true`, as it did
beside the git URL, 113 entries, and the root's entry says nothing of
them. Cargo was held to ignore a member's `default-features = false`
unless the workspace's entry turns the defaults off; cargo 1.100 takes the
member's, edition 2024, measured 2026-11-28 on a workspace of two crates:
a silent entry and a member's `false` resolve to no default features, and
an entry turning them off with a silent member resolves the same. Writing
the defaults off in the root would have made 15 members say `true`.

**Written by the tooling, from the members.** `Sync-XmipEstate -Cargo`
(`Update-XmipWorkspace`, its plan `Get-XmipWorkspacePlan`) writes the
root's members and `[workspace.dependencies]`, a third party's entries in
it kept, rewrites every member's estate dependency named by git URL into
the form above, keeping its `optional`, `features`, default features and
the comment on its line, deletes every `[patch]` of an estate crate, and
drops a key no member uses; a second run writes nothing. An entry of the
root's that turns a crate's defaults off is read as what each member silent
of them takes, and written onto those members instead. `-Cargo` asks
nothing of GitHub, as `-Brand` and `-Workflow` do not, and `-Compose` runs
it after it mounts, as ADR-0016 already said it did (it did not: only
`-Cargo` wrote the workspace). So a new dependency is written either way:
`x = { workspace = true }` under a key the root holds, or the crate's
repository form once, which the next run converts. `-Cargo`'s other act,
writing a dependency's `rev` from the submodule pins, had nothing to write
since dependencies tracked `main`, and is deleted (`Get-XmipCrateFinding`,
`Get-XmipPinnedCommit`).

Every reader of what a crate depends on reads a member's key through the
root's entry, in one place, `Resolve-XmipCargoPackage` over the estate's one
reader of a manifest's dependency lines (`Read-XmipCargoDependency`): the
landing's order and its consumers (`Read-XmipModuleManifest`), the estate
map's edges (`Get-XmipCargoUse`) and the features a site's build links
(`Get-XmipRootCargo`). The landing's order no longer takes a platform's
own dev-dependencies as what a crate is built of.

**Two keys renamed**, which named two packages each: `shape` is
`edifact_shape`, `x12_shape` and `er7_shape` in the EDIFACT, X12 and HL7 v2
contracts, the shape of each one's own standard; the standard units' `sql`,
the SQL contract, is `contract_sql`, the System Tests' key for it, so `sql`
is the SQL library everywhere. The other packages named under more than one
key keep their keys (open problem 245).

**What it retires.** ADR-0016's amendment of 2026-11-20 resolved the
estate's crates through `[patch]`; that `[patch]` is gone. ADR-0058's *callers
depend on a crate by its URL*: they depend on its key, and a move changes
one path in the root. ADR-0064's finding that nothing resolves while a
declared crate's repository is missing on origin: cargo reads no estate
crate from GitHub now. ADR-0016's *What it costs* (amendment 2026-11-27)
says what is still true.

**What it costs.** A crate of the estate taken by its git URL alone still
does not resolve, as ADR-0016 says. A crate published to a registry cannot
take an estate crate by a path alone: `cargo publish` refuses a dependency
with no version (open problem 247).

**Done.** 1,901 dependency entries in 277 manifests rewritten, 1,748 in
the members and 153 in the root crate; 483 keys written; 209 `[patch]`
tables deleted. Held by `test/Sync-XmipEstate.Test.ps1`, *The estate is one
Cargo workspace, its root holding every crate*: no member names an estate
crate by a git source, no `[patch]` names one, every estate entry is at the
mount `.gitmodules` gives its package and its folder holds that package, and
each key names one package; and *Update-XmipWorkspace turns an estate crate
named by its git URL into the workspace's*, over a tree of its own,
converting, keeping and refusing as above, and writing nothing on its second
run.

**Verified**, on Windows, the tree of 201a8eda with this change: `cargo
metadata` lists 284 packages, none from a git source, and each of the 1,901
entries resolves to the package, features, optional and default features it
did before the change; `cargo check --workspace -j 12` exits 0, and a
second run of `Sync-XmipEstate -Cargo` writes nothing. A copy of the tree
with no `Cargo.lock`, no build output and an empty `CARGO_HOME`: `cargo
metadata --format-version 1` exits 0 in 60 s and `cargo check --workspace
-j 12` in 8 minutes, RocksDB resolved at the version kept, 11.8.1
(open problem 246 has what else floats). `cargo publish --dry-run -p
xmip-core-abi` exits 0.
