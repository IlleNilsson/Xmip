# Xmip machines on Hyper-V, with Microsoft DSC v3

A template for the virtual machines an Xmip environment runs on, for one
virtualization technology: Hyper-V on a Windows host. It makes the network
and, for each machine, a VM that installs its operating system unattended
from the publisher's ISO. Another technology gets a folder of its own beside
this one, `deploy/dsc/msdsc/<technology>`, as `libvirt` is for a Linux
host; Ansible's desired state is `deploy/dsc/ansible`, and an environment
uses one of the two, never a mix (ADR-0015, amendment 2026-10-09).

What runs inside a machine once it is installed is not this template's. The
Xmip nodes and the names of the cluster and its nodes are the environment
templates', `deploy/dsc/msdsc/environment` and, the same set in Ansible,
`deploy/dsc/ansible`, each for Windows and AlmaLinux alike (ADR-0015,
amendment 2026-10-21); the domain and PostgreSQL are not written yet.

The template's resources are Xmip's own: PowerShell 7 behind resource
manifests, as the libvirt template's and `Xmip.Node` are, asking Hyper-V's
and Windows's own commands. Every rule about a switch, an address, a NAT or
a VM is theirs (ADR-0015, amendment 2026-11-11).

| Resource | Is |
| --- | --- |
| `Xmip.HyperV/Network` | an internal switch, the host's address on it, the machines' gateway, and outbound NAT for the network's prefix; or, where a gateway machine is the way out, no NAT and the uplink found, an external switch, never made |
| `Xmip.HyperV/Machine` | one machine, a generation 2 VM installed unattended from its ISO, a gateway machine with its second adapter on the uplink |

Each answers what is not there yet as absent — `_exist` false, and a
finding that says so — never as a failure, so `get` and `test` read a host
before anything is made on it. Only the host's own refusal, such as an
account Hyper-V does not let manage VMs, is an error.

## The System Tests' environment

The `[environment]` table of the Reference Environment, which
`Deploy-XmipEnvironment` reads (`deploy/dsc/README.md`, *The environment
table*), describes the 21 machines of the owner's node plan of 2026-11-22,
the Mac beside them aside: the machines of their own, the far ends and every
node of the file, OP1 on the plan's operator machine (ADR-0028, amendment
2026-11-25). Windows Server is Server Core, Linux is installed minimal but
on the one developer machine with a desktop. Memory is what a machine
starts with and, dynamic, the least and the most Hyper-V gives it, the most
the plan's figure; the file says each figure where it differs from
`[environment.machine]`'s. The machines are listed in the order their
addresses are given:

