# Xmip Rust style

Rust has `rustfmt` and clippy, and this document does not repeat them. What is
here is the part a formatter cannot decide: **where code lives**.

The companion to `powershell-style.md`, and it inherits that document's hardest
lesson — see section 4.

## 1. A file has one subject

**One file, one thing.** A reader who opens `smtp/session.rs` should find
saying and hearing lines, and nothing about listeners, targets or claims.

The test is not length, it is whether the file's name describes everything in
it. `transport/src/lib.rs` was called "transport" and held five protocols, a
TLS client, an error taxonomy, a claim model and a header parser. Every one of
those is a thing; none of them is "transport".

**The estate already declares this shape one level up.** `architecture.toml`
gives each protocol its own repository — `xmip-core-transport-kafka` and eighty
siblings. One file per subject is the same principle inside a crate, and it is
what makes lifting a subject out into its own repository a move rather than a
rewrite.

## 2. Production code and tests are measured separately

`#[cfg(test)] mod tests` at the foot of the file is idiomatic Rust and stays.
Tests beside what they test get read and get updated; tests in a distant
`test/` directory rot.

So **the gate counts the lines above `#[cfg(test)]`**. A file that is 200 lines
of code and 300 lines of tests is a well-tested file, not a long one, and a
measure that cannot tell those apart would push tests out of the file to make a
number go down.

## 3. A function does one thing, and the number to read is branches

**Name the parts rather than scrolling.** `HttpTransport::accept_one` was fifty
lines doing five things — accept, read the head, find the path, size the body,
read it, answer. Six names, six testable pieces, and the body-size check moved
*before* the allocation where it belongs.

**Length is not the measure and this is settled.** `powershell-style.md`
section 6 records what happened when function length was gated: a waiver list
that reached sixteen entries, adjusted four times consecutively, catching
nothing, while the line-length rule caught twenty-five real violations in the
same period.

Length is also the wrong shape. `core/identity.rs` is 705 lines of which most
is a catalog of mechanisms — one `pub fn` per mechanism, each three lines.
That is a table, not complexity. A short function with four nested `match`
arms is worse and would sail through.

So **branches, not lines**: `if`, `match` arms, loops, `?` on a fallible call,
`&&` and `||`. `clippy::too_many_lines` is enabled as a **warning and never a
gate**, for the reason above.

## 4. What this is enforced by

`test/Rust.Style.Test.ps1`, over every `.rs` file `Get-XmipSourceFile` counts
under the root crate's `.src`, `module/`, `test/`, `template/` and `sdk/`: a
crate's programs in `src/bin` too, build output never. Until 2026-11-11 every
directory called `bin` was skipped as .NET's output, and the Essentials' roll
and node had grown past the gate unread; now only the `bin` beside a .NET
project is. **The root's `.src` is gated too**, `xmip-service` among it: it
was no tree the gate read until the same day, when `.src/service/run.rs` had
reached 407 lines unmeasured (ADR-0049, amendment 2026-11-11).

**The template is measured too.** Every new repository is generated from it, so
a rule the template does not obey is a rule every new repository starts out
breaking.

| Rule | Section | Enforced |
| --- | --- | --- |
| Formatting | — | yes, by `Publish-XmipChange` at landing |
| Clippy, warnings denied | — | yes, by `Publish-XmipChange` at landing: a changed module with its default features, a consumer with every feature it declares; a warning fails every cargo build under the estate root (`[build] warnings = "deny"`, `.cargo/config.toml`), and a module repository alone denies them in the shared `rust-verify.yml` |
| File over 400 lines before `#[cfg(test)]` | 1, 2 | yes |
| Function length | 3 | **warned by clippy, never gated** |
| A filename repeating its crate | 5 | yes |
| `mod.rs` | 5 | yes |
| A repeated name covering two subjects | 5 | reported, judged by people |
| A timing test in its module's `measured` program, run last and alone | 5c | yes: run so by `Publish-XmipChange` at landing, and where one sits by `test/Timing.Test.ps1` |
| One subject per file | 1 | reviewed by people |

**400 is taken from measurement, not chosen.** On 2026-08-27 the estate's
production files were: three over 400, and everything else at 305 or below. The
gate sits above the settled body of the estate and below the three that are
genuinely doing too much.

### Length is a strict recommendation

**400 is not a law.** It is where the estate settled, and a file with a genuine
reason to be longer may be longer.

