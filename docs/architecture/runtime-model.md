# Xmip runtime model

What Xmip does at runtime: how a Stream becomes a Message, how a Message
becomes Journeys, and what an operator can do to them afterwards.

This is the architecture specification. It replaces
`Xmip-Architecture-Specification-v1.0.md`, `-v1.1.md`, `-v1.2.md` and
`Xmip-Architecture-Baseline-Current.md`, which were four documents wearing
version numbers that suggested a lineage they did not have. Sections 9 to 15 of
v1.2 were about the estate rather than the runtime and are now in
`repository-model.md`. Their history is in git.

Where those documents conflicted with each other or with an accepted ADR, the
conflict is resolved in section 21 rather than silently. Four were substantive.

## 1. Purpose

Xmip reliably receives, moves, understands, validates, processes, delivers,
observes and recovers information over time.

Xmip is:

- Stream-centric at its foundation.
- Stream- and Message-centric in processing.
- Journey-centric in execution and operations.
- Immutable by design.

## 2. Stream, Message, Section, Journey

**Stream** — immutable data received by, or produced within, Xmip.

**Message** — an immutable processing unit with a message id, metadata and one
or more Sections. An XML, JSON, CSV, EDI, HL7 or FHIR instance, or text or
binary payload, may be *represented* by a Message. **A representation is not a
Contract.**

**Section** — a stream within a Message, with a section id, metadata and a
stream reference. Sections reuse stream references when content is unchanged.

**Journey** — one line of execution carrying a Message through Xmip, with its
history, audit events and lineage.

A new Message is created when Xmip performs an operation producing a new
message state — Assignment or Transformation. **Routing alone creates no new
Message.**

## 3. Immutability

Streams and Messages are never modified. Assignment and Transformation create
new immutable artifacts when information changes.

A Journey appends execution history, audit events and lineage. Its historical
record is never rewritten.

## 4. Actors and Communication Domains

Xmip is not fundamentally an integration engine. Its responsibility is to move
authenticated, authorized, immutable information between communicating actors,
and the same communication pattern recurs at every scale.

An **Actor** is any entity that can communicate. A **Domain** is an Actor that
contains other Actors. The recursion is the point:

```text
Fleet owner
  └── Ship owner
        └── Ship
              ├── Captain
              │     └── Crew
              └── Ship control
                    ├── Navigation system
                    ├── Engine system
                    └── NMEA 2000 network
                          └── Devices
                                └── Sensors
```

Every Domain follows the same rules. A parent informs, delegates and commands
its children; children report, acknowledge and escalate to their parent; peers
communicate when authorized; external communication is policy controlled.

**The runtime does not distinguish between these entity types.** It understands
Actors, Domains, Identities, Policies and Messages, and nothing else. That is
what lets one architecture serve a fleet operator and a sensor on a bus.

### Xmip artifacts are Actors

Actor semantics do not replace or rename anything. Receive Ports, Receive
Locations, Xmip Processes, Send Ports, Send Locations, Handlers, Nodes and
Clusters remain explicit, named, versioned, configurable and deployable
artifacts. They *gain* actor semantics when they communicate, publish,
subscribe, own work, report status or transfer responsibility.

| Artifact | As an Actor |
| --- | --- |
| Receive Location | receives external input and reports to its parent Receive Port |
| Receive Port | owns the Message after receive, until another Actor takes ownership or a derived Message is created |
| Xmip Process | may take ownership, orchestrate, assign, transform, publish, subscribe or route |
| Send Port | owns send-side preparation and delivery decisions |
| Send Location | performs delivery and reports the result to its Send Port |
| Handler | an Actor when it participates in execution, capability reporting or delivery |
| Node | an Actor inside a Cluster |
| Cluster | an Actor inside a larger Xmip or organizational domain |

A Receive Location is a crew member reporting to a Captain. The Receive Port is
the Captain of the Message after receive.

> Actor semantics explain how artifacts communicate and transfer
> responsibility. They must never erase artifact semantics.

### Message ownership

**A Message has one owning Actor at every stage of its lifecycle**, and
ownership transfers. Assignment and Transformation do not mutate: they create a
new message form with a new message id, which may have a new owning Actor. The
previous form stays immutable and auditable.

Ownership is what makes "who is responsible for this right now" answerable at
any instant, which is the operational question underneath *Show me the
Journey*.

