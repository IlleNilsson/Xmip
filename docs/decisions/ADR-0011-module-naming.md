# ADR-0011: Module and repository naming

## Status

Accepted.

## Context

Three naming rules were in force at once and they disagreed.

ADR-0001 defines `xmip-handler-<technology>`. ADR-0010 defines capability-first patterns: `xmip-transport-<technology>`, `xmip-contract-<technology>`, `xmip-message-<representation>`, `xmip-path-<language>`, `xmip-logic-<technology>`. ADR-0004 was already marked superseded by a decision that was itself only proposed.

None of them can name two implementations of the same standard.

A standard usually has several implementations. XSLT has Saxon, libxslt and the .NET engine. JSON Schema has several validators. Under a capability-first pattern `xmip-contract-json-schema` can be claimed exactly once, and the second implementation has nowhere to live.

This matters because Xmip is built for third-party modules. An organisation conforms to Xmip traits and publishes under its own licence and its own support. A naming rule with no publisher slot cannot express that, and the boundary Xmip cares about is precisely the trait.

## Decision

One rule covers the whole namespace.

```text
xmip-<provider>-<standard>-<module>
```

| part | meaning | tokens |
|---|---|---|
| `provider` | who publishes it. `core` is reserved and means Xmip itself | exactly 1 |
| `standard` | the standard, technology, dialect or vendor implemented | 0 or more |
| `module` | the core module whose trait is implemented | 0 or 1 |

Provider and module are single tokens. Everything between them is the standard. Every name therefore resolves without a lookup table.

Only `core` may omit the standard. Any other provider must name what it implements.

```text
xmip-core-transform             core   ·  —         ·  transform     a core module
xmip-core-xslt-transform        core   ·  xslt      ·  transform     Xmip’s XSLT
xmip-saxon-xslt-transform       saxon  ·  xslt      ·  transform     Saxon’s XSLT
xmip-core-json-schema-contract  core   ·  json-schema ·  contract
xmip-core-http-transport        core   ·  http      ·  transport
```

### Token discipline

- shortest singular form; verb form where one exists — `identify`, not `identification`
- one meaning per token across the whole namespace
- a contract names the dialect, never the family
- where a vendor defines the dialect, the vendor token carries it

```text
xmip-core-mssql-contract     T-SQL
xmip-core-oracle-contract    PL/SQL
xmip-core-sql-contract       ANSI SQL — the one with no vendor
```

Bare `edi` and `hl7` are therefore not contract tokens. `edi-x12`, `edi-edifact` and `hl7-v2` are, because someone defines those.

### The `core` provider is the endorsement boundary

`xmip-core-*` is what Xmip ships, hosts and supports. Anything else names its own provider and carries its own licence, its own support and its own responsibility. No approval, no registration and no negotiation is required to publish one.

This is why the rule needs no enforcement mechanism. The name states who stands behind the module.

## Relationship to ADR-0010

ADR-0010 remains in force. Its architectural decisions stand unchanged:

- `xmip-receive` and `xmip-send` remain orchestration capabilities with no technology children;
- `xmip-transport` owns direction-neutral transport, and an implementation declares whether it supports receive, send or both;
- `xmip-logic` owns method and operation semantics;
- Contract owns implication, evaluation, descriptors and results; representation parsing belongs to Message; path execution belongs to Path;
- handler is a runtime module role, not a repository-name prefix;
- credential and identity presentation is not a transport technology.

Only the naming patterns in ADR-0010 clauses 3, 6, 7, 8 and 9 are superseded. The capability model they describe is retained and improved by it: collapsing the direction-specific technology groups removed 44 duplicate repositories, and that result is preserved here.

Translation:

| ADR-0010 | This ADR |
|---|---|
| `xmip-transport-file` | `xmip-core-file-transport` |
| `xmip-transport-http` | `xmip-core-http-transport` |
| `xmip-message-json` | `xmip-core-json-message` |
| `xmip-message-xml` | `xmip-core-xml-message` |
| `xmip-path-json-pointer` | `xmip-core-json-pointer-path` |
| `xmip-path-xpath` | `xmip-core-xpath-path` |
| `xmip-contract-json-schema` | `xmip-core-json-schema-contract` |
| `xmip-contract-xml-schema` | `xmip-core-xml-schema-contract` |
| `xmip-logic-soap` | `xmip-core-soap-logic` |
| `xmip-logic-grpc` | `xmip-core-grpc-logic` |

A second implementation of the same standard is now expressible, which was the point:

```text
xmip-core-json-schema-contract     shipped by Xmip
xmip-acme-json-schema-contract     shipped by someone else
```

## Supersedes

- ADR-0001, handler repository naming. A transport implementation is `xmip-core-<technology>-transport`, not `xmip-handler-<technology>`.
- ADR-0010, clauses 3, 6, 7, 8 and 9.

ADR-0001 clause `xmip-<core-area>` for core repositories is unaffected.

## Consequences

`xmip-transport` and `xmip-logic` join the core modules, taking the count from 30 to 32.

`xmip-receive` and `xmip-send` lose their technology children and become orchestration only, alongside route, resilience, assign, promote and demote.

A repository is the unit of source, build and release. A sub-module is the unit of loading and runtime upgrade. One repository may ship several sub-modules where they share an implementation — one driver, one dialect, one credential model, one test suite.

The manifest remains the registry. It is the only place that will know a third-party module exists.
