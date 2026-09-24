# ADR-0050: An identity technology is one mechanism at one gate

- Status: Accepted
- Date: 2026-09-10
- Related: ADR-0019 (identity, Parties and direction: the three gates and
  their order), ADR-0022 (identity classes and runtime isolation), ADR-0033
  and ADR-0034 (certificates), ADR-0044 (a technology shares through its
  capability), ADR-0045 (offline is the default),
  doc/planning/open-problems.md problem 10

## In brief

- Theme: Identity and security
- Subject: What the fifty-one technologies under `identify`, `authenticate`
  and `authorize` are, and which trait each implements
- Name: An identity technology is one mechanism at one gate
- Order: 7
- Concepts: Identity technology; identifier; authenticator; authorizer;
  mechanism; gate

**ADR-0019 orders three gates — who is claimed, is the claim true, may this
true identity do this — and the capabilities behind them already carry one
trait each. An identity technology is one mechanism at one of those gates and
nothing at the others. An identify technology reads one mechanism's claim out
of an arrival or a Message and proves nothing. An authenticate technology
verifies one mechanism's presented claim and resolves it to a Party. An
authorize technology is one policy that decides an attempt at one layer.
Nineteen, eighteen and fourteen of them, each its own repository.**

## Context

The manifest declared fifty-one technologies under the three identity
capabilities with no description, maturity or dependency: bare headers.
Unlike `route`, `message` and `resilience` (ADR-0046 to ADR-0048) the traits
were not missing — `TransportIdentifier`, `MessageIdentifier`,
`Authenticator` and `Authorizer` have stood since ADR-0019 and ADR-0022, with
`Mechanism` in the Foundation naming a mechanism's layer, identity class and
assurance. What was missing was the sentence that says which of the fifty-one
implements which, and what each one reads, verifies or decides. The owner's
instruction of 2026-09-10 to sort everything declared and not built covers
them; problem 10's rule that the trait comes first is already met.

## Decision

### 1. The sentence

The one in brief. A technology sits at one gate. The mechanism a technology
reads at the first gate and the one it verifies at the second are the same
`Mechanism` value, declared once in the identify technology and reused by
its authenticate sibling, so that `identify/jwt` and `authenticate/jwt` agree
on a name without either depending on the other: the declaration goes up
into `xmip-core-identify` (ADR-0044) as a catalog of the mechanisms the
estate knows.

### 2. The traits, as they stand

- An identify technology implements `TransportIdentifier` (before the
  Message exists, given a `StreamArrival`), `MessageIdentifier` (after it,
  given the Message), or both where the mechanism travels on both layers.
  It answers `None` where the arrival carries nothing it recognizes, a
  `Presented` claim marked passed, inferred or detected where it does, and
  an error only where it recognizes something it cannot read.
- An authenticate technology implements `Authenticator`: `mechanism()` and
  `verify(&Presented) -> Verified`. It never takes a Party; the Party is what
  the capability resolves the verified value to.
- An authorize technology implements `Authorizer`: `name()`, `layer()` and
  `decide(&IdentityFacts, &Attempt) -> Option<Decision>`, where `None` is
  "this policy has no opinion" and a denial names the policy that denied.

### 3. Nineteen identify technologies

Each reads one thing and calls it the claim.

| leaf | reads | layer | established |
|---|---|---|---|
| `ip` | the peer address | transport | passed |
| `mac` | the peer's link-layer address, where the transport reports one | transport | passed |
| `dns` | the peer's reverse name, from the resolver the node is given | transport | detected |
| `header` | one named transport header | transport | passed |
| `cookie` | one named cookie | transport | passed |
| `username` | a username presented without a proof | transport | passed |
| `api-key` | a key in a header or a query parameter | transport | passed |
| `certificate` | the peer certificate's subject and issuer | transport | passed |
| `ssh-key` | the presented public key's fingerprint | transport | passed |
| `jwt` | a bearer token's subject, unverified | transport, message | passed |
| `oidc` | an ID token's subject and issuer, unverified | transport | passed |
| `saml` | an assertion's subject, unverified | transport, message | passed |
| `kerberos` | a ticket's client principal, unverified | transport | passed |
| `ntlm` | the user and domain of an NTLM type 3 message | transport | passed |
| `endpoint` | the identity the Receive Location's configuration names | transport | inferred |
| `party` | the Party the Location's configuration names | transport | inferred |
| `transport` | one named transport property the carrier promoted | transport | passed |
| `message` | one named property of the Message | message | detected |
| `contract` | the identity the content's contract names: ISA06, UNB S002, MSH-3 | message | detected |

