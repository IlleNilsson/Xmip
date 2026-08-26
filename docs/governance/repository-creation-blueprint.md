# Xmip Repository Creation Blueprint

Status: committed prerequisite for repository creation, Rust implementation and build work.

This document freezes the repository strategy before new repositories are created. Xmip is one Platform composed of Modules. Most first-party Module repositories will be referenced by the main `Xmip` repository as git submodules.

## 1. Rules before repository creation

1. `Xmip` remains the integration repository and architectural source of truth.
2. A repository represents one coherent Module responsibility, not a folder in a technology tree.
3. Technology trees describe dependencies; submodule paths describe source composition.
4. First-party Modules are separate repositories and are normally added to `Xmip` as submodules.
5. External stakeholders integrate through each Module's traits and ABI, not through the submodule layout.
6. There is no broad standalone `xmip-abi`. Each extensible Module owns its own ABI.
7. A minimal shared `xmip-module-foundation` may contain only universal loading conventions.
8. Each Module owns its administration extensions where applicable: `<module>-cli` and `<module>-powershell`. The root CLI and PowerShell Modules are command hosts, not containers for all Module logic.
9. Every repository starts with the MIT License, README, Cargo metadata, tests and continuous build validation.
10. No Rust implementation begins until the repository exists, is licensed, is referenced correctly and its responsibility is documented.

## 2. Common Module shape

A Module repository may contain a Cargo workspace with only the crates it needs:

```text
xmip-<module>/
    Cargo.toml
    README.md
    LICENSE
    crates/
        xmip-<module>                implementation and native Rust contracts
        xmip-<module>-abi            stable external binary boundary, when required
        xmip-<module>-cli            CLI command contribution, when required
        xmip-<module>-powershell     PowerShell command contribution, when required
    tests/
```

The ABI crate belongs to its Module. It must expose only stable data and operations required across process, language or dynamic-loading boundaries. Native Rust-to-Rust collaboration uses ordinary crate dependencies and traits.

## 3. Foundation repositories — create first

```text
xmip-core
xmip-module-foundation
xmip-configuration
xmip-persistence
```

### xmip-core

Shared domain primitives and identifiers that cannot belong to a narrower Module:

```text
Stream references
Message
Journey
Event envelope
Module identity
Artifact and Endpoint references
Outcome and fault primitives
Version primitives
```

It must not contain Routing, security mechanisms, transport implementations or Module-specific administration.

### xmip-module-foundation

Only universal Module-host conventions:

```text
Module descriptor
Capability declaration
Lifecycle handshake
ABI version representation
Error representation
Buffer and ownership conventions
Host/Module negotiation
```

### xmip-configuration

TOML models, validation, configuration references, environment profiles and configuration distribution contracts.

### xmip-persistence

Durable storage contracts for Journey state, Messages, Stream references, checkpoints, deduplication, leases and Module state. Concrete stores remain separate extension repositories.

## 4. Execution repositories — create second

```text
xmip-routing
xmip-resilience
xmip-runtime
xmip-cluster
xmip-host
xmip-service
```

### xmip-routing

Owns internal Message routing:

```text
Publish
Path
Subscription evaluation
Dispatch
```

Publication is part of Routing. Routing evaluates Subscriptions and dispatches to Xmip Processes, Send Ports or Send Port Groups.

Path supports the Xmip base named/indexed model and pluggable native technologies such as XPath, JSONPath, FHIRPath, EDI/HL7 selectors and future Path technologies.

### xmip-resilience

Native Rust resilience inspired by Polly:

```text
Retry
Timeout
Circuit Breaker
Fallback
Rate Limiting
```

### xmip-runtime

Executes Journeys and Artifacts. It coordinates Modules but does not absorb their responsibilities.

### xmip-cluster

Node membership, capabilities, ownership, failover, disaster recovery coordination and inter-node execution.

### xmip-host

Host Process lifecycle, Module loading, isolation, trusted/untrusted execution and runtime hosting.

### xmip-service

The long-running Xmip System Process that starts and supervises configured Xmip Modules and Host Processes.

## 5. Operational data repositories — create third

```text
xmip-tracking
xmip-auditing
xmip-retention
xmip-archiving
xmip-observer
xmip-reporter
```

### xmip-tracking

Retains Messages, Streams or references, lineage and execution positions required to follow Journeys.

