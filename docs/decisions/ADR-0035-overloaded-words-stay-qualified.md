# ADR-0035: An overloaded word stays qualified; the glossary arbitrates

- Status: Accepted
- Date: 2026-09-06
- Related: ADR-0011 (module and repository naming), ADR-0018 (the Service and the
  Host Services — the senses "Process" collides on), ADR-0030 (prefix external
  names, not internal ones), docs/terminology.md

## In brief

- Theme: The shape of the estate
- Subject: A word that means several things is qualified, never rewritten
- Name: Overloaded words stay qualified
- Order: 7
- Concepts: Naming, overloaded words; qualification; the glossary as arbiter

**A word that collides — with the world and inside Xmip — is not remedied by
inventing a new one. It is remedied by three things already the estate's habit:
always use the qualified form, let `docs/terminology.md` arbitrate which sense is
meant, and gate new unqualified uses with a ratchet test.** "Process" is the
first word this governs; the same three moves handle the next.

## Context

The owner, 2026-09-06: *the naming is settled; it is conflicting, as so many
words are in the world, not only within Xmip. Any suggestions on how to remedy
that?* The word in hand is "Process", which names three different things —
`docs/terminology.md` already separates them: an operating system's **System
Process**, the master **Xmip Service** and its worker **Xmip Host Service**
(each running as a **Host Process**), and an integration **Xmip Process** defined
in configuration. The glossary already bans the bare word and already carries the
senses. What it lacked was enforcement: nothing stopped a new record from writing
"Process" and leaving the reader to guess.

The remedy is deliberately not a new coinage. A unique word per concept breeds
jargon and does not scale to the next collision — "Message", "Party", "Contract"
all mean other things elsewhere too. Xmip's obligation is to be unambiguous in
its own texts, not to own a word globally.

## Decision

### 1. Qualify, always — never the bare word for a concept

Write "Xmip Process", "Host Process", "System Process"; write "Process" alone
only where the surrounding text makes the sense unmistakable, and prefer
"Process Definition" / "Process Instance" (the Definition/Instance axis) when it
does not. The generic operating-system sense stays lowercase, "process". The
estate already capitalises its domain terms (Stream, Message, Journey); this
extends that discipline to every collision.

### 2. `docs/terminology.md` is the arbiter

When two readings are possible, the glossary decides. Each sense of an overloaded
word has its own entry and its own qualified name there, and the "Process
terminology" section states the ban outright. A collision is resolved by pointing
at the record, not by debate.

### 3. A ratchet gates new unqualified uses

`tests/Terminology.Tests.ps1` freezes the count of bare, unqualified "Process"
across `docs/` at its present value and forbids growth — the same instrument as
the line-length ratchet in `Rust.Style.Tests.ps1`, pointed at prose. A lint
cannot judge whether a given historical use reads clearly, so the test does not
force the existing uses to be rewritten; it forbids a new one, and every edit to
an old record is the chance to qualify its uses and lower the ceiling. It counts
a use, not a mention: the word in quotes or code — as this record uses it
throughout — is discussion of the word, not a concept left ambiguous, and does
not count. The test also guards that the glossary keeps carrying the senses.

### 4. In code, the qualified form is the type name

`XmipProcess` (the `process` capability's trait) is **correct as it stands**: it
is the settled qualified term "Xmip Process", the disambiguator terminology
mandates — not a redundant `xmip` prefix. Renaming it to a bare `Process` would
break the rule this record sets, so it stays. This is the case ADR-0030's
"drop the internal prefix" does **not** reach: qualification wins over
prefix-dropping wherever the bare word is ambiguous.

`XmipModule` (the `abi` crate's Rust trait) is the opposite case. "Module" is not
overloaded — terminology names one sense — so ADR-0030 applies and the internal
Rust name drops the prefix to `Module`. The C ABI type in `xmip_module.h` and the
`Test-XmipModule` cmdlet keep the prefix: they are external. The crate already
documents this split (`abi/src/descriptor.rs`: the Rust side does not repeat the
prefix the header supplies); the trait was the one place it had not been applied.

## Consequences

- `tests/Terminology.Tests.ps1` joins the suite as the wording gate. The suite
  is the estate's memory; ambiguity of a settled word is now a remembered defect.
- The ceiling falls, never rises. Editing an old record to qualify its "Process"
  uses lowers it; the test then requires the lower number.
- The `abi` trait `XmipModule` becomes `Module`; `XmipProcess` is confirmed
  correct and stays. No other renames follow from this record.
- The three moves are reusable: the next overloaded word gets an entry in
  terminology.md and a row in the watchword list, nothing more.

## Provenance

The question is the owner's, 2026-09-06: the naming is settled and conflicting,
as words are; how to remedy that. The three moves, the confirmation that
`XmipProcess` is the correct qualified form, and the `XmipModule` → `Module`
resolution are the assistant's drafting of it, on the instruction to proceed and
to write the decision down.
