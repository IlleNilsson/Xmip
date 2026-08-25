# Xmip Naming Hierarchy

The grammar of a name, not the inventory of things named.

## The tree

```text
xmip
│
├── Xmip                                   the platform itself — outside the pattern
├── .github                                organisation defaults — outside the pattern
│
├── xmip-<single token>                    PLATFORM LEVEL
│   ├── xmip-core                          foundation contracts, identifiers, shared types
│   └── xmip-template                      scaffolding for new repositories
│                                          no provider, implements nothing
│
└── xmip-<provider>-<module>[-<standard>]  THE MODULE NAMESPACE
    │
    ├── provider = core ─────────────────  Xmip ships, hosts and supports it
    │   │
    │   ├── <module>                       xmip-core-path            the module itself
    │   │                                  xmip-core-transform       "  "
    │   │
    │   └── <module>-<standard>            xmip-core-path-xpath      Xmip's implementation
    │                                      xmip-core-transform-xslt  "  "
    │
    └── provider = anyone else ──────────  their licence, their support, no approval needed
        │
        ├── surface module                 xmip-acme-abi
        │   (abi, cli, powershell)         xmip-acme-cli
        │                                  xmip-acme-powershell
        │                                  nothing external to name — stops here
        │
        └── standard-keyed module          xmip-saxon-transform-xslt
            (everything else)              xmip-bosch-transport-can-bus
                                           xmip-acme-contract-volkswagen-multimedia
                                           standard is REQUIRED
```

## Walking down to a name

```text
1. Is it infrastructure, not a module?        → Xmip, .github            stop
2. Is it platform level, no provider?         → xmip-core, xmip-template stop
3. Who publishes it?                          → provider token
4. Which core module's trait?                 → module token
5. Is that module surface or standard-keyed?
      surface        (abi, cli, powershell)   → stop
      standard-keyed → is provider core?
                          yes, and it IS the module    → stop
                          otherwise                    → name the standard
```

## Reading a name back

Count the tokens after `xmip-`.

| tokens | what it is | provider slot | example |
|---|---|---|---|
| 0 | the platform | — | `Xmip` |
| 1 | platform level | none | `xmip-core`, `xmip-template` |
| 2 | core module, **or** a provider's surface extension | `core` → module<br>other → surface | `xmip-core-path`<br>`xmip-acme-cli` |
| 3+ | always an implementation | anyone | `xmip-saxon-transform-xslt` |

Two tokens is the only ambiguous count, and the provider token resolves it: `core` means a
core module, anything else means a surface extension.

## What each slot means

```text
xmip - acme - contract - volkswagen-multimedia
       ^^^^   ^^^^^^^^   ^^^^^^^^^^^^^^^^^^^^^
       1      2          3
```

| slot | tokens | question it answers | nature |
|---|---|---|---|
| 1 provider | exactly 1 | who publishes and supports this | **attributive** — a claim about authorship |
| 2 module | exactly 1 | which core module's trait it implements | **structural** — fixed vocabulary |
| 3 standard | 0 or more | what it implements or interoperates with | **descriptive** — names someone else's spec |

The attributive/descriptive split is the one that matters in practice. Slot 3 may freely name
a vendor, because naming the standard you talk to is simply accurate — `aws-sqs`,
`azure-service-bus`, `ibm-mq`, `oracle`, `mssql`, `opc-ua`, `volkswagen-multimedia`. Slot 2
states who made the thing, so a vendor name there is a claim, not a description.

The variable-length slot sits last, so a multi-token standard needs no special rule.

## Token rules

- shortest singular form; verb form where one exists — `identify`, not `identification`
- one meaning per token across the whole namespace
- lowercase, hyphen-separated, always
- a contract names the dialect, never the family — `edi-x12`, never `edi`
- where a vendor defines the dialect, the vendor token carries it:

```text
xmip-core-contract-mssql     T-SQL
xmip-core-contract-oracle    PL/SQL
xmip-core-contract-sql       ANSI SQL — the one with no vendor
```

## The ladder

Shortest to longest, every rung legal:

```text
Xmip                                        the platform
xmip-core                                   platform level
xmip-core-path                              a core module
xmip-acme-cli                               a provider's surface extension
xmip-core-path-xpath                        Xmip's implementation of a standard
xmip-saxon-transform-xslt                   a vendor's implementation
xmip-acme-contract-volkswagen-multimedia    multi-token standard
```

## Where the namespace stops

`core` is the endorsement boundary, and it is the only thing the name guarantees.

```text
xmip-core-*        Xmip ships it, hosts it, supports it, licenses it AGPL-3.0-or-later
everything else    someone else's licence, someone else's support, no approval required
```

A name says who published a module and what it implements. It does not say what tier the
module belongs to, how mature it is, or who depends on it — those live in
`xmip-architecture.json`, so that reclassifying something never means renaming it.

## Deliberately not in the name

| dimension | where it lives instead |
|---|---|
| tier — Foundation, Capabilities, Operations, Platform | `classificationModel` |
| standard-keyed or surface | `surfaceModules` |
| dependencies | `commonRepositories[i][4]` |
| technology parent | `technologyGroups` |
| maturity | `defaults.maturity` |
| direction — receive or send | the artifact, not the name |

Identity goes in the name. Classification goes in the manifest. Judgements move; identity
does not.
