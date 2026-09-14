# Xmip Roadmap

The roadmap is architecture-led. Ordering may change when requirements or dependency boundaries change.

## 1. Architecture baseline

- Stabilize the repository classification and dependency model.
- Reconcile Contract, representation, Path, Transport and Logic repository boundaries.
- Replace direction-specific transport repositories with direction-neutral `xmip-core-transport-<standard>` technologies.
- Keep the architecture models in `doc/architecture/` and the manifest synchronized.
- Define versioning and compatibility rules for Definitions, Contracts and runtime components.
- Complete C4 views for system context, containers, components and deployment.

## 2. Foundation contracts

- Core identifiers and shared types.
- Immutable Stream and Message models.
- Message Context and creation metadata.
- Journey lineage and descendant relationships.
- Node, cluster, party and event models.

## 3. Common capabilities

- Contract implication, evaluation and validation.
- JSON and XML vertical slices across representation, Path and Contract.
- Direction-neutral transport contracts used by Receive and Send orchestration.
- Path expressions.
- Stream preparation.
- Transformation, assignment, promotion and demotion.
- Identification, authentication and authorization.
- Receive, route, process and send behavior.

## 4. Runtime platform

- Rust core engine.
- gRPC internal execution contracts.
- Local IPC and inter-node HTTP/2 communication.
- Durable execution state and disaster recovery.
- Scheduling, priorities, overload handling and capability-aware failover.
- Resilience, and artifact claims at the endpoint (ADR-0024).

## 5. Technologies

- Transport technologies, each shipping its Transport Handler.
- Message technologies, each shipping its Content Handler.
- Logic technologies for method-oriented protocols.
- Approved Extension hosts for .NET, Java, Python, C/C++, Rust and Go.
- PowerShell and Bash scripting support.

## 6. Operations

- Audit and tracing.
- Near-real-time observation.
- Reporting, retention and archive.
- Deployment, configuration slicing and air-gapped operation.
- Cross-platform CLI and operator tooling.

## 7. Verification and releases

- Contract and conformance tests.
- Failure, recovery and deduplication tests.
- Performance and overload tests.
- Security review.
- Versioned architecture and runtime releases.

## Current tooling priority

The estate module (`Xmip/Xmip.psd1`) is the multi-repository control surface: `Sync-XmipEstate` reconciles the estate with the manifest, `Sync-XmipRepository` owns the working copies, `Get-XmipStatus` reports the whole estate at once and `Publish-XmipChange` lands a change in dependency order. Later operations may include checkout, synchronization, merge, tagging, fetching, cleaning and repository filtering, each added through a separate reviewed change.
