# Xmip — Open Problems and Possible Solutions

Options per problem, with a lean. Nothing here is decided.

---

# Blocking now

## 1. Eight orphaned tests hold the build red

Every `.rs` file in `tests/` imports `xmip_linear_kernel`, the crate's pre-narrowing name.
They reference modules `src/lib.rs` does not publish. One, `xmip_message_model`, names a
module that no longer exists in `src/` at all.

| option | effect | cost |
|---|---|---|
| **A. Delete all eight** | build green today | loses nothing that currently runs; git keeps the history |
| **B. Move to `attic/`** | build green, files stay visible | a folder of code that compiles against nothing |
| **C. Restore them** | keeps the coverage | must publish ~40 modules from `lib.rs`; one test is unfixable regardless |

**Lean: A.** Eleven unit tests inside `journey_model`, `transport_technology` and
`vertical_slice` still run and cover the live architecture. B only makes sense if you want to
read the old design without `git log`.

## 2. Roughly forty files in `src/` are published by nothing

`src/lib.rs` exposes four modules — `contracts`, `journey_model`, `transport_technology`,
`vertical_slice`. `src/` holds about forty-five files.

**First, one command**, because it decides everything:

```powershell
Select-String -Path src\main.rs -Pattern '^\s*(pub )?mod ' | ForEach-Object { $_.Line }
```

| if main.rs... | then | option |
|---|---|---|
| declares them | they are live, owned by the binary | leave, or move the shared ones into the library |
| does not | forty files compile in nothing | **A.** delete · **B.** move to `attic/` · **C.** publish incrementally from `lib.rs`, fixing as you go |

**Lean: B if orphaned.** Deleting forty files of design work outright is harsher than parking
them. Moving them out of `src/` stops them reading as live code, which is the actual harm.

## 3. Edition mismatch

`cratePolicy` says edition 2024. The workspace `Cargo.toml` says 2021. Toolchain is 1.94.1,
so both are available.

| option | effect |
|---|---|
| **A. Move the workspace to 2024** | matches stated policy; a real migration with borrow-checker and prelude changes |
| **B. Change `cratePolicy` to 2021** | one-line honesty fix; policy follows reality |

**Lean: B now, A later.** Do not attempt an edition migration while the build is red. Make
the manifest tell the truth today, migrate deliberately once green.

---

# Structural — naming and boundaries

## 4. `assign`, `promote`, `demote` sit in Capabilities with zero implementations

"Capabilities" means *things Xmip does*, and these do things — but nothing about them is
pluggable, so they have no vendor and no trait to implement.

| option | effect |
|---|---|
| **A. Reclassify to Foundation** | honest about what they are; no code change |
| **B. Give them a plugin surface** | an assignment strategy becomes pluggable — real, but nobody has designed it |
| **C. Fold into `xmip-core-path`** | they are all path-driven operations |

**Lean: A.** C is tempting but wrong — they are artifact-level verbs in the journey, and
`path` is an addressing capability. B is the long-term answer if a second assignment strategy
ever appears; until then it is speculation.

## 5. `transport` carries 44 of the 246 implementations

One repository per protocol is correct. It also means one module owns a third of the build
and support burden permanently.

| option | effect |
|---|---|
| **A. Leave the naming, tier the execution** | declare 44, build six, mark the rest `maturity: reserved` |
| **B. Group families into shared repositories** | `aws-*` in one repo — fewer repos, breaks one-repo-one-release |
| **C. Split by transport kind** | `transport-queue`, `transport-file`, `transport-stream` — reintroduces classification into names |

**Lean: A.** The manifest already has `maturity`, and declaring is not building. C is the one
to avoid: it puts a judgement back into the name, which is exactly what the manifest exists
to prevent.

## 6. `logic` has three implementations and an unclear trait

Smallest capability with a plugin surface. Arrived via PR #32 and has not been stress-tested.

**The test:** state the trait in one sentence. If it can't be stated without describing
`process`, it isn't a capability.

| option | effect |
|---|---|
| **A. Fold into `process`** | one fewer module; `process` gains method semantics |
| **B. Keep and define the trait** | needs the one-sentence answer first |

**Lean: run the test before choosing.** This is the module most likely to be a feature
wearing module clothes.

## 7. The Operations tier is five near-identical modules

`audit` 9, `report` 6, `observe` 5, `retain` 5, `archive` 5 — and their technology lists
overlap heavily: postgres, s3, elasticsearch and otlp keep reappearing.

| option | effect |
|---|---|
| **A. Leave** | five policies genuinely differ, even if adapters repeat |
| **B. Merge into one `record` module with modes** | fewer modules; conflates retention policy with audit semantics |
| **C. Keep five modules, share a store trait** | the adapters stop being written five times |

**Lean: C.** The duplication is `postgres` appearing five times, not the modules. A shared
store trait in `xmip-core` — or a `store` surface module — removes the repetition without
pretending archive and audit are the same concern.

## 8. Cloud vendor prefixes are inconsistent

`aws-sqs` and `azure-blob` carry a vendor. `s3` and `gcs` do not.

