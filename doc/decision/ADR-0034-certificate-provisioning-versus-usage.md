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
   (a fresh P-256 key and the request, written into a folder as
   `operator.key` and `operator.csr`, private files, and answered as JSON of
   the two paths: the key never crosses the boundary — amended 2026-10-16,
   below), carried by
   every build, the phone's remote build too; `xmip_operator_sign_v1` (a
   request signed by the authority a node configuration names), a node's
   build only. `Xmip.Abi`'s `RuntimeCertificates` binds both;
   `Xmip.Surface`'s `OperatorCertificate` calls them once, for
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

**Built the same day, phase 2: the key in the platform's keeper.** The
phone's key is made in its platform's keeper and never leaves it; the
request and every handshake are signed there.

- **The two halves, placed once.** `xmip-core-provision`'s
  `operator::information(person, public_key)` writes what a request signs
  over the keeper's public key, read in either form a platform hands it —
  `SubjectPublicKeyInfo` DER (the Android Keystore, Windows CNG) or the bare
  uncompressed point (the iOS keychain) — and `operator::assemble` makes the
  request of it and the keeper's signature, verifying that signature under
  the key first, so a keeper that signed in another form is told so before
  the authority is asked. `operator::request` is the two around a key in
  memory. Exported in `xmip_operate.h` section 19 as
  `xmip_operator_information_v1` and `xmip_operator_assemble_v1`, carried by
  every build, the phone's remote build too, and bound in `Xmip.Abi`'s
  `RuntimeCertificates` (`Information`, `Assemble`); the surface never
  writes DER.
- **TLS presenting a key it cannot read.** `xmip-core-library-tls` takes a
  signer in place of a PEM key, `Identity::from_signer` with a `Sign`: a
  rustls signing key for ECDSA on P-256 with SHA-256 whose every signature
  is asked of the keeper. Section 17's remote open gains
  `xmip_remote_open_kept_v1`, taking the chain and a signing callback with
  its context instead of the key's PEM, forwarded by the runtime
  (`ffi::keeper`) and bound as `RuntimeRemotes.OpenKept`, the callback held
  until the handle is freed.
- **The keepers.** One interface, `Xmip.Surface`'s `IOperatorKeeper`, and
  one keeper per platform in `Xmip.Operations`: the Android Keystore
  (`AndroidKeeper`; EC on secp256r1 in `AndroidKeyStore`, SHA-256, StrongBox
  where the phone declares it, the trusted environment where StrongBox
  cannot make the key), the iOS keychain in the Secure Enclave
  (`EnclaveKeeper`; `kSecAttrTokenIDSecureEnclave`, permanent and tagged,
  usable only on that phone while it is unlocked), and Windows CNG on the
  desktop (`CngKeeper`; the Microsoft Platform Crypto Provider — the TPM —
  first, the software provider where the TPM makes no P-256 key, never
  exportable). `OperatorCertificate.RequestKept` makes the request over the
  kept key — made first where none is kept, else the kept one asked again, so
  a renewal keeps its key — and `Keep` keeps the chain the authority signed
  once the keeper signs a probe its leaf verifies; `KeepAnchors` keeps the
  cluster's authority. `SecureSurface` names a keeper's key where a host's
  document names a `Certificate` and no `PrivateKey`, and `RemoteOperator`
  then opens kept. The host's Certificate page — on the phone and the
  desktop alike — makes the request, shares it, and keeps the chain and the
  authority, each act audited; what it keeps is presented from the next
  start. The phone's shipped document names `Certificate = "operator.pem"`
  and `TrustAnchor = "anchor.pem"` and no key.