### Capabilities are not roles

Two dimensions that read alike and are not:

| | Describes | Examples |
| --- | --- | --- |
| **Security role** | what a user or security principal may do in Xmip | Developer, Operator, Executer |
| **Actor capability** | what an Actor can do in communication and runtime execution | Publish, Subscribe, OwnMessage, Report, Command, Execute, Route, Transform, Send, Receive |

A Receive Port has the capability `OwnMessage`. A person has the role
`Operator`. **Do not call an actor capability a role**, and do not mix user
authorization with runtime communication modelling — ADR-0009 exists because
the two collapse into each other the moment anyone stops paying attention.

This is also why a Party is not a role: a Party is recognised, a role is
granted, and a capability is what an Actor can do. Three dimensions.

### The test for Xmip Core

> If a feature does not improve communication between Actors or Domains, it
> probably does not belong in Xmip Core.

## 5. The receive chain

```text
External Stream
    -> Receive Location      physical ingress: transport, security, acceptance
    -> Receive Port          logical ingress: creates the Message
    -> Publication           the Message is made available
    -> Routing               evaluated against Subscriptions
    -> Journey               one per matched Subscription
```

> Receive Locations receive Streams. Receive Ports create Messages. Publication
> offers them. Routing decides where they continue. Journeys carry them.

**Failures before Publication are audited receive failures, not Dead Journeys.**
There is no Journey yet to be Dead. This is the single most important boundary
in the model and the one earlier drafts got wrong.

The gate sequence inside acceptance is specified in ADR-0013 and is not
optional or reorderable:

```text
Incoming Stream
    -> transport identification
    -> transport authentication
    -> transport authorization
    -> Message creation
    -> default promotion
    -> configuration may inspect Stream and Message Context
    -> optional message identification
    -> optional message authentication
    -> optional message authorization
    -> Contract implication
    -> optional deserialization
    -> Validation
    -> Publication
```

Transport security is mandatory and precedes Message creation, so **Xmip never
parses content from an unauthorized sender**. Message-level security is
separate and optional and follows Message creation, so configuration can
inspect the Stream and Context before deciding whether it applies. Identity,
Parties and the two layers are ADR-0019's; what Xmip *retains* at each refusal
is ADR-0013's.

## 6. Receive Port and Receive Locations

A **Receive Port** is the logical common ingress for information of one
purpose — Invoices, Purchase Orders, Customers, Laboratory Results. It owns
common actions, Message creation and Publication.

A **Receive Location** defines how a Stream reaches its parent Receive Port. It
owns the transport binding and endpoint, the accepted identities and
mechanisms, the interaction type, the response behaviour, and any
location-specific Content and Contract configuration.

```text
HTTP Receive Location ─┐
FILE Receive Location ─┼─> Invoices Receive Port ─> Publication ─> Routing
FTP  Receive Location ─┘
```

The Receive Port executes with the context of the originating Receive Location.

## 7. Interaction and processing depth

These are two independent characteristics and are constantly conflated.

**Interaction** — what the caller expects back:

| | |
| --- | --- |
| **Composite** | the caller expects a response composed through configured Xmip work. The Receive Location may wait for a Process-produced response. SOAP, Web API, gRPC. |
| **Data Transfer** | the caller transfers information and is acknowledged once acceptance succeeds. The Journey then continues asynchronously. |
| **Batch Load** | a batch or large workload is accepted and acknowledged for later processing. Configuration decides whether it becomes one Journey or many. |

**Processing depth** — how far Xmip interprets the content:

| | |
| --- | --- |
| **Transfer** | move a trusted, often very large Stream with no deserialization and no payload inspection. |
| **Light** | route on trusted sender, Receive Location, declared type and other metadata. |
| **Context** | interpret through Content, Contract and Path for content-aware Routing. |

The same transport may serve more than one interaction type. Transfer and Light
require no Path evaluation, which is what makes them cheap.

## 8. Preparation Steps

A **Preparation Step** prepares a Stream before or after normal Content
processing. It is Xmip's term for the useful part of what BizTalk Pipelines
did, and it exists because external standards are not always followed.

```text
Decrypt / Encrypt          Decode / Encode
Decompress / Compress      Convert character encoding
Extract / create archives  Normalize line endings
Unwrap / wrap              Digitally sign or verify
Repair explicitly configured partner quirks
Custom Preparation Step
```

