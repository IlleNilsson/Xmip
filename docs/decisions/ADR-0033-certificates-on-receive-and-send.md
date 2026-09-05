# ADR-0033: Certificates on Receive and Send, Let's Encrypt prioritised

- Status: Accepted
- Date: 2026-09-05
- Related: ADR-0019 (identity, parties, direction), ADR-0022 (identity classes),
  ADR-0010 (contract and transport boundaries), ADR-0028 (the Playground's
  injected faults)

## In brief

- Theme: Identity and security
- Subject: Certificate identity is the first mechanism built, provisioned by ACME
- Name: Certificates on Receive and Send
- Order: 5
- Concepts: Certificates, mutual-TLS; ACME, Let's Encrypt

**Certificate identity is the first authentication mechanism Xmip implements,
on both directions: a Receive Location verifies the certificate a caller
presents, and a Send Location presents one. And provisioning those certificates
prioritises ACME — Let's Encrypt — among the identity protocols.** Twenty-eight
mechanisms are declared and none is built (the survey, 2026-09-05); this picks
the order, starting with certificates.

## Context

The owner's requirement, 2026-09-05: *incorporate certificates on Receive and
Send, and make Let's Encrypt a priority amongst the identity protocols.* The
identity model is thorough and unimplemented — `core/mechanism/declared.rs` names
`mutual-tls`, `certificate`, `oauth2`, `password` and the rest; the
`Authenticator` gate and `Acceptance` (closed set) are built; no concrete
authenticator exists. This decides what gets built first.

Where certificate proof lives matters. A `mutual-tls` handshake is proven at the
transport layer — the TLS stack verifies the peer certificate before a byte of
content is read — so the authenticate gate's job for it is to record what the
transport already proved, not to redo cryptography. `certificate` (an X.509
outside a TLS handshake — S/MIME in AS2, an OPC UA instance certificate) is
proven where the content is. The transport crate carries a client-only rustls
path today (`http/tls.rs`); server TLS and client-certificate presentation are
not built.

## Decision

### 1. Certificate identity is built first, both directions

- **Receive** — a Receive Location can require and verify a peer certificate.
  For `mutual-tls` the transport's TLS server requests and verifies the client
  certificate during the handshake and hands the proven subject to the gate; for
  `certificate` the presented X.509 is verified where the content arrives. The
  verified subject becomes the [`Presented`] value the `Acceptance` gate checks.
- **Send** — a Send Location presents a client certificate: the transport's TLS
  client is configured with a key pair, so the far end can authenticate Xmip.

The gate and `Acceptance` are unchanged; what is new is the transport growing a
**server TLS** path and **client-certificate** presentation, and two concrete
`Authenticator`s (`mutual-tls`, `certificate`) that surface what was proven.

### 1a. Identification, Authentication, Authorization stay three stages

A certificate touches all three, and they are not the same question — the estate
keeps them in three capabilities and this work keeps that line (ADR-0019):

- **Identification** (`xmip-core-identify`) — *who is claimed.* The certificate's
  subject or SAN is a claimed identity, a [`Presented`] value. Extracting it is
  not proving it.
- **Authentication** (`xmip-core-authenticate`) — *does the claim hold.* The TLS
  handshake or the certificate chain proves the subject cryptographically →
  `Verified::Proven`. This is the substrate the server-TLS work in clause 1
  builds.
- **Authorization** (`xmip-core-authorize`) — *what may that proven party do.*
  Whether it may use this Receive or Send Location, this operation. A proven
  identity is not a permission (ADR-0009).

A certificate that is identified but not authenticated is a claim, not a caller;
a caller that is authenticated but not authorized is refused with the reason. The
three never collapse into one check, and this holds for every mechanism, not just
certificates.

### 2. Provisioning prioritises ACME (Let's Encrypt)

The Receive side needs server certificates. Among the ways to obtain them, **ACME
(RFC 8555 — Let's Encrypt) is prioritised**: an Xmip node can obtain and renew
its own certificate rather than an operator installing one by hand. It is a
capability of its own (`xmip-core-authenticate-acme`, or the certificate
module's provisioning half), not a transport.

### 3. Let's Encrypt is one source, not the story

Recorded already in ADR-0028 and restated here as a constraint on clause 2: ACME
with Let's Encrypt issues **public, domain-validated** certificates over HTTP. It
does not cover mutual-TLS against a private partner, an internal certificate
authority, client certificates, or any non-public endpoint. Those remain, and
for high-assurance partner integration the **internal CA + mutual-TLS** path is
the default; Let's Encrypt is prioritised for the public edge, not made
universal.

### 4. The build order

1. Server TLS in the transport (accept a TLS connection with a server cert).
2. Client-certificate verification on the server side — `mutual-tls` on Receive.
3. Client-certificate presentation on the send side — `mutual-tls` on Send.
4. The `mutual-tls` and `certificate` `Authenticator`s surfacing the proof.
5. ACME provisioning of the server certificate — Let's Encrypt.

Each is security-critical and lands on its own, tested, rather than as one drop.

## Consequences

- The transport crate's `tls` feature grows a server path; it stops being
  client-only. Its crypto still comes from rustls, the one place the estate
  admits a crypto dependency, kept behind the feature.
- `xmip-core-authenticate-certificate` (already declared in `architecture.toml`)
  gains the two authenticators; an ACME capability is added for provisioning.
- The Playground's authentication faults (ADR-0028) become exercisable against a
  real mechanism rather than only simulated.
- `open-problems.md` gains this as a prioritised item.

## Provenance

The requirement and the priority are the owner's, 2026-09-05: certificates on
Receive and Send, Let's Encrypt prioritised among the identity protocols.
Clauses 1 to 4 are the assistant's drafting of it, on the instruction to
proceed and to write the decision down.
