# Architectural change permission

Xmip architecture is controlled by explicit decisions.

Before changing an established architectural decision, implementation strategy, technology choice, repository structure, naming rule, dependency rule, manifest schema, execution model, or other locked project principle, the proposed change must be presented to the project owner and explicit permission must be received.

Implementation must not silently replace an agreed approach with a different one, even when the alternative appears simpler or more familiar.

## Required sequence

1. Identify the existing decision that would be affected.
2. Describe the proposed change and the reason for it.
3. Explain the consequences, including new dependencies and compatibility effects.
4. Ask for explicit permission.
5. Implement only after permission is granted.

Corrections that restore conformance to an already approved decision do not require a new architectural decision. They still require normal review through a pull request.

## Every decision record states its provenance

A decision record ends with a `## Provenance` section saying **which parts are the owner's ruling and which were drafted**.

This exists because of how these documents are written. Most of the text in this repository was generated, and generated text has no tell: it is fluent, internally consistent and authoritative whether it is transcribing a decision that was made or filling a gap that was noticed. There is no hedging to signal the difference, and a reader six months later — human or model — cannot recover it from the prose.

The damage is not hypothetical. Four documents each called a version of the specification turned out to be four different documents. Three vocabularies described one runtime. SFTP was inside the FTP family in two documents and outside it in a third. Node.js was a supported module technology in one and explicitly excluded in two others. None of that came from anyone changing their mind.

ADR-0013 already does it:

> The definitions of identity, authentication and authorization are the owner's, as is the disposition of faulty Streams to the retention service.

One sentence, and it makes the rest of the document safe to consolidate — because a later reader knows which lines cannot be quietly rewritten to resolve a conflict.

Be specific. "Drafted by an assistant, reviewed by the owner" says nothing. Name the clauses that are rulings, name the material that came from an earlier draft or another model, and name what was inferred to fill a gap. The inferred parts are the ones a future consolidation is allowed to correct.

`tests/Decisions.Tests.ps1` counts the records carrying a Provenance section. That count may rise and may not fall.

## Estate changes are atomic

A repository may be added, removed or renamed only through a change that updates the manifest, the affected architecture documents and the affected decision records **together, in one change**.

Not because ceremony is good, but because these three drift apart silently and in a particular order: the manifest is edited because something has to work today, the documents are left for later, and later does not come. `architecture.toml` then describes an estate the documents do not, and neither of them is wrong enough to notice.

`tests/Allocation.Tests.ps1` catches part of this — a move whose destination is not a declared repository fails — but it cannot see a repository that was renamed while a document went on using the old name. That part is a human obligation, which is why it is written here rather than left to the tooling.

## Locked application to the architecture reconciler

`Sync-XmipEstate.ps1` uses the GitHub REST API directly for remote repository discovery, creation, and configuration.

It must not depend on GitHub CLI (`gh` or `gh.exe`).

Local Git operations may use `git` for clone, fetch, checkout, submodule, commit, and push operations.
