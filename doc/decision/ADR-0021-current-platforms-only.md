# ADR-0021: Current platforms only

- Status: Accepted
- Date: 2026-08-25
- Related: ADR-0012 (module boundary), ADR-0015 (packaging), ADR-0020 (documentation structure)

## In brief

- Theme: Operating Xmip
- Subject: Current platforms only
- Name: Current platforms only
- Order: 3
- Concepts: Pester, PowerShell, .NET, Rust versions; Version floors, channels

Xmip tracks the newest release of every platform it depends on and carries
no compatibility with superseded ones. PowerShell 7.7.0 Core, .NET 11, latest
stable Rust, Pester 6 (the amendments of 2026-10-19 and 2026-11-02 have every
version).

**The version numbers are not the decision** — they will be history soon enough.
The decision is the rule that produced them, which is why `prerequisite.toml`
and `rust-toolchain.toml` express channels rather than pins. A floor states what
would break; it does not freeze anything.

**And the rule itself has an end.** Latest anywhere and everywhere is a
design-phase policy, right because nothing depends on Xmip yet. It expires at
the first Linear release — the same trigger `release-model.md` uses to end its
own design-phase exception, for the same reason. See the amendment of
2026-09-03.

## Context

Xmip is new. Nothing depends on it, no customer is mid-migration, and there is
no installed base to protect. That is a position every platform occupies exactly
once, and it is worth spending deliberately rather than losing by default.

BizTalk is the cautionary case and the one Xmip is measured against. Its
compatibility burden is a large part of why it ossified: each release had to
carry the previous one, the .NET Framework it was built on could not move, and
by the end the effort of *not breaking* consumed the effort available for
*improving*. The technology was not the problem. The accumulated promise was.

The specific question that prompted this: whether PowerShell 5.1 or 6 should be
supported by the tooling, and whether `#requires -Version 7.0` or `7.6` is
right.

## Why this is realistic rather than hostile

The usual objection to a current-only policy is that it strands users. For the
platforms Xmip depends on, it does not, and that is what makes the policy
affordable:

- **.NET consumers move quickly.** The release cadence is annual, support
  windows are short and well published, and the ecosystem has been trained by a
  decade of it. An organization running .NET is already on a rapid path.
- **PowerShell users on Windows move quickly too.** Note the distinction:
  *PowerShell on Windows* is PowerShell 7 running on a Windows machine, and
  those installations update through winget, the Store or the MSI on a fast
  cycle. **Windows PowerShell** — the proper noun, 5.1, on .NET Framework — is a
  different product that ships with the operating system and does not move at
  all. Xmip requires the first and cannot use the second. `#requires -PSEdition
  Core` is what draws that line.
- **Rust has no long-term-support branch to speak of.** Stable ships every six
  weeks and the ecosystem follows; pinning is the unusual choice, not tracking.

So the burden a current-only policy places on an adopter is one they are
already carrying for other reasons. That is the difference between this and
demanding an upgrade nobody else is asking for.

## Decision

**Xmip targets current platforms. It does not carry compatibility with
superseded ones.**

Concretely, at the time of writing:

| | Xmip requires | Explicitly not supported |
| --- | --- | --- |
| PowerShell | 7.7.0 or later, Core edition | Windows PowerShell (5.1, .NET Framework) |
| .NET | 11 | 8, 9, 10 |
| Rust | latest stable, via `rust-toolchain.toml` | any pinned older toolchain |
| Pester | 6 or later | 3, 5 |

**These numbers are not the decision.** They will be old by the time Xmip is in
wide use anywhere, and quoting them in five years will be quoting history. The
decision is the rule that produced them:

> Track the current stable release of every platform Xmip depends on. Where a
> preview is the only way to reach a needed capability, track the preview and
> record the date it becomes stable. Do not accumulate support for what a
> platform has already superseded.

This is why `prerequisite.toml` and `rust-toolchain.toml` express **channels**
rather than pins — `channel = "stable"`, `channel = "preview"` — and why a
`minimum` is a floor rather than a target. A floor states what would break; it
does not freeze anything.

### Corollaries

**A version floor is a real refusal.** `#requires -PSEdition Core` and
`#requires -Version 7.7.0` are not advisory. A machine below the floor is told so
by PowerShell, by name and version, and nothing runs. That error message *is*
the compatibility documentation.

