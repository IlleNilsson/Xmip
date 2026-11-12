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
| `machine/` | what a machine is, for both: the network, pool and domain definitions, the kickstart, the Windows answer file and the answer medium, each step of a libvirt machine's installation and how the Windows machines' secret is read, plain PowerShell 7 that DSC's resources dot-source and Ansible's role asks through `machine.ps1` |

## The environment file

One TOML file says what an environment is, and nothing else does: which
node runs on which machine is here, never in the cluster's file
(ADR-0028, amendment 2026-10-21). The examples are `libvirt.example.toml`,
for a Linux host's KVM, and `hyperv.example.toml`, for a Windows host's
Hyper-V; copy one to `.local-work/deploy/` and write in what it leaves
empty.

| Key | Is |
| --- | --- |
| `name` | the environment, its run folder's and its pool's name |
| `technology` | `msdsc` or `ansible`: the template set that makes all of it. Required; a file without it is refused |
| `hypervisor` | `libvirt` or `hyperv`, whose machines the technology makes |
| `root`, `domain`, `cluster` | where the machines' disks are, their DNS domain, and the cluster's name |
| `linux_account` | the account each AlmaLinux machine is installed with, which is given the environment's own SSH key |
| `secret` | the Windows machines' Administrator password, `Export-Clixml` on Windows by the account that deploys, which encrypts it for that account. Off Windows `Export-Clixml` keeps a password as plain text ([Microsoft's documentation](https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/export-clixml)), so a file whose password is not encrypted is refused wherever it is read, and an encrypted one is read on Windows alone |
| `configuration` | the cluster's file, each node's configuration sliced from it |
| `slicer` | this machine's `xmip-service`, which slices each node's configuration and signs it |
| `authority`, `identity` | the cluster's authority, which signs each slice and issued each node's certificate, and a folder per node of that certificate (`New-XmipCertificate -Node`) |
| `far_end` | where the machines reach the Parties' far end the Essentials serves |
| `[packages.<family>]` | the package a node is installed from, `path`: the `.rpm` for Linux, the MSI for Windows |
| `[tools.<family>]` | msdsc only: the tarballs DSC is brought to each AlmaLinux machine with, `pwsh` and `dsc`, each `path` and `sha256` |
| `[network]`, `[images.<name>]`, `[[machines]]` | the network, the installation images, and each machine with the `nodes` it runs: one at most, since a package lays one node out in one folder; every Storage node the cluster's file lists on a machine of its own |

A path not rooted is the estate's. The YAML each tool reads is written
from this file into the run folder, `.local-work/deploy/<name>/`: DSC's
`<step>.parameters.yaml` and Ansible's `inventory.yml`. It is generated,
never configuration (CONTRIBUTING).

## The command

```powershell
Deploy-XmipEnvironment -Path /mnt/d/Repos/Xmip/.local-work/deploy/libvirt.toml
```

It keeps the environment's private state: on Linux under
`~/.local/state/xmip/deploy/<name>`, on Windows in the run folder, its
access this account's alone, since a file on a Windows drive mounted in WSL
shows as `0777` and OpenSSH refuses a private key others may read. The run
takes the folder's `run.lock` before it writes anything there, so a second
run of the environment, `-WhatIf` too, is refused while one runs: two never
install its machines or start its nodes at once, and a run's keys and
`known_hosts` never change under it. Then the state is made where it is
not:

- `technology`, which the first run that applies writes: an environment is
  made by one technology, never a mix, so a run of the other one is refused
  until the environment is removed (below). A libvirt machine's record in
  its domain names the technology too, and the other is refused there.
- The environment's own SSH key, `ssh/id_ed25519`, which each AlmaLinux
  machine's account is given. It has no passphrase, so a run needs nobody
  at the keyboard; with sudo without a password on every AlmaLinux machine,
  whoever reads it is root on every node, so how the key is held waits on
  the owner (ADR-0015, amendment 2026-11-11).
- A host key for each AlmaLinux machine, which its kickstart gives it, and
  `known_hosts` holding exactly those, so every login is checked strictly
  and none trusts on first use.

The keys are kept as long as the folder is: a person reaches a machine with
`ssh -i <state>/ssh/id_ed25519 -o UserKnownHostsFile=<state>/known_hosts
<linux_account>@<address>`.

**msdsc** applies each document on its own, with the parameters it
declares: the network and the pool; each machine, one installation at a
time, applied again every thirty seconds until it answers from its disk;
the names, where one of the machines is the network's DNS server; then each
node on its machine in the order the file lists them —
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
`dsc` runs from there with sudo. That staging folder is the login's alone,
`0700`, one another account owns refused; what a node is given, its key
among it, is sent to its `files` for each run of the document and removed
once `dsc` has run.

**ansible** writes `inventory.yml` and runs `ansible/environment.yml`: the
machines, one installation at a time, the names, the nodes, one machine at
a time, and last every node started together, as msdsc does. Each step of
a libvirt machine's installation is `machine/LibvirtInstallation.ps1`'s,
the code msdsc's machine resource runs, asked through `machine.ps1`. A node
machine's package is staged in Ansible's own folder,
`/var/tmp/xmip-ansible`, never msdsc's. Its controller is a Linux machine —
Ansible's control node does not run on Windows, and there the command is
refused, naming the WSL command to run instead. WSL is not what Ansible
supports for production; it is a test level 2 controller here.

One line is written per step, or per play: ETD, ATD and ETA, then the time
elapsed, left and in all. Everything DSC or Ansible says goes to the run
folder's `run.log`. `-WhatIf` tests and changes nothing, on a host where
nothing is made yet too: msdsc's resources answer what is not there as
absent; Ansible runs `--check`, where every read runs, every step that
would change says so, a machine not made yet is answered unreached, and a
host that would change or is not reached is not in its desired state.

## Before the first run

On the Linux host, the WSL AlmaLinux guest included, KVM and libvirt as
`msdsc/libvirt/README.md` says, then, with no sudo:

- PowerShell 7.7 and the Xmip module's prerequisites;
- for msdsc, Microsoft DSC 3.4.0-preview.2 on `PATH`, and the two tarballs
  the file's `[tools.Linux]` names, from their GitHub releases;
- for ansible, `prerequisite.toml`'s `[prerequisite.ansible]`, with its bin
  on `PATH`;
- `nfpm` and a Linux build of `xmip-service`: `Build-XmipService -Site
  personal-computer -CargoArgument '--release' -Package rpm`, the package
  and the `slicer` both (`deploy/package/README.md`);
- on Windows, not elevated, the cluster's authority and each node's
  certificate: `New-XmipCertificate -Node R1 -Cluster C1 -Authority
  D:\Repos\Xmip\.local-work\environment\authority -Path
  D:\Repos\Xmip\.local-work\environment\identity\R1`, and the same for
  every node the file maps.

## Starting again from nothing

An environment's machines, network and pool are removed with libvirt's own
`virsh`, after listing the pool's volumes to see they are the
environment's: `virsh vol-list xmip`, then `virsh destroy` and `virsh
undefine --nvram --remove-all-storage` for each machine, `virsh vol-delete
--pool xmip` for each volume left, the ISO's among them, `virsh
pool-destroy`, `pool-delete` and `pool-undefine`, `virsh net-destroy` and
`net-undefine`, and the run and state folders, the state's `technology`
with it, so either technology may make the environment again.
