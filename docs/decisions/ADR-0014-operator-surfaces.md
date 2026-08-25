# ADR-0014: The operator surfaces and their language

## Status

Accepted. Implementation follows in separate reviewed changes.

## Context

Xmip has a runtime and no way to look at it. The manifest already declares the four observation capabilities, xmip-core-event, xmip-core-observe, xmip-core-report and xmip-core-audit, and the three surfaces, abi, cli and powershell. What it does not have is anything an operator sits in front of.

Two are required: an executable, and a web solution. Both configure, operate, report and observe.

Monitoring is not a fifth verb. It is xmip-core-observe, which was already declared and is only now getting a surface.

BizTalk is the warning. Its Administration Console was simultaneously the live monitor and the historical query tool, reading the same tracking tables in the same SQL Server instance the runtime depended on. Turning tracking on cost throughput, so the standard field advice became to turn tracking off in production. A monitoring system that must be disabled to go fast is not a monitoring system.

The same console reached into the MessageBox directly. That is why parts of it were never scriptable, and why what the console could do and what the PowerShell provider could do drifted apart.

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

## Open

**Backpressure.** Clause 10 settles what a follow mode emits and says nothing about what happens when a consumer cannot keep up. Dropping is consistent with clause 5, since observation is lossy by design and says so. Which samples are dropped, and whether the consumer is told it missed some, is not settled. A monitor that silently skips is worse than one that admits a gap.

