# ADR-0054: A principal name is read one way

- Status: Accepted
- Date: 2026-09-19
- Related: ADR-0019 (identity, Parties and direction), ADR-0022 (identity
  classes), ADR-0044 (a technology shares through its capability), ADR-0050
  (an identity technology is one mechanism at one gate), ADR-0033
  (certificates on Receive and Send)

## In brief

- Theme: Identity and security
- Subject: How a user principal name and a service principal name are read,
  written and compared, whichever mechanism carried them
- Name: A principal name is read one way
- Order: 8
- Concepts: User principal name, UPN; service principal name, SPN; principal evidence

**Identification and authentication by user principal name and by service
principal name are supported wherever a mechanism can carry one. The two
names are types in the identify capability, written in one canonical form,
and a technology that reads one puts it on the claim under one of two
evidence names, `principal.user` and `principal.service`. A Party is
resolved by a principal name whatever mechanism carried it.**

## Context

The owner, 2026-09-19, while the last identity technologies were being
built: *identification and authentication by user and service principal
name should be supported where it can.*

Nothing in the record had named either. The same two things were already
arriving under many names. A person or an account is `jane@partner-x.example`
to a directory, `PARTNERX\jane` to an older Windows logon, a client
principal to Kerberos, the `upn` claim to an identity provider and an
alternative name on a smart-card certificate. A service is
`HTTP/xmip.example@EXAMPLE.COM` to Kerberos, a target name to NTLM and an
application's identity to an authorization server. Left to each technology,
`authenticate/windows` had grown an `Account` that parses the first two
forms, `identify/kerberos` wrote a service principal as its value, and
neither could be compared with the other.

## Decision

### 1. Two types, in the identify capability

`UserPrincipalName` and `ServicePrincipalName`, with `PrincipalName` for a
reader handed text that must say which it is, live in `xmip-core-identify`
(`principal`), the crate every identify and authenticate technology already
depends on (ADR-0044). No technology parses a principal name itself.

- A **user principal name** is a user within a domain. It is read from
  `user@domain` and from the down-level `DOMAIN\user`; the last `@`
  divides, because a user part may hold one. A bare `jane` names a user and
  no domain, and is not one.
- A **service principal name** is a service class on a host, optionally at
  a port, optionally a named instance, optionally within a realm:
  `class/host`, `class/host:port`, `class/host/instance`, each optionally
  followed by `@REALM`.

### 2. One canonical form

Canonical means comparable. A domain and a realm fold to lower case, a host
folds to lower case, a user part keeps its case as written, and a service
class keeps its case because Kerberos compares it exactly. *The same
account* and *the same service* are their own questions (`is`): a user part
compares without case, as a directory compares a logon name, and a service
without a realm is the same service in whichever realm it is found.

### 3. Two evidence names

A technology that reads a principal name puts its canonical form on the
claim as evidence, `principal.user` or `principal.service`, beside whatever
its mechanism calls the claim. The claim's `value` stays the mechanism's
own, so nothing already recorded changes meaning. An authenticate
technology that proves a principal name says so in what it verifies; one
that only carries it leaves it as evidence, and evidence is never proof.

### 4. Where it can

| technology | user principal name | service principal name |
| --- | --- | --- |
| `username` | the presented name, where it is one | |
| `windows` | the logon name, either form | |
| `ldap` | the bind name, where the directory binds by it | |
| `ntlm` | the user and domain of the type 3 message | the target name, where the message carries one |
| `kerberos` | the client principal, once the ticket is decrypted | the ticket's service principal, in the clear |
| `certificate`, `mutual-tls` | the alternative name a smart-card certificate carries | |
| `jwt`, `oidc` | the `upn` claim, else `preferred_username` where it is one | the application a client-credentials token names |
| `oauth2` | `username` in the introspection answer, where it is one | the `client_id` of the answer |
| `saml` | the name identifier or the UPN attribute | |

Where a mechanism cannot carry one, nothing is invented.

### 5. A Party is resolved by it

A principal name is an identity a Party may hold, like any other value a
mechanism verifies (ADR-0019 clause 4). Registered once, it resolves the
same Party whether it arrived in a Kerberos ticket, an ID token or a
directory bind.

## Consequences

- `authenticate/windows` reads its logon name through the capability's type
  and drops its own `Account` parsing.
- `identify/kerberos` keeps the service principal as its value and adds it
  as `principal.service`; the client principal is sealed in an AP-REQ and
  becomes `principal.user` only at the second gate, which is the gap the
  next point names.
- **The second gate cannot yet hand a verified name back.** `Authenticator`
  answers `Verified` and nothing else, so a mechanism that learns the real
  name only by verifying — Kerberos, and an opaque token by introspection —
  has nowhere to put it. Recorded here as open; it is a change to the
  capability's trait and the owner's to rule on.
- The technologies adopt the type in the order they are touched; the table
  in clause 4 is the list.

## Adopted, 2026-09-19

Built the same day across the table of clause 4, each crate gated and
checked on disk.

- **The first gate writes the evidence.** `username`, `ntlm`, `kerberos`,
  `certificate`, `jwt`, `oidc` and `saml` put `principal.user` or
  `principal.service` on the claim in canonical form, and nothing where the
  text is not a principal name: an application's GUID is not a service
  principal name and is left alone. `certificate` reads a new transport
  property, `tls.peer.upn`, and parses no X.509. A token's principal is
  read once, by `Compact::principal` in the capability, because `jwt` and
  `oidc` both need it.
- **The second gate compares accounts, not strings.** `windows` is rebuilt
  over the capability's type and its own parsing is gone; `ldap` can bind
  by the user principal name itself, as Active Directory accepts, beside
  its DN template; `ntlm` meets a claim of `jane@partnerx` with a message
  for user `jane` in domain `PARTNERX`; `kerberos` compares the ticket's
  service through `ServicePrincipalName::is` and hands the client out as a
  `UserPrincipalName`; `oidc`, `oauth2` and `saml` take an expected user
  principal name and refuse another account naming both. `certificate`
  proves a user principal name by the one the verified leaf carries in its
  alternative names, under Microsoft's object identifier, read by
  `authenticate::x509`. Principal evidence on a claim is used only to
  refuse; the mechanism still decides.
- **Two things changed that a reader of `windows` would notice.** A domain
  now folds to lower case, so an account reads `corp\alice` where it read
  `CORP\alice`; and `a@b@c` is a name, user `a@b` in domain `c`, because
  the last `@` divides. Both follow from clause 2 and clause 1.
- **Not done, and said so in the crates.** `ntlm` writes no
  `principal.service`: the target name sits inside the NTLMv2 response's
  attribute pairs, which `identify/ntlm` does not open. `mutual-tls` reads
  no name of its own; the transport's handshake is where that certificate
  is verified. And the open point of the Consequences stands: a name
  learned only by verifying has nowhere to go.

## Alternatives considered

**Each technology parses what it meets.** That is what had begun, and two
technologies already disagreed about what a logon name is.

**Make the principal name the claim's value.** Simpler to resolve, and it
would change the meaning of every value already recorded and every Party
already registered by a mechanism's own name. Evidence beside the value
changes nothing that stands.

## Provenance

The requirement is the owner's, 2026-09-19. The two types, the canonical
form, the evidence names and the table are the assistant's drafting of it.
