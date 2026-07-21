# Xmip Architecture Specification v1.1

Status: Architecture baseline

This specification and `xmip-architecture.json` are the authoritative desired state for Xmip.

## 1. Purpose

Xmip reliably receives, moves, understands, validates, processes, delivers, observes and recovers information over time.

Xmip is:

- Stream-centric at its foundation;
- Stream-and-Message-centric in processing;
- Journey-centric in execution and operations;
- immutable by design;
- modular by capability and technology.

## 2. Runtime lifecycle

```text
Incoming Stream
    -> Transport identification
    -> Transport authentication
    -> Transport authorization
    -> Message creation
    -> Default promotion
    -> Configuration may inspect Stream and Message Context
    -> Optional message identification
    -> Optional message authentication
    -> Optional message authorization
    -> Contract implication
    -> Optional deserialization
    -> Validation
    -> Journey creation
```

Transport identification, authentication and authorization occur before Message creation. Message-level security is separate and optional. Journey creation occurs only after required validation succeeds.

An incoming transport attempt that fails before Message creation may be audited as a transport event, but it is not a Message or Journey.

## 3. Stream, Message, Context and Journey

### Stream

A Stream is immutable data accepted by or produced within Xmip.

### Message

A Message is immutable and contains one or more immutable sections. Each accepted incoming Stream becomes a section with its own section identifier. A transformation or assignment creates a new Message instance with the same Journey lineage and new Message and section identifiers as applicable.

### Message Context

Message Context contains metadata and promoted values. It exists after Message creation and may be inspected before Contract implication or deserialization.

### Journey

A Journey is the execution context and lineage of validated work through Xmip over time. Journey replaces the former term Interchange.

## 4. Contract architecture

A Contract is one of:

- a schema;
- a profile;
- a standard;
- code.

A Contract does not execute itself.

`xmip-contract` owns:

- Contract implication;
- evaluation coordination;
- common results and diagnostics.

Technology repositories implement specific Contract technologies, for example:

```text
xmip-contract-xml-schema
xmip-contract-json-schema
xmip-contract-protocol-buffers
xmip-contract-apache-avro
xmip-contract-fhir
```

Contract implication is:

```text
Receive Configuration
+ Incoming Stream
+ Message Context
    -> Implied Contract
```

Runtime configuration participates in implication. It does not construct Contract inheritance and does not merely select a Contract by filename.

## 5. Representation, Contract and Path separation

A Message representation describes how information is encoded. Examples include XML, JSON, CSV, HL7 ER7, text and binary.

A Contract describes structural expectations. Examples include XML Schema, JSON Schema, HL7 profiles and FHIR profiles.

A Path locates information. Path children are path syntaxes or addressing strategies:

```text
xmip-path-xpath
xmip-path-jsonpath
xmip-path-dot
xmip-path-index
xmip-path-json-pointer
xmip-path-fhirpath
xmip-path-regex
```

FHIR is not a generic Message representation. FHIR resources are represented through XML or JSON and governed by FHIR Contracts and profiles.

SOAP is an envelope/protocol concern, not a generic Message representation.

## 6. Receive responsibility

A Receive Location defines how an incoming Stream reaches Xmip. The receiving side performs transport identification, authentication and authorization before Message creation.

After Message creation, default promotion occurs. Configuration may then inspect the Stream and Message Context before optional message-level security, Contract implication and validation.

## 7. Send responsibility

A Send Location presents configured identity material, including as applicable:

- identity;
- credentials;
- certificates;
- tokens;
- claims.

The external receiver performs identification, authentication and authorization. Send owns presentation, not the receiver's security decisions.

## 8. Immutability

Streams and Messages are never modified. Assignment and transformation create new Message instances. Routing does not create a new Message merely by routing.

Journey history and lineage are append-only.

## 9. Repository classification

### Foundation — things Xmip is

Examples: `xmip-core`, `xmip-stream`, `xmip-message`, `xmip-context`, `xmip-journey`, `xmip-node`, `xmip-cluster`, `xmip-party`, `xmip-event`.

### Capabilities — things Xmip does

Examples: `xmip-receive`, `xmip-prepare`, `xmip-identify`, `xmip-authenticate`, `xmip-authorize`, `xmip-contract`, `xmip-path`, `xmip-assign`, `xmip-transform`, `xmip-route`, `xmip-process`, `xmip-send`.

### Technology — how a capability is implemented

Every technology repository is a direct child of a common capability repository.

### Operations — running and governing Xmip

Examples: Audit, Observe, Report, Tracking, Retain, Archive, CLI and PowerShell administration.

### Platform — platform-wide runtime services

Examples: ABI, Service, Host, Runtime, Configuration, Persistence, Resilience and Exclusiveness.

## 10. Repository naming

Repository names use the recognized technology or standard name, normalized to lowercase hyphenated form. File extensions or informal abbreviations are not used when a recognized standard name exists.

Examples:

```text
xmip-contract-xml-schema
xmip-contract-json-schema
xmip-contract-protocol-buffers
xmip-contract-apache-avro
```

## 11. Repository maturity

Repository existence is independent of implementation maturity.

Allowed states:

```text
reserved
scaffolded
implemented
verified
supported
deprecated
retired
```

The complete known repository taxonomy is created from the beginning. Maturity describes implementation and support state, not whether the repository belongs in the architecture.

## 12. Dependency rules

- The graph must be acyclic.
- Foundation must not depend on Technology.
- Common capabilities must not depend on their technology children.
- Technology repositories may depend on their parent capability.
- Technology sibling dependencies require explicit architectural justification.
- Operations consume public contracts and events, not implementation internals.
- Platform services must not depend on specific technology implementations.

## 13. Submodules

The physical submodule hierarchy mirrors capability ownership:

```text
xmip-path/
└── modules/
    ├── xpath/
    ├── jsonpath/
    ├── dot/
    └── index/
```

The five architectural domains remain metadata and do not determine physical submodule paths.

Submodule commits are pinned by the parent repository. Reconciliation must not use uncontrolled `git submodule update --remote` behaviour.

## 14. Desired-state reconciliation

`Set-XmipArchitecture.ps1` reconciles actual state with `xmip-architecture.json`.

Plan mode is read-only. Apply mode is explicit. The script reports:

- missing repositories;
- unexpected repositories;
- deprecated and retired repositories;
- active references to deprecated items;
- repository setting drift;
- missing or unexpected submodules.

The script does not delete repositories automatically.
