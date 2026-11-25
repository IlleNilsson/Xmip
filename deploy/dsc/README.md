# Xmip environments, from one file and one command

`deploy/dsc` holds the templates that create Xmip environments, never a
lab: the machines an environment runs on and the Xmip node each machine
runs, Windows and AlmaLinux alike. Two technologies hold the same set, side
by side, and an environment is made by one of them, never a mix (ADR-0015,
amendments 2026-10-09 and 2026-10-21; the owner, 2026-10-08: *it is either
DSC V3 or Ansible, not a mix*):

| Folder | Is |
| --- | --- |
| `msdsc/` | Microsoft DSC v3, the standalone `dsc`: `libvirt` and `hyperv` make the machines, `environment` what runs inside them, PowerShell 7 resources behind manifests |
| `ansible/` | ansible-core: the role `xmip_machine` makes the machines, `xmip_name` the names, `xmip_node` each node |
| `machine/` | what a machine is, for both: the network, pool and domain definitions, the kickstart, the Windows answer file and the answer medium, what the hypervisor gives its guest (its memory and chrony's clock), each step of a libvirt machine's installation and how the Windows machines' secret is read, plain PowerShell 7 that DSC's resources dot-source and Ansible's role asks through `machine.ps1`; and what runs on a Windows host or machine under Windows PowerShell, which both hand over whole: the key a Windows ISO's prompt is answered with, the uplink found (`HyperVUplink.ps1`) and the gateway machine made (`WindowsGateway.ps1`) |

## The environment table

Where a cluster runs on virtual machines is its cluster file's
`[environment]` table, and no other file says it (ADR-0015, amendment
2026-11-25; the owner, 2026-11-25: *I still don't get why there is a need
for two files?*). The System Tests' own cluster file, which the Systems
Tests run too, `test/core/system-test/configuration/cluster.xmip`, holds the owner's node
plan of 2026-11-22: every node of the file and every far end on a virtual
machine of its own, OP1 on the operator's machine, and the domain
controller, the file storage and the developers' machines beside them. A
smaller plan is a smaller cluster file. The plan is drawn, with its
machines and the four ways to run it — local processes, containers,
virtual machines on Hyper-V, KVM with libvirt or VMware, and physical
machines (ADR-0015, amendment 2026-11-24) — in
[the environment deck](../../asset/brand/presentation/Xmip-environment.pptx);
every node in it is optional, and Xmip runs on one node with all roles.

Slicing gives no node the table (ADR-0031, the second amendment of
2026-11-25), and the table names no cluster, no machine's address and no
absolute path: the command is given the cluster, and the host's facts are
its defaults (*The command*, below).

| Key | Is |
| --- | --- |
| `network` | optional, `"<prefix>/<length>"`: the machines' network. Left out, the command picks a free private /24 on the host and keeps it in the environment's state. The host takes the range's first address, then the machines in order: the `[environment.machines]` entries that run no node and no far end, in the file's order, then the far ends, senders then receivers, then the nodes, in the file's order |
| `domain` | the machines' DNS domain, `xmip.test` where left out |
| `domain_controller` | optional: a Windows machine of the environment made the first domain controller of a new Active Directory forest of `domain` and the network's DNS server; every other Windows machine is joined to it, each restarted. AlmaLinux machines are not joined. Without one, the host answers the machines' names |
| `gateway` | optional: a Windows machine of the environment that is the network's way out in the host's place, NAT on it out of a second adapter on the host's uplink — on Hyper-V an external switch onto one of the host's adapters, on libvirt a bridge of the host's — behind the owner's firewall (*The way out*, below); it is given no gateway on the network. Refused: a name that is no Windows machine of the environment. Left out, the host's own NAT is the way out where any node is online, and the network is isolated otherwise: a network has one way out |
| `[environment.machine]` | every virtual machine's defaults, the keys below: `os`, `cpu`, `memory_gb`, `dynamic_memory` and `disk_gb`. Built in: `cpu` 2, `memory_gb` 2 and `disk_gb` 64; no `os` |
| `[environment.machines.<name>]` | the same keys. For a node or a far end of that name: its machine, where it differs from the defaults. Any other name is a machine of its own that runs no node and no far end, such as the domain controller, the file storage or a person's machine, and needs an `os`; it may say a `purpose`, which its description gives where it is neither the domain controller nor the gateway |
| `[environment.far_ends]` | `senders = [...]` and `receivers = [...]`: the far ends of the System Tests and the Systems Tests, each run on a virtual machine of its own as the service `xmip-<name>` (msdsc's `far-end.dsc.yaml`). Each Receive Location listens over HTTP on its own node, where the senders push to it, and each Send Port puts over SFTP on the receiver of its turn, in the order `receivers` lists them (ADR-0028, amendment 2026-11-22) |
| `[environment.images.<os>]` | an installation image an `os` names: `name`, the system in plain words, which each machine's description gives; `sha256`, by which the command finds the image in the image folder, never by a path; `family`, `Windows` or `Linux`; `edition`, a Windows image's `NAME` in its `sources\install.wim`; `secureBootTemplate`, `tpm` and `environment`, below |
| `os` | on a machine: the name of the image it is installed from |
| `cpu`, `disk_gb` | on a machine: its virtual processors, and its disk in GiB |
| `memory_gb`, `dynamic_memory` | on a machine: the memory it starts with and installs with, in GiB, static; and `{ minimum_gb, maximum_gb }`, in steps of 2 MiB, `minimum_gb <= memory_gb <= maximum_gb`: on Hyper-V the least and the most it is given as it uses it; on libvirt `maximum_gb` is the domain's memory, of which its virtio balloon starts with `memory_gb` and gives back up to the most as the machine runs short, the host given back every page it frees; libvirt has no least. Windows has no balloon driver of its own, so on libvirt a Windows machine's `dynamic_memory` is refused and its memory is static |
| `environment` | on a Linux image: the kickstart's environment group, `minimal-environment` where it names none; one with a desktop starts to its graphical target |
| `tpm` | on an image: `true` gives its machines a virtual TPM 2.0, as Windows 11's Setup asks; on libvirt swtpm's, refused where the host has no `swtpm`. Left out, none. `secureBootTemplate` is Hyper-V's: libvirt's firmware enrolls both of Microsoft's certificate authorities |

**Derived, never written.** A machine is named `XMIP-<name>`: XMIP-RX1 for
the node RX1, XMIP-DC01 for the entry DC01. The network, the switch and the
pool are `Xmip-<cluster>`. A node's machine reaches past the network where
the node declares the Node capability `online` (ADR-0056, amendment
2026-11-24), and is installed with the way out as its gateway; a far end's
machine and a machine of its own do not, and are installed with no
gateway, reaching the network alone, the host on it included. Each
machine's description field, Hyper-V's Notes and libvirt's
`<description>`, states its role and its operating system in one line:
the role from what the cluster file declares — a node's roles, a far end's
side, the domain controller or the gateway, and for any other machine of
its own its `purpose` — and the system from its image's `name`: *Receiving
node RX1 · AlmaLinux 10*, *Sender far end EXTTX1 · AlmaLinux 10*, *Domain
controller and gateway DC01 ·* and its image's name (the owner, 2026-11-25:
*When you set up virtual machines, there is a description field. I want it
to state Role and OS type*).

The YAML each tool reads is written from the table into the run folder,
`.local-work/deploy/<cluster>/`: DSC's `<step>.parameters.yaml` and
Ansible's `inventory.yml`. It is generated, never configuration
(CONTRIBUTING).

## The way out

Where the table names a `gateway`, that machine is the network's way out,
in the owner's plan the domain controller, XMIP-DC01 (ADR-0015, amendments
2026-11-24 and 2026-11-25; the owner, 2026-11-24: *the VM DSC can be a gateway
to internet for those machines that needs it*, *A good choice would be the
DC*). A domain controller on two networks is a known cause of DNS and
Active Directory trouble; the owner, told so: *The DC would be behind my
firewall*. So its second adapter, the uplink, is on his network behind his
firewall, addressed by its DHCP, and the templates keep it out of the
domain, each by Microsoft's own setting, every one in
`machine/WindowsGateway.ps1`, which both technologies run on the machine:

