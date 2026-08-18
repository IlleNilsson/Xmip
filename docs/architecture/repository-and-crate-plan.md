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
xmip-<provider>-<standard>-<module>
```

`core` is the reserved provider and means Xmip itself. Any other provider publishes under its own name, licence and support, without needing permission.

The thirty existing common repositories are still named `xmip-<area>` and are renamed to `xmip-core-<area>` under a separate change. The target names are used below.

## Canonical ownership

| Concern | Core module | Implementation pattern | Primary crate |
|---|---|---|---|
| Representation | `xmip-core-message` | `xmip-<provider>-<representation>-message` | repository name |
| Contract | `xmip-core-contract` | `xmip-<provider>-<technology>-contract` | repository name |
| Path | `xmip-core-path` | `xmip-<provider>-<language>-path` | repository name |
| Transport | `xmip-core-transport` | `xmip-<provider>-<technology>-transport` | repository name |
| Logic | `xmip-core-logic` | `xmip-<provider>-<technology>-logic` | repository name |
| Receive | `xmip-core-receive` | no implementations | `xmip-core-receive` |
| Send | `xmip-core-send` | no implementations | `xmip-core-send` |

Handler is a runtime role, not a repository prefix.

Two implementations of one standard are expressible, which is the reason for the provider slot:

```text
xmip-core-json-schema-contract     shipped by Xmip
xmip-acme-json-schema-contract     shipped by someone else
```

## Creation order

### Wave 0: common boundaries

1. Create and scaffold `xmip-core-transport`.
2. Create and scaffold `xmip-core-logic`.
3. Refactor the common Message, Contract and Path interfaces in separate reviewed changes.
4. Adapt Receive and Send to `xmip-core-transport`.
5. Define the module-API adapter to the domain contracts.

### Wave 1: JSON

1. `xmip-core-json-message`
2. `xmip-core-json-pointer-path`
3. `xmip-core-json-schema-contract`

### Wave 2: XML

1. `xmip-core-xml-message`
2. `xmip-core-xpath-path`
3. `xmip-core-xml-schema-contract`

### Wave 3: initial Transport

1. `xmip-core-file-transport`
2. `xmip-core-tcp-transport`
3. `xmip-core-http-transport`
4. `xmip-core-websocket-transport`
5. `xmip-core-mllp-transport`

### Wave 4: Logic

1. `xmip-core-http-api-logic`
2. `xmip-core-soap-logic`
3. `xmip-core-grpc-logic`

## Migration

| Existing item | Disposition |
|---|---|
| `xmip-handler-file` monorepo crate | migrate into `xmip-core-file-transport` |
| `xmip-handler-*` planned repositories | do not create |
| `xmip-receive-*` technology declarations | replaced by `xmip-core-<technology>-transport` |
| `xmip-send-*` technology declarations | replaced by `xmip-core-<technology>-transport` |
| `present-*` Send entries | move to security or credential-presentation design |
| SOAP and gRPC transport entries | move to `xmip-core-<technology>-logic` |

Repository creation remains explicit. The manifest describes desired state; it does not authorize automatic creation, compilation, linking, testing or packaging.
