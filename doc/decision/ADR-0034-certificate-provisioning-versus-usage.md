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
server can run locally — Let's Encrypt's own test server, Pebble, speaks the
protocol; so do on-premises certificate authorities — he ruled: *ACME has to be
incorporated both locally and internetwise for Xmip.*

1. **Provisioning is a capability, `xmip-core-provision`**, mounted at
   `module/core/capability/provision` (ADR-0016), with a technology per source:
   `acme`, `internal-ca`, `self-signed` and `platform`. Clause 3's provisioner is
   this capability's trait; usage stays where ADR-0033 put it (the owner,
   2026-09-24).
2. **ACME is one technology for both reaches.** It speaks RFC 8555 to whatever
   ACME directory a node's configuration names: a server on the premises, or
   Let's Encrypt over the internet. The first row of clause 2's table is no
   longer the only one ACME serves: an on-premises estate with its own ACME
   server provisions through it too.
3. **The Playground tests identity twice**, as two tests of the `Core.Playground`
   suite rather than one stage of the round trip:
   - **`identity-local`** — on-premises: a node obtains its certificate by ACME
     from a local ACME server the Playground runs, and presents it on mutual
     TLS. No internet, repeatable, on every node.
   - **`identity-online`** — a node that declares itself online (ADR-0045,
     ADR-0056) obtains its certificate by ACME over the internet, and presents
     it. It runs only on a node that declares online.
4. **Clause 4 is amended.** The Playground still does not issue publicly from a
   laptop with nothing to prove, which is what clause 4 guarded; but it does
   perform real ACME issuance, locally always, and over the internet where a
   node is online.

Open problem 27 holds the work.