### 4. Eighteen authenticate technologies

Each verifies one mechanism's presented value against something the node
holds or can reach, and answers with the verified value or a refusal with a
reason. Offline is the default (ADR-0045): a verifier that needs a server —
`ldap`, `kerberos`, `oauth2`, `oidc`, `saml` metadata — takes the endpoint
from its configuration and is proven against an in-process far end, exactly
as the transports are.

| leaf | verifies |
|---|---|
| `password` | a username and password against a store of salted hashes |
| `basic` | an HTTP Basic credential, decoded and handed to the same store |
| `digest` | an HTTP Digest response against the same store and the nonce |
| `bearer` | an opaque bearer token against a token store |
| `api-key` | a key against a key store, with its expiry |
| `scram` | a SCRAM-SHA-256 exchange against stored verifiers |
| `jwt` | a token's signature (HS256, RS256, ES256), expiry, issuer, audience |
| `oidc` | an ID token against the issuer's published keys and the nonce |
| `oauth2` | a token by introspection at the authorization server |
| `saml` | an assertion's signature and conditions against the IdP metadata |
| `certificate` | a certificate chain to a configured trust anchor, validity and revocation as ADR-0033 says |
| `mutual-tls` | the client certificate the TLS handshake proved, bound to the connection |
| `ssh-key` | a signature over a challenge by the presented key |
| `kerberos` | a service ticket with the node's keytab |
| `ntlm` | the NTLMv2 response against the stored hash |
| `ldap` | a bind at the directory with the presented credential |
| `pam` | the credential through the host's PAM stack, refusing where there is none |
| `windows` | the credential through the host's SSPI, refusing where there is none |

### 5. Fourteen authorize technologies

Each is one policy. It has an opinion or none; the capability consults them
in order and the first denial stands.

| leaf | decides by | layer |
|---|---|---|
| `location` | whether this Location admits this identity at all | transport |
| `transport` | rules on the transport identity: mechanism, class, address | transport |
| `party` | an allow-list of Parties | transport |
| `role` | the roles the identity holds, from a role store | transport |
| `rbac` | roles granted permissions on artifacts | transport |
| `abac` | attribute rules over the identity's facts and the attempt | transport |
| `acl` | an access-control list per artifact | transport |
| `artifact` | what this identity may do to this named artifact | transport |
| `scope` | the scopes a token carries against the scope an action needs | transport |
| `claim` | a claim the identity carries, its value against a rule | message |
| `contract` | whether this identity may present content under this contract | message |
| `policy` | a declarative policy document in the estate's own TOML | transport |
| `cedar` | a Cedar policy set, evaluated with the Cedar engine | transport |
| `opa` | a decision fetched from an Open Policy Agent, proven against an in-process one | transport |

### 6. Where things go up

The mechanism catalog and the credential store the password, basic, digest
and scram verifiers share go up into their capabilities (ADR-0044). Nothing
goes sideways: `basic` does not depend on `password`; both depend on
`xmip-core-authenticate`.

## Consequences

- Fifty-one manifest entries gain a description; each names its trait.
- `xmip-core-identify` gains the mechanism catalog; `xmip-core-authenticate`
  gains the credential store the four password-shaped verifiers share.
- Every technology is built offline and proven in-process; the ones that
  need a host facility (`pam`, `windows`) build where the facility is and
  refuse where it is not, as ADR-0045 requires.

## Amendment, 2026-09-16: the catalog was already there, and the proof has a place

Written by the assistant on the day the fifty-one were built, on the owner's
*continue with protocol, identity, authentication and authorization*, and
put here for the owner to confirm or strike. Two things the record of
2026-09-10 got wrong, and one it left unsaid, surfaced when the first crate
was read before it was written.

