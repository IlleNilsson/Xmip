# Xmip Release Model

This document defines the Xmip project release terminology.

## Xmip Continuum

Xmip Continuum is the continuously evolving project stream.

The `main` branch represents Xmip Continuum.

Continuum contains the current architectural truth, documentation, specifications, tests, and code that have been accepted into the project.

Continuum is allowed to evolve.

Continuum may contain work that is not yet ready to be released as a stable user-facing package.

## Xmip Linear

Xmip Linear is a releasable, stabilized line derived from Xmip Continuum.

A Linear release is created from a specific Continuum state.

A Linear release must be reproducible.

A Linear release is versioned, tested, documented, and intended for use outside the evolving project stream.

## Branch and release mapping

```text
Feature branches
    -> Pull request
        -> Xmip Continuum (`main`)
            -> Stabilization / validation
                -> Xmip Linear release
```

## Current practice, and when it ends

**Until the first Linear release, work commits directly to Continuum.**

This is a deliberate exception to the branch mapping above, not an oversight.
The project has one contributor, nothing outside the repository depends on it,
and no repository other than `Xmip` yet holds content. A pull request in that
situation is a review of one's own work by oneself, which costs time and
catches nothing.

The exception ends at the **first Linear release**. From that point the mapping
above is mandatory: development branches, a pull request, then Continuum or a
Linear branch. Nothing goes straight to `main`.

The reason for the trigger being the first Linear release rather than a date or
a feeling: a Linear release is the first moment something exists that a change
to Continuum can break, and review is worth paying for exactly when there is
something to protect.

**A second trigger may arrive first, and should be honoured if it does.** Once
the module repositories hold content and are mounted as submodules per
ADR-0016, a change in `Xmip` can break a repository that a different working
copy depends on. That is also something to protect, and it may happen before
any Linear release exists.

Until then, the discipline that replaces review is the one already in force:
`cargo fmt`, `cargo clippy -D warnings` and `Invoke-Pester ./tests` before every
commit, and the architectural change permission recorded in
`architectural-change-permission.md`.

## Rules

1. `main` is Xmip Continuum.
2. Continuum is the source of current project truth.
3. Linear releases are cut from Continuum.
4. Continuum may evolve.
5. Linear must be reproducible.
6. Documentation-first architecture decisions may enter Continuum before implementation.
7. A Linear release must not redefine the architecture independently of Continuum.
8. Until the first Linear release exists, commits may go directly to Continuum.
   After it, they may not: development branch, pull request, then Continuum or
   Linear.

## Intent

The terms are intended to separate two concerns:

- how Xmip evolves,
- how Xmip is released.

Continuum describes evolution.

Linear describes release.
