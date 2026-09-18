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

## Provenance

The sentence and the three tables are the assistant's, 2026-09-10, under the
owner's instruction to sort everything declared and not built. The traits
they lean on are ADR-0019's and ADR-0022's. Nothing was put to the owner as
a question because the records had already said what a gate is.
