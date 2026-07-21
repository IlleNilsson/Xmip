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

## Locked application to the architecture reconciler

`Set-XmipArchitecture.ps1` uses the GitHub REST API directly for remote repository discovery, creation, and configuration.

It must not depend on GitHub CLI (`gh` or `gh.exe`).

Local Git operations may use `git` for clone, fetch, checkout, submodule, commit, and push operations.
