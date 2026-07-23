# Xmip Roadmap

The roadmap is architecture-led. Ordering may change when requirements or dependency boundaries change.

## 1. Architecture baseline

- Stabilize the repository classification and dependency model.
- Keep the architecture specification and manifest synchronized.
- Define versioning and compatibility rules for artifacts, contracts and runtime components.
- Complete C4 views for system context, containers, components and deployment.

## 2. Foundation contracts

- Core identifiers and shared types.
- Immutable Stream and Message models.
- Message Context and creation metadata.
- Journey lineage and descendant relationships.
- Node, cluster, party and event models.

## 3. Common capabilities

- Contract implication, evaluation and validation.
- Path expressions.
- Stream preparation.
- Transformation, assignment, promotion and demotion.
- Identification, authentication and authorization.
- Receive, route, process and send behaviour.

## 4. Runtime platform

- Rust core engine.
- gRPC internal execution contracts.
- Local IPC and inter-node HTTP/2 communication.
- Durable execution state and disaster recovery.
- Scheduling, priorities, overload handling and capability-aware failover.
- Resilience and scoped exclusiveness services.

## 5. Handler ecosystem

- Transport handlers.
- Content handlers.
- Logic handlers for method-oriented protocols.
- Approved extension hosts for .NET, Java, Python, C/C++, Rust and Go.
- PowerShell and Bash scripting support.

## 6. Operations

- Audit and tracing.
- Near-real-time observation.
- Tracking, reporting, retention and archive.
- Deployment, configuration slicing and air-gapped operation.
- Cross-platform CLI and operator tooling.

## 7. Verification and releases

- Contract and conformance tests.
- Failure, recovery and deduplication tests.
- Performance and overload tests.
- Security review.
- Versioned architecture and runtime releases.

## Current tooling priority

`Xmip-Git` is being expanded as the multi-repository control surface. Status reporting is established. Later operations may include checkout, synchronization, merge, tagging, fetching, cleaning and repository filtering, each added through a separate reviewed change.