# ADR-0053: PowerShell has three public nouns

- Status: Accepted
- Date: 2026-09-14
- Related: ADR-0014 (the operator surfaces), ADR-0016 (submodule composition),
  ADR-0027 (the operator boundary), ADR-0028 (the Playground), ADR-0052
  (the operator surfaces share one model)

## In brief

- Theme: Operating Xmip
- Subject: The public PowerShell command model for developing, testing and operating Xmip
- Name: PowerShell has three public nouns
- Order: 11
- Concepts: PowerShell command model

**PowerShell exposes three Xmip nouns: Estate for repositories, submodules and
their architectural record; Test for suites, test nodes, results and their
monitor; Runtime for the running product. Parameters select a view, target or
action within one noun. The verb keeps its PowerShell promise: Get and Test
only read, while Install, Set, Sync, Publish, Start and Stop may change state
and support WhatIf. Public commands are façades over small private functions,
not large scripts containing every implementation.**

## Context

The estate module exported twenty-four functions. The same test facility alone
had separate Start, Get and Stop commands for its roll, node processes and web
monitor, plus a separate result reader. The operator module exported seven more
cmdlets, including two names for the two states of one runtime operation.

The problem was not the number of implementation functions. Those should be
small and live in separate files. The problem was making every implementation
detail a public noun a user had to discover.

The owner identified the three subjects on 2026-09-14: Estate for repository
and submodule work, Test for testing, and Runtime for runtime work. The owner
also rejected `Get-XmipEstate -Sync`: Get must never surprise a caller by
changing repositories. A later example introduced a named local slice with a
destination and selected features; the manifest has no Feature selection model,
so the public shape uses exact repository names and resolves their dependencies.

## Decision

### 1. Three nouns, twelve commands

The estate module exports:

```text
Install-XmipEstate   Get-XmipEstate      Test-XmipEstate
Set-XmipEstate       Sync-XmipEstate     Publish-XmipEstate
Start-XmipTest       Get-XmipTest        Stop-XmipTest
```

The operator module exports:

```text
Get-XmipRuntime      Test-XmipRuntime    Set-XmipRuntime
```

An implementation function is not exported merely because it exists. It is
called through the public command whose noun owns it.

### 2. Verbs state the safety boundary

`Get` and `Test` do not write files, move branches, change processes or alter a
runtime. `Get-XmipEstate -Sync` is therefore not a valid convenience. `Sync`
reconciles repositories, `Publish` lands changes, `Start` and `Stop` operate
test processes, and `Set` records desired state or changes the runtime state.
Every changing command supports `-WhatIf`.

### 3. A local estate slice is declared, then synchronized

`Set-XmipEstate -Slice <name> -Path <directory> -Include <repositories>` writes
a machine-local definition under `.local-work/estate`. `Destination` is an
input alias for `Path`; `Feature` and `Features` are input aliases for
`Include`. Their values are exact repository names from `architecture.toml`;
Xmip does not invent an undeclared Feature taxonomy. The definition records the
complete dependency closure.

`Sync-XmipEstate -Target Repository -Slice <name> -Action <action>` reads that
definition and acts only on its repositories. Set declares the desired local
selection. Sync materializes or updates it.

### 4. Runtime remains at the operator boundary

The root module does not duplicate runtime behavior. `xmip-core-powershell`
owns the Runtime noun and remains a thin face over `Xmip.Surface` and the
operator ABI. `Set-XmipRuntime -State Paused|Running` is the two acts the
boundary already carries. It does not add start, stop or restart of a runtime
scope, and it does not revive the declined PowerShell provider.

### 5. Test targets are parameters

`Start-XmipTest`, `Get-XmipTest` and `Stop-XmipTest` select suites, emulated
nodes, results, history and the test monitor through `Target` or `View`.
The internal functions retain the process-specific implementation and tests.

This supersedes the public command spellings recorded on 2026-09-12 for
`XmipTestNode`, `XmipWeb`, `Get-XmipTestStatus`, `Suspend-XmipScope` and
`Resume-XmipScope`. It does not change their behavior or ADR-0052's declined
runtime operations.

## Consequences

- Completion begins with three memorable nouns instead of implementation
  details.
- Scripts stay small by growing private helpers, while the public surface gets
  smaller.
- Existing scripts using the removed pre-alpha names must move to the new
  façade commands; the major estate-module version records that break.
- A slice is reproducible on one machine without becoming shared architecture.
- The CLI can use the same Estate, Test and Runtime subjects without imitating
  PowerShell syntax.

## Provenance

The three nouns, the consolidation, the separation between public cmdlets and
private scripts, and the local-slice example are the owner's instructions on
2026-09-14. The command spellings and dependency-complete slice are the
assistant's implementation of them, accepted through the owner's approval of
the verb model.
