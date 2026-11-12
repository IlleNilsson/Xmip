# ADR-0072: A Quest probes, and the regulation is a parameter

- Status: Accepted
- Accepted: 2026-11-08, the owner, in the words quoted below
- Date: 2026-11-08
- Related: ADR-0068 (every dependency is a trait, handed in), ADR-0040
  (Xmip retains and archives, it does not delete), ADR-0062 (every Xmip
  tool audits), ADR-0063 (Xmip encrypts its own traffic and its own
  storage), ADR-0070 (an audit record holds what it audits), ADR-0014 (the
  operator surfaces), ADR-0064 (the integration, amendment 2026-11-11),
  `doc/terminology.md` *Report and Quest*, `observability-model.md`
  section 8

## In brief

- Theme: Operating Xmip
- Subject: What a Quest is, and how the Regulation Report presents what the Regulation Quest finds: a regulation's evidence and gaps
- Name: A Quest probes, and the regulation is a parameter
- Order: 22
- Concepts: Quest; the Regulation Quest; regulation; requirement; evidence; gap; GDPR; erasure, of the identity; every Report in one list; the Dependency Quest

**A Quest probes an installation handed to it and returns what it found,
the data a Report presents; it changes nothing it probes. The first is the
Regulation Quest: one Quest, the regulation its parameter, the set of
regulations open to any module. For each of a regulation's requirements,
citing its article, it shows evidence, a gap or not applicable, what is
behind it, and the actions that close a gap, which the operator applies. It
reads at three levels — the regulation with its tally, a row per
requirement, one requirement in full — and never judges whether an
installation meets the regulation. GDPR is the first regulation. The
Dependency Quest shows how things are connected within Xmip, at three
levels too: only integrations work or not, never the installation, and
every gap is reported with the action that closes it (amendment 2026-11-11;
decided, not built).**

## Context

`doc/terminology.md`, *Report and Quest*: *A Report presents existing data,
a Quest probes for data to present in a Report* (the owner, 2026-11-07),
and the Quests the owner named on 2026-11-05 — *Security, Sanity,
Performance, Redundancy, Fail Over, Size, Compile Time and Firewall* —
none designed. `xmip-core-report` was a stub of 49 lines: a
`ReportRecord` and a `ReportDataSink`. `observability-model.md` section 8:
reports are *derived from configuration and records, never authored by
hand*.

The owner agreed the Regulation Quest on 2026-11-08: one Quest whose
regulation is a parameter — GDPR, the patient data law, the Cyber
Resilience Act, NIS2, the AI Act — a module able to add one; for each of a
regulation's requirements it probes, shows the evidence or the gap, and
offers the actions that close a gap; *the operator applies an action; the
Quest never applies one*; it presents evidence and gaps and never says
that an installation meets the regulation, *compliance is the customer's
legal judgment*. The terminology row left its form open; the owner agreed
the form the same day, in three levels:

1. a regulation, with a tally of evidence, gaps and not applicable;
2. its requirements, one row each, with its state;
3. one requirement, with the Locations, Streams and settings behind it
   and the actions that close it.

Being the first Quest, it defines the seam every later Quest uses.

## Decision

1. **A Quest is a trait.** `report::quest::Quest` has a name and one act,
   `probe(&dyn Installation) -> Found`, its associated type what it found.
   A Quest reads; it applies nothing.
2. **What a Quest probes is handed in.** `Installation` is a trait
   (ADR-0068): the node's configuration as `xmip-core-configure` reads it
   (`XmipConfigurationDocument`, the one model of it), and the two facts
   another capability owns — `wire`, what a Location's technology declares
   of its wire (encrypted, plain or undeclared), and `at_rest`, how a data
   domain is kept at rest (sealed on the node's embedded Storage node, on a
   database server IT runs, or on the Storage nodes the node lists). Whoever
   composes implements it; a Quest never reads a file or looks a technology
   up by its name. A later Quest adds what it probes to the trait, with a
   default for the Quests it does not concern.
3. **One Regulation Quest; the regulation is a parameter.**
   `RegulationQuest::of(&Regulations, name)` takes the regulation by the
   name an operator gives, and refuses one not held in words naming those
   that are.
4. **The regulations are open.** `Regulation` (its name, its title, its
   requirements in order) and `Requirement` (its name, its citation, its
   probe) are traits. `Regulations::standard()` holds Xmip's own; a module
   adds its regulation with `Regulations::with`, refused where one of its
   name is held. Nothing in the set is a closed list.
