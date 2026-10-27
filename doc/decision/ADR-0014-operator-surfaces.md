# ADR-0014: The operator surfaces and their language

## Status

Accepted. Implementation follows in separate reviewed changes.

The versioning question the 2026-08-26 amendment left open — one header, two
audiences, different stability expectations — is answered by ADR-0027: a second
header, `xmip_operate.h`, versioned apart from the module boundary.

The identity consequence the same amendment recorded is **not** answered. A
surface holding runtime state in-process is a host process with an identity
context, and ADR-0022 clause 3 governs what may sit beside it. Open problem 20.

## In brief

- Theme: Operating Xmip
- Subject: The operator surfaces and their language
- Name: The operator surfaces
- Order: 1
- Concepts: ABI, the interface into Xmip; Audit, the durable record; Blazor, .NET, the GUI; CLI, `xmip`, Rust; Observation, and why it is lossy; Phone app, APK; Remote operation, WinRM, SSH

Rust is the language of the runtime; everything in the message path is Rust.
Across a language boundary everything goes through the C ABI; Rust to Rust,
through traits (amendment 2026-10-12). The command line, `xmip`, is Rust
on the runtime's traits, so it runs where .NET does not; the PowerShell module
and the GUIs, a MAUI desktop and a Blazor web, are .NET 11 through the C ABI
(`Xmip.Abi`). The four stay, each for its purpose; the desktop runs on Windows
and macOS, and on Linux only through Microsoft's experimental GTK4 backend
(amendment 2026-10-13).

**No surface goes through another surface to reach Xmip.** `xmip-core-abi` is the interface *into* Xmip —
configuration, runtime, observing, eventing, auditing — and not only the
boundary loadable Modules plug into. The amendment of 2026-08-26 put it there,
superseding the original clauses that made every surface a client of the `xmip`
executable: that made the CLI a chokepoint, where a capability had to be a
command before it could be a screen, and left the PowerShell module scraping
JSON out of a subprocess.

The guarantee that mattered survives and is stronger. One definition of what an
operator can do, so surfaces cannot drift the way the BizTalk console and its
PowerShell provider did — now held by a normative versioned contract with a
written specification rather than by a Rust library inside one executable.

Observation never sits in the message path and is lossy by design; `report` and
`audit` are the durable records. A command is run on another machine through
existing shell remoting — PowerShell Remoting over WinRM or SSH, and the CLI
over SSH; a surface operates a node over gRPC to its operate listener — on
TCP inside mutual TLS from another machine, at its local endpoint, a named
pipe or a Unix domain socket, from its own — and calls the C ABI directly
only for what has no node behind it (ADR-0052, amendment 2026-10-05;
amendment 2026-10-13), and SignalR is only between the web host and a GUI
client.

## Context

Xmip has a runtime and no way to look at it. The manifest already declares the four observation capabilities, xmip-core-event, xmip-core-observe, xmip-core-report and xmip-core-audit, and the three surfaces, abi, cli and powershell. What it does not have is anything an operator sits in front of.

Two are required: an executable, and a web solution. Both configure, operate, report and observe.

Monitoring is not a fifth verb. It is xmip-core-observe, which was already declared and is only now getting a surface.

BizTalk is the warning. Its Administration Console was simultaneously the live monitor and the historical query tool, reading the same tracking tables in the same SQL Server instance the runtime depended on. Turning tracking on cost throughput, so the standard field advice became to turn tracking off in production. A monitoring system that must be disabled to go fast is not a monitoring system.

The same console reached into the MessageBox directly. That is why parts of it were never scriptable, and why what the console could do and what the PowerShell provider could do drifted apart.

## Amendment, 2026-08-26: every user-interfacing module is .NET 11

**Supersedes clauses 7 and 8 where they say the CLI is Rust.**

Clause 2 already said *"the operator surfaces are written in .NET 11, both the
executable and the web solution"*. Clauses 7 and 8 said the executable is Rust.
Both were accepted, in one record, contradicting each other.

The rule:

```text
xmip-core-cli          .NET 11      the xmip executable
xmip-core-powershell   PowerShell   which runs on .NET
xmip-core-gui          .NET 11      MAUI desktop and Blazor web
xmip-core-abi          Rust         the exception
```

**`xmip-core-abi` is the exception because it is not a surface.** It is the
binding over the normative C header, and it sits on the runtime's side of the
boundary. Everything a person touches is .NET 11; the thing they touch it
through is Rust.

**Why it settles the right way.** Clause 2's reasoning was always the stronger
one: *"the operator surfaces are .NET because that is where the operators are.
The people replacing BizTalk are .NET people, running Windows, already holding
PowerShell."* A Rust binary would have been the odd surface out, and clause 7
justified it by the CLI being what everything else went through — which the ABI
amendment below has since retired.

**Consequences.**

`xmip-core-cli` is not a Rust crate. It carries `primaryLanguage = "dotnet"`,
and the crate policy does not apply to it — ADR-0014 clause 14 already covers
that shape for `powershell` and `gui`.

**All three surfaces P/Invoke the same C ABI, and all three are .NET.**
PowerShell Core runs on .NET, so one binding assembly serves all of them.
Writing those declarations three times would mean three things that must agree
about struct layout, calling convention and lifetimes — which is the drift an
ABI exists to prevent. ADR-0012 clause 2 already frames bindings as
conveniences over the normative header, so the .NET binding belongs beside the
Rust one in `xmip-core-abi`.

`crates/xmip-cli/src/main.rs` was distributed to `module/operation/cli` on
this date on the assumption it was a Rust crate. It is Rust in a .NET
repository and does not belong there.

**.NET 11 reaches GA on 10 November 2026**, so all three need a preview SDK
until then. ADR-0021 permits tracking a preview provided the date it becomes
stable is recorded, and `prerequisite.toml` records it.

## Amendment, 2026-08-26: the ABI is the interface into Xmip

**Supersedes clauses 3, 9 and 13.**

`xmip-core-abi` is **the interface into Xmip** — configuration, runtime,
observing, eventing, auditing and the rest. It is not only the boundary that
loadable Modules plug into.

**Its clients are every operator surface:**

```text
xmip-core-cli          the xmip executable
xmip-core-powershell   the PowerShell module
xmip-core-gui          .NET 11 MAUI, the desktop GUI
xmip-core-gui          .NET 11 Blazor, the web GUI
```

All four go to the ABI. None of them goes through another surface to get there.

### What this replaces

Clause 3 said *"Nothing outside the runtime calls the ABI: not the PowerShell
module, not the GUI, not a .NET surface."* Clause 9 said the PowerShell module
*"does not call the ABI"*. Clause 13 put the operations in `xmip-core-cli` so
that clause 3 held by construction.

That arrangement made the CLI a chokepoint: every capability any surface needed
had to be expressible as a command first, and every other surface was a client
of a *program* rather than of a contract. The PowerShell module's job became
scraping JSON out of a subprocess.

### What holds instead

**The guarantee survives and gets stronger.** Clause 13's real value was
*implemented once* — one definition of what an operator can do, so surfaces
cannot drift the way the BizTalk console and its PowerShell provider did. That
now sits at the ABI, which ADR-0012 already made a **normative, versioned
contract with a written specification**. A Rust library inside one executable
was never that.

**One path becomes one contract.** Clause 3's intent — no surface gets a
privileged route, no private endpoint, no direct store access — is unchanged.
What changed is where the single route runs: through the ABI rather than through
the `xmip` binary.

**The CLI stops being special.** It is now one client among four, and a
capability no longer has to be a command before it can be a screen.

### Consequences, recorded rather than discovered

**The .NET surfaces P/Invoke a C ABI.** `xmip_module.h` is C (ADR-0012), so
`powershell` and `gui` carry native libraries per platform and per
architecture — Windows, Linux, macOS, x64 and arm64. ADR-0015 packages the node
and does not yet cover a PowerShell module shipping native binaries.

**The runtime loads in-process.** A PowerShell session calling the ABI is a
host process holding runtime state. ADR-0022 clause 3 says different identity
contexts must not share a host process, and an operator session now has one.
That needs settling before anything ships.

**The ABI serves two audiences.** Module authors plug *in*; operator surfaces
drive *from outside*. One header, two consumers, different stability
expectations — a versioning question ADR-0012 did not have to answer when the
boundary faced one way.

**Remoting is unaffected in principle.** PowerShell Remoting still carries the
session over WinRM or SSH, so Xmip still designs no authentication for its own
control plane. What crosses is now an ABI call on the remote machine rather than
a command run there.

## Amendment, 2026-08-26: xmip-core-webapi is deprecated

`xmip-core-webapi` was declared in `architecture.toml` as *"HTTP Web API for
addressing Xmip Streams, Messages and Journeys"*, created on GitHub, and mounted
as a submodule — with no architecture document describing it and no decision
record authorizing it. It is now `maturity = "deprecated"`.

**It contradicted clauses 3 and 6 of this record.** An HTTP API for addressing
Xmip's own Streams, Messages and Journeys is a private endpoint and a second
path from an operator to the runtime, which clause 3 forbids in its first
sentence, and it is a bespoke remote control protocol, which clause 6 forbids by
name.