| Machine | Operating system | Role | Memory | CPUs | Disk |
| --- | --- | --- | --- | --- | --- |
| XMIP-DC01 | Windows Server 2025 | domain controller, DNS and the network's gateway | 2, 1-4 GiB | 2 | 64 GiB |
| XMIP-FS01 | Windows Server 2025 | file storage, optional | 1, 0.5-2 GiB | 2 | 64 GiB |
| XMIP-DEV01 | Windows 11 | developer machine | 4, 2-4 GiB | 2 | 128 GiB |
| XMIP-DEV02 | AlmaLinux 10, desktop | developer machine | 2, 1-4 GiB | 2 | 64 GiB |
| XMIP-EXTTX1 | AlmaLinux 10 | a far end that sends, external TX1 | 2, 0.5-2 GiB | 1 | 32 GiB |
| XMIP-EXTTX2 | Windows Server 2025 | a far end that sends, external TX2 | 1, 0.5-2 GiB | 1 | 64 GiB |
| XMIP-EXTTX3 | AlmaLinux 10 | a far end that sends, external TX3 | 2, 0.5-2 GiB | 1 | 32 GiB |
| XMIP-EXTRX1 | Windows Server 2025 | a far end that receives, external RX1 | 1, 0.5-2 GiB | 1 | 64 GiB |
| XMIP-EXTRX2 | AlmaLinux 10 | a far end that receives, external RX2 | 2, 0.5-2 GiB | 1 | 32 GiB |
| XMIP-EXTRX3 | Windows Server 2025 | a far end that receives, external RX3 | 1, 0.5-2 GiB | 1 | 64 GiB |
| XMIP-RX1 | AlmaLinux 10 | Xmip node RX1, receiving | 2, 0.5-3 GiB | 2 | 32 GiB |
| XMIP-RX2 | Windows Server 2025 | Xmip node RX2, receiving | 1, 0.5-3 GiB | 2 | 64 GiB |
| XMIP-RX3 | AlmaLinux 10 | Xmip node RX3, receiving | 2, 0.5-3 GiB | 2 | 32 GiB |
| XMIP-EX1 | Windows Server 2025 | Xmip node EX1, processing | 1, 0.5-4 GiB | 2 | 64 GiB |
| XMIP-EX2 | AlmaLinux 10 | Xmip node EX2, executing | 2, 0.5-4 GiB | 2 | 32 GiB |
| XMIP-TX1 | Windows Server 2025 | Xmip node TX1, sending | 1, 0.5-3 GiB | 2 | 64 GiB |
| XMIP-TX2 | AlmaLinux 10 | Xmip node TX2, sending | 2, 0.5-3 GiB | 2 | 32 GiB |
| XMIP-TX3 | Windows Server 2025 | Xmip node TX3, sending | 1, 0.5-3 GiB | 2 | 64 GiB |
| XMIP-OP1 | Windows 11 | Xmip node OP1, operational and monitoring, on the operator machine | 4, 2-4 GiB | 2 | 128 GiB |
| XMIP-DS1 | AlmaLinux 10 | Xmip node DS1, Xmip Storage, primary | 2, 0.5-4 GiB | 2 | 32 GiB |
| XMIP-DS2 | Windows Server 2025 | Xmip node DS2, Xmip Storage, standby | 1, 0.5-4 GiB | 2 | 64 GiB |

They share an internal switch, `Xmip-<cluster>`, on the network the table
names, or, since the System Tests' file names none, a free private /24 the
command picks on the host and keeps in the environment's state. The host
is the range's first address, the one manual IPv4 address of the switch's
host adapter, and the machines take the next in the order above, the
machines of their own in the file's order; the domain is `xmip.test`, and
the `domain_controller`'s address is the DNS server every machine is given.
The `gateway`, XMIP-DC01 in the owner's plan, is the network's way out: a
second adapter, `Uplink`, on the host's external switch, behind your
firewall, with NAT on it (`deploy/dsc/README.md`, *The way out*). Only the
machine of a node that declares the Node capability `online` is given it
as its gateway: every other machine is installed with no gateway, and
reaches the network alone, the host on it included. Name no `gateway`, and
the host's own NAT is the way out where any node is online. The plan's
Linux developer machine takes an image of the same DVD installing
`workstation-product-environment`. Each far end runs on its machine, as
the plan has it, for the System Tests and the Systems Tests alike; the far
end the System Tests served on the host for nodes on machines is deleted
from the rig. What runs inside a machine is the environment templates'
business; its role is said in its Notes (below).

## What each machine is given