**Preparation Steps contain no Process decision logic and perform no
Assignment.** That restriction is what keeps them composable.

## 9. Publication and Routing

Publication is part of Routing, not a separate platform concern.
`xmip-core-route` owns Publish, Path, Subscription evaluation and Dispatch.

A **Publication** is not an attempt. It is the act that makes a Message
available for Routing, and **every Publication is audited**.

**Routing** evaluates a Publication against Subscriptions. A Subscription may
target an Xmip Process, a Send Port or a Send Port Group.

```text
Publication              one event, one identity, immutable
  └── Journey            one per matched Subscription
```

A Journey is one line of execution, **not a tree**. A Publication is finished
when all its Journeys are terminal — not when they all succeed. "3 matched,
2 delivered, 1 failed" is expressible without any record having to lie.

Journeys are independent because the world is. If a Process succeeds and an
SFTP Send fails, the file cannot be un-sent. There is no transaction across a
Send Location, so there is none across a Publication.

**Zero matches produces zero Journeys**, and the Message goes to the Xmip DMQ
with its receive context, validation results, correlation and trace references,
audit references, failure reason, timestamps, artifact identities and
subscription evaluation metadata. That metadata is the point: when nothing
matched, the operator's question is "what were the promoted properties, and
which Subscription nearly matched?" — not "what was in the body".

### Path

Xmip has a base path model using numbered and named indexes:

```text
index[n]
index['name']
```

Format-native Path technologies are expected and supported: XPath, JSONPath,
JSON Pointer, FHIRPath, EDI selectors, HL7 selectors, and stakeholder-defined
technologies. A Message retains its applicable Content, Contract and Path
technologies until Assignment or Transformation creates a new Message.

## 10. Send model

**Send Port Group** — a named collection of Send Ports and nothing more. It
owns no delivery behaviour. A Subscription targeting a Group dispatches to
every Send Port in it, and each executes independently.

**Send Port** — the logical outbound artifact. Several Subscriptions may
dispatch to the same Send Port. It may receive a routed Message, Transform it,
select and invoke ordered Send Locations, apply retry and failover policy, and
audit its actions.

**A Send Port cannot perform Assignment.** Receive and Send artifacts hold only
the current Message and cannot make Process decisions or create assigned
Messages. Assignment belongs to an Xmip Process. Transformation may happen in a
Receive Port, an Xmip Process or a Send Port.

**Send Location** — one physical outbound endpoint, owning the concrete
transport, destination, presented identity, serialization, demotion, optional
outgoing Contract validation, delivery and optional response transport.

A Send Port succeeds when one of its Send Locations succeeds. Retries apply to
the active Send Location; failover moves to another per Send Port policy. If
all Send Locations fail, the Journey fails.

The identity a Send Location presents resolves per ADR-0006:

```text
Send Location -> Send Port -> Send Port Group -> Xmip Sending Process
```

First one found wins, and it is resolved independently of any receive-side
identity.

## 11. Responses, in both directions

The symmetry is exact, and it is the clearest statement of what Ports and
Locations are for:

> Locations exchange Streams with the outside world. Ports exchange Messages
> with Xmip.

**Receive side.** A Receive Location may return a response. Data Transfer and
Batch Load acknowledge as soon as the Message is accepted and validated. Xmip
does not wait for the Journey unless a Composite interaction requires a
Process-produced response. The Receive Port produces the logical response
Message; the originating Receive Location transports the response Stream back
to the caller.

**Send side.** A Send Location may receive a response Stream. The Send Port
accepts it and creates the response Message, which continues **the same
Journey**:

```text
Send Location receives the physical response Stream
Send Port accepts it and creates the response Message
Response Message continues the same Journey
```

A response ingress is an ingress. It is identified, authenticated, authorized
and audited before acceptance, exactly as a Receive Location is.

There is a runtime consequence for responding protocols: everything up to
Validation must complete **inside** the receive call. It cannot be deferred to
a worker without losing the ability to answer.

## 12. Journey state

```rust
enum JourneyState { Active, Waiting, Suspended, Recovering, Completed, Failed }
```

`Completed` and `Failed` are terminal. `Suspended` and `Recovering` are the
operator-recoverable path. This is what `journey_model.rs` implements, with
tests, and what ADR-0013 clause 7 records.

