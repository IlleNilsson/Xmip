# Creating transports, contracts and processes

All three are code. A transport and a contract are each a technology: a Rust
repository and module beneath its capability, implementing that
capability's trait. A Work Process is declared in a node's configuration
and designed in VS Code, and what is designed is compiled at design time
into a native Module the node loads (ADR-0066); no repository is created
for it. Declaring one is
[built, in the assembled service](../architecture/estate-map.md#process-declaration); compiling and
running one are [decided, not built](../architecture/estate-map.md#process-execution).

None of them reaches a node by being installed beside it: `xmip-service`
links every technology it runs, and adding one means building it again with
`Build-XmipService`
([built, not in the assembled service](../architecture/estate-map.md#module-loading); each guide
below says what to change).

Each guide lives with the subject it describes (ADR-0020 clause 3):

| You want to add | Read |
| --- | --- |
| A transport (Kafka, MQTT, S3 ...) | `module/core/capability/transport/doc/adding-a-transport.md` |
| A contract (CSV, JSON, EDIFACT ...) | `module/core/capability/contract/doc/adding-a-contract.md` |
| A Work Process (its declaration, and what is not built) | `module/platform/configure/doc/node-configuration.md` |

What every technology shares — how its repository is named, declared, created,
mounted and landed — is `doc/architecture/repository-model.md`, sections 2, 7,
8 and 10; the rules the tests enforce are `doc/governance/rust-style.md`; what
to build and in what order is `doc/planning/open-problems.md`; a transport or a
contract is proven in the Playground (ADR-0028, `test/core/playground/README.md`).