A folder, `<disk folder>\Xmip-<cluster>\<machine>`, and in it a new
dynamic disk, `os.vhdx`, made once and never resized or replaced. A
generation 2 VM holding it, whose own files Hyper-V keeps in that folder,
with the memory it starts with, static, or dynamic between the least and
the most its `dynamic_memory` names, its CPUs, no automatic checkpoints,
and in its Notes its role and its operating system in one line, the role
from what the cluster file declares and the system from its image's
`name`, such as *Receiving node RX1 · AlmaLinux 10* (`deploy/dsc/README.md`,
*The environment table*); its one
adapter on the switch with a static MAC made from its address (00-15-5D and
the address's last three octets), and the gateway machine a second,
`Uplink`, on the uplink, its MAC the same with its first octet 02, a
locally administered address no vendor's adapter holds, which your
network's DHCP addresses; Secure Boot on with the template its image
names — `MicrosoftWindows` for Windows, `MicrosoftUEFICertificateAuthority`
for AlmaLinux — and a virtual TPM where its image asks for one (Windows 11).
Two DVD drives, and the boot order disk first, then the two drives, then
its own adapter, never the uplink. The hardware is set only while the VM is
off: one running and differing is refused, never stopped, and so is one
with more than one adapter of its own, since each would be given the
machine's MAC, or an `Uplink` it is not given: an adapter is never removed.

On its first start the VM holds its ISO, checked against the SHA-256 the
parameters give, and an answer medium this template writes for it, an ISO
image made with the image mastering API every Windows host has. The empty
disk does not boot, so the firmware moves on to the ISO, which installs onto
the disk; every later boot starts from the disk.

- **Windows**: the answer medium holds `autounattend.xml`, which Windows
  Setup reads from the root of a removable medium. It partitions the disk for
  UEFI, installs the image the parameters name as `edition` (the image's
  `NAME` in the ISO's `sources\install.wim`), sets the computer name, the
  static address, the DNS server and, where the machine has a gateway, a
  route out through it, enables the built-in Administrator with the password
  in the secret file, and skips the out-of-box experience. The password is
  in Windows's answer-file encoding, Base64, which keeps it from a glance,
  not from a reader. A
  Windows ISO boots only after *Press any key to boot from CD or DVD*, so for
  the first twenty seconds of that start the template presses Enter through
  Hyper-V's virtual keyboard: a later press stops the Windows Boot
  Manager's countdown, and only Enter then chooses Windows Setup.
- **AlmaLinux**: the answer medium is labeled `OEMDRV` and holds `ks.cfg`, a
  kickstart, which the installer reads from a volume of that label without
  being told to. It installs from the DVD's own repositories the environment
  group its image names, `minimal-environment` where it names none, a
  desktop started to its graphical target: the host name in the domain, the
  static address on the adapter with the static MAC, the gateway where the
  machine has one, the DNS server, the Linux account with the SSH key and
  sudo without a password, root locked, sshd and firewalld on, and chrony
  keeping Hyper-V's clock (`refclock PHC /dev/ptp_hyperv`, the device udev
  names for the guest's `hyperv` clock), since a machine with no way out
  reaches no pool.

The installation is done when the guest answers from its disk: a Windows
machine opens PowerShell Direct as its Administrator, an AlmaLinux machine
answers SSH at its address. Until then `set` leaves it, and its state says
so, `installation` `Installing`: a resource writes nothing but its answer,
which DSC reads from its standard output. The next `set` then empties both
DVD drives, deletes the answer medium and writes `installed` in the
machine's folder, so a VM found off later is started from its disk and
never installed again. Delete that file and the disk to install a machine
anew.

## Before the first run

Once, in an elevated Xmip PowerShell Console, then restart the host:
Hyper-V, Microsoft DSC v3, and your account a member of the host's Hyper-V
Administrators group (its SID is `S-1-5-32-578` in every language), which
lets it manage VMs unelevated:

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
Add-AppxPackage -Path https://github.com/PowerShell/DSC/releases/download/v3.4.0-preview.3/DSC-3.4.0-preview.3-Win.msixbundle
[string] $account = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
Add-LocalGroupMember -SID 'S-1-5-32-578' -Member $account
```

The ISOs go into the image folder: the account's Xmip folder's `images`,
`%LOCALAPPDATA%\Xmip\images`, or one `-ImageFolder` names once, each found
there by the SHA-256 its `[environment.images.<os>]` gives, whatever its
file is called. Nothing else is written by hand: the Windows machines'
Administrator secret is the command's, generated once into the
environment's state and encrypted to the user that deploys, and so is the
AlmaLinux machines' account, `xmip-admin`, given the environment's own SSH
key. A smaller plan is a smaller cluster file: a cluster of your own names
the machines it wants in its own `[environment]`.

The uplink XMIP-DC01's second adapter is on is an external switch onto the
host's adapter on your network, behind your firewall. It takes that
adapter, the host keeping its own way out through it, so it is yours to
make, once, in an elevated Xmip PowerShell Console, and the template finds
it, refuses one that is not there or not external, and never makes, changes
or removes it. Its name is your own: the command finds the host's one
external switch, or `-Uplink` names it once, kept in the state, where there
are several:

```powershell
Get-NetAdapter -Physical
New-VMSwitch -Name '<uplink>' -NetAdapterName '<the host''s adapter on your network>' -AllowManagementOS $true
```

Without it, name no `gateway`: the host is the network's way out. A
XMIP-DC01 made before the uplink was there is running with one adapter,
and its hardware changes only while it is off: the run refuses it, never
stopping it, until you shut it down once.

## Running it

In an elevated Xmip PowerShell Console, as the same user: the network
document asks for elevation as a whole, because a switch's host address and
NAT are an administrator's to set; the machine documents ask for none, since
a member of Hyper-V Administrators manages VMs unelevated. A run not
elevated is refused, naming the console, and none is started. One command
makes the network and every machine, Hyper-V being the Windows host's kind,
and waits until each is installed; `-WhatIf` says what differs and changes
nothing, on a fresh host too:

```powershell
[string] $cluster = 'D:\Repos\Xmip\test\core\system-test\configuration\Xmip-reference-environment.xmip'
Deploy-XmipEnvironment -Path $cluster -WhatIf
Deploy-XmipEnvironment -Path $cluster
```

It applies `network.dsc.yaml`, then `machine.dsc.yaml` once per machine,
each on its own with the parameters it declares and with this folder on
`PATH` so DSC finds the resources, and writes one line per step with the
time left. An installation runs on its own; while a machine installs, its
document is applied again every thirty seconds until it is installed, its
media gone, and running, and only then is the next machine made. The names
and the nodes follow (`deploy/dsc/msdsc/environment`). Everything DSC says
goes to `.local-work\deploy\<cluster>\run.log`. The same environment
with `-Technology ansible` is made by `deploy/dsc/ansible` from a Linux
controller, the command naming the one to run there.

## The files

| File | Is |
| --- | --- |
| `network.dsc.yaml` | the network, `Xmip.HyperV/Network` |
| `machine.dsc.yaml` | one machine, `Xmip.HyperV/Machine` |
| `hyperv.resource.ps1` | the resources' entry, run by DSC with the kind and the operation |
| `HyperVResource.ps1` | what the entry runs: the state each operation answers, and the parts below |
| `HyperVNetwork.ps1` | the switch, the host's address and NAT, and the uplink found |
| `HyperVMachine.ps1` | the machine: its folder, disk and VM, and where it is |
| `HyperVHardware.ps1` | the VM's settings, devices and firmware |
| `HyperVInstallation.ps1` | the installation from the ISO |
| `xmip-hyperv-*.dsc.resource.yaml` | the resource manifests |
| `../../machine/HyperVDefinition.ps1` | the machine's folder files, static MAC, the uplink adapter's name and MAC, drives' places and answer medium, shared with Ansible's template |
| `../../machine/HyperVUplink.ps1` | the uplink, one external switch, found; handed to the host whole by Ansible's template |
| `../../machine/MachineAnswer.ps1` | the install answers and the answer medium, shared with the libvirt template |
| `../../machine/MachineGuest.ps1` | what the hypervisor gives its guest, its dynamic memory and chrony's clock line, shared with the libvirt template |
| `../../machine/autounattend.template.xml` | the Windows answer `MachineAnswer.ps1` fills in |

Each document requires DSC `^3.4.0-preview.3`, the latest release.

`test/MsdscHyperV.Test.ps1` holds what can be held without Hyper-V: the
documents read as YAML by DSC, their parameters and elevation, the
manifests found by DSC and every property each requires given, the System
Tests' environment as `Deploy-XmipEnvironment` applies it — the network, then each
machine — each step evaluated by DSC with every resource replaced by an
echo, this table of machines against it, the install answers and the answer
medium, and the resources' `get`, `test` and `set` with every Hyper-V and
network command a stub: a switch, a NAT and a machine that are not there
answered absent, a host's refusal kept an error, an absent network and
machine made, an uplink that is not one external switch refused and never
made, a gateway machine given its `Uplink` and never booted from it, an
`Uplink` on any other machine refused, a machine given dynamic memory
between its least and its most, the gateway and a desktop where the
plan's machine has one, a
Windows 11 machine's TPM given before its media and Enter
pressed for its first twenty seconds, a machine still installing answered
by its state alone, a VM with two adapters refused, and an installed
machine's media removed.
