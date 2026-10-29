# Getting started with Xmip

This page takes you from nothing to a running Xmip node that carries a file
in to a file out, and that you can watch. Read it top to bottom the first
time. Every command runs in PowerShell 7 (`pwsh`) from the root of your
clone, on Windows, Linux and macOS alike, unless it says otherwise.

## 1. Welcome

Xmip is a Messaging and Integration Platform written in Rust. It connects
systems: it accepts data, keeps it safe, processes it and delivers it.
It is the replacement for BizTalk, MuleSoft and their kind: on-premises first,
and it runs without internet access.
It is not a hosted service, and nothing in it phones anywhere to work.
It is not finished either: there is no stable release yet, so you build it from
source.

If you know BizTalk, the words are familiar on purpose: Receive Locations, Send
Ports, promoted properties. The words Xmip uses are defined once, in
[terminology.md](terminology.md), and this page uses them the same way:

- **Stream**: the bytes that arrive at Xmip, from a file, a socket, a queue, a
  mailbox, a database or a device. A Stream belongs to the sender until Xmip
  accepts it.
- **Message**: accepted content, published into Xmip. Its content never changes
  and is written to disk before anything acts on it.
- **Receive Location**: where a Stream arrives, through one transport at one
  address, such as a folder or a port.
- **Subscription**: what picks a published Message up, by its context values:
  its Receive Location, its Receive Port, its promoted properties. The
  Message rushes through, unless it encounters an Xmip Work Process.
- **Journey**: metadata on a Message: the history of its travel to one
  Subscription, from its Publication to its delivery. It survives a restart and ends Completed,
  Failed or Dismissed.
- **Xmip Work Process**: the integration process you define, which works on a
  Message between arrival and delivery.
- **Send Port** and **Send Location**: a Send Port delivers a Message through
  its Send Locations; a Send Location is one physical destination, such as a
  folder or an address.
- **Xmip Application**: what a developer designs: its Receive Locations, Send
  Ports and Subscriptions, by name, bound to the nodes that run them.
- **Xmip Service**: `xmip-service`, the one program the operating system starts
  on a machine. It reads the configuration and runs everything else.
- **Node**: one Xmip Service and the configuration it runs by.
- **Cluster**: the nodes that share one configuration file, `xmip.toml`.

## 2. What you need

`prerequisite.toml` at the root of the estate decides what a machine needs, per
role and per operating system, and `Install-XmipPrerequisite` (section 3)
applies it. The versions below change often; **see
[prerequisite.toml](../prerequisite.toml)** for the current ones.

| You need | For | Version |
| --- | --- | --- |
| PowerShell, Core edition | all Xmip tooling | 7.6.7 or later; see prerequisite.toml |
| Git | cloning and submodules | 2.41 or later; see prerequisite.toml |
| PSToml and posh-git | reading Xmip's TOML; the prompt | current; see prerequisite.toml |
| Pester | the estate's tests | 6.0 or later; see prerequisite.toml |
| Rust (rustup, rustfmt, clippy) | the runtime and every module | stable; see prerequisite.toml |
| A linker | linking Rust | see prerequisite.toml |
| libclang (LLVM) | building the runtime store, RocksDB | see prerequisite.toml |
| A C++ compiler, libudev | Linux only | see prerequisite.toml |
| .NET SDK 11 | the command line, the PowerShell operator module, the GUIs | see prerequisite.toml |
| .NET MAUI workloads | the desktop GUI only | see prerequisite.toml |

The linker is Visual Studio Build Tools with the C++ workload on Windows, the
command line tools on macOS, and `build-essential` or `gcc` on Linux.
Every language but Rust is optional for Xmip itself: Java, Python and zig
build the event bindings, and TypeScript's native compiler the VS Code
extension, and a machine without them builds and runs a node all the same.
Node.js is needed nowhere on your machine.

Windows PowerShell 5.1 is a different product and is not supported. Install
PowerShell 7 first, in whichever way your system offers:

```sh
winget install Microsoft.PowerShell          # Windows
sudo snap install powershell --classic       # Linux, any distribution with snap
sudo apt-get install -y powershell           # Debian, Ubuntu; Microsoft package repository required
sudo dnf install -y powershell               # Fedora, RHEL; Microsoft package repository required
brew install powershell                      # macOS
```

Every command on this page runs inside `pwsh` and is the same on all three
platforms.

`rust-toolchain.toml` at the root picks the Rust compiler for you, so there is
no version to choose. RocksDB, the runtime store, is C++: every build links
one library compiled once per RocksDB version, which
`Install-XmipPrerequisite -Install` compiles the first time (section 3): twenty
minutes or more, depending on the machine.

## 3. Get the code

Xmip is an estate: one root repository, and every module in a repository of its
own, mounted under `module/` as a git submodule. On Windows, let Git write
paths longer than 260 characters first, once per machine: a module's
repository nests deep under the clone's `.git`, and a clone in a deep folder
fails with `Filename too long` without it.

