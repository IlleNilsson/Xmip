# ADR-0020: One document per subject, and no versions in filenames

- Status: Accepted
- Date: 2026-08-25
- Amended: 2026-09-09 — `doc/decisions/` became `doc/decision/`: a folder is
  named in the shortest singular form like everything else (ADR-0011); the
  empty `doc/operations/` went
- Amended: 2026-09-20 — `CLAUDE.md` folded into `CONTRIBUTING.md`; the root
  keeps `CLAUDE.md` and adds `AGENTS.md` as pointers to it (clause 8)
- Amended: 2026-09-20 — a document that names a thing is tested against it:
  `README.md` must name every command the module exports
- Related: ADR-0011 (naming), ADR-0016 (composition)

## In brief

- Theme: How the work is done
- Subject: One document per subject, no versions in filenames
- Name: The documentation structure
- Order: 1
- Concepts: Documentation, one document per subject

A subject has exactly one document. If two describe the same subject, one is
wrong and you cannot tell which by looking. Versions belong in git history, not
in filenames. Architecture is six documents.

## Context

`doc/` held 110 markdown files. Twelve were empty. The rest included four
architecture specifications that were not versions of each other, three
vocabularies, five documents on repository layout, six on the module boundary,
eight on deployment, four on auditing, and three hand-written inventories of a
thing that generates its own.

None of this was carelessness. It is what happens when a design is worked out
over months: each session produces a document, the document is right when
written, and nothing ever says which one is current. The cost is not storage.
It is that a reader — or a contributor, or a model — finds the wrong one, and
nothing in the repository indicates it is wrong.

The specific failure that forced this: `Xmip-Architecture-Specification-v1.0.md`
contained 23 sections that appeared in no other document, while `v1.2.md` was
about the repository estate rather than the runtime. Reading the version numbers
instead of the files would have deleted the architecture and kept the filing
rules.

## Decision

### 1. One document per subject

A subject has exactly one document. If two documents describe the same subject,
one is wrong, and which one is not discoverable by looking at them.

### 2. No version in a filename

`git` holds versions. A version in a filename creates a lineage the content
does not have, and it lies silently. **`-v1.0`, `-v2`, `-final`, `-current`,
`-new`, `-old` and `-baseline` are not permitted in a document name.**

Where a document supersedes another, the replacement says so in its opening
lines and the superseded file is deleted. The history is in git.

### 3. The document lives where its subject lives

The root repository holds what is true of Xmip as a whole. Anything true of one
module belongs in that module's repository, per `allocation.toml`. A document
about FTP does not live in the root because FTP does not.

### 4. The structure

```text
doc/
  terminology.md                    the vocabulary. One term, one concept.
  architecture/
    runtime-model.md                what Xmip does at runtime
    repository-model.md             why the estate is shaped as it is
    module-model.md                 the module boundary, loading and isolation
    deployment-model.md             nodes, profiles, roles, installation, recovery
    observability-model.md          audit, correlation, tracing, observation
  decision/ADR-NNNN-*.md            the record. Never deleted, superseded in place.
  governance/*.md                   change permission and release model
  planning/*.md                     working notes, explicitly not authoritative
```

Five architecture documents in the root. The sixth, identity per technology
against the standards, lives with the repository that owns its subject, at
`module/capability/authenticate/doc/identity-by-technology.md`, by clause 3
(`doc/planning/allocation.toml` records the move; the tree above was
corrected on 2026-09-12). A further one requires a reason that is not "this
document got long", because length is solved by sections.

### 5. `architecture.toml` is the estate, not a document

Any document that lists repositories is a second source of truth and will be
wrong within a week. Documents hold reasoning; the manifest holds facts. The
same rule retires the three hand-written repository inventories.

### 6. An ADR is a record, not a document about a subject

ADRs are exempt from clause 1: two ADRs may touch one subject because they were
decided at different times, and that is the point of them. They are never
deleted. A superseded ADR gains a header naming its successor and stays.

Where an ADR's content has grown into a description of how the system works
rather than a record of a decision, the description moves to the document that
owns that subject and the ADR keeps the decision. ADR-0013 lost its identity
sections to ADR-0019 this way, and ADR-0019 is a decision record, not the
identity manual.

### 7. An empty file is not a placeholder

Twelve zero-byte files existed under `doc/data/`, `doc/operations/`,
`doc/ux/` and `doc/vision/`. An empty file is a promise nobody made and a
search result that wastes a reader's time. **Delete them.** The directory
structure can be recreated in the second it takes, when there is something to
put in it.

