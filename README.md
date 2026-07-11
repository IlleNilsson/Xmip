# Xmip

Xmip is a cross-platform messaging and integration platform built around immutable Streams, immutable Messages, long-running Journeys, modular Handlers and executable Contracts.

The repository is currently the integration point for the platform. Focused repositories will be recreated and referenced as git submodules according to the versioned architecture specification.

## Architecture specification

The authoritative baseline is:

[**Xmip Architecture Specification v1.0**](docs/Xmip-Architecture-Specification-v1.0.md)

Changes to top-level concepts, repository responsibilities, public traits/interfaces or Journey semantics require an explicit design review and an update to the specification.

## Architectural foundation

Xmip is Stream-centric at its foundation, Stream-and-Message-centric in processing, and Journey-centric in execution and operations.

```text
External source
    -> immutable Stream
    -> immutable Message referencing that Stream
    -> Content Handling
    -> Contract validation
    -> Receive Port Publication
    -> Routing evaluates Subscriptions
    -> Xmip Process, Send Port or Send Port Group
    -> Send Location
    -> optional response Stream
    -> new Message in the same Journey
```

A Journey retains the lineage of all Messages, Streams, actions and outcomes until it is completed or intentionally dismissed.

## Core vocabulary

```text
Stream
    Immutable data accepted by or produced within Xmip.

Message
    Immutable Xmip object that references one Stream.

Journey
    The complete execution context and history of related work through Xmip over time.

Event
    Something happened that may cause configured work.

Handler
    Executable Module fulfilling an Xmip trait or interface.

Contract
    Executable validation and structural knowledge applied to a Message.

System Process
    An operating-system process.

Xmip Service
    The long-running System Process that starts and supervises Xmip.

Host Process
    A System Process started by Xmip to load and execute Modules.

Xmip Process
    A configured process that progresses a Journey.
```

## Receive model

A Receive Port is the logical common ingress for information of one purpose.

All Receive Locations configured under a Receive Port feed that same Receive Port.

```text
HTTP Receive Location ─┐
FILE Receive Location ─┼─> Invoices Receive Port ─> Publication ─> Routing
FTP Receive Location  ─┘
```

A Receive Location defines how the Stream arrives and owns its transport binding, authentication, authorization, interaction type and response behavior.

Receive Location types are:

```text
Composite
Data Transfer
Batch Load
```

Every Stream reaching a Receive Location creates a Journey, Message and Stream, even when a later required condition fails.

## Publication and Routing

Every incoming Stream becomes a Publication through its Receive Port.

A Publication is not an attempt. Every Publication is audited.

Routing is the evaluation of the Publication against Subscriptions owned by:

```text
Xmip Processes
Send Ports
Send Port Groups
```

When no Subscription matches, the Journey becomes Dead with a Routing cause.

## Send model

A Send Port or Send Port Group selects one or more Send Locations.

A Send Location may perform:

```text
Assignment
Transformation
Contract validation
Content serialization and demotion
Transport send
Automatic Retry
Failover
Optional response receive
```

A response from a Send Location creates a new immutable Stream and a new immutable Message in the same Journey. Because it is ingress, it must be authenticated, authorized and audited before acceptance.

A Receive Location may also return an optional response. Data Transfer and Batch Load normally acknowledge acceptance and validation immediately. Composite interactions may wait for a Process-produced response.

## Transport, Content and Contracts are independent

Xmip does not create a Module for every combination.

```text
FILE + XML + PurchaseOrderContract
HTTP + JSON + InvoiceContract
FTP + EDI + OrderContract
MLLP + HL7 + AdmissionContract
HTTP + FHIR + PatientContract
```

Transport Handlers move Streams.

Content Handlers understand Message representations such as XML instances, JSON instances, CSV, EDI, HL7, FHIR, text or binary.

Contracts validate Messages and provide structural knowledge, selectors, paths, promotion and demotion support. A Contract may be implemented by XML Schema, JSON Schema, RegEx, standardized profiles, implementation guides or custom executable code.

Contract derivation is a design-time and build-time concern of the contract technology. Xmip TOML selects an already built, versioned Contract; it does not define inheritance.

## Journey lifecycle

Journey states:

```text
Created
Running
Paused
Waiting
Dead
Completed
Dismissed
```

Journey control commands operating on the same Journey:

```text
Start
Pause
Continue
Retry
Stop
```

`Retry` resumes the same Journey from its failed audited stage. Automatic Retry may be performed by Xmip; an authorized operator may issue Retry after configured retries are exhausted.

`Replay` is different: it creates a new Journey from another Journey's starting point while preserving lineage.

A Dead Journey may be retried, replayed or dismissed according to authorization and policy.

## Auditing and Tracking

Auditing is the authoritative record of significant Xmip interactions and boundaries.

Tracking retains Messages, Streams or Stream references, lineage, state and execution history that Auditing uses to inspect, follow and replay Journeys.

Default audited boundaries include:

```text
Receive Location
Receive Port and its actions
Authentication and authorization
Transport Handling
Content Handling
Contract validation
Publication
Routing
Xmip Process entry and result
Assignment entry and result
Transformation entry and result
Send Port Group
Send Port
Send Location
Automatic Retry and operator Retry
Response ingress
Replay
Dismissal
Success and failure
```

Execution itself is not automatically audited instruction-by-instruction. Xmip, Handlers, Processes and Extensions may emit additional audit events at any meaningful execution stage.

## Security posture

Every ingress path must support authentication, authorization and auditing.

Development environments may permit broad or test identities. Production environments must support stronger policy, trusted certificates, safe secret references, least privilege and explicit rejection of insecure configuration.

Xmip shall ease stakeholder security work through support for:

```text
ACME and certificate renewal
Let's Encrypt and other ACME authorities
Mutual TLS
Username/password without plaintext configuration
API keys and tokens
OAuth/OIDC
SSH keys
External secret providers
Custom authentication and authorization Modules
```

Secrets must never be written to Tracking or Auditing.

## Repository direction

The planned platform repositories include:

```text
xmip-core
xmip-abi
xmip-service
xmip-host
xmip-runtime
xmip-cluster
xmip-configuration
xmip-persistence
xmip-resilience
xmip-tracking
xmip-auditing
xmip-cli
xmip-powershell
```

Independent repositories will provide Transport, Content, Contract, Store, Security and other Modules. External stakeholders may implement Xmip traits/interfaces in their own repositories and deploy compatible Modules by reference.

First-party repositories will be referenced by `Xmip` as git submodules after their responsibilities and public contracts are established.

## Governing design rule

Xmip owns the public contracts. Stakeholders own implementations.

The platform must always be able to answer:

> Show me the Journey.
