# ADR-0059: A test suite carries its provider

- Status: Proposed
- Date: 2026-09-19
- Related: ADR-0011 (module and repository naming), ADR-0055 (bad input is
  refused at the door), ADR-0028 (the Playground), ADR-0014 (the operator
  surfaces), ADR-0052 (the operator surfaces share one model), ADR-0031
  (configuration is TOML)

## In brief

- Theme: Operating Xmip
- Subject: What a test suite is called, who may add one, what it means to
  run one without naming tests, and how a filter selects among them
- Name: A test suite carries its provider
- Order: 15
- Concepts: qualified suite name; suite declaration; the whole suite;
  wildcard on a filter

**A test suite is named `<Provider>.<Name>`, the same rule that names every
module (ADR-0011), and the provider is required: `Core.Playground`, never
`Playground`. `core` is Xmip itself; anyone else names themselves, and adds
a suite by declaring it rather than by editing Xmip. Naming no test runs
the whole suite, for every suite and every provider.**

## Context

The owner, 2026-09-19: *what we need is this CmdLet to be wider:
`Start-XmipTest -Suite Playground` to need `Start-XmipTest -Suite
Core.Playground` to make room for `Start-XmipTest -Suite <ACME>.Playground`.*

And, the same day, on what a run with no `-Test` means:
*`Start-XmipTest -Suite 'WhatEver'` with excluded parameter `-Test`, means
run all test in the test suite.*

And, the same day, on selecting a group: *another PowerShell, Filter
property. use wild characters or regexp for parameters. For instance
`-Test *`, or `.*`*

`-Suite` was a `ValidateSet` of two bare words, `Playground` and `Estate`.
Read against ADR-0011 that is the one shape the estate does not allow: a
name with no provider slot cannot say who stands behind the thing it names,
and a second implementation has nowhere to live. The same argument that gave
`xmip-acme-contract-json-schema` its place gives `Acme.Playground` its place,
and a bare `Playground` denies it.

The two core suites also already ran whole when no test was named, but by
two unrelated accidents: `Core.Playground` leaves
`XMIP_PLAYGROUND_SCENARIOS` unset and the roll reads unset as every
scenario, while `Core.Estate` hands an empty `-Test` to Pester, which runs
every file when none is named. Two behaviors that happen to agree are not a
rule, and a third party's suite would have inherited neither.

## Decision

1. **A suite is `<Provider>.<Name>`, and the qualified form is required.**
   `Core.Playground` and `Core.Estate` are Xmip's. `core` is reserved and
   means Xmip itself, exactly as in ADR-0011's clause table. Comparison is
   case-insensitive — `core.playground` is accepted — and the canonical
   spelling, in run records and on every surface, is `Core.Playground`.

2. **A bare name is REFUSED at the door.** The shape is a
   `ValidatePattern` on the parameter, which is ADR-0055 clause 1: the door
   is the parameter, not the body. The refusal names what was given and what
   would be right — *REFUSED. A suite is `<Provider>.<Name>`: 'Playground'
   names no provider. Did you mean Core.Playground?*

3. **Which suites exist is checked in the body, because it cannot be
   declared.** A `ValidateSet` cannot know a third party's suite, so the set
   is read and the name refused before anything is built or spawned, naming
   the suites there are (ADR-0055 clause 2). Tab completion offers the known
   suites, so the common case cannot be typed wrong (clause 4).

4. **A provider declares a suite; it does not edit Xmip.** A declaration is
   a TOML file under `test/suite`, one per suite, saying three things:

   ```toml
   provider = "Acme"
   name     = "Playground"
   command  = "Start-AcmeXmipTest"
   ```

   `Start-XmipTest` hands that command everything it was given beside
   `-Suite`. The command is the provider's own, from the provider's
   PowerShell surface module — `xmip-acme-powershell` in ADR-0011's terms —
   so Xmip runs nothing of its own for a suite it did not write. A
   declaration that omits any of the three, that spells provider or name as
   something other than a name, that claims the reserved provider `core`, or
   that names a command this session does not have, is REFUSED by name and
   never quietly skipped.

5. **No new cmdlet.** A suite is a value of `-Suite`, never a noun of its
   own: the owner's standing preference is as few cmdlets as possible, and a
   new act on a known noun is a parameter. `Get-XmipTestSuite` exists inside
   the module and is deliberately not exported; what an operator needs from
   it — which suites there are — reaches them through tab completion and
   through the refusal.

6. **Naming no test runs the whole suite.** For every suite and every
   provider. One predicate, `Test-XmipWholeSuite`, is where that is decided,
   and all three branches ask it: the Playground's environment, the estate's
   Pester configuration, and the forwarding to a provider's command, which
   passes `-Test` on only when tests were named.

7. **A filter takes wildcards; a name does not.** A parameter that selects
   among things that already exist declares `[SupportsWildcards()]` and
   matches with `-like`: `-Test`, `-Node`, `-Name`, `-Cluster` where a
   cluster is being found rather than started. `-Test *` is every test and
   says exactly what omitting `-Test` says. A pattern that matches nothing
   is REFUSED where something was about to start, naming the pattern and
   what there is; a `Get-` returns nothing, which is an answer.

   A parameter that names what to create takes no wildcard: `-Nodes` and
   `-Cluster` on `Start-XmipTest` name processes to spawn, and a pattern
   there means nothing.

   **`-Suite` stays exact.** A wildcard suite would leave *which provider
   did I just run* unanswerable, and the qualified name exists precisely so
   that question has one answer. Tab completion still offers the literal
   names; a wildcard is for asking for a group, never for choosing a suite.