**PowerShell is the one prerequisite Xmip cannot install for you**, because the
tooling is written in it. Everything else — git, Rust, the linker, PSToml,
Pester, .NET — `Install-XmipPrerequisite` reports and can install.

**A newer major version is refused, not guessed at.** `Get-XmipManifest` accepts
schema 2.x and refuses 3.0, because a major bump may have moved something the
reader would then silently misread. Tracking current is not the same as
accepting anything.

**The estate is a customer of this rule too.** `xmip-core-transport-modbus`
speaks to hardware that predates all of the above by decades, and that is
correct: **Xmip integrates with ancient systems, it does not run on them.** The
protocols in `identity-by-technology.md` go back to the 1970s. The runtime does
not.

## Consequences

- Windows PowerShell 5.1 users cannot run Xmip tooling. That is intended, and
  it removes an entire class of "works differently on Desktop edition" defect.
- CI tracks stable rather than a pinned toolchain, so a Rust release can break
  the build. That is the cost, and it is paid in small, immediate increments
  rather than in one large migration later.
- A preview dependency means a dated obligation: `prerequisite.toml` records
  the date it becomes stable and what to change on that date. .NET 11's was
  met on 2026-11-12 (amendment 2026-11-12).
- Where a deployment genuinely cannot move — an air-gapped site, a regulated
  estate on a frozen image — the answer is a purpose-compiled runtime pinned at
  build time per `deployment-model.md`, not a compatibility branch in the
  mainline.

## Amendment, 2026-09-03: this rule has an end, and it is the first Linear release

**Latest anywhere and everywhere is a design-phase rule.** It is right now and it
becomes wrong the day Xmip is public. Recorded because the record above does not
say so, and a rule with no stated end is applied forever by whoever inherits it.

The Context section already gives the reason without drawing the conclusion:
*nothing depends on it, no customer is mid-migration, and there is no installed
base to protect.* All three stop being true on the same day.

### The trigger is the one the release model already uses

`release-model.md` ends its own design-phase exception — committing straight to
Continuum — at the **first Linear release**, and gives the reason: *a Linear
release is the first moment something exists that a change to Continuum can
break.* The same sentence is the reason this rule ends there. One trigger, two
practices, and nobody has to decide twice.

### What ends, and what does not

**Tracking a preview ends.** The *realistic rather than hostile* section above
justifies this policy by saying the burden it places on an adopter is one they
already carry. That test passes for current stable and **fails for a preview**:
installing a preview SDK to run a production integration platform is not
something anyone is already doing. .NET 11 reaching stable on 2026-11-10 removes
the instance; it does not remove the rule.

**Tracking current stable does not end.** Carrying compatibility with superseded
platforms is what ossified BizTalk, and that argument is not about phase. What
changes is that "current" acquires a published window instead of meaning
whatever shipped this morning.

### Continuum tracks, Linear pins

`release-model.md` rule 5 says **Linear must be reproducible**, and a release
that resolves `channel = "stable"` at build time is not. The two records have
disagreed since both were written and nothing had to reconcile them, because no
Linear release exists.

The reconciliation, stated here so it is not discovered during a release:
Continuum tracks channels, and a Linear release **pins what it was built with**
and publishes it. That is not a compatibility branch — the mainline still moves
— it is a release naming its own inputs, which is what reproducible means.

### What is not decided here

The supported-platform matrix a public Xmip publishes: how many versions back,
for how long, and what a security fix means for a superseded one. That belongs
to the release it constrains and cannot be usefully answered now. This amendment
records only that **the current rule expires rather than continuing by
default**, and names the moment.

*Raised by the owner, 2026-09-03: latest anywhere and everywhere is intended
because we are in a design phase, and will be obsolete if Xmip reaches a
public.*

## Amendment, 2026-10-19: every reference moves to the latest

The owner, 2026-10-19: *Let's be real, we are designing for the future,
update all references. PowerShell has gone to 7.6.7, .NET has skipped
forward. Maybe Rust has* — and *latest of .NET, Python and Java as well.*
The rule above, applied on that date; each version read from its publisher:

| | Xmip requires | Source |
| --- | --- | --- |
| PowerShell | 7.6.7 or later, Core edition: every `#requires` and manifest | released 2026-10-13 |
| .NET SDK | 11.0.100-rc.2.26504.105, preview channel, in every `global.json` | dotnet.microsoft.com, 2026-10-13 |
| Target framework | net11.0; net10.0 where pwsh 7.6.7 hosts (ADR-0014) | |
| Rust | latest stable, 1.99.1; edition 2024, still the latest | blog.rust-lang.org, 2026-10-15 |
| Pester | 6 or later; 6.2.0 current | PowerShell Gallery, 2026-09-09 |
| Java | 27, the current JDK; 25 is the current long-term support release | GA 2026-09-15 |
| Python | 3.15 | python.org, 2026-10-09 |
| Node | 26 for the VS Code extension; long-term support from 2026-10-28 | nodejs.org |

**Java follows the current release, not the long-term one.** The foreign
function and memory API the Java binding uses is final since 22, so the
binding compiles with `--release 27` and no preview flag. The Windows
package is Eclipse Temurin 27, the Eclipse Foundation's vendor-neutral
OpenJDK build (the owner, 2026-11-09: *Lets go with Temurin*); Microsoft
builds OpenJDK only for long-term support releases.

**Python 3.15 is installed on Windows through the Python install manager**
(`py install 3.15`); winget carries no package for 3.15 itself.

The GitHub Actions the workflows use move to their current majors:
`actions/checkout@v7`, `actions/setup-dotnet@v6`, `actions/setup-node@v7`.

## Amendment, 2026-11-02: the floor is the latest release, a release candidate included

The owner, 2026-11-02: *Set the latest to what we have. Do that always.
Notify me of updates of underlying components*, and *7.7.0-rc.x, .NET 11
rc.x, Rust x.* A floor is no longer the newest stable release alone: it is
the latest release, a release candidate included, raised the day it is out.
Applied that day:

| | Xmip requires | Source |
| --- | --- | --- |
| PowerShell | 7.7.0 or later, Core edition: every `#requires` and manifest; 7.7.0-rc.1 passes it | GitHub releases, 2026-10-29 |
| PowerShell Gallery modules | the gallery's newest: Pester 6.2.0, PSToml 0.5.0, powershell-yaml 0.4.12, posh-git 1.1.0; `Install-XmipPrerequisite` compares | PowerShell Gallery |
| Microsoft DSC | 3.3, the newest stable | GitHub releases, 2026-09-17 |
| Crates and NuGet packages | the newest release of each | crates.io, nuget.org |

PowerShell 7.7 hosts .NET 11, so the exception above for what pwsh loads
follows it (ADR-0014).

## Amendment, 2026-11-07: previews too, and a package a day old