5. **A requirement's state is Xmip's own fixed answer:** `Evidence`, `Gap`
   or `NotApplicable`, a closed enum. A `Finding` holds the state, what it
   says in words, what is `Behind` it — a Location by side and name, a
   Stream by its identifier, a setting by its key and value — and the
   `Action`s that close it. Only a gap carries actions, at least one: a
   change to the configuration (`Configure`, the setting and what to make
   it say), something done outside Xmip by whoever owns it (`Outside`), or
   `NotYetAvailable`, saying that what would close it is not yet available
   in Xmip.
6. **Three levels.** What the Quest returns, `Probed`, is the first level:
   the regulation's name and title and its `Tally`. `rows()` is the second,
   a `Row` per requirement with its citation and state. `requirement(name)`
   is the third, the `Found` requirement with its finding in full.
7. **Where a regulation's requirements come from.** From the regulation's
   own text: each requirement cites the article it rests on, checked
   against the published text, and its probe reads only what the
   installation can answer. A requirement Xmip cannot support is shown as a
   gap whose action says *not yet available in Xmip*, never left out and
   never answered by guess.
8. **No verdict.** No name, finding or action says the installation meets,
   satisfies or is approved under a regulation; a test holds every word
   the GDPR Quest says to it.

### GDPR, the first regulation

Regulation (EU) 2016/679, nine requirements, each probed in what a node's
configuration can say today:

| Requirement | Citation | What the probe finds |
| --- | --- | --- |
| Data minimization in logs and traces | Article 5(1)(c) and Article 25(1) | A gap: masking personal data in logs and traces is not yet available in Xmip. |
| Storage limitation | Article 5(1)(e) | A gap: a node reads no retention window — retention and archiving are built and not in the node (`estate-map.md`, `retention-archiving`) — so its configuration says nothing of how long what Xmip keeps is kept; a retention window on a node is not yet available in Xmip. |
| Accountability: the audit | Article 5(2) | Evidence: every Xmip program records through `xmip-core-audit`, each record chained to the one before it (ADR-0062, ADR-0070); behind it `[audit] storage` where the node names it. |
| Right of access | Article 15 | A gap: finding one data subject's personal data is not yet available in Xmip. |
| Right to erasure | Article 17 | A gap: erasure per data subject is not yet available in Xmip. What erases is decided below, *Erasure is of the identity*. |
| Records of processing activities | Article 30 | A gap: declaring the flows that carry personal data is not yet available in Xmip. |
| Encryption at rest | Article 32(1)(a) | Evidence where every domain this node keeps is sealed on its embedded Storage node, behind it `[store] key_store`; a gap closed outside Xmip where a domain is on a database server IT runs, whose encryption at rest is IT's (ADR-0063, amendment 2026-10-01); not applicable where the Storage nodes the node lists keep everything. |
| Encryption in transit | Article 32(1)(a) | Per Receive and Send Location: evidence where every technology declares its wire encrypted; a gap where one is plain, closed by entering the Location as its technology encrypts, or undeclared, closed by a declaration not yet available in Xmip; not applicable with no Location. |
| Transfers outside the European Union | Chapter V, Article 44 | A gap: probing transfers of personal data outside the European Union is not yet available in Xmip. |

### Erasure is of the identity

Decided by the owner, 2026-11-08: *A person's data does not necessarily
have to be erased. The person's identity regarding the data has. The
actual data will be deleted when retention occurs.*

- **What is erased is the identity, irreversibly.** The data stays until
  retention removes it (ADR-0040). Pseudonymized data is still personal
  data (GDPR, recital 26), so a link that a table or a key could restore
  does not erase.
- **Per-subject keys.** The fields that identify a person are sealed under
  a key of that person's alone; erasing the person deletes the key, and the
  identity is unreadable everywhere it was written — Storage, standbys and
  archive alike. No record is rewritten, so ADR-0040 holds and the audit
  chain (ADR-0070) stays whole.
- **A Stream declares its identifying fields**, as Promote declares what it
  reads; Xmip seals what is declared.
- Not built. Until it is, the Quest finds Article 17 a gap.

## Open

1. **A transport declaring its wire.** `transport::Configured` declares a
   technology's schemes and settings, and nothing of whether its wire is
   encrypted; until it does, whoever composes an `Installation` can only
   answer `Undeclared`, and every Location is a gap. A declaration beside
   `SCHEMES` — whether an address and its settings encrypt, as `waits`
   answers whether a Receive Location waits — follows.

