# Xmip Governance

Xmip is a centrally governed architecture and software project.

## Authority

The authoritative architecture is defined by the current architecture specification, `xmip-architecture.json`, and accepted pull-request history. When these disagree, the conflict must be resolved through an explicit architecture change.

## Decision process

Changes follow this order:

```text
Requirement -> Architecture -> Implementation -> Verification -> Commit -> Pull request -> Review -> Merge
```

Architecture decisions are made before implementation when a change affects repository boundaries, contracts, message semantics, runtime behaviour, dependency direction or platform guarantees.

## Repository ownership

Each repository has a defined role in the Xmip classification model:

- Foundation
- Capabilities
- Technology
- Operations
- Platform

Repository responsibilities must remain narrow. Common capability repositories define reusable behaviour and contracts. Technology repositories implement a specific technology beneath the owning capability.

## Compatibility

Public contracts, message semantics and artifact definitions should evolve deliberately. Breaking changes require an explicit version change, migration impact statement and review.

## Licensing

Xmip is licensed under the GNU Affero General Public License, version 3 or later (`AGPL-3.0-or-later`).

The license is chosen so that Xmip source remains free and so that modifications are returned to the community, including when a modified version is made available to users over a network rather than distributed as software.

`xmip-architecture.json` declares this license as the repository default. Every Xmip repository carries the full license text, and every crate declares `license = "AGPL-3.0-or-later"`.

Contributions are accepted under the same license. The license governs the freedoms attached to the source; it does not replace the contribution and review process defined in this document.

## Contributions

External contributions are welcome through the official pull-request process. Acceptance is moderated to preserve architectural coherence and long-term compatibility.

## Releases

A release must identify the architecture version, compatible script/runtime versions, included repository versions and known migration requirements.