The owner, 2026-11-07: *Xmip adopts previews until Xmip goes Linear, GA.*
Until the first Linear release, a preview is the latest too: a preview
release (Microsoft DSC 3.4.0-preview.x) and a preview or experimental
feature of a language or runtime (C# 15's updated memory-safety rules,
.NET 11's Runtime Async) are adopted, and reworked when they change.

One exception, the owner's choice the same day: NuGet takes no package
published less than 24 hours ago, so a package withdrawn in its first day
as malicious never reaches a build. Every .NET repository carries a
`nuget.config` that clears the inherited sources and names nuget.org with
`minPublishAgeHours`, the number `architecture.toml` declares once
(`[project] nugetMinimumAgeHours`); `test/Dotnet.Target.Test.ps1` holds
them equal. NuGet refuses a floating version while an age is set (NU1020),
so every package reference names its exact version, raised to the newest
release old enough the day one is out: the four that floated as
`11.0.0-rc.3.*` name `11.0.0-rc.3.26522.148`.

Applied that day:

| | Xmip requires | Source |
| --- | --- | --- |
| Git | 2.56 | git-scm.com, 2026-09-28 |
| ansible-core | 2.22, with four security fixes over 2.21 | GitHub releases, 2026-11-02 |
| NuGet packages | the newest release at least 24 hours old | nuget.org |

## Amendment, 2026-11-11: the deploy track's tools

Checked 2026-11-11, for the environments `Deploy-XmipEnvironment` makes in
either technology (ADR-0015, amendment 2026-11-11):

| | Xmip requires | Source |
| --- | --- | --- |
| PowerShell | 7.7.0, out 2026-11-10; the release candidate rc.1 before it | GitHub releases, PowerShell/PowerShell |
| Microsoft DSC | 3.4.0-preview.2, still the latest; the Linux tarball a node machine is brought | GitHub releases, PowerShell/DSC |
| ansible-core | 2.22, which needs Python 3.13: on AlmaLinux 10.2, whose python3 is 3.12, pip stops at 2.21.6 until python3.13 is installed from EPEL | pypi.org, 2026-11-02 |
| community.libvirt | 2.4.0, of 2026-10-09, with libvirt's Python binding and lxml from the distribution | Ansible Galaxy |
| microsoft.hyperv | 1.1.0, of 2026-05-19 | Ansible Galaxy |
| nfpm | 2.48.0, of 2026-10-12 | GitHub releases, goreleaser/nfpm |

The tarballs a machine is brought are named in the environment file with
their SHA-256, each the release's own digest, and refused where they differ.

## Amendment, 2026-11-12: .NET 11 is generally available

.NET 11 left the preview channel on 2026-11-10, and SDK 11.0.100 was
installed on this computer on 2026-11-12 (ADR-0014, amendment 2026-11-12).
The rule above, applied that day:

| | Xmip requires | Source |
| --- | --- | --- |
| .NET SDK | 11.0.100, stable channel, in every `global.json`, no prerelease taken; its release candidates are below it | the installed SDK; .NET 11.0.0 on nuget.org, 2026-11-10 |
| .NET MAUI | 11.0.0, from the workload set 11.0.100.1 | `dotnet workload list` |
| `Microsoft.PowerShell.SDK` | 7.7.0 | nuget.org, 2026-11-10 |

`prerequisite.toml` says the stable channel and winget's
`Microsoft.DotNet.SDK.11`, the change it recorded for that date.

## Amendment, 2026-11-19: the platform's call replaces hand-made code

Once a floor has a call that does what the estate's own code does by hand,
the call replaces that code, every use of it, and the hand-made code is
deleted rather than kept beside it. The first two, applied that day, are
the temporary folder's:

| | The platform's call | What it replaced |
| --- | --- | --- |
| PowerShell | `New-TemporaryDirectory`, from 7.7.0, generally available 2026-11-10, and `$TestDrive` in a Pester test | names built under `[System.IO.Path]::GetTempPath()`, `GetTempFileName()`, and the event bindings' own wrapper of the call in `verify-event-bindings.ps1` |
| .NET | `Directory.CreateTempSubdirectory`, in .NET since 7 | a name built under `Path.GetTempPath()` and made with `Directory.CreateDirectory`, in the operator surfaces' and the GUI's tests |

The platform names the folder at random, where a name built by hand can be
known and made first by another account (ADR-0015, amendment 2026-11-11),
and is left behind by a run that stops before its own cleanup.
`test/Xmip.Style.Test.ps1` refuses `GetTempPath()` and `GetTempFileName()`
in `Xmip/` and `test/`, except in `test/XmipProcess.Test.ps1`, which asserts
the runtime's default folder `<temp>/xmip/process`
(`doc/governance/powershell-style.md`, sections 5 and 6), and
`test/CSharp.Style.Test.ps1` refuses a folder made under `Path.GetTempPath()`
in C#.

## Amendment, 2026-11-19: Rust's temporary folder is one guard, as Rust has no call

Rust's standard library has no call that makes a temporary folder:
`std::env::temp_dir()` names the directory and nothing more. So each Rust
test built a name under it, from the process id, a counter, a clock reading
or nothing at all: 179 calls in 143 files that day. A test that removed its
folder as its last line left it behind when it failed, and the factory tests
of nine contract crates never removed theirs.

What stands now:

- A test's folder is `file::temporary::Folder`, from the `test-support`
  feature of the Library `xmip-core-library-file`, taken as a dev-dependency
  (`module/core/library/file/src/temporary.rs`): it acts on a file, which
  is not Foundation's (ADR-0058 clause 1), as the directory sync moved there
  the same day. It is `xmip-<label>-<UUIDv7>` under the system's temporary
  directory, the UUIDv7 the `uuid` crate's `v7`, the crate xmip-core names
  its identifiers by, an optional dependency of the Library under
  `test-support` alone, its random bits the operating system's (through
  `getrandom`); it is made with `create_dir`, which refuses a folder
  already there rather than taking it over; on Unix only its owner may enter
  it; and dropping it removes it with everything in it, also when the test
  panics. A test makes its folder first, so that it outlives every file,
  database or socket the test opened in it; where something must not exist
  yet, the test names a path inside its folder.
