# Xmip terminology

Xmip uses one term for one concept, in code, configuration, documentation and
diagnostics.

This is the only vocabulary. `doc/glossary.md` was empty and is deleted.
`doc/architecture/glossary.md` was 363 lines written under the Interchange
vocabulary that ADR-0013 replaced; everything in it that survives is below, and
the file is deleted. If a term is not here, it is not defined.

## Process terminology

The bare word **Process** is ambiguous in Xmip and should not be used alone
unless the surrounding context makes the meaning unavoidable.

| Term | Meaning |
| --- | --- |
| **System Process** | An operating system process managed by Windows, Linux, macOS, or another host operating system. |
| **Xmip Service** | The master long-running service on a node. One per node, started by the operating system. It reads the configuration, builds and validates the execution tree, then registers, starts and supervises the Xmip Host Services. It is never in the message path: no Stream, Message or Journey passes through it. Its executable is `xmip-service`: a Windows service, a systemd unit or a launchd daemon, which any of those stops by draining the node (ADR-0018, amendment 2026-09-28). Until Host Services run in processes of their own, it runs the in-process Host Service itself. |
| **Xmip Host Service** | A long-running service registered and started by the Xmip Service to host one or more Modules and, when required, execute Extensions. Many per node. It does the work — Receive Locations, Xmip Processes, Send Locations — and holds the claim on what it is working on. Its service name and description are generated from configuration when it is registered, so an operator reading the service list can tell what each one does. |
| **Xmip Playground** | The tool that exercises Xmip. It spawns Development nodes as System Processes on one machine — no virtualization — and drives every transport and every content contract through them continuously: Receive Locations fed, Send Locations watched, a verdict per pair published as health. It is where a transport or contract is proven, and the source of real measurement. Named by the owner, 2026-09-05; ADR-0028. |
| **Host Process** | The System Process an Xmip Host Service runs as. The service is the registered, managed thing; the process is what the operating system schedules. |
| **Xmip Application** | An integration as a developer designs it: its routes, and later its transforms and Xmip Processes, drawn once in VS Code and kept as text in the repository. A node's configuration binds it — which Application runs there, with which addresses and credentials. Named by the owner, 2026-09-26, BizTalk's word; ADR-0064. |
| **Binding** | What a node's configuration says about an Xmip Application it runs: that it runs it, and the environment's side of it — addresses, credentials, which node takes which Receive and Send Location. The design is the Application's; the binding is the node's. ADR-0064. |
| **Transform** | What turns one Message's content into another's. Designed in VS Code, compiled at design time into a native module (ADR-0066). |
| **Expression** | One line of Xmip's own expression language, shaped like SQL's WHERE clause: `MessageType = 'Order' and not Amount > 1000`. A Subscription's filter is one; a Transform's conditions and an Xmip Process's decisions will be. Compiled once into a tree and decided in three truths — true, false and *unknown*, where a value that is not there is unknown with its reason, never a silent false. `xmip-core-path`'s `expression`; ADR-0066. |
| **Subscription** | What picks a published Message up and opens a Journey into an Xmip Process, a Send Port or a Send Port Group: a filter and a destination, drawn in an Xmip Application and bound by a node's configuration, and added and removed in that TOML and nowhere else (ADR-0013, ADR-0064). An operator lists them and pauses or resumes one — never removes one — in the Subscriptions view, `xmip-cli subscriptions` and `Get-XmipSubscription`; a paused one holds what it matches in the Ledger, and a resume picks it up oldest first (ADR-0013, amendments 2026-09-30 and 2026-10-01). It is not an **Event subscription**. |
| **Event subscription** | A Party's standing request to be told what Xmip did: a filter over Event types, outcomes, a scope and a Party, held with a bounded queue in the hub of the process that took it, and never persisted (ADR-0065). An operator lists them, and pauses, resumes and removes one, in the Event subscriptions view, `xmip-cli event-subscriptions` and `Get-XmipEventSubscription` (amendments 2026-09-29 and 2026-09-30). It is not a **Subscription**, which picks a published Message up and opens a Journey; where either could be meant, say Event subscription. |
| **Xmip Process** | An integration process defined by Xmip configuration and artifacts. It belongs to Xmip runtime semantics, not to the operating system. |
| **Xmip Subprocess** | A configured child part of an Xmip Process. It is not an operating system child process unless explicitly stated as a System Process. |

