# ADR-0073: Languages beyond American English are an opportunity

- Status: Proposed
- Date: 2026-11-12
- Related: ADR-0014 (the operator surfaces), ADR-0052 (the operator surfaces
  share one model), ADR-0062 (every Xmip tool audits), ADR-0021 (current
  platforms only)

## In brief

- Theme: Operating Xmip
- Subject: Whether Xmip speaks languages other than American English, and what it would take
- Name: Languages beyond American English are an opportunity
- Order: 23
- Concepts: globalization; localization; language; translation; American English; message catalog

**Xmip speaks American English on every surface, and nothing else is
planned for now. Supporting other languages — Chinese, the European
languages and the rest — is recorded as an opportunity, with what it would
take, so it can be taken up when a customer asks for it. Nothing is decided
or built.**

## Context

The owner, 2026-11-12: *We have not thought about globalization. I'm fine
with US English. How hard would it be to support all other Chinese, European
and what not languages. An estimate, do not do it.* And, given the estimate
below: *That is too much for now, just store it as an opportunity, ADR for
now.*

Every word a person reads is written in English where it is shown, measured
the same day: about 340 strings in 56 Razor views, 169 refusal and failure
texts in Rust beside the kinds' names and meanings in some 40 Rust files,
26,000 characters of command-line usage, and the PowerShell help and
formats. Many refusals are composed from English fragments.

## What it would take

1. **One catalog, in the runtime.** Every word a person reads comes from one
   message catalog in Rust — Project Fluent for whole sentences and plurals,
   ICU4X for dates, numbers and durations — exported through the ABI, so the
   command line, PowerShell and the GUI, Web and Desktop, read the same
   words (code placed once). The VS Code extension localizes the few words
   of its own the way VS Code does.
2. **Sentences, not fragments.** A refusal composed from English pieces
   becomes one message with placeholders, as a translator needs it. The
   riskiest part.
3. **Room on screen.** German and Finnish run 30 to 40 percent longer than
   English: the bar, the grid columns and the Topology's labels. Chinese,
   Japanese and Korean need font fallback and their own line breaking.
4. **Right to left**, only if Arabic or Hebrew is wanted: CSS logical
   properties, mirrored icons, a mirrored Topology and BPMN drawing.
5. **Guards.** A pseudo-language test — accented, 40 percent longer — that
   finds a word written outside the catalog, and a test that every message
   exists in every language, English where one is missing.
6. **Each language.** Some 2,000 to 3,000 strings and the help pages,
   machine-translated and reviewed by a native speaker against a glossary
   of Xmip's terms (Receive Location, Send Port, Work Process), with every
   release after.

**What stays English:** command and cmdlet names, TOML keys, the audit,
logs and the decision records — read by machines and by support. Stored
invariant, shown in the reader's language.

## Estimate (2026-11-12)

| Piece | Estimate |
| --- | --- |
| 1 and 2, the catalog and whole sentences | 4 to 6 working days by the assistant with workers, reviews and landings; about 6 to 10 developer-weeks by hand |
| 3, room on screen | 1 to 2 days |
| 4, right to left | 2 to 3 days, only if wanted |
| 5, guards | 1 day |
| 6, each language | 2 to 4 reviewer-days per language, again with each release |

## Why it waits

The owner's: too much for now; American English is enough. The cost of
waiting: every word written meanwhile is one more to move into the
catalog, so pieces 1, 2 and 5 cost more the later they are done. The
assistant recommended doing those three before general availability with
English the only language; the owner chose to record it instead.

## Provenance

The question and the decision to wait are the owner's, 2026-11-12, quoted
above. The design sketch, the measurements and the estimate are the
assistant's, the same day, and are a starting point, not a decision.