- **The catalog is `xmip-core`'s and was before this record.** Section 1
  and the Consequences sent the mechanism catalog up into
  `xmip-core-identify`; `xmip-core` had held it since ADR-0022 as
  `mechanism::declared` — twenty-eight mechanisms, each the last segment of
  the repository that implements it. The seventeen this record names and
  that file lacked (`ip`, `mac`, `dns`, `header`, `cookie`, `username`,
  `endpoint`, `party`, `transport`, `message`, `contract`, `jwt`, `saml`,
  `ntlm`, `ldap`, `pam`, `windows`) are added there, in the same voice, and
  nothing goes into `identify`. A name read off a connection is filed as
  `SharedSecret` and `Identifies`, following `circumstance`, because
  ADR-0022's four classes have no other place for a claim with nothing
  behind it. `ldap`, `pam` and `windows` verify a `username` claim and keep
  their own names, so an Acceptance can say which verifier a Location uses.
- **The proof rides on `Presented::proof`, and never on the record.**
  `Presented` said the secret does not appear on it, and `Authenticator`
  is given nothing else. Both were right and the type could not honour
  them: a password, a Digest response, an NTLM type 3, a JWT with its
  signature, an SSH signature over the session all have to reach the
  verifier. `Presented` gains a private `proof` list beside `evidence`,
  `with_proof(name, value)` and `proof(name)`, under names the mechanism
  owns (`basic.credential`, `digest.response`, `jwt.token`,
  `ntlm.authenticate`, `ssh-key.signature` and the rest); `Debug` prints
  the names only, and the gate copies evidence onto the identity and proof
  onto nothing. `value` stays the name — a username, a subject, a key id —
  so what reaches the record is what may be recorded.
- **What both jwt-shaped gates need lives up in `identify`.** Reading a
  compact JWT's claims is the first gate's work and checking its signature
  the second's, so `identify::jwt::Compact` (split, base64url, one
  top-level claim by name) is the capability's, and `identify/jwt`,
  `identify/oidc`, `authenticate/jwt`, `authenticate/oidc` and
  `authenticate/oauth2` read it rather than each other. ADR-0044 as it
  stands; no sibling depends on a sibling, and the manifest declares no
  such dependency for any of the fifty-one.
- **`pam` and `windows` bind nothing yet.** `unsafe_code = "forbid"` stands
  in every crate; the two host verifiers are built over a trait with an
  in-process implementation and refuse a real login with the reason, on
  every operating system, until the owner rules on where unsafe may live.
  The Consequences above said they build where the facility is; they do
  not, yet, and this says so.

## Amendment, 2026-09-18: one reading, two mechanisms, and a feature in the capability

- **`identify/certificate` presents `mutual-tls` where the handshake proved
  the chain, and `certificate` where it did not.** Section 3 gave the leaf
  one mechanism; ADR-0033 clause 1 gives the two names to two situations
  only the transport can tell apart. So the transport says which, in
  `tls.peer.verified`, and the one reading of the peer certificate yields
  the claim under the name the second gate will verify it by: `mutual-tls`
  with the transport's word as its `mutual-tls.handshake` proof, else
  `certificate` with the chain as its `certificate.chain` proof. The
  sentence holds — each authenticate technology verifies one mechanism —
  and the identify technology reads one thing; what it calls the claim is
  what the transport did with it. The assistant's drafting, for the owner
  to confirm or strike.
- **A capability may hold shared code behind a feature.** Section 6 sends
  shared code up; `authenticate::x509` goes up and stays off unless a
  technology turns it on, so going up does not mean every sibling carries
  it. The same for `mint`, a test-only issuer of chains. ADR-0044 as it
  stands, with the feature as the packaging seam.

## Amendment, 2026-09-19: the last twenty-four are written, and what writing them found

**A correction first.** The landing of 2026-09-18 said of these technologies
that they *read a claim off a connection* and *verify by password, digest,
bearer*. For twenty-four of them that was not so: the session of 2026-09-16
had wired their manifests and READMEs and left `src/lib.rs` the five-line
declaration, the assistant landed them on the file list and not on the
diff, and the message described code that was not there. Found the next
day by counting lines. Pushed history stands, by the owner's word; this
says what it did not. The twenty-four were written on 2026-09-19, each
gated — format, tests, pedantic lints, a hundred columns, four hundred
lines — and each checked on disk before it landed:

