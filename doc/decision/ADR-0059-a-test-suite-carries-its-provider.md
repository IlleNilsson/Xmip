# ADR-0059: A test suite carries its provider

- Status: Accepted
- Accepted: 2026-09-20, the owner, on being shown what each record named
  as his to strike. Nothing was struck.
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
module (ADR-0011): `Core.Playground` is the name, and it is what the estate
prints, records and documents. `core` is Xmip itself, so a bare `Playground`
is accepted as its shorthand and canonicalized; a third party names itself
and adds a suite by declaring it rather than by editing Xmip. Naming no test
runs the whole suite, for every suite and every provider.**

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
`xmip-<provider>-contract-json-schema` its place gives
`<Provider>.Playground` its place,
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
   provider = "Example"
   name     = "Playground"
   command  = "Start-ExampleXmipTest"
   ```

   `Start-XmipTest` hands that command everything it was given beside
   `-Suite`. The command is the provider's own, from the provider's
   PowerShell surface module — `xmip-<provider>-powershell` in ADR-0011's
   terms —
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
help text. A third party's stays qualified, because it must:
`<Provider>.<Name>`.

This is not the alternative this record rejected. *Accept a bare name and
expand it to `Core.<Name>`* was declined below as teaching the wrong shape;
what is decided here is stronger and is ADR-0011's own clause applied rather
than bent — *`core` is reserved and means Xmip itself*. A name with no
provider is therefore not a name missing a slot; it is the reserved
provider's, exactly as a one-token module name already means platform level
in ADR-0011. The slot `<Provider>.Playground` needs was never the bare word's
to occupy: a third party is not `core`, and nothing a bare name means is
available to
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

## Amendment, 2026-09-20: the qualified name is canonical, and no placeholder

Three rulings, all the owner's, all the same day, quoted here as he wrote them.
The first two are about the suite name and are opposite to one another; the
third is about the company the record had invented. This amendment says which
way the estate went, and says that it changed its mind rather than letting the
record read as though it always knew.

### The suite is `Core.Playground`

The morning, on having used the qualified form and disliked it — the ruling the
amendment of 2026-09-19 above carries: *"Got it, -Suite is Playground, Not
Core.Playground. My choice. That is fine but all instructions has to be
updated."*

The afternoon, on being told the suite was called `Playground`: *"Sort it, there
was a decision made. It's name is Core.Playground, to give place for third
parties."*

**Clause 21. The qualified form is canonical, and clauses 1 and 2 as this
record first wrote them are the rule again.** `Core.Playground` and
`Core.Estate` are what the estate prints, records and documents: the run
record's `suite` field, `Get-XmipTestStatus`, `Get-XmipTestResult`,
`Get-XmipTestNode`, the `[run]` table, every refusal, tab completion, all help
text, `README.md`, `CONTRIBUTING.md` and the governance documents. This
**supersedes clause 14** of the amendment above, which made the bare name
canonical. That amendment is not deleted and its ruling is not rewritten: it was
what he said in the morning, an agent made the whole estate say it, and by the
afternoon he had decided the other way. A record that quietly reverses itself is
worse than one that shows it changed its mind.

The reason he gave the second time is the reason clause 1 gave the first time —
*to give place for third parties* — which is why the second ruling wins rather
than merely being later. The morning's was a preference about typing; the
afternoon's is about the slot the name leaves for someone else, and that is what
this record exists to protect.

**Clause 22. A bare name is accepted and is canonicalized to the qualified one.
This is the assistant's reading of two opposite rulings, and it is the owner's
to strike.** He has now said *"Not Core.Playground"* once and *"It's name is
Core.Playground"* once. Read together, the thing both rulings agree on is that
`Core.Playground` must exist and must be spelled somewhere; they disagree only
about whether `Playground` is an error. It is not treated as one. `Playground`
and `core.playground` both resolve to `Core.Playground`, case never matters, and
what comes back is always the qualified spelling — so every command he typed
this morning still runs and every instruction the estate publishes is correct.
Refusing a bare name would break the former to satisfy the latter, and nothing
he wrote asked for that.

This **supersedes clause 2** of the record as first written, which refused a
bare name at the door, and it **replaces clause 15**, which said the same thing
with the canonical and the accepted the other way round. **If he wants a bare
name refused, this is the clause to strike**, and it is one condition in
`Get-XmipNamedTestSuite` — the `Provider -ieq 'Core'` arm that lets an unqualified
name reach the reserved provider's suites.

**Clause 23. A bare name reaches the reserved provider alone.** `Playground` is
shorthand for `Core.Playground` and never for a third party's suite of the same
name, even where Xmip declares none. That is what keeps the shorthand safe to
accept: it can only ever mean the one thing ADR-0011 already says a missing
provider means.

### The estate names no placeholder company

On the invented third party: *"third parties aka acme, as NOT in the
certification protocol ACME"*, and then: *"Let's dump acme as a word for third
party. Let's just use 3'rd party instead."*

**Clause 24. There is no placeholder company. A grammar slot says what a
fictional company only pretended to say.** `Acme` was this record's example
provider in thirty-nine places across the estate — `Acme.Playground`,
`xmip-acme-powershell`, `Start-AcmeXmipTest`, `xmip-acme-authenticate-scim`, and
ADR-0012's descriptor comment `"core", "saxon", "acme"`. The estate also uses
ACME for what RFC 8555 means by it: certificate provisioning from Let's Encrypt,
eleven times in ADR-0033 and six in ADR-0034. So the same four letters named the
protocol Xmip depends on and a company Xmip made up, and a reader had to know
which was which from context. The invented company goes; the protocol stays,
untouched, everywhere it appears.

What replaces it:

1. **In prose, a third party is called a third party.** *A third party declares
   a suite under `test/suite`.* No invented name appears in explanatory text
   anywhere in the estate.

2. **Where a grammar needs a slot, the metavariable the estate already uses.**
   `<provider>` and `<Provider>`: `xmip-<provider>-powershell`,
   `<Provider>.<Name>`. ADR-0011 already writes
   `xmip-<provider>-<module>-<standard>`, so this is the estate's own
   convention rather than a new one, and it says the true thing — the slot is a
   slot — where a company name only stood in for it.

3. **Where a runnable example or a test fixture needs a literal, one token:
   `Example`, lowercase `example` for a repository segment.** A suite
   declaration has to hold a string; a test asserting that a qualified name
   resolves has to name one. The token is `Example` because RFC 2606 reserves
   `example` for documentation precisely so that documentation can never
   collide with a real party — which is the exact fault `acme` had — and because
   it is plainly not a company, which is what was asked for. It collides with
   nothing: `xmip-example-*`, `Example.Playground` and `Start-ExampleXmipTest`
   appear nowhere else in the estate. One token across the whole estate, so a
   reader learns it once.

   `vendor` and `partner` were considered and both were rejected on collision
   with the estate's own vocabulary, not on taste. ADR-0011 uses *vendor* as a
   naming concept — *a vendor name in slot 3 is unremarkable* — so
   `xmip-vendor-contract-sql` would read as a dialect rather than a publisher,
   in the one record that governs the slot. *Partner* is a domain term of
   ADR-0019, `doc/terminology.md` and the runtime model, where it means a party
   Xmip exchanges messages with. **The choice of `Example` is the assistant's
   and is the owner's to change**; it is one token and a sweep.

4. **`saxon` stays.** It is a real XSLT vendor, named deliberately in ADR-0011
   as a real example of the provider slot in use. It was never a placeholder,
   and nothing here touches it.

5. **The ACME protocol stays, and so do his own words.** ADR-0033, ADR-0034,
   ADR-0045, ADR-0056, ADR-0019, `doc/architecture/runtime-model.md`,
   `README.md`'s walkthrough and the Playground's fault simulation all mean RFC
   8555 and are correct. The owner's quoted words keep his spelling wherever he
   wrote *acme*, including in the Context of this record, because a quote is
   what was said.

6. **This record's own earlier prose is swept in place, not annotated.** The
   Context, the original clause 4, the superseded amendment, the Consequences
   and the Alternatives all named `Acme` as the example provider; they now say
   `<Provider>` or *a third party*, and clause 4's declaration holds `Example`.
   Nothing they decided changed — the placeholder was never a decision, only an
   illustration of one — so annotating each would have buried the rule under its
   own footnotes. The rulings, the clauses and every word of his stay exactly
   where they were.

### What this amendment overtakes in the Consequences below

The first Consequences bullet says *`Start-XmipTest -Suite Playground` is
refused where it used to run*. It is not refused; clause 22 accepts it and
canonicalizes it. The second bullet — *the run record carries
`suite = "Core.Playground"`* — is true again, and so is the rest of that bullet
about `Get-XmipTestStatus`, `Get-XmipTestResult` and `Get-XmipTestNode` saying
`Core.Playground` from one spelling held in one place. The paragraph of the
amendment above headed *What this amendment overtakes in the Consequences below*
is therefore itself overtaken: a record written this morning with
`suite = "Playground"` is read back as `Core.Playground`, and one written before
that already said it.

### Where these two reached

The canonical spelling: `$script:XmipPlaygroundSuite` and
`$script:XmipEstateSuite` in `Xmip/Get-XmipTestSuite.ps1`, `New-XmipTestSuite`'s
canonical `Name`, `Get-XmipNamedTestSuite`, `Get-XmipTestSuiteRefusal`,
`Start-XmipTest`'s default, help, examples and tab completion,
`Get-XmipTestStatus`, `Get-XmipTestResult`, `Get-XmipTestNode`,
`Start-XmipOperationWeb`'s filter, `test/XmipTest.Test.ps1`, `README.md`,
`CONTRIBUTING.md`, `doc/governance/release-model.md` and
`doc/governance/powershell-style.md`.

The placeholder: ADR-0011 and ADR-0012, each with an amendment of its own
pointing here; ADR-0014's `xmip-<provider>-gui`; ADR-0057's
`xmip-<provider>-authenticate-scim`; `doc/architecture/repository-model.md`'s
tree; `module/foundation/core/src/mechanism.rs`; and the module and test files
above.

Two shipped documents were checked and needed nothing:
`module/operation/cli/src/Xmip.Cli/xmip.cli.toml` and
`module/operation/powershell/src/Xmip.PowerShell/xmip.powershell.toml` name the
Playground as the rig of ADR-0028 and no longer name a suite or the command that
produced their snapshot, which the Consequences above said they did.

**Not swept, and named here so it is a decision rather than an oversight.**
Several Rust test fixtures in mounted modules use *ACME* as a customer or tenant
name in sample data — a CSV row, an Avro string, a Pub/Sub project id, a claim
value — and `test/playground` uses it in a payload fixture. None of them is the
example *provider* this ruling is about, none of them is read by a person
looking for who publishes a module, and changing them would dirty modules for
nothing. **If he wants them gone too, that is one sweep and this clause is where
to say so.**

## Consequences

- `Start-XmipTest -Suite Playground` is refused where it used to run. That
  is the instruction: the slot it left empty is where `<Provider>.Playground`
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
learns that a suite has no provider, and the day a third party ships one, a
habit has
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

The third amendment's three rulings are the owner's, 2026-09-20, quoted at its
head: that the suite's name is `Core.Playground`, and that no invented company
stands for a third party. The first of those reverses his own ruling of the
morning, which is said in the open rather than smoothed over. Clause 22 — that a
bare name is accepted and canonicalized rather than refused — is the assistant's
reading of two opposite rulings and is named there as his to strike, and it is
the first thing to read. So is the choice of `Example` as the one literal
stand-in token in clause 24, with `vendor` and `partner` rejected on collision
with ADR-0011's and ADR-0019's own vocabulary; the reasoning is stated so he can
overrule it in one sweep. The `## In brief` block above still reads
*`Core.Playground`, never `Playground`*. The first half was right again; the
second contradicted clause 22, which accepts the bare form as the reserved
provider's shorthand. Corrected the same day, and the index regenerated with
it, so the estate's own concept listing no longer advertises a rule the
record does not hold.

