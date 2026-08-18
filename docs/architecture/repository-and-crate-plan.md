# Xmip repository and crate plan

## Baseline

Before ADR-0010:

- 30 of 30 common repositories existed.
- 313 technology repositories were declared.
- none of the 313 technology repositories existed;
- Receive and Send declared 105 direction-specific technology entries with 44 duplicates;
- the monorepo contained 12 Rust crates and one concrete transport crate named `xmip-handler-file`.

## Naming

Names follow ADR-0011:

```text
xmip-<provider>-<module>-<standard>
```

`core` is the reserved provider and means Xmip itself. Any other provider publishes under its own name, licence and support, without needing permission.

The thirty existing common repositories are still named `xmip-<area>` and are renamed to `xmip-core-<area>` under a separate change. The target names are used below.

## Canonical ownership

| Concern | Core module | Implementation pattern | Primary crate |
|---|---|---|---|
| Representation | `xmip-core-message` | `xmip-<provider>-message-<representation>` | repository name |
| Contract | `xmip-core-contract` | `xmip-<provider>-contract-<technology>` | repository name |
| Path | `xmip-core-path` | `xmip-<provider>-path-<language>` | repository name |
| Transport | `xmip-core-transport` | `xmip-<provider>-transport-<technology>` | repository name |
| Logic | `xmip-core-logic` | `xmip-<provider>-logic-<technology>` | repository name |
| Receive | `xmip-core-receive` | no implementations | `xmip-core-receive` |
| Send | `xmip-core-send` | no implementations | `xmip-core-send` |

Handler is a runtime role, not a repository prefix.

Two implementations of one standard are expressible, which is the reason for the provider slot:

```text
xmip-core-contract-json-schema     shipped by Xmip
xmip-acme-contract-json-schema     shipped by someone else
```

## Creation order

### Wave 0: common boundaries

1. Create and scaffold `xmip-core-transport`.
2. Create and scaffold `xmip-core-logic`.
3. Refactor the common Message, Contract and Path interfaces in separate reviewed changes.
4. Adapt Receive and Send to `xmip-core-transport`.
5. Define the module-API adapter to the domain contracts.

### Wave 1: JSON

1. `xmip-core-message-json`
2. `xmip-core-path-json-pointer`
3. `xmip-core-contract-json-schema`

### Wave 2: XML

1. `xmip-core-message-xml`
2. `xmip-core-path-xpath`
3. `xmip-core-contract-xml-schema`

### Wave 3: initial Transport

1. `xmip-core-transport-file`
2. `xmip-core-transport-tcp`
3. `xmip-core-transport-http`
4. `xmip-core-transport-websocket`
5. `xmip-core-transport-mllp`

### Wave 4: Logic

1. `xmip-core-logic-http-api`
2. `xmip-core-logic-soap`
3. `xmip-core-logic-grpc`

### Native path model

Xmip’s own path model is implemented like any other, with `core` as the provider:

1. `xmip-core-path-dot`
2. `xmip-core-path-index`
3. `xmip-core-path-predicate`

Predicate covers value-based node selection, the `[. = 'value']` form. It evaluates rather than navigates, so it needs a comparison model and a decision on multi-node matches; it is the largest of the three.

## Migration

| Existing item | Disposition |
|---|---|
| `xmip-handler-file` monorepo crate | migrate into `xmip-core-transport-file` |
| `xmip-handler-*` planned repositories | do not create |
| `xmip-receive-*` technology declarations | replaced by `xmip-core-transport-<technology>` |
| `xmip-send-*` technology declarations | replaced by `xmip-core-transport-<technology>` |
| `present-*` Send entries | move to security or credential-presentation design |
| SOAP and gRPC transport entries | move to `xmip-core-logic-<technology>` |

Repository creation remains explicit. The manifest describes desired state; it does not authorize automatic creation, compilation, linking, testing or packaging.