```powershell
git config --global core.longpaths true      # Windows
```

Clone them all at once:

```powershell
git clone --recursive https://github.com/IlleNilsson/Xmip.git
Set-Location -Path Xmip
```

Run this once in each clone, so a push of the root can never point at a module
commit that was not pushed:

```powershell
git config push.recurseSubmodules check
```

After every later pull, bring the modules to the commits the root names:

```powershell
git submodule update --init --recursive
```

Load the estate's PowerShell module, link it into your module path, and let it
check your machine:

```powershell
Import-Module -Name ./Xmip/Xmip.psd1
Install-XmipModule
Install-XmipPrerequisite -Role developer
```

`Install-XmipPrerequisite` reports what is present, missing or outdated, and
fails while anything Xmip needs is missing or below its floor. An optional
toolchain that is absent is said `SKIPPED OPTIONAL`, and one that is older
than its floor `OUTDATED OPTIONAL`; neither fails anything. In a fresh clone
it says the RocksDB library is `MISSING`: nothing builds until it is there.
Run it again with `-Install` to install what is missing or outdated, and to
compile that library:

```powershell
Install-XmipPrerequisite -Role developer -Install
```

Add `-IncludeOptional` to both to take the optional toolchains too: the event
bindings' Java, Python and zig, and TypeScript's native compiler for the VS
Code extension, fetched and checked by its digest, under .local-work/tool.

It never elevates. Where a package needs administrator rights, it says
`NEEDS ELEVATION` and prints the command for you to run from an elevated Xmip
PowerShell Console; where a package manager cannot install one, it says
`MANUAL` and prints what to run instead.

In any later session, `Import-Module -Name Xmip` is enough.

A console of its own, in Windows Terminal: add a profile whose starting
directory is the clone and whose command line is

```text
pwsh -NoExit -Command "Import-Module -Name D:\Repos\Xmip\Xmip\Xmip.psd1"
```

Do not add `-NoProfile`. posh-git is imported by a PowerShell profile file,
`-NoProfile` skips every one of them, and the prompt then shows
`PS D:\Repos\Xmip>` with no repository state (the owner's console,
2026-09-18). Leave the Xmip status segment out of the command line and import
it in the session that wants it: a console holding that module holds its
assemblies, and a build into them fails until it is closed. That console is
`pwsh`, which `Get-Process -Name xmip-*` does not find.

## 4. Compile

### The Xmip Service, for a site

You do not build "all of Xmip". You build `xmip-service` for a **site**: one
deployment's choice of what it runs on and what it does. A site is a small TOML
file under `deploy/site/`, and it names three things:

- one **target**, what the program runs on: `device`, `edge`, `computer`,
  `server` or `hosted`;
- the node **roles** it serves: `receiving`, `processing`, `sending`,
  `executing` (all three in one process), `operational`, `monitoring`,
  `development` or `storage`;
- the **technologies** you chose, by repository name, such as
  `xmip-core-transport-file`.

This is `deploy/site/personal-computer.toml`, its comments left out:

```toml
description = "A person's computer: files and mail, one node of its own."

target = "computer"

roles = ["executing", "monitoring", "storage"]

technologies = [
  "xmip-core-transport-file",
  "xmip-core-transport-smtp",
  "xmip-core-transport-imap",
  "xmip-core-authorize-location",
]
```

It is one machine, so it keeps Xmip Storage itself: only a node with the
`storage` role stores. `xmip-core-authorize-location` is the `location`
policy, which admits at each Location the node starts what its configuration
says; without a policy nothing is permitted. The other example sites are
`b2b-exchange`, `factory-gateway`, `field-sensor` and `hospital-interface`.
What a target and a role bring is under `deploy/profile/`.

See what a site would build, without building anything:

```powershell
Build-XmipService -Site personal-computer -WhatIf
```

It answers the plan: the site, its target, roles and technologies, the cargo
features they make and the cargo command. `Unlinked` names a technology the
site chose that `xmip-service` has no feature for yet, here the mail
transports: said, not refused.

Then build it:

```powershell
Build-XmipService -Site personal-computer
```

Add `-CargoArgument '--release'` for an optimized build. A site of your own
is a file anywhere; give its path instead of a name:

```powershell
New-Item -ItemType Directory -Force -Path .local-work/site
Copy-Item -Path deploy/site/personal-computer.toml -Destination .local-work/site/my-computer.toml
Build-XmipService -Site ./.local-work/site/my-computer.toml -WhatIf
```

The build sets what is possible; the node's configuration picks from it when
the node starts. A technology the site does not name is not in the program, and
a Location that asks for it is refused when the node starts. A role or a
technology the target cannot have is refused before anything is built, and the
refusal says why.

The program lands in `target/debug/` at the root of the estate
(`target/release/` with `--release`), or under `CARGO_TARGET_DIR` when you set
it.

### The operator surfaces

