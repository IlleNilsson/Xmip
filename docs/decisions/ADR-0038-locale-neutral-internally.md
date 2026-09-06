# ADR-0038: Locale-neutral internally; globalization at the data boundary only

- Status: Accepted
- Date: 2026-09-06
- Related: ADR-0021 (current platforms), ADR-0031 (configuration is TOML),
  docs/architecture/market-position.md

## In brief

- Theme: The shape of the estate
- Subject: Xmip has no product i18n; globalization lives only where it parses data
- Name: Locale-neutral internally
- Order: 10
- Concepts: Globalization, scope; locale-neutral; the data boundary

**Xmip is an integration platform, not an end-user application, so it carries no
product internationalisation — no translated UI, no localised messages. English
throughout code, logs, health, documentation and scope URIs. Globalization
matters only at the data boundary, where Xmip parses or formats a partner's data,
and there the locale is the partner's declared convention, never the server's.**

## Context

The owner, 2026-09-06: *I conform to English. Does Xmip need globalization apart
from time, calendars and formatting of data? I think that is enough.* It is. An
integration platform's users are systems and the operators who run it, not a
consumer audience, so the cost of an i18n framework, resource bundles and a
translation process buys nothing. What it must get right is the data it moves
between systems that disagree about how data is written — and getting that wrong
corrupts values silently, which is worse than any missing translation.

## Decision

### 1. Invariant everywhere internal

Code, configuration, logs, health evidence, documentation and scope URIs are
English and locale-neutral. Machine-read text is formatted with the invariant
culture, so a document means the same on every host — `NodeConfiguration` writes
with `InvariantCulture` precisely so a German-locale machine does not write
`1,5` where the parser expects `1.5`. This is the safe default and the one that
prevents the classic locale bug.

### 2. Locale-aware only at the data boundary

Three concerns, and only these, are locale-aware, at the edge where Xmip reads or
writes a partner's data:

- **Time and calendars** — time zones, daylight saving, and the ambiguity of a
  date like `01/02/2026`; the substrate for scheduling, retention windows and
  timestamps.
- **Number and data formatting** — decimal separators, digit grouping, currency;
  because integration moves values between systems that format them differently.
- **Character encoding** — UTF-8, Latin-1, EBCDIC off a mainframe EDI feed; part
  of reading a partner's bytes as text.

In each, the locale is a property of the **partner or the contract**, declared in
configuration, not inherited from the host the node runs on.

### 3. No i18n framework

There is no localisation of Xmip's own surfaces and no resource-bundle
machinery. If a future deployment needs an operator UI in another language, that
is a decision for then; nothing here builds toward it, and nothing should.

## Consequences

- A whole category of work is bounded out: no translation pipeline, no locale
  resource files, no per-culture UI.
- Data-boundary correctness (time, number, encoding per declared convention) is
  in scope for the transport and contract capabilities, and is where locale code
  is allowed to live.
- Internal formatting stays invariant; a reviewer treats a non-invariant format
  call outside the data boundary as a defect.

## Provenance

The position is the owner's, 2026-09-06: English internally, globalization only
for time, calendars and data formatting. The invariant-internal / locale-at-the-
boundary framing and the encoding addition are the assistant's drafting of it, on
the instruction to write it down.
