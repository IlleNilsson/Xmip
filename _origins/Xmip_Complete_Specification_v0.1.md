
# Xmip — Complete Technical Specification
Version: 0.1 (Foundational Specification)

---

# 1. Project Definition

Xmip (Cross‑platform Messaging & Integration Project) is a deterministic, artifact‑driven, cross‑platform messaging and integration engine designed for secure, regulated, and scalable environments.

Xmip operates primarily within clusters and supports inter‑cluster communication using the Xmip gRPC protocol.

Core principles:

- Deterministic execution
- Explicit isolation
- Artifact‑driven configuration
- Recoverable runtime
- Identity‑aware placement
- Offline‑first operation
- Rust‑only implementation

---

# 2. Language & Repository Model

## 2.1 Language

- Xmip Core and all artifacts are written in Rust.
- No mixed-language components inside the engine.
- External systems may use any language but are not artifacts.

## 2.2 Multi‑Repo Ecosystem

Core repo:
xmip/
  crates/
    xmip-interface
    xmip-core
    xmip-cli
  docs/

Artifact repos:
xmip-artifact-<name>

Each artifact:
- Independent versioning
- Depends only on xmip-interface
- Compiled as dynamic plugin
- No dependency on xmip-core

---

# 3. Artifact Model

## 3.1 Artifact

An artifact is a named, versioned configuration-defined unit declared in:

- template.xmip.toml
- cluster.xmip.toml
- node-specific xmip.toml

Artifacts include:

- receivePort
- receiveLocation
- process
- sendPortGroup
- sendPort
- sendLocation
- transportHandler
- contentHandler
- intentHandler
- contractHandler
- rule (routingRule / processRule)
- transformation
- event
- schedule

## 3.2 Artifact Instance

An artifact instance is a runtime execution of an artifact bound to:

- node
- host process
- configuration version

---

# 4. Node & Host Architecture

## 4.1 Node

A node runs Xmip Service.

Node capabilities:

- receiving
- executing
- sending
- serviceBus
- monitoring
- operations
- development

Nodes may have one or more capabilities.

## 4.2 Host Process

- Spawned by Xmip Service at startup
- Executes artifact instances
- Enforced by node capability
- Identity‑aware isolation

---

# 5. Runtime Lanes

Xmip execution lanes:

1. Receive
2. Process (optional)
3. Send
4. Void

Valid flows:

- Receive → Send
- Receive → Process → Send
- Receive → Void
- Receive → Process → Void

Assignments:
- Optional
- Occur only within Process

---

# 6. Message Model

Messages are immutable.

Routing does not create messages.

New messages are created only by:
- transformation
- assignment

Messages consist of:

- Metadata
- List of Sections (streams)

Sections:
- Stream‑based
- May reference previous section stream for storage efficiency
- Metadata attached

---

# 7. Identity & Isolation

Supported identity protocols:

- Kerberos
- mTLS
- OAuth2 / OIDC
- SAML
- API Key
- Username/Password
- Anonymous

Identity classes:

- highAssurance
- federated
- sharedSecret
- anonymous

Kerberos identity context includes:

- domain
- service principal
- delegation scope
- delegation allow‑list

Isolation rules:

- Incompatible identity contexts must not share host process.
- High‑assurance identities require node isolation in regulated profile.
- Violations block artifact startup.
- Violations logged and reported.

---

# 8. Security Profiles

- standard
- enterprise
- regulated

Regulated enforces strict identity isolation and fail‑closed behavior.

---

# 9. Sequential Enforcement

Sequential sources (FILE, FTP, FTPS, SFTP):

- Durable claim model
- Lease mechanism
- Checkpointed recovery

Sequential behavior enforced via state, not process placement.

---

# 10. Service Bus

Internal service bus:

- Durable queues
- Artifact‑declared lanes
- Restart recoverable
- Exactly‑once where possible
- At‑least‑once when external guarantees required

---

# 11. Observability

Four pillars:

- Logging
- Tracing
- Metrics
- Tracking (optional)

All addressed using Xmip URI.

---

# 12. Xmip URI

RFC 3986 compliant:

xmip://[userinfo@][host][:port]/path?query#fragment

Defaults:

- Omit userinfo → caller identity
- Omit host → all nodes

Used for:

- Logs
- Traces
- Metrics
- Tracking
- Operations
- Reports

---

# 13. Reports

Mandatory reports:

- Firewall & Operations Report
- Identity & Isolation Compliance Report

Optional:

- Performance & Capacity Report
- Artifact Drill‑Down Report

---

# 14. Configuration Model

Configuration files:

- template.xmip.toml
- cluster.xmip.toml
- node-specific xmip.toml

Templates reusable.
Cluster defines global artifacts.
Node slice contains runtime‑specific subset.

---

# 15. Build & Distribution

Targets:

- Windows
- Linux
- macOS
- ARM (Raspberry Pi)
- Industrial/Defense hardware

Offline‑first build model.
CI advisory only.
Local build canonical.

---

# 16. Extension & Governance

Extensions may be:

- Open source
- Commercial

Rules:

- Must depend only on xmip-interface
- No reimplementation of core semantics
- No forking of core engine

Moderated contribution model.

---

# 17. Deterministic Principle

Xmip enforces:

- Deterministic placement
- Deterministic execution
- Deterministic recovery
- Deterministic isolation

---

# End of Specification
