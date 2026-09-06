# ADR-0018: The Xmip Service and the Xmip Host Services

- Status: Accepted, with open questions recorded at the end
- Date: 2026-08-25
- Related: ADR-0012 (module boundary), ADR-0014 (operator surfaces), ADR-0024 (a claim at the endpoint)
- Read by: ADR-0027 clause 4, which makes the execution tree this record builds
  the one scope tree everything observable is addressed against

## In brief

- Theme: What Xmip is at runtime
- Subject: One Service per node, and it stays out of the message path
- Name: The Service and the Host Services
- Order: 5
- Concepts: Host Service; Service, the Xmip Service

The Xmip Service is the master and the only thing the operating system starts.
It reads the node configuration, builds and validates the execution tree, then
supervises the Xmip Host Services. **No Stream, Message or Journey passes
through it.** It loads no Modules and executes no Extensions.

## Context

`terminology.md` defined System Process, Host Process, Xmip Process and Xmip
Subprocess. It never defined **Xmip Service**, which is the term carrying the
whole runtime model — used twice in passing and specified nowhere. Two people
reading the same documents disagreed about which way the containment ran, and
the code implemented one reading while the manifest descriptions implied the
other.

BizTalk is the reference and the warning. Its Host Instances are Windows
services, which is right: they are long-running, the operator starts and stops
them, and the service manager supervises them. They were all called
`BTSNTSvc.exe` and named `BTSSvc$BizTalkServerApplication`, which told an
operator nothing about which one was doing FTP and which was running
orchestrations. Diagnosis required opening the Administration Console.

## Decision

**1. The Xmip Service is the master. One per node.** The operating system
starts it and nothing else. It reads the node's configuration, builds and
validates the execution tree, then registers, starts and supervises the Xmip
Host Services.

**2. The Xmip Service is never in the message path.** No Stream, no Message, no
Journey passes through it. It loads no Modules and executes no Extensions. Same
principle as ADR-0014 clause 4 holds for observation, and for the same reason.

**3. An Xmip Host Service is a long-running service, not a child process.**
Registered with the service manager, started and stopped by name, supervised by
the operating system. Many per node. Each hosts its configured Modules and does
the work: Receive Locations, Xmip Processes, Send Locations. Each holds
the claim on what it is working on, per ADR-0024 — taken at the endpoint rather
than from a lease store inside Xmip.

**4. Startup is nine phases, split between the two.**

Xmip Service:

```
1  read-configuration      the node's configuration, whole
2  build-execution-tree    what this node is supposed to be
3  validate-startup        fail here, before anything is registered or started
4  plan-host-services      which Host Services, with what character and Modules
5  start-host-services     register what is missing, start in configured order
```

Xmip Host Service, each within itself:

```
6  load-modules            its own Modules, ABI-verified per ADR-0012
7  register-capabilities   into its capability registry
8  verify-extensions       verified, not loaded
9  accept-work             Receive Locations poll, Send Locations ready,
                           Xmip Processes runnable
```

Phase 3 is the gate. The master proves the whole node's configuration coherent
before registering or starting anything, so a bad configuration fails as one
clear error rather than as four half-started services.

**5. Losing the master must not stop the node.** The Xmip Service is a
supervisor, not a participant. When it dies, Host Services keep receiving,
processing and sending, and keep their claims — which are held at the endpoint
and owe the master nothing. What is lost is supervision and reconfiguration, not
work.

**6. The master re-attaches; it does not re-spawn.** On restart it enumerates
the services it registered, adopts those already running, and starts only what
is missing. Because Host Services are registered services rather than child
processes, the service manager already holds this state and Xmip does not need
to keep its own record of what it started.

**7. The service name is composed from configuration, and Xmip guarantees it is
legal.**

```toml
[default.host]
serviceNamePattern   = "xmip-host-{host}"
serviceNameSanitiser = "[^a-z0-9-]"
```

Variables: `{host}` `{cluster}` `{node}` `{id}` `{trust}` `{bitness}`
`{latency}` `{index}`. The template composes, the sanitiser regex replaces what
is not legal, and a validator that Xmip owns — not the operator — checks the
result against the platform's rules. An operator who could configure the
validator could configure a name that registers on Windows and fails on Linux,
and find out in production.

**8. An unnamed host falls back to its identifier, which lives in
configuration.** A GUID minted at spawn time changes on every restart and
traces to nothing. A GUID assigned when the host is declared is stable and
matches back by construction:

```toml
[host.orders]
id = "3f2a9c14-8d51-4b0e-a6f7-1c2d3e4f5a6b"
description = "Order intake and EDI translation"
```

**9. The description always carries the readable identity.** Whatever the
service is called, the description names the host and says what it does, so a
service list stays diagnosable even when the name is a GUID:

```
xmip-host-orders    Xmip Host Service 'orders' — Order intake and EDI
                    translation, 12 Modules, trusted, 64-bit
```

Where the operator has written a description, that is used. Where nobody has,
one is generated: module count, character, and which of Receive, Process and
Send this host actually does. Three facts an operator can act on, rather than a
list of forty Modules nobody will read.

**10. Every Host Service runs the same executable, so the command line carries
the host.** `xmip host --host orders` (one executable with a `host` subcommand,
as `registration.rs` invokes it — not a separate `xmip-host` binary). Otherwise
`ps` and Task Manager show identical entries and the BizTalk complaint returns
intact.

**10a. Latency is bought with isolation, and the currency is process hops.** A
Journey whose receive, process and send all run in one Host Service crosses no
process boundary. Split across three Host Services it pays serialisation, a
copy and a context switch at every hop, and it is no longer low latency
whatever anybody labels it.

So there is no `low_latency` flag on a Host Service and no `low_latency_capable`
on a Module. Neither was ever a property of the thing it was attached to. What
exists instead is the role combination already in
`runtime-roles-and-isolation.md`: a host configured as Reader, Executor *and*
Writer runs a whole Journey without a hop, and a host configured as Reader only
cannot.

The trade is real and belongs to the operator, not to a boolean. One Host
Service doing everything is the fastest and shares a process between an
untrusted transport and the routing it feeds. Three Host Services isolate that
and cost three hops. Which is right depends on the workload, which is why
BizTalk separated hosts by workload in the first place.

**11. Supervision is `xmip-core-resilience`, by configuration.** Restarting a
dead Host Service is retry with backoff. Giving up and reporting the node
degraded is a circuit breaker. Waiting for drain is a timeout. Not restarting
six at once is a bulkhead. A Host Service that will not start at all is a
fallback. No new concept: the primitives already exist, applied to services
instead of to messages.

**12. Shutdown drains.**

```
drain      the master tells Host Services to stop accepting new work
finish     in-flight Journeys complete or checkpoint
release    claims released at the endpoint explicitly, not left to expire
exit       Host Services stop, the master stops last
```

**13. Configuration that no longer names a Host Service is reconciled.** A host
renamed or removed leaves a registered service behind. The master drains and
deregisters services it registered that configuration no longer names,
otherwise the service list accumulates ghosts and an operator cannot tell a
live host from a dead one.

## Consequences

- `xmip-core-service` and `xmip-core-host` are not separate repositories. Both
  are modules inside `xmip-core-runtime`, which already owns `ExecutionTree`,
  `StartupValidationReport`, `HostProcessPlan` and `HostBitness`. Ten kilobytes
  that always change together do not need three repositories, three CI
  pipelines and three submodule mounts.
- `xmip-core-runtime` depends on `xmip-core-configure` and
  `xmip-core-resilience`. Platform on Platform, still acyclic.
- The crate layering `xmip-service → xmip-host → xmip-runtime` is correct and
  survives the fold as module layering inside one crate.
- `terminology.md` gains **Xmip Service** and **Xmip Host Service**, and
  **Host Process** is narrowed to the System Process a Host Service runs as.

## Open

**Registration needs elevation.** Creating a Windows service requires
administrator; writing a systemd unit and reloading requires root. Proposed,
not yet accepted: the master runs elevated and the Host Services run under
configured least-privilege accounts. The master is small, loads no Modules and
is not in the message path; all untrusted code is in the children. That is how
IIS, systemd and SQL Server are arranged. The alternative is a small privileged
helper, which is safer on paper and one more thing to install and get wrong.

**An operator stopping a Host Service.** Proposed, not yet accepted: respect
it and report the divergence rather than restarting. If the master overrides a
deliberate stop, nobody can take a host out of service to investigate, which is
a daily operational need. BizTalk leaves it alone.

**What the spawn plan depends on beyond the node's own configuration.** Cluster
membership, node role, capability and load may all bear on which Host Services
a given node should run. Deferred deliberately: the node-local case is settled
and sufficient to build against, and the cluster-wide case needs its own
decision rather than an assumption made here.

## Amendment, 2026-09-06: phases 4-5 renamed to host-services

The startup phases 4 and 5 were named `plan-system-processes` /
`start-system-processes`, and the code mirrored them
(`StartupPhase::PlanSystemProcesses`, `XmipServiceState::ReadyToStartSystemProcesses`).
That carried the exact "Process" overload the owner flagged: terminology.md is
explicit that a Host Service is **not** a System Process (a Host Process is the
operating-system process a Host Service runs as). ADR-0035 settled that
terminology.md arbitrates such a collision, so the phases are renamed to
`plan-host-services` / `start-host-services` — they plan and start **Host
Services**, which is what phase 3's tree already validated. The state and phase
enums in `service.rs` were renamed to match. No behaviour changed; the names now
say what the phases do.