Earlier drafts named a different set — Created, Running, Paused, Waiting, Dead,
Completed, Dismissed. The mapping, and what happened to the two that had no
equivalent, is in section 21.

**A Failed Journey** cannot continue automatically. Causes include Transport
Handler, Content Handler, Contract, Process, Send Location, response and
technical failure. Authentication or authorization can cause it **only once the
Journey exists**; failures during pre-Publication acceptance are audited receive
failures.

A Failed Journey retains its Message, Stream, Receive Port, Receive Location,
failure stage, failure reason and the audit and retention references needed to
diagnose it. The state answers *where* the Journey is; the cause answers *why*.

**A failed Journey does not send its Message to the DMQ.** If a Message matched
three Subscriptions and one Journey failed, the Message *was* routed. Only a
Message matching zero Subscriptions is undeliverable.

## 13. Journey control

Commands operating on the same Journey:

```text
Start   Pause   Continue   Retry   Stop   Dismiss
```

**Retry** resumes from the failed audited stage of the same Journey. Xmip may
retry automatically per resilience policy; an authorized operator may retry
after automatic retries are exhausted and the underlying fault is fixed.
Successful prior actions are not repeated unnecessarily.

**Stop** prevents further execution. The resulting state depends on reason and
policy.

**Dismiss** intentionally terminates a Journey without deleting its history,
Messages, Streams, retention or audit.

## 14. Replay

**Replay is not a Journey command and is not Retry.** It creates a *new*
Journey from a selected historical source:

```text
a historical Receive Location event
a historical Receive Port event or Publication
a historical Journey starting point
```

Replay uses the Message, corresponding Stream, artifact context and
configuration identity retained at the audited source. The new Journey records
lineage to that source and to the original Journey where one exists.

- Replay what entered a Receive Location during a period.
- Replay a Message as it entered a Receive Port, before its actions and
  Publication.
- Replay a whole Journey from its original starting point.

**The historical source is unchanged, and the Replay is itself audited.**

Replay and detailed inspection are possible only while the required retained or
archived evidence can be restored.

## 15. Resilience

`xmip-core-resilience` is a native Rust implementation informed by Polly, not a
line-by-line translation of it. Initial scope:

```text
Retry   Timeout   Circuit Breaker   Fallback   Rate Limiting   Bulkhead
```

**Handlers report Success, Retryable Failure or Non-retryable Failure. They do
not own retry loops.** A handler with its own retry loop cannot be governed by
policy, and two of them compound multiplicatively.

Once configured retries are exhausted the Journey fails, and an operator may
retry later. The same primitives supervise Host Services, per ADR-0018.

## 16. Audit, retention and archiving

**Audit** is the authoritative record of significant Xmip interactions and
boundaries. Audited by default:

```text
Receive Location    Receive Port          Receive Port actions
Publication         Routing               Xmip Process entry and result
Assignment          Transformation        Send Port Group
Send Port           Send Location         Response ingress
Authentication      Authorization         Automatic Retry result
Operator Retry      Replay                Dismissal
Success             Failure
```

**Entry and outcome are audited; execution internals are not.** Custom code and
Extensions may emit additional audit events at any meaningful stage.

**Retention** (`xmip-core-retain`) holds what Audit needs to show: Messages,
Streams or durable Stream references, lineage, Journey execution positions,
artifact and Handler outcomes. Policy may apply by Receive Location, Receive
Port, Publication, Journey, Message, Stream, Event, Audit category or retention
category, using time, size, count, state or hold rules.

**Archiving** (`xmip-core-archive`) moves, represents, stores and restores
retained history. Targets may include CSV, SQL, JSON, Parquet, XML, Avro, file
systems, object stores and custom providers.

Audit comes first conceptually and uses retention to show Messages and their
Streams at audited events, and to support Replay.

## 17. Eventing

`xmip-core-event` is separate from internal Routing, and the distinction is one
question each:

> **Routing** — where should this Message continue?
> **Eventing** — who is allowed to know that an action completed, and what may
> they receive?

Every completed Receive, Process and Send action produces a signalable Event
for every outcome: success, failure, rejection, waiting, pause, timeout,
exhausted retries, failure or dismissal where applicable.

