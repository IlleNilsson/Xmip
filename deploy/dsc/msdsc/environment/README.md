# An Xmip environment's machines, with Microsoft DSC v3

A template for what runs inside an Xmip environment's machines once they
are installed: the names of the cluster and its nodes on the DNS server, and
on each node machine — Windows and AlmaLinux alike — its node. It is the
part the Hyper-V template (`deploy/dsc/msdsc/hyperv`) leaves to the
environment templates. Ansible's set is `deploy/dsc/ansible`, the same set
in another technology; both cover Windows and Linux, and an environment
uses one of the two, never a mix (ADR-0015, amendments 2026-10-09 and
2026-10-21). The owner, 2026-10-21: *dotnet is cross platform, so is
Blazor, MAUI and DSC. We keep Ansible and other tech for familiarity and
support for the project.*

It is a template for creating Xmip environments, never a lab.

## The one file, and the environment

The cluster's file is the Reference Environment,
`test/core/system-test/configuration/Xmip-reference-environment.xmip`: the one
file a test runs
whether its nodes are processes on one computer or on virtual machines of
their own (the owner, 2026-10-21: *one TOML file that can be run for tests
regardless of node faking or actual nodes*; ADR-0028, amendments 2026-10-21
and 2026-11-25). What the cluster is, and in its `[environment]` table where
it runs on virtual machines, which no node is given
(`deploy/dsc/README.md`, *The environment table*). What the environment
adds is the command's: the cluster's name, `-Cluster`, the package, every
node's and far end's certificate, and each machine's address, in the order
the table derives it. `Deploy-XmipEnvironment` gives the documents here
their parameters from them; the layout and the accounts are
`machine.dsc.yaml`'s own defaults.

The System Tests' table puts each of the file's eleven nodes on a machine of
its own, as the owner's node plan of 2026-11-22 lays them out, OP1 on the
plan's operator machine (ADR-0028, amendment 2026-11-25), under Hyper-V or
under KVM alike. Both Storage nodes the file lists, DS1 and DS2, run on
machines of their own: neither serves until both answer (ADR-0056,
amendment 2026-11-08).

| Node | Roles | Machine | Operating system |
| --- | --- | --- | --- |
| RX1 | receiving | XMIP-RX1 | AlmaLinux 10 |
| RX2 | receiving | XMIP-RX2 | Windows Server 2025 |
| RX3 | receiving | XMIP-RX3 | AlmaLinux 10 |
| EX1 | processing | XMIP-EX1 | Windows Server 2025 |
| EX2 | executing | XMIP-EX2 | AlmaLinux 10 |
| TX1 | sending | XMIP-TX1 | Windows Server 2025 |
| TX2 | sending | XMIP-TX2 | AlmaLinux 10 |
| TX3 | sending | XMIP-TX3 | Windows Server 2025 |
| OP1 | operational, monitoring | XMIP-OP1 | Windows 11 |
| DS1 | storage | XMIP-DS1 | AlmaLinux 10 |
| DS2 | storage | XMIP-DS2 | Windows Server 2025 |

Which machine runs which node, and its system, are the owner's node plan of
2026-11-22 (ADR-0028 and ADR-0056, amendments of that date); a machine's
name is `XMIP-<node>`, and its address is the network's, the nodes after
the machines of their own and the far ends, in the file's order (ADR-0015,
amendment 2026-11-25).

## What each machine is given

**The DNS server**, the `domain_controller`, XMIP-DC01 in the owner's plan
(`name.dsc.yaml`): the zone, `xmip.test`, where it is not there, and an A
record for the cluster, `CL1`, holding every node machine's address, and
one for each node holding its machine's. A node finds another by its name —
`DS1:7443` — inside the network; the System Tests and the Systems Tests
reach each node and far
end at the address `deployed.toml` gives it, and resolve no name.

