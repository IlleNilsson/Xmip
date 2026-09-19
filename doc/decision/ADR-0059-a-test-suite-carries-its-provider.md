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

## Amendment, 2026-09-19: a bare name is Xmip's own, and `-Suite` filters

Two rulings the same day, both the owner's, both against clauses drafted by
the assistant and quoted here as he wrote them.

On the name, having used the qualified form and disliked it: *"Got it, -Suite
is Playground, Not Core.Playground. My choice. That is fine but all
instructions has to be updated."*

On the filter: *"Filter the -Suite as the -Test parameter."*

**Clause 14. A name with no provider is the reserved provider's, and that is
the canonical spelling for Xmip's own two.** This **supersedes clause 1**,
which required the qualified form, and **supersedes clause 2**, which refused
a bare name at the door. `Playground` and `Estate` are how the estate spells
its own suites, and they are what every surface prints, records and documents:
the run record's `suite` field, `Get-XmipTestStatus`, `Get-XmipTestResult`,
`Get-XmipTestNode`, the `[run]` table, the refusals, tab completion and all
help text. A third party's stays qualified, because it must: `Acme.Playground`.

This is not the alternative this record rejected. *Accept a bare name and
expand it to `Core.<Name>`* was declined below as teaching the wrong shape;
what is decided here is stronger and is ADR-0011's own clause applied rather
than bent — *`core` is reserved and means Xmip itself*. A name with no
provider is therefore not a name missing a slot; it is the reserved
provider's, exactly as a one-token module name already means platform level
in ADR-0011. The slot `Acme.Playground` needs was never the bare word's to
occupy: `Acme` is not `core`, and nothing a bare name means is available to
anyone else.

**Clause 15. The qualified form is still accepted, and that is the owner's to
strike.** `Core.Playground` resolves to the Playground and `Core.Estate` to
the estate, because that is literally what a bare name means and because every
instruction written before this amendment spells it that way. The owner wrote
*"Not Core.Playground"*, which can be read as a refusal rather than a
preference; it was not read that way, and refusing it outright is a one-line
change to `Get-XmipNamedTestSuite`. **This clause is his to strike.**

**Clause 16. `-Suite` takes wildcards, as `-Test` does.** This **supersedes
clause 7's `-Suite` stays exact**, and with it the argument that a wildcard
suite would leave *which provider did I just run* unanswerable. That argument
was the assistant's, named in the Provenance below as his to strike, and he
struck it. It is safe to strike because a run records its own resolved suite —
the run record beside the snapshot, and `Get-XmipTestStatus` reading it back —
so *which did I run* is answered per run and never needed to be answered per
command. Wildcards, never regular expressions: clause 8 stands unchanged.

`-Suite *` is every suite this estate knows, `-Suite *Play*` is the
Playground, and a literal name holds no wildcard character and selects exactly
one suite, so nothing an operator typed before this means anything else now. A
pattern that matches nothing is REFUSED before anything starts, naming what
was given and the suites there are — the same words as a name nobody
provides, since a name that names none and a pattern that matches none are
one fault (ADR-0055 clause 2).

**Clause 17. Several suites matched run one after another, and one that will
not start does not stop the rest.** They run in the order `Get-XmipTestSuite`
lists them, Xmip's own first. Each returns what it returns — the Playground a
detached roll that comes back at once, the estate a Pester run that blocks, a
provider's whatever its command gives — so a group run emits the same objects
a caller would get from running each by hand, in order, and reads them by
type. What is about to run is said in one line before anything starts, and
what did not start is said by name at the end, in the estate's words: this is
the only report of a group run, because the objects cannot be one. A suite
that refuses is named and the rest carry on, which is the rule a malformed
declaration already follows in the Consequences below — what another provider
wrote may never stop Xmip's own tests.

**Clause 18. A switch that belongs to one suite alone is not a fault when a
pattern chose the group.** `-Stress` on `-Suite Estate` is still REFUSED: an
operator who named one suite and gave it another's switch meant something
else. `-Suite * -Cluster Z3` is not that mistake — it is a roll on Z3 with the
estate's files beside it — so the Playground's own parameters are dropped for
the Pester suite rather than refused. A provider's command keeps everything it
was given, since only the provider knows what its command takes.

**Clause 19. `-Suite` still defaults to `Playground`.** An omitted `-Suite`
could be read as `*` under clause 9 — an omitted selector means the most the
rig can give — and it is not. Clause 9's rule is about what one run brings;
`-Suite` chooses which rig runs at all, and a bare `Start-XmipTest` has never
meant *and also run the estate's Pester gate*. The owner's words at clause 9
named `-Stress` and `-Nodes` and nothing else. **If he wants the default to be
`*`, this is the clause to strike.**

**Clause 20. The shape of a suite name is checked in the body, not at the
parameter, and this qualifies ADR-0055 clause 1.** The door is the parameter
where the parameter can say the whole refusal; a `ValidatePattern` cannot,
because PowerShell wraps it — the operator reads *Cannot validate argument on
parameter 'Suite'* first and the estate's words second, which reads as the
framework complaining rather than Xmip refusing (the owner, 2026-09-19). The
estate says its outcomes in its own words, so the words must be ours alone.
Nothing is lost: `Get-XmipTestSuiteRefusal` is the first thing the cmdlet
does, it is pure, and it starts nothing — which is what ADR-0055 clause 1
protects. Clause 16 then made the check redundant as a shape check and it is
gone: with a filter, an unmatched pattern and a misspelled name are the same
refusal, and there is one voice rather than two.

