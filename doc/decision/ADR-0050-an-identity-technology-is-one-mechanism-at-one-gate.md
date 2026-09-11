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
into `xmip-core-identify` (ADR-0044) as a catalogue of the mechanisms the
estate knows.

### 2. The traits, as they stand

- An identify technology implements `TransportIdentifier` (before the
  Message exists, given a `StreamArrival`), `MessageIdentifier` (after it,
  given the Message), or both where the mechanism travels on both layers.
  It answers `None` where the arrival carries nothing it recognises, a
  `Presented` claim marked passed, inferred or detected where it does, and
  an error only where it recognises something it cannot read.
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

The mechanism catalogue and the credential store the password, basic, digest
and scram verifiers share go up into their capabilities (ADR-0044). Nothing
goes sideways: `basic` does not depend on `password`; both depend on
`xmip-core-authenticate`.

## Consequences

- Fifty-one manifest entries gain a description; each names its trait.
- `xmip-core-identify` gains the mechanism catalogue; `xmip-core-authenticate`
  gains the credential store the four password-shaped verifiers share.
- Every technology is built offline and proven in-process; the ones that
  need a host facility (`pam`, `windows`) build where the facility is and
  refuse where it is not, as ADR-0045 requires.

## Provenance

The sentence and the three tables are the assistant's, 2026-09-10, under the
owner's instruction to sort everything declared and not built. The traits
they lean on are ADR-0019's and ADR-0022's. Nothing was put to the owner as
a question because the records had already said what a gate is.
