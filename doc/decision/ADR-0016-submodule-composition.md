# ADR-0016: Submodule composition

- Status: Accepted
- Date: 2026-08-25
- Amended: 2026-09-07, decision 1 — a technology mounts directly under its
  parent, `csv`, not `module/csv`
- Amended: 2026-09-23, corrected 2026-09-24, decision 1 — what starts a node
  mounts at `module/<domain>/<leaf>`, everything else at
  `module/<provider>/<domain>/<leaf>`
- Amended: 2026-11-20, decision 4 — the estate is one Cargo workspace;
  resolved: path dependencies win, and a repository alone still builds
- Amended: 2026-11-27, decision 4 — a module takes what every crate shares
  from the root and builds only inside the estate; its workflow is the one
  file it keeps, written from its template
- Supersedes: `.gitmodules.planned`, `Invoke-SynchronizeSubmodules` in `Sync-XmipEstate.ps1`
- Related: ADR-0010 (direction-neutral transport), ADR-0011 (naming), ADR-0015 (packaging),
  ADR-0018 (amendment 2026-11-20: the build profiles of the one workspace)

## In brief

- Theme: The shape of the estate
- Subject: Submodule composition mirrors ownership
- Name: Submodule composition
- Order: 2
- Concepts: Submodules; Provider before purpose

Two levels, each owned by the repository that pins it. `Xmip` pins
`module/core/capability/transport`; `xmip-core-transport` pins `kafka`. A parent pins
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
   `handlers/`, `doc/submodules/` and `.gitmodules.planned` — sixty-nine
   files in all.

## Decision

**1. Two levels, each owned by the repository that pins.**

```
Xmip                     module/transport   -> xmip-core-transport
xmip-core-transport      kafka              -> xmip-core-transport-kafka
```

*Amended 2026-09-07.* The second line read `module/kafka`. Inside a module
repository everything is the module, so a `module/` directory there says
nothing: `xmip-core-contract/csv` is the CSV contract the way
`xmip-core-contract/src` is its source. The owner ruled the directory out on
2026-09-07, when the contract and archive repositories held one technology
each and the layout was cheap to change. The root keeps `module/`, because at
the root the word separates modules from `doc/`, `test/` and `template/`.

*Amended 2026-09-23, corrected 2026-09-24: what starts Xmip carries no
provider; everything else does, provider before purpose.* The owner,
2026-09-23: *What is needed to start Xmip on a node does not need to be mounted
with provider. Everything else has to be mounted with provider* — and then
*provider before purpose*: he is the inventor and others plug in. So the root
pins what starts a node by its domain alone, `xmip-core` at
`module/foundation/core` and `xmip-core-runtime` at `module/platform/runtime`,
and every other module at `module/<provider>/<domain>/<leaf>`,
`xmip-core-transport` at `module/core/capability/transport` and another
provider's at `module/<theirs>/…` beside it. System Tests are test scaffolding
and mounts at `test/<provider>/system-test` (ADR-0028); the templates stay at
`template/<language>`, belonging to no provider.

As first written, this amendment read *provider before purpose* as replacing
the first rule and moved `foundation` and `platform` under `core` too. The
owner, 2026-09-24: *Do you think core is not needed to start Xmip?* The second
instruction refines the first; both hold. repository-model.md, section 7,
draws the tree; `test/Sync-XmipEstate.Test.ps1` holds every mount to it.

A `.gitmodules` file belongs to the repository doing the pinning. The root
never reaches past its own children; a module repository composes its own
standards. Recursion is git's job, not the manifest's.

**2. The path is the manifest key, not the repository name.**

`module/transport`, not `module/xmip-core-transport`. The path mirrors the
TOML tree exactly, so a reader who knows one knows the other. The submodule
*name* stays the full repository name, which is what `git config` keys on.

**3. Composition is gated by existence, not by maturity.**

`maturity` decides whether `Sync-XmipEstate` creates a repository. It has
nothing to say about pinning: you cannot pin what does not exist, and anything
that does exist is worth pinning. `Sync-XmipRepository -Submodule` reports the absent
ones and carries on.

