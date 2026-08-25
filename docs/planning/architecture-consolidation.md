# docs/architecture consolidation

Working notes. Not authoritative. Delete when the consolidation is done.

`docs/architecture/` holds 31 documents. ADR-0020 says one document per
subject, and the README lists six. This records what is in the other 25, so
nothing is deleted without someone having read it.

The headline: **they are not superseded.** Roughly a third of their content is
live design that never reached the six, including two whole subjects — the
Definition/Instance model and the Process model — that the six do not cover at
all.

## 1. Fully superseded — safe to delete

Content verified present in a surviving document.

| Document | Lines | Superseded by |
| --- | --- | --- |
| `message-disposition.md` | 19 | `runtime-model.md` §9. The DMQ metadata list is near-verbatim. |
| `definition-instance-namespace.md` | 20 | Strict subset of `definition-instance-model.md`. |
| `process-and-transform-assignment-rules.md` | 43 | `runtime-model.md` §10. Same Transform/Assign rules. Its "same interchangeId" is retired vocabulary, resolved in §21 conflict 5. |
| `publication-subscription-runtime.md` | 67 | `artifact-model.md` and `foundations.md` say the same thing; whatever survives them covers this. |
| `handler-specification-map.md` | 62 | Names only. **But keep the RFC anchors** — see section 3. |
| `handler-taxonomy.md` | 71 | `repository-model.md` §5. Uses pre-ADR-0011 names. **One fact to rescue** — see section 4. |

## 2. Live subjects the six documents do not contain

These are gaps, not duplicates.

### Definition and Instance

`artifact-model.md`, `foundations.md`, `definition-instance-model.md`.

Every configurable Xmip object exists twice: a **Definition** in TOML
describing configured intent, and an **Instance** created at runtime when the
kernel binds the definition to loaded module code satisfying the required
contracts.

```text
Artifact Definition + Module Instance + Validated Contracts + Runtime Context
    = Artifact Instance
```

`runtime-model.md` §20 says "Artifacts are configured objects that compose
Modules" and never distinguishes the configured object from the running one.
That distinction is load-bearing for lifecycle, audit and hot reconfiguration,
and it is currently written down nowhere the README points at.

Related and also missing:

- **Artifact identity survives implementation change.** `OrdersInbound` stays
  the same artifact when it moves from `receive-http` to `receive-mqtt`.
  Lineage, audit and deployment history must not anchor to the transport.
- **Module Definition and Module Instance** — the same Module Definition
  yields many Module Instances across nodes, processes and isolation
  boundaries. Belongs in `module-model.md`.
- **The 11-step startup flow**, from loading kernel configuration to starting
  eligible receive entry points.
- **Kernel-to-kernel is Protocol Buffers over gRPC**, and is a different
  boundary from kernel-to-module. Absent from all six.

### The Process model

`xmip-process.md`, `business-process-runtime.md`.

`runtime-model.md` mentions "Xmip Process" in passing and never models it.
Missing entirely:

- Process Definition fields; Process Instance capabilities.
- **Process State belongs to cluster persistence.** Execution ownership may
  move between nodes; the state does not move, because it already belongs to
  the cluster. A Process Instance must not use thread, host process or node
  memory as its source of truth.
- **Process Stage** — named phases, explicitly non-linear.
- **Process Outcome** — `Completed`, `CompletedWithWarnings`, `Failed`,
  `Cancelled`, `TimedOut`, `Abandoned`. Note this is a *third* state
  vocabulary alongside `JourneyState` and the retired v1.0 set.
- **ExecutionScope** — `None`, `Transactional`, `BusinessProcess`. Applies to
  both process and pub/sub execution. Appears in no ADR.
- **A Subscription decides when work starts. A Correlation Rule decides when
  waiting work resumes.** One sentence, and it is the whole of long-running
  correlation.

### Validation gates

`message-contracts-and-validation.md`, `message-runtime-context.md`.

