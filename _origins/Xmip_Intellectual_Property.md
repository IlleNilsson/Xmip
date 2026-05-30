
# Xmip Intellectual Property Export

This document captures the intellectual property, decisions, and architectural agreements developed in the ChatGPT session.

---

## Core Definition
Xmip is a cross-platform messaging and integration project focused on deterministic, artifact-driven execution across nodes and environments.

Xmip operates primarily within clusters and supports inter-cluster communication using the Xmip gRPC protocol.

---

## Language & Repositories
- Xmip is Rust-only.
- Multi-repo ecosystem:
  - Core repo: Xmip engine (Rust workspace)
    - xmip-interface (stable contract)
    - xmip-core (runtime/engine)
    - xmip-cli (CLI)
  - One repo per artifact: xmip-artifact-<name>
- Artifacts depend only on xmip-interface.
- Artifacts are dynamically loaded plugins.
- No Rust ABI dependency across boundaries.

---

## Artifacts
- Artifact = configuration-defined definition.
- Declared in:
  - template.xmip.toml
  - cluster.xmip.toml
  - node-specific xmip.toml
- Artifact Instance = runtime execution of an artifact.
- Handlers are artifacts:
  - transportHandler
  - contentHandler
  - intentHandler
  - contractHandler

Assignments:
- Optional
- Only occur inside processes

---

## Runtime Model
- Nodes run Xmip Service.
- Xmip Service spawns host processes at startup.
- Node types:
  - receiving
  - executing
  - sending
  - serviceBus
  - monitoring
  - operations
  - development
- Node types constrain host processes (firewall & latency guarantees).

Lanes:
- Receive
- Process (optional)
- Send
- Void

---

## Pub/Sub, Rules, Transformations
- Routing via REST-style routes + promoted properties.
- routingRule (pub/sub)
- processRule (inside processes)
- Transformations may occur in receive, process, or send.
- Routing never creates new messages.

---

## Identity & Trust
- Trust is contextual acceptance.
- Identity protocols:
  - Kerberos
  - mTLS
  - OAuth2 / OIDC
  - SAML
  - API Key
  - Username/Password
  - Anonymous

Identity Classes:
- highAssurance
- federated
- sharedSecret
- anonymous

Kerberos specifics:
- Constrained vs Unconstrained delegation are distinct identity contexts.
- Different delegation scopes must not co-reside.
- Delegation allow-lists form part of identity context.

Rules:
- Different identity contexts must not share host processes.
- High-assurance identities require node isolation in regulated mode.
- Violations block startup, are logged, and appear in reports.

---

## Reports
- Firewall & Operations Report
- Identity & Isolation Compliance Report (mandatory)

---

## Observability
- Logs
- Tracing
- Metrics
- Tracking (optional, policy-controlled)

All addressed using RFC 3986-compliant Xmip URIs.

---

## Xmip URI
xmip://[userinfo@][host][:port]/path?query#fragment

Defaults:
- Omit userinfo: caller identity
- Omit host: all nodes

Used for:
- Logs
- Tracing
- Metrics
- Tracking
- Operations
- Reports

---

## CI/CD & Contribution
- Git-centric, offline-first.
- Local build is canonical.
- CI is advisory.
- Contributions accepted by human moderation.
- Extensions (handlers, transformations, processes, tooling) may be commercial or open source.
- No forking or reimplementation of core semantics.

---

## Security Profiles
- standard (small orgs)
- enterprise
- regulated (government/military)

---

## Key Principle
Determinism, isolation, and recoverability are enforced by design, not convention.

---

End of export.