Proved: in `xmip-core-provision` (both forms of a public key make a request
that reads; a fixed-width signature and another key's are refused in words);
in `xmip-core-library-tls` (a client whose keeper signs is admitted by a
mutual-TLS server, one whose keeper refuses is not, a server whose kept key
is not its certificate's is refused, one whose is answers); in the runtime
(both new section 19 exports across the boundary, and a kept open that is
the caller `CN=phone` a served operate listener proves, while a keeper that
refuses leaves the node unreachable); in `Xmip.Abi.Test` (the two halves
from either form of a .NET key, a request .NET reads back naming the
person); in `Xmip.Surface.Test` (a keeper's request signed by the authority,
the chain kept and refused for another key, and the kept key presented to a
real operate listener as `CN=alice@example.org`, refused an act as
Observer); in `Xmip.Operations.Test` (Windows CNG, the software provider, on
this machine: a key not exportable that makes a request). The Android
keeper is built and not yet run on a phone; the iOS keeper is written and
neither built nor run — iOS builds only on macOS. The TPM is not asked by
any test: a key it made would outlive a failed run in the machine's chip.

**Not yet.** `xmip-service` reads no `[provision]` table yet (open problem
27), so no node holds an authority on its own; the folder
`[provision.operator] authority` names is the one `internal-ca` keeps.
Revocation of an operator's certificate is not decided. The command line
and the PowerShell module still make the key as a PEM file
(`--operator`, `-Operator`) and take no keeper: the keepers live in the
MAUI host, and whether those two surfaces gain one — Windows CNG first — is
the owner's to say (ADR-0014, amendment 2026-09-19). The Certificate
page's form, and whether the phone may take the cluster's authority from
the chain it is sent rather than separately, are the owner's to say.

## Amendment, 2026-10-16: every key and identity on disk is a private file

An outside review asked that identities be secured and persisted
atomically. Before this, a node's `Provisioned` was three files each renamed
into place, so a crash between two renames could leave a new chain beside
the old key; the cluster's authority and an ACME account key were written by
a plain write; and a person's operator key was written by the .NET surface,
owner-only on Unix and not on Windows, never synced. None set an access list
on Windows.

1. **One writer, in the key home.** `xmip-core-secret`'s `private_file`
   writes every key and identity the estate keeps on disk — the
   key-encryption keys of `file` and `dpapi` too: the bytes go to a file
   created beside the one they become, owner-only before its first byte
   (mode `0600`, a created directory `0700`; on Windows an access list
   granting the user the process runs as and `SYSTEM` full control and no
   one else, protected from inheritance), synced, then moved into place —
   `replace` by a rename, `create` by a link that refuses a file already
   there — and on Unix the directory synced after. It is in the key home
   because the key home is the capability that keeps keys (ADR-0063 clause
   4), and it is the lowest layer both it and `xmip-core-provision` reach:
   provisioning now depends on it, as do `acme` and `internal-ca`.
2. **A node's identity switches whole.** `Provisioned::write` writes
   `chain.pem`, `key.pem` and `anchors.pem` into a new folder
   `generation-<random>` of the purpose's place and only then replaces the
   file `current`, which names it; `Provisioned::read` follows `current`.
   A crash at any step leaves the identity kept before; the folder a crash
   left is removed at the next write, and the generation replaced at once.
   Nothing else reads the place's identity files.
3. **The authority's pair** is written certificate first and key last,
   never over a key: the key is what says an authority is kept, so a crash
   between leaves none kept and the next start makes a matching pair.
4. **The operator key never enters .NET.** `xmip_operator_request_v1` takes
   the folder and writes both files through `provision::operator::
   request_into`; its answer is the two paths, and a file already there is
   refused with nothing written. `OperatorCertificate` no longer names the
   files or writes the key.
5. **The chain and the anchors a surface keeps** are not secret, and are
   kept the same way: `OperatorCertificate.Keep` and `KeepAnchors` check
   what they keep and call `xmip_operator_keep_v1`, which writes the text
   beside its file, syncs it and renames it over what was there
   (`provision::operator::keep`, over `private_file::replace_readable`,
   readable as its folder lets). The chain `OperatorCertificate.Sign`
   writes where `xmip-cli certificate --sign --out` or `New-XmipCertificate
   -Path` names a file goes through the same export with `replace` zero:
   written beside it, synced and linked where nothing is, never over a file
   already there (`private_file::create_readable`). A file there before the
   signing is refused before anything is signed. .NET writes none of these
   files itself.
6. **A crash's leftover is swept.** A file written and never switched is
   named `.<name>.<16 hex>.new`, and nothing else is; whoever opens a folder
   of private files — `KeyDirectory`, the authority's folder, the purpose's
   place before an account key or a generation is written — removes exactly
   those first (`private_file::sweep`).

Proved in `xmip-core-secret` (mode and access list asserted; a crash after
the bytes are written leaves the file as it was, and the sweep removes that
leftover and no look-alike), `xmip-core-provision` (an identity read back
whole and owner-only; a crash before the switch, or halfway through a
generation, leaves the old chain with the old key), `internal-ca` (a crash
between certificate and key leaves a matching pair next time), `acme` (the
account key made once, owner-only), the runtime's exports, `Xmip.Abi.Test`
and `Xmip.Surface.Test` (the key file owner-only on Windows and Unix; a
chain and anchors kept through the runtime, a chain created never over a
file and replaced only where asked).

## Amendment, 2026-10-19: a node uses its `receive` certificate

The first use of a provisioned purpose in the assembled service:
`xmip-service` reads `[provision.receive]` as it starts and terminates the
TLS of every tcp Receive Location saying `tls = true` with it, the client's
certificate verified against the table's `anchors` (ADR-0033, amendment
2026-10-19; the runtime's `receive_certificate`). Usage is the TLS
library's, as this record has it; provisioning is still the operator's own
files alone: a table naming a `source` is refused, no provisioner runs in a
node and nothing renews while it runs (open problem 27). Reading the
anchors a Party's certificate must reach from the same table is the
assistant's drafting of 2026-10-19, for the owner to overrule: the
operator's-files source already declared `anchors` as *the PEM anchors a
peer's certificate must reach*.

## Amendment, 2026-10-22: ACME offline — the premises' own ACME service, and the air gap

**Provenance.** The owner, 2026-10-22: *There has to be tools, aid, to
support 'Let's encrypt', ACME when being offline.* Asked which case, he
answered **both**: the premises' own ACME service, and a node with no
network route at all. The same day: node certificates last **90 days**;
and, agreeing a finding below, *Let's Encrypt covers only a node's public
server side; node-to-node mutual TLS always uses the cluster authority's
certificate.* Nothing in Xmip ships a CA for production: the end user
chooses their CA (clause 2 of the amendment of 2026-09-24). What follows
beyond those sentences is the assistant's drafting, each point the owner's
to strike.

**What was current on 2026-10-22** (each read that day):

- **ACME Renewal Information is a standard**: RFC 9773, June 2025. A server
  names `renewalInfo` in its directory (section 3); a certificate is named
  by its authority key identifier's `keyIdentifier` and its serial, each
  base64url without padding, joined by a dot (section 4.1); the answer is a
  `suggestedWindow` of `start` and `end` and an optional `explanationURL`
  (section 4.2), its `Retry-After` how long to wait before asking again
  (section 4.3); a new order says which certificate it `replaces` (section
  5) (<https://www.rfc-editor.org/rfc/rfc9773.html>).
- **Let's Encrypt serves it**: its directory names
  `https://acme-v02.api.letsencrypt.org/acme/renewal-info`, and offers the
  profiles `classic`, `tlsserver` and `shortlived`
  (<https://acme-v02.api.letsencrypt.org/directory>). Its profiles page,
  updated 2026-10-04: `classic` 90 days, `tlsserver` 45 days, `shortlived`
  160 hours; `tlsclient`, the last to carry TLS client authentication, *is
  no longer available* since 2026-07-08
  (<https://letsencrypt.org/docs/profiles/>). Its schedule: `tlsserver` 45
  days from 2026-05-13; `classic` 64 days from 2027-02-10 and 45 days from
  2028-02-16; a client without ARI renews about two thirds of the way
  through (<https://letsencrypt.org/2025/12/02/from-90-to-45/>). The
  profiles extension is `draft-ietf-acme-profiles`, submitted to the IESG,
  not yet an RFC (<https://datatracker.ietf.org/doc/draft-ietf-acme-profiles/>).
- **OCSP is gone**: Let's Encrypt *turned off our Online Certificate Status
  Protocol (OCSP) service* on 2025-08-06 and publishes revocation *exclusively
  via Certificate Revocation Lists (CRLs)*
  (<https://letsencrypt.org/2025/08/06/ocsp-service-has-reached-end-of-life/>).
- **The CA/Browser Forum's schedule** (ballot SC-081v3, passed 2025-04-11;
  TLS Baseline Requirements 2.3.1, section 1.2.2): a subscriber certificate
  lasts at most 200 days from 2026-03-15, 100 days from 2027-03-15 and 47
  days from 2029-03-15; domain validation is reused for 200, 100 and then
  10 days (<https://cabforum.org/2025/04/11/ballot-sc081v3-introduce-schedule-of-reducing-validity-and-data-reuse-periods/>,
  <https://raw.githubusercontent.com/cabforum/servercert/main/docs/BR.md>).
- **The clients**: certbot 5.8.0 (2026-09-01), lego 5.5.2 (2026-09-23;
  in lego 5 `run` obtains and renews, ARI is on unless `--ari-disable`,
  revocation is `certificates revoke`, http-01 listens on `--http.address`,
  and `LEGO_CA_CERTIFICATES` names the anchors it trusts), win-acme 2.2.9.1
  (2024-05-25, the newest; ARI since 2.2.3; it trusts the Windows store
  alone, or turns verification off with `ValidateServerCertificate`)
  (<https://github.com/certbot/certbot/releases>,
  <https://github.com/go-acme/lego/releases>,
  <https://go-acme.github.io/lego/references/ref-flags/>,
  <https://go-acme.github.io/lego/advanced/options/>,
  <https://github.com/win-acme/win-acme/releases>,
  <https://www.win-acme.com/reference/settings>).
- **Where a verifier fetches a list**: Windows' retrieval takes `ldap`,
  `http`, `https` for a CRL or OCSP alone, and `file`
  (<https://learn.microsoft.com/en-us/windows/win32/api/wincrypt/nf-wincrypt-cryptretrieveobjectbyurla>),
  and practice is plain HTTP: *You MUST NOT serve CDP/AIA/OCSP URLs over
  HTTPS, use plain HTTP only*
  (<https://learn.microsoft.com/en-us/answers/questions/169840/how-can-i-configure-cdp-with-https>).

### 1. The cluster's authority keeps a register

The authority kept in a folder (`authority.key`, `authority.pem`) now keeps
beside them every certificate it signs, by any way — ACME, a node issued on
the operator's machine (section 22), a carried request, a person's request
— as `issued/<serial>.pem`, each revocation as `revoked/<serial>`, and the
list it publishes, `authority.crl`, a version 2 CRL it signs, made again at
every revocation and when a day old, valid a week
(`provision::register::Register`, `provision::crl`). Each file is created
once and never written over, so the node serving ACME and an operator's
surface never write the same one. No OCSP responder is built: revocation is
published as a list alone, as Let's Encrypt now publishes it.

### 2. Every certificate says where to check it

Every certificate names its own key, and a leaf its issuer's, by key
identifiers — the leftmost 160 bits of SHA-256 over the key (RFC 7093,
method 1) — which a verifier builds a chain by and ARI names a certificate
by. Where the authority publishes, `published` in its folder, a leaf names
`<published>/crl` its CRL distribution point and `<published>/authority.cer`
its issuer's certificate. The address is plain `http://host:port`, refused
otherwise: a verifier fetches the list before it trusts any TLS.

### 3. The premises' own ACME service

The node whose `[provision.node]` names `source =
"xmip-core-provision-internal-ca"` and `serve` answers ACME there, in
`xmip-service` beside the node's path (ADR-0045 clause 1), until it drains;
`publish` names the plain-HTTP listener for `/crl`, `/authority.cer` and
`/authority.pem`, `published_at` the address the premises reach it at, and
`authority` the folder, `authority` beside the configuration unless said.
`xmip-service --listening` names both ports. The service is completed
for any standard client:

- the directory names `revokeCert` and `renewalInfo`, and says no
  external account is required; there are no terms of service;
- an account is kept in the authority's folder (`acme/accounts/`) and
  outlives a restart; `onlyReturnExisting` and the account's POST-as-GET
  are answered;
- an order and an authorization say when they expire; an order's
  `replaces` is held to a certificate this authority issued, replaced once
  (`alreadyReplaced` after);
- `renewalInfo` answers the window from two thirds to three quarters of a
  certificate's life — two thirds is the moment every Xmip reader renews
  at (`provision::renewal_moment`), and Let's Encrypt's advice for a client
  without ARI — with `Retry-After` six hours; for a revoked certificate a
  window already passed, so its client renews at once;
- `revokeCert` is taken from the account the certificate was issued to
  (`acme/ordered/<serial>`) or signed by the certificate's own key, into the
  register and the list at once (`alreadyRevoked`, `badRevocationReason`).

**Proved with a standard third-party client**: lego 5.5.2, Go, one binary
from `.local-work/lego`, nothing installed, trusting the authority through
`LEGO_CA_CERTIFICATES` alone — no trust store touched. `internal-ca`'s
`tests/acme/third_party.rs`, run where `XMIP_ACME_LEGO` names the binary
and said SKIPPED otherwise: lego obtains a certificate by http-01 on its
`--http.address`; asked again, ARI says it is not due and lego keeps it;
`lego certificates revoke --reason 4` revokes it into the register and the
list; asked again, ARI's window has passed and lego renews at once. Xmip's
own client asks the same (`acme::Client::renewal_window`, `revoke`).
win-acme is not tested: it trusts the Windows store alone, which this work
does not touch. certbot is not tested: it is Python, run only in the WSL
guest if at all, and lego answered the question it would.

**dns-01 against the premises' DNS**: `dns_server`, a DNS server on the
premises the authority asks a name's TXT records of, over UDP
(`internal_ca::Resolver`, RFC 1035); an answer cut short is refused, since
TCP is not built. Writing the record is a DNS provider's module's
(`DnsWriter`), as before; Xmip ships none for a vendor.

**Renewal offline, checked**: ARI needs only the authority, which is on the
premises; the list needs the plain-HTTP address its leaves name, reachable
on the premises; nothing reaches beyond the cluster. Xmip's own provisioner
still renews at two thirds of the life it read, which is where the window
opens; it does not yet ask ARI, so a revocation reaches it at its next
renewal and not at once.

### 4. A node's certificate across an air gap

Three acts, each checking the file it is given (`provision::carried`):

1. **On the node, a request**: a fresh key, `node.next.key`, which never
   leaves the node, and a PKCS #10 request for it, `node.csr`, naming the
   node and every name it is reached by, each checked as a host's name;
   never over a request waiting.
2. **Where the authority is kept, the signing**: the request's own
   signature verified, held to what a node's certificate may be
   (`Purpose::admit`) and, where the signer names any, to exactly the names
   expected; signed for 90 days for server and client authentication by an
   authority that exists — never made by this act — and registered.
3. **On the node, the import**: every signature of the chain checked, the
   leaf for `node.next.key`'s key and the request's names, serving a node,
   valid now, the chain ending at an authority that signed itself and that
   is the node's anchor where it holds `anchors.pem`; only then are
   `node.pem` and `node.key` written, the anchor too where the node held
   none — the import then says the authority's SHA-256, to compare by
   another way — and the request's files removed. A crash between the
   writes leaves the request's files, and the same import again finishes.

Renewal is the same three acts. **The node says in its health when a
request is due**: at `<node>/certificate/<use>`, each certificate its
configuration names — `operate`, `receive`, `storage` — `Fine` while
current, `Stressed` saying *renewal due* from two thirds of its life,
`Done` once expired (`provision::renewal::Standing`).

### 5. A node's certificate always comes from the cluster's authority

Between nodes each end presents a certificate for client authentication
too, which Let's Encrypt has not issued since 2026-07-08 (ADR-0033,
amendment 2026-10-13). So `[provision.node]` from a source that declares
`anchors` — ACME, an operator's files — is refused unless `anchors` names
the cluster authority's anchor: a public authority trusted through the
operating system's store serves `[provision.receive]` alone, the public
server side an online node may take from Let's Encrypt
(`provision::read`, the owner, 2026-10-22).

### 6. The surfaces

`xmip_operate.h` section 23, `xmip_authority_v1`: an act and its arguments
as JSON, its answer JSON — `set-up`, `inspect`, `read`, `revoke`,
`export`, `back-up`, `request`, `sign`, `import` — a node's build only, a
forwarder over the capability (`ffi::authority`). `Xmip.Abi`'s
`RuntimeCertificates.Authority` binds it; `Xmip.Surface`'s
`AuthorityCertificate` asks it once for every .NET surface:

| act | `xmip certificate` | PowerShell |
| --- | --- | --- |
| set up the authority | `--authority <folder> --cluster <c> [--publish http://host:port]` | `New-XmipCertificate -Authority -Cluster [-Publish]` |
| inspect it | `--inspect <folder>` | `Get-XmipCertificate -Authority` |
| read a certificate, renewal due | `--inspect <file>` | `Get-XmipCertificate -Path` |
| revoke | `--revoke <serial> --authority <folder> [--reason <word>]` | `Get-XmipCertificate -Authority -Serial -Revoke [-Reason]` |
| hand out the anchor or the list | `--export <file> --authority <folder> [--format pem\|der\|crl]` | `Get-XmipCertificate -Authority -Export [-Format Pem\|Der\|Crl]` |
| back up | `--backup <folder> --authority <folder>` | `Get-XmipCertificate -Authority -Backup` |
| a node's request | `--node <node> [--names] [--out <folder>]` | `New-XmipCertificate -Node [-Name] [-Path]` |
| sign a carried request | `<node.csr> --authority <folder> [--names] [--out <file>]` | `New-XmipCertificate -Request -Authority [-Name] [-Path]` |
| import it on the node | `<chain> --import <folder>` | `New-XmipCertificate -Import -Path` |

One new cmdlet, `Get-XmipCertificate`, reads, its acts parameters on it as
`Get-XmipSubscription`'s are (ADR-0014, amendment 2026-09-15). Every act is
audited — `xmip` audits every command, the PowerShell module every act
that changes something (ADR-0062). The desktop host gains an Authority page
— set up, inspect, revoke, export, back up and sign a carried request —
for a role that may configure; the phone keeps no authority.

**Handing the anchor out** (`doc/getting-started.md`, *The cluster's
authority on the premises*): the anchor as DER for Windows and PEM for
Linux; Windows' user store `certutil -user -addstore Root authority.cer` or
`Import-Certificate -CertStoreLocation Cert:\CurrentUser\Root`, the
machine's in an elevated prompt; AlmaLinux and RHEL
`/etc/pki/ca-trust/source/anchors/` and `update-ca-trust`; Debian and
Ubuntu `/usr/local/share/ca-certificates/*.crt` and
`update-ca-certificates`; Chrome and Edge on Windows read the system
store; Firefox through its enterprise policy `Certificates` — `Install` on
Linux, where `ImportEnterpriseRoots` does nothing; Chrome on Linux its NSS
database, `$HOME/.local/share/pki/nssdb` from M146. Xmip runs none of them:
each changes what a machine trusts, and is its owner's to run.

**Proved**: in `xmip-core-provision` (the register, the list read back and
verified, a revocation never twice, a backup the same authority, the
carried round trip and every refusal of it, a node issued on the
operator's machine registered); in `internal-ca` (the premises' test above,
an account kept across a restart, a stranger refused revocation, the DNS
server asked over UDP, lego); in the runtime (section 23 end to end); in
`Xmip.Abi.Test`, `Xmip.Surface.Test` (the round trip, and .NET's own chain
builder reaching the exported anchor with no store touched), `Xmip.Cli.Test`
and the PowerShell module's Pester suite.

**Drafted, for the owner to strike**: the register's files and their
layout; the list valid a week, made again daily; the ARI window from two
thirds to three quarters and six hours between asks; a revoked
certificate's window already passed; key identifiers by SHA-256; the
publication plain HTTP only; an authority set up here valid ten years;
`Stressed` for renewal due; the cmdlet split, one new `Get-XmipCertificate`
with its acts; the Authority page's place on the desktop alone.

**Not yet**: `xmip-service` still starts no provisioner for its own
certificates, and the node holding the authority does not issue itself
(open problem 27); Xmip's own provisioner does not ask ARI; no OCSP; no
DNS over TCP; win-acme and certbot untested.