- Another Library takes it as a dev-dependency, as `net` and `tls` take
  `xcore::latency`: what a Library is built from stays Library
  (`test/Layer.Test.ps1` reads `[dependencies]`). The Essentials, a test
  never in a node, takes it among its dependencies, and the runtime under
  its own `test-support`, for its test authority.
- `test/Rust.Style.Test.ps1` refuses `temp_dir()` in any Rust file but the
  guard and six that name a place a program itself uses, each with its
  reason (`doc/governance/rust-style.md` section 5f): a named endpoint's path
  on Unix, the runtime's default `<temp>/xmip/process`, the language
  server's copies of the runtime it loads, the runtime fixture that names
  the shared place a test must not write in, a Unix socket's far end, whose
  address is its path as a network transport's is a port (ADR-0051), and
  the Essentials roll's working folder, named for its cluster.

Evidence, 2026-11-19. `git grep --recurse-submodules -n 'temp_dir()' -- '*.rs'`
before and after, and the guard's own tests, `cargo test --lib temporary` in
`module/core/library/file`, on Windows and on Linux (the owner-only test is
Unix's):

```text
before: 179 lines
after:   11 lines: the guard's 2, and 9 in the six files the style test allows
Windows: test result: ok. 4 passed; 0 failed; 0 ignored; 0 measured; 1 filtered out
Linux:   test result: ok. 5 passed; 0 failed; 0 ignored; 0 measured; 1 filtered out
```

## Amendment, 2026-11-19: Rust 1.100

Rust 1.100.0, released 2026-11-12 (the Cargo changelog), is the floor by the
rule of 2026-11-02; `rust-toolchain.toml` follows `stable` and needs no
change. The code builds on 1.99.1 as well, clippy's warnings denied: every
form below is in 1.99.1's standard library too. Three of its changes reach the
estate, each found by a full pass over every workspace on Linux:

```text
$ cargo clippy -j 8 --all-targets --all-features -- -D warnings
error: called `map(_).unwrap_or_default()` on an `Option` value
103 +             .map_or_default(|contract| format!(" carrying {contract}"));
error: the loop variable `at` is used to index `figures.values`
warning: unused dependency `secret`
   = note: `cargo::unused_dependencies` is set to `warn` by default
error: warnings are denied by `build.warnings` configuration
```

- **Clippy's `map_unwrap_or`** (pedantic, which every crate warns) now
  reads `map(f).unwrap_or_default()` on an `Option` or a `Result` and asks
  for `map_or_default(f)`, the same value: 63 sites on an `Option` and 12 on
  a `Result` in 36 workspaces are written so, and one loop in
  `xmip-core-operate` walks `figures.values` rather than indexing it
  (`needless_range_loop`).
- **Cargo's own lints**, `unused_dependencies` among them, a warning by
  default and an error under the estate's `[build] warnings = "deny"`
  (`.cargo/config.toml`, Cargo 1.97). A crate empty off its own platform is
  a dependency of that platform alone (ADR-0062, amendment 2026-11-19); a
  dependency only tests use is a dev-dependency (`xmip-core-resilience` in
  the HTTP, Kafka and AMQP transports); and what `xmip-service` alone uses
  — `ctrlc`, `windows-service`, `xmip-core-operate` — comes with `node`,
  which the program requires, so a build that leaves the program out does
  not link them.
- **The build directory's new layout.** Final artifacts stay where they
  were: `<target>/debug/` holds the binaries, the cdylibs and `examples/`,
  so `Get-XmipEssentialsLayout` and `Test-XmipEssentialsBinary` find the
  Essentials as before. A test program moved, from `<target>/debug/deps/`
  to a unit's own `<target>/debug/build/<package>/<hash>/out/`, so a test
  that found an example one folder above itself found none; the runtime's
  test of a generated unit's library now looks up every folder above it,
  and the Essentials' binary lookup no longer looks one folder above
  itself, which only a test program in `deps/` ever needed. A cdylib
  crate's rlib is written in its unit's own folder too
  (`build/xmip-core-operate/<hash>/out/libxmip_core_operate.rlib`), so
  workspaces no longer share one unhashed file: the layout ended the
  collision of 2026-10-06, two `xmip_core_configure` in one graph after
  one workspace's unhashed rlib was linked by another. Every machine builds
  with 1.100, so what removed that file from `deps/` before each workspace
  is deleted: `Clear-XmipUnhashedLibrary`, `Unhashed` in
  `Get-XmipEstateCrate`, its calls in `Test-XmipChangeTree` and
  `Invoke-XmipPatchedBuild`, and its two tests. Two toolchains never share
  one build directory: 1.99.1 after 1.100 in the same one stopped with
  "could not parse/generate dep info".

```text
$ cargo test --test gathered_cluster        (module/core/operation/cli, 1.100)
     Running tests/gathered_cluster.rs (<target>/debug/build/xmip-core-cli/<hash>/out/gathered_cluster-<hash>)
the full 1.100 test pass, module/platform/runtime, before the change:
library::tests::a_unit_generated_from_a_design_opens_from_beside_its_configuration_and_turns --- FAILED
panicked at src/library.rs:381:9
$ cargo test --features dynamic-loading --lib -- library::tests::a_unit_generated_from_a_design
test library::tests::a_unit_generated_from_a_design_opens_from_beside_its_configuration_and_turns ... ok
```

The last line is the same on 1.100 and on 1.99.1, where the test program is
still in `deps/`.

**Provenance.** The owner's rule that the latest is the floor (amendment
2026-11-02); the pass over every workspace and the fixes are the
assistant's, at the coordinator's order.