- identify: `api-key`, `cookie`, `endpoint`, `party`, `transport`,
  `username`, `kerberos`.
- authenticate: `api-key`, `bearer`, `digest`, `scram`, `ldap`, `pam`,
  `windows`, `oidc`, `oauth2`, `saml`, `ssh-key`, `kerberos`, `ntlm`.
- authorize: `abac`, `policy`, `cedar`, `opa`.

Digest and SCRAM pass the published vectors of RFC 7616 and RFC 7677,
Kerberos those of RFC 3961, NTLM those of MS-NLMP. `pam` and `windows` are
over a trait with an in-process implementation and refuse a real login with
the reason, as the amendment of 2026-09-16 says, until the owner rules on
where unsafe may live. `saml` verifies the enveloped RSA-SHA256 signature
of the common profile and refuses everything else by name; an assertion
whose canonical form it does not reproduce fails its digest and is refused,
never passed.

**What writing them found**, recorded and not decided here:

- **The authorize gate counted the asked, not the answered.** `authorize()`
  allowed an attempt where every policy consulted had abstained, against
  its own second and third rules and its test's own comment; one offline
  `opa` left a gate open. Fixed the same day in the capability: an attempt
  is allowed where at least one policy permits and none denies, and the
  denial says how many were asked. The runtime's tests and all fourteen
  technologies pass against it.
- **Section 3's row for `kerberos` cannot be built as written.** An AP-REQ
  seals the client principal; what is in the clear is the ticket's service
  principal, and that is what `identify/kerberos` presents. The second gate
  decrypts the ticket and learns the client, and has nowhere to hand it
  back: `Authenticator` answers `Verified` and nothing else. The same gap
  keeps a token's granted scopes from reaching `authorize/scope`. ADR-0054
  names it; it is a change to the capability's trait and the owner's.
- **Digest needs the request's method and address as evidence**, under
  `http.method` and `http.uri`, and the first gate does not write them; it
  verifies today only where a method is configured.
- **An API key in a query string is also in the arrival's address**, which
  other identifiers put on the record as evidence. The HTTP transport
  should strip it before the arrival is built, or the practice be refused.
- **Candidates to go up** (ADR-0044), built without: a hashed secret store
  with expiry (`api-key`, `bearer`); the Authorization scheme split and
  Basic decoding (five identify technologies); one DER reader (two
  Kerberos gates and `authenticate::x509`); a JWKS reader (`oidc`, `jwt`);
  a neutral rendering of the facts for outside engines (`cedar`, `opa`);
  the trailing-star match (three authorize technologies).

## Amendment, 2026-09-24: the candidates went up, each to one home

The owner, 2026-09-24: *code is placed once, and everything else uses it.*
The candidates of the amendment of 2026-09-19, and the copies the audit of
2026-09-22 found beside them, each have one home now, and every copy is gone.
Section 6 as it stands; nothing goes sideways.

| concept | home | read by |
|---|---|---|
| the `Negotiate` token to its AP-REQ's ticket: SPNEGO, GSS-API, bare | `identify::kerberos` | `identify/kerberos`, `authenticate/kerberos` |
| the NTLM AUTHENTICATE message | `identify::ntlm::Authenticate` | `identify/ntlm`, `authenticate/ntlm` |
| every evidence and proof name a claim carries across the gates | `identify::evidence` | the first gate's writers, the second gate's readers, `authorize/scope` |
| the clock and a credential's window | `authenticate::clock` | the ten verifiers that hold a time |
| JOSE keys and the choice of one | `authenticate::jose`, behind a feature | `jwt`, `oidc` |
| X.690, and an `OBJECT IDENTIFIER`'s contents | `xmip-core-library-asn1` | Kerberos, LDAP, X.509, SNMP, IEC 61850, directly |
| base 64 and base64url | `codec::base64` | every identity crate; the external `base64` crate is gone from all of them |
| the name an API key with no id goes by, `sha256:` and sixteen hex digits | `identify::api_key` | `identify/api-key`, `authenticate/api-key` |

