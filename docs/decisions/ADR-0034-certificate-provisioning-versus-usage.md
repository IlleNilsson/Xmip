# ADR-0034: Certificate provisioning is separate from usage

- Status: Accepted
- Date: 2026-09-06
- Related: ADR-0033 (certificates on Receive and Send), ADR-0019 (the identity
  pipeline), ADR-0021 (current platforms), ADR-0028 (the offline Playground),
  deployment-model.md

## In brief

- Theme: Identity and security
- Subject: Where a certificate comes from is a separate, per-deployment question
- Name: Certificate provisioning versus usage
- Order: 6
- Concepts: Provisioning, usage; source, deployment

**Using a certificate and obtaining one are two different concerns. Usage —
mutual-TLS on Receive and Send — is uniform everywhere. Provisioning — how the
certificate arrives — is plural, and the source is chosen per deployment.**
Let's Encrypt is one provisioning source, for the public edge; it is not usage,
not the pipeline, and not universal.

## Context

The owner's framing, 2026-09-06, resolving where Let's Encrypt fits: *Xmip runs
on-premises with or without internet access, in the cloud, and on a tiny device.*
Those deployments do not share a way to obtain a certificate — a laptop with no
network cannot reach an ACME server; a private partner has no public domain to
validate — but they share how a certificate is used once present. Collapsing the
two is what made "proper Let's Encrypt in the Playground" look sensible when the
Playground is offline by design (ADR-0028) and Let's Encrypt needs public
reachability. Separated, the question answers itself.

## Decision

### 1. Three layers, kept apart

- **The pipeline** — Identification → Authentication → Authorization. Invariant,
  sectech-agnostic (ADR-0019).
- **Usage** — mutual-TLS on Receive and Send: a Location presents a certificate,
  the peer verifies it. A substrate under Authentication, and the *same code*
  everywhere Xmip runs.
- **Provisioning** — how the certificate got there. This is the layer that
  varies by deployment, and it is a set of interchangeable sources, never one.

### 2. Provisioning is a set of sources, chosen by deployment

| Deployment | Reachability | Provisioning source |
| --- | --- | --- |
| Cloud edge with a public domain | public | Let's Encrypt / ACME (domain-validated) |
| On-premises, private partners | private | an internal certificate authority + mutual-TLS |
| Managed cloud | platform | a platform issuer — KMS, cert-manager |
| On-premises without internet, laptop, the Playground | offline | a self-signed or stand-in certificate authority |
| A tiny device (Meadow-class) | provisioned into it | a certificate pushed in; no on-device ACME |

The estate's default for private, high-assurance partner integration is the
**internal CA + mutual-TLS** (`transport/http/tls.rs` already says so). Let's
Encrypt is prioritised for the **public-edge** source specifically (ADR-0033),
and adds nothing to the other rows.

### 3. A provisioner is its own abstraction

Provisioning gets an abstraction beside the mechanisms — a **provisioner** with
interchangeable sources — rather than being wired into the certificate mechanism
or the transport. Obtaining and renewing a certificate is not the same code as
proving one during a handshake, and a deployment swaps its source without
touching usage.

### 4. The Playground exercises usage, not public provisioning

The Playground is offline (ADR-0028), so it exercises **usage** — mutual-TLS on
Receive and Send over loopback, with a stand-in certificate authority — and it
already simulates **provisioning faults** ("ACME challenge failed", "certificate
expired"). It does not, and will not, perform real public issuance: there is no
public name on a laptop with no network for an authority to validate. Real ACME
and Let's Encrypt are exercised only where there is a public domain, which is a
deployment scenario outside the offline Playground.

## Consequences

- ADR-0033's build order stands for **usage** (server TLS, client-cert verify and
  present, the mutual-TLS/certificate authenticators). **Provisioning** — the
  ACME/Let's Encrypt client and the internal-CA source — is a separate track
  behind the provisioner abstraction, not a step in the usage chain.
- The Playground's certificate exercise, when built, uses a stand-in CA and is
  honest that it is not issuing publicly.
- No deployment scenario is left without a certificate story: each row of the
  table has a source.

## Provenance

The framing is the owner's, 2026-09-06: Xmip runs on-premises with or without
internet, in the cloud, and on a tiny device, and the certificate source differs
by deployment while its use does not. Clauses 1 to 4 are the assistant's drafting
of it, on the instruction to write the overall answer down.