### xmip-auditing

The authoritative significant-event history. It uses Tracking to inspect Messages and Streams and to support Retry and Replay.

### xmip-retention

Evaluates time, size, count, state and hold policies. It decides when data changes lifecycle; it does not archive the data itself.

### xmip-archiving

Archives and restores historical data through pluggable targets and formats, including:

```text
CSV
JSON
XML
Avro
Parquet
SQL
File systems
Object stores
Custom providers
```

### xmip-observer

Live operational observation of Nodes, Modules, Endpoints, Journeys, pressure, latency, failures and retries.

### xmip-reporter

Historical, scheduled and exported reports based on Auditing, Tracking, Retention and Archiving.

## 6. Identity and stakeholder repositories — create fourth

```text
xmip-identification
xmip-authentication
xmip-authorization
xmip-parties
xmip-eventing
```

### xmip-identification

Establishes who or what claims an identity.

### xmip-authentication

Proves a claimed identity.

### xmip-authorization

Permits or denies actions and access to Endpoints, Journeys, Messages, Streams, Events and administration.

### xmip-parties

Represents organizations, systems and stakeholders. Parties rely on Identification, Authentication and Authorization and associate identities with Endpoints, contacts, agreements, certificates and secret references.

Developer bootstrap profile:

```text
Identities
    Developer
    Me
    Myself
    I

Parties
    Nice
        Me

    Greedy
        Myself
        I
```

Development is permissive but never bypasses Xmip security. Other environments require precise configuration.

### xmip-eventing

Outward-facing significant completion Events. It is separate from internal Routing.

Every completed Receive, Process and Send action produces a signalable Event for every outcome. The receiver is identified, authenticated and authorized, preferably through Parties. Large Streams are represented by metadata and durable references rather than copied into Events.

## 7. Administration hosts — create fifth

```text
xmip-cli
xmip-powershell
```

These are discovery and command hosts. Module-specific commands remain with their owning Modules and are contributed through stable command contracts.

## 8. Artifact ownership frozen before coding

```text
Receive Location
    receives and prepares physical Streams
    performs configured identification, authentication and authorization
    uses Transport, Content, Contract and Preparation capabilities
    feeds its parent Receive Port

Receive Port
    accepts the Stream
    creates the Message
    publishes through Routing
    starts the Journey
    may transform, but cannot assign

Xmip Process
    owns state, decisions, assignments, transformations, waits and correlation

Send Port Group
    named convenience collection of Send Ports
    dispatches a matched Message to every Send Port in the collection

Send Port
    logical delivery
    may transform, but cannot assign
    attempts ordered Send Locations until one succeeds

Send Location
    physical outbound transport
    sends Streams and may receive a response Stream
    the parent Send Port creates the response Message in the same Journey
```

Locations exchange Streams with the outside world. Ports exchange Messages with Xmip.

## 9. Endpoint model

For non-technical and operational users, these Artifacts are presented as Endpoints:

```text
Receive Port
Receive Location
Send Port Group
Send Port
Send Location
```

Artifact remains the internal architectural term. Endpoint is the public operational abstraction.

## 10. Preparation Steps

Preparation Steps replace the broad BizTalk Pipeline concept. They prepare Streams for normal handling without carrying Process decisions or assignments.

Examples:

```text
Decrypt
Decompress
Extract archive
Convert encoding
Repair known partner deviations
Compress
Encrypt
Sign
Package
Custom Preparation Step
```

## 11. Transport dependency repositories — create after foundation contracts

```text
xmip-transport-file-system
xmip-transport-ip
xmip-transport-tcp
xmip-transport-udp
```

Initial Handler repositories:

```text
xmip-handler-file
xmip-handler-http
xmip-handler-ftp
xmip-handler-ftps
xmip-handler-sftp
```

Dependency examples:

```text
HTTP -> TCP -> IP
FTP  -> TCP -> IP
UDP protocols -> UDP -> IP
FILE -> File System
```

The hierarchy is a dependency graph. Repository nesting is not required.

## 12. Content and Contract repositories — create after their Module contracts

Initial Content repositories:

```text
xmip-content-text
xmip-content-xml
xmip-content-json
xmip-content-csv
xmip-content-binary
```

Initial Contract repositories:

