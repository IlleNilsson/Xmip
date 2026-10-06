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

*Wired 2026-09-29:* both GUIs take the role by this rule, once
(`RoleAssignment`, in `Xmip.Surface`, since the amendment of 2026-10-06): a
role the run states is the role, a word that is no role is Observer, and with
none stated the directory answers — the Playground's fake one allowing the
tester — and with no directory the role is Observer (ADR-0052, amendment
2026-09-29; the amendment of 2026-10-06 below).

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

## Amendment, 2026-10-03: an act from elsewhere is refused server-side

Found by an outside review the same day: a web host's surface hub
(`SurfaceHub` in `Xmip.Surface.Relay`, ADR-0052, amendment 2026-09-15)
forwarded every pause, resume and remove a remote surface asked for to the
host's surface without asking the host's role, and took who acted from the
caller's own argument. The TLS handshake proved a certificate and nothing was
done with it. A host assigned Observer still acted, as anyone who said so.

- **The role is enforced where an act crosses to the host.** Every act the
  hub serves — pause and resume a scope, pause and resume a Subscription,
  pause, resume and remove an Event subscription — passes one check,
  `GatedOperator` in `Xmip.Surface`, a surface over the host's own: an act
  is taken only where the host's assigned role may operate
  (`Roles.MayOperate`, Operator and up), and refused otherwise in words —
  `REFUSED.`, who, what, on what, and the role that refused it. Taken or
  refused, it is an audit record of the host's (ADR-0062), with who, the
  act, its target and the role.
- **Who acted is what the connection proved, never what the caller said.**
  The act is the subject of the client certificate the handshake checked
  against the host's anchors (ADR-0063 clause 1); no hub method takes a
  name any more, and `RemoteOperator` sends none. **On loopback without a
  certificate, the act is the host's own user.** The owner, the same day,
  *Go with A*: over loopback, where no client certificate is presented, an
  act takes the identity of the logged-on operating system user running the
  web host — `DOMAIN\user` on Windows, the user name elsewhere — because
  only someone logged on to that machine can reach loopback. From anywhere
  else without a certificate nothing was proven, and every act is refused,
  whatever the host's role, rather than taken on the caller's word. The rule
  is one, `GatedOperator.Proven`.
- **The role moved down to the layer that enforces it.** `Role`, `Roles` and
  `RoleContext`, with the rule that assigns it, are `Xmip.Surface`'s, beneath
  both GUIs and the relay, not `Xmip.Gui`'s: the hub could not see the role
  where it was. The rule is unchanged, and `AddXmipSurfaceRelay` takes the
  host's registered assignment, else that rule's answer.

What stays open is what the paragraph *Not yet enforced* above names: the
role a host runs as is still the run's to state until a directory grants it
to a proven principal. A certificate now proves who acts; which role that
principal holds is the directory's question, and the gate's answer comes
from the host's assigned role until it is asked. The screens of a host keep
shaping what they offer by the same role in their own process.

Provenance: the outside review of 2026-10-03; the check, its place and the
refusal without a proven identity are the assistant's drafting, for the
owner to overrule.

## Amendment, 2026-10-06: every act is the proven caller's, by the caller's role

Found by an outside review, the owner approving the repair the same day: the
amendment of 2026-10-03 gated what another machine asks over the surface hub
and left the browser's own path open. The web host took one role for its
whole run, a run that stated none was Developer, a browser presented no
certificate and was asked nothing, and every browser act was taken and
audited as the account the host runs as. The certificate gate on `/surface`
guarded remote surfaces, not the browser.

- **A browser is a proven caller, by the one rule.** Every request to a web
  host carries the caller its connection proved, `GatedOperator.Proven`: the
  subject of a client certificate the handshake checked against the host's
  anchors, else, over this machine's loopback, the operating system user the
  host runs as (the owner's *Go with A* of 2026-10-03), else no one.
  `ProvenCaller` in `Xmip.Surface.Relay` sets it as the request's user, and
  Blazor hands it to the circuit the request opens, so a circuit is one
  caller for its life. A browser nothing proved reads the pages (ADR-0063)
  and acts on nothing. The desktop's caller is the user running it.
- **The role is the caller's, by one rule for every host and the hub.**
  `RoleAssignment` in `Xmip.Surface`: a caller nothing proved is an
  Observer; a role the run states (`Role` in `xmip.gui.toml`, else
  `XMIP_ROLE`) is every proven caller's, as the amendment of 2026-10-03 left
  it until a directory is asked; else the directory the host is handed
  (`IDirectory`, ADR-0068) answers for the caller; else Observer. **An
  unstated role grants nothing.** `RoleContext` is the caller and that role,
  one per browser circuit, and is what every screen offers by.
- **The tester is God in the Playground only, by configuration.** The fake
  directory of the amendment of 2026-09-14 is `TesterDirectory`: it allows
  the user the host runs as every role and knows no one else. A host has it
  only where its configuration names it, `Directory = "tester"`, which
  `Start-XmipOperationWeb` passes to a host following a Playground roll; no
  name of a cluster, node or file decides it. A directory kind not built is
  no directory, so a misstatement grants nothing.
- **Every act passes `GatedOperator`, as its caller.** The screens act
  through the gate the hub uses — pause and resume a scope, a Subscription
  and an Event subscription, remove an Event subscription, replay a Message,
  retry and dismiss a Journey — not beside it: refused in words where the
  caller's role may not act, never taken under a name the caller gives, and
  audited as that caller, taken or refused, with the act, its target and the
  role (ADR-0062). The screens' own role checks and their refusal text are
  deleted; the gate is the one.

What stays open is what this record has said since 2026-09-14: which
directory group means which role, and the directories a production caller is
proven against beyond a client certificate — Kerberos and Active Directory,
the account behind an SSH key (ADR-0014, Reach) — are not built. Until they
are, a run that does not state a role grants Observer outside the
Playground.

Proved in `Xmip.Surface.Test` (`BrowserCallerTest`): an anonymous browser's
act is refused whatever the run states, an Observer is refused and audited
as themselves, an Operator's act is taken and audited under that Operator's
certificate subject and never the host's account, the Playground's tester
acts by the fake directory on loopback, and every request's user over the
wire is what its connection proved; and in `Xmip.Gui.Test`
(`JourneyActsViewTest`): a screen's act is audited as the browser's caller,
and one nothing proved is offered no act and the gate takes none.

Provenance: the outside review of 2026-10-06 and the owner's approval of its
repair; the per-caller assignment, the fake directory's configuration key
and the deletion of the screens' own checks are the assistant's drafting,
for the owner to overrule.