**Each node's slice, on this machine** (`machine.dsc.yaml`,
`Xmip.Environment/Slice`), before its machine is set up: `node.xmip` as
this machine's `xmip-service --slice --cluster --bind --nodes --authority`
prints it, signed by the environment's authority kept in `authority`, and
that authority's certificate beside it, written into `slices/<node>`: every
Receive Location and Send Port the cluster's file designs is placed over the
environment's nodes, round robin over those whose roles serve its stage,
every Work Process on each node serving its stage, and work no node
satisfies refused (ADR-0056, amendment 2026-11-13); each Receive Location
listening over HTTP on its node, where the far ends that send push to it,
and each Send Port bound over SFTP to the far end that receives of its
turn, in the order `[environment.far_ends] receivers` lists them, each a
user of its own there (ADR-0028, amendment 2026-11-22). The nodes are the
cluster file's, never written again. A node never slices and never
holds the authority's key, so a `node.xmip` edited on it is refused there
and the node runs its active configuration, the last slice that ran. Its
pin, kept in the node's data folder apart from that configuration, holds
the authority, the node's name and the highest serial it has seen, so a
swapped certificate, an older slice or another node's is refused too; and a
correctly signed slice the node cannot start is refused as it starts, the
active configuration running instead and the slice tried again at the
next start (ADR-0031, amendments 2026-11-06, 2026-11-07 and 2026-11-12). A signature and its
serial differ each time it is made, so a slice is made again only where
the text it signs differs — its set too, which DSC asks without a test
first — and a run over an environment restarts no node for a new
signature.

**Each far end's machine** (`far-end-program.dsc.yaml`, from the host's
`far-end.dsc.yaml`), for each far end of the System Tests and the Systems
Tests the table's
`[environment.far_ends]` names (ADR-0028, amendments 2026-11-22 and
2026-11-25): its certificate, key and anchors from the cluster's own
authority, issued into the environment's state, under `tls`; the program
`xmip-system-test-external` of the build for its system, placed and
registered as the service
`xmip-<name>` by its own `--install`, which asks the runtime's one
registration of a service, as `xmip-service --install` does
(`Xmip.Node/Program`); a firewall opening for exactly the ports
`--listening` says it serves on, 7422 for a receiver's Send Ports and 7423
for the roll; and the service running and started with the machine. The far
end is no node: it takes no slice, package or account of its own. The names
step gives its name the machine's address, and the roll reaches it at the
address `deployed.toml` gives it.

**Each node machine** (`node.dsc.yaml`), in this order:

1. its account: on AlmaLinux the system account `xmip`, made here; on
   Windows the virtual account `NT SERVICE\xmip-<node>`, which exists with
   its service and is never made;
2. its slice, `node.xmip`, in the package's config folder, and the
   authority's certificate in `authority/authority.pem` beside it, as they
   were shipped; a node that runs and whose file changed is left to its
   Service step to restart (6). `node.xmip` is the node's alone to
   write (ADR-0031, amendment 2026-11-06, point 4): on Windows it inherits
   nothing, SYSTEM and the administrators hold it in full and the node's
   account may modify it, the virtual account's SID computed as Windows
   computes it, since the account exists only once the package registers the
   service; on AlmaLinux it is the account's, group root, mode 0640;
   `Xmip.Node/Slice` sets it (`NodeAccess.ps1`), and get and test report it.
   Where the package is installed, the slice is in its desired state only
   once the node runs it as its active configuration, as `xmip-service
   --activation` says in the node's words (`activation`): a service that
   started does not say so, since a correctly signed slice the node cannot
   start is refused and the node runs the last one that ran; set leaves the
   node to its Service step to restart then, which tries the slice again
   (ADR-0031, amendment 2026-11-12);
3. its certificate, key and anchors from the cluster's own authority,
   `tls/node.pem`, `tls/node.key` and `tls/anchors.pem`, as the file's
   `[operate]` names them, the key private; one placed while the node runs
   is left to its Service step to restart;
4. the estate's package, the portable archive (the MSI once it is built) or
   the `.rpm`, told the node, the cluster
   and the account, whose `xmip-service --install` lays the node out by the
   slice already there, gives the account what it reads and writes, and
   registers and starts the node's service as that account. A node that ran
   before is restarted by that install after every file above was placed,
   and left to its Service step to wait for, not to restart again;
5. a firewall opening for exactly the ports `xmip-service --listening` says
   its configuration listens on, and none it no longer does — none for the
   far end, which a node reaches and never serves;
