# Xmip Architecture Baseline — Current

Status: Agreed architectural baseline

This document preserves the architectural decisions made after reviewing Xmip from implementation, operational, developer, stakeholder and marketing perspectives. It supplements the detailed architecture specification and takes precedence where an older statement conflicts with this baseline.

## Working method

Xmip architecture work follows this sequence:

```text
Discuss
Agree
Commit
```

Major decisions record both the decision and its reason. Xmip is designed around responsibilities rather than technologies. Technologies evolve; responsibilities should remain stable.

## Fundamental receive and Journey boundary

The agreed responsibility chain is:

```text
External Stream
    -> Receive Location
    -> Receive Port accepts the Stream
    -> Receive Port creates the Message
    -> Routing publishes the Message
    -> Journey begins
```

A Receive Location owns physical ingress. It receives a Stream and performs the configured acceptance work, including identification, authentication, authorization, Transport Handling, Preparation Steps, Content Handling and Contract validation.

A Receive Port owns logical ingress. After accepting the Stream, it creates the Message and passes it to Routing for Publication.

Failures before Publication are audited receive failures. A Journey begins when the accepted Message is published.

> Receive Locations receive Streams. Receive Ports create Messages. Publication starts Journeys. Routing determines where Journeys continue.

## Receive Port and Receive Locations

All Receive Locations configured beneath one Receive Port feed that same Receive Port.

```text
HTTP Receive Location ---+
FILE Receive Location ---+--> Invoices Receive Port --> Routing
FTP Receive Location ----+
```

The Receive Port is the common logical ingress. Each Receive Location retains its own transport, security, interaction and response characteristics. The Receive Port executes with the context of the originating Receive Location.

## Receive interaction characteristics

The current interaction terms are:

```text
Composite
Data Transfer
Batch Load
```

Composite describes a call whose response may be composed through Xmip Processes, Send Ports or other configured work.

Data Transfer describes delivery of information with an acknowledgement after the configured acceptance requirements have succeeded.

Batch Load describes acceptance of a batch or large workload for subsequent processing.

The inspection/processing wording is not frozen. The current technical progression is:

```text
Transfer
Light
Context
```

Their meaning is:

```text
Transfer
    Move a trusted, often very large Stream without deserialization or payload inspection.

Light
    Route using trusted sender, Receive Location, declared type and other metadata.

Context
    Interpret the Message through Content, Contract and Path capabilities for content-aware Routing.
```

Interaction and processing depth are separate characteristics, but their developer-facing wording still requires refinement.

## Routing Module

Publication is part of Routing, not a separate platform concern.

The `xmip-routing` Module owns:

```text
Publish
Path
Subscription evaluation
Dispatch
```

Routing is the evaluation of a Publication against Subscriptions and dispatch to matched targets.

Targets may be:

```text
Xmip Process
Send Port
Send Port Group
```

When no Subscription matches after a Journey has begun, the Journey becomes Dead with a Routing cause.

### Path

Xmip has a simple base path model using numbered and named indexes:

```text
index[n]
index['name']
```

Format-native Path technologies are allowed and expected, including XPath, JSONPath, JSON Pointer, FHIRPath, EDI selectors, HL7 selectors and future or stakeholder-defined technologies.

A Message retains the applicable Content, Contract and Path technologies until Assignment or Transformation creates a new Message and, where changed, a new Stream.

Transfer and Light Routing do not require Path evaluation.

## Send side

### Send Port Group

A Send Port Group owns no delivery behavior. It is a named convenience collection of Send Ports.

When a Subscription targets a Send Port Group, the Publication is dispatched to every Send Port in that collection. Each Send Port executes independently.

### Send Port

A Send Port is the logical outbound artifact. Multiple Subscriptions may dispatch Messages to the same Send Port.

A Send Port may:

```text
Receive a routed Message
Transform the current Message
Select and invoke ordered Send Locations
Apply configured retry and failover policy
Audit its actions and outcomes
```

