# Contributing to Xmip

Xmip follows an architecture-first engineering workflow:

```text
Requirements -> Architecture -> Implementation -> Verification -> Commit -> Pull request -> Review -> Merge
```

## Before implementation

A contribution must first identify:

- the requirement being addressed;
- the owning Xmip capability or repository;
- affected contracts and dependencies;
- compatibility and migration implications;
- the verification approach.

Repository placement is governed by [`xmip-architecture.json`](xmip-architecture.json). New repositories, dependencies and technology implementations must fit the classification and dependency rules in that manifest.

## Change scope

Keep pull requests focused. Architecture changes and implementation changes should not be mixed unless the implementation directly proves the architecture change.

Changes to the architecture baseline must update all authoritative representations that are affected, including the architecture specification and manifest.

## PowerShell tooling

Xmip PowerShell scripts require PowerShell Core 7.6.3 or newer and must remain cross-platform.

Use advanced functions and native PowerShell parameter sets. Mutating commands should support `ShouldProcess` where practical.

## Pull requests

A pull request should state:

- requirement;
- architecture impact;
- implementation summary;
- changed files;
- verification performed;
- known limitations or unverified runtime behaviour.

A branch or commit is not considered completed work until a pull request exists. A pull request is not project history until it is merged.

## Contributions and ownership

Xmip is free to use, but the project is centrally governed. Contributions are reviewed and accepted through the official repositories. Creating incompatible forks or copies is outside the intended contribution model.

By contributing, you agree that accepted changes may be maintained, revised or replaced as the Xmip architecture develops.