You watch and operate Xmip from four surfaces, and all four read the same
library, so they cannot disagree: the command line `xmip`, the PowerShell
operator module, the web GUI and the desktop GUI. The command line and the
PowerShell module talk to Xmip through the runtime library, so build that
first:

```powershell
cargo build --manifest-path module/platform/runtime/Cargo.toml
```

The command line, `xmip`, is built with .NET today:

```powershell
dotnet build module/core/operation/cli/src/Xmip.Cli
```

The PowerShell operator module, which answers the same questions as objects:

```powershell
dotnet build module/core/operation/powershell/src/Xmip.PowerShell
```

The web GUI needs no build step of yours: `Start-XmipOperationWeb` builds it
before it starts it (section 6). The desktop GUI needs the MAUI workloads; on
Windows:

```powershell
dotnet run --project module/core/operation/gui/src/Xmip.Operations -f net11.0-windows10.0.19041.0
```

Build a .NET surface before you import or start it, never after in the same
session: a loaded module locks its files, and a build into them fails.

## 5. Configure and slice

### One file per cluster

A cluster is configured in one file, `xmip.toml`. What every node shares is
written once at the top; what concerns one node goes under `[nodes.<name>]`,
in the same sections. The node's value wins where both say one. Each node
declares its roles there; Xmip reads nothing into a name, and what a node does
is the roles it declares. Every section is described in the configure
module's
[cluster-configuration.md](../module/platform/configure/doc/cluster-configuration.md)
and [node-configuration.md](../module/platform/configure/doc/node-configuration.md).

Make a first cluster file: one node, offline as every node is unless it says
otherwise, keeping its own storage, and one Xmip Application that copies each
file dropped in one folder to another.

```powershell
New-Item -ItemType Directory -Force -Path .local-work/node/config, .local-work/node/in, .local-work/node/out
Set-Content -Path .local-work/node/config/xmip.toml -Value @'
[service]
name = "xmip"
cluster_name = "learning"

[[xmip_applications]]
name = "FileCopy"

[[xmip_applications.receive_ports]]
name = "In"

[[xmip_applications.receive_locations]]
name = "Drop"
receive_port = "In"
interaction = "data-transfer"
depth = "light"

[[xmip_applications.send_ports]]
name = "Out"

[[xmip_applications.subscriptions]]
id = "every-dropped-file"
destination = { send-port = "Out" }
filter = "xmip.transport.mechanism = 'circumstance'"

[nodes.first]
roles = "executing, storage"

[[nodes.first.applications]]
name = "FileCopy"

[[nodes.first.applications.receive_locations]]
name = "Drop"
node = "first"
address = ".local-work/node/in"
[nodes.first.applications.receive_locations.accept]
mechanism = ["circumstance"]

[[nodes.first.applications.send_ports]]
name = "Out"
node = "first"
address = ".local-work/node/out"
'@
```

`.local-work/` is git-ignored and is where the estate keeps what belongs to
this machine. `learning`, `first` and `FileCopy` are names chosen for this
page.

What it says, from the top:

- The `[[xmip_applications]]` section is the Xmip Application `FileCopy` as
  its developer designed it: a Receive Location `Drop`, a Send Port `Out`,
  and a Subscription that sends every Message whose Stream was accepted by
  `circumstance` to `Out`.
- `[nodes.first]` declares the node and its roles, `executing` (receive,
  process and send in one process) and `storage`.
- `[[nodes.first.applications]]` binds `FileCopy` to the node, and says where
  its Locations are: `Drop` reads the folder `.local-work/node/in`, and `Out`
  writes in the folder `.local-work/node/out`.
- Each Location is entered by its `address` alone: a path is a folder,
  the file transport's, as `file://` would be; `sftp://party@host/in`,
  `ftps://host/out` or `https://party.example/orders` would choose SFTP,
  FTPS or HTTPS, logging in as the user the address names. A Location
  starts unless it says `start = false`.
- `accept` is what a Receive Location takes; one that says nothing accepts
  nothing. A file dropped in a folder presents no identity of its own, and
  `circumstance` is the drop folder's implied identity: whoever may write in
  the folder.

A relative `address` is relative to where the node is started, which on this
page is the root of the clone.

### Slicing

A node never reads the cluster's file. It reads its **slice**: the shared
sections and its own, merged, written as `xmip-node.toml`. You edit only the
cluster's `xmip.toml`; a slice is always written for you and never edited by
hand.

Slice the node's configuration out of it with the Xmip Service you built:

```powershell
./target/debug/xmip-service --configuration .local-work/node/config/xmip.toml `
    --node first --slice |
    Set-Content -Path .local-work/node/config/xmip-node.toml
```

Ask for a node the file does not declare and the slice is refused, naming the
nodes it does declare.

### Validating

Check a file without starting anything. Both commands take a cluster's
`xmip.toml` or a node's slice; a cluster's file is checked node by node, and
each problem says which node it belongs to.

```powershell
dotnet run --project module/core/operation/cli/src/Xmip.Cli -- `
    validate .local-work/node/config/xmip.toml
```

