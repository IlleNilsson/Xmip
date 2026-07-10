# Xmip

Xmip is a cross-platform messaging and integration platform built around immutable Streams, immutable Messages, long-running Journeys, modular Handlers and executable Contracts.

The repository is currently the clean integration point for the platform. Code may later be split into focused repositories and referenced as git submodules, but repository boundaries must follow clear purposes rather than accidental folder structure.

## Architectural foundation

Xmip is Stream-centric at its foundation and Stream-and-Message-centric in execution.

```text
External source
    -> immutable Stream
    -> immutable Message referencing that Stream
    -> Content Handling
    -> Contract validation
    -> Publication
    -> Subscription / Routing
    -> Xmip Process, Send Port or Send Port Group
    -> Send Location
    -> optional response Stream
    -> new Message in the same Journey
```

A Journey retains the lineage of all Messages, Streams, actions and outcomes until it is completed, failed, inspected or replayed.

## Core vocabulary

```text
Stream
    Immutable bytes accepted by or produced by Xmip.

Message
    Immutable Xmip object that references a Stream.

Journey
    The lifetime of related work through Xmip over time.

Event
    Something happened that may cause configured work.

Handler
    Executable module fulfilling an Xmip contract.

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

## Receive chain

A Receive Location defines the complete acceptance chain:

```text
Authentication
Authorization
Transport Handler
Content Handler chain
Contract
Receive Location actions
Receive Port actions
Publication
```

If a required stage fails, Xmip regards the received information as faulty, audits the failure and returns or creates an error response when the transport allows it.

FILE, FTP and similar transports need configured rejection, quarantine, acknowledgement or error-file behavior. HTTP, Web API, SOAP, gRPC and similar request/response transports use their native response mechanism.

## Publication and routing

A Receive Port publishes a Message.

Xmip evaluates that Publication against Subscriptions owned by:

```text
Xmip Processes
Send Ports
Send Port Groups
```

Publication, subscription evaluation, matches, routing decisions and subscriber outcomes are audited.

## Send chain

A Send Port or Send Port Group selects one or more Send Locations.

A Send Location may perform:

```text
Assignment
Transformation
Contract validation
Content serialization and demotion
Transport send
Retry
Failover
Response receive
```

A response from a Send Location is a new immutable Stream and a new immutable Message in the same Journey. Because it is ingress, it must be authenticated, authorized and audited before acceptance.

## Transport, content and contracts are independent

Xmip does not create a module for every combination.

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

## Auditing and Tracking

Auditing is the authoritative record of significant Xmip activity.

Tracking stores the Messages, Streams, lineage, state and execution history Auditing uses to inspect, follow and replay a Journey.

Xmip audits entry and success/failure for major execution boundaries, including:

```text
Receive Location
Receive Port
Receive and Port actions
Authentication and authorization
Transport Handling
Content Handling
Contract validation
Publication
Subscription evaluation and match
Routing
Xmip Process
Assignment
Transformation
Send Port Group
Send Port
Send Location
Retry and failover
Response ingress
Journey completion, failure and replay
```

Execution itself is not automatically audited instruction-by-instruction. Xmip, Handlers, Processes and Extensions may emit additional audit points at any meaningful stage.

## Security posture

Every ingress path must support authentication, authorization and auditing.

Development environments may permit broad or test identities. Promotion toward production must support stronger policies, trusted certificates, safe secret references, least privilege and explicit rejection of insecure configuration.

Xmip should ease stakeholder security work through support for:

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

## Future repository boundaries

The intended platform repositories are:

```text
xmip-core
xmip-abi
xmip-service
xmip-host
xmip-runtime
xmip-cluster
xmip-configuration
xmip-persistence
xmip-tracking
xmip-auditing
xmip-cli
```

Independent module repositories will cover Transport Handlers, Content Handlers, Contract implementations, Stores and stakeholder-specific Extensions.

The split will be made only after the purpose and public contract of each repository are stable enough to justify an independent lifecycle.

## Design rule

Build vertical slices first. Introduce or split abstractions only when implementation proves the need.
