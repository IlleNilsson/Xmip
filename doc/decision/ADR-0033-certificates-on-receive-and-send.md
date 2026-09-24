# ADR-0033: Certificates on Receive and Send, Let's Encrypt prioritized

- Status: Accepted
- Date: 2026-09-05
- Related: ADR-0019 (identity, parties, direction), ADR-0022 (identity classes),
  ADR-0010 (contract and transport boundaries), ADR-0028 (the Playground's
  injected faults), ADR-0034 (provisioning versus usage — this record is the
  *usage* half; provisioning, including where Let's Encrypt fits, is there)

## In brief

- Theme: Identity and security
- Subject: Certificate identity is the first mechanism built, provisioned by ACME
- Name: Certificates on Receive and Send
- Order: 5
- Concepts: Certificates, mutual-TLS; ACME, Let's Encrypt

**Certificate identity is the first authentication mechanism Xmip implements,
on both directions: a Receive Location verifies the certificate a caller
presents, and a Send Location presents one. And provisioning those certificates
prioritizes ACME — Let's Encrypt — among the identity protocols.** Twenty-eight
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

### 2. Provisioning prioritizes ACME (Let's Encrypt)

The Receive side needs server certificates. Among the ways to obtain them, **ACME
(RFC 8555 — Let's Encrypt) is prioritized**: an Xmip node can obtain and renew
its own certificate rather than an operator installing one by hand. It is a
capability of its own (`xmip-core-authenticate-acme`, or the certificate
module's provisioning half), not a transport.

### 3. Let's Encrypt is one source, not the story

Recorded already in ADR-0028 and restated here as a constraint on clause 2: ACME
with Let's Encrypt issues **public, domain-validated** certificates over HTTP. It
does not cover mutual-TLS against a private partner, an internal certificate
authority, client certificates, or any non-public endpoint. Those remain, and
for high-assurance partner integration the **internal CA + mutual-TLS** path is
the default; Let's Encrypt is prioritized for the public edge, not made
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
- `open-problems.md` gains this as a prioritized item.

## Amendment, 2026-09-18: the two authenticators are built, and where X.509 lives

Step 4 of the build order, on the owner's *go ahead, and be sure to split
into repos and modules so slicing and packaging can be done*. Built the same
day, tested, each in its own repository as the manifest already had them:

- **`authenticate/certificate`** walks the chain the first gate handed over
  as the `certificate.chain` proof to one of the anchors the node holds, at
  the clock it is given, against the CRLs it was configured with; then
  requires the leaf to name the claimed value — subject or DNS name — and
  the reported fingerprint to be the leaf's. The usage the leaf must be for
  is configuration, any unless said, because an S/MIME certificate in AS2
  is not a client-auth certificate.
- **`authenticate/mutual-tls`** records what the transport proved and redoes
  no cryptography, as clause 1 says: the transport that verified the client
  chain in its handshake promotes `tls.peer.verified = verified`, the first
  gate presents that as the `mutual-tls.handshake` proof, and the gate
  answers Proven for it and refuses anything else with the reason. It may
  narrow the issuers it takes.
- **X.509 is the capability's, behind a feature.** Two technologies need
  the chain walk, the names and the revocation lists, so they live in
  `xmip-core-authenticate` (ADR-0044) as `authenticate::x509`, on only for
  the two that ask (`features = ["x509"]`) and absent from the sixteen that
  do not. The crypto beneath is webpki over ring — rustls's own — so the
  estate still admits one crypto dependency. A `mint` feature issues test
  chains and ships in no build. This is the split that lets a package carry
  certificate verification or not.
- **Revocation is by CRL and offline** (ADR-0045). Held lists are checked
  down the whole chain and a certificate no held list covers is refused,
  not passed. OCSP asks a responder and waits for the `online` switch.
- **Steps 2 and 3 stay open.** The transport's server TLS still says
  `with_no_client_auth()`, and nothing promotes `tls.peer.*` yet: the
  vocabulary the two gates read is fixed here so the transport can grow
  into it. Step 5, ACME, is untouched.

## Amendment, 2026-09-18: hybrid certificates, classical and post-quantum in one

The owner, the same day: *we need this: an X.509 hybrid certificate
combines traditional classical cryptography (RSA or ECDSA) with
post-quantum cryptography in a single digital certificate, to ensure
backward compatibility while migrating to quantum-safe security.* Nothing in
the record had said post-quantum before; this does.

- **The shape is ITU-T X.509 (10/2019) clause 9.8, alternative
  signatures.** The classical signature stays where it always was, and
  three extensions carry a second public key (`subjectAltPublicKeyInfo`),
  the algorithm of a second signature (`altSignatureAlgorithm`) and that
  signature (`altSignatureValue`), computed over the `tbsCertificate`
  without its `signature` field and without the `altSignatureValue`
  extension (clause 7.2.2). A verifier that knows nothing of the extensions
  sees an ordinary certificate, which is the backward compatibility the
  owner named. Chosen over IETF LAMPS composite signatures
  (draft-ietf-lamps-pq-composite-sigs), which a legacy verifier cannot read
  at all; composite is the next slice, its own feature beside this one, on
  the owner's word of the same day: alternative signatures first.
- **The post-quantum algorithm is ML-DSA (FIPS 204)**, in its three
  parameter sets, recognized by the identifiers RFC 9881 gives them.
  Verification is aws-lc-rs's, because ring has no post-quantum signature;
  so it is its own feature, `x509-alt` on the capability and `hybrid` on
  `authenticate/certificate`, and a package is quantum-ready or not. The
  classical walk stays on ring beneath webpki; the alternative walk follows
  the very path the classical walk proved, leaf to anchor, and verifies
  each certificate's alternative signature with its issuer's alternative
  key — the anchor's with its own.
- **The policy is the node's, in three words.** `Ignored`, a legacy
  verifier's view; `WherePresent`, the default, where a certificate that
  carries the extensions is held to them and one that does not is taken on
  its classical signature, so a partner may move before the node requires
  it; `Required`, every certificate on the path, anchor included, or
  refused saying which one lacks it. A certificate carrying an alternative
  signature its issuer has no alternative key for, or by an algorithm this
  build does not know, is refused under any policy but `Ignored`.
- **Minting for tests signs twice.** The alternative signature covers the
  certificate without its own extension and without the classical
  `signature` field, so the test minter signs once to learn those bytes,
  alternative-signs them, and signs again with the third extension in
  place; the classical signature covers all three. Proved in the
  capability: a hybrid path verifies under every policy, a classical one
  passes where present and is refused where required, and an alternative
  signature by the wrong key is refused naming ML-DSA-65.
- **Not yet.** Composite signatures; a hybrid key on Xmip's own side (a
  Send Location presenting one, ACME issuing one); and the transport's
  handshake, which is rustls's and follows rustls on post-quantum
  certificates. Each is a slice of its own.


## Amendment, 2026-09-23: the handshake's key exchange is hybrid, and TLS has a home

The owner asked whether TLS hybrid was built, and on hearing it was not:
*Fix ... TLS Hybrid.* The certificate had been hybrid since 2026-09-18 and
the session it opened was not: the key exchange was X25519 alone, so a
recording of today's traffic could be read by whoever later holds a quantum
computer, however quantum-safe the certificate that authenticated it.

- **The group is X25519MLKEM768**, the hybrid of X25519 and ML-KEM-768
  (FIPS 203) that the IETF's hybrid design for TLS 1.3 names and that
  browsers, CDNs and OpenSSL 3.5 already offer. A session agreed on it is as
  safe as the stronger of the two: a flaw found in the young lattice scheme
  still leaves X25519, and a quantum computer still faces ML-KEM.
- **Offered first, never alone.** Both sides build from one provider whose
  groups are, in order, X25519MLKEM768, X25519, P-256 and P-384. Two Xmip
  nodes agree the hybrid; a peer that knows only classical groups is served
  with X25519, so nothing that connects today stops connecting. The
  handshake records which was agreed, and the tests prove both.
- **The provider is aws-lc-rs, not ring**, because ring has no ML-KEM. It is
  rustls's default and the crypto the estate already builds for ML-DSA in
  `x509-alt`; its assembler comes prebuilt, so a Windows build needs no NASM.
  The groups are listed explicitly rather than taken from the provider's
  default, so a change of rustls's preference cannot quietly change Xmip's.
- **TLS is a repository of its own, `xmip-core-library-tls`**, on the owner's
  decision of 2026-09-22. It sat inside `xmip-core-transport-http`, where the
  transports riding on HTTP could reach it and the twenty that do not — SMTP
  and IMAP with STARTTLS, MQTT, AMQP, Kafka, the databases, syslog — could
  not. Four technologies mapped their `https` URLs to a stack they had no way
  to load, and `webdav` mapped `webdavs://` and then refused it; all five now
  reach TLS, and webdav connects through the http technology's endpoint like
  every other rider. *(Corrected 2026-09-24: msmq did not — it still wrote
  `http://` and never used its `tls` feature. Since problem 25 row (g) it
  connects through the same endpoint, and `msmqs://`, `https://` and
  `DIRECT=HTTPS://` queues are refused rather than sent in the clear without
  `tls`.)* A client, a server, the node's certificate and the
  operating system's trust store live there; one call serves STARTTLS, since
  an upgrade in place is the same wrap on a socket already negotiated. When
  to upgrade, and what a protocol sends first, stays with the protocol.
- **Not yet**, still: composite signatures, and a hybrid key on Xmip's own
  side. A post-quantum *certificate* in the handshake — ML-DSA as the TLS
  signature rather than beside it — waits on rustls and on public CAs issuing
  one.

The requirement and the priority are the owner's, 2026-09-05: certificates on
Receive and Send, Let's Encrypt prioritized among the identity protocols.
Clauses 1 to 4 are the assistant's drafting of it, on the instruction to
proceed and to write the decision down.