Or, as objects, from the PowerShell operator module:

```powershell
$operator = 'module/core/operation/powershell/src/Xmip.PowerShell/bin/Debug/net10.0'
Import-Module -Name "./$operator/Xmip.PowerShell.psd1"
Test-XmipNodeConfiguration -Path .local-work/node/config/xmip.toml
```

The VS Code extension and the desktop GUI validate through the same call, as
you type.

### Editing in VS Code

The VS Code extension edits the cluster's `xmip.toml` with suggestions,
lookups, fixes and the cluster designer, every answer the runtime's. It
needs two settings, and the runtime's library is one of them, always: the
extension's language server looks for no runtime of its own (ADR-0064,
amendment 2026-10-22). Build the server and the runtime, then name both in
your VS Code settings, as full paths:

```powershell
cargo build --manifest-path module/platform/runtime/Cargo.toml
cargo build --manifest-path module/core/operation/gui/vscode/Cargo.toml
Build-XmipService -Extension VsCode
code --install-extension .local-work/package/vscode/xmip-0.1.0.vsix
```

`Build-XmipService -Extension VsCode` compiles the extension's shell with
TypeScript's native compiler and writes its VSIX, with no Node.js.

```json
{
  "xmip.server.path": "<estate>/module/core/operation/gui/vscode/target/debug/xmip-lsp.exe",
  "xmip.runtime.library": "<estate>/module/platform/runtime/target/debug/xmip_core_runtime.dll"
}
```

`<estate>` is the full path of your clone. On Linux the library is
`libxmip_core_runtime.so` and the server `xmip-lsp`, on macOS
`libxmip_core_runtime.dylib`. Left out, every validation says where to
point it.

## 6. In practice

### Carry a file in to a file out

Start the node in this Xmip PowerShell Console. It runs until you press
Ctrl+C:

```powershell
./target/debug/xmip-service --configuration .local-work/node/config/xmip-node.toml --console
```

On Linux and macOS, the folder of the node's local endpoint must exist and be
yours first: `/run/xmip` on Linux, `/var/run/xmip` on macOS.

It says what it starts, and `accepts work` when it is ready. From a second
Xmip PowerShell Console, in the root of the clone, drop a file in:

```powershell
Set-Content -Path .local-work/node/order.edi -Value 'ISA*00*first-order*'
Move-Item -Path .local-work/node/order.edi -Destination .local-work/node/in/
```

A file is written beside the folder and moved in, as a producer that means a
file to be whole drops it. The file system tells the node the moment a file
lands in its drop folder; it lists the folder then and takes the file once no
writer holds it open, so within a few milliseconds it is gone from `in` and
is in `out` under the same name, whole. A file still being written is left
until its writer closes it. On Linux and macOS, where the system does not say
whether a writer holds a file, the node takes it once two listings agree it
is unchanged, the second at the next change or at its recovery sweep,
`[tuning] receive_sweep`, a second by default:

```powershell
Get-ChildItem -Path .local-work/node/out
Get-Content -Path .local-work/node/out/order.edi
```

On its way it was received, accepted by `circumstance`, admitted by the
`location` policy, written to Xmip Storage as a Message, picked up by the
Subscription and sent by the Send Port `Out`. The node audits each step.

The node keeps its data beside its configuration, in `.local-work/node/data`.
It publishes what it says of itself to `.local-work/node/data/snapshot.toml`
four times a second, and serves a local endpoint, `xmip-first`, that only this
machine reaches. From the second Xmip PowerShell Console, watch it:

```powershell
dotnet run --project module/core/operation/cli/src/Xmip.Cli -- `
    show xmip:///learning --local xmip-first
dotnet run --project module/core/operation/cli/src/Xmip.Cli -- `
    measure xmip:///learning --local xmip-first
Import-Module -Name Xmip
$operator = 'module/core/operation/powershell/src/Xmip.PowerShell/bin/Debug/net10.0'
Import-Module -Name "./$operator/Xmip.PowerShell.psd1"
Get-XmipHealth -Scope xmip:///learning -Local xmip-first
```

`show` says the scope's mood and its worst leaf; `measure` counts Streams,
Messages and Journeys: one file is one Stream, one Message and one Journey.
A dash is a figure the node does not count yet, bytes among them. Add
`--json` for one JSON document, or `--follow` with `health` or `measure` to
keep answering as things change. `Get-XmipHealth` answers every leaf: the
node, each module it loaded, the Receive Location `Drop`, the Subscription
and the Send Port `Out`, with what each has done.

The web GUI reads the node's snapshot:

```powershell
Start-XmipOperationWeb -Snapshot .local-work/node/data/snapshot.toml
```

Open <http://127.0.0.1:5087> in a Web Browser tab. The Monitor view follows
receive, process and send as the node moves; Configuration shows the tree of
the whole cluster, and Topology how it communicates.

