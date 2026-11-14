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

## Amendment, 2026-09-27: the guards are the surface, and read one failure

The first consequence is amended. `ResiliencePolicy`, `ResilienceExecutor`
and `ResilienceClassifier` had no caller: the guards are built by the
technologies' own constructors, `execute` is what runs in-process, and
whether a failure may be retried is the failure's own property. They are
deleted, with `RetryPolicy`, `TimeoutPolicy` and the `from_policy`
constructors that were their only readers. What an attempt failed with is
`xcore::Failure`, the one retryable failure (ADR-0037, amendment
2026-09-27); `resilience` keeps `Guard`, `Attempt`, `Decision`, `Guarded`
and `execute`.

## Provenance

The sentence and the trait are the assistant's, 2026-09-10, under the owner's
instruction to sort everything declared and not built. Nothing was put to the
owner as a question because the record — problem 9 — had already said what
was missing.

## Amendment, 2026-10-06: Polly is the goal, on the send artifacts only

The owner, 2026-10-06, asked how Xmip's resilience stands against the Polly
open-source project as its goal, and, shown that Xmip has the basic form of
five of Polly's strategies, no hedging, no pipeline builder, no telemetry
and no chaos strategies, used only by three transports: *We only need Send
Port Group, Send Port and Send Location to utilize 'polly'-resilience. The
rest is internal Rust matters.*

- **Polly is the goal for what an operator configures**, and the place it is
  configured is the send side alone: a Send Port Group, a Send Port and a
  Send Location each name the guards — retry, timeout, circuit breaker,
  fallback, rate limiting, concurrency limit, hedging — and their settings
  in `cluster.xmip`, and every send through them goes through that pipeline.
- **Everywhere else, resilience is the code's own business**: a transport,
  a Receive Location or Xmip Storage handles its failures inside Rust as its
  technology needs, with nothing to configure.
- Not built: the send artifacts' pipeline, a timeout that interrupts the
  attempt, telemetry, and Polly's missing options. The order and the keys
  are to be proposed.

## Amendment, 2026-10-06: answered, confirmed and unconfirmed sends

The owner, 2026-10-06: *we have to think about non Request-Response
protocols like FILE, (S)FTP(S) and broadcast*; and, on the design the
assistant then drew: *do your best over Request-Response protocols and non
Request-Response protocols whatever we wanna call them.* The names and the
table are the assistant's.

- **Each transport declares how its send completes** — a capability it
  declares, never read from its name:
  - **answered** — the far end answers, and the answer is success or
    failure (HTTP, AS2, SOAP, gRPC);
  - **confirmed write** — no one answers; success is the whole Stream in
    place under its final name, written under a temporary name and moved to
    it in one step, so a partial write is never seen as delivered (FILE,
    FTP, FTPS, SFTP, SMB, object stores);
  - **unconfirmed** — no one answers and no one confirms; Xmip knows only
    that it left the node (UDP broadcast and multicast, syslog over UDP).
- **A guard means what the kind lets it mean:**

  | guard | answered | confirmed write | unconfirmed |
  |---|---|---|---|
  | retry | yes | yes — a failed try leaves at most its temporary name, overwritten by the next; the Journey's identifier in the name where the target allows, so a retry never makes a second copy | a local failure only; a lost datagram is never known |
  | timeout | yes, interrupting | yes, interrupting the transfer and removing its temporary file | the local send only |
  | circuit breaker | yes | yes — a share, server or directory gone | no: nothing reports a failure |
  | fallback | yes | yes | yes |
  | rate limit, concurrency limit | yes | yes | yes, above all |
  | hedging | only where the far end deduplicates | refused: two files | refused: two datagrams |

- **Configuration refuses what cannot be honored**: `cluster.xmip` naming a
  guard a Send Location's transport cannot honor is refused at start, in
  words naming the guard, the kind and why. An unconfirmed send is said to
  be at most once (`runtime-model.md` section 15).
- Not built.

## Amendment, 2026-11-08: every guard applies, in its order