**The capability already exists.** `xmip-core-logic-http-api` over
`xmip-core-transport-http` is the Web API, and `[logic]` in the manifest reads
*"**Expose** and invoke method-oriented protocol operations"* — serving an HTTP
API was always in scope there. `webapi` duplicated it at module level, in a
different domain, distinguished only by plane: integration versus management.
Management is the one this record rules out.

**The case that could have justified it does not exist.** A Blazor WebAssembly
GUI cannot invoke an executable and would need an HTTP endpoint. But
`xmip-core-gui` declares *"two hosts: Hybrid in the desktop application and
server-side on the web"* — neither is WebAssembly, both run where they can call
the `xmip` executable, and both already declare `dependency =
["xmip-core-cli"]`. The manifest had answered the question before anyone asked
it.

**How it survived.** It was `xmip-core-api`, renamed to `webapi` to stop it
colliding with `xmip-core-abi`. The rename made it look deliberate — an
ambiguous name someone might have questioned became a specific one that reads
like a decision. Nobody asked whether it should exist, including the assistant
that created it on GitHub on 2026-08-26 and cemented it.

**If a management surface over HTTP is ever wanted**, the answer is not a
module. It is an ordinary Xmip artifact: a Receive Location on
`transport-http` with `logic-http-api`, using the Composite interaction pattern
in `runtime-model.md` section 11, routing to Processes. Xmip operated through
its own message model, with identity, authorization, audit and Journeys applying
to management operations for free.

That carries a real hazard, named in `open-problems.md` problem 16 as the
tempting wrong answer: an estate that reconfigures itself through its own
message flow has no configuration anyone can read. It needs deciding, not
building.

## Decision

1. Rust is the language of the runtime. Everything in the message path is Rust.
2. The operator surfaces are written in .NET 11, both the executable and the web solution.
3. The operator surfaces are clients of the xmip executable. Nothing outside the runtime calls the ABI: not the PowerShell module, not the GUI, not a .NET surface. A surface gets no privileged path, no direct store access and no private endpoint. Anything a surface can do is a thing the command line can already do.
4. Observation never sits in the message path. observe consumes events. It is not a step that must succeed for a Message to proceed.
5. Observation is lossy by design and says so. report and audit are the durable records. observe is a sample of what is happening now.
6. Remote operation is carried by existing shell remoting: PowerShell Remoting over WinRM or SSH, and the CLI over SSH. Xmip defines no bespoke remote control protocol.
7. The runtime is Rust. abi is Rust, as the binding crate over the C header that ADR-0012 made normative. cli is Rust: one cross-platform executable that bash and PowerShell both drive, which is why there is no bash module and no bash repository. powershell is PowerShell Core, cross-platform, and Windows PowerShell is not supported. The GUI is .NET 11 Blazor.
8. There is one command-line executable. It is written in Rust, produced by xmip-core-cli, and it is called xmip.
9. Every operator surface goes through that executable. The PowerShell module invokes it. It does not call the ABI. There is exactly one path from an operator to the runtime.
10. The executable emits JSON. A follow mode emits JSON Lines, one object per line, so it streams down a pipe, over SSH and through a remoting session without becoming a different mechanism. The PowerShell module shapes that JSON into objects.
11. The GUI never reaches the runtime directly. It invokes the executable, locally or through remoting, like any other operator.
12. The GUI is one component library with two hosts: Blazor Hybrid for the desktop application and server-side Blazor for the web solution. Both live in xmip-core-gui. The desktop host is .NET MAUI, so every operator surface runs on Windows, macOS and Linux; WPF and WinForms are excluded because they are Windows only. WebAssembly is excluded because a browser sandbox cannot satisfy clause 6. gui is a surface module alongside abi, cli and powershell.
13. The operations live in xmip-core-cli. Every operator action is implemented once, in a library, and the xmip binary is argument parsing and JSON formatting over it. Clause 3 then holds by construction rather than by discipline: a surface cannot do what the command line cannot, because there is nothing else for it to call.
14. A module that is not a Rust crate carries a language key in the manifest. powershell and gui are not crates, and the crate policy assumes Rust. ADR-0011 governs module and repository names; it governs neither the name of a command a person types nor the names of .NET projects.

## Why the split

Rust holds the runtime because that is where correctness under concurrency is decided, where throughput is won or lost, and where a defect is most expensive to find. It is also where the module boundary lives, and ADR-0012 already made that boundary a C ABI rather than a language.

The operator surfaces are .NET because that is where the operators are. The people replacing BizTalk are .NET people, running Windows, already holding PowerShell. A surface they can read, extend and script in a language they know is worth more than one written in the same language as the runtime.

The two never share a process, so the split costs nothing at runtime. Clause 3 is what keeps it honest.

## Reach

Clause 6. abi is in-process and cli and powershell are local processes, so on their own they reach one node. A web solution serving many operators across many nodes cannot call into a machine it is not running on.

The answer is that both shells already solve this. PowerShell Remoting carries a session over WinRM or over SSH, and the CLI runs over SSH like any other command. A remote invocation is the same invocation, so clause 3 holds unchanged: the web solution still does only what the command line does, on a machine it is not sitting on.

This is worth more than the convenience. Remoting brings its own authentication with it, Kerberos and Active Directory on one path and SSH keys on the other, both already understood and already permitted inside the organizations Xmip is aimed at. Xmip does not have to design authentication for its own control plane, and a control plane with hand-rolled authentication is exactly the kind of thing that fails an enterprise security review.

Streaming survives the crossing. A remoting session returns objects as they are produced rather than at the end, and SSH streams standard output, so a follow mode works remotely without becoming a different mechanism.

## The .NET version

Version 11 reaches general availability on 10 November 2026 and is a Standard Term Support release, supported until 9 November 2028. Version 10 is the current Long Term Support release and is supported until November 2028, so the LTS window ends later than the STS one.

That tradeoff was put and 11 was chosen. The consequence is recorded rather than argued: neither operator surface can ship on a released runtime before November 2026, and both will need to move to the next LTS sooner than an equivalent version 10 codebase would.

The Xmip runtime is unaffected. It is Rust and does not wait for a .NET release.

## Amendment, 2026-09-12: one scope surface, including the PowerShell provider

**Withdrawn 2026-09-14, two days after it landed.** It was merged with the
code it describes and without the review the record asks for. The owner
reviewed it against ADR-0027 and ADR-0032 and kept the shared shapes, the
two acts and the two outcome counts, and declined the provider, start, stop
and restart, and the word Activity for a count. ADR-0052's amendment of
2026-09-14 is the ruling; the text below stays as what was proposed.
The CLI, PowerShell module and GUI share `IOperatorSurface`, `ScopeTree`,
`ScopeItem` and `ActivitySummary` from `xmip-core-abi`. They may render them
differently; they may not redefine what a scope, counter or action means.

PowerShell exposes the canonical scope tree as the `Xmip:` provider. It is an
operational provider, not a read-only catalogue: `Set-Item` and the named
lifecycle cmdlets can pause, resume, start, stop or restart a node, host
service, process or location through the same scope operations the CLI uses.
Every mutating cmdlet supports `-WhatIf`.

The CLI exposes the corresponding `list`, `show`, `activity`, `pause`,
`resume`, `start`, `stop` and `restart` commands. `activity --follow` consumes
the shared change signal; neither shell polls the runtime to decorate its
prompt.

An operation the current runtime cannot perform returns Unsupported. A surface
must not simulate lifecycle by changing health text: host-service start, stop
and restart become effective only when ADR-0018's host-service phases exist.
Pause and resume are effective now through the accepted operator table.

## Consequences

ExecutionHostKind::DotNet already exists in contracts.rs. .NET was already a declared execution host, so nothing in the module model changes to accommodate this.

cli becomes the specification of what an operator can do. Every capability the executable or the web solution needs must be expressible as a command first. That is a real constraint on the CLI and a deliberate one. It is what stops the two surfaces drifting apart the way the BizTalk console and its PowerShell provider did.

It also means a capability is testable before any user interface exists.

A web solution that can remote into every node holds credentials that reach the whole cluster. That makes the web host a high-value target and it must be treated as one: its own identity rather than a shared operator account, least privilege on each node, and every remote invocation audited through xmip-core-audit like any other operator action. Inheriting mature authentication does not mean inheriting a safe deployment. ADR-0062 (2026-09-25) widens the audit clause from remote invocations to every Xmip program and every act and failure in it, and sends to the operating system's log what audit cannot persist.

## The command

Clauses 8 and 9. Bash cannot call a C ABI. It can execute a binary and read what comes back, and that is the whole of it. PowerShell can P/Invoke into a native library, so it could reach xmip-core-abi directly, and that is precisely why it must not. A PowerShell surface with a path bash does not have would be able to express things bash cannot, and the two would drift. That is the BizTalk Administration Console and its PowerShell provider again, for the same reason.

So one binary, and both shells drive it.

The cost is that PowerShell operators are handed text where they expect objects. Clause 10 pays it: the text is JSON, and the module turns it into objects on arrival. This is how az, gh and kubectl settle the same argument, and it keeps one code path rather than two.

The binary is called xmip. The repository and the crate are xmip-core-cli under ADR-0011, but ADR-0011 governs module names, not the name of a command a person types at a prompt. A command is one word.

## The GUI

