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

The cluster's `xmip.toml` is the Playground's own,
`test/core/playground/configuration/xmip.toml`: the one file a test runs
whether its nodes are simulated on one computer or on machines of their own
(the owner, 2026-10-21: *one TOML file that can be run for tests regardless
of node faking or actual nodes*; ADR-0028, amendment 2026-10-21). It says
what the cluster is and nothing of where it runs. What the environment adds
is here, in `environment.example.parameters.yaml`: the cluster's name, its
DNS domain, which node runs on which machine, the package, the layout, the
accounts, the folder of each node's certificate, and `farEnd`, where the
machines reach the Parties' far end the Playground serves.

The example puts five of the file's nine nodes on the Hyper-V example's
five node machines; the Playground simulates the other four:

| Node | Roles | Machine | Operating system | Address |
| --- | --- | --- | --- | --- |
| R1 | receiving | XMIP-IN01 | AlmaLinux 10 | 10.77.0.61 |
| S1 | sending | XMIP-OUT01 | AlmaLinux 10 | 10.77.0.71 |
| P1 | processing | XMIP-APP01 | Windows Server 2025 | 10.77.0.51 |
| L1 | executing | XMIP-APP02 | Windows Server 2025 | 10.77.0.52 |
| D1 | storage | XMIP-APP03 | Windows Server 2025 | 10.77.0.53 |

Which five, and on which machine, is the assistant's draft of 2026-10-21,
for the owner to strike.

## What each machine is given

**The DNS server**, XMIP-DC01 (`name.dsc.yaml`): the zone, `xmip.test`,
where it is not there, and an A record for the cluster, `C1`, holding every
node machine's address, and one for each node holding its machine's. A node
finds another by its name — `D1:7443` — and the Playground uses a node whose
name resolves.

**Each node machine** (`node.dsc.yaml`), in this order:

1. its account: on AlmaLinux the system account `xmip`, made here; on
   Windows the virtual account `NT SERVICE\xmip-<node>`, which exists with
   its service and is never made;
2. the cluster's `xmip.toml` in the package's config folder;
3. its certificate, key and anchors from the cluster's own authority,
   `tls/node.pem`, `tls/node.key` and `tls/anchors.pem`, as the file's
   `[operate]` names them, the key private;
4. the estate's package, the MSI or the `.rpm`, told the node, the cluster
   and the account, whose `xmip-service --install` slices the file already
   there, gives the account what it reads and writes, and registers and
   starts the node's service as that account;
5. its slice, `xmip-node.toml`, as `xmip-service --slice --cluster --bind
   --nodes` prints it, the service restarted when it changed: every Receive
   Location and Send Port the cluster's file designs is placed over the
   environment's nodes, round robin by their roles, and bound over SFTP on
   the Parties' far end at `farEnd`, port 7422, each a user of its own
   there, so a node fetches what the Playground drops and puts what it
   sends where the Playground is told of it (ADR-0028, amendment
   2026-10-22). The nodes are the parameters' `nodes`, never written again;
6. a firewall opening for exactly the ports `xmip-service --listening` says
   its configuration listens on, and none it no longer does — none for the
   far end, which a node reaches and never serves;
7. its service running and started with the machine: on Windows the
   built-in `Microsoft.Windows/Service`, on AlmaLinux `Xmip.Node/Service`.

Every rule about the node is `xmip-service`'s: nothing here reads the TOML,
slices it or knows a port.

## The resources

DSC v3 is a standalone command, and its resources are executables that
speak JSON (checked 2026-10-21: 3.3.0 current, 3.2.0 general availability
on 2026-04-29). The documents use a built-in resource wherever one fits and
an Xmip resource of this folder for the rest: PowerShell 7 scripts behind
resource manifests, on Windows and AlmaLinux alike. The Windows PowerShell
adapter is used nowhere here.

| Instance | Resource |
| --- | --- |
| the account | `Xmip.Node/Account` (AlmaLinux; Windows needs none) |
| the cluster's file, the certificate, key and anchors | `Xmip.Node/File` |
| the package | `Xmip.Node/Package` |
| the slice | `Xmip.Node/Slice` |
| the firewall | `Xmip.Node/Opening` |
| the service | `Microsoft.Windows/Service` on Windows, `Xmip.Node/Service` on AlmaLinux |
| the names | `Xmip.Environment/Name` |
| a document applied on another machine | `Xmip.Environment/Machine` |

