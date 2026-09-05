# ADR-0019: Identity, Parties and the two directions

- Status: Accepted
- Date: 2026-08-25
- Related: ADR-0006 (send-side identity inheritance), ADR-0007 (communication
  domain model), ADR-0008 (Xmip entities as actors), ADR-0009 (security roles
  versus actor capabilities), ADR-0013 (disposition and the Journey model)

## In brief

- Theme: Identity and security
- Subject: Identity, Parties and the two directions
- Name: Identity, Parties and direction
- Order: 1
- Concepts: Alignment, misalignment; Authentication, authorization, and their order; Kerberos; Party; Receive Location, Receive Port

A Receive Location declares a **closed set** of identities and mechanisms it
accepts; anything else is refused at authentication and is not attempted
against the others. Authentication precedes authorization. A Send Location
presents its configured identity outward. A Party holds identities in both
directions.

Where transport identity and message identity disagree, the model is DMARC's:
**alignment, not precedence**.

## Context

Three things were true at once and none of them fitted together.

**ADR-0006 settled the send side** in 2026 and settled it correctly: a Send
Location resolves the identity it exposes independently of any receive-side
identity, inheriting up through Send Port and Send Port Group to the Sending
Process. Targets only care which identity Xmip presents.

**The receive side had no counterpart.** Nothing said what a Receive Location
accepts, or whether it accepts anything a caller happens to present.

**`xmip-core-party` existed with no identity semantics.** The manifest
described it as "Xmip Party model and associations", and nothing connected a
Party to a credential in either direction.

Meanwhile the identity model was accreting inside ADR-0013, which is about
message disposition. Two layers, alignment policy, the WCF and DMARC
precedents — none of that is disposition, and it had grown to a third of that
record. This ADR takes it, and ADR-0013 keeps the lifecycle and what Xmip
retains at each refusal.

## Decision

### 1. A Receive Location declares what it can authenticate

A Receive Location configures a **closed set** of identities and mechanisms it
accepts. An identity presented by a mechanism the Receive Location does not
declare is refused at authentication. It is not attempted against the other
configured mechanisms, and it is not attempted at all.

```toml
[receive.location.partner-x]
transport = "https"

  [receive.location.partner-x.accept]
  mechanism = ["mutual-tls", "oauth2"]
  party     = ["partner-x"]
```

Trying every configured mechanism against every caller is how credential
stuffing across mechanisms works, and how a downgrade to the weakest configured
scheme works. It is also slow, in the one place in Xmip where latency is paid
by the caller waiting on a connection.

This is the receive-side mirror of ADR-0006, and the reason both exist: **a
Receive Location declares what it accepts, a Send Location declares what it
presents.** Neither infers anything from the other.

### 2. Authentication always precedes authorization

The gate order in ADR-0013 is not an implementation detail and does not vary by
transport:

```text
identity  ->  authentication  ->  authorization
who is claimed    is the claim true    may this true identity do this
```

An unauthenticated identity cannot be authorized, because there is nothing to
authorize — only a claim. Where a Receive Location accepts anonymous callers,
**anonymous is an authenticated outcome, not a skipped gate**: the claim is
"nobody", it is verified as such, and authorization then decides whether nobody
may post here. Most of the time it may not, and that decision is made once, in
authorization, rather than scattered across every handler.

### 3. A Send Location presents a configured identity

ADR-0006, unchanged, restated here as the mirror:

```text
Send Location
Send Port
Send Port Group
Xmip Sending Process
```

The first identity found is presented. Transport handlers receive the resolved
identity and apply it with their own technology-specific mechanism — an
X.509 certificate on FTPS, a bearer token on HTTP, an SSH key on SFTP.

On send, **Xmip is the client**. It is somebody else's producer, arriving at
somebody else's Receive Location, and the symmetry is exact:

| | Receive | Send |
| --- | --- | --- |
| Xmip is | the server | the client |
| The counterparty is | the producer | the consumer |
| Identity is | accepted | presented |
| Configured on | Receive Location | Send Location, inherited upward |
| Governed by | this ADR, clause 1 | ADR-0006 |

### 4. The Xmip Party is the identity holder, in both directions

A **Party** is the thing that has identities. It is not a credential store and
not a role; it is the actor, per ADR-0007 and ADR-0008, and its identities are
how it is recognised.

```text
Party  partner-x
  identity  mutual-tls    CN=partner-x.example        accepted on receive
  identity  oauth2        sub=partner-x               accepted on receive
  identity  edi-x12       ISA06=PARTNERX              accepted on receive
  identity  sftp-key      SHA256:...                  presented on send
```

- **On receive**, a Receive Location names the Parties it accepts. Authentication
  verifies the presented credential and resolves it to a Party, or refuses.
