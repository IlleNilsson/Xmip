# Xmip observability model

How Xmip records what it did, and how an operator finds out what is happening
now.

This replaces `Xmip-Audit-Architecture.md`, `audit-and-correlation.md`,
`audit-directive.md` and `Xmip-Observer-Architecture.md`.

## 1. Five things, and only one of them holds payloads

| | Answers | Holds payloads | Module |
| --- | --- | --- | --- |
| **Audit** | what happened, where, by whom, why, when, with what outcome | no | `xmip-core-audit` |
| **Logs** | what Xmip itself did — startup, configuration, hosts, threads, internal decisions | **no** | `xmip-core-observe` |
| **Traces** | where a Message went, with timing, boundaries and correlation | **no** | `xmip-core-observe` |
| **Retention** | the actual Message, its context and history | **yes** | `xmip-core-retain` |
| **Observation** | what is happening right now, and what is unhealthy | no | `xmip-core-observe` |

**Only retention stores message content**, and it is therefore controlled
separately from the other four, because it is the one that can hold personal
data, credentials in transit, medical records and commercial terms.

A correction to earlier vocabulary: `terminology.md` retired "Tracking" in
favour of Audit, which flattened a distinction worth keeping. Tracking's *job* —
holding the real Message for inspection and replay — survives as retention. Only
the word went.

## 2. Audit is cross-cutting, not a stage

Every architectural action is auditable: Receive, Prepare, Contract resolution,
validation, Path execution, Promotion, Demotion, Routing, Assignment,
Transformation, Process, Send, authentication, authorization, resilience,
persistence, observation, reporting and external Event delivery.

**Audit is not placed before or after the execution chain. It is available
throughout it.**

### Lifecycle

Every audited action follows one of two shapes:

```text
Begin -> Execute -> Finished
Begin -> Execute -> Failure
```

`Finished` and `Failure` are mutually exclusive for one execution attempt.

### Severity, which is independent of phase

```text
Information   normal execution and successful completion
Warning       recoverable, degraded or exceptional; execution may continue
Error         failure, or a condition preventing continuation
```

```text
Transform / Begin   / Information
Transform / Execute / Information
Transform / Finished/ Information

Send      / Begin   / Information
Send      / Execute / Warning
Send      / Finished/ Warning

Process   / Begin   / Information
Process   / Execute / Error
Process   / Failure / Error
```

### Policy

Every action is auditable; effective policy decides what is *recorded*.

```text
Xmip -> Cluster -> Node -> Artifact type -> Artifact -> Action -> Phase -> Severity
```

**The most specific configured policy wins; unspecified settings inherit from
the containing level.** Policy may set enabled or disabled, phase, severity,
action type, artifact type, individual artifact, node, cluster, detail level,
and sampling or throttling for high-volume Information records.

That range is the point: detailed Path-execution auditing on one development
artifact, and Error-only auditing on a high-volume production artifact, from one
model.

**Failures are always audited, and failure audit records are always persisted.**
That is not policy-configurable.

### The persistent audit directive

Configured on a Definition — typically a Receive Location:

> Audit this Receive Location, and every Message and every generation descended
> from it.

When active, audit intent is carried as **runtime metadata on the Message
itself** and applies through receive, accept, assignment, transformation,
process execution, subscription, pass-on, pickup, send, retry, failure and
leaving Xmip.

It is persistent runtime metadata. It is not a log setting, not a UI filter and
not a diagnostic flag — those all evaporate at the wrong moment, which is why
this is none of them.

Mandatory audit remains regardless. The directive adds depth to configured
flows; it cannot remove the floor.

## 3. Audit must outlive what produced it

```text
Hosts are perishable.
System Processes are perishable.
Threads and tasks are perishable.
Artifact Instances and Module Instances are perishable.
```

Therefore **durable audit persistence is the historical truth** — not host
memory, process memory, thread state or instance state. An audit record must
outlive the runtime entity that produced it, and must carry enough context to
reconstruct where, what, why, when and the outcome once that entity is gone.

Each audit event should carry, where applicable: host; System Process; thread or
task; Artifact Definition and Instance; Module Definition and Instance; Message
Contract; CorrelationId; SubCorrelationId and its parent; Message identity;
error identity; event name; purpose; node or address; **Service Identity**;
start and end time; outcome.

Failure audit must include what went wrong — **without putting payloads into
Logs or Traces.** If content must be preserved, it belongs in retention.

## 4. Correlation

**Every accepted Message receives a CorrelationId**, stable for the whole of
that Message's travel through Xmip. **No Message runtime action occurs without a
correlation footprint.**

A rejected Stream is audited but creates no owned Message, and therefore no
CorrelationId. That asymmetry is deliberate and matches ADR-0013: Accept means
Xmip takes ownership and creates a Message; Reject means it does not.

**SubCorrelationIds** form a hierarchy beneath the CorrelationId for significant
activities: receive accept, publish and subscribe, Assignment, Transformation,
Process execution, Send execution, Artifact Instance execution, Module Instance
interaction.

## 5. Performance

**Audit must not become the execution bottleneck.** Normal execution emits a
small audit envelope onto a bounded asynchronous channel; `xmip-core-audit`
batches and persists independently of the action that produced it.

When capacity is exhausted, configured policy decides whether Xmip discards
selected Information records, reduces detail, throttles or samples, blocks the
audited action, or fails it.

Warning and Error records normally require stronger delivery guarantees than
Information. Some conditions are configurable as **non-suppressible**: audit
subsystem failure, security-critical failure, configuration corruption, and
persistence failure that risks losing required evidence.

## 6. Observation

`xmip-core-observe` produces near-real-time, navigable traffic and health data
for the whole installation, navigable down the scope tree in section 7 —
installation, Cluster, Node, Host Service, and the Receive Locations, Xmip
Processes and Send Locations beneath it.

