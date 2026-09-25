# ADR-0062: Every Xmip tool audits, and the operating system's log catches what audit cannot

- Status: Accepted
- Accepted: 2026-09-25, the owner, in the words quoted below
- Date: 2026-09-25
- Related: ADR-0014 (operator surfaces; its security clause already audits
  every remote invocation through `xmip-core-audit`), ADR-0027 (the operator
  boundary, whose sections 7 and 8 are how a .NET surface calls a rule the
  runtime owns), ADR-0052 (the surfaces share one model), ADR-0053 (the
  processes Xmip owns and their names), ADR-0059 (a test suite carries its
  provider), `doc/architecture/observability-model.md`,
  `module/core/operation/audit/doc/audit-record.md`

## In brief

- Theme: What Xmip is at runtime
- Subject: Which Xmip programs audit, through what, and where a record goes
  when audit itself fails
- Name: Every Xmip tool audits
- Order: 14
- Concepts: audit; audit sink; the operating system's log; Xmip tool

**Every Xmip program records what it does and every failure through
`xmip-core-audit` — the runtime and its node, the web and desktop monitors,
the command line, both PowerShell modules, the Playground's roll, cluster and
node processes, the language server and the estate's own tooling — not the
runtime alone. The record is written once, in the audit capability; a .NET
program and PowerShell reach it through the runtime's library, as they reach
every other rule (ADR-0052, ADR-0027). When audit cannot persist a record,
the record goes to the operating system's log instead: the Windows Event
Log, the systemd journal or syslog on Linux, the unified log on macOS.
Nothing an Xmip program does fails silently.**

## Context

On 2026-09-25 the web monitor showed *An unhandled error has occurred* and
lost its connection. Its process was running; it had written nothing
anywhere. `Start-XmipOperationWeb` starts it with no log, and the error was
gone before anyone could read it. The audit capability existed — its README
says *failures are always audited and failure records are always persisted;
that is not policy* — and only the runtime was meant to use it.

The owner, 2026-09-25, reading that: *The operation web tool should use
Xmip's auditing functionality.* Then: *All Xmip tools should use Xmip's
auditing functionality, not just the runtime.* Then: *If auditing fails use
the OS log.*

## Decision

### 1. Every Xmip program audits

A program Xmip ships or the estate runs — a process ADR-0053 names, a
surface ADR-0014 names, a cmdlet in either PowerShell module, the estate's
landing and test tooling — records through `xmip-core-audit`: what it
started and stopped, every act an operator took through it, and every
failure, an unhandled one first.

### 2. One implementation, called across the boundary

The record, its policy and its sinks are the audit capability's, in Rust,
and nowhere else (the owner, 2026-09-24: *code shall be uniquely placed*).
The runtime's library forwards an audit export beside the rules of
`xmip_operate.h`, and `Xmip.Abi` binds it once; the .NET programs and both
PowerShell modules call it. No program writes an audit record of its own.

### 3. The operating system's log is the fallback, not a second sink

When audit cannot persist — no sink configured, the sink unreachable, the
runtime's library not loadable — the record goes to the operating system's
log, written by the same capability: the Windows Event Log (source `Xmip`),
the systemd journal or syslog on Linux, the unified log on macOS. A program
that cannot reach even the audit capability writes to the operating system's
log itself, with the one sentence that says why, and nothing else.

### 4. A failure is never only on a screen

A page, a prompt or a console may say a failure; the record of it is
audit's, or the operating system's. *An unhandled error has occurred* with no
record behind it is a defect.

## Consequences

- The web host's unhandled errors, the Playground's crashes and a landing
  that stopped are all found in one place, or in the operating system's log
  when that place was down.
- Registering the `Xmip` event source on Windows needs elevation once; the
  prerequisite installer does it, and until it has, the fallback writes
  under the Application log's existing .NET runtime source and says so.
- The audit capability grows an operating-system sink per platform; each is
  a technology under it, declared in `architecture.toml`.
- Every surface and tool changes in the same change (the owner's rule:
  surfaces stay current).

## Where it is written, 2026-09-25

- **The capability.** `xmip-core-audit`: `Audit` decides by policy and
  keeps failures always, persists to the sink, and sends what the sink could
  not keep — or everything, with no sink — to `OperatingSystemLog`; clause
  3's rule is written there once. `ProgramAudit` is a program's audit, and
  its default sink is `FileSink`, `audit.toml` in the directory the program
  was told, else `XMIP_AUDIT_DIRECTORY`, else none. An address's user and
  password never reach a record (`redaction.rs`).
- **The operating system's log.** On Unix one datagram to the local syslog
  socket — the journal's own on a systemd machine, the unified log's on
  macOS. On Windows an entry under the source `Xmip` — `XMIP_EVENT_SOURCE`
  in `xmip_operate.h`, declared once and bound in both bindings — through
  the Event Log's C interface, from `windows_event_log.rs`, the one file in
  the crate that may hold unsafe code (ADR-0050, amendment 2026-09-25).
  `Install-XmipPrerequisite` reads the name from the header and registers
  the source when run elevated with `-Install`, and otherwise prints the
  line. No test writes to the machine's log or to `.local-work/audit`.
- **The crossing.** `xmip_operate.h` section 9, `xmip_audit_v1`, forwarded
  by the runtime and bound once by `Xmip.Abi` (ADR-0027, amendment of this
  date); `Xmip.Surface`'s `ProgramAudit` is every .NET program's call, and
  its `OperatingSystemLog` the one .NET writer, for a program that cannot
  load the runtime's library at all (ADR-0052, amendment of this date).
- **The programs.** The web host and the desktop host (every error they
  log, their start and stop, the desktop's validate and start); the command
  line (each command and its exit); the PowerShell module (every cmdlet's
  failure, its acts on a scope, the prompt's failures); the script module's
  `Write-XmipAudit` in `Start-XmipTest`, `Stop-XmipTest`,
  `Start-XmipOperationWeb`, `Stop-XmipOperationWeb` and
  `Publish-XmipChange`; the Playground's roll, cluster and node processes
  and the language server, which call the capability directly. The web
  host's console is kept in `.local-work/web` beside its run, as a roll's
  is; the estate's records go to `.local-work/audit`.

## Provenance

**The owner's**, 2026-09-25: the three sentences quoted in Context — every
Xmip tool audits, through Xmip's auditing, and the operating system's log
when auditing fails.

**The assistant's**, everything else: the list of programs in clause 1,
the call path in clause 2, the platform logs named in clause 3 and the
event source's name, and clause 4's wording. Written on the day of the
failure that prompted it.