An Event carries event identity and type, timestamp, action and outcome,
Journey reference where a Journey exists, Message and Stream references,
Endpoint, Module and Artifact, Party context, and safe diagnostic information.
For large Messages and Transfer workloads it carries metadata and durable
references rather than copying the Stream.

Event receivers are identified, authenticated and authorized, preferably as
Parties communicating through Endpoints. Authorization controls which Event
types, Messages, Streams, Journeys and metadata a receiver may access. **Event
delivery and its security outcome are audited.**

## 18. Parties and Endpoints

A **Party** is an organization, stakeholder, system, service or other entity
Xmip interacts with. `xmip-core-party` connects Parties to identities,
permissions, contacts, agreements and Endpoints, and holds the identities a
Party is recognised by on receive and the ones Xmip presents on send. ADR-0019.

**Endpoint** is the public, non-technical collective term for Receive Port,
Receive Location, Send Port Group, Send Port and Send Location.

> Artifacts are Xmip's precise internal model. Endpoints are Xmip's public
> operational model.

Internally they remain distinct Artifacts with precise responsibilities;
externally they are observed, reported and administered as Endpoints.

## 19. The security path

```text
xmip-core-identify      establishes the claimed identity
xmip-core-authenticate  proves it
xmip-core-authorize     determines what the proven identity may do
xmip-core-party         provides stakeholder context and connects identities,
                        permissions and Endpoints
```

All access through Xmip follows this path. **Development uses permissive
configuration; it does not bypass security.** A developer installation
bootstraps four identities:

```text
Developer   Me   Myself   I
```

and two Parties:

```text
Nice     Me
Greedy   Myself, I
```

They exist to make development immediately usable. Permissions stay
configurable, and every other environment requires precise identification,
authentication, authorization, Party and Endpoint configuration.

> Environment profiles change policy, never the security architecture.

Secrets and certificates are referenced through providers and never embedded in
configuration, logs, retention or audit. Xmip supports ACME-compatible
certificate provisioning and renewal. **All access results are audited without
recording secret values.**

## 20. Artifacts, Content, Contract and Configuration

**Artifacts** are configured objects that compose Modules:

```text
Receive Port   Receive Location   Xmip Process   Assignment
Transformation   Send Port   Send Port Group   Send Location
```

**Content** describes how a Message is represented and how it can be
identified, partially deserialized, serialized, promoted and demoted: XML,
JSON, CSV, EDI, HL7, FHIR, text, binary, custom. **Content is independent of
Transport** — the same XML Message may arrive by FILE, FTP, HTTP or MQ.

**A Contract** is executable validation and structural knowledge applied to a
Message:

```text
Schema     XML Schema, JSON Schema, RegEx, Avro, Protobuf
Standard   EDI, HL7, FHIR and other standardized validation systems
Custom     stakeholder, project and partner contracts, and contracts derived
           from standard or other custom contracts
```

Contract derivation is a design-time and build-time concern using the
underlying contract technology — XML Schema import and restriction, JSON Schema
`$ref`, EDI implementation guides, HL7 conformance profiles, FHIR profiles,
custom validation code. **Runtime TOML selects a completed, versioned Contract;
runtime configuration never constructs Contract inheritance.**

**Configuration** is TOML and composes already-implemented, versioned Modules
and Artifacts. A Receive Location selects, by reference: Transport Handler,
Content Handler, Contract, accepted identities and mechanisms, authorization,
interaction type, response behaviour, and audit and retention policy.

## 21. Conflicts resolved

Four substantive disagreements existed between the four source documents and
the accepted ADRs. Recording them because each was load-bearing, and because a
merge that hides them is worse than four documents that disagree visibly.

**1. Who creates the Message, and when a Journey begins.**
v1.0 said every Stream reaching a Receive Location creates a Journey, Message
and Stream, "even when authentication, authorization, handling, validation or
routing later fails". Baseline-Current reassigned this: the Receive Location
receives, the Receive **Port** creates the Message, and Publication starts the
Journey. ADR-0013 went further: Message creation follows transport
authorization, and Journey creation follows successful Validation.

*Resolved:* Baseline-Current and ADR-0013, which agree. v1.0's rule would mean
Xmip creates a Journey for every unauthenticated connection attempt, which is
both a liability and a denial-of-service surface. Section 4 states the result.

**2. Journey states — two different enums.**
v1.0 named seven operational states. `journey_model.rs` implements six, and
ADR-0013 clause 7 records the code.

