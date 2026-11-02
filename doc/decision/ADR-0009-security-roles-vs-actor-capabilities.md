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
(`MessageActsViewTest`): a screen's act is audited as the browser's caller,
and one nothing proved is offered no act and the gate takes none.

Provenance: the outside review of 2026-10-06 and the owner's approval of its
repair; the per-caller assignment, the fake directory's configuration key
and the deletion of the screens' own checks are the assistant's drafting,
for the owner to overrule.

## Note, 2026-10-12: the gate is the runtime's

The one check of the amendments above — who acts is what the connection
proved, and only a role that may operate acts — is written once in Rust
(`plane::role`, `xmip_operate.h` section 18) and asked by `GatedOperator`
and by a node's operate listener alike (ADR-0014, amendment 2026-10-12), so
a screen and a node refuse in the same words. On the operate listener every
caller is proven by its client certificate, and its role is the one the
node's `[operate] role` states, Observer where it states none; no directory
is asked there yet.

## Amendment, 2026-10-21: loopback proves where a caller is, not who

**Amends the amendment of 2026-10-03, where an act over this machine's
loopback without a certificate was the host's own user (the owner's *Go
with A*), and the amendment of 2026-10-06, which carried that to every
browser.** Raised by the outside review of 2026-10-08 (open problem 35):
with a role stated for the run, or a Playground host's tester directory,
another user on the machine acted as the host's account, and a reverse
proxy forwarding to loopback gave remote callers the same trust. Decided
by the owner, 2026-10-19: *local callers are proven by the operating
system*, through a named pipe or a Unix socket's peer account, and *tcp
loopback is no longer trusted by itself*.