### 8. A rule is not named for the tool that reads it

The owner, 2026-09-20: *I do not think that the file CLAUDE.md should be
named CLAUDE.md. Regardless of AI-tool, the same rules apply.*

`CLAUDE.md` held how work is done in the estate — the records to read before
writing, the hard-learned rules, how a change lands, the working area — and
every line of it is as true of a human contributor as of a model. A filename
that names one vendor's tool makes the rules look like that tool's
configuration rather than the estate's, and it puts clause 1 in breach: two
root documents, `CONTRIBUTING.md` and `CLAUDE.md`, on the one subject of how
to contribute. The content was folded into `CONTRIBUTING.md` on 2026-09-20,
phrased for whoever is working, with the differences between a person and a
model stated where they matter instead of smoothed away.

Tools that load a fixed filename are the one exception clause 1 has to allow.
`CLAUDE.md` and `AGENTS.md` stay at the root as pointers of a few lines each:
what the file is, where the rules live, and that it is a pointer on purpose
so that nobody re-fills it. They carry no rule of their own, so there is
nothing in them that can fall out of step — which is what clause 1 protects.

## Consequences

- 110 documents become roughly 30: six architecture documents, terminology,
  twenty ADRs, two governance documents, and the planning notes.
- Everything technology-specific leaves the root for the repository that owns
  it, per `doc/planning/allocation.toml`.
- `doc/planning/*` is explicitly non-authoritative. It is where thinking is
  allowed to be duplicated and contradictory, which is what it is for.
- A reader who finds a document can trust it is the current one, because there
  is no other.

## Alternatives considered

**Keep everything and add an index.** Rejected: an index is a third thing to
keep in step, and it does not stop a reader finding the wrong document
directly. The four specifications would still all exist.

**Date-prefix the filenames.** Rejected: it is the version problem wearing a
different hat, and it makes the newest file look authoritative even when it is a
narrow addendum — which is exactly the trap `v1.2` set.

**One document per repository, no `doc/` in the root at all.** Rejected for
now: the root genuinely owns cross-cutting subjects — the runtime model spans
every module — and pushing those into any one module repository would make that
repository the de facto root.

## Amendment, 2026-09-20: a document that names a thing is tested against it

The owner, 2026-09-20: *when you change things, you have to change all
related — I can see for example, that the main README.md is not updated.*

He was right, and the gap was measurable. The Xmip module exported
twenty-seven functions and two aliases; `README.md` named twenty-two
functions and one alias. `Expand-XmipEstate`, `Get-XmipEstateRepository`,
`Get-XmipRepositoryRoot`, `New-XmipEstateMap`, `Publish-XmipPin` and the
`xmip-git` alias appeared nowhere in it. The module loader that had landed
the day before (ADR-0057, amendment 2026-09-19) appeared nowhere either,
although it is the first time Xmip opens a Module for real. `Start-XmipTest`
had gained `-NodeCapability` (ADR-0056) while the README still told a
beginner that a node's name says nothing about what it does — which had been
true and had stopped being true.

Clause 1 says a subject has exactly one document. It does not say the
document is right. A document read as true and not true is the failure
clause 1 exists to prevent, arriving by a different road: not two documents
disagreeing, but one document and the estate disagreeing.

**Where the relationship between a document and the thing it describes can be
checked, the check is a test.** `test/Documentation.Test.ps1` has asserted
since it was written that `README.md` names no command that does not exist,
and that every document under `doc/architecture/` is linked from it. It now
also asserts the direction that rots silently: **every function and alias the
Xmip module exports is named in `README.md`**, and the failure lists the ones
missing and says where to put them. A new cmdlet cannot reach `main` without
the front door naming it.

Not asserted, deliberately: that every exported command carries
comment-based help with a `.SYNOPSIS` and an `.EXAMPLE`. Ten of the
twenty-seven have no `.EXAMPLE` and six no `.SYNOPSIS` — but comment-based
help may sit above a function as well as inside it, so an honest check needs
an AST walk rather than a search, and two of the six are helpers whose export
is itself questionable (`Expand-XmipEstate` takes a TOML node and a list;
`New-XmipRepositoryEntry` beside it in ADR-0036 is not exported at all).
Writing help for a command the owner may choose to withdraw is work spent
twice. The test is worth having once the export list is his again.