Section 2 said every guard is asked before and after every attempt, and
`execute` did not: the first guard that did not say proceed ended the
asking. A bulkhead behind a retry that asked for another try never freed its
slot and refused the next attempt; a circuit breaker there never counted the
failure; a bulkhead behind a rate limit's wait was never asked before the
attempt and freed a slot it had not taken (the deep review, group 2).

- **After an attempt every guard is asked, in order, whatever the ones
  before it said**, and the first that does not say proceed decides, as
  section 2 has it.
- **Before an attempt every guard is asked, in order, until one refuses or
  falls back**: that one decides, and no guard after it is admitted to an
  attempt that will not happen. Otherwise the attempt goes after the
  longest wait any guard asked for: a wait is a guard's condition for the
  attempt, so a refusal behind it still refuses and each guard's wait is
  kept.
- Open: a guard admitted before a later one refused — a bulkhead's slot, a
  half-open circuit breaker's trial — is not told that the attempt will not
  happen, so it keeps what it took. Telling it is a method on `Guard`, a
  change to the trait, and waits on the owner.

## Amendment, 2026-11-14: a Send Port's retry is the retry guard

A Send Port's `retry = { attempts, backoff }` was a second retry rule beside
the retry technology: the runtime's send step counted the tries on the
active Send Location and read the backoff itself, and only the Event
forwarder asked a guard (the placement audit of 2026-11-13; the owner, that
day: *Do we have all code in the modules, repos that we should. This is a
refactoring statement*, and *Good that you found it, fix it*).

- **The retry guard decides whether and when a send is tried again.** As a
  node starts, each Send Port whose design states `retry` is given the retry
  guard, built for `attempts` tries after the first and `backoff` between
  them, flat. After each try that did not send, the send step asks the
  Port's guards as `execute` asks them after an attempt, in order, the first
  that does not say proceed deciding (`resilience::judged`, public since
  this date): a wait is how long the Message waits before its active Send
  Location is tried again; anything else lets the try stand, and the Port
  fails over where it says `failover = "next"`, or the Message is Failed. A
  try that never reached the transport — not permitted, or with nowhere to
  go — is a permanent failure, judged the same way.
- **No thread waits between tries.** `execute` sleeps between attempts; the
  send step does not, since a retry waiting for its backoff holds no
  thread, no claim and no place (`runtime-model.md` section 10). It asks
  after a try and not before one: no guard a Send Port is given judges
  before an attempt yet.
- **The due time is `xmip-core-schedule`'s to keep** (ADR-0058, amendment
  2026-11-13): the guard's wait goes into the hand-on as the Message's due
  time in Xmip Storage, and the node wakes for its queue's earliest.
- **The runtime takes the guard from its program.** A platform service links
  no technology (`architecture.toml` [policy]), so the runtime depends on
  `xmip-core-resilience` for `Guard`, and the program starting a node hands
  in how the retry guard is built (`Linked::retry`). `xmip-service` links
  `xmip-core-resilience-retry` with its `resilience` feature, which every
  role that sends carries (`deploy/profile/role`). A Send Port stating
  `retry` on a node whose program linked no retry guard refuses the node as
  it starts, in words.
- **The configuration means what it meant**: the same tries, counted in the
  Journey's `attempts` across passes and restarts; the same flat backoff; a
  permanent failure never tried again; and a Send Port without `retry` tried
  once.

Built 2026-11-14 (`xmip-core-runtime`'s `sending` and `departure`; the
retry technology unchanged). Proved by the runtime's `sending` tests (the
guard a retrying Port is given, its tries and its backoff; none without
`retry`; the refusal where none is linked), `tests/ledger/send.rs` (tries
counted, the backoff kept as the due time, a retry tried again once due,
the count surviving a restart, and a Port with retry off failing a
retryable failure after one try), `tests/running` (the node refused) and
`tests/measured/due.rs` (a retry woken for within a millisecond of its due
time). The send artifacts' pipeline (the amendment of 2026-10-06) is
unchanged: decided, not built.
