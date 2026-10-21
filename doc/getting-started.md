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
- **Subscription**: what picks a published Message up. Each matching
  Subscription opens one Journey.
- **Journey**: one durable line of work for a Message, from its Subscription to
  its delivery. It survives a restart and ends Completed, Failed or Dismissed.
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
| Git | cloning and submodules | 2.40 or later; see prerequisite.toml |
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
Every language but Rust is optional for Xmip itself: Java, Python, Node and
zig build the event bindings and the VS Code extension, and a machine without
them builds and runs a node all the same.

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
bindings' Java, Python and zig, and Node for the VS Code extension.

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
library, so they cannot disagree: the command line `xmip-cli`, the PowerShell
operator module, the web GUI and the desktop GUI. The command line and the
PowerShell module talk to Xmip through the runtime library, so build that
first:

```powershell
cargo build --manifest-path module/platform/runtime/Cargo.toml
```

The command line, `xmip-cli`, is built with .NET today:

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
start = true
transport = "xmip-core-transport-file"
address = ".local-work/node/in"
[nodes.first.applications.receive_locations.accept]
mechanism = ["circumstance"]

[[nodes.first.applications.send_ports]]
name = "Out"
node = "first"
start = true
transport = "xmip-core-transport-file"
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
- `start = true` starts a Location; only `true` does.
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
when above zero. `xmip-cli --snapshot <path>` names which cluster the
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

Everything above is test level 1: one computer, every node simulated, a
process the run spawned. At test level 2 the same cluster file runs with
real nodes — `xmip-service` on machines of their own — and the same
scenarios (ADR-0028, amendment 2026-10-21). The templates under `deploy/dsc`
make the machines and put the file's nodes on them, Windows and AlmaLinux
alike: `deploy/dsc/msdsc/hyperv/README.md` for the virtual machines on
Hyper-V, then `deploy/dsc/msdsc/environment/README.md`, or
`deploy/dsc/ansible/README.md` for the same in Ansible, for what runs inside
them. Then a `-Cluster` or `-Nodes` name that resolves is a real node, asked
with the operator certificate `-Certificate` names:

```powershell
Start-XmipTest -Suite Core.Playground -Cluster C1 -Nodes R1, R2, P1, S1, S2, L1, O1, D1, D2 `
    -Certificate D:\Repos\Xmip\.local-work\environment\tester
```

A name that answers as its node is real and never spawned; one that does not
answer is REFUSED by name; one that does not resolve is simulated as at
level 1. The first lines of the run, its board and `Get-XmipTestStatus` say
which nodes are real.

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
