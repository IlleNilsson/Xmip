# ADR-0062: Every Xmip tool audits, and the operating system's log catches what audit cannot

- Status: Accepted
- Accepted: 2026-09-25, the owner, in the words quoted below
- Date: 2026-09-25
- Related: ADR-0014 (operator surfaces; its security clause already audits
  every remote invocation through `xmip-core-audit`), ADR-0027 (the operator
  boundary, whose sections 7 and 8 are how a .NET surface calls a rule the
  runtime owns), ADR-0052 (the surfaces share one model; its fourth view,
  the Audit, since the amendment of 2026-09-29), ADR-0053 (the processes
  Xmip owns, their names and the location each declares, which every record
  carries since 2026-09-29), ADR-0059 (a test suite carries its
  provider), ADR-0028 (a hidden run's records say `hidden = "true"` and are
  read only when a query includes them, its amendment 2026-09-30), `doc/architecture/observability-model.md`,
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

## Amendment, 2026-09-28: the Xmip Service audits

`xmip-service` (ADR-0018, amendment 2026-09-28) joins clause 1's programs,
calling `ProgramAudit` directly. It records `start` with its node,
configuration and purpose, and `stop` with who stopped it (the console, the
service manager, the Service Control Manager, or the system shutting down),
how long the drain took in milliseconds, and the counts of what became of
every Stream. A refused start, a failed declaration and every panic are
failures.

## Amendment, 2026-09-29: the audit is read, whose each record is, and the Audit view

The owner, 2026-09-29: *The operation web needs an audit view: audited
entries in the clusters. Drill-down, sorting and filtering.* The form was
left to the assistant (*do your best and I'll view it*). Every program had
audited since 2026-09-25 and nothing read the records back: an operator
opened `audit.toml` in an editor, and nothing in a record said which cluster
or node it belonged to except a program's name, which nothing at runtime may
read for meaning.

### 5. A record says whose it is

A process that belongs somewhere in Xmip writes on every record the
location it declares (ADR-0053 clause 3): `location = "xmip:///C1"` for a
Playground roll and its cluster, `xmip:///C1/node/R1` for a node and for the
Xmip Service. The one writer puts it there — `ProgramAudit::locate`, set
once where the process declares itself and shared by every clone, the panic
hook's among them — so no caller writes it of its own. A program that serves
no scope — a cmdlet, a web host, the command line — writes none, and a
reader shows its records under their host. Records written before this carry
none and stand under their host too; nothing is inferred from their names.

### 6. The audit is read in one place

The reader is the capability's, beside the writer: `audit_store::read`
reads `audit.toml` into records and keeps them, reading only what was
appended since — the file only grows, so a view that reads again on every
change of a cluster reads a few hundred bytes. `audit_query::AuditQuery` is
what every surface asks, in one set of words: who (`location`, at and
beneath a scope; `host`; `program`; one `record`), the scope `pattern` by the
estate's one wildcard over each location, `severity`, `action`, `from` and
`to`, `sort` by any column either way, and a bounded page. The answer counts
what matched, carries the page, the groups one step down the drill —
clusters and hosts, a cluster's nodes and its own programs, a node's
programs — the actions there are to choose from, and the column and severity
words, so no surface keeps a list of its own.

The wildcard it filters by was `ScopePattern`'s, in `Xmip.Surface`, and a
Rust reader could not call it; code is placed once, so it moved to
`observe::wildcard`, the runtime forwards it as `xmip_scope_matches_v1`
(`xmip_operate.h` section 7) and `ScopePattern.Matches` calls that (ADR-0052,
amendment of this date).

### 7. Every surface reads it the same way

The runtime forwards the read as `xmip_audit_read_v1` (`xmip_operate.h`
section 9, the header's JSON in memory), `Xmip.Abi`'s `RuntimeAudit.Read`
binds it once, and `Xmip.Surface`'s `ProgramAudit.Read(AuditQuery)` is every
.NET surface's call, reading where that program's own records go:

- **The views** (web and desktop, which share `Xmip.Gui`): a fourth view,
  **Audit**, beside Configuration, Monitor and Topology. The drill is
  cluster → node → program → one record, each level listing the groups
  beneath with their counts, errors and warnings, then the records — time,
  node, program, action, phase, severity, summary — newest first, a column's
  head sorting by it and again the other way. The filters are the scope
  pattern box every view has, and severity, action and a time range beside
  it. Everything is in the address, so a link reproduces the view; a page is
  200 rows with the next and the previous a link away, never a `Virtualize`.
  A record opens whole. Where the audit cannot be read — no directory, no
  runtime library, a remote surface whose cluster's audit stays on its own
  machine — the page says so in words. The Monitor's drill links each scope
  to its audit.
- **The command line**: `xmip-cli audit [<pattern>] --location <scope>
  --host <name> --program <name> --record <id> --severity <word> --action
  <word> --from <time> --to <time> --sort <column> --order
  ascending|descending --offset <n> --limit <n> [--json]` — the file read
  and how many matched, the groups one step down, then the records; with
  `--record`, every field and property; with `--json`, the whole read. A
  refused query is the capability's REFUSED sentence and exit 2; no audit
  directory is said in words and exit 1.
- **PowerShell**: `Get-XmipAudit [[-Pattern] <string>] [-Location <string>]
  [-ComputerName <string>] [-Program <string>] [-AuditId <string>]
  [-Severity <string>] [-Action <string>] [-From <datetime>] [-To <datetime>]
  [-Sort <string>] [-Ascending] [-First <n>] [-Skip <n>]
  [-IncludeTotalCount]`, `AuditEntry` objects with a table view. The words
  `-Severity`, `-Sort` and `-Action` take are offered by Tab from the
  capability's answer, never a `ValidateSet` of a copy; a wrong word is the
  capability's REFUSED. The sentences all three surfaces say — no directory,
  a refusal, a time to the second — are `English`'s, once.

## Provenance, 2026-09-29

**The owner's**: the requirement, in the words quoted above, and the form
left to the assistant. **The assistant's**, for the owner to view and
overrule: the location on every record and its name, the reader and its
words, the groups, the view's columns, its filters and the page of 200, the
move of the wildcard to Rust, and the command line's and PowerShell's forms.