A Send Port cannot perform Assignment. Receive and Send artifacts only have the current Message and cannot make Process decisions or create assigned Messages. Assignment belongs to an Xmip Process. Transformation may occur in a Receive Port, Xmip Process or Send Port.

### Send Location

A Send Location is one physical outbound endpoint. It owns the concrete transport, destination, credentials, serialization, demotion, optional outgoing Contract validation, delivery and optional response transport.

A Send Port succeeds when one of its configured Send Locations succeeds. Retries apply to the active Send Location according to policy. Failover proceeds to another Send Location according to Send Port policy. If all Send Locations fail, the Journey becomes Dead.

A Send Location may receive a response Stream. The Send Port and Send Location share responsibility for bringing the response into Xmip:

```text
Send Location receives the physical response Stream
Send Port accepts it and creates the response Message
Response Message continues the same Journey
```

Likewise, on the receive side, a Receive Port produces the logical response Message while the originating Receive Location transports the response Stream back to the caller.

> Locations exchange Streams with the outside world. Ports exchange Messages with Xmip.

## Preparation Steps

Preparation Step is the Xmip term for the useful capability often implemented by BizTalk Pipelines when external standards are not followed.

Preparation Steps prepare Streams before or after normal Content processing. Examples include:

```text
Decrypt
Encrypt
Decompress
Compress
Extract or create archives
Decode or encode
Convert character encoding
Normalize line endings
Unwrap or wrap
Digitally sign or verify
Repair explicitly configured partner quirks
Custom Preparation Step
```

Preparation Steps contain no Process decision logic and no Assignment.

## Platform, Modules, capabilities and services

Xmip is the Platform.

The functional building blocks previously called platforms are Modules.

```text
Xmip Platform
    -> Modules
        -> capabilities and, where applicable, services
```

A Module may contain cohesive Handlers, providers, services or other implementation components. Each extensible Module owns its own ABI rather than relying on one broad `xmip-abi`.

A minimal common module foundation may define only universal conventions such as module identity, lifecycle, capability discovery, versioning, error representation, host handshake and buffer ownership.

Each Module may contribute its own:

```text
ABI
CLI extension
PowerShell extension
Configuration
```

The common `xmip-cli` and `xmip-powershell` Modules host and present commands contributed by other Modules; they do not own all Module-specific administration logic.

Current agreed Module map includes:

```text
xmip-core
xmip-routing
xmip-resilience
xmip-retention
xmip-archiving
xmip-persistence
xmip-tracking
xmip-auditing
xmip-observer
xmip-reporter
xmip-eventing
xmip-identification
xmip-authentication
xmip-authorization
xmip-parties
xmip-runtime
xmip-cluster
xmip-configuration
xmip-host
xmip-service
xmip-cli
xmip-powershell
```

## Parties and Endpoints

A Party is an organization, stakeholder, system, service or other entity with which Xmip interacts.

The `xmip-parties` Module depends on Identification, Authentication and Authorization and connects Parties to identities, permissions, contacts, agreements and Endpoints.

Endpoint is the public and non-technical collective term for:

```text
Receive Port
Receive Location
Send Port Group
Send Port
Send Location
```

Internally these remain distinct Artifacts with precise responsibilities. Externally they may be observed, reported and administered as Endpoints.

> Artifacts are Xmip's precise internal model. Endpoints are Xmip's public operational model.

## Security Modules

Security is separated into:

```text
xmip-identification
    Establishes the claimed identity.

xmip-authentication
    Proves the claimed identity.

xmip-authorization
    Determines what the authenticated identity may do or access.

xmip-parties
    Provides stakeholder context and connects identities, permissions and Endpoints.
```

All access through Xmip follows this security path. Development uses permissive Xmip security configuration; it does not bypass security.

A developer installation bootstraps four identities:

```text
Developer
Me
Myself
I
```

and two Parties:

```text
Nice
    Me

Greedy
    Myself
    I
```

The names provide usable development bootstrap data. Permissions remain configurable.

Other environments require precise identification, authentication, authorization, Party and Endpoint configuration.

> Environment profiles change policy, never the security architecture.

## Xmip Eventing

`xmip-eventing` is separate from internal Routing.

Internal Routing answers:

> Where should this Message continue?

Xmip Eventing answers:

> Who is allowed to know that an action completed, and what may they receive?

Every completed Receive, Process and Send action produces a signalable Xmip Event for every outcome, including success, failure, rejection, waiting, pause, timeout, exhausted retries, Dead or dismissal where applicable.

An Event contains the completed action, outcome and applicable Message context. For large Messages and Transfer workloads, it contains metadata and durable references rather than copying the Stream.

Typical Event data includes:

```text
Event identity and type
Timestamp
Action and outcome
Journey reference, when a Journey exists
Message reference
Stream reference
Endpoint
Module and Artifact
Party context
Safe diagnostic information
```

Event receivers must be identified, authenticated and authorized, preferably as Parties communicating through Endpoints. Authorization controls which Event types, Messages, Streams, Journeys and metadata a receiver may access.

Event delivery and its security outcome are audited.

## Journey control and operations

Commands controlling the same Journey are:

```text
Start
Pause
Continue
Retry
Stop
Dismiss
```

Retry continues the same Journey from the failed audited stage. It may be automatic according to configured resilience policy or manually initiated by an authorized operator after automatic retries are exhausted.

Replay is separate. Replay creates a new Journey from an audited historical source, which may be:

```text
A Receive Location event
A Receive Port event or Publication
A Journey starting point
```

The original evidence and lineage remain unchanged.

## Dead Journeys

A Dead Journey is a Journey state entered when the Journey cannot continue automatically after Publication.

Causes may include Handler, Contract, Routing, Process, Send Location, response or technical failure. Authentication or authorization may cause a Dead Journey only when the Journey already exists; failures during pre-Publication receive acceptance remain audited receive failures.

A Dead Journey may be Retried, Dismissed or used as a source for Replay according to authorization and retained evidence.

## Auditing, Tracking, Retention and Archiving

Auditing is the authoritative record of significant Xmip interactions and boundaries.

Tracking retains Messages, Streams or references, lineage and execution state needed by Auditing to inspect and follow Journeys and support Retry and Replay.

Retention decides how long or how much historical information remains available. Policies may apply by Receive Location, Receive Port, Publication, Journey, Message, Stream, Event, Audit or Tracking category using time, size, count, state or hold rules.

Archiving is a separate Module. It executes movement, representation, storage and restoration of retained historical data. Archive formats and targets may include:

```text
CSV
SQL
JSON
Parquet
XML
Avro
File systems
Object stores
Custom providers
```

Replay and detailed inspection are possible only while the required retained or archived evidence can be restored.

## Marketing and explanatory language

Engineering language remains precise:

```text
A Stream enters through a Receive Location.
A Receive Port accepts the Stream and creates a Message.
Routing publishes the Message and the Journey begins.
The Message travels through Xmip on that Journey.
```

A stakeholder-facing expression may be:

> Every Message travels through Xmip on an observable, durable Journey.

Xmip hauls short, light, long, fast and heavy Messages through durable, observable Journeys, while applying only the amount of interpretation the configured integration requires.

The marketing perspective is an architectural review tool. Explaining Xmip to developers, operators and non-technical stakeholders exposed and clarified the ownership of Streams, Messages, Ports, Locations, Publication, Routing and Journeys.

## Architecture review note

This baseline was established after reviewing Xmip from implementation, operational, developer, stakeholder and marketing perspectives. Several responsibilities were deliberately reassigned, including Message creation, Journey creation, Publication ownership, Port/Location response responsibilities, Eventing and security ownership.

Future changes to these responsibilities require explicit architectural review rather than incidental implementation changes.
