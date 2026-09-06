# Creating transports, contracts and processes

A task-oriented guide for a developer adding to Xmip. It assumes you have read
`docs/architecture/repository-model.md` (why modules mount where they do) and
`docs/governance/rust-style.md` (the rules the tests enforce).

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

## Part A — A new transport

### 1. The base you implement

`Transport` (`modules/capabilities/transport/src/protocol.rs`) — five methods,
and nothing in it names a protocol:

```rust
pub trait Transport {
    fn name(&self) -> &'static str;                          // the token in the repo name
    fn directions(&self) -> Directions;                      // receive, send, or both
    fn receive(&self) -> Result<Vec<Arrived>>;               // empty vec = nothing arrived
    fn send(&self, target: &str, bytes: &[u8]) -> Result<()>;
    fn claims(&self) -> Option<&dyn ResourceClaim> { None }  // exactly-once pickup (ADR-0024)
}
```

Never bring a protocol name into the transport *capability* — protocol code lives
only in its own technology repository (that is the rule that keeps the base
protocol-agnostic).

### 2. Create the repository and module

The repository is `xmip-core-transport-<name>`; it mounts as a submodule at
`modules/<name>` **inside the transport capability**, and it **depends on the
capability, never the reverse** (`repository-model.md`).

1. **Declare it** in `architecture.toml` under `[xmip.core.transport.<name>]`,
   with a `maturity` (`reserved` → `planned` → `scaffolded` → `supported`).
2. **Create the GitHub repo.** `gh repo create xmip-core-transport-<name> --public`
   — run this yourself; the assistant is blocked from creating repositories.
3. **Scaffold** from the working template — copy the layout of
   `modules/capabilities/contract/modules/csv/` (Cargo.toml, `src/lib.rs`,
   README, `rust-toolchain.toml`, LICENSE, tests). In `Cargo.toml`:
   ```toml
   [package]
   name = "xmip-core-transport-<name>"

   [dependencies]
   transport = { package = "xmip-core-transport", git = "…", branch = "main" }
   ```
4. **Implement** the trait in `src/lib.rs`. Keep `receive` honest: *nothing there
   is not an error* — an absent source returns an empty vector.
5. **Green it:** `cargo test` and `cargo clippy --all-targets -- -D warnings`.

### 3. Mount and land

```bash
# inside the transport capability repo
git -C modules/capabilities/transport submodule add \
    https://github.com/<you>/xmip-core-transport-<name> modules/<name>

# from the estate root
Import-Module ./Xmip/Xmip.psd1 -Force
xgit -m 'Add the <name> transport'
```

`xgit` (`Publish-XmipChange`) is nesting-aware: it tests and lands the technology,
records the gitlink in the capability, then pins the superproject — in that order.

### 4. Prove it

Add the transport to the **Playground**'s pingpong scenario (ADR-0028): one new
`RoundTrip` adapter, and it is exercised by every content contract at once,
timed, sized and fault-injected — not a new test, a new adapter.

---

## Part B — A new contract

Identical shape to a transport, against a different base. **`csv` is the
reference implementation** — read `modules/capabilities/contract/modules/csv/`
before starting; your module is that module with the format changed.

### The base you implement

`Contract` (`modules/capabilities/contract/src/lib.rs`):

```rust
pub trait Contract: Send + Sync {
    fn descriptor(&self) -> &ContractDescriptor;                       // id, version, representation
    fn identify(&self, stream: &Stream) -> Result<bool, ContractError>;   // is this my format?
    fn validate(&self, stream: &Stream) -> Result<ValidationResult, ContractError>;
}
```

`identify` answers "does this stream look like mine" (cheaply); `validate`
answers "and is it well-formed", returning `ValidationIssue`s rather than a bare
false so an operator sees *what* failed.

### Create, mount, land

Exactly as Part A, substituting `contract` for `transport`:

- repo `xmip-core-contract-<name>`, mounted at `modules/<name>` inside the
  contract capability;
- `Cargo.toml` depends on `contract = { package = "xmip-core-contract", … }`
  (and `stream`, for the `Stream` type);
- declare `[xmip.core.contract.<name>]` in `architecture.toml`;
- `gh repo create` (you) → scaffold → implement → `cargo test`/`clippy` → mount →
  `xgit`.

The Playground pairs every contract against every transport, so a new contract is
picked up by pingpong the same way a new transport is.

---

## Part C — A new process

A process is **configuration, not code**. There is no repository and nothing to
compile — you describe a node's work, and the runtime enacts it.

### What a process is made of

From `modules/platform/configure/src/lib.rs`:

- **`XmipProcessConfiguration`** — `name`, `start`, `execution_style`,
  `required_modules`, `xmip_subprocesses`, `extensions`.
- **`ExecutionStyle`** — `sequential` (default; one at a time, in order per key),
  `parallel`, or `concurrent` (throughput over ordering). This is the lever an
  operator raises when a node falls behind (the Playground's `daily` scenario).
- **`ConfiguredLocation`** — a Receive or a Send Location: a `name`, the
  `transport` module that moves it, and the `address` in that transport's own
  terms. A Receive Location runs the identity pipeline (identify → authenticate →
  authorize, ADR-0019); a Send Location presents identity (ADR-0033).

A process is the flow **Receive Location → process (and subprocesses) → Send
Location**, referencing transport and contract *modules* by name.

### Two ways to author it

1. **Xmip Operations (the desktop app)** — the intended path. Navigate the tree,
   add a process, set its execution style, add Receive and Send Locations that
   point at your transport and contract modules. The operator observes, reasons,
   then tweaks or adds a node.
2. **The configuration TOML directly** — the same document Xmip Operations reads
   and writes. Minimal shape:
   ```toml
   [service]
   name = "…"; cluster_name = "…"; node_name = "…"

   [[xmip_processes]]
   name = "invoices"
   start = true
   execution_style = "sequential"      # or "parallel" / "concurrent"
   required_modules = ["xmip-core-contract-csv"]

   [[receive_locations]]
   name = "drop"
   start = true
   transport = "xmip-core-transport-file"
   address = "/var/xmip/in/invoices"

   [[send_locations]]
   name = "forward"
   start = true
   transport = "xmip-core-transport-<name>"
   address = "…"
   ```

Validate the document with `configure::parse_toml`; the desktop editor validates
a half-built document rather than failing at line 1, so you can save work in
progress.

---

## Reference

| Thing | Base trait / type | Reference implementation |
|---|---|---|
| Transport | `Transport` (`transport/src/protocol.rs`) | `file`, `tcp`, `http`, `smtp` in the capability |
| Contract | `Contract` (`contract/src/lib.rs`) | `contract/modules/csv/` |
| Process | `XmipProcessConfiguration` (`configure/src/lib.rs`) | a node configuration document |

- **Repository model:** `docs/architecture/repository-model.md`
- **What to build and in what order:** `docs/planning/open-problems.md`
- **How work lands:** `CLAUDE.md`, "How work lands"; the pipeline is
  `Xmip/Publish-XmipChange.ps1`
- **Testing a transport or contract for real:** the Playground, ADR-0028