## Amendment, 2026-09-21: Stop-XmipTest takes a test by name

The owner: *The CmdLet Stop-XmipTest is not complete. There is a parameter
set missing. Stop-XmipTest -Cluster <Cluster> -Test <Test>.*

It was worse than missing. `-Test` existed on `Stop-XmipTest` and was the
pipeline's parameter, typed as a run's status object, so
`Stop-XmipTest -Test RoundTrip` bound a test's name to a run and failed,
while `Start-XmipTest -Test RoundTrip` meant the test. One word had two
meanings on one noun.

1. **`-Test` names a test**, as on `Start-XmipTest` and
   `Get-XmipTestResult`: wildcards allowed, offered from what is running.
   The pipeline's object is `-InputObject`, PowerShell's own name for it;
   binding from `Get-XmipTestStatus` is unchanged.
2. **`-Cluster` and `-Test` pick together**, in one parameter set that is
   also the default: neither is every run, and a run started without
   `-Test` drives its whole suite and is matched by every test in it.
3. **A run is stopped whole.** A run is one process, so a test is stopped by
   stopping the run that drives it. A run that also drives a test not named
   is REFUSED, naming what else it runs, and the refusal comes before
   anything is stopped, so a refused command has done nothing (ADR-0055
   clauses 2, 3 and 5). `Start-XmipTest -Cluster C1 -Test RoundTrip` and
   `Stop-XmipTest -Cluster C1 -Test RoundTrip` are each other's inverse.