**Party and Endpoint are a second axis, not levels in that tree.** A Party is
reachable through many Endpoints on many Nodes, so it filters across the tree
rather than sitting in it, and observation is navigable both ways. This
paragraph named Parties and Endpoints as though they were containment until
2026-09-03, which put two different hierarchies in one document — see ADR-0027
clause 4.

Health is a **mood**, not a colour (ADR-0041): it names what a human gets out of
a thread, process, node or cluster — the resource under load, not the machine —
and tells an operator what to do when results are not flowing. A surface paints
it. Five **leaf** moods, worsening:

```text
Fine       results flowing, at ease
Working    handling the load
Stressed   strained — change the load
Exhausted  spent — replace the hardware
Done       blocked or failed — the pain (a cert, a password, a folder)
```

**A leaf's mood does not propagate.** In a perfect world everything is `Fine`;
the moment anything below is not, the parent is displeased and reports the rollup
mood **`Holding`** — drill in. So a parent is only ever `Fine` or `Holding`; the
leaf carries the real mood, and an operator drills down through the `Holding`
scopes to the one that is costing them. `Fine` up the tree still means every leaf
beneath is `Fine`. Every mood drills down to the evidence behind it. (The GUIs
paint Fine green, Working blue, Stressed yellow, Exhausted burnt, Done red,
Holding orange; the colour is the surface's, the mood is the model's.)

**Observation is deliberately near-real-time, not synchronous.** Receive,
Process and Send execution must never wait for it. It consumes lightweight
measurements, snapshots and persisted outcomes asynchronously — the same
reasoning as ADR-0014 clause 4 and the same reasoning as the audit channel: the
thing that watches must not be able to stop the thing it watches.

> Find the Done so it can be solved. Find the Average so it can be corrected
> before it becomes Done.

`xmip-core-report` is the historical counterpart: observation answers *what is
happening*, reporting answers *what happened over a period*.

## 7. Addressing: naming a thing across the estate

Correlation (section 4) answers *which Message*. It does not answer *which
component*, and six subsystems need that second answer: logs, traces, metrics,
retention, operations and reports all have to name the thing they are about, and
policy has to be scoped to it.

The scope hierarchy is one tree, and it is the **execution tree** the Xmip
Service already builds and validates at startup under ADR-0018:

```text
installation → cluster → node → host service → receive location
                                             │ xmip process
                                             └ send location
```

Effective policy resolves down that path, most specific winning — which is the
same resolution the audit directive already uses in section 2, stated once here
so that metrics, tracing and retention can use it too rather than each inventing
a scope of its own.

**One tree, because there was briefly more than one.** This read
`installation → cluster → node → module → action` while section 6 named Parties
and Endpoints, and below the node those are different shapes. Naming the
execution tree settles it against something that exists in code rather than
against a diagram: a Module is loaded *into* a Host Service and an action
happens *in* a Location or a Process, so neither was a level of containment in
its own right. ADR-0027 clause 4.

**The written form is an Xmip URI**, RFC 3986 compliant:

```text
xmip://[userinfo@][host][:port]/path?query#fragment
```

with two defaults that make the common case short:

- **Omitted userinfo** means the caller's identity.
- **Omitted host** means estate-wide rather than a particular node.

So `xmip:///transport/ftp?phase=receive` addresses the FTP transport across
every node, as whoever is asking.

Two things this is not. It is **not a transport** — nothing is sent to an
`xmip://` address, and it does not compete with the gRPC inter-cluster protocol.
And it is **not a replacement for trace context**: a Trace carries standard
correlation identifiers, and the URI names the component the span belongs to.
They answer different halves of the same question.

Recovered from the `_origins` design export, 2026-08-26, where it was the only
addressing model Xmip had written down anywhere.

## 8. Reports

`xmip-core-report` answers *what happened over a period*. Four reports, and the
split between mandatory and optional is the point:

**Mandatory:**

| Report | Answers |
| --- | --- |
| Firewall and Operations | every TCP and UDP port, every UNC path a file-based Location touches, and every protocol exposed — inbound and outbound |
| Identity and Isolation Compliance | every identity context, its class, where it runs, and every isolation rule evaluated with its result |

**Optional:** Performance and Capacity, and Artifact End-to-End Drill-Down.

The two mandatory reports are mandatory because of who needs them and when. A
security review board asks for the firewall report before Xmip is permitted onto
a network, and an auditor asks for the compliance report after something has
gone wrong. Neither population knows to ask for a report by name, and a report
that must be requested before it exists is a report nobody has.

**Both are derived, never authored.** The firewall report is computable from the
Receive and Send Locations plus their transport configuration; the compliance
report is computable from identity contexts and the ADR-0022 isolation rules.
A hand-written network document describes what someone believed the estate did
when they wrote it, which is the failure mode this replaces.

Recovered from the `_origins` design export, 2026-08-26.

## 9. Ownership

`xmip-core-audit` owns the audit record model, lifecycle phases, severity,
policy definition and resolution, envelopes, buffering and back-pressure,
persistence contracts, and query contracts.

**Every other Module reports its action lifecycle and outcome through the
`xmip-core-audit` public contract.** No Module invents its own audit model or
its own audit persistence — the moment two exist, no query can answer a question
that spans both.

## 10. The invariant

> Every Xmip action is auditable. What is recorded is determined by the
> effective policy, from Xmip scope down to the individual action, lifecycle
> phase and severity. Failures are always recorded.

Xmip audit must be able to reconstruct what happened, where, by whom, why,
whether it succeeded, and what went wrong when it did not — which is what
banking, aviation, energy, government and defence require before they will run
anything at all.
