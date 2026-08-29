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
`tests/` directory rot.

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
is a catalogue of mechanisms — one `pub fn` per mechanism, each three lines.
That is a table, not complexity. A short function with four nested `match`
arms is worse and would sail through.

So **branches, not lines**: `if`, `match` arms, loops, `?` on a fallible call,
`&&` and `||`. `clippy::too_many_lines` is enabled as a **warning and never a
gate**, for the reason above.

## 4. What this is enforced by

`tests/Rust.Style.Tests.ps1`, over `modules/**/*.rs` and `template/**/*.rs`.

**The template is measured too.** Every new repository is generated from it, so
a rule the template does not obey is a rule every new repository starts out
breaking.

| Rule | Section | Enforced |
| --- | --- | --- |
| File over 400 lines before `#[cfg(test)]` | 1, 2 | yes, with a ratchet |
| Function length | 3 | **warned by clippy, never gated** |
| A filename repeating its crate | 5 | yes |
| `mod.rs` | 5 | yes |
| A repeated name covering two subjects | 5 | reported, judged by people |
| One subject per file | 1 | reviewed by people |

**400 is taken from measurement, not chosen.** On 2026-08-27 the estate's
production files were: three over 400, and everything else at 305 or below. The
gate sits above the settled body of the estate and below the three that are
genuinely doing too much.

### The ratchet, and why it is not a waiver list

Three files exceed the gate today and are recorded in the test with their
current size:

```text
foundation/core/src/identity.rs        705
capabilities/route/src/lib.rs          680
platform/runtime/src/arrival.rs        440
```

**A ratchet may only shrink.** The test fails if any of them grows, and fails if
a file not on the list exceeds the gate. Removing an entry is the only edit that
does not need a reason.

That is the difference from the waiver list `powershell-style.md` buried. A
waiver list absorbs new violations and its maintenance becomes the work. A
ratchet cannot: the only way to change it in the direction the code is drifting
is to fix the file.

*`arrival.rs` is on that list because of work done on 2026-08-27, in the same
session that wrote this document. It is recorded rather than excused.*

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

## 6. What this does not enforce

Module layout beyond file length, whether a `struct` should have been three, and
whether a trait earns its existence. Those need judgement and are reviewed by
people.

Listing them here as enforced when they are not is the failure mode
`powershell-style.md` section 6 already had once — it named its own test file
for some time before that file existed.

Style that is only written down decays. ADR-0021 made that argument about
version floors and it applies equally here.