- **On send**, a Send Location names the Party whose identity it presents, and
  the transport handler applies it.

One registry, two directions. The alternative — credentials configured inline
on every Receive and Send Location — means a partner's certificate rotation is
a search across the estate rather than one edit, and it means nothing can
answer "what does partner-x use to reach us, and what do we use to reach them".

A Party's identities are **per direction and per mechanism**, because they
genuinely differ: the certificate a partner presents to Xmip is not the
certificate Xmip presents to that partner.

Security roles remain separate from Party identity, per ADR-0009. A Party is
recognised; a role is granted. Resolving a credential to a Party answers
authentication, and authorization is a separate question asked afterwards
against that Party.

### 5. Identity travels on both layers

Identity is not the property of one layer. It may travel on the **transport**,
on the **message**, or on both, where the technology makes it feasible and
configuration asks for it.

```text
transport   TLS client certificate, Kerberos ticket, bearer token, SFTP key,
            the permissions and path of a drop folder
message     EDI interchange sender qualifier and id, SOAP WS-Security header,
            a signed JWT inside the payload, an HL7 MSH sending application
```

Neither substitutes for the other, because they answer different questions. The
transport says who opened the connection. The message says on whose behalf the
content was produced.

Feasibility is a property of the technology and is not negotiable by
configuration. A file dropped in a folder carries no transport credential, so
its identity is implied by circumstance — the path, the permissions, the source
address — and verified as that. A raw CSV carries no message identity at all.

This is why the mandatory pass is transport and the optional pass is message,
rather than one configurable pass over whichever happens to be present.
Transport security always has *something* to verify, even when that something is
a circumstance. Message security often has nothing.

**The line between them**, derived from the gate order and needing no new
concept:

> Anything Xmip can read before Message creation is **transport** identity.
> Anything that requires the Message to exist is **message** identity.

So an HTTP `Authorization` header is transport, even though it is not TLS — it
is in the request envelope, readable before deserialization. A WS-Security
header inside a SOAP envelope is message, because reading it means parsing the
body, and Xmip does not parse content from an unauthorized sender.

`docs/architecture/identity-by-technology.md` sorts the whole estate by this
rule, per transport and per representation, against the standards.

### 6. Where both exist, both are recorded and neither is discarded

Message Context carries the transport identity and the message identity
separately, each with the evidence that authenticated it, the layer it came
from, and the Party it resolved to. Collapsing them into one `identity` field
loses the distinction exactly when it is needed — a dispute about who sent what
is a question about both.

Authorization is evaluated per layer. Transport authorization answers whether
this connection may post a Stream into this Receive Location at all. Message
authorization answers whether this named Party may send this contract on this
Path. Both must pass where both apply, and neither implies the other.

### 7. Disagreement is configured alignment, not precedence

"Which identity wins" is the wrong question, and asking it produces a rule
wrong for half the estate:

| | Authoritative for |
| --- | --- |
| **Message identity** | who the Journey is **for** — Subscription matching, Party resolution, contract selection, billing |
| **Transport identity** | who is **accountable for the transmission** — audit, rate limiting, credential revocation, non-repudiation of delivery |

Disagreement is not an error. It is the normal case for a relaying VAN, a
service bus, an API gateway and a managed file transfer broker — every
arrangement where one authenticated connection carries traffic for many
Parties. A platform that treats misalignment as a fault cannot integrate with
any of them.

Where they must agree, configuration says so. **This is DMARC's structure and
Xmip adopts it deliberately**: SPF proves the envelope sender, DKIM proves the
author domain, and DMARC is neither — it is the alignment policy between them
plus what to do when alignment fails. The same problem, a decade in production
on internet mail, standardised as RFC 9989.

```toml
[receive.location.partner-x.identity]
alignment      = "none"      # none | relaxed | strict
onMisalignment = "accept"    # accept | quarantine | reject
```

| `alignment` | Means |
| --- | --- |
| `none` | record both, never compare. The relaying case. |
| `relaxed` | the same Party through a different endpoint, matched at the Party rather than at the credential |
| `strict` | transport credential and message identity must resolve to the same Party |

| `onMisalignment` | Effect |
| --- | --- |
| `accept` | proceed, misalignment recorded in Message Context and audited |
| `quarantine` | to the Xmip DMQ with both identities and the alignment result, per ADR-0013 |
| `reject` | refused at message authorization |

**The default is `none`.** A default of `strict` would refuse every relayed
integration on the first day, and the failure would present as a routing bug
rather than a policy decision — which is precisely how this goes wrong in
products that ship the other default.

Because alignment is expressed at the Party rather than at the credential,
`relaxed` is meaningful: a partner reaching Xmip through two endpoints with two
certificates is still one Party, and still aligned with its own `ISA06`.

Two degenerate cases close the rule:

