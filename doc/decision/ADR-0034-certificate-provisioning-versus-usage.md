# ADR-0034: Certificate provisioning is separate from usage

- Status: Accepted
- Date: 2026-09-06
- Amended: 2026-09-24 — provisioning is a capability, `xmip-core-provision`;
  ACME is used on-premises against a local ACME server and over the internet;
  the Playground tests both, `identity-local` and `identity-online`
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
Encrypt is prioritized for the **public-edge** source specifically (ADR-0033),
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

## Amendment, 2026-09-24: ACME on-premises and online, and a test of each

The owner, 2026-09-24: *The identity test has to be split into two. One local,
on-prem version and one using ACME when a node is online.* Told that an ACME
server can run locally, he ruled: *ACME has to be incorporated both locally and
internetwise for Xmip*; then *we have an online switch for nodes: if a node is
online use Let's Encrypt, otherwise internal emulated ACME service*; and, of
that service: *step-ca is only for test. The end user will choose their CA.*

1. **Provisioning is a capability, `xmip-core-provision`**, mounted at
   `module/core/capability/provision` (ADR-0016), with a technology per source:
   `acme`, `internal-ca`, `self-signed` and `platform`. Clause 3's provisioner is
   this capability's trait; usage stays where ADR-0033 put it.
2. **ACME is one technology for both reaches**, speaking RFC 8555 to whatever
   ACME directory it is pointed at. **The node's online switch chooses the
   default** (ADR-0045, ADR-0056): a node that declares itself online uses
   Let's Encrypt; a node that does not uses the certificate authority its end
   user configures — any ACME service on the premises, or an internal CA. The
   end user chooses their CA; Xmip ships none for production.
3. **The Playground tests identity twice**, as two tests of the
   `Core.Playground` suite rather than one stage of the round trip:
   - **`identity-local`** — a node that is not online obtains its certificate
     by ACME from **step-ca** (Smallstep, Apache-2.0), which the Playground runs
     on the machine, and presents it on mutual TLS. No internet, repeatable, on
     every node. step-ca is the test's certificate authority only (the owner,
     2026-09-24); nothing in a production node depends on it.
   - **`identity-online`** — a node that declares itself online obtains its
     certificate by ACME from Let's Encrypt, and presents it.
4. **Clause 4 is amended.** The Playground still does not issue publicly from a
   laptop with nothing to prove, which is what clause 4 guarded; but it does
   perform real ACME issuance: against step-ca always, and against Let's
   Encrypt where a node is online.

Open problem 27 holds the work.