8. **Wildcards, not regular expressions.** The estate had already chosen
   once — `Get-XmipTestNode -Name` has been `[SupportsWildcards()]` matched
   with `-like` — and `[SupportsWildcards()]` is PowerShell's own
   convention, so `Get-Help` announces it without anyone writing prose. Two
   syntaxes for one job would also disagree about a dot: `Rust.Style` is a
   real test of `Core.Estate`, and as a regular expression it matches
   `RustXStyle` too, while as a wildcard it is the name the operator typed.

## Consequences

- `Start-XmipTest -Suite Playground` is refused where it used to run. That
  is the instruction: the slot it left empty is where `Acme.Playground`
  goes. `-Suite` still defaults to `Core.Playground`, so every command that
  never said `-Suite` is unaffected.
- The suite travels. The run record carries `suite = "Core.Playground"`, and
  `Get-XmipTestStatus` reports what the run was started with rather than a
  constant. `Get-XmipTestResult` and `Get-XmipTestNode` read a snapshot and
  a process, which only a roll writes, so they say `Core.Playground` from
  one spelling held in one place.
- **The surfaces, asked one at a time (ADR-0014, amendment 2026-09-19).**
  The PowerShell module is where a suite is named and is changed throughout.
  The API and the CLI owe nothing: neither has a notion of a test suite —
  the CLI reads a snapshot and never starts a run — and the only mention is
  a comment in `xmip.cli.toml` naming the command that produced the shipped
  snapshot, which is corrected. The web GUI owes nothing for the same
  reason: it follows a snapshot and shows scopes, and no page of it names a
  suite. If a surface ever shows a run, it shows the qualified name.
- **Where the wildcards landed.** `Start-XmipTest -Test` and
  `Get-XmipTestResult -Test` gained them; `Get-XmipTestResult -Node` and
  `Get-XmipTestNode -Name` already had them. `Get-XmipTestStatus` and
  `Stop-XmipTest` had no filter parameter at all and gained `-Cluster`,
  which is how an operator names a run that exists; `Get-XmipProcess`
  gained `-Name`. `Get-XmipProcess -Purpose` stays a two-value
  `ValidateSet`, because an offered set beats a pattern where the set is
  closed (ADR-0055 clause 4). Nothing here is a new cmdlet.
- **A malformed declaration is that provider's alone.** It was written to
  refuse outright, and because every declaration is read before a suite is
  chosen, one third party's typo refused `Core.Estate` and stopped the
  estate's own gate. That is too much: nothing another provider writes may
  break Xmip's own tests, and the estate must be able to run its gate on a
  machine it does not control the contents of. So a declaration that does
  not hold is **warned about by name and is absent** — asking for it refuses
  with the same words as a suite nobody declared, and the other suites are
  untouched. ADR-0055 clause 5 forbids silence, not judgement; a warning
  naming the file and the fault is not silence. Corrected the same day it
  was written, before landing.
- ADR-0055's consequence note that ``-Suite`` is a set is superseded by
  clauses 2 and 3 here; the parameter is a pattern with a completer, which
  is the same ruling applied to a set that is open.
- **Not built.** `test/suite` is a directory in this repository, which is
  the right home for a suite declared by a provider whose module is mounted
  here, and the wrong one for an installed estate that has no clone. When
  the manifest or an installed-module layout answers where a provider's
  files live, the declaration moves there and this clause is what says it
  may. Nothing in the estate ships a declaration today, so the mechanism is
  proven by a fixture and by the refusals, not by a second provider.
- **Not decided here.** Whether a provider may declare more than one suite
  in one file, whether a declaration may name a script rather than a
  command, and how a suite's own tests are offered to `-Test` tab
  completion, which today knows only the Playground's seven and the
  estate's files.

## Alternatives considered

**Keep the bare names and add providers later.** It is one fewer change
today and it keeps `Playground` meaning Xmip's, which is exactly the claim
ADR-0011 refuses to let any name make implicitly. The estate has had the
argument once, over module names, and the second implementation is the one
that pays.

**Accept a bare name and expand it to `Core.<Name>`.** Convenient, and it
teaches the wrong shape: an operator who types `Playground` for a year
learns that a suite has no provider, and the day Acme ships one, a habit has
to be unlearned. The owner said the qualified form should be *needed*.

**A `ValidateSet` rebuilt at import from the declarations.** The set would
be right for a session that started after the declaration was dropped and
wrong for one that started before, and nothing would say which. A pattern at
the door and a refusal in the body are right in both.

**A registry in `architecture.toml`.** ADR-0011 says the manifest is the
registry and the only place that will know a third-party module exists, so
this is the candidate with the best record behind it. It is not taken yet
because the manifest names repositories and a suite is not one, and because
a declaration a provider drops beside its own files needs no write to a file
the whole estate shares. The door is left open above.

**A new cmdlet, `Register-XmipTestSuite` or `Get-XmipTestSuite`.** Two more
commands for something an operator reads once. The owner's rule is as few
cmdlets as possible.

**Regular expressions on the filters, or both syntaxes side by side.** More
expressive, and two ways to say one thing whose answers differ: `Rust.Style`
selects one test under a wildcard and two under a regular expression, and
nothing on the command line says which was meant. Neither does a second
syntax pay for itself on lists of seven tests and a handful of clusters.

## Provenance

All three requirements are the owner's, 2026-09-19, quoted in the Context:
the qualified suite name with room for `<ACME>.Playground`, that excluding
`-Test` runs the whole suite, and wild characters on a filter parameter. He
offered wildcards or regular expressions and the choice between them is the
assistant's, with the estate's own precedent and the dot in `Rust.Style` as
the reason; it is clause 8 and the first thing to strike if he meant
otherwise. The eight clauses, the declaration file's shape, the choice of
`test/suite` over the manifest, and the reading of ADR-0011 and ADR-0055
into them are the assistant's drafting, and the record is Proposed rather
than Accepted until the owner says so.