**4. How Cargo sees `module/` is UNRESOLVED and blocks the rest.**

*Resolved 2026-11-20 by the amendment at the end: path dependencies win, and a
repository checked out alone still builds. Narrowed 2026-11-27: a repository
alone no longer builds; a module builds only inside the estate.*

Two decisions taken separately turn out to contradict each other.

*Exclude from the workspace* was chosen so root CI stays fast and independent:

```toml
[workspace]
exclude = ["module"]
```

*Path dependencies through submodules* was chosen so a recursive clone builds
with no publishing step:

```toml
[dependencies]
xmip-core-route = { path = "module/route" }
```

These pull opposite ways. A path dependency means the root cannot compile
without the submodules present, so CI must check out recursively and a broken
submodule breaks the root — precisely what the exclusion was meant to prevent.

Resolve it one of two ways, and this ADR is not final until it is:

- **Path dependencies win.** `module/*` become workspace members, CI checks
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
`doc/submodules/` (11), `doc/architecture/handler-submodules-*.md` (6) and
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
  fix that and it is not this ADR's business. `doc/planning/allocation.toml`
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

## Amendment, 2026-11-20: the estate is one Cargo workspace; decision 4 resolved

**Provenance.** The owner, 2026-11-20, on what the estate's builds cost:
*Go with recommendations*, the first of which was one Cargo workspace for
the estate, its patch committed in place of the one written for every
landing; later that day, *Too long, do not accept. Solve it*; asked how the
landing that makes the workspace should verify, *Workspace-wide* (below);
and at about 18:08, *I need the solution to be solid according to ADR,
changes and agreements.* The design and the build are the assistant's, at
the coordinator's order; every choice below that quotes no word of the
owner's was decided by the assistant while building, told to the owner.

**Decision 4 is resolved: path dependencies win, and a repository alone
still builds.** The root's `Cargo.toml` lists every crate of the estate as
a member — 281 of them, every crate under `module/`, `test/core/system-test`,
`test/core/module` and `sdk` — and excludes `template`. Its `[patch]` maps
each estate crate a manifest names by its git URL to its folder, 208 of
them, by a relative path, so one committed manifest serves every machine. A
member keeps its git dependencies on `branch = "main"` (ADR-0005) and has no
`[workspace]` or `[profile]` of its own: checked out alone, with no
workspace above it, a crate is its own root and resolves its dependencies
from GitHub as before. In the estate there is one resolution, one
`Cargo.lock`, still not committed, and one build directory, and cargo
rebuilds what changed and what depends on it. `Sync-XmipEstate -Compose`
writes the members and the `[patch]` as it mounts a crate
(`Update-XmipWorkspace`), in place of the empty `[workspace]` it wrote into
every crate it mounted; `test/Sync-XmipEstate.Test.ps1`, *The estate is one
Cargo workspace, its root holding every crate*, holds the committed members
and `[patch]` to `Get-XmipWorkspacePlan` over the tree on disk.

The root does not list `"."`: cargo ignores `exclude` whenever `members`
holds `"."`, since every path under the root starts with `<root>/.` — which
is why the template had to carry an empty `[workspace]`. With `"."` left
out the root package is still a member, and an excluded crate is passed
over; measured on a scratch workspace with cargo 1.100, an excluded crate
under a root that lists `"."`:

```text
error: current package believes it's in a workspace when it's not
```

