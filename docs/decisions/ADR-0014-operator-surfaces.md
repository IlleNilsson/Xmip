# ADR-0014: The operator surfaces and their language

## Status

Accepted. Implementation follows in separate reviewed changes.

## In brief

- Theme: Operating Xmip
- Subject: The operator surfaces and their language
- Name: The operator surfaces
- Order: 1
- Concepts: ABI, the interface into Xmip; Audit, the durable record; Blazor, .NET, the GUI; CLI, the `xmip` executable; Observation, and why it is lossy; Remote operation, WinRM, SSH

Rust is the language of the runtime; everything in the message path is Rust. The
operator surfaces are .NET 11 — the `xmip` executable, the PowerShell module, a
MAUI desktop GUI and a Blazor web GUI.

**All four P/Invoke the same C ABI, and none of them goes through another
surface to get there.** `xmip-core-abi` is the interface *into* Xmip —
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
`audit` are the durable records. Remote operation rides existing shell remoting
— PowerShell Remoting over WinRM or SSH, and the CLI over SSH. Xmip defines no
bespoke remote control protocol.

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

`crates/xmip-cli/src/main.rs` was distributed to `modules/operations/cli` on
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
record authorising it. It is now `maturity = "deprecated"`.

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
its own message model, with identity, authorisation, audit and Journeys applying
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

This is worth more than the convenience. Remoting brings its own authentication with it, Kerberos and Active Directory on one path and SSH keys on the other, both already understood and already permitted inside the organisations Xmip is aimed at. Xmip does not have to design authentication for its own control plane, and a control plane with hand-rolled authentication is exactly the kind of thing that fails an enterprise security review.

Streaming survives the crossing. A remoting session returns objects as they are produced rather than at the end, and SSH streams standard output, so a follow mode works remotely without becoming a different mechanism.

## The .NET version

Version 11 reaches general availability on 10 November 2026 and is a Standard Term Support release, supported until 9 November 2028. Version 10 is the current Long Term Support release and is supported until November 2028, so the LTS window ends later than the STS one.

That tradeoff was put and 11 was chosen. The consequence is recorded rather than argued: neither operator surface can ship on a released runtime before November 2026, and both will need to move to the next LTS sooner than an equivalent version 10 codebase would.

The Xmip runtime is unaffected. It is Rust and does not wait for a .NET release.

## Consequences

ExecutionHostKind::DotNet already exists in contracts.rs. .NET was already a declared execution host, so nothing in the module model changes to accommodate this.

cli becomes the specification of what an operator can do. Every capability the executable or the web solution needs must be expressible as a command first. That is a real constraint on the CLI and a deliberate one. It is what stops the two surfaces drifting apart the way the BizTalk console and its PowerShell provider did.

It also means a capability is testable before any user interface exists.

A web solution that can remote into every node holds credentials that reach the whole cluster. That makes the web host a high-value target and it must be treated as one: its own identity rather than a shared operator account, least privilege on each node, and every remote invocation audited through xmip-core-audit like any other operator action. Inheriting mature authentication does not mean inheriting a safe deployment.

## The command

Clauses 8 and 9. Bash cannot call a C ABI. It can execute a binary and read what comes back, and that is the whole of it. PowerShell can P/Invoke into a native library, so it could reach xmip-core-abi directly, and that is precisely why it must not. A PowerShell surface with a path bash does not have would be able to express things bash cannot, and the two would drift. That is the BizTalk Administration Console and its PowerShell provider again, for the same reason.

So one binary, and both shells drive it.

The cost is that PowerShell operators are handed text where they expect objects. Clause 10 pays it: the text is JSON, and the module turns it into objects on arrival. This is how az, gh and kubectl settle the same argument, and it keeps one code path rather than two.

The binary is called xmip. The repository and the crate are xmip-core-cli under ADR-0011, but ADR-0011 governs module names, not the name of a command a person types at a prompt. A command is one word.

## The GUI

Clause 12. Blazor is what turns two requirements into one. A Razor class library holds the components, Blazor Hybrid hosts them in the desktop application and server-side Blazor hosts them on the web. The two are then literally the same screens. They cannot drift, because there is nothing to keep in step.

MAUI hosts the desktop application because every other decision in Xmip is cross-platform and this one should not be the exception: PowerShell Core runs everywhere, ADR-0015 packages for Windows, Linux and macOS, and the command is a Rust binary. WPF with a BlazorWebView is the better-trodden path and it is Windows only, which would make the desktop application the one surface an operator on Linux cannot run.

The render mode is not a preference. A web solution has to reach many nodes; reaching them means PowerShell Remoting or SSH; and a browser sandbox can do neither. WebAssembly cannot satisfy clause 6, so the web solution runs server-side. That is a constraint falling out of an earlier decision rather than a fresh choice.

gui joins abi, cli and powershell in surfaceModules. A provider may ship xmip-acme-gui, on the same terms as the other three: their licence, their support, no approval.

## Amendment, 2026-08-30: the SDK and the target framework are two rulings

Stated by the owner when a net11.0 build of the PowerShell module met the shell
it exists for: **PowerShell 7.6.5 hosts .NET 10, and that is fine. C# is
compiled with the .NET 11 preview SDK.**

The 2026-08-26 amendment said ".NET 11" and meant one thing; it is two. The
*toolchain* is the .NET 11 preview SDK, estate-wide, pinned in every
`global.json`. The *target framework* is owned by whoever loads the assembly:
an executable owns its runtime and targets net11.0 — the cli — while a binary
PowerShell module loads into pwsh and targets what the platform pwsh
(ADR-0021, 7.6.5) hosts, which is net10.0 today and follows pwsh upward.

Found the honest way: the module was built net11.0 to the letter of the earlier
amendment, and `Import-Module` refused it. A rule that produces an assembly its
own platform cannot load was a rule stated with one word too few.

## Open

**Backpressure.** Clause 10 settles what a follow mode emits and says nothing about what happens when a consumer cannot keep up. Dropping is consistent with clause 5, since observation is lossy by design and says so. Which samples are dropped, and whether the consumer is told it missed some, is not settled. A monitor that silently skips is worse than one that admits a gap.