The firewall is an Xmip resource rather than the built-in
`Microsoft.Windows/FirewallRuleList` because its ports are what the node's
configuration listens on, which the built-in would take typed. DSC applies
a document on the machine it runs on, so `Xmip.Environment/Machine` copies
this folder, a node's files and its parameters to the machine's staging
folder — WinRM to a Windows machine as its Administrator, SSH to an
AlmaLinux one with its key — and runs `dsc` there, elevated. Every document
requires DSC `^3.2` and each resource `^0.1`.

| File | Is |
| --- | --- |
| `environment.example.dsc.yaml` | the example environment, run on the host: the names, then each node machine |
| `environment.example.parameters.yaml` | what it is given, the mapping of nodes onto machines among it |
| `machine.dsc.yaml` | one node machine, from the host |
| `node.dsc.yaml` | one node, on its machine |
| `name.dsc.yaml` | the names, on the DNS server |
| `node.resource.ps1`, `NodeMachine.ps1`, `NodeFile.ps1`, `NodeOpening.ps1` | the `Xmip.Node` resources |
| `environment.resource.ps1`, `EnvironmentMachine.ps1`, `EnvironmentName.ps1` | the `Xmip.Environment` resources |
| `*.dsc.resource.json` | their manifests |

## Before the first run

The machines are installed (`deploy/dsc/msdsc/hyperv`), and XMIP-DC01 runs
the DNS Server role; the domain controller's own template is not written.

**On each machine**, once, as its Administrator or with sudo: PowerShell
7.6 and Microsoft DSC 3.2 or newer — `winget install --id Microsoft.PowerShell
--exact` and `winget install --id Microsoft.DSC --exact` on Windows, the
`powershell` and `dsc` packages from Microsoft's package repository on
AlmaLinux — and on AlmaLinux PowerShell as an SSH subsystem,
`Subsystem powershell /usr/bin/pwsh -sshs -NoLogo` in
`/etc/ssh/sshd_config`.

**On the host**, in an elevated Xmip PowerShell Console, once: WinRM may
reach the Windows machines by address, and the host asks XMIP-DC01 for the
environment's names, so `R1` and `C1` resolve where the Playground runs.

```powershell
Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value '10.77.0.*' -Force
Add-DnsClientNrptRule -Namespace '.xmip.test' -NameServers '10.77.0.10'
[string[]] $suffixes = @((Get-DnsClientGlobalSetting).SuffixSearchList) + 'xmip.test'
Set-DnsClientGlobalSetting -SuffixSearchList $suffixes
[hashtable] $farEnd = @{
    DisplayName   = 'Xmip Playground, the Parties'' far end'
    Direction     = 'Inbound'
    Protocol      = 'TCP'
    LocalPort     = 7422
    RemoteAddress = '10.77.0.0/24'
    Action        = 'Allow'
}
New-NetFirewallRule @farEnd
```

The last lets the machines reach the far end the Playground serves on this
host, and nothing else reach it.

Then, not elevated, in an Xmip PowerShell Console: the packages
(`deploy/package/README.md`; the `.rpm` is written and not built while
builds are Windows-only), the cluster's authority and each node's
certificate from it, and the parameters copied to where they are yours.

```powershell
Import-Module -Name D:\Repos\Xmip\Xmip\Xmip.psd1
Build-XmipService -Site personal-computer -CargoArgument '--release' -Package msi
[string] $local = 'D:\Repos\Xmip\.local-work\environment'
foreach ($node in 'R1', 'S1', 'P1', 'L1', 'D1') {
    [hashtable] $issue = @{
        Node      = $node
        Cluster   = 'C1'
        Authority = "$local\authority"
        Name      = "$node.xmip.test", 'C1', 'C1.xmip.test'
        Path      = "$local\identity\$node"
    }
    New-XmipCertificate @issue
}
[string] $example = 'D:\Repos\Xmip\deploy\dsc\msdsc\environment\environment.example.parameters.yaml'
Copy-Item -LiteralPath $example -Destination "$local\environment.parameters.yaml"
```

