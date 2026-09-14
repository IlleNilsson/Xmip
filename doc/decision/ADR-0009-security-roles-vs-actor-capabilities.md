# ADR-0009: Security Roles vs Actor Capabilities

## Status
Accepted.

## In brief

- Theme: Identity and security
- Subject: Security roles are not Actor capabilities
- Name: Security roles versus Actor capabilities
- Order: 4
- Concepts: Security roles; Observer, a read-only role

Two separate concepts that look alike and are constantly conflated. A security
role is what a human or Service Identity is permitted to do. An Actor capability
is what a runtime entity is able to do. Neither implies the other.

## Decision

Xmip security roles and actor capabilities are separate concepts.

## Security roles

Xmip user/security roles remain:

```text
Observer
Operator
Developer
```

These describe what a user or security principal may do in Xmip, least first.

## Actor capabilities

Actor capabilities describe what an Actor can do in communication and runtime execution.

Examples:

```text
Publish
Subscribe
OwnMessage
Report
Command
Execute
Route
Transform
Send
Receive
```

These are not user/security roles.

## Rule

Do not call actor capabilities roles.

Do not mix user/security authorization with runtime communication capability modeling.

A Receive Port can have the capability OwnMessage.

A user can have the role Operator.

Those are different dimensions.

## Amendment, 2026-09-06: the Observer role

The role set gains **Observer**, the least-privileged role: a principal who may
**watch and not act**. An Observer reads every monitoring surface — cluster
health, drill-down, history, recent activity — and performs no configuration and
no execution.

The owner's observation, 2026-09-06: the desktop Application offers **Monitor**
and **Configure**, and both are ways to interact, so the role set needs one that
observes only. It did — Operator was the floor, and Operator acts.

This aligns the roles with a distinction the estate already drew elsewhere.
ADR-0027 separates **observing from configuring at the boundary** — "an observer
watches, a configurer acts" — the read-only `XmipOperate` table versus the
separate configuration symbols. That was a distinction in the *code*; Observer
makes it a distinction in *who is at the keyboard*.

Mapped to the operator surfaces (ADR-0014):

| Surface | Observer | Operator |
| --- | --- | --- |
| Web (monitoring only) | yes | yes |
| Desktop **Monitor** | yes | yes |
| Desktop **Configure** | no | yes |

The roles are cumulative in what they may read and do: Observer watches;
Operator also configures; Developer also builds. Each includes what the one
before it can do.

The set is three — **Observer, Operator, Developer** — the owner's wording,
2026-09-06. The former **Executer** security role is retired: running work is a
node's job, described by the **Executor** *node role* (Reader / Writer /
Executor, `deployment-model.md`), not something a person is granted. The two were
one letter apart and one idea apart; only the node role remains.

**The role is the person's, not the surface's.** A person *is* an Observer,
Operator or Developer, and that role — not which surface they open — is what
grants their rights. Every surface reads the **same** assigned role (from
`Xmip:Role` or `XMIP_ROLE`, defaulting to Observer so a missing value grants
nothing) and shows it, so one person sees one role on the web and the desktop
alike. The role is **assigned, never chosen in the UI** — a person cannot promote
themselves.

What a surface then *offers* is the surface's own limit, separate from who you
are: the desktop offers Monitor and, to an Operator, Configure (an Observer who
reaches `/configure` is sent back to Monitor); the web offers monitoring only
(ADR-0014), whatever role is at the keyboard. So an Operator on the web is still
shown as Operator — the surface simply has less to offer there, not a smaller
person. Assigned stands in until a proven identity gates it (ADR-0022/ADR-0027).

**Not yet enforced.** No surface gates on role today — a surface holding runtime
state in-process is a host process, and ADR-0022 clause 3 with the identity
question ADR-0027 flags as *blocking shipping* must be settled before a role is
enforced rather than merely defined. This records the role and its surface map;
the gate is future work behind that settlement.

## Amendment, 2026-09-14: the web is no longer monitoring only

The table above says *Web (monitoring only)*. ADR-0014's amendment of the
same day withdraws that limit: the web GUI offers, by role, what the desktop
offers — an Observer watches, an Operator also acts and configures, and a
Developer also opens the specific point's configuration from its scope
(ADR-0052, amendment 2026-09-14). The roles stay the three named above and
stay cumulative; what changes is that the web surface stops offering less
than the role at the keyboard may do. Still not enforced, for the reason the
paragraph above gives.

**Where the role comes from**, the owner, the same day. Running for real, a
principal's role is **authorized by a directory** — the group membership the
remoting session already proved, Kerberos and Active Directory on one path,
the account behind the SSH key on the other (ADR-0014, Reach). Xmip keeps no
user store and assigns no role of its own; it reads which of Observer,
Operator and Developer the directory grants the proven identity. Running the
tests without a directory, **the tester is God** — the owner's words: the
person who started the run holds every role and is refused nothing, unless
the run says otherwise, because a playground roll is that person's own
machine and their own doing (ADR-0028), and a gate there would guard
nothing. The owner's later wording the same evening: the playground has no
directory, it has a **fake directory** that allows the tester — so a surface
run over a roll asks a directory like any other and is told yes, and the
role gate has one code path, not a test-mode bypass. Which directory group
means which role is configuration, not code, and is not yet written.

A test run that wants the real thing says so: `Start-XmipTest` gains
**`-Directory`** beside `-OnlineNodes`, the owner's wording, naming the
directory the roll authorizes its roles against — the run switch that turns
God into a proven principal for that roll. A type alone is not enough to
reach one, the owner added: the parameter carries **three things — the kind,
the name and the address** — the kind says how to ask, the name says which
directory (a domain, a tenant, a realm), and the address says where (a
domain controller, a tenant endpoint, an LDAP URL), because a name resolves
differently from each machine and an address alone does not say what it is.
The kinds are the directories the remoting paths already prove against,
and the parameter is built when the gate it feeds exists, not before: a
parameter the playground cannot honor is a stub, and the playground does not
simulate (ADR-0028).