Clause 12. Blazor is what turns two requirements into one. A Razor class library holds the components, Blazor Hybrid hosts them in the desktop application and server-side Blazor hosts them on the web. The two are then literally the same screens. They cannot drift, because there is nothing to keep in step.

MAUI hosts the desktop application because every other decision in Xmip is cross-platform and this one should not be the exception: PowerShell Core runs everywhere, ADR-0015 packages for Windows, Linux and macOS, and the command is a Rust binary. WPF with a BlazorWebView is the better-trodden path and it is Windows only, which would make the desktop application the one surface an operator on Linux cannot run.

The render mode is not a preference. A web solution has to reach many nodes; reaching them means PowerShell Remoting or SSH; and a browser sandbox can do neither. WebAssembly cannot satisfy clause 6, so the web solution runs server-side. That is a constraint falling out of an earlier decision rather than a fresh choice.

gui joins abi, cli and powershell in surfaceModules. A provider may ship xmip-<provider>-gui, on the same terms as the other three: their license, their support, no approval.

## Amendment, 2026-08-30: the SDK and the target framework are two rulings

Stated by the owner when a net11.0 build of the PowerShell module met the shell
it exists for: **PowerShell 7.6.5 hosts .NET 10, and that is fine. C# is
compiled with the .NET 11 preview SDK.**

