
# Xmip — Current State Architecture & Specification
Version: Consolidated State Export

This document provides a complete, consolidated description of Xmip as currently defined.
It does not include historical reasoning — only the current architectural state.

---
# 1. Definition

Xmip (Cross-platform Messaging & Integration Project) is a deterministic, artifact-driven,
cross-platform messaging and integration engine designed for secure, regulated,
recoverable, and identity-aware execution across nodes and clusters.

Xmip operates primarily within clusters and supports inter-cluster communication
using the Xmip gRPC protocol.

Core architectural principles:

- Deterministic execution
- Explicit identity isolation
- Artifact-defined runtime
- Immutable message model
- Recoverable state
- Rust-only implementation
- Offline-first governance

---
# 2. Technology & Repository Model

## 2.1 Language
- Xmip core and all artifacts are implemented in Rust.
- No mixed-language runtime components.
- External systems may use other languages but are not artifacts.

## 2.2 Repository Structure

Xmip uses a multi-repo ecosystem.

Core repository:
xmip/
  crates/
    xmip-interface   (stable contract)
    xmip-core        (runtime engine)
    xmip-cli         (CLI entry point)
  docs/

Artifact repositories:
xmip-artifact-<name>

Rules:
- Artifacts depend only on xmip-interface.
- Artifacts are dynamically loaded plugins.
- Rust ABI is not relied upon across boundaries.
- Interface compatibility is enforced at load time.

---
# 3. Artifact Model

## 3.1 Artifact Definition

An artifact is a named, versioned, configuration-defined unit declared in:

- template.xmip.toml
- cluster.xmip.toml
- node-specific xmip.toml

Artifacts define behavior and runtime topology.

## 3.2 Artifact Instance

An artifact instance is the runtime execution of an artifact bound to:
- node
- host process
- configuration version

## 3.3 Artifact Types

Ports & Locations:
- receivePort
- receiveLocation
- process
- sendPortGroup
- sendPort
- sendLocation

Handlers:
- transportHandler
- contentHandler
- intentHandler
- contractHandler

Logic & Flow:
- rule (routingRule / processRule)
- transformation
- assignment (inside process only)

Eventing:
- event
- schedule

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

A node may carry one, some, or all capabilities.

Nodes are grouped into clusters.

## 4.2 Host Process

- Spawned by Xmip Service at startup.
- Executes artifact instances.
- Must align with node capability.
- Identity isolation enforced at host process boundary.

Host process spawning considers:
- node capability
- identity context
- configuration requirements

---
# 5. Runtime Execution Lanes

Xmip defines explicit runtime lanes:

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
- Only occur within a process

Execution style is artifact-defined and may be:
- Sequential
- Parallel
- Concurrent

Sequential enforcement is state-based and durable.

---
# 6. Message Model

Messages are immutable.

Routing does not create new messages.
New messages are created only by:
- transformation
- assignment

A message consists of:
- Metadata
- One or more sections (streams)

Sections:
- Stream-based
- Deserialized only when required
- May reference previous stream for storage efficiency
- Have metadata

Metadata includes creationInstance:
- type: port | assignment | transformation
- name
- nodeName
- clusterName
- timestamp (UTC)

Messages carry:
- logicalName
- route (REST-style path)
- promoted properties

---
# 7. Pub/Sub, Rules & Transformations

Routing:
- Based on route + promoted properties.
- routingRule used for pub/sub.
- processRule used within processes.

Transformations:
- May occur in receive, process, or send lane.
- Produce new immutable message.

---
# 8. Identity & Isolation

Supported identity protocols:

- Kerberos
- mutual TLS
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
- delegation allow-list

Isolation rules:
- Different identity contexts must not share host process.
- Regulated profile enforces node-level isolation for highAssurance.
- Violations block artifact startup.
- Violations logged and reported.

Trust:
- Trust is contextual acceptance of identity within defined boundary.

---
# 9. Security Profiles

Profiles:
- standard
- enterprise
- regulated

Regulated:
- strict isolation
- fail-closed
- mandatory compliance reporting

---
# 10. Service Bus & Runtime Storage

Internal service bus:
- Durable queues
- Artifact-declared lanes
- Restart recoverable
- Exactly-once where possible
- At-least-once where external system limits apply

Sequential sources:
- Durable claim model
- Lease-based locking
- Checkpointed recovery

---
# 11. Observability

Four pillars:

- Logging
- Tracing (begin/end spans)
- Metrics (aggregated, P95 etc.)
- Tracking (optional message payload persistence)

Metrics, tracing, tracking configurable per:
- cluster
- node
- artifact
- action

---
# 12. Xmip URI

RFC 3986 compliant:

xmip://[userinfo@][host][:port]/path?query#fragment

Defaults:
- Omit userinfo → caller identity assumed
- Omit host → cluster-wide

Used for:
- Logging
- Tracing
- Metrics
- Tracking
- Operations
- Reports

---
# 13. Reports

Mandatory:

- Firewall & Operations Report
- Identity & Isolation Compliance Report

Optional:

- Performance & Capacity Report
- Artifact End-to-End Drill-Down Report

Firewall report includes:
- TCP/UDP ports
- UNC paths (file-based locations)
- Protocol exposure

---
# 14. Configuration Model

Files:
- template.xmip.toml
- cluster.xmip.toml
- xmip.toml (node slice)

Templates reusable.
Cluster defines global artifacts.
Node slice defines runtime placement.

Artifacts are preloaded and precompiled at host process startup.

---
# 15. Build & Distribution

Targets:
- Windows
- Linux
- macOS
- ARM (Raspberry Pi)
- Industrial & defense hardware

Offline-first build.
CI advisory only.
Local build canonical.

---
# 16. Governance

- Git is system of record.
- Contributions moderated.
- Extensions may be open or commercial.
- Core semantics may not be forked or reimplemented.

---
# 17. Deterministic Principle

Xmip enforces:

- Deterministic placement
- Deterministic execution
- Deterministic isolation
- Deterministic recovery

---

End of current-state specification.