*Resolved:* the code. The mapping, and the two that had no equivalent:

| v1.0 | Now | |
| --- | --- | --- |
| Created | — | a Journey exists only after Validation, so there is nothing to be Created in |
| Running | `Active` | |
| Paused | `Suspended` | operator-initiated |
| Waiting | `Waiting` | |
| Dead | `Failed` | |
| Completed | `Completed` | |
| Dismissed | — | **see below** |
| — | `Recovering` | a Retry in flight, which v1.0 could not express |

`Dismissed` is the loss, and it is real: Dismiss is a command in section 13 with
no state to land in, so a dismissed Journey is currently indistinguishable from
one that simply Failed. Either `JourneyState` gains a `Dismissed` terminal
variant, or dismissal is recorded outside the state as an audited disposition.
**Not decided here — it needs a ruling and belongs in ADR-0013.**

**3. What happens when no Subscription matches.**
v1.0 and Baseline-Current both said the Journey becomes Dead with a Routing
cause. ADR-0013 says a Publication produces zero, one or N Journeys, so zero
matches means no Journey exists to become Dead, and the Message goes to the
Xmip DMQ.

*Resolved:* ADR-0013. Baseline-Current had already hedged toward it — "when no
Subscription matches *after a Journey has begun*" — which is a sentence written
by someone noticing the same problem.

**4. One ABI or one per Module.**
Baseline-Current proposed that each extensible Module owns its own ABI rather
than relying on one broad `xmip-abi`. ADR-0012 decided one normative C ABI,
`xmip_module.h`, in `xmip-core-abi`.

*Resolved:* ADR-0012. Per-module ABIs multiply the version-negotiation surface
by the number of Modules, and the compatibility matrix by its square.

**5. Whether the interchange identifier is stable across message generations.**
Not from the four specifications — from the ADRs and the retired glossary, and
found while adding the Actor model.

ADR-0008 says Assignment and Transformation create "a new message form with a
new messageId and the **same** interchangeId". `architecture/glossary.md` said
the opposite: a **child** Interchange with a **new** interchange id, referencing
its parent, so that a Message carries a chain `I1 -> I2 -> I3`.

*Resolved:* ADR-0008, which is Accepted and later. The interchange identifier is
**stable** across every generation descended from one reception. It is a
correlation identifier, not a lineage chain, and generation is tracked by
message id.

That leaves a naming question rather than a modelling one, since "Interchange"
is retired vocabulary. A stable identifier over one reception and all its
descendants is what ADR-0013 calls the **Publication** — one event, one
identity, immutable. Whether the two are the same identifier is undecided and
recorded in `terminology.md`.

Two further differences were vocabulary rather than substance. **Tracking** is
now `xmip-core-audit` for the authoritative record and `xmip-core-retain` for
what it shows — the split survives, the name did not. All Module names in the
source documents predate ADR-0011 and are `xmip-core-*` here.

## 22. Governing principles

1. Streams and Messages are immutable.
2. Receive Locations receive Streams; Receive Ports create Messages;
   Publication offers them; Routing decides where they go; Journeys carry them.
3. Failures before Publication are audited receive failures, not Dead Journeys.
4. Transport, Content and Contract are independent concerns.
5. Every Publication is audited.
6. A Publication produces zero, one or N Journeys — one per matched
   Subscription. A Journey is a line, not a tree.
7. Zero matches means the Xmip DMQ, not a failed Journey.
8. Retry continues the same Journey from the failed audited stage.
9. Replay creates a new Journey from an audited historical source, unchanged.
10. Audit uses retention to inspect and replay retained Messages and Streams.
11. Every Xmip artifact is an Actor when it communicates, and every Message has
    one owning Actor at every stage. Actor semantics never erase artifact
    semantics.
12. A security role, an actor capability and a Party are three dimensions, and
    none of them is the others.
13. Xmip owns the public contracts; stakeholders own implementations.
14. Development may be permissive; production is hardened by policy. Neither
    bypasses the security path.
15. Xmip never parses content from an unauthorized sender.

## 23. Design goal

Xmip shall make every Journey understandable, auditable, retryable, replayable
and dismissible, from the first received Stream until completion or intentional
dismissal.

The operational question Xmip must always be able to answer is:

> Show me the Journey.
