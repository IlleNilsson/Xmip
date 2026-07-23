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

## Contributions

External contributions are welcome through the official pull-request process. Acceptance is moderated to preserve architectural coherence and long-term compatibility.

## Releases

A release must identify the architecture version, compatible script/runtime versions, included repository versions and known migration requirements.