The 2026-08-26 amendment said ".NET 11" and meant one thing; it is two. The
*toolchain* is the .NET 11 preview SDK, estate-wide, pinned in every
`global.json`. The *target framework* is owned by whoever loads the assembly:
an executable owns its runtime and targets net11.0 — the cli — while a binary
PowerShell module loads into pwsh and targets what the platform pwsh
(ADR-0021's floor) hosts, which is net10.0 today and follows pwsh upward.

Found the honest way: the module was built net11.0 to the letter of the earlier
amendment, and `Import-Module` refused it. A rule that produces an assembly its
own platform cannot load was a rule stated with one word too few.

## Open

**Backpressure.** Clause 10 settles what a follow mode emits and says nothing about what happens when a consumer cannot keep up. Dropping is consistent with clause 5, since observation is lossy by design and says so. Which samples are dropped, and whether the consumer is told it missed some, is not settled. A monitor that silently skips is worse than one that admits a gap.


## Amendment, 2026-09-05: the desktop GUI runs what a browser cannot

Both GUIs read the same operator surface, but they are not interchangeable, and
the reason is the browser's sandbox. **The desktop GUI executes commands a
browser cannot** — it reads and writes the node configuration TOML files on
disk, loads the native runtime library, and asks it to validate or start a node
(`xmip_validate_v1`, `xmip_start_v1`). None of that is available to a page in a
browser: no local file it did not receive over the wire, no native library, no
process control.

So the split in clause form: the **web GUI monitors** — it reads snapshots and
nothing else, which a sandbox can do safely. The **desktop GUI monitors and
configures** — configuration is on the desktop precisely because configuring a
node means touching the disk and the runtime, which only an unsandboxed process
can. This is not a preference about where a screen lives; it is what each host is
physically able to do. The owner's point, 2026-09-05: *the GUI shall be able to
execute commands that a browser can't.*

## Amendment, 2026-09-09: the .NET binding is one project in xmip-core-abi

The 2026-08-26 amendment made every surface a client of the ABI and recorded
that *the .NET surfaces P/Invoke a C ABI*. By 2026-09-09 they did so three
times: `xmip-core-cli` and `xmip-core-powershell` each carried a copy of the
`xmip_module.h` binding and the probe, and `xmip-core-gui` bound
`xmip_operate.h` on its own with its own `XmipStr`. Three bindings of one
header is the drift ADR-0012 and this record exist to prevent, one header at a
time.

**The binding lives with the header.** architecture.toml already says so —
`xmip-core-abi` is *C header, specification and language bindings* — and
ADR-0044 says shared code goes up to what both already depend on. So
`module/foundation/abi/dotnet/Xmip.Abi` is the one .NET binding: the module
boundary (`XmipStr`, `XmipStatus`, the descriptor, host and module structs, the
probe) and the operator boundary (`Operator` over `xmip_operate.h`, with the
health, measurement and lifecycle calls, and the record types the GUI's
`IOperatorSurface` returns). It targets .NET 10 because pwsh hosts .NET 10
(amendment 2026-08-30) and a .NET 11 surface can reference a .NET 10 library;
the reverse would not hold.

**The three surfaces reference it by path inside the composed estate**
(ADR-0016): `../../../../foundation/abi/dotnet/Xmip.Abi/Xmip.Abi.csproj`
from each surface project. .NET has no `git = ..., branch = "main"`; a NuGet
feed would be the equivalent and is not worth standing up for four consumers
in one estate. A surface repository therefore builds inside the estate, which
is where `xgit` builds it. This is the one place the estate's "each repository
builds on its own" does not hold, and it is recorded here rather than
discovered.

**What it makes possible.** With the operator boundary bound once, the CLI and
the PowerShell module gain what only the desktop GUI had: `xmip health` and
`xmip validate`, `Get-XmipHealth` and `Test-XmipNodeConfiguration`, driving a
node through `xmip_operate.h` rather than describing the binding (ADR-0027's
complaint about `abi`, `status` and `probe`). A capability no longer has to be
a screen before it can be a command, which is the 2026-08-26 amendment's
promise the other way round.

## Amendment, 2026-09-10: the configuration tool has two faces

The desktop GUI's configuration half (amendment 2026-09-05) is one tool with
two faces, for two kinds of people. **Operators** run the MAUI executable —
screens, a health tree, Validate, Save and Start. **Developers** edit the same
node configuration where they already are, in VS Code: a **VS Code
extension** is the second face of the configuration tool, and it is a surface
on the same terms as the other four. The owner, 2026-09-10: *the GUI
configuration tool has to be represented as a MAUI executable and a VS Code
extension. Operators are more likely to use the MAUI executable and
developers the VS Code extension.*

**It goes to the ABI, like every surface.** The extension is a TypeScript
shell and nothing more: it starts a language server and shows what the server
says. The server is a Rust binary, `xmip-lsp`, that loads the runtime's
native library and calls `xmip_validate_v1` through `xmip_operate.h` — the
same call the desktop GUI makes through `Xmip.Abi`. No surface goes through
another surface to get there (amendment 2026-08-26): the extension does not
run the `xmip` command, and the server does not link the runtime's crates
directly, because the boundary is the C ABI and the estate has one route
through it.

**Repository.** `xmip-core-gui-vscode`, a technology of `xmip-core-gui`,
mounted at `module/operation/gui/vscode`, Rust as its primary language because
the server is the substance and the shell is thin. It ships what a developer
wants from an editor: diagnostics on save from the runtime's own validation
report, and a command to validate a document on demand. Anything the MAUI
face does with the runtime beyond validation — start a node, pause a scope —
stays on the desktop, where an operator is.

**TypeScript and JavaScript live in the extension and nowhere else.** The
owner, 2026-09-10: *keep TypeScript and JavaScript only to the VS Code
extension; I do not want it anywhere else.* The estate had already refused
the language twice — it is not a module technology (`module-model.md`,
section 1) and not a contract language (ADR-0042) — and this closes the third
door: no surface, tool, test or build step in any other repository is written
in it. The extension carries it because VS Code's extension host runs nothing
else, and the shell is kept to what that host requires: starting the server,
passing the runtime's path, and showing what comes back. The moment a piece
of logic could live in the Rust server instead, it does.

## Amendment, 2026-09-14: the web GUI offers every role

The amendment of 2026-09-05 made the web GUI monitor-only, on the ground that
a page in a browser cannot read a file on disk, load the native library or
control a process. The owner ruled on 2026-09-14 that the limit is the
browser's and was wrongly made the web GUI's: the web GUI is server-side
Blazor, and its server invokes the executable, locally or over remoting, as
clause 11 says every GUI does. A node's configuration is on the node and is
reached the same way. So the web offers what the desktop offers, by role:
an Observer watches, an Operator also pauses, resumes and configures, a
Developer also opens the specific point's configuration from its scope. The
rulings and their reasons are ADR-0052, amendment 2026-09-14, which also
requires every surface — the CLI, the PowerShell module and both GUIs — to
drill from the cluster to the leaf, and the prompt to name the node when the
session is remote. What stays from 2026-09-05 is the fact: a browser page
does none of this itself; the web GUI's server does it on the page's behalf.

*Wired 2026-09-29:* until then the web host still ran as Observer, fixed in
its code. Both hosts now take the role by one rule, `RoleAssignment`
in `Xmip.Surface`, per proven caller (ADR-0009, amendments 2026-10-03 and
2026-10-06), as ADR-0009's amendment
of 2026-09-14 says where a role comes from (ADR-0052, amendment
2026-09-29), and an Operator on the web pauses,
resumes and removes an Event subscription (ADR-0065, amendment 2026-09-29),
and pauses and resumes a Subscription (ADR-0013, amendment 2026-09-30).

## Amendment, 2026-09-15: as few cmdlets as possible

The owner, 2026-09-15: *create as few cmdlets as possible; use parameters,
like the CLI uses commands and arguments.* Clause 10 already makes the
PowerShell module the shape of the executable's JSON as objects; this says
how small that shape is. `xmip` is one executable with eleven commands and
their arguments. The PowerShell module is one cmdlet per noun, and what it
does to the noun is a parameter or a parameter set — a new act on a known
noun is a parameter, and only a new noun earns a cmdlet. Every parameter is
named in every documented command. Every cmdlet that exists today stays as
named; the rule governs what is added, and a consolidation is the owner's
call. The estate module (`Xmip`) is held to the same rule.

## Amendment, 2026-09-18: the executable is `xmip-cli`

ADR-0053: every System Process Xmip owns is named `xmip-<what>`, the
executable included, so that one line finds and stops them all. Where this
record says the `xmip` executable, read `xmip-cli`; an operator types
`xmip-cli health <scope>`. Nothing else about it changes.

## Amendment, 2026-09-19: a change reaches every surface, or says which it did not

The owner, after a day in which three separate things were published and
reached one surface each: *with all you do, keep API, CLI, PowerShell & GUI
up to date.*

The four are one model (ADR-0052) so that an operator sees the same estate
whichever one they open. A change that reaches only the surface its author
happened to be working in does not leave the others empty — it leaves them
**wrong**, and confidently so, which is worse. Each of the day's three was
found by the owner opening the surface nobody had updated.

- **Every change asks the question four times.** When something is newly
  published, recorded or named, what should the ABI and `Xmip.Surface`
  expose, the CLI print, the PowerShell module return as an object, and the
  GUI show? A change is not finished until each has its answer.
- **A surface left behind is named in the landing message.** Not omitted,
  not deferred silently, and never *"left for the owner to ask for"* — that
  phrase was written the same day about node capabilities reaching the
  snapshot and not the GUI, and it is the failure this amendment exists to
  stop. The operator should not have to ask for the view of a thing the
  estate already knows.
- **The order is the model first.** `Xmip.Surface` reads it once; the three
  faces render it. A surface that parses a published file itself is the
  drift ADR-0052 was written to end.
- **What a surface shows nothing about, it says nothing about.** Silence is
  reserved for what is genuinely absent; a value the estate holds and a
  surface does not show is a defect, not a design.

Applies to everything from this day forward, and to the debt named above,
which is now owed rather than optional.

## Amendment, 2026-09-19: every object an operator sees is typed and has a table view

The owner, looking at his console: *"Now revise the output from Xmip, it does
not look well."*

He was right, and the cause was measurable rather than aesthetic. The module
exported twenty-seven commands and `Xmip/Xmip.Format.ps1xml` declared a view
for four types. PowerShell renders an object of more than four properties and
no view as a vertical list, one property per line with a blank line between
objects, so `Get-XmipStatus` printed five lines *per changed file* — hundreds
of lines on a dirty estate where a table of six rows says the same thing. Most
of those objects could not be given a view at all, because they carried no
`PSTypeName` for a view to select on.

**The rule: every object an operator sees is typed `Xmip.<Noun>` where it is
built, and every such type has a table view that fits a 120-column console.**
A type name is not decoration — it is the only handle formatting, parameter
validation (`[PSTypeName('Xmip.TestStatus')]`) and a future `Xmip.Surface`
have on the shape. This is clause 10's "the shape of the executable's JSON as
objects" carried one step further: the shape is also *named*.

Typed and given a view on this day, all in the estate module:

| Type | Cmdlet |
| --- | --- |
| `Xmip.Status` | `Get-XmipStatus` |
| `Xmip.StatusSummary` | `Get-XmipStatus -Short` |
| `Xmip.Change` | `Publish-XmipChange` |
| `Xmip.DecisionRecord` | `Get-XmipDecisionRecord` |
| `Xmip.EstateRepository` | `Get-XmipEstateRepository` |
| `Xmip.History` | `Get-XmipHistory` |
| `Xmip.Prerequisite` | `Install-XmipPrerequisite -PassThru` |

Given a view, having already been typed: `Xmip.Process` (`Get-XmipProcess`)
and `Xmip.TestSuite` (the suites `Start-XmipTest -Suite` takes). The four that
had views — `Xmip.TestStatus`, `Xmip.TestNode`, `Xmip.TestResult`, `Xmip.Web`
— keep their shape; `Xmip.TestStatus` was 134 columns wide and wrapped its own
header, and it and `Xmip.Web` now fit.

Three conventions the views follow, so that a reader meets one style:

- **A long free-text field or a path is the last column**, where truncation
  costs least, and a full path is shortened to its file name. A full path in a
  table is almost always wrong; `Format-List` still holds it whole.
- **A time in a table is `MM-dd HH:mm`.** The year is this year and the
  seconds are not what the eye is looking for. `Xmip.History` is the exception
  and keeps `yyyy-MM-dd HH:mm:ss`, because there the instant *is* the
  measurement.
- **An empty, zero or null value is rendered as the word for it** — `none`,
  `open`, `absent`, `by hand`, `unsaid`, `Xmip runs it` — which the four
  original views already did. A blank cell is a question; a word is an answer.

Presentation only. No cmdlet's return changed: same objects, same properties,
same pipeline behavior, and `Format-List` still shows every property,
including the ones a table drops. Columns a table drops are named in the view
file, not hidden: `Leaf`, `Parent` and `Mounted` from `Xmip.EstateRepository`
(the first two are read off `Name`, the third is `Mount` being non-empty),
`Branch` from the per-file `Xmip.Status` (it repeats once per file and is kept
in the `-Short` summary), and `Prose`, `Concepts`, `Subject`, `Note`, `Order`
and `File` from `Xmip.DecisionRecord`.

The four surfaces of the amendment above are not all reached by this: it is
the PowerShell module's rendering alone. The CLI, the GUIs and the ABI publish
the same model and render it their own way, and nothing here changes what they
are given.

## Amendment, 2026-09-22: xmip-core-webapi is deleted

The GitHub repository this record deprecated on 2026-08-26 is deleted, on the
owner's word: *xmip-core-webapi can be deleted.* Nothing is released, and
`xmip-core-logic-http-api` over `xmip-core-transport-http` is the web API. The
reason it went is kept here.

## Amendment, 2026-10-12: MCP comes in through the command line

The Model Context Protocol server is a mode of the command line,
`xmip-cli mcp`, not a fifth surface of its own: the fifth way into the
operator boundary, through `Xmip.Surface` as the four are, read only, its
tools the command line's read commands and its resources the scopes, and
remote over SSH as clause 6 says (ADR-0071).

## Amendment, 2026-10-12: the command line is Rust; across languages the ABI, Rust to Rust the traits

**Supersedes the amendment of 2026-08-26 where it makes the executable
.NET.** The owner, 2026-10-12: *I'm questioning my desicions, regarding the
CLI, the CLI has to be usable without .NET. If you are on an MCU or any kind
of edge device, .NET might not be the way to go. So ABI is fine, CLI should
be Rust relying on ABI, Powershell should also rely on ABI* — asked whether
the GUI stays .NET over the ABI: *Go ahead* — and, the same day, the rule
behind it: *I like .NET, but on MCU, Edge devices it is to heavy. A clean C
by Rust CLI is the way. So the CLI goes, Rust, ABI. Where PowerShell is it
will go through the ABI. Everything will go through the ABI unless it is
Rust2Rust, then it is Traits.*

```text
xmip-core-abi          Rust         the C ABI: the door for every other language
xmip-core-cli          Rust         xmip-cli, on the runtime's traits
xmip-core-powershell   PowerShell   on .NET, through the C ABI (Xmip.Abi)
xmip-core-gui          .NET 11      desktop and web, through the C ABI (Xmip.Abi)
```

- **Across a language boundary, the C ABI; Rust to Rust, traits** (ADR-0068,
  every dependency is a trait handed in). The command line is Rust calling
  Rust, so it uses the runtime's traits and loads no native library; that is
  also what lets it build small and statically for an edge device. The .NET
  surfaces, and any other language, call the same code through
  `xmip_operate.h`. None goes through another surface.
- **What the surfaces share is implemented once, in Rust.** A rule the
  command line and the .NET surfaces both apply — which surface an
  invocation reads, what a scope argument selects, the words for a mood, a
  figure, a refusal — lives in the crate that owns it; the command line
  calls it as a trait, the .NET surfaces through its export, as ADR-0052's
  amendment of 2026-09-24 began (*the surfaces call the runtime's exports*).
  `Xmip.Surface` keeps only what is .NET's own.
- **`xmip-cli mcp` moves with it** (ADR-0071): MCP is a mode of the Rust
  command line.
- **Built as it lands**: until the Rust executable replaces it, the .NET
  one is what ships; the replacement deletes it with every use.

## Amendment, 2026-10-12: a surface reaches another node over gRPC, SignalR only to a GUI

**Amends clause 6.** The owner, 2026-10-12, finding the remote surfaces
still on SignalR: *I thaugt we droped SignalR for evertyhing but GUI/Web* —
and, told they were not yet: *Go do it then, I'm not a fan of waiting.* He
had ruled it on 2026-10-05 (ADR-0052, amendment of that date): *Events is
the way to go, even between processes using gRPC over net pipe, even
between machines using gRPC over TCP*, and *SignalR is between a server and
a client using a GUI.* That later ruling is the one built here.

- **Running a command on another machine stays shell remoting**: `ssh
  <host> xmip-cli …` and PowerShell Remoting over WinRM or SSH, as clause 6
  says. Xmip adds no remote command protocol.
- **A surface that reads or follows another node does so over gRPC on TCP
  to the node's operate listener** (ADR-0067), inside Xmip's mutual TLS
  (ADR-0063): the node's publication read, a follower told when it advances,
  and the acts the surfaces have, each admitted by the role the node grants
  the identity its client certificate proves and audited, taken or refused
  (ADR-0009). Both ends are the runtime's, once (`xmip-core-runtime`'s
  `plane`); the surface's end is exported through `xmip_operate.h` section
  17, so the command line, the PowerShell module and the GUIs follow a node
  the same way (ADR-0027). The recovery loop of ADR-0052's note of 2026-10-05
  moved down with it.
- **gRPC on Xmip's own stack**: the estate's HTTP/2 (`net::http2`), its TLS
  (`xmip-core-library-tls`) and its gRPC framing (`net::grpc`, which the gRPC
  logic technology now frames with too); no gRPC crate and no async runtime.
  The messages are JSON (`application/grpc+json`), the wire's form in the
  estate; the publication they carry is the TOML its file holds, read by
  the one reader (section 8).
- **SignalR only between the web host and a GUI client**: the browser's own
  circuit of server-side Blazor. The surface hub the web host served remote
  surfaces (`SurfaceHub`, `SurfaceRelay`) and the SignalR client in
  `Xmip.Surface` are deleted with every use.
- **`--remote` and `-Remote` keep their names** and take the node's operate
  address, `host:port`; a host's document names it as `Address` with
  `Surface = "remote"`. A node serves its operate listener from its
  configuration's `[operate]` (`listen`, `certificate`, `key`, `anchors`,
  `role`).
