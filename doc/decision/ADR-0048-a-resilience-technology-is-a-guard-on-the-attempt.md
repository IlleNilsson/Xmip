# ADR-0048: A resilience technology is a guard on the attempt

- Status: Accepted
- Date: 2026-09-10
- Related: ADR-0043 (Logic is the method), ADR-0044 (a technology shares
  through its capability), doc/planning/open-problems.md problem 9
  (`resilience` has no plugin surface) and problem 10

## In brief

- Theme: Modules and the boundary
- Subject: What the six resilience technologies are, and the trait they
  implement
- Name: A resilience technology is a guard on the attempt
- Order: 9
- Concepts: Guard; attempt; decision; fallback; resilience technology

**An operation is attempted. A guard is asked before each attempt whether it
may go, must wait, is refused, or is answered by the fallback instead; and
after each attempt whether the outcome stands, the attempt is repeated, or
the operation is given up. Retry, timeout, circuit breaker, rate limit,
bulkhead and fallback are six guards with those two questions each. The
platform runs the loop and asks the guards in order; a guard never runs the
operation and never sees its value, only whether it failed and how long it
took.**

## Context

`xmip-core-resilience` declared a policy with a field per pattern and an
executor trait generic over the operation, which no technology could
implement behind the module boundary and none did. Problem 9 recorded it:
*resilience has no plugin surface in practice, despite six declared
implementations.* The owner asked on 2026-09-10 for everything declared to be
sorted, and problem 10 says the trait comes first.

## Decision

### 1. The sentence

The one in brief. A guard judges; it does not act. That is what makes six
patterns one trait: each has an opinion before an attempt and after it, and
nothing else in common.

### 2. The trait

`Guard` has three methods, and every technology implements all three:

- `technology()` — the manifest leaf.
- `before(number)` — may attempt `number` go: proceed, wait this long first,
  refuse with a reason, or let the fallback answer.
- `after(&Attempt)` — does the outcome stand: proceed, attempt again after
  this long, refuse, or let the fallback answer. An `Attempt` is its number,
  how long it took, and its failure if it failed — with the failure's kind,
  retryable or not, which is the classification the capability already had.

`execute(guards, operation)` in the platform runs the loop: every guard is
asked before every attempt and after it, in the order given, and the first
that does not say proceed decides. What comes back is the operation's own
answer, the word *fallback*, the guard's refusal, or the last failure.

### 3. Six technologies, each its own repository

Mounted directly under `xmip-core-resilience`. `retry` counts attempts and
delays; `timeout` refuses an outcome that took too long; `circuit-breaker`
keeps a state and refuses while open; `rate-limit` waits for a token;
`bulkhead` refuses beyond its concurrency; `fallback` answers a failure. Each
is a value with its own settings, constructed from the policy the platform
already declares.

## Consequences

- `ResiliencePolicy` stays as the configuration the guards are built from;
  `ResilienceExecutor` stays for what runs in-process, and is not the module
  surface.
- Problem 9's sentence about the plugin surface is no longer true; the
  problem's question about the tier stays open.
- Problem 10's rule is honored: the trait landed before any repository.

## Provenance

The sentence and the trait are the assistant's, 2026-09-10, under the owner's
instruction to sort everything declared and not built. Nothing was put to the
owner as a question because the record — problem 9 — had already said what
was missing.
