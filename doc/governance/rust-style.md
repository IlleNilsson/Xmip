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

`test/Rust.Style.Test.ps1`, over `module/**/*.rs` and `template/**/*.rs`.

**The template is measured too.** Every new repository is generated from it, so
a rule the template does not obey is a rule every new repository starts out
breaking.

| Rule | Section | Enforced |
| --- | --- | --- |
| Formatting | — | yes, by `Publish-XmipChange` at landing |
| Clippy, `-D warnings` | — | yes, by `Publish-XmipChange` at landing: a changed module with its default features, a consumer with every feature it declares |
| File over 400 lines before `#[cfg(test)]` | 1, 2 | yes |
| Function length | 3 | **warned by clippy, never gated** |
| A filename repeating its crate | 5 | yes |
| `mod.rs` | 5 | yes |
| A repeated name covering two subjects | 5 | reported, judged by people |
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
amendment 2026-09-25). The runtime is the one exception, refined the same
day: its whole C boundary — the operator's exports and the module loader —
is one folder, `src/ffi/`, each file under 400 lines, and what a boundary
file does beyond reading and writing pointers stays outside it. Its `Cargo.toml` says `unsafe_code = "deny"` rather
than `forbid`, because Rust lets no file lower `forbid`; the file lowers
`deny` at its top with its reason. `test/Unsafe.Test.ps1` holds the folder and
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
Playground alone, under the rule that anything over a millisecond apart from
load is a defect (`CONTRIBUTING.md`). The first build after a dependency
changes takes longer; every build after it is cached. `test/Rust.Style.Test.ps1`
holds every workspace root to it.

## 6. What this does not enforce

Module layout beyond file length, whether a `struct` should have been three, and
whether a trait earns its existence. Those need judgment and are reviewed by
people.

Listing them here as enforced when they are not is the failure mode
`powershell-style.md` section 6 already had once — it named its own test file
for some time before that file existed.

Style that is only written down decays. ADR-0021 made that argument about
version floors and it applies equally here.