```text
xmip-contract-regex
xmip-contract-xml-schema
xmip-contract-json-schema
```

Later standardized Content and Contract Modules include EDI, HL7 and FHIR. Custom stakeholder repositories implement the same traits and ABIs without becoming first-party submodules.

## 13. Store repositories — create after persistence contracts

Initial store proof:

```text
xmip-store-sqlite
```

Later stores may include PostgreSQL, SQL Server, RocksDB, object storage and custom providers.

## 14. Main Xmip submodule layout

```text
modules/
    foundation/
        core
        module-foundation
        configuration
        persistence

    execution/
        routing
        resilience
        runtime
        cluster
        host
        service

    operations/
        tracking
        auditing
        retention
        archiving
        observer
        reporter

    security/
        identification
        authentication
        authorization
        parties
        eventing

    administration/
        cli
        powershell

    transport/
        file-system
        ip
        tcp
        udp

    handlers/
        file
        http
        ftp
        ftps
        sftp

    content/
        text
        xml
        json
        csv
        binary

    contracts/
        regex
        xml-schema
        json-schema

    stores/
        sqlite
```

This layout is for human navigation only. Cargo dependencies define the technical dependency graph.

## 15. Creation and implementation sequence

```text
1. Create and license foundation repositories.
2. Add foundation repositories as Xmip submodules.
3. Define shared domain primitives and Module foundation.
4. Create Routing and Resilience repositories and their ABIs.
5. Create Runtime, Host and Service around those contracts.
6. Create Tracking and Auditing before broad execution work.
7. Create Identification, Authentication, Authorization and Parties before external ingress/event delivery.
8. Create Eventing.
9. Create first Transport, Content, Contract and Store repositories.
10. Build the first end-to-end Journey across repositories.
11. Add Observer, Reporter, Retention and Archiving as retained data becomes real.
```

## 16. First executable proof across repositories

The first proof must demonstrate responsibility boundaries rather than maximum feature breadth:

```text
FILE Receive Location
    -> Receive Port creates Message
    -> Routing publishes and evaluates a Subscription
    -> Send Port
    -> FILE Send Location succeeds
    -> Receive, Routing and Send completions audited and evented
```

Failure proofs:

```text
Authentication failure before Journey creation
Contract failure before Journey creation
No Subscription -> Dead Journey
Send Location retries exhausted -> Dead Journey
Operator Retry -> same Journey
Replay -> new Journey from audited source
```

## 17. Information required from the repository owner

Architecture is sufficiently defined. Before automated repository creation, only operational choices remain:

```text
GitHub owner: IlleNilsson
Repository visibility: public or private
Default branch: main
Repository naming: lower-case xmip-...
License: MIT
Initial repository set or creation wave
Whether branch protection is applied immediately
Whether GitHub Actions is enabled from the first commit
```

Known decisions already supplied:

```text
Owner: IlleNilsson
Naming: lower-case xmip-...
License: MIT
Main integration repository: Xmip
Most first-party repositories: git submodules of Xmip
Language: Rust
Configuration: TOML
```

The remaining essential owner decision is repository visibility. If not stated, the safe creation procedure is to create repositories privately, validate the structure and make them public deliberately later.

## 18. Tool limitation and practical creation path

The current GitHub connector can update existing repositories but does not expose repository creation. Therefore one of these is required before repository creation:

1. The owner creates the empty repositories in GitHub, after which Xmip can populate them and add submodules.
2. Repository creation is performed locally with Git and GitHub's web interface.
3. A GitHub repository-creation tool or authenticated API workflow is made available.

No source code should be written into speculative local folders and mistaken for completed repositories. Repositories, remotes and submodule references are established first.

## 19. Gate before Rust coding

Repository creation is complete only when:

```text
Repository exists remotely
MIT License exists
README states responsibility and exclusions
Cargo workspace exists
Module dependencies are declared
ABI ownership is clear
CLI/PowerShell ownership is clear
Submodule is registered in Xmip where applicable
Clean clone with recursive submodules succeeds
cargo build succeeds
cargo test succeeds
```

Only then does implementation begin.

## 20. SACE gate

```text
Simplify — Is each repository responsibility coherent and non-overlapping?
Agree    — Is the repository map accepted?
Commit   — Is this blueprint and every change persisted?
Evolve   — Can boundaries be refined through implementation without losing ownership?
```