- It registers no address in DNS, and both adapters ask the machine's own
  DNS server at the network's address, the one it listens on, where
  promoting it left them asking the loopback; a gateway machine that runs
  no DNS server has its uplink ask what its network's adapter asks:
  `Set-DnsClient -RegisterThisConnectionsAddress $false`
  ([Set-DnsClient](https://learn.microsoft.com/powershell/module/dnsclient/set-dnsclient))
  and `Set-DnsClientServerAddress`
  ([Set-DnsClientServerAddress](https://learn.microsoft.com/powershell/module/dnsclient/set-dnsclientserveraddress)).
- The DNS server listens on the network's address alone, and every record
  of the machine's name, of its zone's own name and of `gc` that holds an
  outside address is removed: `Set-DnsServerSetting` with
  `ListeningIPAddress`
  ([Set-DnsServerSetting](https://learn.microsoft.com/powershell/module/dnsserver/set-dnsserversetting)),
  the three steps of [Avoid registering unwanted NICs in DNS on a
  multihomed domain
  controller](https://learn.microsoft.com/troubleshoot/windows-server/networking/unwanted-nic-registered-dns-mulithomed-dc)
  (2026-02-12), and its *delete the existing unwanted Host A record*.
- No NetBIOS over TCP/IP on it:
  [SetTcpipNetbios](https://learn.microsoft.com/windows/win32/cimwin32prov/settcpipnetbios-method-in-class-win32-networkadapterconfiguration),
  2, of `Win32_NetworkAdapterConfiguration`.
- Nothing in through it: the uplink is a Public network
  ([Set-NetConnectionProfile](https://learn.microsoft.com/powershell/module/netconnection/set-netconnectionprofile)),
  and one inbound rule on its interface, whatever profile it is given,
  blocks everything arriving on it
  ([New-NetFirewallRule](https://learn.microsoft.com/powershell/module/netsecurity/new-netfirewallrule)
  `-InterfaceAlias`); *explicit block rules take precedence over any
  conflicting allow rules*
  ([Windows Firewall rules](https://learn.microsoft.com/windows/security/operating-system-security/network-security/windows-firewall/rules)).
  A rule on the interface, never the Public profile's: Windows Server 2025
  domain controllers have been reported to give their own network the
  Public profile after a restart, and a profile that let nothing in would
  then shut the domain out.
- NAT for the network's prefix: Routing and Remote Access, whose Routing
  role service Microsoft documents as a NAT router a Hyper-V virtual
  machine may run, installed by `Install-RemoteAccess -VpnType
  RoutingOnly` ([Remote
  Access](https://learn.microsoft.com/windows-server/remote/remote-access/remote-access),
  [Install-RemoteAccess](https://learn.microsoft.com/powershell/module/remoteaccess/install-remoteaccess),
  Windows Server 2025), its NAT the uplink in full and the network's
  adapter private, by `netsh routing ip nat`
  ([its reference](https://learn.microsoft.com/previous-versions/windows/it-pro/windows-server-2008-r2-and-2008/cc754535(v=ws.10)),
  no PowerShell command covering it), read back from its dump. WinNAT,
  `New-NetNat`, the host's own NAT, is not used there: Microsoft documents
  it for a host's internal switch, its virtual machines and containers, one
  per host ([Set up a NAT
  network](https://learn.microsoft.com/windows-server/virtualization/hyper-v/setup-nat-network)).

The machine of each node that declares the Node capability `online` is
given the gateway's address as its gateway, every other none. The step runs after
the domain's controller, whose DNS server it settles, and before the names.
Not yet run on a machine: whether Netlogon registers the uplink's address
again in its hourly registration, which each later run then finds and
removes, and whether RRAS's NAT passes the replies the inbound rule lets
through, the first Hyper-V run shows.

## The command

```powershell
Deploy-XmipEnvironment -Path D:\Repos\Xmip\test\core\system-test\configuration\cluster.xmip -Cluster CL1
```

`-Path`, the cluster file, and `-Cluster`, its name, are required: the file
names no cluster (ADR-0028, amendment 2026-10-21). On Windows the command
runs in an elevated Xmip PowerShell Console, and an unelevated run is
refused, naming one; it never starts one. Everything else is a default,
and what the command cannot choose is given once, as a parameter, and kept
in the environment's state, so a later run needs none of it (ADR-0015,
amendment 2026-11-25):

| Parameter | Is | Where left out |
| --- | --- | --- |
| `-Technology` | `msdsc` or `ansible`: the template set that makes all of it, never a mix | `msdsc`, or the technology the state holds |
| `-Hypervisor` | `hyperv` or `libvirt`, whose machines the technology makes | the host's kind: Hyper-V on Windows, KVM through libvirt on Linux; refused in words on macOS |
| `-ImageFolder` | the installation images, each found there by the SHA-256 its `[environment.images]` gives, and the archives Microsoft DSC brings to each machine, each found there by the name `prerequisite.toml` gives | the one the state keeps, else the account's Xmip folder's `images`: `%LOCALAPPDATA%\Xmip\images` on Windows, `xmip/images` under `$XDG_STATE_HOME` or `~/.local/state` elsewhere |
| `-DiskFolder` | where the machines' disks are, `Xmip-<cluster>` in it | the one the state keeps, else Hyper-V's virtual hard disk path, or `/var/lib/libvirt/images` |
| `-Uplink` | where `gateway` is named: the switch or bridge its second adapter is on | the one the state keeps, else the host's one external switch on Hyper-V, or its one bridge on Linux; refused where there is none or several, naming the switches found |
| `-WindowsHost` | for Ansible on Hyper-V: the Windows host as the controller reaches it over WinRM | the one the state keeps |
| `-Operator` | who else operates the nodes, each a certificate's subject, `CN=<person>`, as `New-XmipCertificate -Operator` names it, or an account: listed among every node's `[operate] operators` (`xmip-service --slice --operators`) beside this account's person, whose certificate the command makes (below) | the ones the state keeps; with none, this account's person alone, since a node's operate listener grants no one by default (ADR-0009) |

What it takes with no parameter:

- the packages a node is installed from — the `.rpm` for Linux, the
  portable archive for Windows (the MSI once it is built) — the module
  libraries the cluster file names, built for each system and carried
  beside every node's configuration, the far ends' program,
  `xmip-system-test-external`, for each system, and the slicer, this
  machine's `xmip-service`, which slices and signs each node's
  configuration: all from the build under `.local-work/package/<version>/`,
  refused naming `Build-XmipService` where absent;
- the environment's authority, which signs every slice and issues every
  certificate, kept in the private state's `authority` folder and made
  there where none is, and `operator.xmip` beside it: the slice of the node
  the cluster file declares `[provision.operator]` for, signed by that
  authority, which signs the operator's request (`Write-XmipOperatorSlice`,
  the one the System Tests' authority is written with too);
- every certificate, made in the private state where none is
  (`Initialize-XmipDeployIdentity`): each node's and far end's in
  `identity/<name>`, issued by `New-XmipCertificate -Node`; and the
  operator's in `operator/`, `operator.pem`, `operator.key` and
  `anchors.pem`, for this account's person, `CN=<account name>`, whom every
  node lists among its `[operate] operators`, with each `-Operator` given,
  and with which `Start-XmipTest -VirtualMachine` asks the nodes;
- the Windows machines' Administrator secret, generated once into the
  state, `Export-Clixml`, which encrypts it with Windows' Data Protection
  API for the account that deploys. Off Windows `Export-Clixml` keeps a
  password as plain text ([Microsoft's
  documentation](https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/export-clixml)),
  so a file whose password is not encrypted is refused wherever it is read,
  and an encrypted one is read on Windows alone;
- the AlmaLinux machines' account, `xmip-admin`, which is given the
  environment's own SSH key;
- what Microsoft DSC brings to each machine, `pwsh` and `dsc` for each
  system — tarballs for Linux, zips for Windows — their archives' names and
  SHA-256 in `prerequisite.toml`, `[prerequisite.powershell.archive]` and
  `[prerequisite.dsc.archive]`, found by name under `-ImageFolder`.

Refused in words before anything is made: on a Linux host, every Windows
machine, naming ADR-0015's third amendment of 2026-11-22, by which Windows
machines are not made from a Linux host yet — a smaller plan is a smaller
cluster file; and `-Technology ansible` on Windows, naming the command to
run in the WSL guest, which carries `-Hypervisor hyperv` and
`-WindowsHost`.

It keeps the environment's private state: on Linux under
`xmip/deploy/<cluster>` of `$XDG_STATE_HOME` or `~/.local/state`, on
Windows in the run folder, `.local-work/deploy/<cluster>`, its access this
account's alone, since a file on a Windows drive mounted in WSL shows as
`0777` and OpenSSH refuses a private key others may read. The run takes the
folder's `run.lock` before it writes anything there, so a second run of the
environment, `-WhatIf` too, is refused while one runs: two never install
its machines or start its nodes at once, and a run's keys and
`known_hosts` never change under it. Then the state is made where it is
not:

- `technology`, which the first run that applies writes: an environment is
  made by one technology, never a mix, so a run of the other one is refused
  until the environment is removed (below). A libvirt machine's record in
  its domain names the technology too, and the other is refused there.
- The network the command picked, and every parameter given once.
- The environment's own SSH key, `ssh/id_ed25519`, which each AlmaLinux
  machine's account is given. It has no passphrase, so a run needs nobody
  at the keyboard; with sudo without a password on every AlmaLinux machine,
  whoever reads it is root on every node, so how the key is held waits on
  the owner (ADR-0015, amendment 2026-11-11).
- A host key for each AlmaLinux machine, which its kickstart gives it, and
  `known_hosts` holding exactly those, so every login is checked strictly
  and none trusts on first use.
- The authority, `operator.xmip`, the certificates and the Windows
  machines' secret, above.
- `deployed.toml`, which a run that applies writes: the cluster file's path
  and SHA-256, the technology, the hypervisor, and each node's and far
  end's machine and address. `Start-XmipTest -VirtualMachine` reads it, for
  the System Tests and the Systems Tests alike, the run's node list from it
  and its operator certificate from `operator/`, resolving no name, and
  refuses a cluster file that changed since (ADR-0028, amendment
  2026-11-25). Its third switch, `-Container`, deploys nothing here: the
  run makes a Linux container for each node and far end itself, from the
  file's `[environment.container]` image and the same build under
  `.local-work/package/<version>/`, and slices each node with
  `Set-EnvironmentSlice` (`msdsc/environment/EnvironmentSlice.ps1`) as a
  machine's slice is made (ADR-0028, the second amendment of 2026-11-25).

The keys are kept as long as the folder is: a person reaches a machine with
`ssh -i <state>/ssh/id_ed25519 -o UserKnownHostsFile=<state>/known_hosts
xmip-admin@<address>`, the address `deployed.toml` gives it.

**msdsc** applies each document on its own, with the parameters it
declares: the network and the pool; each machine, one installation at a
time, applied again every thirty seconds until it answers from its disk;
the network's way out through its gateway machine, where the table names
one, `msdsc/environment/gateway.dsc.yaml`, after the domain's controller;
the names, where one of the machines is the network's DNS server; each far
end on its machine, senders then receivers,
`msdsc/environment/far-end.dsc.yaml`, its program placed and registered as
its service by its own `--install`; then each
node on its machine in the order the file declares them —
`msdsc/environment/machine.dsc.yaml`, which slices and signs the node's
configuration here, brings DSC to the machine and applies `node.dsc.yaml`
there — and last every node started together, `started.dsc.yaml`: a node
refuses to accept work until its cluster's Xmip Storage answers, and a
Storage node until every Storage node the cluster lists does (ADR-0056,
amendment 2026-11-08), so none of them starts alone, one machine after
another, and each is started again every five seconds until all run or
three minutes are spent. On an AlmaLinux machine nothing needs to be there
but sshd: the `pwsh` and `dsc` tarballs are checked against their SHA-256,
copied over SSH and unpacked in `/var/tmp/xmip-environment/tools`, and
`dsc` runs from there with sudo; a Windows machine is brought the two zips
the same way, under `C:\ProgramData\Xmip\environment\tools`. That staging folder is the login's alone,
`0700`, one another account owns refused; what a node is given, its key
among it, is sent to its `files` for each run of the document and removed
once `dsc` has run.

**ansible** writes `inventory.yml` and runs `ansible/environment.yml`: the
machines, one installation at a time, the way out through the gateway
machine (the role `xmip_gateway`), the names, the nodes, one machine at
a time, and last every node started together, as msdsc does; its role for
a far end's machine is not written. Each step of
a libvirt machine's installation is `machine/LibvirtInstallation.ps1`'s,
the code msdsc's machine resource runs, asked through `machine.ps1`. A node
machine's package is staged in Ansible's own folder,
`/var/tmp/xmip-ansible`, never msdsc's. Its controller is a Linux machine —
Ansible's control node does not run on Windows, and there the command is
refused, naming the WSL command to run instead, which carries the Windows
host's kind, `-Hypervisor hyperv`, and `-WindowsHost`. WSL is not what
Ansible supports for production; it is a test level 2 controller here.

One line is written per step, or per play: ETD, ATD and ETA, then the time
elapsed, left and in all. Everything DSC or Ansible says goes to the run
folder's `run.log`. `-WhatIf` tests and changes nothing, on a host where
nothing is made yet too: msdsc's resources answer what is not there as
absent; Ansible runs `--check`, where every read runs, every step that
would change says so, a machine not made yet is answered unreached, and a
host that would change or is not reached is not in its desired state.

## Before the first run

On a Windows host, Hyper-V, DSC and your account in the Hyper-V
Administrators group, as `msdsc/hyperv/README.md` says; on a Linux host,
the WSL AlmaLinux guest included, KVM and libvirt as
`msdsc/libvirt/README.md` says. Then, neither elevated nor with sudo:

- PowerShell 7.7 and the Xmip module's prerequisites;
- for msdsc, Microsoft DSC 3.4.0-preview.3 on `PATH`;
- for ansible, `prerequisite.toml`'s `[prerequisite.ansible]`, with its bin
  on `PATH`;
- the build the command takes what it ships from, under
  `.local-work/package/<version>/`: on Windows `Build-XmipService -Site
  personal-computer -CargoArgument '--release' -Package archive`, and on a
  Linux machine, with `nfpm`, the same with `-Package rpm`
  (`deploy/package/README.md`);
- in the image folder, every installation image the table's
  `[environment.images]` names, found by its SHA-256 whatever its file is
  called, and the `pwsh` and `dsc` archives `prerequisite.toml`'s
  `[prerequisite.powershell.archive]` and `[prerequisite.dsc.archive]`
  name, from their publishers, found by that name.

Nothing else is made by hand. No certificate: the command keeps the
environment's authority in its private state and issues every node's and
far end's certificate and your operator certificate where none is. No name is set up for the host — no rule or suffix that makes its
resolver ask the environment's DNS server: a run reads every node's and far
end's address from `deployed.toml`, and resolves no name. On Hyper-V the
Windows machines are reached through PowerShell Direct, which the Hyper-V
Administrators group allows.

The uplink stays yours to make, once, where the table names a `gateway`:
on Hyper-V an external switch onto the host's adapter on your network,
elevated, `New-VMSwitch -Name <uplink> -NetAdapterName <the host's
adapter> -AllowManagementOS $true`, the host keeping its own way out
through it; on libvirt a bridge of the host's holding that adapter, made
with the system's own network tools. Where the host has one, the command
finds it; where it has several, `-Uplink` names it once, never this folder.
A template refuses one that is not there or not external, and never makes,
changes or removes it: it takes a host adapter.

## Starting again from nothing

An environment's machines, network and pool are removed with the
hypervisor's own commands, after listing them to see they are the
environment's: the machines are `XMIP-<name>`, the network, the switch and
the pool `Xmip-<cluster>`.

- **libvirt**, with `virsh`: `virsh vol-list Xmip-<cluster>`, then `virsh
  destroy` and `virsh undefine --nvram --remove-all-storage` for each
  machine, `virsh vol-delete --pool Xmip-<cluster>` for each volume left,
  the images' among them, `virsh pool-destroy`, `pool-delete` and
  `pool-undefine`, and `virsh net-destroy` and `net-undefine`.
- **Hyper-V**, in an elevated Xmip PowerShell Console: `Get-VM`, then
  `Stop-VM -TurnOff` and `Remove-VM` for each machine, its folder under the
  disk folder's `Xmip-<cluster>` removed, and the switch `Xmip-<cluster>`
  with `Remove-VMSwitch`, the host's address on it with it, and its NAT, if
  the host's NAT was the way out, with `Remove-NetNat`. The uplink is yours
  and is kept.

Then the run and state folders, the state's `technology`, `deployed.toml`,
the authority and every certificate with them, so either technology may
make the environment again, under an authority made anew, and
`Start-XmipTest -VirtualMachine` is refused until one has. The images are
kept. On 2026-11-25 the owner had
the Hyper-V environment's every machine deleted, and the coordinator
accepted making it again from nothing.