6. its service running and started with the machine, `Xmip.Node/Service`,
   after every step that changes what it runs: one step that changed what
   a running node runs leaves `deploy.pending` in its configuration folder,
   `restart` or, from the package, `ready`; this step restarts a node left
   `restart`, once, and waits once for a node this deploy restarted until it
   is ready before the next machine is deployed, as `xmip-service
   --readiness --within <ready>` says in the node's words, asked of the
   program the package installed: it runs its slice and its Xmip Storage
   stands Fine, a Storage node the primary or a standby ready and following
   (`NodeService.ps1`, `Set-NodeService` and `Wait-NodeReadiness`; the
   owner, 2026-11-23: *That has to be sorted, nothing can be left*;
   ADR-0056, amendments 2026-11-23 and 2026-11-24). A Storage node restarted
   comes back a standby, and its primary stopped in order before it follows
   ready has no standby to hand over to; past `ready` seconds, 180 unless
   the document's parameter says, the set is refused in the node's words and
   no next node is deployed. Until 2026-11-24 the slice restarted the node
   and asked it before its certificates and package were placed, on the
   program installed then, and a node whose slice and package both changed
   was restarted twice. The Windows service is automatic, the systemd unit
   enabled. DSC refuses a
   document naming a resource its machine has none of, a condition
   notwithstanding, so the built-in `Microsoft.Windows/Service`, which DSC
   has on Windows alone, cannot be named in a document both families run
   (checked 2026-11-11).

Every rule about the node is `xmip-service`'s: nothing here reads the TOML,
slices it or knows a port.

## The resources

DSC v3 is a standalone command, and its resources are executables that
speak JSON (checked 2026-11-21: 3.4.0-preview.3 the latest release, adopted as
Xmip adopts previews; 3.3.0 the latest stable). The documents use a built-in
resource wherever one fits and an Xmip resource of this folder for the rest:
PowerShell 7 scripts behind resource manifests, on Windows and AlmaLinux
alike. The Windows PowerShell adapter is used nowhere here.

| Instance | Resource |
| --- | --- |
| the account | `Xmip.Node/Account` (AlmaLinux; Windows needs none) |
| the certificate, key and anchors | `Xmip.Node/File` |
| the package | `Xmip.Node/Package` |
| each node's slice, made and signed on this machine | `Xmip.Environment/Slice` |
| the slice in place on the node | `Xmip.Node/Slice` |
| the firewall | `Xmip.Node/Opening` |
| the service | `Xmip.Node/Service` |
| a far end's program, placed and registered as its service by its own `--install` | `Xmip.Node/Program` |
| the names | `Xmip.Environment/Name` |
| the Active Directory domain, its controller promoted and each other Windows machine joined | `Xmip.Environment/Domain` |
| the network's way out, NAT on its gateway machine out of its uplink, which is kept out of the domain | `Xmip.Environment/Gateway` |
| a document applied on another machine | `Xmip.Environment/Machine` |
| every node started together | `Xmip.Environment/Started` |