Every leaf has a mood: Fine, Paused, Working, Stressed, Exhausted or Done. A
scope above it is Holding when something beneath needs attention, and it
carries that leaf and its evidence, so you always drill toward the cause.

When you are done, stop the web GUI, then press Ctrl+C in the Xmip PowerShell
Console the node runs in. Nothing in Xmip starts on its own, and nothing
keeps running unless you started it:

```powershell
Stop-XmipOperationWeb
```

From here, add Receive Locations, Send Locations and Subscriptions to the
cluster's `xmip.toml`, validate it, slice it again, and restart the node. A
changed slice takes effect when the node starts again.

To run the node as a service that starts with the machine, see
[the portable archive's README](../deploy/package/archive/README.md) and
`Get-Help -Name Build-XmipService -Full` for its `-Package` parameter.

### Watch Messages move, in the Playground

The **Xmip Playground** is Xmip's own rehearsal. It starts a cluster of nodes
as processes on your machine and carries payloads through them, round after
round, over every transport and content contract, the file transport among
them. It needs no network and no other software.

Start a cluster called `C1` with three nodes, one per stage: receive, process,
send.

```powershell
Start-XmipTest -Suite Core.Playground -Cluster C1 -Test RoundTrip -Nodes R1, P1, S1 `
    -NodeRole @{ R1 = 'receiving'; P1 = 'processing'; S1 = 'sending' } -OnlineNodes R1
```

`-NodeRole` states each node's roles — receiving, processing and sending one
stage each, or `executing` for all three in one process, the low-latency
choice ([ADR-0056](decision/ADR-0056-a-node-declares-what-it-can-do.md)).
Omit `-Nodes` and the run takes every node of the Playground's own cluster
file, `test/core/playground/configuration/xmip.toml`, whose `[nodes.R1]
roles = "receiving"` and so on cover the whole path; a node you name with no
`-NodeRole` takes the roles that file declares for it. A node
given no role declares none and runs the shared-directory tests whole, which
`Start-XmipTest` says in words before it starts anything. `-OnlineNodes R1`
records that `R1` may assume a route to the internet and the others may not
(ADR-0045): it is the receiving edge, the node that may obtain its server
certificate over ACME from a public authority (ADR-0033, ADR-0034;
[built, not in the assembled service](architecture/estate-map.md#certificate-provisioning)).
The switch permits; nothing in the Playground reaches out.

It returns at once and builds in the background. Ask how it is going:

```powershell
Get-XmipTestStatus
```

It says `building` until the nodes start, then `running`, or `FAILED` with the
first error. The names `C1`, `R1`, `P1` and `S1` are yours to choose; this page
uses `C1` because the surfaces in a fresh clone are set to follow it.

The Playground injects faults on purpose, of the kinds real integrations
suffer: a reset connection, an unresolved host, content that fails its
contract. Expect the cluster to be Holding and some leaves Done; the file
transport is the one path it keeps fault-free.

Watch it on each surface:

```powershell
Get-XmipTestResult -Path .local-work/playground/C1-snapshot.toml -Worst
Get-XmipHealth -Scope xmip:///C1
Get-XmipScope -Scope xmip:///C1/*
dotnet run --project module/core/operation/cli/src/Xmip.Cli -- show xmip:///C1
dotnet run --project module/core/operation/cli/src/Xmip.Cli -- measure xmip:///C1
Start-XmipOperationWeb -Snapshot .local-work/playground/C1-snapshot.toml
```

The web GUI at <http://127.0.0.1:5087> opens on the Monitor view, the board
that follows receive, process and send as the cluster moves. Beside it are
Configuration, the classic tree of the whole cluster, and Topology, the
cluster's own communication.

A roll is one cluster's test, and the cluster is a process the roll spawns
(ADR-0052, amendment 2026-09-19); two rolls are two clusters side by side.
Start a second before stopping the first, and one web host serves them both;
the views say which cluster they are on and move between them (ADR-0052,
amendment 2026-09-20):

```powershell
Start-XmipTest -Suite Core.Playground -Cluster C2 -Test RoundTrip -Nodes R1, P1 `
    -NodeRole @{ R1 = 'receiving'; P1 = 'processing,sending' } -OnlineNodes R1
Get-XmipTestStatus | Start-XmipOperationWeb
```

`P1` carries two roles because `-NodeRole` says so, not because of its name,
and `C2`'s `R1` is not `C1`'s: each cluster names its own nodes, and Xmip
reads none of those names (the owner, 2026-09-20: *Rn, Pn and Sn are
arbitrary node names*, and the same of clusters).

The prompt follows one cluster and says how many it is not showing —
`[C2+1 ≡ R:1.2K/s P:240/s S:238/s]`. The letters are the three stages of the
message path, the one place in Xmip where a letter means anything, and each
is what that stage moves per second, not a total since the roll began:
`R:0/s` says stalled, which a rising total never can, and a dash says there
has been only one publication so far. T and F are counts, on the line only
when above zero. `xmip --snapshot <path>` names which cluster the
executable reads; it answers one cluster per invocation and shows totals,
because a single reading has no interval to take a rate over.

Every System Process Xmip owns is named `xmip-<what>` and declares its name,
its location and its purpose, test or runtime (ADR-0053). A Playground
process says which cluster and which node it is — `xmip-playground-C1-roll`,
`xmip-playground-C1-cluster`, `xmip-playground-C1-node-R1` (amendment
2026-09-20). `Get-XmipProcess` lists them with what they said, and one line
stops every one of them, whatever started it:

```powershell
Get-Process -Name xmip-* | Stop-Process -Force
```

Stop when you are done:

```powershell
Stop-XmipTest
Stop-XmipOperationWeb
```

### The same run on machines of their own

Everything above is test level 1: one computer, every node a process the run
spawned. Where the run's nodes include one declaring the Storage role —
every node of the Playground's file, when `-Nodes` is left out — each is a
process of `xmip-service`, the build `Start-XmipTest` makes beside the
Playground: D1 and D2 keep Xmip Storage, the primary and its standby, and
every other node reaches them over Xmip's mutual TLS on loopback, with a
certificate from the Playground's authority, the one the web GUI is served
under, kept in .local-work/playground/authority across runs. The rig drops files into their Receive
Locations and reads what their Send Ports write, and `xmip:///C1/carried`
says whether every file dropped arrived (ADR-0028, amendment 2026-10-22).
Where none declares the Storage role, as with `-Nodes R1, P1, S1` above,
every node is simulated.

```powershell
Start-XmipTest -Suite Core.Playground -Cluster C1
Get-XmipHealth -Scope xmip:///C1/carried
Get-XmipHealth -Scope xmip:///C1/node/R1/storage
```

`xmip:///C1/node/R1/storage` says which Storage node R1 reaches and whether
it answered, and D1's which it is, the primary or a standby.

At test level 2 the same cluster file runs with
real nodes — `xmip-service` on machines of their own — and the same
scenarios (ADR-0028, amendment 2026-10-21). The templates under `deploy/dsc`
make the machines and put the file's nodes on them, Windows and AlmaLinux
alike: `deploy/dsc/msdsc/hyperv/README.md` for the virtual machines on
Hyper-V, then `deploy/dsc/msdsc/environment/README.md`, or
`deploy/dsc/ansible/README.md` for the same in Ansible, for what runs inside
them. Each node's slice binds every Receive Location and Send Port of the
file, placed over the environment's nodes by their roles, on the Parties'
far end: SFTP the Playground serves on your computer, port 7422, each
Location a user of its own there (ADR-0028, amendment 2026-10-22). A
`-Cluster` or `-Nodes` name that resolves is a real node, asked with the
operator certificate `-Certificate` names; a name that answers as its node
is real and never spawned, one that does not answer is REFUSED by name, one
that does not resolve is simulated. The first lines of the run, its board
and `Get-XmipTestStatus` say which nodes are real. On its machine each node
presents the certificate its environment gave it, `tls/node.pem`, on its
operate listener and to the Storage nodes, which serve on port 7443 — the
port a Storage node's `xmip-service --listening` says, so the environment
opens it.

The whole way, in order, with Microsoft DSC. **E** marks a step that needs
an elevated Xmip PowerShell Console; every other step runs in an ordinary
one. Each README says each step in full.

1. **E** Hyper-V, DSC and the two DSC modules, then restart the computer
   (`deploy/dsc/msdsc/hyperv/README.md`, *Before the first run*).
2. The Windows machines' Administrator credential, the AlmaLinux machines'
   SSH key and the Hyper-V parameters (the same section).
3. **E** The machines: `dsc config --parameters-file
   D:\Repos\Xmip\.local-work\hyperv\environment.parameters.yaml set --file
   D:\Repos\Xmip\deploy\dsc\msdsc\hyperv\environment.example.dsc.yaml`, and
   again once they have installed (*Running it*).
4. **E** On each machine once, as its Administrator or with sudo:
   PowerShell 7.6 and DSC 3.2 (`deploy/dsc/msdsc/environment/README.md`,
   *Before the first run*).
5. **E** On your computer once: WinRM's trusted hosts, the names, and the
   firewall opening that lets the machines reach the far end,
   `New-NetFirewallRule -DisplayName 'Xmip Playground, the Parties'' far
   end' -Direction Inbound -Protocol TCP -LocalPort 7422 -RemoteAddress
   10.77.0.0/24 -Action Allow` (the same section).
6. The packages, the cluster's authority and each node's certificate, and
   the environment's parameters, `linuxAccount` and the version written in
   (the same section).
7. The nodes: `dsc config --parameters-file
   D:\Repos\Xmip\.local-work\environment\environment.parameters.yaml test
   --file D:\Repos\Xmip\deploy\dsc\msdsc\environment\environment.example.dsc.yaml`,
   then the same with `set` (*Running it*). Each document runs itself
   elevated on its machine; on yours it needs none.
8. The tester's operator certificate (*Running it*), and the run against
   the machines:

```powershell
Start-XmipTest -Suite Core.Playground -Cluster C1 -Nodes R1, S1, P1, L1, D1 `
    -Certificate D:\Repos\Xmip\.local-work\environment\tester
Get-XmipTestStatus
Get-XmipHealth -Scope xmip:///C1/carried
Get-XmipTestStatus | Start-XmipOperationWeb
```

Type exactly the nodes the environment maps: the Playground places the
Locations over them as the machines did. It drops a file into every
Receive Location's directory on the far end each round; a real receiving
node fetches it, D1 keeps it, a real sending node puts it back under its
name, and `xmip:///C1/carried` counts what arrived and how long it took.
The Web Browser tab at <https://127.0.0.1:5087> follows them on the
Monitor.

With Ansible, step 7 is `ansible-playbook` from the WSL guest
(`deploy/dsc/ansible/README.md`); the rest are the same.

Two things wait on the owner of the estate: the Windows machines take the
MSI, which WiX 7 builds only once its license is accepted, and the
AlmaLinux machines the `.rpm`, which is not built while builds are
Windows-only (`deploy/package/README.md`). A machine without its package
runs no node.

### The operator app on a phone

The desktop host is the phone app too (ADR-0014, amendment 2026-10-14): on
Android it follows one node over its operate listener and observes it. One
command builds the app, the runtime's two Android libraries first, and
`-Address` names the node it follows — here D1 on the machines above, a
network the phone must reach, over the Wi-Fi of a host that routes to it or
a VPN:

```powershell
Build-XmipService -Remote Android -Package apk -Address 10.77.0.53:7401
```

It needs the maui-android workload, the Android SDK and NDK and
Microsoft's OpenJDK 21, each optional in `prerequisite.toml`, which says
how to install each; none needs Node.js. The APK lands at
`.local-work/package/<version>/xmip-operations-<version>-android.apk`,
signed with the Android SDK's debug key: for side-loading, not for a
store. Put it on a phone with USB debugging on:

```powershell
adb install -r .local-work/package/0.1.1/xmip-operations-0.1.1-android.apk
```

or copy the file to the phone and open it there, allowing installs from
that source. On the phone it reads the node it follows from the document
shipped inside the app, the one `-Address` wrote, and makes its key in
the Android Keystore on its Certificate page; the cluster's authority signs
the request it shares (ADR-0034, amendment 2026-10-15). The keeper has not
run on a phone yet: the first phone that runs it proves it (ADR-0014,
amendment 2026-10-22).

### The cluster's authority on the premises

Xmip runs with no internet (ADR-0045), and its certificates still come by
ACME: the cluster's own authority is the premises' own ACME service
(ADR-0034, amendment 2026-10-22). Nothing in Xmip ships an authority for
production; the authority is yours, kept in a folder you choose, and an
`acme` source may name any other directory on the premises instead. Set it
up once, on the machine that will keep it:

```powershell
xmip certificate --authority D:\Xmip\authority --cluster C1 --publish http://ca.xmip.test:8080
```

or `New-XmipCertificate -Authority D:\Xmip\authority -Cluster C1 -Publish
http://ca.xmip.test:8080`. It answers with the authority's SHA-256: the
fingerprint every machine that comes to trust it compares by another way.
The node that keeps it serves ACME where its configuration says, and its
revocation list and certificate over plain HTTP at the address you
published, the one every certificate it signs names:

```toml
[provision.node]
source = "xmip-core-provision-internal-ca"
names = "ca.xmip.test"
lifetime = "2160h"                       # ninety days
authority_lifetime = "87600h"
authority = "D:/Xmip/authority"
serve = "0.0.0.0:14000"                  # ACME: https://ca.xmip.test:14000/directory
publish = "0.0.0.0:8080"                 # /crl and /authority.cer, plain HTTP
published_at = "http://ca.xmip.test:8080"
```

`xmip-service --listening` names both ports, so the environment opens them.
Any standard ACME client on the premises uses it — lego, the Go client, is
proved against it with renewal information (RFC 9773) and revocation:

```powershell
$env:LEGO_CA_CERTIFICATES = 'D:\Xmip\authority.crt'   # --export --format pem wrote it
lego run --server https://ca.xmip.test:14000/directory --accept-tos `
    --email operator@example.org --domains web1.xmip.test --http
lego certificates revoke --server https://ca.xmip.test:14000/directory `
    --cert.name web1.xmip.test --reason 4
```

Inspect the authority, revoke from it, hand its anchor out and back it up:

```powershell
xmip certificate --inspect D:\Xmip\authority
xmip certificate --revoke 5B8E9CC6D36BF3DB --authority D:\Xmip\authority --reason keyCompromise
xmip certificate --export D:\Xmip\authority.cer --authority D:\Xmip\authority --format der
xmip certificate --export D:\Xmip\authority.crt --authority D:\Xmip\authority --format pem
xmip certificate --backup E:\backup\authority --authority D:\Xmip\authority
```

`Get-XmipCertificate -Authority D:\Xmip\authority` does the same, with
`-Revoke`, `-Export` and `-Backup`, and so does the desktop's Authority page.
The backup holds the authority's key: keep it as the key is kept.

**Handing the anchor out.** Each of these changes what a machine trusts, and
is that machine's owner's to run; Xmip runs none of them.

| where | how |
| --- | --- |
| Windows, one user | `certutil -user -addstore Root authority.cer`, or `Import-Certificate -FilePath authority.cer -CertStoreLocation Cert:\CurrentUser\Root` |
| Windows, the machine | the same into `Cert:\LocalMachine\Root`, in an elevated prompt |
| AlmaLinux, RHEL | copy `authority.crt` into `/etc/pki/ca-trust/source/anchors/`, then `update-ca-trust` |
| Debian, Ubuntu | copy `authority.crt` into `/usr/local/share/ca-certificates/`, then `update-ca-certificates` |
| Chrome, Edge on Windows | the Windows store above |
| Firefox | the enterprise policy `Certificates`, `Install` naming the file — on Linux the one way, since `ImportEnterpriseRoots` reads the Windows and macOS stores alone |
| Chrome on Linux | `certutil -d sql:$HOME/.local/share/pki/nssdb -A -t "C,," -n "Xmip C1" -i authority.crt` |

**A node no network reaches the authority from.** Its certificate is
carried by hand, each step checking the file it is given and audited:

```powershell
# On the node: a fresh key that stays, and a request to carry.
xmip certificate --node R1 --names R1.xmip.test --out D:\Xmip\tls
# Where the authority is kept: its signature, its names, ninety days.
xmip certificate E:\R1\node.csr --authority D:\Xmip\authority --names R1,R1.xmip.test --out E:\R1\node.pem
# Back on the node: every signature, the key, the names, the anchor; then it is used.
xmip certificate E:\R1\node.pem --import D:\Xmip\tls
```

`New-XmipCertificate -Node R1 -Name R1.xmip.test -Path D:\Xmip\tls`,
`New-XmipCertificate -Request E:\R1\node.csr -Authority D:\Xmip\authority`
and `New-XmipCertificate -Import E:\R1\node.pem -Path D:\Xmip\tls` are the
same three. The node says when its next request is due: at
`xmip:///C1/node/R1/certificate/operate`, Stressed and *renewal due* from two
thirds of its ninety days, which `xmip certificate --inspect
D:\Xmip\tls\node.pem` says too.

### Decompress what a Party sends, with a standard unit

Xmip's standard units are there out of the box, at receive, at process and
at send: Compression, CharacterEncoding, TransferEncoding,
TextNormalization, Encryption and Signature prepare a Stream; Validate
holds it to its format or a contract; Promote and Demote read and write a
value; Convert, Stylesheet and Script transform it. They are the built-in
module `xmip`, so a step names one by module and unit, and nothing declares
the module itself. If the files dropped at `Drop` above arrive gzipped,
the node decompresses them at the Receive Location, before a Message
exists — a step on the node, attached to the Location by its name. Add
the step to the node in `.local-work/node/config/xmip.toml`:

```toml
[[nodes.first.preparation_steps]]
name     = "Unzip"
module   = "xmip"
unit     = "Compression"
settings = { format = "gzip" }
```

and name it in `Drop`'s binding, beside its `address`:

```toml
prepare = ["Unzip"]
```

At receive, Compression decompresses; the same step on a Send Location
compresses, and in a Work Process it says which with `direction`. Check it
as every surface does:

```powershell
Test-XmipNodeConfiguration -Path .local-work/node/config/xmip.toml
```

A step's settings are held to what its unit declares, so `format = "rar"`
is refused in words. Running the steps is decided and not built: a node
still refuses to start a Location that attaches one, and says so.

## 7. Where next

- [terminology.md](terminology.md): every word Xmip uses, defined once.
- [decision/README.md](decision/README.md): the architecture decision records,
  indexed by subject. Start with ADR-0014 (the operator surfaces), ADR-0015
  (packaging and sites) and ADR-0031 (configuration).
- [architecture/](architecture/): the models. `runtime-model.md` is what Xmip
  does at runtime, `deployment-model.md` nodes, roles and installation,
  `observability-model.md` audit and observation, `repository-model.md` and
  `module-model.md` how the estate is built.
- [architecture/estate-map.md](architecture/estate-map.md): what of each
  capability is built today, and what is decided and not built yet.
- [The README](../README.md): the full guide, per reader, from operator to
  developer.
- [CONTRIBUTING.md](../CONTRIBUTING.md): how work is done and lands in the
  estate, before you change anything.
- `Get-Help -Name Start-XmipTest -Full`: every cmdlet documents every parameter.