`runtime-model.md` §5 has one `Validation` step in the gate sequence. These
documents say validation happens at seven message-boundary passages: receive/
stream, deserialize, transform, process input, process output, pre-
serialization, and optional outgoing representation.

Two sharp rules worth keeping verbatim:

- **Structured validation must happen before serialization.** After
  serialization Xmip can perform representation checks only — content type,
  encoding, destination metadata, send identity — not structured validation.
- Promotion and Publication are **not** validation gates.

Also missing: the audit event field list (`CorrelationId`, `SubCorrelationId`,
`EventName`, `Purpose`, `Node`, `Address`, `ServiceIdentity`, `StartTime`,
`EndTime`, `Outcome`), and the rule that no runtime action occurs without a
correlation footprint.

### Communication layering

`communication-layering.md`, `protocol-landscape.md`,
`industrial-iot-handler-lineage.md`.

```text
Communication Medium -> Transport -> Protocol -> Interaction Pattern -> Capability
```

Not every technology uses every layer, and **not every technology is
IP-based**. CANBUS is not below TCP or UDP; it is a transport under the CAN
Network medium. `repository-model.md` §4 currently states flat dependencies
("HTTP depends on TCP, MLLP depends on TCP") which is right for IP and says
nothing about the media where that chain does not apply.

The kernel holds explicit metadata for all five layers and must not assume one
hierarchy.

### Handler lineage

`handler-lineage.md`, `tcp-handler-lineage.md`, `queue-handler-lineage.md`,
`industrial-iot-handler-lineage.md`.

Four documents stating one rule four times: a family shares behaviour, the
module manifest declares `family`, `base component id`, `derived-from` and
`supported technologies`, and the kernel applies platform rules — loadability,
compatibility, trust, isolation, ownership, audit, configuration binding —
without understanding technology internals.

What is worth keeping is the per-family concept lists, which are real design
knowledge:

| Family | Shared concepts |
| --- | --- |
| TCP | connection management, session, request/response, streaming, framing, timeout, keepalive, pooling, TLS |
| Queue | queue/topic/subject/stream/partition identity, consumer group, durable subscription, acknowledgement, visibility timeout, offset, cursor, dead-letter, competing consumers, ordering |
| Industrial/IoT | UDP has no ordered reliable delivery; a handler needing reliability, ordering, de-duplication, acknowledgement, replay or persistence must declare and implement it |

Collapses to one section of `module-model.md`.

### Source layout

`feature-folder-convention.md`, `rust-runtime-guidelines.md`.

Organise by deployable capability, not technical layer. The same shape repeats
at repository, module and feature level:

```text
feature/
├── contracts/  runtime/  configuration/  preservation/  observability/  tests/
```

Plus the Rust rules: immutability, ownership handoff between stages, channels
preferred, `Result` not panic, traits at handler boundaries, no unsafe in core
runtime. Belongs in `repository-model.md` and `module-model.md`.

## 3. Belongs in another repository

| Document | Destination |
| --- | --- |
| `module-abi-specification.md` (471 lines) | `xmip-core-abi`, with `include/xmip_module.h` |
| RFC anchors from `handler-specification-map.md` | `identity-by-technology.md` — RFC 9293 (TCP), RFC 9110 (HTTP), RFC 6455 (WebSocket) |

## 4. Conflicts requiring a ruling

Found by reading, not invented. Each is two accepted-looking documents saying
incompatible things. **None may be merged silently.**

**C1. Is "Artifact" a legal umbrella term?**
`artifact-model.md` mandates `ArtifactDefinition` / `ArtifactInstance` and an
AD/AI/MD/MI acronym convention. `definition-instance-model.md` explicitly
forbids it — *"Xmip shall not use a generic parent term such as Artifact"*,
*"Avoid: ArtifactDefinition"* — and requires `ReceivePortDefinition`,
`ProcessDefinition`. `runtime-model.md` §20 uses "Artifacts" as the umbrella,
siding with the first while carrying none of the model.