What breaking it costs is a sentence. No file is over the gate, and the test
holds no list of exceptions; an agreed one is written into the test beside the
gate with its reason, because an exception with no reason cannot be told from
something nobody got round to. That cost is what keeps exceptions rare, and
rare is the goal rather than zero.

**The reason is agreed before the exception is written, not offered after it.**
A recommendation this strong is broken by asking the estate's owner and being
told yes, and the answer belongs in the entry. Anyone contributing follows this;
an assistant follows it absolutely, because an assistant is exactly the
contributor most likely to find a rule inconvenient at two in the morning and
record a plausible sentence rather than ask. A reason written to justify a
decision already taken is not a reason, it is a defense.

The same holds for line length in `powershell-style.md`. Neither is a rule that
good code never breaks; both are rules that good code breaks knowingly and says
so.

## 5. A file is named for what it defines, in the estate's own words

Section 1 says a file has one subject. This says what to call it.

**The name comes from `terminology.md` or a decision record.** Not invented at
the keyboard. `Arriving` and `Departing` live in `direction.rs` because ADR-0019
is *Identity, Parties and the two directions* and `terminology.md` files them
under *Identity, Party and direction* — so an operator, a decision record and a
source file all use one word for one thing.

**A name may repeat across crates when the subject is the same.** The module
path qualifies it, exactly as `std::fmt::Error` and `std::io::Error` coexist.
`xmip_core::direction` is the vocabulary and `xmip_transport::direction` is
which directions one implementation supports; they are the same subject at two
levels and both deserve the documented word. A uniqueness rule would force one
of them to a word the documentation does not have, which is worse than the
repeat.

**A name may not cover two subjects.** This is the rule that was actually being
broken. Three files were called `identity.rs`:

```text
foundation/core/src/identity.rs      Purpose, Arriving, Departing, Mechanism...
foundation/context/src/identity.rs   Verified, AuthenticatedIdentity, Alignment
foundation/party/src/identity.rs     Identity
```

The vocabulary, the outcome of the gates, and a Party's identity. One name,
three subjects, and only the third earns it.

**A filename does not repeat its crate.** `transport/src/transport.rs` inside
`xmip-core-transport` spends its name saying where it already is. It holds the
trait every protocol implements, so it is `protocol.rs`.

**A name that its own file contradicts is the worst case**, because the file
argues with itself. `runtime/src/receive.rs` opened with *"What a Message
generation is, and the three treatments an artifact declares"* while a whole
crate called `xmip-core-receive` existed elsewhere. It is `generation.rs`.

**No `mod.rs`.** `http.rs` beside `http/`, not `http/mod.rs`. The 2018 form puts
the module's name in the tab bar instead of five identical tabs.

## 5a. Unsafe code lives in one named file

A crate forbids unsafe code. A crate that must call a C interface allows it
in one named file and nowhere else, and every block in that file says where
its pointers come from, how long they live and who frees them (ADR-0050,
amendment 2026-09-25). A boundary longer than a file is a folder, refined
the same day for the runtime: its whole C boundary — the operator's exports and the module loader —
is one folder, `src/ffi/`, each file under 400 lines, and what a boundary
file does beyond reading and writing pointers stays outside it. `net` keeps
its named pipe's calls into Windows the same way, in `src/pipe/windows/`
(amendment 2026-10-21). Such a crate's `Cargo.toml` says `unsafe_code = "deny"` rather
than `forbid`, because Rust lets no file lower `forbid`; the file lowers
`deny` at its top with its reason. `test/Unsafe.Test.ps1` holds the folders and
the list of those files, one per crate, fails on any other file that allows
unsafe code or crate that lowers the lint without one, and fails on a block without its `SAFETY`
comment.

## 5b. Dependencies build optimized, even in a debug build

Every crate that is its own workspace root carries

```toml
[profile.dev.package."*"]
opt-level = 3
```

so what a crate depends on runs at near release speed in a debug build,
while the crate's own code stays debuggable. Unoptimized, a parser such as
`toml` runs about twenty times slower; that, not Xmip, was behind a week of
tests failing on time and a cluster that judged healthy nodes hung
(2026-09-25). The owner, 2026-09-26, chose it for every crate over the
Essentials alone, under the rule that anything over a millisecond apart from
load is a defect (`CONTRIBUTING.md`). The first build after a dependency
changes takes longer; every build after it is cached. `test/Rust.Style.Test.ps1`
holds every workspace root to it.

