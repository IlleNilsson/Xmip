# ADR-0030: Prefix external names, not internal ones

- Status: Accepted
- Date: 2026-09-05
- Related: ADR-0011 (module and repository naming)

## In brief

- Theme: The shape of the estate
- Subject: The `xmip` prefix belongs where a name meets the outside world
- Name: Prefix external names, not internal ones
- Order: 5
- Concepts: Naming, external versus internal; prefix external, not internal

**A name carries the `xmip`/`Xmip` prefix when, and only when, it is external —
when it lives in a namespace shared with the world and could collide there.
Internal names drop it: inside the estate it is known to be Xmip, so the prefix
is noise.** ADR-0011 fixed this for repositories and crates; this record states
the principle behind it and extends it to everything else that gets named.

## Context

The owner's ruling, 2026-09-05. The assistant, told a local runtime file did not
need the `xmip-` prefix, over-corrected and stripped it from an environment
variable too. An environment variable is external — it sits in the operating
system's shared namespace beside every other program's — so it keeps the prefix.
A file the estate writes for itself does not. *"There is a world outside of
Xmip."*

## Decision

### 1. External names are prefixed

A name is external when it enters a namespace Xmip does not own, where another
party's name could collide with it. These are prefixed:

- **Repositories and crates** — `xmip-core-*`, on GitHub and crates.io. ADR-0011.
- **Environment variables** — `XMIP_PLAYGROUND_SNAPSHOT`, in the OS environment.
- **Published commands** — `Get-XmipHistory`, in the operator's shell, where it
  would otherwise shadow or collide with a built-in (`Get-History`).
- Anything else presented to the outside: a service name registered with the OS,
  a well-known port's advertised name, a public URL scheme (`xmip:///`).

### 2. Internal names are not

A name is internal when it lives only within Xmip's own operation, read by Xmip
and no one else. These drop the prefix:

- **Local runtime files** the estate writes for itself — `playground-snapshot.toml`,
  `playground-history.toml`, the temp `playground` directory.
- Modules, types, functions and fields **within** a crate — a struct is not named
  `XmipSnapshot` inside `xmip-core-observe`; it is `Snapshot`.
- Internal configuration **sections and keys**, which sit under a context that
  already says Xmip.

### 3. The test is collision, not tidiness

Do not strip a prefix from an external name to look tidy, and do not add one to
an internal name for uniformity. Before naming a thing, ask one question: does
this name enter a namespace shared with the outside world? Yes, prefix it. No,
leave it bare.

## Consequences

- ADR-0011 is the specific case of this principle for repositories and crates;
  it stands unchanged and this record is the general statement beside it.
- New surfaces inherit the rule without a fresh decision: a future CLI verb is
  prefixed, a future local cache file is not.

## Provenance

The principle and its wording are the owner's, 2026-09-05: environment variables
and every external entity carry the prefix; internally we know it is Xmip.
Clauses 1 to 3 are the assistant's drafting of it, on the instruction to write it
down.