## Amendment, 2026-11-20: a .NET test's temporary folder is one helper, `TestFolder`

`Directory.CreateTempSubdirectory` (amendment 2026-11-19) makes a folder and
does not remove it. On 2026-11-20 the GUI's tests had left about 1,267
folders per label under the system's temporary directory, 12,307 in all,
the newest from 2026-11-19 at 08:08. Until that day the page tests removed
their folder in their own `IDisposable.Dispose`, and xUnit v3 never calls it
on a bUnit page test: it disposes a test class through `IAsyncDisposable`
where the class has it and through `IDisposable` only where it has not, and
`BunitContext` has both. Its source, `TestRunner.DisposeTestClassInstance`:

```text
if (testClassInstance is IAsyncDisposable asyncDisposable)
    await asyncDisposable.DisposeAsync();
else if (testClassInstance is IDisposable disposable)
    disposable.Dispose();
```

The change of 2026-11-19 moved that removal into `DisposeAsyncCore`, and the
page tests have left nothing since. But each of the other sites still made
its own temporary path and removed it its own way: by `try` and `finally`, by
`File.Delete`, by a `catch` that kept what it could not remove, or not at all
where the path was only to be absent. That was 77 calls in 54 files.

What stands now:

- A .NET test's folder is `TestFolder`, in
  `module/core/operation/operate/dotnet/Xmip.Surface.Test/TestFolder.cs`,
  linked into every .NET test project that makes one, as `TestCluster` is:
  `Xmip.Operate.Test`, `Xmip.Gui.Test` and `Xmip.Operations.Test`. That is
  where the estate's shared .NET test code already is. The one lower .NET
  project, xmip-core-abi's `Xmip.Abi`, is a Foundation definition that opens
  no file (ADR-0058 clause 1), and its test makes no folder.
- `Directory.CreateTempSubdirectory` makes it, `xmip-<label>-<random>`, the
  random part from the operating system. On Windows that is eight random
  bytes as an 8.3 name, made with `CreateDirectory`, which takes another name
  where one is already there. On Unix it is `mkdtemp`, with entry for the
  owner only. Disposing it removes it with everything in it, also when the
  test throws, and never throws itself: a folder that cannot be removed is
  named on standard error. A test makes its folder first, so that it is
  disposed after every file, host or watcher opened in it. A path that must
  not exist is named inside it (`TestFolder.Inside`).
- A bUnit page test disposes its folder in `DisposeAsyncCore`, after the
  base. `AsyncDisposalTest` is linked beside `TestFolder` and refuses a test
  class that xUnit disposes asynchronously and that has its own
  `IDisposable.Dispose`. In the GUI's tests, `Unacted` is an assembly
  fixture. It names the audit no Observer's act writes, and its folder is
  removed after the last test.
- `test/CSharp.Style.Test.ps1` refuses `CreateTempSubdirectory(`,
  `GetTempPath(`, `GetTempFileName(` and `"TEMP"`, `"TMP"` and `"TMPDIR"`
  in any C# file, comments aside, except three. Each is listed with its count
  and its reason: the helper (1); its test, which asserts where the folder is
  made (1); and the runtime library's copies in `NativeRuntime.cs` (1), the
  one folder every process loading the library shares. This replaces the
  check of 2026-11-19, a `GetTempPath()` beside a `CreateDirectory(` in one
  file. C# has no style document, so the test's header states the rule.