Every System Process and every service Xmip owns is named `xmip-<what>` —
`xmip-cli`, `xmip-gui-web`, `xmip-playground-<cluster>-node-<node>` — and declares its name,
its location and its purpose, test or runtime, so that one line finds them
all and one line stops them all (ADR-0053). Where there are many of a kind,
`<what>` says which: a Playground process carries its suite, its cluster and
what it is, so a list of twenty reads as a tree (amendment 2026-09-20).

When a person writes or says **Process** without qualification and the meaning
is not clear, the correct response is to ask whether they mean **System
Process** or **Xmip Process**.

## Roll and Role

Two words, one letter apart, both chosen. The owner read one for the other on
2026-09-20, which is the evidence that this section was owed: **role** is a
type in the code and **roll** had never been written down here at all.

| Term | Meaning |
| --- | --- |
| **Roll** | One continuous run of a test suite. The Playground rolls: it drives its tests round after round and does not stop until it is told to or its duration runs out. `Start-XmipTest` starts a roll, `Stop-XmipTest` ends one, and `xmip-playground-roll` is the System Process it runs as. A roll runs exactly one cluster (ADR-0028), and the cluster is a process the roll spawns, not the roll itself (ADR-0052, amendment 2026-09-19). |
| **Hidden run** | A roll that declared itself hidden when it was started, `Start-XmipTest -Hidden`: an assistant's test run beside the owner's. Every surface leaves it out — its cluster, its run and its audit records — until asked to show it: the views' *show test clusters* box, `-IncludeHidden`, `--include-hidden`. Hidden by what it declared and never by its name, so a cluster that declared nothing is shown whatever it is called (ADR-0028 and ADR-0052, amendments 2026-09-30). Shown with it, it is marked *test*. |
| **Role** | What something is permitted or expected to be. A Node has `NodeRole`, eight of them: Receiving, Processing and Sending serve one stage of the message path each; Executing is their sum, all three in one process, the low-latency role; Operational changes runtime state, Monitoring reads it, Development is the Playground's; Storage is Xmip Storage, the doorway every other node calls for all storage (ADR-0056, amendments 2026-10-01). A node declares its roles and never has one read from its name. An operator has a role at a surface: Observer, Operator, Developer (ADR-0009). Neither has anything to do with a roll. Executor, Reader and Writer were `deployment-model.md`'s names for node roles until 2026-10-01 and are not words any more. |

A node's **capability** is what it declares in ADR-0056's terms — its roles,
which say the stages of the message path it serves, and whether it is online
— published at `<node>/capability` and never read from its name. A **stage**
(receive, process, send) is where a Message is on its path and a segment of a
scope; a node does not declare a stage, its roles serve them.

## Target, Domain and Site

Three words for what a deployment's program is built with, each a TOML file
under `deploy/` (ADR-0015, amendment 2026-10-01). A node's roles are the
third axis, and are the Role row above.

| Term | Meaning |
| --- | --- |
| **Target** | What a node's program runs on: `device` (a microcontroller, no_std), `edge` (a Raspberry Pi, industrial PC or gateway), `computer` (a person's own machine), `server` (an on-premises service) or `hosted` (a virtual machine or container at a hosting provider). A target says whether a build can be an embedded Storage node — RocksDB and SQLite, never one for the other (ADR-0015, amendment 2026-10-01) — which key store it carries, and what it refuses, each with its reason; a role or domain needing what it refuses is refused. A cluster and a hybrid are arrangements of nodes on targets, not targets. `deploy/profile/target`. |
| **Domain** | What a node integrates, named by what its technologies serve: `healthcare`, `industrial`, `b2b`, `managed-service` (what a hosting provider sells), `integration` (the mechanisms every integration uses) and the rest. A domain lists standards, the leaves of technologies' positions in `architecture.toml`, and its members are every built technology with one of those leaves, across capabilities. Not a repository's architectural domain, such as Foundation or Platform (ADR-0058). `deploy/profile/domain`. |
| **Site** | One deployment's choice of a target, its node roles and its domains, `deploy/site/<name>.toml`, and so what its `xmip-service` is built with: `Build-XmipService -Site <name>`. The build sets what is possible; the node's TOML picks from it at run time. |