**The estate's own crates build optimized too** (the owner, 2026-11-01: the
millisecond rule is measured on the optimized build). Set once, in the
configuration every cargo build under the estate root reads,
`.cargo/config.toml`:

```toml
[profile.dev]
opt-level = 3
```

so a crate's own tests — the runtime's, the root's measured service tests —
run its code as it ships, with debug assertions and debug information kept.
A workspace root built alone, outside the estate, keeps only its
dependencies optimized. `test/Rust.Style.Test.ps1` holds the configuration
to it.

## 5c. A timing test runs alone, in its module's `measured` program

A test that holds Xmip to a time — the millisecond rule's fastest of five
(`xcore::latency`'s `spread` and `at_once`), a Message's own share
(`xcore::spent`), a budget of milliseconds an operation — is in its module's
timing program and nowhere else: the cargo test target `measured`, declared
with `test = false` so a plain `cargo test` leaves it out:

```toml
[[test]]
name = "measured"
path = "tests/measured/main.rs"
test = false
```

The landing runs it after every other test of the module has passed, with
every feature the module declares and one test thread
(`Test-XmipMeasuredProgram`, the rule's one implementation), and lints it
apart, since `--all-targets` leaves it out too. Modules verify one after
another, so nothing else runs beside it. By hand, the same:

```powershell
cargo test --test measured --all-features -- --test-threads=1
```

The owner, 2026-11-01, after landings failed at random on timing tests run
inside a module's parallel suite: the other tests' load slowed the measured
work 1.5 to 3 times — the clock drops, and hyperthread siblings share a
core — and each passed alone. The root's service tests were moved the same
way the day before (ADR-0018), and every other module's on 2026-11-02. A
test that only proves something ends or waits — a lower bound alone, or an
upper bound of a second or more, such as a stop within seconds — is not a
timing test, and stays where it is; an upper bound under a second is one.

Where a test mixes the two — a thousand sends on one session and that
session replaced, and the thousand timed — it is split: the behavior stays
where it was, and the timing program holds the time over the same far end,
reached through the crate's public surface. A timing test that needs a
module's private items takes them through the estate's `test-support`
convention: `#[cfg(any(test, feature = "test-support"))] pub mod fixture;`
or the like, as little as the test needs, and `required-features =
["test-support"]` on the program where the crate does not already give its
tests that feature. What a module's tests and its timing program both stand
up — a far end, a schema, a crowded node — is written once, in a file
under the program's folder both include with `#[path]`, or behind
`test-support`; a helper of a line or two, such as a scratch directory, is
written again rather than shared.

**A storage device's sync is the disk's time, never Xmip's.** Waiting for
the device to sync — `fsync`, `FlushFileBuffers`, a directory's sync, the
Ledger's sync — is measured and reported apart from Xmip's own share, and
the millisecond holds Xmip's own work only; a bound is never raised for
it. The owner, 2026-11-09 (ADR-0018, amendment 2026-11-09). Every sync
Xmip makes waits through one helper, `xcore::spent::on_sync`, which runs
it as the payload's I/O, so a Message's own share leaves it out, and adds
the time it waited to the Message's disk time (`Spent::disk_sync`); no
sync is timed anywhere else. A node reports both, the fastest of five, in
its stop record: `own_share_ns`, held under the millisecond, and
`disk_sync_ns` beside it, held to nothing.

`test/Timing.Test.ps1` holds it: a timing assertion — an `assert!` holding
a measured time, a fastest of five or a figure read in milliseconds or
less, under a bound below a second, or a call of `xcore::latency::at_once` —
anywhere in a module's tests outside a `measured` folder fails it, and so
does a `measured` program declared without `test = false`.

## 5d. A test that runs a minute fails the landing

Every `cargo test` of a landing runs through `Invoke-XmipCargoTest`. The
first time libtest says a test *has been running for over 60 seconds*, the
run is stopped with every process beneath it, the test is named, and the
module fails. The minute is libtest's own word, not a limit Xmip sets: no
test needs it, so a test that reaches it waits on something that will not
come. On 2026-11-04 a landing waited
two hours on seven TLS tests that never ended, and nothing said so.

## 6. What this does not enforce

Module layout beyond file length, whether a `struct` should have been three, and
whether a trait earns its existence. Those need judgment and are reviewed by
people.

Listing them here as enforced when they are not is the failure mode
`powershell-style.md` section 6 already had once — it named its own test file
for some time before that file existed.

Style that is only written down decays. ADR-0021 made that argument about
version floors and it applies equally here.