**C2. Send retry: retry-then-failover, or failover-then-retry-all?**
`runtime-model.md` §10: *"Retries apply to the active Send Location; failover
moves to another per Send Port policy."*
`xmip-send.md`: any error moves immediately to the next Send Location; when
all have failed, the Send Port retries **the whole ordered list**, and each
retry pass repeats every location.
These produce different attempt counts, different latency and different
failure audit. Both are defensible; they are not the same design.

**C3. Is SFTP in the FTP family?**
`handler-taxonomy.md`: *"FTP includes FTP and FTPS modes. SFTP remains a
separate SSH-based transport."*
`handler-lineage.md` and `protocol-landscape.md`: SFTP is derived from FTP.
The taxonomy is technically correct — SFTP is SSH File Transfer Protocol and
shares nothing with FTP but a purpose — so this is likely a defect in the
other two rather than a genuine disagreement.

**C4. One Publication, or many per Message?**
`runtime-model.md` §9: a Publication is *"one event, one identity,
immutable"*, and a Journey is a line, not a tree.
`message-runtime-context.md` and `publication-subscription-runtime.md`: a
Message may be published repeatedly with progressively richer context, and
each publication re-evaluates subscriptions, recursively.
Possibly compatible — re-publication may create a new Publication — but the
six documents never say so, and "Subscription Instances form a chain like a
call stack" implies an accumulating structure that "a line, not a tree" reads
as excluding.

**C5. Process Outcome versus JourneyState.**
`JourneyState` is `Active, Waiting, Suspended, Recovering, Completed, Failed`.
`Xmip.Process.Outcome` is `Completed, CompletedWithWarnings, Failed,
Cancelled, TimedOut, Abandoned`. Two enums, overlapping names, no stated
relationship. Compare the still-open `Dismissed` question in §21.

**C6. Is Node.js a target module technology?**
`artifact-model.md` and `foundations.md`: explicitly not.
`feature-folder-convention.md` lists it among supported languages.
Minor, and almost certainly an oversight in the third.

## 5. Rulings taken

| | Ruling | Recorded in |
| --- | --- | --- |
| C1 | Artifact is a collective noun in prose; code, TOML and logs use the concrete concept | `runtime-model.md` §21, §23.6 |
| C2 | Retry the Send Location, then fail over | `runtime-model.md` §23.7 |
| C4 | A re-publication is a new Publication | `runtime-model.md` §23.8 |
| C5 | Open — decide with the Process model, in ADR-0013 beside `Dismissed` | `runtime-model.md` §22, §23.9 |
| C3 | Defect: SFTP is not in the FTP family. FTPS is | `runtime-model.md` §23.10, `module-model.md` §7 |
| C6 | Defect: Node.js is not a target module technology | `runtime-model.md` §23.11, `module-model.md` §1 |

## 6. Where the content went

| Absorbed from | Into |
| --- | --- |
| `artifact-model.md`, `foundations.md`, `definition-instance-model.md`, `definition-instance-namespace.md` | `runtime-model.md` §21 (Definition and Instance, identity, startup); `module-model.md` §1 (Module Definition/Instance, module technologies) |
| `xmip-process.md`, `business-process-runtime.md` | `runtime-model.md` §22 (the Xmip Process, cluster state, stages, correlation, ExecutionScope, outcome) |
| `message-contracts-and-validation.md`, `message-runtime-context.md` | `runtime-model.md` §20 (validation gates, the pre-serialization rule, audit fields) |
| `communication-layering.md`, `protocol-landscape.md` (taxonomy only) | `module-model.md` §6 (five-layer metadata, non-IP media) |
| `handler-lineage.md`, `tcp-handler-lineage.md`, `queue-handler-lineage.md`, `industrial-iot-handler-lineage.md`, `handler-taxonomy.md` | `module-model.md` §7 (lineage metadata, family concept tables, UDP reliability, the runtime learns none of it) |
| `rust-runtime-guidelines.md` | `module-model.md` §12 |
| `feature-folder-convention.md` | `repository-model.md` §9 |
| `handler-specification-map.md` | `identity-by-technology.md` §6 |
| `message-disposition.md`, `process-and-transform-assignment-rules.md`, `publication-subscription-runtime.md`, `platform-lineage.md`, `xmip-send.md`, `xmip-subscription.md` | already present in `runtime-model.md` §9, §10, §22 |

