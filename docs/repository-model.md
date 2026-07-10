# Xmip repository model

The `Xmip` repository is the integration point and current source of truth.

All previous experimental repositories have been removed. New repositories will be created deliberately, one purpose at a time, and may be referenced by `Xmip` as git submodules.

A repository is created only when it has:

- one clear responsibility,
- a stable public contract,
- an independent build and release lifecycle,
- a reason to be versioned separately.

## Planned platform repositories

```text
xmip-core
    Journey, Message, Stream, Event and shared domain contracts.

xmip-abi
    Stable binary boundary for dynamically loaded Modules.

xmip-service
    Long-running Xmip Service System Process.

xmip-host
    Host Process startup, isolation, module loading and execution.

xmip-runtime
    Scheduling, dispatch, Publications, Subscriptions, routing and Xmip Process execution.

xmip-cluster
    Cluster membership, node capability awareness, failover, recovery ownership and leases.

xmip-configuration
    TOML parsing, validation, environment profiles and deployment configuration.

xmip-persistence
    Durable Journey state, checkpoints, deduplication and storage contracts.

xmip-tracking
    Retained Messages, Streams, lineage, execution history and replay source data.

xmip-auditing
    Authoritative audit history, inspection and replay using Tracking.

xmip-cli
    Command-line administration and operational tooling.
```

Auditing and Tracking are separate. Auditing depends on Tracking for retained Messages, Streams and execution history.

## Planned module repository families

### Transport Handlers

Transport Handlers move Streams and deal with transport-specific ingress, egress, errors and responses.

Examples:

```text
xmip-handler-file
xmip-handler-ftp
xmip-handler-sftp
xmip-handler-http
xmip-handler-grpc
xmip-handler-mllp
xmip-handler-websocket
xmip-handler-rabbitmq
xmip-handler-ibm-mq
xmip-handler-azure-service-bus
xmip-handler-azure-event-grid
```

Lower-level technologies such as TCP and UDP are dependencies and reusable capabilities. They become separate repositories only if they acquire a stable reusable Xmip-specific purpose.

### Content Handlers

Content Handlers understand Message representations and bridge immutable Streams and immutable Messages.

```text
xmip-content-xml
xmip-content-json
xmip-content-csv
xmip-content-edi
xmip-content-hl7
xmip-content-fhir
xmip-content-text
xmip-content-binary
```

### Contract Modules

Contracts validate Message instances and provide paths, selectors, promotion and demotion knowledge.

Standard implementations may include:

```text
xmip-contract-xml-schema
xmip-contract-json-schema
xmip-contract-regex
xmip-contract-edi
xmip-contract-hl7
xmip-contract-fhir
```

Stakeholders may create project-specific Contract Modules such as:

```text
acme-contract-purchase-order
hospital-contract-admission
municipality-contract-citizen-case
```

A custom Contract may derive from a standard Contract or another custom Contract. Derivation belongs to the contract technology and its design/build process, not to runtime TOML.

### Stores

Stores implement persistence contracts.

```text
xmip-store-sqlite
xmip-store-postgresql
xmip-store-sqlserver
xmip-store-rocksdb
```

### Extensions

Stakeholder or partner Extensions may implement custom actions, authentication, authorization, secret providers, certificate providers, business rules and Process activities.

## Dependency model

The technology tree is a dependency graph, not a forced Git directory hierarchy.

```text
HTTP depends on TCP
MLLP depends on TCP
SOAP request/response logic uses HTTP
FHIR instances may be carried through HTTP, FILE or another transport
JSON instances may be carried through HTTP, FILE, FTP, MQ or another transport
```

Transport, content and Contract remain independent and are composed by configuration.

## Submodule policy

`Xmip` may reference focused repositories as submodules after those repositories exist and contain a valid initial commit.

Suggested integration layout:

```text
submodules/
    platform/
    handlers/
    content/
    contracts/
    stores/
    extensions/
```

This folder layout organizes the integration checkout. It does not define runtime dependency or technology inheritance.

Submodules must use real repository URLs and must be added only after repository creation has been verified with `git ls-remote`.

## Clean-slate sequence

1. Keep all architecture and prototype work in `Xmip`.
2. Stabilize the public purpose and contract of the first component.
3. Create its repository with an initial commit.
4. Move or rebuild that component in the new repository.
5. Build and test it independently.
6. Add it to `Xmip` as a submodule.
7. Repeat one component at a time.

The first candidate should be `xmip-core`, because every other platform and module repository depends on its shared domain contracts.