## PowerShell

Two names one letter apart, for two different products:

| Term | Meaning |
| --- | --- |
| **Windows PowerShell** | A proper noun: version 5.1, on .NET Framework, shipped with Windows and not updated. Xmip does not run on it. |
| **PowerShell** | Version 7 and later, Core edition, cross-platform, installed and updated separately. What Xmip requires. |
| **PowerShell on Windows** | PowerShell 7 running on a Windows machine. A deployment, not a product. |

"Windows PowerShell users" and "PowerShell users on Windows" are different
populations, and the second is much larger and updates much faster. Say which
you mean. `#requires -PSEdition Core` is the line between them, and it is
enforced rather than advised — ADR-0021.

## Definition and Instance

| Term | Meaning |
| --- | --- |
| **Definition** | A named Xmip configuration object declared in TOML. It declares what may exist and how it is configured. A Definition describes what a node may handle; it does not process a message by itself. |
| **Instance** | The runtime execution of a Definition, created when the runtime uses that Definition to handle a specific Message, Stream, action or execution scope. An Instance is auditable, and traceable and trackable according to policy. |

Definition means configured in TOML. Instance means running, or previously run.
The pairing is mechanical and the names are formed the same way every time:

```text
ReceivePortDefinition        -> ReceivePortInstance
ReceiveLocationDefinition    -> ReceiveLocationInstance
SubscriptionDefinition       -> SubscriptionInstance
ProcessDefinition            -> ProcessInstance
SendPortDefinition           -> SendPortInstance
SendLocationDefinition       -> SendLocationInstance
ContractDefinition           -> (evaluated, not instantiated)
```

A Definition may declare a name, kind-specific configuration, a Handler
reference and Handler configuration where applicable, runtime-affecting
configuration values, contracts or contract references, security requirements,
and tracing and tracking settings.

Runtime persistence records Instance state, outcome, failure, retry and
recovery information. Configuration declares what may exist; persistence
records what did happen.

## Module, Handler and Extension

A **Module** is compiled code loaded during Xmip Host Service startup according
to configuration, ABI-verified per ADR-0012. A Module may declare Handlers and
Extensions.

A **Handler** is a technology-specific trait implemented by a Module, called by
the runtime through a stable boundary. HTTP, FTP, SFTP, Kafka, File, CANBUS,
FHIR and HL7 are Handlers.

An **Extension** is a utility capability declared by a Module and executed when
an artifact references it. Extensions are verified during startup but not
loaded, unless Xmip later defines a preloading policy. .NET, Java, Python, Go,
Rust, C/C++, PowerShell, Bash and company-specific utilities are Extensions.

The distinction is purpose, not mechanism:

| | Handler | Extension |
| --- | --- | --- |
| Purpose | technology | utility |
| Binds Xmip to | communication, protocol, format, transport | reusable executable capability |
| Loaded | at startup | on reference |

`handler` is **not** a repository-name segment — ADR-0011 retired it there, and
`xmip-core-transport-ftp` is the repository that ships the FTP Handler. Handler
remains correct as the name of the runtime role. The two rules are not in
conflict and are frequently misread as if they were.

A Module may provide Transport Handler, Content Handler, Logic Handler, Store
Provider or Management Module capabilities.

## Identity, Party and direction

A **Party** is an actor Xmip recognizes, per ADR-0007 and ADR-0008. It holds
the identities it is recognized by and the identities Xmip presents when
reaching it. One registry, both directions. The Topology draws a Party on
each side it is on: left of the nodes whose receive stages it sends into,
right of the nodes whose send stages deliver to it (ADR-0052, amendment
2026-09-29).

Another system or organization that sends to or receives from Xmip is a
**Party**, plural **Parties**, and the estate has no other word for it. The
owner, 2026-09-29: *Partner is the wrong word. It is Party, plural Parties.*

| Term | Meaning |
| --- | --- |
| **Transport identity** | Who opened the connection. Read before Message creation. Mandatory. |
| **Message identity** | On whose behalf the content was produced. Requires the Message to exist. Optional, and absent for most representations. |
| **Implied identity** | An identity nothing presented, evidenced by circumstance — path, permissions, source address. Still authenticated, against that evidence. |
| **Alignment** | Whether the two identities must resolve to the same Party. `none`, `relaxed` or `strict`, per Receive Location. |