The firewall is an Xmip resource rather than the built-in
`Microsoft.Windows/FirewallRuleList` because its ports are what the node's
configuration listens on, which the built-in would take typed. DSC applies
a document on the machine it runs on, so `Xmip.Environment/Machine` copies
this folder, a node's files and its parameters to the machine's staging
folder and runs `dsc` there, elevated: over PowerShell Remoting to a
Windows machine as its Administrator, PowerShell Direct where this host
runs it on Hyper-V and WinRM otherwise, DSC brought to it as to an
AlmaLinux one, the `pwsh` and `dsc` zips `prerequisite.toml`'s
`[prerequisite.powershell.archive]` and `[prerequisite.dsc.archive]` name,
found by that name in the image folder, each checked against its SHA-256 and unpacked
under `C:\ProgramData\Xmip\environment\tools`, since Windows Server ships
Windows PowerShell alone; over OpenSSH to an AlmaLinux one,
with the environment's key and its `known_hosts`, checked strictly, so a
machine whose host key is not the one its kickstart was given is refused
(`EnvironmentSsh.ps1`). Every command a Windows machine runs goes through
`Invoke-EnvironmentCommand`, which brings what it warns of or writes there
back as standard error here: PowerShell Remoting writes a warning of the
far side to the console past any redirection, standard output, where DSC
reads the resource's JSON. An AlmaLinux machine needs nothing but its sshd:
DSC is brought to it, the `pwsh` and `dsc` tarballs the same two tables
name, found by that name in the image folder, each checked against its
SHA-256, copied once and
unpacked under `/var/tmp/xmip-environment/tools`, never installed for the
machine, and `dsc` runs from there with sudo. That staging folder is the
login's alone, `0700`, and one another account owns is refused; a node's
files, its key among them, are sent to its `files` for each run of the
document, read by the login and root alone, and removed once `dsc` has
run, whatever it answered; so a file is placed with the mode its resource
names, never its staged source's: `Xmip.Node/File` makes the key `0600`,
the certificate, the anchors and the authority's certificate `0644`.
Ansible stages in a folder of its own. A
machine that does not answer yet is answered absent, so a fresh host is
tested too. The Windows machines' secret is read as every template reads
it (`deploy/dsc/machine/MachineSecret.ps1`): encrypted, on Windows. Every document
requires DSC `^3.4.0-preview.3`, the latest release, and each resource `^0.1`.
No document asks for elevation as a whole: each resource's manifest states
`requireSecurityContext: elevated` on exactly the methods that need
administrator rights — every method of `Xmip.Environment/Name`,
`Xmip.Node/File`, `Xmip.Node/Opening` and `Xmip.Node/Slice`, which read
what only an administrator may, and the set of `Xmip.Node/Account`,
`Xmip.Node/Package` and `Xmip.Node/Service`; `Xmip.Environment/Machine`,
`Xmip.Environment/Slice`, `Xmip.Environment/Domain`,
`Xmip.Environment/Gateway` and `Xmip.Environment/Started` run unelevated on
this machine.

`Xmip.Environment/Domain` is no document applied on the machine but works
from this one, inside the session `Xmip.Environment/Machine` opens: the
Administrator's secret is the forest's Directory Services Restore Mode
password and the account a member joins with, `Administrator@<domain>`,
and so goes to the machine inside that session alone, never in a staged
parameters file. Microsoft's own resources for it, ActiveDirectoryDsc and
ComputerManagementDsc, are Windows PowerShell DSC resources, which DSC v3
runs only through its Windows PowerShell adapter, which no document here
uses. Promoting and joining each restart the machine; one that does not
answer while it restarts is not yet in its desired state, never an error,
so the run sets it again until it is.

`Xmip.Environment/Gateway` works from this machine in the same session: it
makes the machine the table's `gateway` names, XMIP-DC01 in the owner's
plan, the network's way out (the owner, 2026-11-24: *the VM DSC
can be a gateway to internet for those machines that needs it*, *A good
choice would be the DC*, *The DC would be behind my firewall*). What the
machine is given is `deploy/dsc/machine/WindowsGateway.ps1`'s, the one
script Ansible's `xmip_gateway` role hands to `win_powershell` too, sent
whole into the session: its second adapter, the uplink, the one beside the
adapter holding its address, registers nothing in DNS and asks the
machine's own DNS server at the network's address, as its network's
adapter does too, has no NetBIOS over TCP/IP, is a Public network,
and an inbound rule on that interface, `Xmip-Uplink-Inbound`, blocks
everything arriving on it whatever profile it is given; where the machine
runs the DNS Server service, it listens on the network's address alone and
every A or AAAA record of the machine's name, of the zone's own name and of
`gc` that holds an address outside the network is removed; and Routing and
Remote Access's Routing, `Install-RemoteAccess -VpnType RoutingOnly`, holds
NAT with the uplink translated in full and the network's adapter private
(`netsh routing ip nat`), read back from netsh's own dump. A machine
without its second adapter is refused: the adapter is the hypervisor's to
give, and the hypervisor's template gives it. `deploy/dsc/README.md` says
why each, with Microsoft's documentation.

`Xmip.Node/Package` compares an installed `.rpm` with the
shipped one by its header's SHA-256, so a build made again under the same
version reaches the machine too, installed over the one there by rpm's own
upgrade.