- **No message identity.** The transport identity is authoritative for both
  questions and alignment is vacuously satisfied. This is most of the estate.
- **No presented transport identity.** The circumstance *is* the transport
  identity — implied, and authenticated as such. A partner drop folder is not
  an absence of identity.

### 8. A Stream arrives three ways, and an identity is established three ways

A Stream gets into Xmip by being **pushed** (something connects and sends it),
**detected** (Xmip is watching a folder, a queue, a table, and it appears) or
**scheduled** (a timer fires and Xmip goes and fetches it). All three are
arrivals and all three run the same gates. Only the first has a caller.

Independently of that, an identity is established by being **passed** (the
sender presented it), **inferred** (the configuration says so — this folder,
this schedule, this credential Xmip used to go and get it) or **detected** (read
out of what arrived — `ISA06`, a signature, an envelope).

**Both are recorded, and neither implies the other.** A pushed Stream can yield
a detected identity: a partner posts an X12 interchange over plain HTTP and the
only name anywhere is inside the envelope. A scheduled pickup can only ever
yield an inferred identity, because there was nobody there to pass anything —
and the credential in play was Xmip's own, which proves something about Xmip and
nothing about the source.

This is provenance, not strength. **Inferred is not weak by definition and
passed is not strong by definition:** a drop folder reachable only over a
dedicated line says more than a bearer token pasted into a header. Strength is
the mechanism's class and assurance, which are ADR-0022's.

Both values are declared by the module that did the work and are never
configurable, for the reason ADR-0022 clause 1 gives about class: an operator who
could relabel an inferred identity as passed would have relabelled away the only
thing the record is for. When a Journey is disputed, *was it proven* answers
whether the claim held; this answers why there was a claim at all, and a record
with only the first cannot tell a forged certificate from a folder that anyone on
the network could write to.

## Consequences

- `xmip-core-party` owns the Party and its identities, and gains a reason to
  exist beyond "model and associations".
- The identity vocabulary — mechanism, layer, class, assurance, purpose, and
  clause 8's two — lives in `xmip-core`. `xmip-core-identify`, `-authenticate`
  and `-authorize` depend on it and **never on `xmip-core-party`**, which is what
  `architecture.toml` already said. The gates answer with a `PartyId`; resolving
  the Party happens elsewhere. Proving a credential and knowing whose it is are
  different questions, and a gate able to see the answer to the second would
  eventually decide something with it.
- `xmip-core-authenticate` resolves a presented credential to a Party.
  `xmip-core-authorize` decides what that Party may do, and owns alignment
  evaluation.
- `xmip-core-context` carries both identities, their evidence, their layer,
  their resolved Party and the alignment result. Five facts, none discarded.
- `xmip-core-receive` gains the accepted-mechanism set on a Receive Location.
  `xmip-core-send` is unchanged: ADR-0006 already specified it.
- ADR-0013 loses its identity sections to this record and keeps disposition.
  Its clauses 8 and 9 are clauses 6 and 7 here.
- A Receive Location that declares no accepted mechanism accepts nothing. That
  is a deliberate failure mode: an unconfigured endpoint is closed, not open.

## Open

- **Whether a Party may be recognised by an unverified message identity alone.**
  A `ISA06` with no transport credential behind it is a claim. Clause 7 makes
  the transport identity authoritative for accountability, which implies the
  answer is no, but EDI over a shared drop folder is a real deployment and it
  deserves an explicit ruling rather than an inference.
- **Party hierarchy.** ADR-0007 makes communication domains recursive —
  organisation, company, fleet, department, device. Whether identity inherits
  down that hierarchy, so a fleet certificate authenticates a ship, is not
  decided here.

## Amendment, 2026-09-05: identity is three stages, not two

This record paired *authentication and authorization*; identity is **three**
stages, and the estate is three capabilities to match. The owner's articulation,
2026-09-05: *identify, authenticate the identity, check if the identity may do
what it claims — authorization.*

1. **Identify** (`xmip-core-identify`) — determine the *claimed* identity: a
   certificate subject, an `ISA06`, an OAuth `sub`. A claim, extracted, nothing
   proven. This is a stage of its own, not the front of authentication.
2. **Authenticate** (`xmip-core-authenticate`) — prove the claim holds: the TLS
   handshake, the certificate chain, the shared secret. Only now is there a
   caller rather than a claim. Authentication runs only for a declared mechanism
   (the closed set above).
3. **Authorize** (`xmip-core-authorize`) — decide whether that proven identity
   may do what it is asking. A proven identity is not a permission (ADR-0009).

The order is fixed and the stages never collapse: a claim that is not proven is
not a caller; a caller that is not authorized is refused with the reason. Where
clause text says "authentication precedes authorization", read the full chain:
**identify precedes authenticate precedes authorize.**
