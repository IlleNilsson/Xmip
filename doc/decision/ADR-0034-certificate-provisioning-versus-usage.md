# ADR-0034: Certificate provisioning is separate from usage

- Status: Accepted
- Date: 2026-09-06
- Amended: 2026-09-24 — provisioning is a capability, `xmip-core-provision`;
  ACME is used on-premises against a local ACME server and over the internet;
  the Playground tests both, `identity-local` and `identity-online`
- Amended: 2026-10-13 — Let's Encrypt is an option a node chooses, never a
  default; the capability and three of its sources are built
- Amended: 2026-10-15 — a third purpose, `operator`: a person's surface makes
  its own key and request, and the cluster's authority signs it
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
network cannot reach an ACME server; a private Party has no public domain to
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
| On-premises, private Parties | private | an internal certificate authority + mutual-TLS |
| Managed cloud | platform | a platform issuer — KMS, cert-manager |
| On-premises without internet, laptop, the Playground | offline | a self-signed or stand-in certificate authority |
| A tiny device (Meadow-class) | provisioned into it | a certificate pushed in; no on-device ACME |

The estate's default for private, high-assurance Party integration is the
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

## Amendment, 2026-10-13: Let's Encrypt is an option, never the default

Clause 2 of the amendment above let a node's online switch choose Let's
Encrypt by default. The owner, 2026-10-13, told that Let's Encrypt has issued
no client authentication since 2026-07-08 and so cannot prove a node between
nodes: *As an option.* So no source is a default: a node's configuration
names its source and, for ACME, its directory, and `online = true` still
only permits (ADR-0045 clause 3). Let's Encrypt serves what Parties reach;
between nodes the cluster's own authority (`internal-ca`) issues, over ACME.

Built the same day: `xmip-core-provision` with `acme`, `internal-ca` and
`self-signed`; `platform` stays reserved. What `identity-local` proves — a
node not online obtains its certificate by ACME and presents it on mutual
TLS — is proved in `internal-ca`'s own tests against the authority's ACME
server, offline, with nothing installed; the Playground's `identity-local`
test, and whether it still runs step-ca, are not built and remain the
owner's to say. ADR-0033's amendment of 2026-10-13 holds the detail.

## Amendment, 2026-10-15: a person's certificate, the `operator` purpose

**Provenance.** The owner approved the design on 2026-10-15, *Go ahead*: a
new provisioning purpose `operator`, a certificate for client authentication
only, for a person's surface — the phone first (ADR-0014, amendment
2026-10-14, where the phone follows nodes over their operate listener inside
Xmip's mutual TLS); the surface makes its own key pair and a certificate
signing request (PKCS #10), and the cluster's own authority (`internal-ca`)
signs it after an approval out of band. What follows beyond that is the
assistant's draft, each point marked, for the owner to strike.

1. **A third purpose.** `receive` and `node` are what a node obtains;
   `operator` is what a person presents. Its certificate carries client
   authentication alone, no DNS name, and is never obtained by a node
   through a source: it is signed from a request (`Purpose::Operator`, its
   rules in one place, `purpose.rs` in `xmip-core-provision`).
2. **Its subject is the person** — the assistant's draft. ADR-0009 (amendment
   2026-10-03, note of 2026-10-12): *who acted is what the connection proved*,
   *the subject of the client certificate the handshake checked*, and on the
   operate listener *every caller is proven by its client certificate*; the
   listener renders that subject as `CN=<value>`. So the subject is one
   common name, the person's name as their directory knows it — a user
   principal name, `alice@example.org`, where there is one (ADR-0054) — one
   to 64 characters, with no control character and none RFC 4514 escapes, so
   the caller every renderer shows is exactly `CN=<person>`. A distinguished
   name typed as the name is refused.
3. **What a request may ask.** The authority verifies the request's own
   signature under the key it carries and refuses any extension asking for
   more than the purpose's certificate carries: another extended key usage,
   a key usage beyond a digital signature, an authority's constraint,
   alternative names, any other extension. What the certificate may do is
   the purpose's, never the request's (`Issuer::sign`).
4. **Where it is configured** — the assistant's draft.
   `[provision.operator]` on the node whose authority signs: `authority`, the
   folder the cluster's authority is kept in (`authority.key`,
   `authority.pem`, relative to the configuration file), and `lifetime`, how
   long the certificate is valid — **default thirty days**, a new key with a
   default, set per cluster and per node in the Cluster TOML like every
   other assumption (ADR-0031, amendment 2026-10-03). The table names no
   `source`.
5. **Where the code is** — the assistant's draft, because of a rule in
   `architecture.toml`: *Platform services must not depend on specific
   Technology repositories.* The surfaces reach Rust through the runtime's
   library (ADR-0014, amendment 2026-10-12), which may not link
   `internal-ca`. So what an authority signs and how — the request read and
   verified, the purpose's admission, the certificate written — is the
   capability's, `xmip-core-provision`'s `Issuer`, placed once; `internal-ca`
   keeps and makes the authority and signs through that same `Issuer`
   (`Authority::sign`), and the runtime's export signs through it too. The
   capability's own words since 2026-10-13 already said the technologies
   that request, issue or sign hold none of it.
6. **Approval out of band** — the assistant's draft. Running the signing is
   the approval: whoever may read the authority's key signs, after checking
   by other means that the request is the person's. Every surface audits the
   act (ADR-0062).
7. **The surfaces.** `xmip_operate.h` section 19: `xmip_operator_request_v1`
   (a fresh P-256 key and the request, JSON of two PEM texts), carried by
   every build, the phone's remote build too; `xmip_operator_sign_v1` (a
   request signed by the authority a node configuration names), a node's
   build only. `Xmip.Abi`'s `RuntimeCertificates` binds both;
   `Xmip.Surface`'s `OperatorCertificate` writes the files once, for
   `xmip-cli certificate --operator <person>` and `xmip-cli certificate
   <request> --sign <configuration>`, and for `New-XmipCertificate
   -Operator` and `New-XmipCertificate -Request -Configuration` — one new
   noun, `certificate`, since no existing one fitted: nothing provisioned
   on any surface before. The GUIs gain nothing in this change: no
   provisioning page exists to take it in a few lines.

Proved: in `xmip-core-provision` (an operator's request signed for client
authentication alone naming the person; a request asking server
authentication, a host's name, an authority's constraint, a name with a
comma, and one whose signature was tampered with, each refused in words);
in `internal-ca` (a request signed by the kept authority and presented on
mutual TLS to the authority's own node); in the runtime (both exports); in
`Xmip.Abi.Test` (the crossing, the remote build making a request and
refusing to sign); in `Xmip.Surface.Test` (a signed request is the caller a
real operate listener proves, `CN=alice@example.org`, refused an act as
Observer); in `Xmip.Cli.Test` and the PowerShell module's Pester suite.

**Not yet.** The phone keeps its key as a PEM file: phase 2 makes the key in
the platform's keeper — the Android Keystore, the iOS keychain or Secure
Enclave — where it never leaves, which needs a request signed by that keeper
(`csr::information` and `csr::assemble` are the two halves, written for it)
and, through the ABI, an export of those halves; and the phone's TLS
presenting a key it cannot read. `xmip-service` reads no `[provision]` table
yet (open problem 27), so no node holds an authority on its own; the folder
`[provision.operator] authority` names is the one `internal-ca` keeps.
Revocation of an operator's certificate is not decided.
