# Creating transports, contracts and processes

Two are code and one is configuration. A transport and a contract are each a
technology: a Rust repository and module beneath its capability, implementing
that capability's trait. An Xmip Process is described, not built: it is a
node's configuration, and no repository is created.

Each guide lives with the subject it describes (ADR-0020 clause 3):

| You want to add | Read |
| --- | --- |
| A transport (Kafka, MQTT, S3 ...) | `module/core/capability/transport/doc/adding-a-transport.md` |
| A contract (CSV, JSON, EDIFACT ...) | `module/core/capability/contract/doc/adding-a-contract.md` |
| An Xmip Process (a Receive, work, Send flow) | `module/core/platform/configure/doc/node-configuration.md` |

What every technology shares — how its repository is named, declared, created,
mounted and landed — is `doc/architecture/repository-model.md`, sections 2, 7,
8 and 10; the rules the tests enforce are `doc/governance/rust-style.md`; what
to build and in what order is `doc/planning/open-problems.md`; a transport or a
contract is proven in the Playground (ADR-0028, `module/core/test/playground/README.md`).