| File | Is |
| --- | --- |
| `machine.dsc.yaml` | one node machine, from the host: its slice made, then `node.dsc.yaml` applied there |
| `names.dsc.yaml` | the names, from the host: `name.dsc.yaml` applied on the DNS server |
| `domain.dsc.yaml` | the domain, from the host: one Windows machine promoted or joined (`EnvironmentDomain.ps1`) |
| `gateway.dsc.yaml` | the network's way out, from the host: its gateway machine made so (`EnvironmentGateway.ps1`, `../../machine/WindowsGateway.ps1`) |
| `node.dsc.yaml` | one node, on its machine |
| `name.dsc.yaml` | the names, on the DNS server |
| `started.dsc.yaml` | every node started together, from the host |
| `far-end.dsc.yaml` | one of the System Tests' far ends, from the host: `far-end-program.dsc.yaml` applied on its machine |
| `far-end-program.dsc.yaml` | one far end, on its machine: its certificate, its program placed and registered, its firewall opening and its service |
| `node.resource.ps1`, `NodeMachine.ps1`, `NodeFile.ps1`, `NodeOpening.ps1`, `NodeAccess.ps1`, `NodePackage.ps1`, `NodeProgram.ps1`, `NodeService.ps1` | the `Xmip.Node` resources |
| `environment.resource.ps1`, `EnvironmentMachine.ps1`, `EnvironmentSsh.ps1`, `EnvironmentSlice.ps1`, `EnvironmentName.ps1`, `EnvironmentDomain.ps1`, `EnvironmentGateway.ps1`, `EnvironmentStarted.ps1` | the `Xmip.Environment` resources |
| `*.dsc.resource.yaml` | their manifests, YAML as every configuration here: JSON is what the resources speak, never what a person writes (the owner, 2026-11-02); the embedded schema tagged `!embedded`, the form DSC's YAML reader takes |

## Before the first run

`Deploy-XmipEnvironment` makes the machines first, with the hypervisor's
template (`deploy/dsc/README.md`). A machine needs nothing more, Windows and
AlmaLinux alike: DSC is brought to it, as above.

Then, not elevated, in an Xmip PowerShell Console, the build the command
takes the packages, the module libraries, the far ends' program and the
slicer from (`deploy/package/README.md`: the portable archive on Windows,
the `.rpm` on a Linux machine), and the images and the tool archives in the
image folder (`deploy/dsc/README.md`, *Before the first run*):

```powershell
Import-Module -Name D:\Repos\Xmip\Xmip\Xmip.psd1
Build-XmipService -Site personal-computer -CargoArgument '--release' -Package archive
```

Nothing more is made by hand. The environment's authority, with
`operator.xmip` beside it, every node's and far end's certificate in
`identity/<name>`, your operator certificate in `operator/` and the Windows
machines' Administrator secret are the command's own, made in its private
state where none is (`deploy/dsc/README.md`, *The command*). The host is given no rule or suffix that
sends its names to the environment's DNS server, and WinRM no trusted
hosts: the System Tests reach every machine at the address `deployed.toml`
gives it, and this host reaches a Windows machine through PowerShell Direct
on Hyper-V. The uplink, where the table names a `gateway`, is yours to make
once (`deploy/dsc/README.md`, *Before the first run*).

## Running it

`Deploy-XmipEnvironment -Path <cluster file> -Cluster <name>`, msdsc where
`-Technology` is left out: after the machines, it applies `domain.dsc.yaml`
to the `domain_controller` where the table names one, `gateway.dsc.yaml` to
its `gateway` where it names one, `names.dsc.yaml` where one of the
machines is the DNS server, `domain.dsc.yaml` to each other Windows machine
where there is a domain, `far-end.dsc.yaml` once for each far end, then
`machine.dsc.yaml` once for each node in the order the file declares them,
and last `started.dsc.yaml`, with
this folder on `PATH` so DSC finds its resources. A node refuses to accept
work until its cluster's Xmip Storage answers, and a Storage node until
every Storage node the cluster lists does, so no node of them starts alone,
one machine after another: each node's own document enables its service
and starts it waiting for nothing, and `Xmip.Environment/Started` starts
them together, and again every five seconds each one that stopped, until
every one runs or its window, 180 seconds, is spent. Each document runs itself elevated on its machine,
through WinRM as the Administrator or SSH with sudo; on the host it needs
none. `-WhatIf` says what differs and changes nothing.