The first option's cost, *root CI is slower and coupled*, was already paid:
every landing built every crate against every working tree through a cargo
configuration written for it (`New-XmipLocalPatch`,
`.local-work/landing/patch.toml`), each module in a workspace of its own,
with a lock of its own. The round-17 landing ran 366 cargo commands that
way, each resolving and building its own graph: 264 consumer checks, 49
lints of timing programs, 13 each of format, lint and default-feature
tests, 8 every-feature test runs and 6 timing runs. In one workspace the
Rust part runs three commands at the root — format, one command for the
changed crates; every consumer linted at once, `cargo clippy --workspace
--all-targets --all-features`; every timing program's lint, one `cargo
clippy --workspace --all-features --test measured` — and then, for each
changed crate in its folder, leaves first, its tests and its lints with its
default features — the only build that compiles what a feature leaves out,
which a workspace-wide build never does — and its tests with every feature
it declares, where it declares one (`Test-XmipDeclaredFeature`, as the
per-module landing did). A changed crate the workspace's plan does not hold
as a member — the Rust template, which the workspace excludes — is
verified the way a repository alone builds, through its own manifest
(`--manifest-path`: format, its lints and tests with its default features
and with every feature); whether a crate is a member is the plan's
(`Get-XmipWorkspacePlan`), never its folder's name. The first landing of
this change stopped at its first step, `cargo fmt --check -p
xmip-template-rust`, with "package `xmip-template-rust` is not a member of
the workspace" (decided by the assistant, told to the owner). Each timing
program then runs once, alone. Like
for like with round 17's 366, a landing of the same reach runs 43: 3 at
the root, 13 test and 13 lint runs, 8 every-feature test runs and 6 timing
runs; the root crate's own three runs and the three libraries the parts
load make 49 in all. The root's CI checks out the submodules and keeps its
scope, the root crate: its format step is `cargo fmt -p xmip --check`.

**The landing's parts run side by side.** The owner, the same day: *Still,
the time it takes is not acceptable.* The landing verified module after
module, then the root crate, then `test/`, then the .NET projects, though
none reads what another writes. It now builds what its parts load first —
the runtime's library, its remote build where `operate` lands, the test
module's library where the runtime does — and then runs three parts at once,
each in a pwsh of its own with its share of the machine's twelve threads
(`Invoke-XmipLandingPart`; Rust 8, .NET 2, Pester 2, a part alone all
twelve): Rust, the workspace commands above and each changed crate
(`Test-XmipRustChange`); .NET, every changed or consuming .NET project, a
changed crate's TypeScript shell and its Event bindings
(`Test-XmipDotnetChange`), against a copy of the runtime's library so the
Rust part may build over the original; Pester, the root's `test/` when the
root changed. The first part to fail ends the others, every process beneath
them with them, and is named with the lines that say why. Then each changed
crate's timing program, and the root's, runs alone in the `measured` build
(ADR-0018, amendment 2026-11-20), nothing else running. Before the parts,
the landing says how long the last landing's parts and timing took.

**What one resolution changed in the code.** Features now unify across the
estate's crates in a workspace-wide build, so a feature one crate turns on
reaches every other: third parties' — `serde_json`'s `preserve_order` (from
`cedar-policy-core` and `arrow-json`) and a newer `generic-array` — and,
built with every feature, the estate's own: ISO-TP's and J1939's
`socketcan` turns on can-bus's for every CAN technology. What held only in
its own workspace was fixed where it is:

- the Event Grid far end's `Published` variant is boxed (its event grew
  past clippy's `large_enum_variant`);
- the SAML digest compares `digest[..]` (`GenericArray::as_slice` is
  deprecated in 0.14.9);
- four tests' `assert_eq!(x, [])` read `assert_eq!(x, b"")`, the empty
  array's type ambiguous among another crate's `PartialEq` impls (NFS,
  Zigbee, syslog, OPC UA);
- operate's test of a decided surface reads its answer as JSON, never as
  text, since the key order is the feature's;
- JSONPath's test of `$..price` compares the prices as a set: an object's
  members are unordered (RFC 9535, section 2.5.2.2), and the order
  `serde_json` keeps is its `preserve_order` feature's;
- the CAN technologies' settings tests build on a simulated bus by its
  constructor, never by a name: with `socketcan` on Linux, can-bus's
  `open_bus("can0")` opens the kernel's SocketCAN interface, which a test
  machine has not. can-bus gains `simulated(name)`, the one constructor of
  a single node on a simulated bus of its own, which `open_bus` itself calls
  where the build has no kernel bus, and which every test that built such a
  node by hand now calls; `can_bus::loopback::Session::fresh` stays the one
  constructor of two nodes sharing one simulated bus, which every CAN
  loopback uses. iso-tp, J1939, OBD-II, UDS and CANopen no longer depend on
  the SDK, which they used only for that bus (architecture.toml follows). can-bus, CANopen, OBD-II and UDS each gain `on(bus, settings)`, which
  their `configured` calls with the bus the address opens, as ISO-TP and
  J1939 had. The transport capability's `Configured` gains
  `finished(read, side)`, the step `open` takes once a technology is built
  — the Location's timeout where it read one, then its side — and `open`
  itself calls it, so a test finishes a technology the way `open` does.
  Every CAN technology's settings test — can-bus's, CANopen's, OBD-II's,
  UDS's, ISO-TP's and J1939's — builds on `can_bus::simulated` and finishes
  through `finished`, and runs in every build, the unified one on Linux
  included; no guard on `socketcan` is left in any of them.

**Where a build is found is cargo's rule, read in one place per language.**
Cargo builds into `CARGO_TARGET_DIR`, else `target` at the workspace's
root: the estate's root in the estate, a repository's own folder when it is
checked out alone. Every place that looked for a build in a crate's own
`target` reads that rule instead:

- PowerShell reads one property, `Get-XmipEstateLayout`'s `Build`, which
  `Test-XmipChangeTree`, `Import-XmipOperatorModule`,
  `Install-XmipNativeLibrary` and `Get-XmipPackageBinary` read; the
  System Tests' roll, cluster and node build in a build directory of their
  own, `Get-XmipSystemTestLayout`'s `Target` (ADR-0028, amendment
  2026-11-20), so a running roll never holds what a landing builds; `Get-XmipPackageBinary` moved from
  `New-XmipPackage.ps1` into a file of its own, which keeps that file under
  400 lines.
- A Rust test finds what cargo wrote through one helper,
  `file::built::found` in `xmip-core-library-file`'s `test-support`: the
  file in the nearest folder above the running test program, the profile's
  folder. The runtime's `ffi::loaded_contract` and `running` tests and its
  example lookup in `library.rs` find the test module's library so, and the
  VS Code server's `.src/built.rs` the runtime's; `XMIP_MODULE_LIBRARY` and
  `XMIP_RUNTIME_LIBRARY` still win where they name a file.
- `Xmip.Operate.csproj` takes `CARGO_TARGET_DIR`'s `debug`, else the estate
  root's `target/debug` where the root's `Cargo.toml` is, else the
  repository's own `target/debug`, so a clone alone builds.
- The Event bindings' check, `module/foundation/abi/verify-event-bindings.ps1`,
  takes the runtime's library from `XMIP_RUNTIME_LIBRARY`, else its
  `-Library`, and looks in no folder of its own.
- What tells a person where `cargo build` leaves the runtime's library says
  `target/debug` at the estate's root: the VS Code server's answer when none
  is named (`.src/server.rs`), the setting's description in
  `extension/package.json`, the extension's `README.md` and a comment in
  `.src/runtime.rs`, all in `module/core/operation/gui/vscode`.
- The command line's `module/core/operation/cli/cli.toml` keeps its
  relative `Snapshot` path, and its `AuditDirectory` example, as examples
  two levels above `target/debug` at the estate's root, saying they assume
  cargo's default `target`.

**This landing verifies in full.** The flip itself edits manifests only:
each of the 282 crate manifests loses its own `[workspace]` and
`[profile]`, and no dependency or feature changes. The landing that carries
it changes source too: what is listed above, under *What one resolution
changed in the code* and *Where a build is found*, and round 18's beside
it, the runtime's directory watch and the surfaces' .NET fixes among them
(ADR-0052, amendment 2026-11-20). While the flip was all it held, the owner
was asked: *The one-workspace landing edits all 282 crate manifests but no source,
dependency or feature. How should that one landing verify?* He answered
*Workspace-wide* (2026-11-20, about 17:27): format, clippy and test over the
whole workspace with every feature, on Windows and Linux. The coordinator
then chose the landing tool's own full verification, `Publish-XmipChange`
with nothing skipped: the workspace-wide commands and, for each changed
crate, its own default-feature and every-feature runs, the timing programs
after, alone. The owner's rule is that no landing skips its verification,
and the round's review showed that the per-crate default-feature pass
checks exactly what a unified build can hide: each crate built with only
its own features, as a repository checked out alone builds, which in the
workspace another crate's features never leave it.

Before it, on the Linux build machine, the tree as it was at 18:05, the
whole workspace with every feature: `cargo clippy --workspace --all-targets
--all-features -j 20 -- -D warnings`, then `cargo test --workspace
--all-features --no-fail-fast -j 20`, each with its exit and its time:

```text
clippy exit=0 in 43 s
test exit=101 in 634 s 5503 passed 13 failed
test routed::an_edifact_document_goes_to_the_send_port_its_message_type_and_recipient_name ... FAILED
test failover::every_file_dropped_arrives_once_when_the_primary_storage_node_stops_mid_run_and_returns ... FAILED
test eval::tests::selects_by_name_index_wildcard_and_descendant ... FAILED
test ffi::loaded_contract::tests::a_real_module_opens_and_says_what_it_is ... FAILED
test ffi::loaded_contract::tests::a_trait_generation_apart_is_refused_naming_trait_major ... FAILED
test ffi::loaded_contract::tests::an_empty_stream_is_read_to_its_end_like_any_other ... FAILED
test ffi::loaded_contract::tests::content_is_validated_through_the_loaded_table ... FAILED
test ffi::loaded_contract::tests::the_capability_that_did_not_ask_for_it_refuses_it_naming_the_field ... FAILED
test a_library_module_is_opened_once_and_let_go_at_the_stop ... FAILED
test tests::a_send_location_downloads_to_its_object_and_a_target_naming_another_wins ... FAILED
test tests::canopen_declares_its_settings_and_reads_through_them ... FAILED
test tests::obd_ii_declares_its_settings_and_reads_through_them ... FAILED
```

The thirteenth was UDS's settings test. What each turned out to be:

- **Five, a feature unified across the workspace**, each fixed where it is
  (above): JSONPath's order of `$..price`, from `preserve_order`; CANopen's
  two tests, OBD-II's and UDS's, from `socketcan`.
- **Six, the test module's library, which that run did not build.** The
  runtime's five `ffi::loaded_contract` tests and its
  `a_library_module_is_opened_once_and_let_go_at_the_stop` load
  `test/core/module`'s library, which `cargo test` does not write; the
  landing builds it before its parts where the runtime lands. With it
  built, each passed three runs of three:

```text
test result: ok. 5 passed; 0 failed; 0 ignored; 0 measured; 342 filtered out; finished in 0.00s
test result: ok. 1 passed; 0 failed; 0 ignored; 0 measured; 17 filtered out; finished in 0.34s
test result: ok. 5 passed; 0 failed; 0 ignored; 0 measured; 342 filtered out; finished in 0.00s
test result: ok. 1 passed; 0 failed; 0 ignored; 0 measured; 17 filtered out; finished in 0.29s
test result: ok. 5 passed; 0 failed; 0 ignored; 0 measured; 342 filtered out; finished in 0.00s
test result: ok. 1 passed; 0 failed; 0 ignored; 0 measured; 17 filtered out; finished in 0.29s
```

- **Two, the root's service tests `routed` and `failover` above**, which
  failed with the machine's load at 30 on its 20 hardware threads and
  passed three runs of three alone; whether a node's deadline or the
  test's bound gives way under load is open problem 84:

```text
test result: ok. 1 passed; 0 failed; 0 ignored; 0 measured; 12 filtered out; finished in 1.50s
test result: ok. 1 passed; 0 failed; 0 ignored; 0 measured; 12 filtered out; finished in 13.12s
test result: ok. 1 passed; 0 failed; 0 ignored; 0 measured; 12 filtered out; finished in 1.46s
test result: ok. 1 passed; 0 failed; 0 ignored; 0 measured; 12 filtered out; finished in 38.77s
test result: ok. 1 passed; 0 failed; 0 ignored; 0 measured; 12 filtered out; finished in 1.46s
test result: ok. 1 passed; 0 failed; 0 ignored; 0 measured; 12 filtered out; finished in 12.03s
```

**The verdict before the landing.** A landing cannot quote its own run in
the commit that run makes; `Publish-XmipChange` verifies the whole tree
again on Windows and commits nothing on a failure. Before it, on the tree
it lands:

- On the Linux build machine (Rust 1.100, the tree of 2026-11-20 19:47,
  `cargo build -p xmip-core-test-module --all-features` first, `-j 20`):
  `cargo fmt --all --check` exit 0; `cargo clippy --workspace
  --all-targets --all-features -- -D warnings` exit 0 in 3 s, warm;
  `cargo test --workspace --all-features --no-fail-fast` exit 0 in
  201 s, 5,518 passed, 0 failed. Each of the 282 crates alone, on the tree
  of 18:34: `cargo clippy -p <crate> --all-targets -- -D warnings` with
  its default features, 0 failed in 389 s; `cargo test -p <crate>
  --all-features`, 282 passed, 0 failed in 1,390 s.
- On Windows, each crate the round touched in its own folder with its
  default features, `cargo clippy --all-targets` then `cargo test`, every
  one exit 0 (the runtime's `running` test 18 of 18 with `node` alone);
  `cargo clippy --workspace --all-targets --all-features` clean in 57 s
  warm; the Pester files of the changed tooling, 174 passed, 0 failed,
  1 skipped (the worker's report).
- Three independent reviews of the change against the ADRs, read-only;
  every finding fixed, or opened as problems 83 and 84.

**What went, with every use:** `New-XmipLocalPatch` and the file it wrote,
`XMIP_CARGO_CONFIG`, every `Patch` and `Through` parameter and `--config
<patch>` argument, `Test-XmipModule` and `Get-XmipBuildableFeature` (the
landing's Rust part is `Test-XmipRustChange`, its .NET part
`Test-XmipDotnetChange`), the per-module estimate `Get-XmipRemainingTime`,
each member's `[workspace]` and `[profile.dev.package."*"]`, and the
System Tests' service build in a directory of its own.

**Measured, before**, on the Linux build machine (20 hardware threads,
Rust 1.100), each build in a fresh build directory, the root with every
feature it declares, as a landing tests it:

```text
cargo test --no-run -j 16 --all-features      (root, cold)         210.9 s, 253 units
  the same after one line in module/platform/persist                   6.7 s, 6 units