**What this amendment overtakes in the Consequences below.** Two bullets there
state clauses 1 and 2 as consequences and are no longer true of the estate:
*`Start-XmipTest -Suite Playground` is refused where it used to run* — it runs,
and it is the spelling — and *the run record carries `suite =
"Core.Playground"`* — it carries `suite = "Playground"`, and a record written
before today is read back as `Playground` all the same, so a roll started this
morning reports the one spelling this afternoon. The bullets stay as what was
decided that day; this is what supersedes them.

## Amendment, 2026-09-19: an omitted selector means the most the rig can give

The owner, the same day, on the two switches nobody types: *"Omitted -Stress,
Omitted -Nodes means bring it all."* Asked whether an omitted `-Stress` should
run every level in turn or the hardest one, he chose **the hardest level**.

**Clause 9. An omitted selector on `Start-XmipTest` means the most the rig can
give, not a cautious default.** `-Stress` omitted is `Brutal`, where it was
`Realistic`. `-Nodes` omitted is the level's full complement. Naming either
still pins it, so `-Stress Calm` is calm and `-Nodes @()` is no nodes.

**Clause 10. Maximum, not each in turn — and that is where this differs from
`-Test`.** Clause 6 says naming no test runs *every* test, because the tests
are a set and running all of them is one run of the suite. The levels are not
a set to be covered; they are an ordering of the same run, and a roll at all
four in turn would be four rolls, each weaker than the last, saying nothing
the hardest one does not say. So an omitted `-Test` means *every*, an omitted
`-Stress` means *hardest*, and both are one rule: the most the rig can give of
the thing that switch selects.

**Clause 11. The full complement is composed, not incidental.** The level's
own count of nodes was already what an omitted `-Nodes` produced at `harsh`
and `brutal` — but as nodes that declared nothing, so `RoundTrip` ran whole in
the roll and the message path between the node processes, the thing the nodes
exist for, never ran. The complement is now dealt: the level's nodes,
`node-01` up, taking receive, process and send in message-path order and round
again, so every stage is covered and no two counts differ by more than one
(`test/playground/src/complement.rs`). A count and a deal, not a count. And at
every level, not only the two hard ones: `-Stress Calm` with no `-Nodes` now
brings calm's own one node where it brought none.

**Clause 12. A level too small for the path declares nothing, and says so.**
Below three nodes the deal cannot cover three stages, and a roster with two of
the three declared is refused by `Roster::refusal` — an omitted `-Nodes` that
composed a roster which then refused itself would be no answer at all. Below
three, every node of the complement declares no stage: each runs whole tests
itself, as a node that declares nothing always has, the roll runs `RoundTrip`
whole, and `Start-XmipTest` warns in words, naming the count and
`-Nodes R1, P1, S1` as what would split the path. ADR-0055 clause 5 allows
exactly this: carrying on is right, it is not what the operator probably
meant, so it is said rather than left to be noticed.

**Clause 13. The rig owns the count; the door owns the record.** How many
nodes a level brings is scaled to the machine's headroom, and only the rig
measures that, so `Start-XmipTest` asks it — `xmip-playground-roll --roster
<level>` prints the complement and starts nothing — and then hands those names
back to the roll. One composition, in one place, and the run record can carry
the nodes an operator never typed. Both readings of a run now say what it was:
the record beside the snapshot and the `[run]` table inside it, and the roll's
first log line names the level and the roster it resolved to.

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
- **What the amendment changed, and what it left.** `Start-XmipTest -Cluster
  C1` with nothing else now rolls at `brutal` over the brutal complement,
  where it rolled at `realistic` over none. `Start-XmipTestNode -Stress` keeps
  `Calm`: its `-Nodes` is mandatory, so nothing there is omitted and there is
  no selector to read as *bring it all* — the owner's words were about the two
  switches of `Start-XmipTest`. If he wants one default for both, this is the
  clause to strike.
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

The amendment's rule is the owner's too, 2026-09-19, quoted at its head, and
so is the choice between the hardest level and every level in turn: he was
asked, and answered *the hardest*. Clauses 11 to 13 — that the complement is
dealt over the message path rather than merely counted, that a level too
small for the path declares nothing and is warned about rather than refused,
and that the count is asked of the rig so the door can record it — are the
assistant's drafting. Clause 12 is the one to read twice: refusing outright
was the alternative, and it was declined because it would refuse every
`-Stress Calm` run, calm's own count being one.

The second amendment's two rulings are the owner's, 2026-09-19, quoted at its
head: the bare name and the filter on `-Suite`. Both overrule clauses this
record's own Provenance had already marked as the assistant's — clause 7's
*`-Suite` stays exact* was his reasoning, and it is now superseded by clause
16. Clauses 17 and 18, which say what several suites matched do and which
switches survive a group run, and clause 20, which records where the shape
check lives and why, are the assistant's drafting. Clause 15 — that
`Core.Playground` is still accepted — and clause 19 — that the default stays
`Playground` — are named there as the owner's to strike, and are the two
things to read first.