Then the System Tests, which test the internals, and the Systems Tests,
which test how nodes interact, run against the machines, `Start-XmipTest
-VirtualMachine` (ADR-0028, amendment 2026-11-25). The run is the file's
every node, OP1 among it; it is handed every node's and far end's address
and the operator certificate the deploy issued for your account,
`CN=<account name>`, signed by the same authority, whom every node lists
among its `[operate] operators` — for the Systems Tests their node list and
operator certificate — resolves no name, and makes, starts and spawns
nothing. `-Container` runs the same file in containers the run makes,
each node's slice written by this folder's `Set-EnvironmentSlice`, as here.
Every node must answer as that node, or the run is REFUSED before it
starts; `-Nodes`, `-NodeRole` and `-NodeCapability` are refused with it,
and so is a cluster file that changed since it was deployed:

```powershell
Start-XmipTest -Suite Core.System -Cluster CL1 -VirtualMachine
Start-XmipTest -Suite Core.Systems -Cluster CL1 -VirtualMachine
Get-XmipTestStatus
Get-XmipTestResult -Test Carried
Start-XmipOperationWeb -Snapshot D:\Repos\Xmip\.local-work\system-test\CL1-snapshot.xmip
```

Open <https://127.0.0.1:5087> in a Web Browser tab: the Monitor follows the
real nodes as they receive, process and send.

**What runs.** A node that declares no Storage role reaches DS1 over Xmip's
mutual TLS on the Storage plane's port, 7443, presenting its own
`tls/node.pem`
([built, in the assembled service](../../../../doc/architecture/estate-map.md#storage-nodes));
DS1's and DS2's `xmip-service --listening` says `7443/tcp storage`, so
their machines' firewalls open it. Each runs on a machine of its own, the
primary and the standby that follows it (ADR-0056, amendment 2026-11-08),
and every other node reaches the primary. Every far end runs on a machine
of its own, and the run reaches each at its address: each round a sender
pushes a document to each Receive Location listening on its node, a real
receiving node takes it and writes it to the Ledger on DS1, and a real
sending node puts it on the receiver of its turn, which tells the run of
it: each Receive Location's `delivery` says how many of the documents
dropped there arrived whole where their route sends them and how long each
took (ADR-0028, amendments 2026-11-11, 2026-11-22 and 2026-11-25). OP1, the
file's operational and monitoring node, runs on XMIP-OP1 and is in the run,
and no node is started on the host. The far end the System Tests served on
the host for nodes on machines is deleted from the rig; on virtual
machines the far ends are always the deployed ones.

**What waits on the owner.** The Windows machines take the portable
archive, `Build-XmipService -Package archive`, until the MSI is built: WiX
7 builds it only once its license is accepted, the owner's decision
(`deploy/package/README.md`).

## How it is held

`test/MsdscEnvironment.Test.ps1` holds what can be held without the
machines: the documents read as YAML by DSC, each declaring every parameter
it uses; the System Tests' environment evaluated by DSC as
`Deploy-XmipEnvironment` applies it, with every resource replaced by an
echo, each node machine given its node's values, the environment's
`known_hosts` and, on AlmaLinux, the tools, and every node machine told the
environment's nodes and the far ends it binds to; the
resource manifests found by DSC; a tool whose SHA-256 differs refused
before anything is sent; and the resources' own steps with the machine's
commands stubbed, the slice asked with `--bind` and `--nodes`.
`test/DeployGateway.Test.ps1` holds the gateway machine: the file's reading
and its refusals, the step's place, and `WindowsGateway.ps1` with every
Windows command a stub over a machine held in memory, a fresh one found
differing in each rule, made so and then found as it is. The root's
`cargo test --test deploy` holds that every node's slice, its Locations
placed and bound to the far ends, reads as `xmip-service` reads it, and that
every Location the file designs is placed on one of them. The machines
themselves are proved by running `Deploy-XmipEnvironment`
(`deploy/dsc/README.md`).
