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

## Rules

1. `main` is Xmip Continuum.
2. Continuum is the source of current project truth.
3. Linear releases are cut from Continuum.
4. Continuum may evolve.
5. Linear must be reproducible.
6. Documentation-first architecture decisions may enter Continuum before implementation.
7. A Linear release must not redefine the architecture independently of Continuum.

## Intent

The terms are intended to separate two concerns:

- how Xmip evolves,
- how Xmip is released.

Continuum describes evolution.

Linear describes release.
