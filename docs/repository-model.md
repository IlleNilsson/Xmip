# Xmip repository model

Xmip uses repositories by purpose.

The main repository, `Xmip`, is the integration point. It can reference other repositories as git submodules, but the architecture is not defined by the file-system tree. The architecture is defined by dependency graphs and runtime configuration.

## Platform repositories

These repositories form the Xmip platform:

```text
xmip-core
    shared domain model and contracts

xmip-abi
    stable binary boundary for dynamically loaded Modules

xmip-service
    long-running System Process that starts and supervises Xmip

xmip-host
    Host Process implementation used to load and execute Modules

xmip-runtime
    scheduling, dispatch, Journey execution, recovery coordination

xmip-cluster
    cluster membership, node capability awareness, failover and recovery ownership

xmip-configuration
    TOML configuration parsing and validation

xmip-persistence
    Journey state, checkpoint, lease and deduplication storage contracts

xmip-tracking
    audit and tracking contracts

xmip-cli
    command-line administration surface
```

## Module repositories

Module repositories implement Xmip contracts. They should not redefine Xmip concepts.

```text
Transport Handler repositories
    move streams between Xmip and the outside world

Content Handler repositories
    identify, deserialize, serialize, promote and demote content

Contract repositories
    validate messages and define selectors/paths usable by Content Handlers

Store repositories
    persist Journey, Message, Stream, checkpoint, lease and audit state
```

## Separation of concerns

A Receive or Send configuration composes independent concerns:

```text
Transport
    how bytes/streams enter or leave

Content
    how a stream is recognized and understood

Contract
    what the content must satisfy and which paths/properties are meaningful
```

Examples:

```text
FILE + XML + PurchaseOrderContract
HTTP + JSON + InvoiceContract
FTP + EDI + OrderContract
MLLP + HL7 + AdmissionContract
HTTP + FHIR + PatientContract
```

Xmip must not create one handler for every combination. That would explode.

Wrong:

```text
HTTP JSON handler
FTP XML handler
FILE EDI handler
```

Right:

```text
HTTP Transport Handler
XML Content Handler
JSON Content Handler
EDI Content Handler
Purchase Order Contract
Invoice Contract
```

## Dependency graph

Technology hierarchy is a dependency graph, not a repository hierarchy.

```text
HTTP depends on TCP
SOAP may depend on HTTP
FHIR content may be carried over HTTP
MLLP depends on TCP
```

A repository may depend on another repository or crate. A repository may also be used as a git submodule by more than one parent repository.

## Contracts and selectors

Contracts are used for:

- validation,
- promotion,
- demotion,
- selectors,
- paths,
- meaning.

Content Handlers use contracts and selectors to inspect only as much of a stream as necessary.

## Current naming direction

Use lower-case repository names for GitHub consistency:

```text
xmip-core
xmip-service
xmip-host
xmip-runtime
xmip-cluster
xmip-handler-file
xmip-handler-http
xmip-content-xml
xmip-content-json
xmip-contract-xml-schema
xmip-contract-json-schema
xmip-store-sqlite
```