A **Receive Location** declares a closed set of mechanisms and Parties it
accepts; anything else is refused at authentication rather than attempted. A
**Send Location** presents a configured identity, inherited up through Send
Port and Send Port Group to the Sending Process where it is not set.

On receive Xmip is the server and the counterparty is the producer. On send
Xmip is the client and the counterparty is the consumer. The two never infer
from each other: ADR-0006 for send, ADR-0019 for receive and for everything
both share.

Authentication always precedes authorization. **Anonymous is an authenticated
outcome, not a skipped gate** — the claim is "nobody", it is verified as such,
and authorization then decides whether nobody may post here.

## Arrival and Departure

**Arrivals are handled by Receive Locations. Departures are handled by Send
Locations.** The words are chosen to read as one board: an operator watching an
estate is watching things come in and things go out, and the two halves are
deliberately symmetric so that neither needs its own vocabulary.

A Stream **arrives** three ways:

| | |
| --- | --- |
| **Pushed** | something connects and sends it. HTTP, SOAP, gRPC, AS2, MLLP. |
| **Detected** | Xmip is watching and it appears. A folder, a queue, a table, an inbox. |
| **Scheduled** | a timer fires and Xmip goes and fetches it. Xmip is the client. |

A Message **departs** three ways, and they are not the same three:

| | |
| --- | --- |
| **Pushed** | Xmip connects and sends it. |
| **Collected** | Xmip holds it and something comes and gets it. |
| **Scheduled** | a timer fires and Xmip sends what has accumulated. |

**A Stream can arrive by being detected; a Message cannot depart by being
detected**, because nothing outside Xmip is watching on Xmip's behalf. What
replaces it is collection — and the difference matters operationally, not just
grammatically. A pushed departure fails at Xmip and is Xmip's to retry; a
collected one waits, and its failure mode is nobody turning up. Reported as one
number, an unreachable Party and an idle one look identical.

Between the two sits the **Ledger**, which holds every Stream, Message and
Journey until *every* departure is settled. A Journey with two destinations
reached and one awaiting collection is unfinished, and the Ledger is the only
place that state can live without lying about it in one direction or the
other.

How a Stream arrived is separate from how its identity was established — see
*Identity, Party and direction* above, and ADR-0019 clause 8.

## Message and Section

A **Message** is a processing unit over immutable content. It has a message id, metadata,
and one or more Sections.

A **Section** is a stream contained within a Message, with a section id,
metadata and a stream reference. Sections may reuse stream references when the
content is unchanged.

A new Message is created when Xmip performs an operation that produces a new
message state, such as assignment or transformation. **Routing alone does not
create a new Message.**

## Audit and Failure Persistence

**Audit** is the persistent accountability record of Xmip actions and outcomes.
Failures are always audited. These lifecycle events are always audited and are
not optional:

- entry into Xmip
- leaving Xmip
- assigned
- transformed
- passed on
- picked up
- sent
- failure

Audit policy may add successful actions beyond these. It may not remove them.

**Failure Persistence** is mandatory and is part of auditability. When a failure
occurs, Xmip persists the Message in its failure-time state: message id,
message metadata, section metadata, stream references or stored streams as
policy requires, Instance context, failure reason, failure classification, time
of failure, and the runtime place where the failure occurred.

It exists so Xmip can inspect, report, recover, retry, move to the Dead Message
Queue, or explain what failed and why.

## Ledger

The durable work store of a cluster: Xmip Storage's **runtime database**.
Named on 2026-10-01 (the owner: *ToDo is a bad name, propose a better one*;
the assistant proposed Ledger; the owner: *Ledger is good*).

Every Stream, in chunks, every Message and every Journey lives in it until
completion or retention, and is archived before either, with claims, the
state of each Xmip Process, retry, failure and replay state, the Messages a
paused Subscription holds, and audit records as first written. Selecting
work is a query over state; completing work is a state transition. That
makes it a queue in every sense that matters — durable, survives restart,
ordered where ordering is configured — while being no kind of message
broker. A write counts only once the database has it durably.

