# Xmip terminology

Xmip uses one term for one concept, in code, configuration, documentation and
diagnostics.

This is the only vocabulary. `docs/glossary.md` was empty and is deleted.
`docs/architecture/glossary.md` was 363 lines written under the Interchange
vocabulary that ADR-0013 replaced; everything in it that survives is below, and
the file is deleted. If a term is not here, it is not defined.

## Process terminology

The bare word **Process** is ambiguous in Xmip and should not be used alone
unless the surrounding context makes the meaning unavoidable.

| Term | Meaning |
| --- | --- |
| **System Process** | An operating system process managed by Windows, Linux, macOS, or another host operating system. |
| **Xmip Service** | The master long-running service on a node. One per node, started by the operating system. It reads the configuration, builds and validates the execution tree, then registers, starts and supervises the Xmip Host Services. It is never in the message path: no Stream, Message or Journey passes through it. |
| **Xmip Host Service** | A long-running service registered and started by the Xmip Service to host one or more Modules and, when required, execute Extensions. Many per node. It does the work — Receive Locations, Xmip Processes, Send Locations — and holds exclusiveness over what it is working on. Its service name and description are generated from configuration when it is registered, so an operator reading the service list can tell what each one does. |
| **Host Process** | The System Process an Xmip Host Service runs as. The service is the registered, managed thing; the process is what the operating system schedules. |
| **Xmip Process** | An integration process defined by Xmip configuration and artifacts. It belongs to Xmip runtime semantics, not to the operating system. |
| **Xmip Subprocess** | A configured child part of an Xmip Process. It is not an operating system child process unless explicitly stated as a System Process. |

When a person writes or says **Process** without qualification and the meaning
is not clear, the correct response is to ask whether they mean **System
Process** or **Xmip Process**.

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

A **Party** is an actor Xmip recognises, per ADR-0007 and ADR-0008. It holds
the identities it is recognised by and the identities Xmip presents when
reaching it. One registry, both directions.

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
number, an unreachable partner and an idle one look identical.

Between the two sits the **ToDo**, which holds every Stream, Message and Journey
until *every* departure is settled. A Journey with two destinations reached and
one awaiting collection is unfinished, and the ToDo is the only place that state
can live without lying about it in one direction or the other.

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

It exists so Xmip can inspect, report, recover, retry, move to the Xmip DMQ, or
explain what failed and why.

## ToDo

The durable work store on a node. **One per node**, embedded, and written only
by the node that owns it.

Every Stream, Message and Journey lives in it until completion or retention, and
is archived before either. Selecting work is a query over state; completing work
is a state transition. That makes it a queue in every sense that matters —
durable, survives restart, ordered where ordering is configured — while being no
kind of message broker.

**The comparison is BizTalk's MessageBox, and so is the warning.** BizTalk's was
one shared SQL database holding every message and subscription for the whole
group, which made it the contention point the entire product was eventually
tuned around. A ToDo is per node, so there is no shared write path to
contend for and nothing to partition later.

It is not a broker, and Xmip requires none. `xmip-core-transport-rabbitmq`,
`-msmq`, `-kafka` and `-ibm-mq` are integration targets — things Xmip talks to
on somebody's behalf — not infrastructure it runs on.

Engine and layout are in `architecture/deployment-model.md` section 7; the
execution model it implements is `architecture/runtime-model.md` section 3.

## Xmip DMQ

**Dead Message Queue.** Where an accepted Message goes when **no Subscription
matched it**.

The expansion was written down for the first time on 2026-08-26. Every document
in the repository used the abbreviation and none defined it, including this one,
which had been using it in the definition above.

**It is not a dead letter queue, and the resemblance is the problem.** Everyone
arriving from BizTalk, MSMQ, RabbitMQ or Kafka reads three letters ending in Q
and expects the place where failures land. In Xmip it is not:

| | Goes to the DMQ |
| --- | --- |
| Accepted Message, no Subscription matched | **yes** |
| Journey failed | no — the Journey is `Failed` and its Message stays with it |
| Stream rejected at the receive boundary | no — no Message was created to queue |
| Journey dismissed by an operator | no — `Dismissed`, per ADR-0013 |

So the DMQ answers one question: *this arrived, Xmip took ownership, and nothing
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

- **From the DMQ** — *re-publish*. Add the missing Subscription and match again
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

Xmip Service startup builds a validated execution tree from configuration. The
tree identifies the Modules to load, the Xmip Processes to start, the Xmip
Subprocesses and their required Modules, and the Extensions to verify but not
load. ADR-0018 specifies the nine phases and which of the two services owns
each.

Xmip cannot own every incorrect decision made in configuration or code, but it
mitigates predictable mistakes through validation, diagnostics, warnings and
clear failure boundaries.

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
