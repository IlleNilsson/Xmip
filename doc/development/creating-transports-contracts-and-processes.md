# Creating transports, contracts and processes

A task-oriented guide for a developer adding to Xmip. It assumes you have read
`doc/architecture/repository-model.md` (why modules mount where they do) and
`doc/governance/rust-style.md` (the rules the tests enforce).

## The mental model: two are code, one is configuration

| You want to add | What it is | Where it lives |
|---|---|---|
| **A transport** (Kafka, MQTT, S3…) | Rust code — a `Transport` implementation | its own **repo + module** |
| **A contract** (CSV, JSON, EDIFACT…) | Rust code — a `Contract` implementation | its own **repo + module** |
| **A process** (a Receive→work→Send flow) | **configuration** of a node | the node's config document — **no repo** |

The first two are *technologies*: a repository and a module for each, sharing one
base, the way a subclass shares a base class. A **transport** is any implementer
of the `Transport` trait; a **contract**, of the `Contract` trait. Adding one is
lifting the base into a new repository and filling in the methods — a move, not a
rewrite.

A **process** is not built, it is *described*. You author it in the **Xmip
Operations** desktop app or directly in a node's configuration TOML; nothing is
compiled and no repository is created.

---

## Adding a transport

The step-by-step guide lives with the capability it implements:
`module/capability/transport/doc/adding-a-transport.md`.

---

## Adding a contract

`module/capability/contract/doc/adding-a-contract.md`.

---

## Describing a process

A process is configuration, not code; what a node configuration document
holds and how it is authored is `module/platform/configure/doc/node-configuration.md`.

---

## Reference

| Thing | Base trait / type | Reference implementation |
|---|---|---|
| Transport | `Transport` (`transport/.src/protocol.rs`) | `file`, `tcp`, `http`, `smtp` in the capability |
| Contract | `Contract` (`contract/.src/lib.rs`) | `contract/csv/` |
| Xmip Process | `XmipProcessConfiguration` (`configure/src/lib.rs`) | a node configuration document |

- **Repository model:** `doc/architecture/repository-model.md`
- **What to build and in what order:** `doc/planning/open-problems.md`
- **How work lands:** `CLAUDE.md`, "How work lands"; the pipeline is
  `Xmip/Publish-XmipChange.ps1`
- **Testing a transport or contract for real:** the Playground, ADR-0028