- **A connection is proven by what it presents, never by where it comes
  from.** `GatedOperator.Proven` takes the client certificate's subject and
  nothing else; its loopback branch is deleted with every use
  (`ProvenCaller.Of`, the web host's middleware, the surface hub). A
  browser on this machine's loopback presents a certificate as a browser
  anywhere does; one that presents none watches and acts on nothing, the
  tester directory notwithstanding. Plain HTTP on loopback stays ADR-0063
  clause 1's one exception for what the wire carries, and grants nothing.
- **A surface on the node's machine is proven by the operating system**,
  on the node's local endpoint: the account its process runs as, read from
  the connection (ADR-0014, amendment 2026-10-21). That is the one way
  xmip-cli, the PowerShell module and both GUIs reach a node on their own
  machine, all through `xmip_remote_open_local_v1`. The desktop host's own
  caller stays the user running it: a process is its operating system
  user, which the node then proves again for every act it takes.
- **The runtime's refusal says it.** `plane::role::admitted` refuses a
  caller nothing proved as *the identity the connection proved — a client
  certificate, or on the node's local endpoint the account the operating
  system names — never from what the caller says, nor from where it
  connects*.

Proved in `Xmip.Surface.Test` (`BrowserCallerTest`): a browser on loopback
without a certificate is no one, an Observer, and its act is not taken
even where the tester directory is configured; every request's user over
the wire is what a certificate proved, and *nobody* over plain loopback.

**Drafted, for the owner: how the Playground's tester acts in the web
GUI.** The tester directory allows the user a host runs as, whom a browser
no longer is. Recommended: `Start-XmipOperationWeb` serves a roll's host on
`https://127.0.0.1` under the roll's cluster authority, the tester presents
an operator certificate (`New-XmipCertificate -Operator`, ADR-0034,
amendment 2026-10-15), and the tester directory knows the tester by that
certificate's subject. Decided and built 2026-10-21 (the amendment below).

Provenance: the owner's decision of 2026-10-19, quoted; the deletion's
reach and the tester's draft are the assistant's, for the owner to
overrule.

## Amendment, 2026-10-21: the Playground's tester acts in the web GUI with an operator certificate, in Xmip's own TLS

**Decided by the owner, 2026-10-21**, as the amendment above drafted it:
*the Playground tester in the web GUI acts with an operator certificate: the
roll's host serves https on 127.0.0.1 under the roll's authority, the tester
presents a certificate from `New-XmipCertificate -Operator`, and the tester
directory knows that certificate's subject. Use Xmip's own TLS (dogfood),
never the platform's.* And on the names, the same day: *Why not call it
SecureSurface, we do not know what comes after TLS* — and, widening it:
*Over all technology and security should not be in functions, parameters is
ok.* A type is named by the capability (`SecureSurface`, `SecureListener`,
`SecureSession`); no function, method or export names a technology or a
protection, which is a parameter (`Protection::Tls`, `XMIP_PROTECTION_TLS`);
only `xmip-core-library-tls`, which is TLS, keeps the technology's name.

Built the same day:

- **Xmip's own TLS serves the web host's HTTPS.** Kestrel's own HTTPS — the
  platform's TLS — is deleted with every use. The runtime listens, finishes
  each handshake and hands the host plain sessions (`secure_listener.rs`;
  `xmip_operate.h` section 21: `xmip_listener_open_v1` taking the
  protection, `xmip_listener_accept_v1`, `xmip_listener_stop_v1`, and a
  session's `xmip_session_peer_v1`, `_read_v1`, `_write_v1`, `_close_v1`),
  asking a client for a certificate and verifying one presented against the
  anchors, a client presenting none let through to watch
  (`tls::Identity::server_asking`); a certificate refused ends the handshake
  and is told to the host's audit. `Xmip.Surface.Relay`'s `SecureTransport`
  is the host's listener for every https address
  (`SurfaceBinding.UseSurface`), each session carrying the client's
  certificate where Kestrel reads it, so `ProvenCaller` is unchanged; a
  plain loopback address keeps Kestrel's sockets. `SurfaceTls` is
  `SecureSurface`, holding the files alone; https names its anchors, the
  operating system's trust store never one.
- **The roll's authority** is kept under the Playground's area
  (`Get-XmipPlaygroundLayout`'s `Authority`,
  `Initialize-XmipPlaygroundAuthority`), made where none is kept
  (`provision::Issuer::kept_or_made`, which internal-ca's authority calls
  too), and issues the host a certificate for 127.0.0.1 as an iPAddress
  alternative name (`provision::host::issue_into`, `xmip_host_issue_v1`).
  One authority serves every roll, since one host serves several. Beside it
  `operator.toml` names it in `[provision.operator]`, so the tester's
  request is signed by it.
- **The tester directory knows the tester's subject**: `TesterDirectory`
  allows the user the host runs as — the desktop's caller — and the subject
  `Xmip:Tester` names, `CN=<person>`; `Start-XmipOperationWeb -Tester
  <person>` passes it. Over a roll the host binds `https://127.0.0.1:5087`
  under the roll's authority.
- **The tester's way**: `New-XmipCertificate -Operator <person> -Path
  <folder>`, the host started once so the authority exists,
  `New-XmipCertificate -Request <folder>/operator.csr -Configuration
  .local-work/playground/authority/operator.toml -Path
  <folder>/operator.pem`, the certificate and key loaded into the browser and
  `authority.pem` trusted there.

Proved by `Xmip.Surface.Test` (`BrowserCallerTest`: the tester's
certificate acts with the tester's role, another certificate or none does
not; the scheme is https), `Xmip.Abi.Test`'s section 21 checks,
`test/PlaygroundAuthority.Test.ps1`, and the built host over https on
127.0.0.1: a roll-signed `CN=alice@example.org` was answered, and so was a
request presenting nothing. Not proved: a real browser.

Not built: a PKCS#12 form for a browser to import; a failed handshake other
than a refused certificate, which is passed over unaudited; a cap on
handshakes in flight. The authority's lifetime of 365 days and a host
certificate's of 30 are the assistant's, for the owner to overrule.
Functions elsewhere that name a technology or a protection — the exports
`xmip_security_role_named_v1` and `xmip_security_role_words_v1`,
`SecureSurface.Pem` and `KeptPem`, `transport::Configured::guarded_by`, the
runtime's `receive_certificate` and `ffi::remote::identity` — are left for
a sweep of their own.

Provenance: the decisions and both naming rules are the owner's, quoted;
the exports' shapes, one authority for the whole Playground and the
lifetimes are the assistant's.

## Amendment, 2026-10-29: every plane admits a call before it reads it

Found by an audit of the secrets' path (ADR-0019, amendment of this date):
the Storage wire answered any certificate under the cluster's anchors —
a person's operator certificate included — every operation, the secrets'
too; and a node's operate listener read a call's message before it
decided who might ask it, and never asked at all of the publication, its
wait or the secrets' listing. Decided by the assistant, for the owner to
overrule:

- **One admission for every plane Xmip serves its own parts**,
  `authorize::plane::admit`: from what the connection proved — who, and a
  standing ranked least first — and the plane's rules, each the least
  standing that may ask an action and an operation, `*` an action's every
  other operation. Nothing proved asks nothing; an operation no rule names
  is refused. The Storage wire asks it, an Event cluster's serving end is
  to.
- **The Storage wire admits nodes alone**: a certificate that
  authenticates a server — a node's, both ways — asks every read and
  write, and one that authenticates a client alone — a person's — is
  refused in words and its connection closed (`persist::storage::server`,
  `RULES`; `tls::peer::authenticates_servers`). The secrets' operations
  are named in the rules apart, so no broader rule later grants them.
- **A node's operate listener decides before it reads**: by the call's
  method, the identity and the role, `plane::role::admitted`, the one
  check, which takes the method — the publication and its wait to anyone
  proven, an act, a secret set and the secrets' listing to an Operator and
  up (`plane::role::RULES`) — and only then reads the call's message. A
  screen's act asks the same check through `xmip_act_admitted_v1`.

Not decided: finer rules by a node's roles — which node may read a secret
— since a node's certificate does not say its roles.

## Amendment, 2026-11-01: the operate plane's caller, through the one gate

Open problem 59's draft, built: the owner, 2026-10-29, *First you present
your identity, then you get identified. Then we look to authentication, do
your identification hold up. When authenticated we look for
Authorization*, and ADR-0019's amendment of 2026-10-30: no identity
reaches authorization *without an authenticator having checked it*. The
operate plane took its caller around that gate: the listener read a
certificate's subject (`plane::served`) or the local endpoint's account as
a bare name and handed it to the role check as proven;
`xmip_act_admitted_v1` took a host's word for proof, a `proven` byte; and
`GatedOperator.Proven` called any non-empty subject proven, in .NET's
spelling of it.

- **The plane's claim goes through `authenticate::authenticate`**, read
  once in `plane::caller` for every plane: a certificate's subject as
  `mutual-tls`, its handshake the proof, and the local endpoint's account
  as `peer-credentials`, *detected* from the connection, the operating
  system's word the proof. Each plane accepts the one mechanism its
  connection carries; an operator is no Party, so the registry is empty.
  A refusal ends the connection, told to the node's audit.
- **Two verifiers beside `Circumstance`**, since every node's operate
  listener proves every caller (ADR-0050, amendment 2026-10-20):
  `authenticate::PeerCredentials`, proven only for an account the system
  named, and `authenticate::Handshake`, the handshake's rule moved down
  from the `mutual-tls` technology, which now asks it before it narrows by
  issuer — a platform service may not depend on a technology
  (`architecture.toml`), and the rule has one home.
- **`plane::role::admitted` takes the authenticated identity**, and only
  one the gate called *proven* is anyone; vouched, claimed and refused act
  on nothing. A screen's act is admitted by the same rule
  (`role::act_admitted`).
- **`xmip_caller_proven_v1`** (`xmip_operate.h` section 21) answers who a
  web host's browser is: the session's certificate through the same gate,
  the identity it answered, empty for no one. `SecureConnection` carries it
  as a `ProvenConnection`, and `ProvenCaller` reads it and nothing else.
  `xmip_act_admitted_v1` loses its byte, and its `who` then the
  handle below.
- **`GatedOperator.Proven` is deleted** with every use; a subject a host
  reads off its connection proves nothing.

Today's rule stays: a caller nothing proved acts on nothing.

**Closed the same day: a caller crosses as an opaque handle, never a
name.** `xmip_act_admitted_v1` took the name its host passed, so a host
passing a name the runtime never answered was believed. Built
(`xmip_operate.h` sections 18 and 21; decided by the assistant, each in
one line):

- **The runtime hands out a handle for every caller its gate proved**
  (`plane::held`): a 64-bit number from the operating system's random
  source (`codec::random`), never 0, which is no one; the identity the gate
  answered is kept behind it, and `xmip_act_admitted_v1` takes the handle
  in place of `who`. A handle unknown, released, revoked, expired or forged
  is no one.
- **`xmip_caller_proven_v1` hands out the session's** (`out_caller`), the
  name beside it for display alone.
- **Each holder holds its own and releases it**: a browser's circuit, which
  outlives the session, takes its own (`xmip_caller_hold_v1`,
  `HeldCaller.Hold`) and releases it when the circuit ends
  (`xmip_caller_release_v1`, the scoped `RoleContext` disposed); the
  session releases its own when it ends.
- **No handle outlives what proved it**: past the certificate's `notAfter`
  (`authenticate::x509::not_after_of`) it is no one, and stopping the
  listener revokes every handle its sessions proved and any it would hand
  out after (`plane::held::revoke`). At most 65536 are held; past that a
  new caller is no one.
- **The desktop's caller is the runtime's word, not .NET's**:
  `GatedOperator.HostUser`, the environment's user name, is deleted with
  every use; `xmip_caller_process_v1` reads the account this process runs
  as from the operating system — its own token on Windows
  (`net::pipe::running_as`), its effective user on Unix — and proves it as
  `peer-credentials`, the same reading a local endpoint makes of a process
  connecting (`plane::local::running_as`); the tester directory knows that
  name (`RoleAssignment.ProcessCaller`).
- **The .NET side carries the handle**: `HeldCaller` in `Xmip.Abi`,
  `SecureSurfaceSession.Caller`, `ProvenConnection`, `ProvenCaller` (the
  handle in the request's `xmip-caller` claim, a circuit holding its own),
  `RoleContext.Caller` and `GatedOperator`; `RoleContext.Who` and
  `HeldCaller.Name` are for display.
- **The local endpoint needed nothing**: no name crosses
  `xmip_remote_open_local_v1` or `xmip_remote_act_v1`, and the node reads
  the account from the connection.

Still a limit: the handle binds a screen's act to a caller the runtime
proved, inside the host's own process; a hostile host in that process can
still act through the node as its own account. The node deciding for a
relayed caller is the next step (the amendment below).

Proved in the runtime (`plane::caller`, `plane::role`, the section 18 and
21 exports, `secure_listener`), `xmip-core-authenticate` (`handshake`,
`peer_credentials`) and `Xmip.Surface.Test` (`BrowserCallerTest`: a
certificate the runtime did not answer for proves no one).

Provenance: the draft and every name are the assistant's, for the owner to
overrule.

## Amendment, 2026-11-01: the node decides for a caller a web host relays

The amendment above left a limit: a handle binds a screen's act to a caller
the host's runtime proved, but inside the host's own process, and an act
reached the node as the host's own account. The owner, the same day: *an
in-process handle cannot stop a hostile host in the same process, so the
node must decide.* Built (decided by the assistant, each in one line):

- **A relay vouches, the node verifies.** An identity `[operate] relay`
  names — an account on the local endpoint, a certificate's subject on the
  network listener — hands the node the leaf certificate its browser
  presented (`Vouch`, `plane::call::VOUCH`). The node verifies it against
  its own `[operate] anchors` for client authentication
  (`authenticate::x509::verify`, `Chain::from_der`), runs it through its
  own authentication gate (`plane::caller::certificate`) and holds the
  caller (`plane::vouched`), answering a handle of its own, a random
  64-bit number as every caller handle is (`plane::handle`).
- **Every call for that caller names the node's handle** in a header,
  `xmip-caller`, so the node decides whose call it is before it reads the
  call. The node acts for the caller only where the connection's identity
  is a relay and the handle was issued to that very identity, before its
  certificate's `notAfter` and not yet let go (`Unvouch`); a handle
  presented through any other identity is no one. The act is admitted by
  the caller's own role, never the relay's: **relaying grants no act of its
  own**, and a relay's own calls are judged by its own role as any
  caller's. No relay configured, no one is relayed, refused in words.
- **The audit says both**: `who` is the caller, and `through` the relay it
  came through.
- **The host's registry is a cache of what the nodes said**: every holder
  of one caller shares one proof (`plane::held::Proof`), which keeps each
  node's handle, vouched for lazily on the first act to that node, since
  one web host operates several nodes and clusters. When the last holder
  lets the caller go — the session, the circuit, the listener stopping —
  each node is told (`Unvouch`), on the surface's own bounded line
  (`Shared::called`). A node that no longer knows the handle — it started
  again — answers that it holds no caller by it, and the caller is vouched
  for once more.
- **The caller crosses the C boundary as the handle**: `xmip_remote_act_v1`,
  `xmip_secret_v1` and `xmip_secrets_v1` take `uint64_t caller`, 0 for this
  side itself; a caller the operating system proved for this process — a
  desktop's — is this side's own connection. In .NET, `RemoteNode.Act`,
  `SetSecret` and `Secrets` take the `HeldCaller`, and so does every act of
  `IOperatorSurface` — a parameter, never ambient state, which an await
  resuming on another thread would lose or hand to another request (the
  owner, the same day): `GatedOperator` hands an admitted act on for its
  own caller, whatever caller the act names, and the command line and the
  PowerShell module pass none, acting as themselves. Proved by two callers
  acting at once, through one surface in the runtime and through the gate in
  .NET, each reaching the node as their own.
- **The Playground** names the account its run runs as as each node's one
  relay, so the tester's web host relays the tester's browser.

**The limit, written for the owner**: the node does not take part in the
browser's handshake, so a compromised web host can act for anyone whose
certificate it has held while that certificate is valid — within that
caller's own role, and visibly in the node's audit, `through` the host. It
cannot make up an identity: the certificate must reach the node's own
anchors. Binding the handshake's freshness to the node closes even that,
and is the next step; ending the browser's mutual TLS in the node itself
is the owner's choice, not built. Not built either: a chain with
intermediates (the leaf alone is handed over, as an operator certificate
the cluster's authority signs needs), and a node's handles outliving a
host that died without letting them go, until each certificate ends or the
node starts again.

Proved in the runtime (`plane::vouched`, `plane::held`, `plane::call`,
`tests/plane/relayed.rs`: an act relayed is the browser's by its own role
and audited through the host, refused as the browser where its role is
Observer, no one once let go; an identity that is no relay, a certificate
under other anchors and a node relaying for no one act for no one; two
callers acting at once through one surface each reach the node as their
own),
`xmip-core-configure` (`[operate] relay` takes `anchors`),
`xmip-core-authenticate` (`Chain::from_der`), `Xmip.Surface.Test`
(`GatedCallerTest`: two callers acting at once through the gate, hopping
threads, each reach the surface behind it as their own) and the Playground
(`served::given`: a tester's operator certificate, signed by the
Playground's one authority as `New-XmipCertificate -Request` has it
signed, is verified and relayed by every node a run starts, whose
`tls/anchors.pem` is that authority).

Provenance: the owner's decision of 2026-11-01, as the coordinator relayed
it; the names `Vouch`, `Unvouch`, `relay`, `plane::vouched` and `through`
the assistant's, agreed the same day.
