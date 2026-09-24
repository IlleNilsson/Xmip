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
  capability's trait and the owner's to rule on. *Closed by the amendment
  of 2026-09-19 below.*
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
- **NTLM's target name, from the specification.** Left out at first,
  because the name sits inside the NTLMv2 response's attribute pairs; the
  owner, the same day: *look at specs online, do your best.* [MS-NLMP]
  2.2.2.1 and 2.2.2.7 give the layout — sixteen bytes of proof, twenty-eight
  of client challenge, then pairs of identifier and length, with
  `MsvAvTargetName` 0x0009 the target's service principal name in UTF-16 —
  and 3.2.5.1.2 gives the server's rules. So the capability reads it once
  (`identify::ntlm::ClientChallenge`), `identify/ntlm` writes it as
  `ntlm.target` and, where the client does not flag it as taken from an
  untrusted source, as `principal.service`; and `authenticate/ntlm`, once
  the proof has verified, holds the client to the service the node says it
  is and refuses a response relayed from another server naming both. The
  same reading gave the response's timestamp, which the second gate now
  holds within thirty-six hours of its clock, the specification's
  `MaxLifetime` as current Windows sets it.
- **Not done, and said so in the crates.** `mutual-tls` reads no name of
  its own; the transport's handshake is where that certificate is verified.
  NTLM's MIC and channel bindings need the three messages and the channel,
  which only the transport holds. And the open point of the Consequences
  stands: a name learned only by verifying has nowhere to go.

## Amendment, 2026-09-19: the second gate hands back what it learned

The open point of the Consequences is closed. The owner, asked what was
still not done, the same day: *solve it.* The assistant read that as the
ruling the point was waiting for; the owner confirms or strikes it.

- **`Conclusion`, in the authenticate capability.** A verdict and the pairs
  of evidence the verifying itself gave. `Authenticator` gains
  `conclude(&Presented) -> Result<Conclusion, AuthenticateError>`, defaulted
  to the verdict of `verify` with nothing learned, so the fourteen
  mechanisms that learn nothing are untouched and `verify` keeps its
  meaning. The gate calls `conclude`.
- **What is learned takes the place of what was claimed.** On the identity,
  a learned pair replaces a presented pair of the same name: a claimed
  `principal.user` does not stand beside a verified one. Everything else
  presented is kept as before.
- **Adopted by the three that learn.** `kerberos` learns the ticket's
  client as `kerberos.client`, and as `principal.user` where it is one user
  in one realm. `oauth2` learns the answer's `scope`, its `client_id` as
  `oauth2.client`, and its `username` as `principal.user` where it is one.
  `jwt` learns the token's `scope`, which its signature covers.
- **A defect this found.** `authorize/scope` has read evidence named `scope`
  since it was written and said `oauth2` and `jwt` record it; neither
  could, so the policy denied every token. The name is now one constant,
  `authenticate::conclusion::SCOPE`, and both write it. *Since 2026-09-24
  it is `identify::evidence::SCOPE`, beside `principal.user` and
  `principal.service` and every other name a claim carries across the
  gates, and `authorize/scope` reads that constant rather than a string of
  its own (ADR-0050, amendment 2026-09-24).*
- **Not done.** `oidc` and `saml` learn nothing new: their names are in the
  token the first gate read, and the second gate already checks them.

## Amendment, 2026-09-19: NTLM's MIC and channel bindings

The same *solve it* covered the other thing left undone. Both were left
because they need what only the transport holds; the answer is that the
transport hands it over, as evidence and proofs already travel.

- **The channel is configuration.** `MsvAvChannelBindings` is the MD5 of a
  `gss_channel_bindings_struct` with empty addresses over
  `tls-server-end-point:` and the hash of the server's certificate (RFC
  5929). The node's certificate is the node's own, so the verifier is told
  it (`bound_to_channel`) and refuses a response bound to another channel,
  or to none: a response relayed from a TLS connection to someone else.
- **The MIC rides as proofs.** A transport that keeps the handshake's first
  two messages writes them as the properties `ntlm.negotiate` and
  `ntlm.challenge`; `identify/ntlm` carries them on as proofs, and
  `authenticate/ntlm` derives the exported session key ([MS-NLMP] 3.3.2,
  3.4.5.1, RC4 where key exchange was negotiated) and verifies the MIC over
  the three messages. The CHALLENGE presented must be the one the response
  proved under. `requiring_integrity` refuses a response whose MIC cannot
  be checked; without it an absent MIC is left alone, as before.
- **Checked against the published numbers.** The session base key and the
  decrypted session key are those of [MS-NLMP] 4.2.4, and RC4 is the
  keystream of RFC 6229.
- **Not done.** No transport of the estate runs the NTLM handshake, so no
  transport writes the two properties yet. `tls-server-end-point` is the
  only channel type built; `tls-unique` is not.

## Alternatives considered

**Widen `Verified` to carry the evidence.** `Verified` is `Copy`, lives in
the context crate and is matched in forty files across three capabilities;
a verdict is also not the place for a name. A second type beside it changes
four crates.

**A second pass, `learned(&Presented)`, after `verify`.** It would open a
ticket or ask an authorization server twice, and the second answer need not
be the first.

**Each technology parses what it meets.** That is what had begun, and two
technologies already disagreed about what a logon name is.

**Make the principal name the claim's value.** Simpler to resolve, and it
would change the meaning of every value already recorded and every Party
already registered by a mechanism's own name. Evidence beside the value
changes nothing that stands.

## Provenance

The requirement is the owner's, 2026-09-19. The two types, the canonical
form, the evidence names and the table are the assistant's drafting of it.