## Consequences

- Built, 2026-11-08, in `xmip-core-report`: `quest.rs` (`Quest`,
  `Installation`, `Wire`, `AtRest`), `finding.rs` (`State`, `Finding`,
  `Behind`, `Action`), `regulation.rs` (`Regulation`, `Requirement`,
  `Regulations`, `RegulationQuest`, `Probed`, `Tally`, `Row`, `Found`) and
  `gdpr.rs`, tested for every state. `xmip-core-report` depends on
  `xmip-core-configure`, and `StoreConfiguration::key_store` there is the
  one place the key store a node names, or the platform's, is read.
- Not in this record's build, and following it: the surfaces, in their
  order — the C ABI, the command line, PowerShell and the GUI (ADR-0014) —
  and the composer that implements `Installation` from a running node
  (built by the amendment of 2026-11-10, from a configuration file; a
  running node follows); the
  other regulations — the patient data law, the Cyber Resilience Act,
  NIS2, the AI Act — each a `Regulation` of its own.
- `estate-map.md`, `regulation-quest`, says what is built.

## Provenance

The owner's, 2026-11-08: one Regulation Quest with the regulation a
parameter, the five regulations named, a module adding one, the open set
as a trait; evidence, gap or not applicable per requirement, the actions
that close a gap, applied by the operator and never by the Quest; no word
saying compliant, conformant or certified; the three levels; GDPR first,
probing retention, encryption at rest, the Locations' wire and the audit,
and the five requirements Xmip cannot support reported as gaps *not yet
available in Xmip*; erasure of the identity, the data left to retention,
and per-subject keys deleted to erase it ("Go with 1"). The trait shapes, the `Installation` seam, the
`Outside` action for a database server IT runs, the requirement names and
the article each cites were drafted by the assistant and are the owner's
to change.

## Amendment, 2026-11-10: every Report in one list, saying whether it is quick or a Quest probes first

The owner asked, 2026-11-10: *And where were the Reports? They should have
been there, with a little icon saying if they were presenting existing data
or probing for data.* And: *I want a list of reports, Firewall and what
not, Quest. I just want the user to know that a report may go quicker than
a report based on quests*; *A firewall report might be a quest. A report on
actual critical, error, warnings and what not might be actual Audit data
and quicker*; and, the list below put to him, *Agreed, go ahead.*

1. **One list of every Report.** `xmip-core-report` keeps it, `Reports` in
   `catalog.rs`: Xmip's own in `Reports::standard()`, and a module adds a
   Report or a Quest with `Reports::with`, as it adds a regulation. Every
   surface shows the same list through `xmip_operate.h` section 25,
   `xmip_report_v1`, and keeps no list of its own: the C ABI, the command
   line, PowerShell and the GUI, in that order (ADR-0014).
2. **Its kind follows from what an entry holds.** A `Report` holds `Data`:
   `Data::Existing`, data that already exists, makes it `Kind::ExistingData`,
   named *Report*, *Presents data that already exists*; `Data::Quest`, what
   a Quest probes first, makes it `Kind::Quest`, named *Probing report*,
   *Presents what a Quest probes first*. No entry declares a kind of its own
   and nothing reads one from a name. The kinds are Xmip's own fixed
   answer, a closed enum, numbered as `XmipReportKind`. A surface that draws
   shows each entry's kind as a plain icon alone, its name the icon's
   accessible name and hover text, and its legend the icon beside the name:
   a page for a Report, the page under a magnifying glass for a Probing
   report. A text surface shows the name (amendment 2026-11-12).
3. **Not yet available.** An entry not built yet holds `Data::Existing(None)`
   or `Data::Quest(None)`. It is listed, says *not yet available*, and has
   nothing to open.
4. **The time to expect.** A Quest's entry shows how long its last probe
   took. The runtime times each probe and records it through the one audit
   writer as `quest.probe` (Finished, Information; properties `report`,
   `parameter`, `node`, `took_ms`), and the list reads the newest such record
   of each Report back through the audit's one query. No second store keeps
   it. An entry never probed says *not probed yet*. Where the audit cannot
   be read, every Report is listed all the same, each Quest's entry says
   *last probe could not be read*, and the list says why.