## 7. Safe to delete

All content verified present in a surviving document. 23 files.

```text
docs/architecture/artifact-model.md
docs/architecture/business-process-runtime.md
docs/architecture/communication-layering.md
docs/architecture/definition-instance-model.md
docs/architecture/definition-instance-namespace.md
docs/architecture/feature-folder-convention.md
docs/architecture/foundations.md
docs/architecture/handler-lineage.md
docs/architecture/handler-specification-map.md
docs/architecture/handler-taxonomy.md
docs/architecture/industrial-iot-handler-lineage.md
docs/architecture/message-contracts-and-validation.md
docs/architecture/message-disposition.md
docs/architecture/message-runtime-context.md
docs/architecture/platform-lineage.md
docs/architecture/process-and-transform-assignment-rules.md
docs/architecture/publication-subscription-runtime.md
docs/architecture/queue-handler-lineage.md
docs/architecture/rust-runtime-guidelines.md
docs/architecture/tcp-handler-lineage.md
docs/architecture/xmip-process.md
docs/architecture/xmip-send.md
docs/architecture/xmip-subscription.md
```

## 8. Held back

**`docs/architecture/protocol-landscape.md` — do not delete yet.**

Its taxonomy is absorbed. Its *catalogue* is not, because 21 protocols it
names are absent from `architecture.toml`, and deleting the document would
delete the only record that they were ever intended:

| Genuinely missing repositories | |
| --- | --- |
| Healthcare | DICOM |
| Industrial | Profinet, EtherNet/IP, BACnet, DDS |
| Wireless / IoT | Bluetooth, Zigbee, Thread, Matter, LoRaWAN, CoAP |
| Discovery | mDNS, SSDP, DHCP |

| Probably not separate repositories | Because |
| --- | --- |
| J1939, OBD-II, CANopen | protocols carried *on* `xmip-core-transport-can-bus`, not transports themselves |
| NATS JetStream | a mode of `xmip-core-transport-nats` |
| Redpanda | speaks the Kafka protocol; `xmip-core-transport-kafka` covers it |
| TRADACOMS, Peppol | EDI standards — message or contract concerns, not transports |

Same shape as the AS2/AS4 gap found earlier: sorting a document against the
manifest is what exposes what the manifest forgot.

**`docs/architecture/module-abi-specification.md` — moves, does not delete.**
To `xmip-core-abi`, with `include/xmip_module.h`. It is the normative
contract; `module-model.md` is the model of it.

## 9. Also superseded, outside docs/

Found alongside. Confirmed replaced by `Xmip/` and the current tooling.

```text
install/install-local.ps1        install/install-local.sh
runtime/main/README.md           tools/Initialize-XmipHandlerCrates.ps1
scripts/create-canary-manifest.ps1
scripts/architecture/README.md
scripts/architecture/Modules/Xmip.Manifest.psm1
scripts/architecture/Modules/Xmip.Reporting.psm1
scripts/architecture/Tests/Xmip.Manifest.Tests.ps1
scripts/git/Add-XmipCommonNestedSubmodules.ps1
scripts/git/Add-XmipNestedSubmoduleFamilies.ps1
scripts/git/Add-XmipSubmodules-CoreNetwork.ps1
scripts/git/Add-XmipSubmodules-DataStorageEnterprise.ps1
scripts/git/Add-XmipSubmodules-IndustrialEnergy.ps1
scripts/git/Add-XmipSubmodules-QueueBusinessHealthcare.ps1
scripts/git/New-XmipFamilyRepositories.ps1
scripts/github/Ensure-XmipHandlerRepositories.ps1
```
