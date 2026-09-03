# ADR-0022: Identity classes and runtime isolation

- Status: Accepted
- Open against it: clause 3 is unsettled for the operator surfaces. ADR-0014's
  amendment made a surface hold runtime state in-process, so an operator session
  is a host process with an identity context; ADR-0027 adds a second reason to
  settle it and settles nothing. Open problem 20.
- Date: 2026-08-26
- Related: ADR-0019 (identity, Parties and direction),
  ADR-0009 (security roles versus Actor capabilities), ADR-0014 (operator surfaces)

## In brief

- Theme: Identity and security
- Subject: Identity classes, and who may run beside whom
- Name: Identity classes and runtime isolation
- Order: 3
- Concepts: Anonymous, federated, highAssurance, sharedSecret; Delegation, constrained and unconstrained; Identity context, co-residency; Kerberos; Regulated, enterprise, standard profiles

Four classes — `highAssurance`, `federated`, `sharedSecret`, `anonymous` —
derived from *how an identity is proven*, never configured. **Different identity
contexts must not share a host process.** Constrained and unconstrained Kerberos
delegation are distinct contexts even for the same principal. The `regulated`
profile isolates `highAssurance` at the node. A violation blocks startup.

*Identity, Parties and the two directions* settles which identity wins. This
settles which identities may co-reside, which is a different question with a
worse failure mode.

## Context

ADR-0019 answered *which identity wins* when transport and message disagree. It
did not answer *which identities may run beside each other*, and those are
different questions with different failure modes. The first is a correctness
question about a single Message. The second is a containment question about a
whole node, and getting it wrong is not a wrong answer — it is a breach.

The material for this decision was recovered from `_origins`, the early design
export, on 2026-08-26. It survived nowhere else: not in `docs/`, not in `src/`,
not in `architecture.toml`. It is written there in the retired Artifact and
Handler vocabulary and asserts a Rust-only runtime that ADR-0014 and ADR-0021
have since contradicted, so the vocabulary is translated here and the
contradicted parts are dropped. The isolation rules themselves are unaffected by
either.

BizTalk is the comparison again. A BizTalk host instance runs under one service
account, and the practice of separating receive, process and send into different
hosts exists precisely so that credentials do not pool. That separation is
convention there, achieved by an administrator who knows to do it. Nothing
enforces it, and nothing reports when it has not been done.

## Decision

### 1. Every identity carries a class

Four classes, and every identity Xmip authenticates or presents belongs to
exactly one:

| Class | Means | Examples |
| --- | --- | --- |
| `highAssurance` | cryptographic proof bound to a named principal | Kerberos, mutual TLS with a verified client certificate |
| `federated` | asserted by a trusted third party | OAuth 2.0, OIDC, SAML |
| `sharedSecret` | a secret that both sides hold | API key, username and password, HMAC |
| `anonymous` | no identity is claimed | open HTTP, anonymous FTP |

The class is a property of *how the identity is proven*, not of who it belongs
to or how much it is trusted. A Party may hold identities in several classes —
ADR-0019 already allows a Party to hold identities in both directions, and this
is the same latitude on a different axis.

Class is derived from the mechanism, never configured. An operator who could
declare an API key `highAssurance` would have declared away the only thing the
classification is for.

### 2. Identity context

An **identity context** is the full set of facts under which a credential
operates. Two credentials share a context only when every fact matches.

For Kerberos, the context is:

- realm or domain
- service principal
- delegation scope — unconstrained, constrained, or resource-based constrained
- the delegation allow-list, where one applies

**Constrained and unconstrained delegation are distinct identity contexts even
for the same principal**, because unconstrained delegation makes a ticket
usable against services the constrained case cannot reach. Treating them as one
context because the account name matches is the specific mistake this clause
exists to prevent.

### 3. Different identity contexts must not share a host process

This is the rule. Everything above is the vocabulary needed to state it.

A host process runs the work of one identity context. Where two Receive
Locations authenticate under different contexts, their work runs in different
host processes, and the runtime places them accordingly.

The reason is memory. A process holds tickets, tokens, session keys and
connection handles; process isolation is the boundary the operating system
actually enforces, and anything finer is a promise made by whatever code
happens to be running. Xmip loads third-party Modules across a C ABI
(ADR-0012), so "whatever code happens to be running" is not a hypothetical.

### 4. The regulated profile isolates highAssurance at the node

Under the `regulated` security profile (deployment-model.md), `highAssurance`
identity contexts require node-level isolation rather than process-level. A node
carrying a `highAssurance` context carries no other context.

This is deliberately expensive. It is the profile for estates where a shared
kernel is itself the finding, and an operator selecting `regulated` is asking
for that cost.

### 5. A violation blocks startup

**Fail closed.** A configuration that would co-locate two identity contexts does
not start. It is not a warning, it does not degrade, and it does not start the
compliant half.

The violation is logged as a security-critical failure (observability-model.md
section on failure classes) and appears in the Identity and Isolation Compliance
Report. That report is mandatory rather than optional, because the population it
matters to — auditors, security review boards — is exactly the population that
will not think to ask for it by name.

*Amended 2026-08-27.* This named ADR-0017 as the enforcement mechanism, on the
grounds that co-residency is "these two things may not run at once" and
exclusiveness already owned that sentence. ADR-0024 retired exclusiveness, and
the reassignment is a correction rather than a loss: **co-residency is decided
before anything starts, not contended for at runtime.** Which identity contexts
may share a host process is answered when the execution tree is built, by the
planner in `xmip-core-runtime`, and a Host Service that should not exist is
never spawned. A lease would have been enforcing a decision that was already
made.

## Consequences

- **Host process count is driven by identity, not by load.** An estate with
  eight distinct identity contexts runs at least eight host processes on any
  node that serves all eight. That is the intended cost and it should be visible
  in capacity planning rather than discovered in production.
- **Placement becomes a solver.** The runtime must satisfy node capability,
  identity context separation and configuration requirements together. Today's
  placement is simpler than that, and this is the clause that will force it to
  grow.
- **Anonymous is a context like any other.** Anonymous work does not share a
  process with authenticated work. It is the cheapest context to isolate and the
  one most likely to be reached by an attacker.
- **An operator can create an unsatisfiable configuration**, and will. The
  failure must name both contexts and the Receive Locations that declared them,
  because "identity isolation violation" without the two names is a message that
  sends someone reading configuration files for an afternoon.

## Alternatives considered

**Isolate by Party rather than by identity context.** Simpler to explain, and
wrong: one Party legitimately holds several credentials, and ADR-0019 depends on
that. Isolating by Party would either over-isolate a single trading partner or
under-isolate two contexts that happen to belong to the same one.

**Warn rather than block.** The conventional choice and the reason convention is
not enough here. A warning in a log that starts successfully is read once, by
nobody. ADR-0021 made the same argument about version floors: a rule that
reports and returns success is not a rule.

**Let the operator declare the class.** Rejected in clause 1. The value of the
classification is that it cannot be argued with.

**Thread or task isolation instead of process isolation.** Cheaper, and it
isolates nothing that matters: a compromised Module reads the address space it
runs in. Process isolation is the boundary the operating system enforces, which
is the only kind worth claiming in a compliance report.
