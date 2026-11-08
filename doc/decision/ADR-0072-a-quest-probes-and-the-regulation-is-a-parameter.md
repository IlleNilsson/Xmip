# ADR-0072: A Quest probes, and the regulation is a parameter

- Status: Accepted
- Accepted: 2026-11-08, the owner, in the words quoted below
- Date: 2026-11-08
- Related: ADR-0068 (every dependency is a trait, handed in), ADR-0040
  (Xmip retains and archives, it does not delete), ADR-0062 (every Xmip
  tool audits), ADR-0063 (Xmip encrypts its own traffic and its own
  storage), ADR-0070 (an audit record holds what it audits), ADR-0014 (the
  operator surfaces), `doc/terminology.md` *Report and Quest*,
  `observability-model.md` section 8

## In brief

- Theme: Operating Xmip
- Subject: What a Quest is, and how the Regulation Quest presents a regulation's evidence and gaps
- Name: A Quest probes, and the regulation is a parameter
- Order: 22
- Concepts: Quest; the Regulation Quest; regulation; requirement; evidence; gap; GDPR

**A Quest probes an installation handed to it and returns what it found,
the data a Report presents; it changes nothing it probes. The first is the
Regulation Quest: one Quest, the regulation its parameter, the set of
regulations open to any module. For each of a regulation's requirements,
citing its article, it shows evidence, a gap or not applicable, what is
behind it, and the actions that close a gap, which the operator applies. It
reads at three levels — the regulation with its tally, a row per
requirement, one requirement in full — and never judges whether an
installation meets the regulation. GDPR is the first regulation.**

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
| Right to erasure | Article 17 | A gap: erasure per data subject is not yet available in Xmip. |
| Records of processing activities | Article 30 | A gap: declaring the flows that carry personal data is not yet available in Xmip. |
| Encryption at rest | Article 32(1)(a) | Evidence where every domain this node keeps is sealed on its embedded Storage node, behind it `[store] key_store`; a gap closed outside Xmip where a domain is on a database server IT runs, whose encryption at rest is IT's (ADR-0063, amendment 2026-10-01); not applicable where the Storage nodes the node lists keep everything. |
| Encryption in transit | Article 32(1)(a) | Per Receive and Send Location: evidence where every technology declares its wire encrypted; a gap where one is plain, closed by entering the Location as its technology encrypts, or undeclared, closed by a declaration not yet available in Xmip; not applicable with no Location. |
| Transfers outside the European Union | Chapter V, Article 44 | A gap: probing transfers of personal data outside the European Union is not yet available in Xmip. |

## Open

1. **Erasure and ADR-0040.** ADR-0040 decides that Xmip retains and
   archives and never deletes; deletion is the archive owner's. The owner's
   wording for Article 17 is *not yet available in Xmip*, which reads as a
   promise ADR-0040 rules out. Which holds — erasure per data subject as a
   future capability, amending ADR-0040, or an action outside Xmip, for
   the archive owner — is the owner's.
2. **A transport declaring its wire.** `transport::Configured` declares a
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
  and the composer that implements `Installation` from a running node; the
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
available in Xmip*. The trait shapes, the `Installation` seam, the
`Outside` action for a database server IT runs, the requirement names and
the article each cites were drafted by the assistant and are the owner's
to change.