- **Measured** on the owner's Windows machine, debug builds, loopback: from
  a node posting its next publication to a follower told, a median of about
  0.3 to 0.6 ms in the runtime (`tests/plane`), and about 1.7 ms to a .NET
  watch, which reads and parses the publication before it tells.

Provenance: the owner's rulings, quoted; the plane's shape — gRPC on the
estate's own HTTP/2, JSON messages, the follow as a held wait, the gate
moved into Rust, `[operate]` and its keys — is the assistant's, for the
owner to overrule.

## Amendment, 2026-10-13: the four surfaces stay, each for its purpose

**Corrects clause 12 where it says MAUI runs on Linux.** .NET MAUI supports
Windows and macOS; on Linux it runs only through Microsoft's experimental
GTK4 backend, maui-labs
(<https://learn.microsoft.com/en-us/dotnet/maui/developer-tools/platform-backends/linux-gtk4>),
which Microsoft does not support. Clause 12 chose MAUI so that *every
operator surface runs on Windows, macOS and Linux*; for the desktop that
holds on Windows and macOS, and on Linux only experimentally. Told so, and
asked whether the desktop should go and the web GUI be the one GUI, the
owner, 2026-10-13: *We are keeping CLI, PowerShell, Desktop via MAUI, Web
via Blazor. All (G)UI Tools has there purpose.*

- **The four surfaces stay**: `xmip-cli`, the PowerShell module, the MAUI
  desktop and the Blazor web, each for its purpose. An operator on Linux
  has the command line, the PowerShell module and the web GUI, which run
  there as on the other two; the desktop is Windows and macOS, and Linux as
  far as the experimental backend carries it.
- **The desktop's configuration logic is placed beneath it.** The cluster's
  file opened, compared, locked and written whole, its slices delivered to
  each node, and Validate, Save and Plan with their audit
  (`ClusterConfiguration`, `SliceDelivery`, `NodeDelivery`, `ClusterSave`,
  `RuntimeCommands`) moved from `Xmip.Operations` to `Xmip.Surface`, and
  their tests to `Xmip.Surface.Test`, so they are proved without MAUI; the
  desktop keeps its pages. The web GUI does not gain the editor.
- `README.md`, the gui README and `doc/planning/compatibility.md` say where
  the desktop runs.
- **A target gets its tools by what its OS offers, not by who makes it.**
  The owner, the same day: *runtime is goining to all specified targets,
  Operations is going to various targtes depending if their OS has only UI
  or GUI, regardless of OS maker.* The runtime is designed for every target
  `doc/planning/compatibility.md` names. An operating system with a text
  interface only gets the command line; one with a graphical interface gets
  the command line and the GUIs too. Xmip is the cross-platform — the X —
  Messaging & Integration Platform; no surface is chosen by a vendor's name.
  Which targets are built at a given time is a choice of the moment, not
  this record's.

## Amendment, 2026-10-13: every .NET surface operates a node over gRPC, here and elsewhere

**Amends the amendment of 2026-10-12 (*across languages the ABI*) where a
.NET surface operated a node through the C ABI, and its amendment *a surface
reaches another node over gRPC*, which said it for another machine only.**
The lead proposed that a .NET surface operate a node on its own machine the
way it operates one on another; the owner, 2026-10-13, agreeing: *Fix it and
dissagree more often, just tell me first.*

- **Operating a node goes over gRPC for every .NET surface, local and remote
  alike**: its health, figures and scopes, its Journeys, Dead Messages and
  Subscriptions, the acts on them and the follow. On the node's own machine
  the surface reaches the node's operate listener at its **local endpoint** —
  a named pipe on Windows, a Unix domain socket elsewhere, as ADR-0052's
  amendment of 2026-10-05 put it, *gRPC over net pipe* — and from another
  machine at its operate address, inside Xmip's mutual TLS, as before.
  `LocalOperator` and `RemoteOperator` in `Xmip.Surface` are the two faces
  of one `ListenerOperator` over the runtime's client (`xmip_operate.h`
  section 17: `xmip_remote_open_local_v1`, `xmip_operate_serve_local_v1`);
  `NativeOperator`, which loaded the runtime into the surface's own process
  and so operated only the nodes that process ran, is deleted with every
  use, and `Surface = "native"` with it: a host's document says
  `Surface = "local"` and `Local = <endpoint>`, a line `--local` or `-Local`.
  `--runtime` and `-Library` name the library a surface calls the runtime
  through and choose no surface; a line and a document naming no node say
  so (`LocalOperator.Unnamed`).
- **The C ABI stays only for what has no node behind it**: validating,
  editing and slicing configuration, the language server's design exports,
  module probing, the audit file read, and Modules (`xmip_module.h`).
  `ConfigurationRuntime` holds Validate and Plan, which `RuntimeCommands`
  asks. The command line in Rust is not touched by this amendment; it moves
  to the runtime's traits on its own (amendment 2026-10-12).
- **The node's side**: `[operate] local` names the endpoint; `listen`,
  `certificate`, `key` and `anchors` the network listener, which now may be
  left out, and either may stand alone (`plane::Listener::local`,
  `plane::local`). Plain HTTP/2 inside the machine is the one exception
  ADR-0063 clause 1 allows, said where it is made: an `operate.local` record
  in the node's audit. The operating system is the gate: on Windows the
  pipe's security descriptor admits its owner — the node's account —
  `SYSTEM` and the machine's administrators, and no caller from another
  machine; on Unix the socket file is `0600`. Who acts is the user the
  operating system says the connecting process runs as — `DOMAIN\user` on
  Windows, the user name elsewhere — never a name the caller gives, and its
  role is the one `[operate] role` states for every proven caller (ADR-0009,
  note of 2026-10-12). `xmip-service` declares where it is operated
  (ADR-0053).
- **Told first, read after.** A `ListenerOperator` tells every watch when the
  node's publication advances and reads it by the next question; until this
  date it read and parsed the whole publication before it told.
- **Measured** on the owner's Windows machine, debug builds: from a node
  posting its next publication to a follower told on the local endpoint, a
  median of about 0.22 ms in the runtime (`tests/plane/local.rs`) and about
  0.3 ms into a .NET watch (`LocalOperatorTest`, held under a millisecond);
  over loopback TCP with mutual TLS into .NET about 0.55 to 0.6 ms, from the
  1.7 ms the amendment of 2026-10-12 recorded.