In the copy, write in `linuxAccount` under `common`, the account the
AlmaLinux machines were installed with, and the packages' version; the
documents refuse to run without the account.

## Running it

In an Xmip PowerShell Console, not elevated — each document runs itself
elevated on its machine, through WinRM as the Administrator or SSH with
sudo — with this folder on `PATH` so DSC finds its resources. `test` says
what differs and changes nothing, `set` makes it so:

```powershell
$env:PATH = "D:\Repos\Xmip\deploy\dsc\msdsc\environment;$env:PATH"
[string] $environment = 'D:\Repos\Xmip\deploy\dsc\msdsc\environment\environment.example.dsc.yaml'
[string] $parameters = 'D:\Repos\Xmip\.local-work\environment\environment.parameters.yaml'
dsc config --parameters-file $parameters test --file $environment
dsc config --parameters-file $parameters set --file $environment
```

Then the Playground runs against the machines: the names typed resolve and
answer, and the run says which nodes are real. The tester's operator
certificate is signed by the same authority — a file naming it,
`D:\Repos\Xmip\.local-work\environment\authority\operator.toml`, holds
`[service]` with `name`, `cluster_name = "C1"` and `node_name`, and
`[provision.operator] authority = "."`. Type exactly the nodes the
parameters map, which the Playground places the Locations over as the
machines did:

```powershell
[string] $local = 'D:\Repos\Xmip\.local-work\environment'
[string] $tester = "$local\tester"
New-XmipCertificate -Operator 'tester@xmip.test' -Path $tester |
    New-XmipCertificate -Configuration "$local\authority\operator.toml" -Path "$tester\operator.pem"
Copy-Item -LiteralPath "$local\authority\authority.pem" -Destination "$tester\anchors.pem"
Start-XmipTest -Suite Core.Playground -Cluster C1 -Nodes R1, S1, P1, L1, D1 -Certificate $tester
Get-XmipTestStatus
Get-XmipHealth -Scope xmip:///C1/carried
Start-XmipOperationWeb -Snapshot D:\Repos\Xmip\.local-work\playground\C1-snapshot.toml
```

Open <https://127.0.0.1:5087> in a Web Browser tab: the Monitor follows the
real nodes as they receive, process and send.

**What runs.** A node that declares no Storage role reaches D1 over Xmip's
mutual TLS on the Storage plane's port, 7443, presenting its own
`tls/node.pem`
([built, in the assembled service](../../../../doc/architecture/estate-map.md#storage-nodes));
D1's `xmip-service --listening` says `7443/tcp storage`, so its machine's
firewall opens it. D2 runs on no machine of the example: every node passes
it over, and D1 is the primary on its own (ADR-0056, amendment
2026-10-22). The Playground serves the Parties' far end on the host, port
7422, each Location placed on the real nodes a user of its own there; each
round it drops a file for every Receive Location, a real receiving node
fetches it, writes it to the Ledger on D1, and a real sending node puts it
back under its name, which the far end tells the Playground of:
`xmip:///C1/carried` says how many of the files dropped arrived and how
long each took (ADR-0028, amendment 2026-10-22). The other four nodes of the
file are simulated, and no node is started on the host beside real ones.

**What waits on the owner.** The Windows machines take the MSI, which WiX
7 builds only once its license is accepted, the owner's decision
(`deploy/package/README.md`); the AlmaLinux machines take the `.rpm`, which
is not built while builds are Windows-only. Until both are there, the
nodes on the machines lacking their package do not run, and the Locations
placed on them are not fetched.
## How it is held

`test/MsdscEnvironment.Test.ps1` holds what can be held without the
machines: the documents read as YAML by DSC, each declaring every parameter
it uses; the example environment evaluated by DSC with every resource
replaced by an echo, each node machine given its node's values and the
mapping the same as Ansible's inventory, every mapped node declared by the
cluster's file, and every node machine told the parameters' nodes and the
far end it binds to; the resource manifests found by DSC; and the
resources' own steps with the machine's commands stubbed, the slice asked
with `--bind` and `--nodes`. The root's `cargo test --test deploy` holds
that every mapped node's slice, its Locations placed and bound on the far
end, reads as `xmip-service` reads it, and every Location the file designs
is placed on one of them. Nothing here has been applied to a machine.
