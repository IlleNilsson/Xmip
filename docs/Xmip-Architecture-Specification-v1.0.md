# Xmip Architecture Specification v1.0

Status: Architecture baseline

This document captures the agreed Xmip architecture. Future implementation work should conform to this model unless a design review explicitly changes it.

## 1. Purpose

Xmip assists people and organizations by reliably receiving, moving, understanding, validating, processing, delivering, auditing and recovering information over time.

Xmip is:

- Stream-centric at its foundation.
- Stream- and Message-centric in processing layers.
- Journey-centric in execution and operations.
- Immutable by design.

## 2. Fundamental runtime model

### Stream

A Stream is immutable data received by or produced within Xmip.

### Message

A Message is immutable and references one immutable Stream.

An XML instance, JSON instance, CSV instance, EDI instance, HL7 instance, FHIR instance, text or binary payload may be represented by a Message. These representations are not Contracts.

### Journey

A Journey is the complete execution context and history that carries Messages and Streams through Xmip over time.

Every Stream reaching a Receive Location creates:

```text
Journey
Message
Stream
```

This remains true even when authentication, authorization, handling, validation or routing later fails.

## 3. Immutability

Streams and Messages are never modified.

Assignments and transformations create new immutable artifacts when information changes.

A Journey retains and appends execution history, audit events, tracking references and lineage. Its historical record is never rewritten.

## 4. Platform repositories

The main `Xmip` repository is the integration repository and shall reference purpose-specific repositories as git submodules.

Planned platform repositories:

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

Responsibilities:

- `xmip-core`: domain model, identifiers and public traits/interfaces.
- `xmip-abi`: stable binary loading boundary and version negotiation.
- `xmip-service`: long-running Xmip System Process and supervision.
- `xmip-host`: Host Process lifecycle, isolation and Module loading.
- `xmip-runtime`: Journey execution, scheduling, publication, routing and artifact execution.
- `xmip-cluster`: node membership, capability awareness, ownership, failover and recovery.
- `xmip-configuration`: TOML parsing, validation and environment-specific configuration.
- `xmip-persistence`: durable Journey, Message, Stream, checkpoint, lease and deduplication contracts.
- `xmip-resilience`: native Rust resilience pipelines inspired by Polly.
- `xmip-tracking`: retained Messages, Streams, lineage, execution positions and operational history.
- `xmip-auditing`: authoritative audit views, inspection and replay using Tracking.
- `xmip-cli`: cross-platform command-line administration.
- `xmip-powershell`: PowerShell administration module.

## 5. Definition, configuration and execution

### Definition

Developers define reusable capabilities through Modules, traits, interfaces and ABI contracts.

### Configuration

Architects and integrators configure Artifacts that compose those capabilities.

### Execution

Xmip creates and executes Journeys, Messages, Streams, Publications, Routing results, audit events and tracking records.

## 6. Modules and external stakeholders

Xmip owns the public contracts. Xmip, partners and external stakeholders may implement them.

Git submodules are a source-composition mechanism for first-party repositories. They are not the extension model.

External Modules may be supplied by reference as compatible Rust crates, dynamic libraries, executables, Host Process Modules or deployment packages.

Primary public implementation families:

```text
Transport
Content
Contract
Store
Security
Tracking
Auditing
Resilience
```

## 7. Transport technology dependency tree

The transport tree describes reusable technology dependencies.

```text
File System
    File
    File Watch
    File Poll

IP
    TCP
        HTTP
            Web API
            SOAP
            Webhook
            gRPC
        FTP
        FTPS
        SFTP
        MLLP
        MQTT
        WebSocket
    UDP
        DNS
        Syslog
        SNMP
        CoAP

Custom Transport
    Any stakeholder implementation satisfying Xmip transport contracts
```

Example repository families:

```text
xmip-transport-file-system
xmip-transport-ip
xmip-transport-tcp
xmip-transport-udp

xmip-handler-file
xmip-handler-http
xmip-handler-ftp
xmip-handler-sftp
xmip-handler-mllp
xmip-handler-grpc
```

Technology hierarchy is a dependency graph. It is not a statement that a Message format belongs to a transport.

## 8. Content tree

Content describes the representation of a Message and how it can be identified, partially deserialized, serialized, promoted and demoted.

```text
XML
JSON
CSV
EDI
HL7
FHIR
Text
Binary
Custom Content
```

Content Modules are independent from Transport Modules.

The same XML or JSON Message may be received by FILE, FTP, HTTP, MQ or another Transport.

## 9. Contract tree