5. **Opening.** A quick entry is opened at the reader that already presents
   it, named by its entrypoint (`read_by`), never by a second reader; each
   surface opens it at its own command for that reader. A Quest's entry
   names its parameter and its choices, what a row of its second level is
   called, and its levels; opening it probes and answers them. The
   Regulation Report's are this record's three, its parameter the
   regulation and its row a requirement. A Quest a module adds is held as a
   `Probe` and opened through the same answer, which says what a row is
   called and holds a title, a tally of each state's count, rows and one
   row in full only where the Quest answers them. A Report that cannot be
   opened — none of that name, not yet available, quick, or given a
   parameter it does not take — is refused before anything is read, and the
   runtime finds the one Report a surface names, for the list as for an
   open, in one sentence.
6. **Probing is a read.** A Quest reads what it probes and changes nothing
   (clause 1), so every role may list and probe, an Observer included.
   Applying an action stays the Operator's.
7. **A node's build only.** `xmip-core-report` reads a configuration
   through `xmip-core-configure`, which only a node's build of the runtime
   links; a remote build, the phone's, has no section 25, and a surface says
   so in words.

| Report | Kind | Available today |
| --- | --- | --- |
| Audit | Report | Yes: `xmip_audit_read_v1` |
| Dead Messages | Report | Yes: `xmip_dead_messages_v1` |
| Locations | Report | Yes: `xmip_publication_read_v1`, the scope tree |
| Subscriptions | Report | Yes: `xmip_subscriptions_v1` |
| Parties | Report | Not yet: no reader presents them; the Topology draws them |
| Expiring certificates and secrets | Report | Not yet |
| Regulation | Probing report | Yes: this record's Quest |
| Firewall | Probing report | Not yet |
| Identity and isolation | Probing report | Not yet: ADR-0022 clause 5's Report |
| Security, Sanity, Performance, Redundancy, Fail Over, Size, Compile Time | Probing report | Not yet: named 2026-11-05, not designed |

The Identity and isolation Report is ADR-0022 clause 5's, which names it
mandatory: every identity context, its class and where it runs, and every
isolation rule evaluated on it with its result. It was *Identity and
Isolation Compliance*; the word that judges is dropped, as clause 8 above
keeps every verdict out of a Report (ADR-0022, amendment 2026-11-10). Its
data is computed from the identity contexts and ADR-0022's isolation rules,
so a Quest probes for it, and it is listed as not yet available. It and the
Firewall Report are mandatory in the sense that record gives the word:
both are in the list on every installation, never one to be asked for
before it exists.

### What a probe reads

A Quest probes a configuration file given by path: a node's own, or a
cluster's `cluster.xmip` sliced for one node by `configure::slice`, the two
told apart by `configure::document_kind`, never by the file's name; a
cluster's file without a node is refused naming its nodes. The runtime
composes the `Installation`: every Location's wire `Undeclared`, since no
transport declares its wire yet (Open 1 above), and each data domain kept
where `storage::keeping` says — the node's own Storage node, a database
server its table names, or the Storage nodes it lists — the one decision
`storage::plan` starts a node by. A configuration that says neither the
Storage role nor Storage nodes, or whose table names a storage its
database is not kept on (`postgres` for `postgresql`, `sqlite` for the
runtime database), is refused in the words a node starting by it is: the
word is read by `xmip-core-persist`'s `database::technology`, which
`database::problems` holds a starting node to, so no Quest reports evidence
of a store that is not there.

### Who decided what

The owner's, 2026-11-10: one list of every Report on every surface; each
saying with a small icon whether it presents existing data or probes for
it; that a quick Report may go quicker than one based on Quests; the
Firewall Report a Quest; the Audit Report quick; the list itself (*Agreed,
go ahead*).