What stays the owner's: the local endpoint admits the node's account and
the machine's administrators and no one else, and the owner kept it so
(amendment *the owner's answers* below). Whether every node serves a local
endpoint, and by what name, and what becomes of the order file the
snapshot surface leaves for a running node (`xmip_order_v1`) are decided
there.

Provenance: the owner's agreement, quoted; the endpoint's shape — a named
pipe with its security descriptor, a `0600` socket, the caller the operating
system proves, `[operate] local`, `Surface = "local"` — is the assistant's,
for the owner to overrule.

## Amendment, 2026-10-13: the owner's answers — the local endpoint always, a bounded call, acts through Xmip Storage

**Amends the amendment of the same date, *every .NET surface operates a
node over gRPC*, where it left the owner's questions open.** Decided by the
owner, 2026-10-13, question by question.

- **The local endpoint always starts.** *The local endpoint always starts,
  named `xmip-<node>` unless the configuration names it.* A node serves it
  whether or not its configuration has an `[operate]`, named as its Xmip
  Service is (ADR-0053), and `[operate] local` names another. `[operate]`
  keeps its keys: *`[operate]` keys kept (`listen`, `certificate`, `key`,
  `anchors`, `role`, `local`)*. Built: `Running::operate`,
  `Running::local_endpoint`; the starter configuration `xmip-service
  --install` writes names no endpoint.
- **Where it is.** *Socket place: Linux `/run/xmip/xmip-<node>.sock`, macOS
  `/var/run/xmip/xmip-<node>.sock`, created by systemd / launchd for the
  node's account; a name may change, the folder may not.* On Windows the
  folder is the pipe namespace, `\.\pipe\`. Built: `plane::local::place`
  is the one rule the node binds by and every surface connects by, and it
  refuses a name that would leave the folder; the systemd unit's
  `RuntimeDirectory=xmip` makes `/run/xmip` for the node's account and keeps
  it when a unit stops; on macOS, which empties `/var/run` as it starts, a
  launchd daemon of its own, `xmip-<node>.run`, makes `/var/run/xmip` at
  every boot (`registration::launchd_run_directory`). The Linux and macOS
  parts are written and not built: builds are Windows only, the owner's
  choice of the moment.
- **Who may open it.** *The local pipe stays the service account's and
  Administrators'.* No operators group is admitted.
- **A local call waits at most a set time.** *A local call waits at most a
  set time — `[tuning]`, default 2 s — then says the node did not answer and
  shows it so; the tool recovers on its own.* Built: `[tuning]
  local_timeout`, two seconds where it says nothing
  (`plane::remote::LOCAL_TIMEOUT`); the node declares it beside its
  endpoint in its process declaration (ADR-0053, `local_timeout_ms`), and a
  surface opened with no wait of its own takes it from there —
  `Remote::local`, `xmip_remote_open_local_v1`'s `within_ms`,
  `LocalOperator`'s `within`. A socket keeps the time itself; a named pipe
  has none, so a thread per surface cancels the call's read when its time
  passes (`plane::deadline`). The surface says *the node did not answer
  within 2 s*, shows the node unreachable, and the follow's recovery loop
  (ADR-0052, note of 2026-10-05) hears it again. That the node declares its
  wait, and the surface reads it there, is the assistant's, for the owner
  to overrule.
- **Receive Locations, Send Ports and Send Locations start only when the
  configuration says `true`.** *Nothing or `false` means not started, shown
  on every surface as "not started: the configuration does not say true";
  the designer writes `true` when it creates one.* The key is each one's
  `start`, which was required until this date.
- **Acts go to Xmip Storage.** *Nodes are consumable: pause, resume, retry,
  dismiss and replay are written to Storage with who and when, and every
  node honors them; reading live state from a node over gRPC stays. Order
  files are deleted with every use; snapshot files are for tests only.
  Built once Storage is assembled in the service (open problem 33).* The
  failed Journeys and a scope's pause go the same way, and the per-node act
  exports go with the order files (the owner's questions 5 and 6, folded
  into this one). Until open problem 33 is closed an act still reaches one
  node — over its operate listener, or as an order file it takes at its
  next look — and the snapshot surface leaves one
  ([`operator-acts-through-storage`](../architecture/estate-map.md#operator-acts-through-storage),
  decided, not built). ADR-0052's note of this date says it for the
  surfaces' shared model.

Provenance: the owner's decisions, quoted from his answers of 2026-10-13;
the key names `local_timeout` and `start`, the declared wait and the
deadline thread are the assistant's, for the owner to overrule.

## Amendment, 2026-10-14: the desktop host on the phone, and an MCP server to talk to Xmip

**Provenance.** The owner, 2026-10-14: *we ne a phone app. The operator
wants to know whar is going on. Extend it on .NET Blazor.* Offered three
forms — the MAUI host on phone targets, the web GUI made phone-shaped, a
separate phone host — he chose the MAUI host on phone targets, and, for
what the operator sees first, cluster health. Of MCP: *I know, that requires
internet, so it is not the first choice, but it has to be an apportunity as
MCP*; *MCP does not relate to apps on a phone*; *As a developer or operator
I can ask the MCP server, What do you got*; *What the MCP server responds is
my way to talk to Xmip*; corrected, *No, it gives me answers on how to talk
to Xmip*; and, told what the Model Context Protocol offers — prompts,
resources, tools, and `server/discover` with the three lists for *What do
you got* — *Great, so that is what the Xmip MCP Server has to do, the
implementation is one of, generall, the questions, request beeing asked is
per installation.* Of how a phone reaches the nodes away from the site:
*VPN, would be nice, not only for the phone apps*; asked whether Xmip
provides it or relies on one out of the box, *Depends if it is hard or shall
we use out of the box*; told that the hard part is each OS's virtual network
interface and that WireGuard ships for every target, *So lets get it out of
the box. Now we have Phone apps and VS Code extensions and VPN, we depend on
external parties. Let's keep that to a minimum.*

- **The phone is the MAUI desktop surface on more targets**, not a fifth
  surface: `Xmip.Operations` gains Android and iOS beside Windows, the
  components stay `Xmip.Gui`'s, and on a phone it follows nodes remotely
  over their operate listener (amendment 2026-10-12), inside Xmip's mutual
  TLS. Its first view is cluster health: every node and every Receive
  Location, Xmip Process and Send Location by its health, with the reason,
  a tap drilling down. Offered the web GUI over the VPN instead, to depend
  on fewer parties, the owner kept it: *Native GUI for the phones, fueled by
  blazor if possible.* *And an iPhone target, not only Android.* With no
  Mac, the iOS target is written but neither built nor tested until one is
  at hand: *I do not have a Mac so that has to be pseudo, virtual ... Test
  will be done later.* Built for Android the same day, not yet run on a
  phone: `Xmip.Operations` targets `net11.0-android` everywhere,
  `net11.0-windows10.0.19041.0` on Windows and `net11.0-ios` only on
  macOS, so the iOS target is built on the CI's macOS machine
  (`.github/workflows/rust.yml`, job `phone-ios`) for the simulator: the
  runtime's remote build by `Build-XmipService -Remote iOS`, then the host;
  not signed, not run. What
  configures a cluster — the Configure page, its editing components and
  the desktop's start (`MauiProgram.Desktop.cs`) — is compiled for Windows
  alone; the phone's start (`MauiProgram.Phone.cs`) takes `Surface =
  "remote"` and nothing else, reads the document shipped inside the app,
  resolves its certificate files and audit directory under the app's data,
  and holds the Observer role, which is not configurable there. The
  stylesheet's narrow-screen block lays the same pages out in one column.
  Its first page is the web's: asked whether it should list every Location
  instead, the owner, 2026-10-15: *Same as the web version.* One page,
  `Xmip.Gui`'s `Cluster.razor`, for both.
- **An MCP server gives answers on how to talk to Xmip.** A developer or
  operator asks it what it has — *What do you got* — and it answers how to
  talk to Xmip, through what the protocol offers: prompts, resources and
  tools, discovered and listed. The implementation is one, general; the
  questions and requests it is asked are per installation. It is not about
  the phone, and it is not the first choice, because it needs the
  internet; it has to be there as an opportunity. Decided, not built; its
  form is to be designed.
- **A VPN out of the box, not only for the phone apps.** Xmip builds no VPN
  of its own. It names no supplier: the owner, *I'm not sure about
  pinpointing a supplier like WireGuard, it should be by protocol or
  multiple suppliers of VPN.* Which protocols are to be decided.
- **Dependence on external parties is kept to a minimum.** The phone apps
  (Android, Apple), the VS Code extension and the VPN each depend on
  another party; the owner named them and asked that such dependence stay
  as small as it can.

Provenance: the owner's decisions, quoted; the wording of the forms he
chose between is the assistant's.

## Amendment, 2026-10-19: .NET MAUI is cross-platform

**Withdraws the 2026-10-13 correction of clause 12; clause 12 stands.** The
owner, 2026-10-19: *.NET MAUI is cross platform, so correct the decisions.*
That correction named only Microsoft's unsupported GTK4 backend, maui-labs,
for Linux, and missed Avalonia's backend for .NET MAUI, which adds Linux and
WebAssembly on .NET 11, the estate's .NET (Preview 1, 2026-03-16,
<https://avaloniaui.net/blog/maui-avalonia-preview-1>).

- **The desktop runs on Windows, macOS and Linux**, as clause 12 says:
  Microsoft's targets are Windows, macOS, Android and iOS, and Linux comes
  through Avalonia's backend, a preview today.
- Which targets are built at a given time remains a choice of the moment
  (the 2026-10-13 amendment's last point).
- `README.md`, the gui README and `doc/planning/compatibility.md` say so.

Provenance: the owner's decision, quoted; the wording is the assistant's.

## Amendment, 2026-10-19: the toolchain moves to the latest

The owner, 2026-10-19: *Lets be real, we are designing for the future,
update all references.* ADR-0021's rule, applied to this record's toolchain
sentences (the 2026-08-26 and 2026-08-30 amendments):

- **The SDK is .NET 11 release candidate 2**, 11.0.100-rc.2.26504.105 of
  2026-10-13, with a go-live license; every `global.json` names it, and the
  MAUI workloads are 11.0.0-rc.2.26505.5. Still the preview channel until
  GA on 10 November 2026.
- **PowerShell 7.6.7 still hosts .NET 10** (10.0.13), so the PowerShell
  module and the ABI's binding stay net10.0; every other project is
  net11.0, as before.
- The packages tied to the SDK follow it: the ASP.NET Core and logging
  packages float on 11.0.0-rc.2, and the lock files are restored again.

Provenance: the owner's instruction, quoted; the versions were read from
Microsoft's download page and NuGet on 2026-10-19.

## Amendment, 2026-10-21: local callers are proven by the operating system

**Amends the amendment of 2026-10-13, *every .NET surface operates a node
over gRPC*, where the local endpoint's gate was fixed, and its answers of
the same date.** Decided by the owner, 2026-10-19 (open problem 35): *local
callers are proven by the operating system*, through a named pipe on
Windows or a Unix socket's peer account elsewhere, and *tcp loopback is no
longer trusted by itself* (ADR-0009, amendment 2026-10-21).

- **Every local surface reaches a node at its local endpoint**: xmip-cli
  (`--local`), the PowerShell module (`-Local`) and both GUIs (`Surface =
  "local"`), each through the runtime's one connecting end
  (`plane::local::connect`, `xmip_remote_open_local_v1`). The VS Code
  extension's language server reaches no node: it validates and designs
  through the ABI alone. The operate listener's network address asks every
  caller for its certificate, from loopback as from anywhere.
- **Windows.** Every surface opens the pipe lent for identification alone
  (`SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION`,
  `net::pipe::connect`, amendment *the named pipe is placed once*, below),
  asking to read and write its data and
  nothing more, so a node — or whatever made a pipe of that name first —
  reads who the caller is and can never act as it. The node reads the
  account from the client's token (`ImpersonateNamedPipeClient`, the
  token's user, `LookupAccountSidW`), held by a test to the
  identification level. The security descriptor admits the node's account,
  `SYSTEM` and the machine's administrators fully, and each account or
  group `[operate] admit` names to read and write the pipe and never make an
  instance of it (`FILE_GENERIC_READ | FILE_WRITE_DATA`), so no admitted
  caller can stand in for the node; a name Windows does not know is refused
  as the node starts. Remote callers are rejected, as before.
- **Unix.** The kernel names the peer (`SO_PEERCRED` on Linux,
  `getpeereid` elsewhere) and the node admits its own account, the
  superuser and each user or group `admit` names, a member of a named group
  by the system's group list, and refuses anyone else in words. The socket
  is `0600` where `admit` names nobody, so the file system refuses everyone
  else first, and `0660` where it names some, belonging to `[operate]
  group` — the node's own group where it is left out — so the file system
  lets only that group's members connect, and the kernel's word against the
  admitted is the second gate (decided by the owner, 2026-10-21, below).
  The folder — `/run/xmip`, `/var/run/xmip` — must be the node's account's
  or the superuser's and writable by nobody else, or a stranger could put a
  socket where a surface looks; a node refuses to make its endpoint in any
  other (`plane::local::unix::guarded`).
- **What authorization judges** is that account: who acts, audited, and
  admitted by the role `[operate] role` states (ADR-0009, note of
  2026-10-12).
- **Measured** on the owner's Windows machine, debug build: a surface's
  connection from nothing to its first answer — the pipe opened, the
  account read, HTTP/2 agreed and one call answered — about 0.28 to
  0.45 ms the fastest of five and 0.30 to 0.49 ms the median over four
  runs, the process's processor time 0.48 to 0.74 ms (`tests/plane/local.rs`,
  held under the millisecond, wall and processor alike); on Linux, the
  AlmaLinux 10 guest under WSL, 0.70 to 0.82 ms the fastest of five and
  0.78 to 0.97 ms the median over three runs.
  Four costs were found and taken out on the way, each measured:
  - Windows took about 0.35 ms to name an account's identifier, so a name
    is kept by the identifier the token proved for the process's life; an
    account renamed meanwhile keeps its old name until the node restarts.
  - Every surface on a pipe started a thread of its own to keep its calls'
    deadline (amendment *the owner's answers*, above); one thread now keeps
    every surface's in the process, woken only where a call's deadline
    falls before its next look (`plane::deadline`).
  - A connection's thread is kept for the next connection, at most eight
    waiting (`plane::workers`): starting and ending one cost about a fifth
    of a millisecond.
  - HTTP/2 is generic over its connection, so the runtime's own tests
    compiled it unoptimized: a call took about 0.4 ms of the caller's
    processor time there and 0.13 ms as it ships. Both ends of the plane
    ride a boxed connection and ask the code `net` compiled
    (`net::http2::BoxedClient`, `BoxedServer`), and a call takes about
    0.2 ms.
  A surface that states no wait of its own first lists the node
  declarations to learn the node's (`deadline::declared`), which took 0.4
  to 0.6 ms of processor time on this machine's temporary folder alone;
  that is not taken out, and is the owner's to weigh.

**Drafted, for the owner:** the key's name and reach, `[operate] admit`, a
list of accounts and groups beside the node's account and the machine's
administrators, empty where it is left out — so the owner's *the local
pipe stays the service account's and Administrators'* holds until a site
names someone.

**Decided by the owner, 2026-10-21:** *Unix socket 0660 with a group, not
0666* — when `admit` names anyone, the socket belongs to a group and is
`0660`, and the node's peer check stays as the second gate; and an
account's name is kept until the node restarts, as drafted above. Built
the same day: the group is `[operate] group`, the node's own group — the
group the node's service account runs under — where it is left out; the
socket is given it as it is made (`plane::local::unix::Acceptor::bind`), a
group the system does not know, or one the node's account may not give
it, refused in words as the node starts; an admitted account outside the
group is refused by the file system. Windows admits by the pipe's security
descriptor and reads no `group`. Proved in the AlmaLinux 10 guest
(`a_socket_others_are_admitted_to_is_0660_of_its_group_and_0600_otherwise`),
where every plane test passed, the deadline test with `/run/xmip` made.

**Repaired the same day: a surface connected once, not twice.** Beside the
runtime's other test programs `a_caller_lends_its_account_for_identification_alone`
read nothing from a caller in some 35 runs of a hundred, and the local
connection's test went over its millisecond (1.24 to 1.6 ms of processor
time). Traced: the pipe library's stream, made from a handle, opens it
again (`ReOpenFile`) and closes the original, which on a pipe is a second
connection and the first one's end, so every surface connected twice and,
on a loaded machine, the node held the connection the surface had let go
while the surface waited on the other; and its accept waited for a client
by `ConnectNamedPipe` with no `OVERLAPPED` on an overlapped instance, which
Windows documents may say *connected* early. The runtime now makes each
instance, waits for its client and reads and writes it itself
(`ffi::pipe`, `ffi::pipe_io`), the security descriptor read once for every
instance, and the `interprocess` dependency is deleted. And a connection a
surface went away from is let go with nothing more said, where the node
answered its `GOAWAY` with its own and read on until it closed, a quarter
of a millisecond of processor time a connection (`plane::served::calls`).
After: the lent test failed none of 150 runs beside the library tests; a
connection from nothing to its first answer took 0.59 to 0.66 ms of the
process's processor time the fastest of five, from 0.77 to 0.87, and the
plane tests passed four runs in four beside the library and the Ledger
tests.

Provenance: the owner's decisions of 2026-10-19 and 2026-10-21, quoted; the
key, the access an admitted caller gets, the folder rule, and the group's
key and its default are the assistant's, for the owner to overrule.

## Amendment, 2026-10-21: the named pipe is placed once

**Amends the amendment above, *local callers are proven by the operating
system*, where the runtime made its pipe itself.** Agreed by the owner,
2026-10-21: the named pipe transport moves off the `interprocess` crate onto
Xmip's own pipe code, placed once.

- **One pipe, in `net`.** The runtime's pipe code moved down to
  `xmip-core-library-net` (`net::pipe`), the lowest layer both the runtime
  and the named pipe transport reach, beside `net::pipe::path_of`, which
  already said where a pipe is: `Listener::bind`, `Listener::accept`,
  `connect`, `Stream` and `Cancel`, the same on Windows and Unix. On
  Windows the system's calls — the security descriptor read from SDDL once
  for every instance, the instance made, its client waited for with an
  `OVERLAPPED` of its own, the overlapped reads and writes, the client
  opened lent for identification alone, the account read from its token
  and the identifier of an account admitted — are `net`'s folder
  `src/pipe/windows/` (ADR-0050, amendment 2026-10-21). The runtime's
  `ffi::pipe`, `ffi::pipe_io` and `ffi::system` are deleted; its local
  endpoint on Windows calls `net::pipe` (`plane::local::windows`), and its
  Unix domain socket is unchanged.
- **The transport on both systems.** On Windows the transport's pipe is
  made with the same descriptor, admitting nobody beyond its owner, the
  system and the administrators, and a Receive Location's wait for a
  writer is the system's event within its timeout, where it napped a
  quarter of a millisecond between tries. On Unix it is a FIFO, its
  owner's alone, made by `mkfifo` through `nix`; an open within a time is
  released at its deadline by the other end, as before. The writer's
  process id travels as it did (`named-pipe.client-process-id`).
- **One client is one connection, and an accept returns only with a
  client.** An instance is never disconnected to be used again and the
  next is made before a connected one is handed out; a timed-out wait is
  cancelled and the instance listens on. Held by `net`'s tests
  (`one_client_is_exactly_one_connection`,
  `an_accept_never_returns_without_a_client`) and the transport's
  (`one_writer_is_one_stream_and_no_second`). A writer that wrote nothing
  and closed before its reader waited is now a Stream of nothing; a
  Windows pipe dropped it until today, and the transport's loopback refused
  an empty Stream there.
- **`interprocess` is deleted** from every manifest in the estate. Its
  defects were reported upstream (#100, #101).

Proved on Windows and in the AlmaLinux 10 guest: `net`'s pipe tests, the
transport's tests, and the runtime's plane tests.

Provenance: the move is the owner's, agreed 2026-10-21; the place, `net`,
was his preference; the API and the folder are the assistant's, for the
owner to overrule.

## Amendment, 2026-10-22: the command is `xmip`

The owner, 2026-10-22: *Xmip CLI should be named just xmip, no need for the
'-cli' part of the name.* The amendment of 2026-09-18 named it `xmip-cli`,
by his word that day — *xmip-cli, not xmip: every System Process Xmip owns
matches xmip-\** — and he approved widening that rule rather than keeping
the name: every System Process Xmip owns is `xmip` or `xmip-<what>`
(ADR-0053, amendment 2026-10-22). An operator types `xmip health <scope>`,
`xmip certificate …`, `xmip mcp`; the repository and crate stay
`xmip-core-cli`. Nothing else about the command line changes.

## Amendment, 2026-10-22: the extension's shell is TypeScript, built without Node.js, and nothing it needs is fetched at run time

**But not JavaScript.** The owner, 2026-10-22, of the amendment of
2026-09-10's *TypeScript and JavaScript live in the extension*: *But not
JavaScript.* The extension's shell is TypeScript, and the estate holds no
hand-written JavaScript: the last file, the shell's `eslint.config.mjs`,
is `eslint.config.ts`, which ESLint 10 reads through Node's own type
stripping when its flag `unstable_native_nodejs_ts_config` is set
(<https://eslint.org/docs/latest/use/configure/configuration-files>), so no
third party's loader is added. What runs as JavaScript is the compiler's
output in `out/`, never tracked. `test/JavaScript.Test.ps1` fails on any
tracked `.js`, `.mjs` or `.cjs` file in the root or any submodule.

**Offline.** The owner, 2026-10-22: *We can't be dependent on resources
online, check that out!* Checked: the designer's webview allows nothing but
its own resources (`default-src 'none'`, its stylesheet and nonce-bound
modules from the extension's own folder), the extension contributes no JSON
or TOML schema and no schema-store association, reports no telemetry and
fetches nothing; `xmip-lsp` opens no connection, only the runtime's library
it is named. Everything it runs is in the extension's package.

**The runtime's library stays named**, `xmip.runtime.library` required
(the owner, 2026-10-22; ADR-0064, amendment of this date).

**Built without Node.js.** The owner, 2026-10-22, on the extension's build:
*Do it*; Node.js is never installed on his machine. So:

- **The compiler is TypeScript 7's native one**, the Go port, stable since
  2026-07-08, released as a program of its own for each platform outside
  npm (<https://github.com/microsoft/typescript-go/releases/tag/typescript/v7.0.2>,
  checked 2026-10-22). `prerequisite.toml`'s `[archive.typescript]` names
  each platform's asset and its SHA-256, and `Install-XmipPrerequisite
  -Install -IncludeOptional` fetches, verifies and unpacks it under
  `.local-work/tool` (`Install-XmipArchive.ps1`), no package manager and no
  Node. The Node.js prerequisite is deleted.
- **The VSIX is zipped by Xmip's own PowerShell**: `Build-XmipService
  -Extension VsCode` restores the packages the shell compiles against and
  runs with — the language client and its dependencies, the type
  declarations of VS Code and Node's API — from the extension's lock, each
  tarball refused unless it is the lock's integrity; compiles the shell and
  its webview with the native compiler; and writes `extension.vsixmanifest`,
  `[Content_Types].xml` and `extension/` into one zip
  (`Build-XmipExtension.ps1`). No vsce, no npm. The language client is the
  one JavaScript the package carries that is not the compiler's output: the
  extension host speaks the language server protocol through it.
- **Tests.** Every rule is the Rust server's and tested in Rust. The
  shell's lint and its tests run in its CI alone, where Node.js lives in a
  throwaway runner, and are reported there; the landing compiles the shell
  with the native compiler and says the rest SKIPPED, naming why. The tests
  are stubbed node tests, not `@vscode/test-electron`'s: moving them is the
  owner's to ask for, since they would download VS Code itself in the CI.
  The CI compiles with TypeScript 6, which the latest typescript-eslint
  still needs.
- **The shell is at its least**: it starts the server, registers what VS
  Code asks it to — the commands, the custom editor — asks the developer
  what the server sends it to ask, and carries the webview's messages; the
  webview draws. No rule is left in it to move.
- `test/JavaScript.Test.ps1` stays.

**Current as of 2026-10-22.** VS Code 1.143 is the latest release
(<https://code.visualstudio.com/updates>, updated 2026-10-19); the owner
runs 1.141.2, and `engines` stays `^1.140.0`, the newest `@types/vscode`
(1.140.0). `vscode-languageclient` 10.1.2 is the latest and asks VS Code
`^1.91.0`. TypeScript 7.0.2 is released, and the shell stays on 6.0: the
latest `typescript-eslint`, 8.72.0, accepts TypeScript below 6.1 alone
(<https://registry.npmjs.org/typescript-eslint/latest>), so the CI's lint
keeps TypeScript 6 and the build compiles with 7. ESLint is 10.13.0, the
latest.

## Amendment, 2026-10-22: the phone app is one act of the build

The owner, 2026-10-22: *I'm so eager to try it out, I want to see the
monitoring, how it works. Deploying to VMs, checking it out on a phone.*
`Xmip.Operations` built for `net11.0-android` since 2026-10-14, but nothing
made the file a person puts on a phone.

- **One act, on the existing build command** (the amendment of 2026-09-15:
  as few cmdlets as possible): `Build-XmipService -Remote Android -Package
  apk -Address <host:port>` builds the runtime's two Android libraries as
  before, then publishes `Xmip.Operations` for `net11.0-android`, Release,
  as one APK holding both, to
  `.local-work/package/<version>/xmip-operations-<version>-android.apk`
  (`Xmip/New-XmipApk.ps1`). `-Address` is the node the app follows: the
  shipped `Resources/Raw/xmip.gui.toml` with that `Address` written in is
  the document the APK carries (`XmipPhoneDocument`), so nobody edits the
  shipped one; left out, the shipped one goes as it is. `-Package apk` is
  refused for a site and without Android, and `-Address` without an APK,
  in words.
- **Signed for side-loading, not for a store.** No signing key is named,
  so the build signs with the Android SDK's debug key, made once per user.
  `adb install -r <apk>`, or the file copied to the phone and opened, puts
  it on a phone whose owner allowed installing from that source.
- **What it needs is optional and said** (`prerequisite.toml`, checked
  2026-10-22): the maui-android workload of the SDK's band, the Android
  SDK at the API level the workload targets (37), the NDK's latest LTS
  (r30, 30.0.16248370), and Microsoft's OpenJDK 21, the JDK Microsoft tests
  .NET for Android with — Java, optional, and not the Java event binding's
  JDK 27. Nothing in it is JavaScript or needs Node.js.
- **What only a phone proves.** The Android keeper (the Android Keystore,
  StrongBox where the phone has one) is built and has never run: on this
  machine no emulator and no system image is installed, so nothing ran on
  an emulator either, and none was installed for it. A real phone proves
  that the key is made in the keeper and never leaves it, that the
  Certificate page's request is signed by it, that a handshake with a
  node's operate listener is signed by it, and that the app follows a node
  over the phone's network — over the VPN the amendment of 2026-10-14 asks
  for, away from the site.

Provenance: the owner's words above. `-Package apk`, the debug key and the
file's name are the assistant's drafting, for the owner to overrule.

## Amendment, 2026-10-27: the SDK is release candidate 3

The owner, 2026-10-27, goes with .NET SDK 11.0.100-rc.3.26522.148, released
2026-10-25 with a go-live license, and it is the only SDK installed.
ADR-0021's rule, applied to the 2026-10-19 amendment's toolchain:

- **Every `global.json` names 11.0.100-rc.3.26522.148**, still the preview
  channel until GA on 10 November 2026.
- **The packages tied to the SDK follow it:** the ASP.NET Core and logging
  packages float on 11.0.0-rc.3, and the lock files are restored again.
- **The MAUI workloads are installed again.** Installing rc.3 removed every
  workload, which is what refused the gui module's build (NETSDK1147,
  maui-tizen). The rc.3 band's workload set, 11.0.100-rc.3.26524.4, still
  carries MAUI 11.0.0-rc.2.26505.5 and Android 37.2.0-rc.2.84.

Provenance: the owner's decision; the versions were read from Microsoft's
download page and `dotnet workload search version` on 2026-10-27.