- **Two readings changed where the copies disagreed.** A token was held
  valid for the second of its `exp` by `jwt`, `oidc` and `oauth2` and not by
  `saml`; RFC 7519 section 4.1.4 refuses it *on or after* `exp`, and the one
  window does. And where a token named no key, `jwt` tried the first key of
  its algorithm and `oidc` every one; every one is the rule.
- **Already one before this, confirmed:** the `Authorization` header and the
  Digest list (`identify::authorization`, quotes honoured as RFC 7616
  requires), SAML's unescaping and its principal (`codec::xml`,
  `identify::saml`), the `*` pattern (`authorize::pattern`), and the peer
  address `authorize/transport` reads (`net::PEER_ADDRESS`).
- **Not here, and why.** The SMB transport writes and reads an NTLM message
  of its own, a counted-field simplification rather than the specification's
  layout; reading it with `identify::ntlm` would make a transport depend on
  the identify capability, which is the owner's to rule on. The SSH names
  the SFTP transport writes and `identify/ssh-key` reads (`ssh.key`,
  `ssh.signature`, `ssh.session`) cross the transport's boundary, not the
  gates', and are left with the same question.

## Amendment, 2026-09-24: the NTLM layout is a library, and the gates share a secret store

The owner ruled the same day on the two questions the amendment above left
open. The first is here; the second — the names a transport writes — is
ADR-0019's, amendment 2026-09-24, and this record points there.

- **The NTLM message layout is `xmip-core-library-ntlm`**, mounted at
  `module/core/library/ntlm` beside asn1, codec, net and tls. It reads and
  writes all three messages — NEGOTIATE, CHALLENGE, AUTHENTICATE — and the
  `NTLMv2` client challenge inside a response, as [MS-NLMP] section 2.2
  lays them out. `identify::ntlm` and its test fixture are gone; so is the
  SMB transport's `ntlm.rs`, a counted-field simplification no other NTLM
  speaker would have understood, which now writes and reads the
  specification's layout through the library. `authenticate/ntlm` read the
  CHALLENGE's nonce and the MIC by offset; it asks the library for both.
  What is identity's own stays at the gates: that a NEGOTIATE claims
  nothing, a CHALLENGE is the server's and a type 3 naming no user claims
  no one (`identify/ntlm`), and the `NTLMv2` proof, the MIC's HMAC and the
  target and channel rules (`authenticate/ntlm`). Both capabilities' errors
  take the library's with `From`, as they take asn1's.
- **The hashed secret store with expiry is `authenticate::secret`**, the
  home the amendment of 2026-09-19 named as a candidate: a secret the node
  minted with full entropy, kept as its SHA-256 under the name it was
  issued to, with its expiry. `api-key` and `bearer` each carried one of
  their own — the same three fields and the same constant-time lookup under
  two names — and both are gone. Which names a key answers to, its id or
  its digest name, stays `api-key`'s.
- **`authenticate` re-exports nothing of the first gate's.** `pub use
  identify::Presented` let twenty crates name the claim through the second
  gate; each imports it from `identify` now.
- **`identify::evidence` keeps only the names that cross the gates inside
  identity.** The peer certificate's issuer and fingerprint and the first
  two NTLM legs are written by a transport before any gate runs, and are
  `context::property`'s with the rest of the transport's vocabulary
  (ADR-0019, amendment 2026-09-24); a test holds the two lists apart.

The table of the amendment above is superseded in two rows: the NTLM
AUTHENTICATE message is the library's, and the names a claim carries are
split between `identify::evidence` and `context::property` as said.

## Provenance

The sentence and the three tables are the assistant's, 2026-09-10, under the
owner's instruction to sort everything declared and not built. The traits
they lean on are ADR-0019's and ADR-0022's. Nothing was put to the owner as
a question because the records had already said what a gate is.

The rulings of the amendment "the NTLM layout is a library, and the gates
share a secret store" are the owner's, 2026-09-24: the library and where it
mounts, the secret store's home, the re-export's removal and what stays in
`identify::evidence`. The assistant drafted the text and chose the library's
shape.