Drafted and decided by the assistant while designing, the owner's to
change: the kind following from what an entry holds, never declared;
*not yet available* as an entry holding none; the last probe's time,
recorded and read back through the audit, as the time to expect; a quick
entry opened at its existing reader, named by its entrypoint;
Configuration split into Locations, Subscriptions and Parties, each with
its own reader; the parameter and the row named by the Quest, so a surface
takes `-Parameter` and `-Row` and no `-Regulation`; probing a read every
role may make; a node's build only; what a probe reads; the composer in
the runtime, over `storage::keeping`. The words
*not yet available*, *not probed yet*, *last probe could not be read*, each
entry's covers sentence, the icons and `quest.probe` are the assistant's
too. `AtRest::Server` keeps its `&'static str`: the word reaches it through
`persist`'s own name for the server, never from the file as written. The
assistant's as well, settled while the build was reviewed the same day:
the Identity and isolation Report kept in the list as ADR-0022 clause 5
requires, a Quest's and not yet available; the runtime finding the one
Report a surface names (`list` takes `report`), so no surface finds or
refuses a name of its own; the tally answered as each state's words and
count, and what a row is called answered with every probe, so no surface
types a state or a row's name; a Quest's answer shown only where it holds
a title, a tally or rows; a Report that cannot be opened refused before
its configuration is read; an open too long for the caller's room answered
for its length and not audited, so one probe asked again leaves one
record; a list the audit cannot be read for naming every Report and saying
why; the probe's record worded as the Report's Quest probing the node; and
the desktop hosting the Reports view through `ReportHosting.Add`, which its
test hosts the view by. On the
surfaces, the assistant's too: each list shows the kind's name, the
Report's, what to expect and, last, where a long sentence is cut least,
what it covers; the command a quick entry is presented by is each
surface's own map from the reader's entrypoint (`Presented by: xmip audit`
on the command line, `PresentedBy` in PowerShell); a probe is audited under the surface's own program,
where its records go, which is where its list reads the last probe back;
the command line's `--node` is `certificate`'s option too, and its `--json`
the runtime's document whole. In the GUI, the assistant's as well: the bolt
and the hourglass are drawn in the text's own color, never the brand or a
mood; each level is in the address (`/reports?report=<name>`, then
`&parameter=<choice>`, then `&row=<requirement>`); the desktop's Quests
probe the `cluster.xmip` it edits, on the node `gui.toml` configures there
or the one the address names, each node of the file offered as a link; a
Quest that takes no parameter is probed as it opens; the web host, which
edits no `cluster.xmip`, lists every Report and says where a Quest is
probed; and the view asks the runtime again only when the address moves.

### Left open

1. **The audit's category.** The owner's *critical, error, warnings and what
   not* reads as more severities and categories than the audit keeps: three
   severities, information, warning and error, and no category. The Audit
   Report presents severity, action and phase over a time range. A category,
   or another severity, changes the audit record and Xmip Storage, and is
   his decision.
2. **Expiring certificates and secrets** is listed as not yet available;
   the record that builds it sets who may open it.
3. **One noun for every Report.** `Get-XmipAudit`, `xmip audit` and the
   Audit view stay where they are, and the Audit Report opens at them.
   Whether they fold into `Get-XmipReport`, fewer cmdlets, is his call.
4. **Probing a running node.** A Quest probes a configuration file today.
   Probing a running node's own configuration through its operate listener
   follows.

### What was built

- Built 2026-11-10 in `xmip-core-report`: `catalog.rs` (`Kind`, `Report`,
  `Data`, `Probe`, `LastProbes`, `Reports`), `answer.rs` (the list, or one
  entry of it, and one Report opened, as section 25's JSON, with
  `answer::probe_of`, every refusal of an open that needs no installation)
  and `RegulationReport` in `regulation.rs`, which shapes the Regulation
  Report's own answer beside its Quest. `xmip-core-report` depends on
  `xmip-core-abi` for the readers' entrypoints and the kinds' numbers.
- Built the same day in the runtime's library: `xmip_report_v1`
  (`ffi/report.rs`) over `report.rs`, which composes the installation and
  records each probe the caller receives, and `storage::keeping`, which
  `storage::plan` now starts a node by, each table's storage read by
  `database::technology` in `xmip-core-persist`. `xmip_operate.h` section 25
  and its Rust mirror, `operate::report`.
