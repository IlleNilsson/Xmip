# ADR-0020: One document per subject, and no versions in filenames

- Status: Accepted
- Date: 2026-08-25
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

`docs/` held 110 markdown files. Twelve were empty. The rest included four
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
docs/
  terminology.md                    the vocabulary. One term, one concept.
  architecture/
    runtime-model.md                what Xmip does at runtime
    repository-model.md             why the estate is shaped as it is
    module-model.md                 the module boundary, loading and isolation
    deployment-model.md             nodes, profiles, roles, installation, recovery
    observability-model.md          audit, correlation, tracing, observation
    identity-by-technology.md       identity per technology, against the standards
  decisions/ADR-NNNN-*.md           the record. Never deleted, superseded in place.
  governance/*.md                   change permission and release model
  planning/*.md                     working notes, explicitly not authoritative
```

Six architecture documents. A seventh requires a reason that is not "this
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

Twelve zero-byte files existed under `docs/data/`, `docs/operations/`,
`docs/ux/` and `docs/vision/`. An empty file is a promise nobody made and a
search result that wastes a reader's time. **Delete them.** The directory
structure can be recreated in the second it takes, when there is something to
put in it.

## Consequences

- 110 documents become roughly 30: six architecture documents, terminology,
  twenty ADRs, two governance documents, and the planning notes.
- Everything technology-specific leaves the root for the repository that owns
  it, per `docs/planning/allocation.toml`.
- `docs/planning/*` is explicitly non-authoritative. It is where thinking is
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

**One document per repository, no `docs/` in the root at all.** Rejected for
now: the root genuinely owns cross-cutting subjects — the runtime model spans
every module — and pushing those into any one module repository would make that
repository the de facto root.
