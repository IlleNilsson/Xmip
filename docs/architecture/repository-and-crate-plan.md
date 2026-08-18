# Xmip repository and crate plan

## Baseline

Before ADR-0005:

- 30 of 30 common repositories existed.
- 313 technology repositories were declared.
- none of the 313 technology repositories existed;
- Receive and Send declared 105 direction-specific technology entries with 44 duplicates;
- the monorepo contained 12 Rust crates and one concrete transport crate named `xmip-handler-file`.

## Canonical ownership

| Concern | Common repository | Technology repository pattern | Primary crate |
|---|---|---|---|
| Representation | `xmip-message` | `xmip-message-<representation>` | repository name |
| Contract | `xmip-contract` | `xmip-contract-<technology>` | repository name |
| Path | `xmip-path` | `xmip-path-<language>` | repository name |
| Transport | `xmip-transport` | `xmip-transport-<technology>` | repository name |
| Logic | `xmip-logic` | `xmip-logic-<technology>` | repository name |
| Receive | `xmip-receive` | no technology children | `xmip-receive` |
| Send | `xmip-send` | no technology children | `xmip-send` |

Handler is a runtime role, not a repository prefix.

## Creation order

### Wave 0: common boundaries

1. Create and scaffold `xmip-transport`.
2. Create and scaffold `xmip-logic`.
3. Refactor the common Message, Contract and Path interfaces in separate reviewed changes.
4. Adapt Receive and Send to `xmip-transport`.
5. Define the module-API adapter to the domain contracts.

### Wave 1: JSON

1. `xmip-message-json`
2. `xmip-path-json-pointer`
3. `xmip-contract-json-schema`

### Wave 2: XML

1. `xmip-message-xml`
2. `xmip-path-xpath`
3. `xmip-contract-xml-schema`

### Wave 3: initial Transport

1. `xmip-transport-file`
2. `xmip-transport-tcp`
3. `xmip-transport-http`
4. `xmip-transport-websocket`
5. `xmip-transport-mllp`

### Wave 4: Logic

1. `xmip-logic-http-api`
2. `xmip-logic-soap`
3. `xmip-logic-grpc`

## Migration

| Existing item | Disposition |
|---|---|
| `xmip-handler-file` monorepo crate | migrate into `xmip-transport-file` |
| `xmip-handler-*` planned repositories | do not create |
| `xmip-receive-*` technology declarations | replaced by `xmip-transport-*` |
| `xmip-send-*` technology declarations | replaced by `xmip-transport-*` |
| `present-*` Send entries | move to security or credential-presentation design |
| SOAP and gRPC transport entries | move to `xmip-logic-*` |

Repository creation remains explicit. The manifest describes desired state; it does not authorize automatic creation, compilation, linking, testing or packaging.
