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
xmip-<provider>-<module>-<standard>
```

| part | meaning | tokens |
|---|---|---|
| `provider` | who publishes it. `core` is reserved and means Xmip itself | exactly 1 |
| `module` | the core module whose trait is implemented | exactly 1 |
| `standard` | the standard, technology, dialect or vendor implemented | 0 or more |

Provider and module are single tokens. Everything after them is the standard. Two tokens after `xmip-` is a name with no standard: a core module where the provider is `core`, a provider's extension of a surface module otherwise. Three or more is always an implementation.

A name with a single token after `xmip-` is **platform level**. It carries no provider and
implements nothing, so it is not a module name at all:

```text
xmip-core        foundation contracts, identifiers and shared types
xmip-template    scaffolding for new repositories
```

Two repositories sit outside the pattern entirely, because they are not named for what they
contain: `Xmip`, the platform itself, and `.github`, the organisation defaults.

This ADR governs module names. It does not govern infrastructure, and forcing infrastructure
into the pattern produces worse names than leaving it out. `xmip-repo-template` was
considered and rejected for exactly that reason: two tokens after `xmip-` reads as provider
`repo` and module `template`, and there is no such provider and no such trait. One token
keeps it level with `xmip-core`, which is what it is. Every name therefore resolves without a lookup table, and a multi-token standard needs no special handling because it sits at the end.

Whether a name carries a standard is a property of the module, fixed once and recorded in
the manifest, not a choice made per repository.

A module is **standard-keyed** when its implementations are defined by someone else's
specification. `transform`, `contract`, `path`, `transport`, `authenticate` and the rest
are standard-keyed, and any provider other than `core` must name the standard —
`xmip-saxon-transform-xslt`, never `xmip-saxon-transform`. Only `core` may omit it, because
`xmip-core-transform` is the module itself rather than an implementation of anything.

A module is **surface** when a provider extends Xmip's own surface rather than implementing
an external specification. `abi`, `cli` and `powershell` are surface modules. They take a
provider and stop:

```text
xmip-core-abi          xmip-core-cli          xmip-core-powershell
xmip-acme-abi          xmip-acme-cli          xmip-acme-powershell
```

There is no standard to name, so requiring one would force an invented token. `xmip-acme-cli`
is already unambiguous: it is Acme's contribution to the command surface. A provider
publishes one of each at most, which is the accepted cost of the shorter name.

Surface modules are open to any provider on the same terms as every other module. They are
not core-only, and no approval is needed to publish one.

```text
xmip-core-transform                core   ·  transform  ·  —             a core module
xmip-core-transform-xslt           core   ·  transform  ·  xslt          Xmip’s XSLT
xmip-saxon-transform-xslt          saxon  ·  transform  ·  xslt          Saxon’s XSLT
xmip-core-contract-json-schema     core   ·  contract   ·  json-schema
xmip-core-path-xpath               core   ·  path       ·  xpath
xmip-core-transport-http           core   ·  transport  ·  http
```

### Why the module comes second

Putting the module last produces names that repeat themselves when the standard already contains the module word:

```text
xmip-core-xpath-path        xmip-core-path-xpath
xmip-core-jsonpath-path     xmip-core-path-jsonpath
xmip-core-json-pointer-path xmip-core-path-json-pointer
```

The right column also sorts by module, so every `xmip-core-path-*` groups together in a listing, and it keeps the variable-length part at the end where it belongs.

### Token discipline

- shortest singular form; verb form where one exists — `identify`, not `identification`
- one meaning per token across the whole namespace
- a contract names the dialect, never the family
- where a vendor defines the dialect, the vendor token carries it

```text
xmip-core-contract-mssql     T-SQL
xmip-core-contract-oracle    PL/SQL
xmip-core-contract-sql       ANSI SQL — the one with no vendor
```

Bare `edi` and `hl7` are therefore not contract standards. `edi-x12`, `edi-edifact` and `hl7-v2` are, because someone defines those.

### Native implementations are still implementations

Xmip’s own path model — dot navigation, index navigation and predicates — is implemented by `xmip-core-path-dot`, `xmip-core-path-index` and `xmip-core-path-predicate`. Being native means `provider = core`, not that the module is absent from the namespace.

### The `core` provider is the endorsement boundary

`xmip-core-*` is what Xmip ships, hosts and supports. Anything else names its own provider and carries its own licence, its own support and its own responsibility. No approval, no registration and no negotiation is required to publish one.

This is why the rule needs no enforcement mechanism. The name states who stands behind the module.

### A worked example: CAN bus

`can-bus` is a transport standard, so it fills the standard slot like any other. The
provider slot is what lets the same standard have more than one implementation:

```text
xmip-core-transport-can-bus     Xmip's own
xmip-bosch-transport-can-bus    Bosch's, should Bosch ever publish one
```

CAN was developed by Robert Bosch GmbH, and the `bosch` provider token is set aside here for
that reason. If Bosch, or anyone acting for Bosch, wants to publish CAN modules for Xmip,
the token is theirs and Xmip will not use it for anything else.

**Xmip is not affiliated with, endorsed by, or sponsored by Robert Bosch GmbH.** No
`xmip-bosch-*` repository exists, and Xmip does not create repositories under another
organisation's name. The token appears in this document as an illustration of the provider
slot and nowhere else — it is deliberately absent from `commonRepositories`, which is the
list the reconcile script acts on. It will be removed on request from Bosch.

This is the general shape of the rule, not a special case. Any vendor whose name is the
obvious provider for a standard they originated is in the same position: the token is
reserved for them, and until they take it up, `core` is the only provider that ships.

## Relationship to ADR-0010

ADR-0010 remains in force. Its architectural decisions stand unchanged:

- `xmip-receive` and `xmip-send` remain orchestration capabilities with no technology children;
- `xmip-transport` owns direction-neutral transport, and an implementation declares whether it supports receive, send or both;
- `xmip-logic` owns method and operation semantics;
- Contract owns implication, evaluation, descriptors and results; representation parsing belongs to Message; path execution belongs to Path;
- handler is a runtime module role, not a repository-name prefix;
- credential and identity presentation is not a transport technology.

Only the naming patterns in ADR-0010 clauses 3, 6, 7, 8 and 9 are superseded. The capability model they describe is retained: collapsing the direction-specific technology groups removed 44 duplicate repositories, and that result is preserved here.

| ADR-0010 | This ADR |
|---|---|
| `xmip-transport-file` | `xmip-core-transport-file` |
| `xmip-transport-http` | `xmip-core-transport-http` |
| `xmip-message-json` | `xmip-core-message-json` |
| `xmip-message-xml` | `xmip-core-message-xml` |
| `xmip-path-json-pointer` | `xmip-core-path-json-pointer` |
| `xmip-path-xpath` | `xmip-core-path-xpath` |
| `xmip-contract-json-schema` | `xmip-core-contract-json-schema` |
| `xmip-contract-xml-schema` | `xmip-core-contract-xml-schema` |
| `xmip-logic-soap` | `xmip-core-logic-soap` |
| `xmip-logic-grpc` | `xmip-core-logic-grpc` |

The shape is close to ADR-0010 — the difference is the provider slot, which is what lets a second implementation exist:

```text
xmip-core-contract-json-schema     shipped by Xmip
xmip-acme-contract-json-schema     shipped by someone else
```

## Supersedes

- ADR-0001, handler repository naming. A transport implementation is `xmip-core-transport-<technology>`, not `xmip-handler-<technology>`.
- ADR-0010, clauses 3, 6, 7, 8 and 9.

ADR-0001 clause `xmip-<core-area>` for core repositories is unaffected.

## Consequences

`xmip-transport` and `xmip-logic` join the core modules, taking the count from 30 to 32.

`xmip-receive` and `xmip-send` lose their technology children and become orchestration only, alongside route, resilience, assign, promote and demote.

A repository is the unit of source, build and release. A sub-module is the unit of loading and runtime upgrade. One repository may ship several sub-modules where they share an implementation — one driver, one dialect, one credential model, one test suite.

The manifest remains the registry. It is the only place that will know a third-party module exists.