4. **A filter that matches nothing is refused**, naming what is rolling,
   as `-Cluster` alone already was.

The choosing is `Select-XmipTestRoll`, apart from the stopping so it is
tested with runs made of their properties and no process started
(`test/XmipTest.Test.ps1`). Nothing here is a new cmdlet.

## Amendment, 2026-09-23: the sweep was not finished, and it was not kept

Clause 24 above says there is no placeholder company. The sweep of 2026-09-20
left nine places holding one, and on 2026-09-23 the assistant wrote four more
into a new mount rule — `xmip-acme-transport`, `module/acme/capability/...` —
in `Get-XmipMountPath`, its test, `repository-model.md` and ADR-0028's
amendment. The owner: *We were not to use acme any more, 3'rd party or
provider*, and *ACME is for the certificate provider*.

- **Prose and doc comments take the grammar slot**: `xmip-<provider>-transport`
  mounting at `module/<provider>/capability/transport`, and *a third party*
  where a sentence needs a noun.
- **Where a literal is needed**, a provider is `example` and a partner or
  tenant is `partner-x`: the mount test's declared repositories, the tenant a
  claim carries (`authorize/claim`), the cloud project a Pub/Sub topic sits in
  (`transport/google-pub-sub`, five places), and a dynamic module's entry-point
  symbol in `platform/runtime`, which read `acme_create_v1` and now reads
  `partner_create_v1`.
- **ACME still means RFC 8555**, and the owner's quoted words keep his
  spelling, as clause 5 of the amendment above already had it.