- Built the same day on the .NET surfaces, in order: `RuntimeReports` and
  `ReportKind` in `Xmip.Abi`, `RuntimeRules.Reports` refused in words by a
  remote build; `ReportCatalog` (`List`, `Named`, `Open`), `ReportListing`,
  `ReportEntry`, `ReportProbe`, `ReportProbed`, `ReportCount`, `ReportRow`
  and `ReportRequirement` in `Xmip.Surface`; the command line's `xmip
  report`, an MCP tool too; and PowerShell's `Get-XmipReport`, with a view
  for each object.
- Built the same day in the GUI, the web's and the desktop's alike: the
  Reports view (`/reports`), on the bar after the Audit for every role, with
  each kind's icon and name (`ReportKindLabel`), the list and its legend
  (`ReportTable`), one Report (`ReportDetail`), the nodes of the file it
  probes (`ReportNodes`) and its levels (`ReportLevels`); `ScopeLink.Reports`
  and `ScopeLink.Presented`; and `ReportHosting`, through which the desktop
  hosts the view over its `SliceDelivery`. The list is built on every
  surface: the C ABI, the command line, PowerShell and the GUI.

## Amendment, 2026-11-11: the Dependency Quest

The owner, 2026-11-11, shown BizTalk's Applications (ADR-0064, amendment
of this date): *What I would like is a dependency tree, a Quest, to tell me
how things are connected within Xmip*; and *There is no such thing as a
working installation. There is only working integrations, hence a gap is a
gap, report it.* An integration is one forward path, from a Receive
Location to a Send Location, never running backwards, which replay
re-enters forward (ADR-0064, amendment of this date, with its drawing,
`doc/architecture/integration-path.svg`).

1. **A Quest on this record's seam.** It probes what it is handed and
   changes nothing (clause 1); what it probes beyond a node's configuration
   is added to `Installation`, with a default for the Quests it does not
   concern (clause 2). It is in the one list of every Report as one that
   takes longer (amendment 2026-11-10).
2. **Three levels.**
   1. The cluster, with a tally of its integrations, things, connections
      and gaps.
   2. One row per integration: it works, or its gaps.
   3. One integration in full: each step with what it needs — its node,
      transport module, secret, certificate and Party; a Subscription's
      filter and the properties it reads; a Work Process's module — and
      what needs it; each link, live or not; the replay entry points, with
      their lineage (ADR-0064, amendment of this date, clause 2); and the
      audit events each step writes (`terminology.md`, *Audit and Failure
      Persistence*; ADR-0070).
3. **Only integrations work or not, never the installation.** No level
   says an installation works; the first tallies, as clause 8 keeps every
   verdict out of a Report.
4. **A gap is a gap: every one is reported, every time, with the action
   that closes it.** The operator applies the action; the Quest never does
   (clause 5; amendment 2026-11-10, clause 6).

**What counts as a gap**, the assistant's draft, which the owner has not
confirmed:

- an accepted Message no Subscription wanted: a Dead Message Queue entry;
- a Subscription nothing can reach: its filter reads a property no Receive
  Port promotes;
- a Send Port or Send Port Group no Subscription feeds;
- a Location, Work Process or Send Port no node runs, or a stopped node on
  the path;
- a secret, certificate or Party a Location names that its node does not
  hold, or a certificate past its date;
- a module a step needs that its node does not carry.

A configuration file answers the path and what each step names. Whether a
node runs, holds what a Location names and carries what a step needs, and
what the Dead Message Queue holds, are the running cluster's, which the
probe of a running node, *Left open* 4 of the amendment of 2026-11-10,
reaches; and the first level is the cluster's, where a probe reads one
node's slice today (*What a probe reads*). Decided, not built: open
problem 65.

Who decided what. The owner's, 2026-11-11: a dependency tree, a Quest,
showing how things are connected within Xmip; no working installation,
only working integrations; a gap is a gap, reported. The assistant's, for
the owner to change: the name *Dependency Quest*, from his words; the three
levels, after the Regulation Quest's, and what each shows; and the draft
of what counts as a gap.

## Amendment, 2026-11-12: a Report icon and a Probing report icon

The owner, 2026-11-12, looking at the Reports view: *The reports states
Quick or Takes longer, not what I asked for. Report icon and a Probing
report icon, not the text*; and *a flash and time glass is not really good
icons*. Clause 2 of the amendment of 2026-11-10 is rewritten to what stands:

- **The kinds' names are *Report* and *Probing report***, the runtime's
  (`Kind::name` in `xmip-core-report`, through `xmip_report_v1`), so every
  surface says the owner's words: the command line and PowerShell show the
  name, as a text surface has no icon.
- **A drawing surface shows the icon alone** in each entry, its name the
  icon's accessible name and, with its meaning, the hover text; the legend
  alone shows the icon beside the name and meaning, since a legend is where
  an icon is read (`ReportKindLabel`, Web and Desktop alike).
- **A page for a Report; the page under a magnifying glass for a Probing
  report**, in place of the bolt and the hourglass: plain inline icons in
  the text's own color, as before.

Who decided what. The owner's: the two names, and icons in place of the
text. The assistant's, for the owner to change: the two glyphs, and the
legend keeping the names beside its icons.