| option | effect |
|---|---|
| **A. Always name the vendor** | `aws-s3`, `google-gcs`, `azure-blob` — consistent, slightly longer |
| **B. Never, where the product name is unique** | `s3`, `sqs`, `blob` — shorter, but `blob` alone is meaningless |
| **C. Vendor only on collision** | shortest, but requires knowing the whole namespace to name one thing |

**Lean: A.** "One meaning per token" is much easier to hold when the vendor is always present.
C fails the test that a namer should not need global knowledge.

## 9. `resilience` and `exclusiveness` are alone in the Platform tier

And `resilience` has no plugin surface in practice, despite six declared implementations.

| option | effect |
|---|---|
| **A. Leave** | the tier is small but the definition fits |
| **B. Move both to Capabilities** | dissolves the Platform tier |
| **C. Move Operations' shared store concern here** | gives the tier a third member with a real reason |

**Lean: A, revisit with 7.** If C happens, the tier earns its place.

---

# Repositories and code

## 10. Three modules declared with no repository

`xmip-core-abi`, `xmip-core-transport`, `xmip-core-logic`.

| option | effect |
|---|---|
| **A. Create all three** | manifest and reality agree |
| **B. Create `abi` only** | it is needed by the boundary; the other two are undesigned |

**Lean: B.** Do not create repositories for capabilities whose traits are unsettled — see 6.
Run `Sync-XmipEstate.ps1` with `-WhatIf` first regardless.

## 11. `xmip-module-api` and `xmip-module-abi` still exist

`xmip-module-api` re-exports `xmip_core::contracts::*`, which is what pulls implementers into
Rust and into AGPL by linkage. `xmip-module-abi` still carries `ModuleAbiKind`, removed by
clause 5 of ADR-0012. Its package is named `xmip-abi`, disagreeing with its directory and
with `cratePolicy.primaryCrateMatchesRepository`.

| option | effect |
|---|---|
| **A. Consolidate into `xmip-core-abi` now** | one crate, correct name, boundary matches the header |
| **B. Wait for the first real module** | avoids churn, but the contradiction stays in the tree |

**Lean: A, once the build is green.** Blast radius is small — two consumers,
`xmip-handler-file` and `xmip-host`. And you can now verify it with `cargo build`, which you
could not before.

---

# Configuration

## 12. The node configuration format

Two shapes are in the tree and they disagree. `[[modules]]` in the node TOML
against the Ansible template in `deploy/ansible/roles/xmip_node/templates/`,
which composes a different structure.

The `_origins` design export, mined 2026-08-26, proposed a third — and it is
the most complete of the three, so it belongs in the comparison rather than in
the bin:

```text
template.xmip.toml   reusable definitions
cluster.xmip.toml    the artifacts the whole cluster runs
xmip.toml            the node slice: what runs here
```

with the rule that a node slice declares *placement*, and templates and cluster
files declare *definition*.

| option | effect |
|---|---|
| **A. Flat node TOML with `[[modules]]`** | simplest; every node file repeats what the cluster already knows |
| **B. Ansible template composes it** | node files are generated, not authored; couples configuration shape to one deployment tool |
| **C. Three-file split, per the origin design** | definition and placement separate cleanly; three files to keep in step, and a resolution order to specify |

**Lean: C, but not by importing it.** The separation is right — a cluster-wide
definition repeated in forty node files is forty places to drift — and it is
what `xmip-core-configure` and desired state in `deployment-model.md` are
already reaching for. What C does not yet have is a resolution order: when the
cluster file and the node slice disagree, one of them wins, and nothing says
which.

**Explicitly not decided by finding it written down.** It arrived in an early
ChatGPT draft alongside the Artifact vocabulary and a Rust-only claim, both
rejected. Adopting one side of an open question because a draft happened to
answer it is how a question gets closed without being decided.

Recorded here rather than acted on. `_origins/` is deleted; git holds it.

---

# Governance

## 13. Succession

AGPL protects the code. The name, the GitHub account, the manifest registry and conformance
have no successor. Everything currently depends on one personal account.

| option | effect | cost |
|---|---|---|
| **A. Move to a GitHub organisation, add a second owner** | survives one person stopping | an afternoon |
| **B. DCO on contributions** | clean provenance for a future transfer | a file and a CI check |
| **C. Register the trademark** | protects the name specifically | money, jurisdiction-by-jurisdiction |
| **D. Written statement of intent** | says what should happen; not binding alone | an hour |

**Lean: A first, then B.** An organisation with two owners is the single cheapest thing that
changes the outcome if you stop — everything else protects assets that an organisation is
already holding. C matters only once someone else wants the name.

---

# Suggested order

```text
1. main.rs module list                one command, decides problem 2
2. Delete the eight orphaned tests    build goes green
3. cratePolicy edition to 2021        manifest tells the truth
4. Consolidate into xmip-core-abi     now verifiable
5. Create xmip-core-abi repository
6. State the logic trait              decides problem 6, then 10
7. Organisation and second owner      independent of all the above
```

Problems 4, 5, 7, 8 and 9 are naming judgements with no deadline. They cost nothing to leave
open and should not block the build work.