A Contract is executable validation and structural knowledge applied to a Message.

```text
Schema Contracts
    XML Schema
    JSON Schema
    RegEx
    Avro
    Protobuf

Standard Contracts
    EDI
    HL7
    FHIR
    Other standardized validation systems

Custom Contracts
    Stakeholder contracts
    Project contracts
    Partner contracts
    Contracts derived from standard contracts
    Contracts derived from other custom contracts
```

Contract derivation is a design-time and build-time concern using the underlying contract technology or code dependency model.

Examples:

- XML Schema include/import/extension/restriction.
- JSON Schema `$ref` and composition.
- EDI implementation guides.
- HL7 conformance profiles.
- FHIR profiles and implementation guides.
- Custom executable validation code.

Runtime TOML selects a completed, versioned Contract. Runtime configuration does not construct Contract inheritance.

## 10. Artifacts

Artifacts are configured objects that compose Modules.

```text
Receive Port
Receive Location
Xmip Process
Assignment
Transformation
Send Port
Send Port Group
Send Location
```

## 11. Receive model

### Receive Port

A Receive Port is the logical common ingress for information of one purpose.

Examples:

```text
Invoices
Purchase Orders
Customers
Laboratory Results
```

It owns common actions and Publication.

### Receive Location

A Receive Location defines how a Stream reaches its parent Receive Port.

It owns:

- Transport binding and endpoint.
- Authentication.
- Authorization.
- Interaction type.
- Response or acknowledgement behavior.
- Location-specific Content and Contract configuration where applicable.

All Receive Locations configured under one Receive Port feed that same Receive Port.

```text
HTTP Receive Location ─┐
FILE Receive Location ─┼─> Invoices Receive Port ─> Publication ─> Routing
FTP Receive Location  ─┘
```

The Receive Port executes with the context of the originating Receive Location.

## 12. Receive Location types

Receive Location type defines the interaction model, not the transport.

### Composite

A caller expects a response composed through configured Xmip artifacts.

The Receive Location may wait for a Process-produced response.

Examples include SOAP, Web API and gRPC calls that require a computed response.

### Data Transfer

A caller transfers information.

Xmip acknowledges after authentication, authorization, required Content Handling and Contract validation succeed. The Journey then continues asynchronously.

### Batch Load

A batch or large workload is accepted and acknowledged for later processing. The configured solution determines whether it creates one or many Journeys.

The same transport technology may support more than one Receive Location type.

## 13. Publication and Routing

Every incoming Stream creates a Message and a Publication through its Receive Port.

A Publication is not an attempt. It is the act that makes the Message available for Routing.

Every Publication is audited.

Routing is the evaluation of a Publication against Subscriptions.

Subscriptions may select:

```text
Xmip Process
Send Port
Send Port Group
```

When no Subscription matches, the Journey becomes Dead with a Routing cause.

## 14. Send model

A Send Port receives a routed Message and executes common configured actions.

A Send Port Group invokes configured Send Ports.

A Send Location owns the concrete outbound transport execution.

A Send Location may:

- Assign.
- Transform.
- Validate.
- Demote.
- Serialize.
- Send.
- Receive an optional response.

A Send Location response creates:

```text
New Stream
New Message
Same Journey
```

The response ingress must be authenticated, authorized and audited before acceptance.

## 15. Receive responses

A Receive Location may return an optional response.

By default, Data Transfer and Batch Load interactions acknowledge as soon as Xmip has accepted and validated the Message.

Xmip does not wait for the Journey to complete unless the configured Composite interaction requires a Process-produced response.

This applies equally to SOAP, Web API, HTTP and gRPC technologies.

## 16. Authentication and authorization

Every ingress must be authenticated and authorized before further acceptance processing.

Ingress includes:

- Receive Locations.
- Send Location responses.
- Inter-node or inter-cluster ingress.
- Other externally initiated callbacks.

Development environments may permit broad access for convenience. Production profiles harden policies, require explicit identity and least privilege, and reject unsafe configuration according to stakeholder policy.

Xmip shall support safe references to credentials and certificates, including ACME-compatible certificate provisioning and renewal. Secrets must not be written into ordinary configuration, logs, Tracking or Auditing.

All ingress access results are audited without recording secret values.

## 17. Auditing and Tracking

### Auditing

Auditing is the authoritative record of significant Xmip interactions and boundaries.

Auditing comes first conceptually and uses Tracking to show Messages and corresponding Streams at audited events and to support Replay.

Default audited boundaries include:

```text
Receive Location
Receive Port
Receive Port actions
Publication
Routing
Xmip Process entry and result
Assignment entry and result
Transformation entry and result
Send Port Group
Send Port
Send Location
Response ingress
Authentication
Authorization
Automatic Retry result
Operator Retry
Replay
Dismissal
Success
Failure
```

Execution internals are not audited by default. Entry and outcome are audited. Custom code and Extensions may emit additional audit events at any meaningful execution stage.

### Tracking

Tracking retains:

- Messages.
- Streams or durable Stream references.
- Lineage.
- Journey execution positions.
- Artifact and Handler outcomes.
- Data required to follow a Journey.
- Data required by Auditing and Replay.

## 18. Journey states

```text
Created
Running
Paused
Waiting
Dead
Completed
Dismissed
```

### Dead Journey

A Dead Journey is a Journey that cannot continue automatically because a required condition has failed.

Causes may include:

```text
Authentication
Authorization
Transport Handler
Content Handler
Contract
Routing
Xmip Process
Send Location
Response
Technical failure
```

The state answers where the Journey is. The cause answers why it became Dead.

A Dead Journey retains its Message, Stream, Receive Port, Receive Location, failure stage, failure reason and audit/tracking references needed for diagnosis.

## 19. Journey control

Commands operating on the same Journey:

```text
Start
Pause
Continue
Retry
Stop
Dismiss
```

### Retry

Retry resumes execution from the failed audited stage of the same Journey.

Xmip may perform configured automatic retries. An authorized operator may also issue Retry after configured retries are exhausted and the underlying issue has been corrected.

Successful prior actions are not repeated unnecessarily.

### Stop

Stop prevents further execution. The resulting state depends on the reason and policy.

### Dismiss

Dismiss intentionally terminates a Dead or otherwise selected Journey without deleting its history, Messages, Streams, Tracking or Audit.

## 20. Replay

Replay is not a Journey command and is not Retry.

Replay uses retained Auditing and Tracking evidence to create a new Journey from a selected historical source. A replay source may be:

```text
A historical Receive Location event
A historical Receive Port event or Publication
A historical Journey starting point
```

Replay uses the Message, corresponding Stream, artifact context and configuration identity retained at the selected audited source. The new Journey records lineage to the original audited source and to the original Journey when one exists.

Examples:

- Replay what entered a particular Receive Location during a selected period.
- Replay a Message as it entered a Receive Port before its actions and Publication.
- Replay an entire Journey from its original starting point.

The historical source remains unchanged. Replay itself is audited.

## 21. Resilience

Automatic retries shall use a native Rust resilience implementation inspired by Polly rather than a direct line-by-line C# translation.

The initial resilience scope includes:

```text
Retry
Timeout
Circuit Breaker
Fallback
Rate Limiting
```

Handlers report Success, Retryable Failure or Non-retryable Failure. They do not own independent retry loops.

After configured retries are exhausted, the Journey becomes Dead. An authorized operator may issue Retry later.

## 22. Configuration

Xmip configuration uses TOML.

Configuration composes already implemented and versioned Modules and Artifacts.

A Receive Location configuration selects, by reference:

```text
Transport Handler
Content Handler
Contract
Authentication
Authorization
Interaction type
Response behavior
Audit and Tracking policy
```

Configuration shall reference secrets and certificates through providers, never embed sensitive values directly.

## 23. Repository split rule

A new repository is created only when:

- its responsibility is clear;
- its public contract is stable enough to be used independently;
- independent versioning is justified;
- independent build and release are useful;
- external stakeholders can reasonably depend on or implement it.

First-party repositories are added to `Xmip` as git submodules after creation.

## 24. Governing principles

1. Streams and Messages are immutable.
2. Every incoming Stream creates a Journey, Message and Stream.
3. Receive Ports define the logical ingress; Receive Locations define how it arrives.
4. Transport, Content and Contract are independent concerns.
5. Every Publication is audited.
6. Routing evaluates Subscriptions.
7. Any unrecoverable automatic failure creates a Dead Journey.
8. Retry continues the same Journey from the failed audited stage.
9. Dismiss is a command on the selected Journey.
10. Replay creates a new Journey from a selected audited Receive Location, Receive Port or Journey source.
11. Auditing uses Tracking to inspect and replay retained Messages and Streams.
12. Xmip owns public traits/interfaces; stakeholders own implementations.
13. Development may be permissive; production is hardened by policy.

## 25. Design goal

Xmip shall make every Journey understandable, auditable, retryable, replayable and dismissible from the first received Stream until completion or intentional dismissal.

The operational question Xmip must always be able to answer is:

> Show me the Journey.