cargo test --no-run -j 16   (module/platform/runtime's own workspace,
  the same build directory, after the root)                          141.6 s, 82 units
```

The runtime's own workspace compiled 82 units again, 53 of them estate
crates, because it resolved other features and a few other versions than
the root's. A sweep of every workspace there, clippy and tests with every
feature in two lanes, took 15:12 to 16:26. In one workspace, the whole
estate linted with every feature on the same machine, cold, `-j 16`:

```text
cargo clippy --workspace --all-targets --all-features --keep-going -j 16
  569 units, 528 s, peak 7.3 GB in use on the machine
```

And on Windows, the landing's own build directory, the workspace linted
again after one crate changed: `Finished ... in 14.39s`.

Following it, the same day: ADR-0018's amendment, the two builds the
workspace's root holds (`dev` at opt-level 1 with line tables, `measured`
optimized for the millisecond rule); ADR-0015's, the package's library and
command line as members; ADR-0028's, the System Tests built in the workspace
and in `measured`; ADR-0058's, the workspace in place of the local patch.

## Amendment, 2026-11-21: a test holds its promise, never its crate's feature name

**Provenance.** Found by the assistant on the Linux build machine on
2026-11-21, three rounds of three of a plain `cargo test --workspace`; the
fix was decided while building, told to the owner (the owner's rule that
nothing reads meaning from a name, capability decides).

A plain `cargo test --workspace` builds every member with its default
features unified across the workspace (amendment 2026-11-20). There, msmq's
`a_guarded_queue_is_carried_to_the_endpoint_rather_than_sent_in_the_clear`
failed every time: another member turns `http/tls` on while msmq's own
`tls` stays off, so http made a TLS handshake that the silent listener
never answered, the send timed out after its second, and the test, which
asked msmq's own feature, expected the refusal a build without TLS gives.
Every-feature runs and `-p` runs passed; no gate ran that build.

The test now holds what its name says whatever the build unified: the
listener reads what reached it, and neither the order's bytes nor a plain
HTTP request line may be there, only a TLS handshake (its first byte, 22)
or nothing; the send fails either way, and only where msmq's own `tls` is
on, so http's is too, may it not be the refusal. Measured as it was
written: with TLS 1,444 bytes arrived, starting with 22; without, nothing,
and the send was refused. On Linux the workspace's 625 other test programs
passed in the same three rounds; msmq's 18 pass with default and every
feature on Windows and on Linux.

## Amendment, 2026-11-27: a module inherits from the root and builds only in the estate

**Provenance.** The owner, 2026-11-27, *Do as recommended*, to this: a
module repository's own boilerplate inherits from the estate's root, so
there is one copy and a module builds only inside the estate, as it
already did in practice; only `.github/workflows/verify.yml` stays in each
repository, because GitHub needs it there, written from one template and
held identical to it. It clears what `test/Duplication.Test.ps1` listed
that day (CONTRIBUTING, *Code is placed once*; ADR-0020 clause 8): the
toolchain file's comment in 247 files, the lint block in 255 manifests,
the version, license and edition typed in about 285, the workflow in 255.
Every detail below that quotes no word of the owner's was decided by the
assistant while building, told to the owner.

**The amendment of 2026-11-20 is narrowed: a repository alone no longer
builds.** There a crate checked out alone was its own root and resolved
its estate dependencies from GitHub. Now:

- The root's `Cargo.toml` holds `[workspace.package]`, `version =
  "0.1.0"`, `edition = "2024"`, `license = "AGPL-3.0-or-later"` and
  `publish = false`, and `[workspace.lints]`, the block every crate
  carried: `unsafe_code = "forbid"`, and clippy's `pedantic` with
  `too_many_lines`, `missing_errors_doc`, `missing_panics_doc` and
  `unwrap_used` warned and `expect_used` allowed. A crate takes each value
  it shares, `version.workspace = true` and the like, and the lints with
  `[lints] workspace = true`: every member's manifest takes the values,
  283 of them, and 246 the lints; the root crate takes its edition and
  license. Every package resolves to the value it had, `cargo metadata`
  before and after.
- 23 crates declared no lints at all: fourteen capabilities' own crates and
  BPMN's, the foundation's context, journey, message, node, party and
  stream, observe and report. Cargo 1.100 warns of a member with no
  `[lints]` under a workspace with `[workspace.lints]`
  (`cargo::missing_lints_inheritance`), and the estate denies warnings, so
  each says which, and says an empty `[lints]`: none. Held to the shared
  lints, contract's and process's C exports, which allow unsafe code, do
  not compile, and clippy found pedantic findings in the foundation's
  context (8), stream, node and journey (1 each) before their dependents
  could build; holding these crates to the lints is a change of its own,
  left to the owner. The root's comment on `[workspace.lints]` says so
  once.
- A crate writes its own only where it differs: xmip-core-abi its
  `license = "Apache-2.0"` (ADR-0075 clause 6), the root crate `xmip` its
  version, 0.1.1; the 41 crates that never said `publish = false` still
  say nothing of it. Cargo takes a crate's lints from the workspace whole
  or not at all, so the thirteen crates that lower `unsafe_code` to `deny`
  for the one file or folder crossing a C interface (rust-style.md section
  5a) keep their own `[lints]` whole, nine of them with the shared clippy
  block beside it; so do xmip-core-configure, which declares `forbid`
  alone, and the root crate, which declares `forbid` and `pedantic` alone.
  Giving those two the shared lints would hold them to lints they never
  had, a change of its own.
- xmip-core-test-module said `missing_safety_doc = "warn"` beside the
  block, clippy's own default level for it; it takes the workspace's lints,
  and nothing it is held to changes.
- The Rust template, `template/rust`, is a member (the workspace excluded
  it), since every module made from it builds only here: its `Cargo.toml`
  takes every shared value and the lints, and it carries no toolchain file.
  `Get-XmipWorkspacePlan` holds it as any crate, and the root's `exclude`
  went. A changed crate the plan does not hold is still verified through
  its own manifest by `Test-XmipRustChange`; no crate of the estate is one
  now.
- The root's `rust-toolchain.toml` is the one. The 246 copies in the
  modules, the SDK and the template are deleted, and with them the
  *Toolchain* section 222 module READMEs had about the copy.

Held by tests: `test/Rust.Style.Test.ps1`, *ADR-0016: a crate takes what
every crate shares from the root*, fails on a member writing a package
value or a lint table equal to the root's; `test/Sync-XmipEstate.Test.ps1`
fails on a toolchain file anywhere but the root and on a root one not on
`stable` (ADR-0021); `test/License.Test.ps1` reads the root's
`[workspace.package]` among the AGPL crates, and requires the boundary to
write its Apache-2.0 itself, since a boundary crate taking the workspace's
license would be AGPL.

**The workflow is the one file a module keeps.** GitHub runs a
repository's workflow only from that repository's own `.github/workflows`.
Each Rust module's `verify.yml` is `template/rust/.github/workflows/verify.yml`
byte for byte: `Sync-XmipEstate -Workflow` writes it from the template
where one differs (`Write-XmipWorkflow`; a repository holding a
`Cargo.toml` takes the Rust template's, any other the .NET template's),
and `test/Workflow.Test.ps1` holds all 251 identical. Two verify a second
language beside the crate and are their own, named in
`Write-XmipWorkflow.ps1`: xmip-core-abi's .NET binding and surface, and
xmip-core-gui-vscode's TypeScript shell (ADR-0052 clause 6); the test holds
that each verifies its crate through the template's shared workflow.
Twenty-nine Rust repositories have no workflow and are given none.
`Write-XmipChangedFile` is the one writer of a file where its bytes
differ, the brand's copies' (`Write-XmipBrand`, which kept it as
`Write-XmipBrandFile`) and the workflows'.

**What it costs.** A module's repository checked out alone does not
build: cargo finds no workspace root to take the values from.

- The shared workflow every module's calls, `rust-verify.yml@v1` in
  `IlleNilsson/.github`, builds a repository alone, and now fails at its
  first cargo step. It runs only when started by hand and lives outside
  the estate's tree; verifying a module there means checking out the
  estate and verifying the crate in it. Left to the owner.
- A crate of the estate taken by its git URL alone, as a developer outside
  the estate could until ADR-0075 (*the Rust crates at `branch = "main"`*),
  no longer resolves. `cargo publish` writes the inherited values into
  what it packs, so crates.io's `xmip-module` (ADR-0075 clause 2) is not
  affected.

**Verified**, on Windows, the tree of b2f703ba with this change:
`cargo metadata` lists 284 packages, each with the version, edition,
license and publish setting it had; `cargo check --workspace -j 12` and
`cargo clippy --workspace --all-features -j 12 -- -D warnings` exit 0, and
the crates taking the workspace's lints were not rebuilt, their lint flags
what they were. A probe in the template, `value.unwrap()` in a public
function, made `cargo clippy -p xmip-template-rust` refuse the build with
`clippy::unwrap_used` and `clippy::missing_panics_doc`, each *requested on
the command line*, the workspace's, and `pedantic`'s `must_use_candidate`.
On the Linux test computer, Core.Estate: OK, 844 passed, 0 failed, 13
skipped. `test/Duplication.Test.ps1`, Configuration: 342 groups over 7,407
places before (13f30383), 338 over 4,828 after; of the copies this
amendment is about, 13 groups over 3,373 places, 7 over 50 remain: the
crates keeping their own lints, and values `architecture.toml` and
`prerequisite.toml` hold for other subjects. The kind is not cleared, so
it is not gated.

Followed the same day: rust-style.md (its table, section 5b),
repository-model.md (sections 8 and 10), `.cargo/config.toml`,
`README.md`, and the template's `README.md` and `TEMPLATE_SETUP.md`.