**It belongs to the cluster, not to a node.** Every node reaches it through
Xmip Storage, and works on it by a time-limited claim, so when a node dies
another picks its work up. Behind Xmip Storage it is a database on a server
IT runs, or RocksDB on an embedded Storage node.

**The comparison is BizTalk's MessageBox, and so is the warning.** BizTalk's
was one shared SQL database holding every message and subscription for the
whole group, which made it the contention point the entire product was
eventually tuned around. Behind a database server the Ledger is a shared
database too, and its write rate is the cluster's limit; what differs is
that no node writes it directly, only Xmip Storage's operations do.

It is not a broker, and Xmip requires none. `xmip-core-transport-rabbitmq`,
`-msmq`, `-kafka` and `-ibm-mq` are integration targets — things Xmip talks to
on somebody's behalf — not infrastructure it runs on.

The databases, the roles and the split with IT's infrastructure are in
`architecture/deployment-model.md` sections 3, 7 and 9; the execution model it
implements is `architecture/runtime-model.md` section 3.

## Xmip Storage

The doorway to all storage: the nodes declaring the **Storage** role, whose
operations — write a Stream chunk, write a Message, claim a Journey, hand it
on, write an audit record — every other node calls,
never a database directly, round robin over the Storage nodes. More than one
Storage node is the safety. It always keeps two databases, whatever the
backend: the **runtime database**, which is the Ledger, and the
**administration database** — administration, deployment state, cluster
membership, operator state, and audit kept over time, moved there by the
audit keeper; and the Subscriptions each Host Service writes from its TOML
as it starts, shared across the cluster. The rest of a node's configuration
it reads from its TOML as it starts and holds as its execution tree in
memory (ADR-0031, amendments 2026-10-01 and 2026-10-02). Behind it is a database server IT
runs (option A, PostgreSQL first), the two databases separate on IT's servers, or, for a
single machine or an edge site, an **embedded Storage node** keeping RocksDB
and SQLite itself, with no failover (the owner, 2026-10-01). Xmip encrypts up
to the Storage node, over its own TLS; behind a database server, encryption
at rest is IT's; an embedded Storage node, test nodes included, encrypts its
own files itself (ADR-0063, amendment 2026-10-01).

## Dead Message Queue

**Dead Message Queue.** Where an accepted Message goes when **no Subscription
matched it**. It is state in the Ledger, not a store of its own: the
Publication that matched nothing, kept with each Subscription's reason for
declining (`architecture/runtime-model.md` section 9). An Operator lists it per
cluster and node, opens one entry and replays it once a Subscription is added
or fixed — in the Dead Message Queue view, `xmip-cli dead-messages` and
`Get-XmipDeadMessage`; an Observer sees the list and no act (ADR-0052,
amendment 2026-10-01).

The expansion was written down for the first time on 2026-08-26. Every document
in the repository used the abbreviation and none defined it, including this one,
which had been using it in the definition above.

**It is not a dead letter queue, and the resemblance is the problem.** Everyone
arriving from BizTalk, MSMQ, RabbitMQ or Kafka reads three letters ending in Q
and expects the place where failures land. In Xmip it is not:

| | Goes to the Dead Message Queue |
| --- | --- |
| Accepted Message, no Subscription matched | **yes** |
| Journey failed | no — the Journey is `Failed` and its Message stays with it |
| Stream rejected at the receive boundary | no — no Message was created to queue |
| Journey dismissed by an operator | no — `Dismissed`, per ADR-0013 |

So the Dead Message Queue answers one question: *this arrived, Xmip took ownership, and nothing
wanted it.* That is a routing problem, usually a missing or mistyped
Subscription, and it is fixed by adding the Subscription and replaying — not by
the failure-triage path that a dead letter queue implies.

The Message is preserved with its receive context, validation results,
correlation and trace references, audit references, failure reason, timestamps,
artifact identities and subscription evaluation metadata. That last one is why
the queue is useful: the operator's question is which Subscription nearly
matched, not what was in the body.

**It is the only queue of its kind.** There is no Dismissed Journey Queue and no
Failed Journey Queue, because a Journey in a terminal state is not homeless — it
is persisted, it holds its execution position, and it is found by query rather
than by being filed somewhere. ADR-0013 records why.

The practical difference is what replay does:

- **From the Dead Message Queue** — *re-publish*. Add the missing Subscription and match again
  against the Message **with the context it already accumulated**. This is not
  a re-receive: envelope context, promoted properties and validation results
  are preserved and reused, and what changed is the Subscription set.
- **From a terminal Journey** — *resume*, from the last checkpoint before it
  stopped, restoring the Journey position **together with the Message
  generation current at that position**.

Both halves matter in both cases. A Journey accumulates execution history,
lineage, the Subscription Instance chain and checkpoints; a Message accumulates
receive context, promoted properties, validation results and its generation
lineage. Neither story replays without the other — and because Transformation
and Assignment create new Messages, a Journey position is meaningless without
knowing which generation it referred to.

The tension with retention — "an accepted Message shall never disappear" against
policy-driven expiry — is an open question in ADR-0013 and is not settled here.

## Startup

**Startup** is the Xmip Service building a validated execution tree from
configuration and starting the Xmip Host Services that do the work; the tree
identifies the Modules to load, the Xmip Processes to start, the Xmip
Subprocesses and their required Modules, and the Extensions to verify but not
load. The nine phases are `architecture/runtime-model.md` section 21,
*Startup*, from ADR-0018.

## Retired terms

| Retired | Use instead |
| --- | --- |
| **Adapter** | Handler. |
| **Plugin** | Module, Handler or Extension, depending on the exact meaning. |
| **Artifact** | The explicit Definition or Instance name. |
| **Enabler** | The explicit Definition or Instance name. |
| **Tracking** | Split, not renamed. The accountability record is **Audit** (`xmip-core-audit`); storing the actual Message for inspection and replay is **retention** (`xmip-core-retain`). `crates/xmip-tracking` was an early `xmip-core-audit` under BizTalk vocabulary, and ADR-0014 names four observation capabilities where a fifth would contradict it. See `architecture/observability-model.md`. |
| **Kernel** | `xmip-core-runtime`, or "the runtime". Six documents used Kernel for the stable runtime core. There is no Kernel repository and there will not be one — ADR-0018 folded service and host into `xmip-core-runtime` — and the word collides with the operating system kernel in a product that discusses System Processes constantly. |

## Open

One term is deliberately not resolved above.

**The Interchange family.** Half decided, and the deciding record was found
after this note was first written.

`architecture/glossary.md` described a *tree*: a root interchange per incoming
Message, a **child interchange with a new id** per transformation or
assignment, and the persisted history of everything sprung from the original.

**ADR-0008 contradicts that and wins**, being Accepted: Assignment and
Transformation create "a new message form with a new messageId and the **same**
interchangeId". So the identifier is **stable** across every generation
descended from one reception. It is a correlation identifier, not a chain, and
generation is tracked by message id.

It is also not Journey renamed. ADR-0013 clause 5 is explicit that a Journey is
one line of execution, **not** a tree, with one Journey per matched
Subscription — so one reception with three matched Subscriptions has three
Journey ids and, per ADR-0008, one interchange identifier across all of them.

So Interchange named a third axis that neither ADR-0013 nor this document
covers — the generation lineage of Messages, where routing creates no new
generation but assignment and transformation do:

```text
Publication              one event, one identity, immutable
  └── Journey            one per matched Subscription   (ADR-0013)
        └── Message      generation 1 -> 2 -> 3         (unnamed)
```

Interchange History also carried retention semantics nothing else does: the
history is persisted until every Message sprung from the incoming Message has
left Xmip or reached a terminal outcome, at a detail level set in TOML —
metadata only, stream references, selected Sections, full message states or
full payloads — and must be recoverable and viewable under retention and
security policy while it is active. That is a real requirement with no current
home.

What remains open is only the **name**, since "Interchange" is retired. A stable
identifier spanning one reception and all its descendants is exactly what
ADR-0013 calls a **Publication** — "one event, one identity, immutable". They
may well be the same identifier under two names, which would remove the concept
rather than rename it.

Recommendation: test whether `interchangeId` and the Publication identity are
the same thing. If they are, say so and delete one. If they are not, name the
remaining axis **Generation** and say what a Publication cannot express. Either
way the retention semantics belong to `xmip-core-retain`, which ADR-0013
clause 2 already made the owner of retained Streams. Not decided.