- The folders already left were removed after a check of their content as
  well as their names. A folder was removed only where its name was in the
  shape its test made, `xmip-<label>-` and then a GUID's 32 digits or
  `CreateTempSubdirectory`'s 8.3 name; where every file in it was one that
  test writes; and where every audit record in it was written under a
  program that test writes as. That is the test assembly's own
  (`Xmip.Gui.Test`, `Xmip.Surface.Test`, `Xmip.Abi.Test`,
  `xmip-operations`), or the one its fixture names: the Audit view's
  cluster records, the hidden run's `probe`, the web host's `xmip-gui-web`.
  12,395 folders were removed and none was refused. They were the GUI's
  12,307, 20 of `Xmip.Surface.Test`'s, and 66 of `Xmip.Abi.Test`'s Event
  tests from before those tests moved to `Xmip.Operate.Test` (2026-11-17).
  One more was a Reports test's of 2026-11-10, and one was left by the
  guard's failing run below.

Evidence, 2026-11-20, on Windows; nothing touched is Unix-only:

```text
$ dotnet test src/Xmip.Gui.Test    (before this change, the code of 2026-11-19)
Passed!  - Failed:     0, Passed:   154, Skipped:     0, Total:   154
xmip-gui-* folders made by this run: 0
$ Invoke-Pester -Path test/CSharp.Style.Test.ps1            (before)
makes a temporary path nowhere but where it is allowed      FAILED: 54 files, 77 calls
module/core/operation/gui/src/Xmip.Gui.Test/SubscriptionsViewTest.cs makes 1 where 0 is allowed, at 36
module/core/operation/operate/dotnet/Xmip.Operate.Test/RuntimeCertificatesTest.cs makes 6 where 0 is allowed, at 25, 55, 108, 142, 179, 211
$ Invoke-Pester -Path test/CSharp.Style.Test.ps1            (after)
Passed makes a temporary path nowhere but where it is allowed
Passed keeps every line at or under 100 columns
$ dotnet test src/Xmip.Gui.Test    (TopologySelectionTest given back its own IDisposable.Dispose)
Failed Xmip.Surface.Test.AsyncDisposalTest.NoTestClassXunitDisposesAsynchronouslyCleansUpInItsOwnDispose
Collection: ["Xmip.Gui.Test.TopologySelectionTest"]
gui-topology folders left by this run: 1
$ dotnet test src/Xmip.Gui.Test    (DisposeAsyncCore, as it stands)
Passed!  - Failed:     0, Passed:     2, Skipped:     0, Total:     2
gui-topology folders left by this run: 0
$ dotnet test, each project, then the folders made under <temp> since the first began
Passed!  - Failed:     0, Passed:   320, Skipped:     0, Total:   320 - Xmip.Surface.Test.dll
Passed!  - Failed:     0, Passed:   110, Skipped:     0, Total:   110 - Xmip.Operate.Test.dll
Passed!  - Failed:     0, Passed:   155, Skipped:     0, Total:   155 - Xmip.Gui.Test.dll
Passed!  - Failed:     0, Passed:    11, Skipped:     0, Total:    11 - Xmip.Operations.Test.dll
xmip-* made under <temp> since the first began: 0
the scan of <temp> by name, files and audit programs above, then the removal:
theirs: 12395      not theirs or too recent: 0      removed: 12395
```

**Provenance.** The leftovers were found by the coordinator on 2026-11-20,
and the Rust rule is this record's amendment of 2026-11-19. The helper, the
guard, the style test and the removal are the assistant's, at the
coordinator's order.

## Alternatives considered

**Support the previous major of each platform.** The conventional choice, and
the one that produced BizTalk's position. Rejected: it doubles the test matrix
for a user base that does not exist yet, and the second version is always the
one nobody actually runs but everything must accommodate.

**Pin exact versions rather than channels.** Reproducible, and wrong for a
project at this stage. A pin ages silently — nothing fails, the numbers simply
become false — whereas a channel that breaks tells you immediately, while the
change is small.

**Decide per platform rather than as a rule.** Rejected: that is how a policy
becomes a set of unrelated version numbers nobody can defend, which is the
state this ADR was written to leave.
