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
| `Xmip.HyperV/Network` | an internal switch, the host's address on it, the machines' gateway, and outbound NAT for the network's prefix |
| `Xmip.HyperV/Machine` | one machine, a generation 2 VM installed unattended from its ISO |

Each answers what is not there yet as absent — `_exist` false, and a
finding that says so — never as a failure, so `get` and `test` read a host
before anything is made on it. Only the host's own refusal, such as an
account Hyper-V does not let manage VMs, is an error.

## The example environment

`deploy/dsc/hyperv.example.toml`, which `Deploy-XmipEnvironment` reads
(`deploy/dsc/README.md`), describes the 21 machines of the owner's node
plan of 2026-11-22, the Mac beside them aside. Windows Server is Server
Core, Linux is installed minimal but on the one developer machine with a
desktop. Memory is what a machine starts with and, dynamic, the least and
the most Hyper-V gives it, the most the plan's figure:

| Machine | Operating system | Role | Memory | CPUs | Disk | Address |
| --- | --- | --- | --- | --- | --- | --- |
| XMIP-DC01 | Windows Server 2025 | domain controller and DNS | 2, 1-4 GiB | 2 | 64 GiB | 10.77.0.10 |
| XMIP-FS01 | Windows Server 2025 | file storage, optional | 1, 0.5-2 GiB | 2 | 64 GiB | 10.77.0.20 |
| XMIP-DS01 | AlmaLinux 10 | Xmip node DS1, Xmip Storage, primary | 2, 0.5-4 GiB | 2 | 32 GiB | 10.77.0.81 |
| XMIP-DS02 | Windows Server 2025 | Xmip node DS2, Xmip Storage, standby | 1, 0.5-4 GiB | 2 | 64 GiB | 10.77.0.82 |
| XMIP-RX01 | AlmaLinux 10 | Xmip node RX1, receiving; reaches past the network | 2, 0.5-3 GiB | 2 | 32 GiB | 10.77.0.41 |
| XMIP-RX02 | Windows Server 2025 | Xmip node RX2, receiving | 1, 0.5-3 GiB | 2 | 64 GiB | 10.77.0.42 |
| XMIP-RX03 | AlmaLinux 10 | Xmip node RX3, receiving | 2, 0.5-3 GiB | 2 | 32 GiB | 10.77.0.43 |
| XMIP-EX01 | Windows Server 2025 | Xmip node EX1, processing | 1, 0.5-4 GiB | 2 | 64 GiB | 10.77.0.52 |
| XMIP-EX02 | AlmaLinux 10 | Xmip node EX2, executing | 2, 0.5-4 GiB | 2 | 32 GiB | 10.77.0.53 |
| XMIP-TX01 | Windows Server 2025 | Xmip node TX1, sending | 1, 0.5-3 GiB | 2 | 64 GiB | 10.77.0.71 |
| XMIP-TX02 | AlmaLinux 10 | Xmip node TX2, sending | 2, 0.5-3 GiB | 2 | 32 GiB | 10.77.0.72 |
| XMIP-TX03 | Windows Server 2025 | Xmip node TX3, sending | 1, 0.5-3 GiB | 2 | 64 GiB | 10.77.0.73 |
| XMIP-EXTTX01 | AlmaLinux 10 | a far end that sends, external TX1 | 2, 0.5-2 GiB | 1 | 32 GiB | 10.77.0.91 |
| XMIP-EXTTX02 | Windows Server 2025 | a far end that sends, external TX2 | 1, 0.5-2 GiB | 1 | 64 GiB | 10.77.0.92 |
| XMIP-EXTTX03 | AlmaLinux 10 | a far end that sends, external TX3 | 2, 0.5-2 GiB | 1 | 32 GiB | 10.77.0.93 |
| XMIP-EXTRX01 | Windows Server 2025 | a far end that receives, external RX1 | 1, 0.5-2 GiB | 1 | 64 GiB | 10.77.0.101 |
| XMIP-EXTRX02 | AlmaLinux 10 | a far end that receives, external RX2 | 2, 0.5-2 GiB | 1 | 32 GiB | 10.77.0.102 |
| XMIP-EXTRX03 | Windows Server 2025 | a far end that receives, external RX3 | 1, 0.5-2 GiB | 1 | 64 GiB | 10.77.0.103 |
| XMIP-DEV02 | AlmaLinux 10, desktop | developer machine | 2, 1-4 GiB | 2 | 64 GiB | 10.77.0.32 |
| XMIP-DEV01 | Windows 11 | developer machine | 4, 2-4 GiB | 2 | 128 GiB | 10.77.0.31 |
| XMIP-OP01 | Windows 11 | operator machine | 4, 2-4 GiB | 2 | 128 GiB | 10.77.0.33 |

They share an internal switch, `Xmip`, on 10.77.0.0/24. The host is
10.77.0.1 on it, the one manual IPv4 address of the switch's host adapter,
with outbound NAT; the domain is `xmip.test`, and XMIP-DC01's address is
the DNS server every machine is given. Only XMIP-RX01 is given the host as
its gateway, its `internet` saying so where the network's says none does:
every other machine is installed with no gateway, and reaches the network
alone, the host on it included. The plan's Linux developer machine takes
the image `AlmaLinux10Desktop`, the same DVD installing
`workstation-product-environment`. The far ends run on their machines in
the plan; the Systems Tests serve them on the host still, until they are
built for machines of their own. The roles are the environment templates'
business; here they are a comment above each machine.

## What each machine is given

A folder, `<root>\<machine>`, and in it a new dynamic disk, `os.vhdx`, made
once and never resized or replaced. A generation 2 VM holding it, whose own
files Hyper-V keeps in that folder, with the memory it starts with, static,
or dynamic between the least and the most its `dynamic_memory` names, its
CPUs, no automatic checkpoints and the environment's name in its notes; its one
adapter on the switch with a static MAC made from its address (00-15-5D and
the address's last three octets); Secure Boot on with the template its image
names — `MicrosoftWindows` for Windows, `MicrosoftUEFICertificateAuthority`
for AlmaLinux — and a virtual TPM where its image asks for one (Windows 11).
Two DVD drives, and the boot order disk first, then the two drives. The
hardware is set only while the VM is off: one running and differing is
refused, never stopped, and so is one with more than one adapter, since
each would be given the machine's MAC: an adapter is never removed.

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

The ISOs go where the environment file names them, under
`D:\Downloads\OS\Images`. Then, as the Windows user that will run DSC, not
elevated: the Administrator secret of the Windows machines, encrypted to
that user on this host, and the environment file copied to where it is
yours:

```powershell
[string] $local = 'D:\Repos\Xmip\.local-work\hyperv'
New-Item -ItemType Directory -Force -Path $local
Get-Credential -UserName 'Administrator' -Message 'The Windows machines' |
    Export-Clixml -LiteralPath "$local\secret.xml"
[string] $example = 'D:\Repos\Xmip\deploy\dsc\hyperv.example.toml'
Copy-Item -LiteralPath $example -Destination 'D:\Repos\Xmip\.local-work\deploy\hyperv.toml'
```

In the copy, write in `linux_account`, the account the kickstart creates on
the AlmaLinux machines, `secret` and what the nodes are given
(`deploy/dsc/README.md`), and strike the machines you do not want. The
AlmaLinux machines' account is given the environment's own SSH key, which
`Deploy-XmipEnvironment` makes.

## Running it

In an elevated Xmip PowerShell Console, as the same user: the network
document asks for elevation as a whole, because a switch's host address and
NAT are an administrator's to set; the machine documents ask for none, since
a member of Hyper-V Administrators manages VMs unelevated. One command makes
the network and every machine, and waits until each is installed; `-WhatIf`
says what differs and changes nothing, on a fresh host too:

```powershell
Deploy-XmipEnvironment -Path 'D:\Repos\Xmip\.local-work\deploy\hyperv.toml' -WhatIf
Deploy-XmipEnvironment -Path 'D:\Repos\Xmip\.local-work\deploy\hyperv.toml'
```

It applies `network.dsc.yaml`, then `machine.dsc.yaml` once per machine,
each on its own with the parameters it declares and with this folder on
`PATH` so DSC finds the resources, and writes one line per step with the
time left. An installation runs on its own; while a machine installs, its
document is applied again every thirty seconds until it is installed, its
media gone, and running, and only then is the next machine made. The names
and the nodes follow (`deploy/dsc/msdsc/environment`). Everything DSC says
goes to `.local-work\deploy\<environment>\run.log`. The same environment
with `technology = "ansible"` is made by `deploy/dsc/ansible` from a Linux
controller.

## The files

| File | Is |
| --- | --- |
| `network.dsc.yaml` | the network, `Xmip.HyperV/Network` |
| `machine.dsc.yaml` | one machine, `Xmip.HyperV/Machine` |
| `hyperv.resource.ps1` | the resources' entry, run by DSC with the kind and the operation |
| `HyperVResource.ps1` | what the entry runs: the state each operation answers, and the parts below |
| `HyperVNetwork.ps1` | the switch, the host's address and NAT |
| `HyperVMachine.ps1` | the machine: its folder, disk and VM, and where it is |
| `HyperVHardware.ps1` | the VM's settings, devices and firmware |
| `HyperVInstallation.ps1` | the installation from the ISO |
| `xmip-hyperv-*.dsc.resource.yaml` | the resource manifests |
| `../../machine/HyperVDefinition.ps1` | the machine's folder files, static MAC, drives' places and answer medium, shared with Ansible's template |
| `../../machine/MachineAnswer.ps1` | the install answers and the answer medium, shared with the libvirt template |
| `../../machine/MachineGuest.ps1` | what the hypervisor gives its guest, its dynamic memory and chrony's clock line, shared with the libvirt template |
| `../../machine/autounattend.template.xml` | the Windows answer `MachineAnswer.ps1` fills in |

Each document requires DSC `^3.4.0-preview.3`, the latest release.

`test/MsdscHyperV.Test.ps1` holds what can be held without Hyper-V: the
documents read as YAML by DSC, their parameters and elevation, the
manifests found by DSC and every property each requires given, the example
environment as `Deploy-XmipEnvironment` applies it — the network, then each
machine — each step evaluated by DSC with every resource replaced by an
echo, this table of machines against it, the install answers and the answer
medium, and the resources' `get`, `test` and `set` with every Hyper-V and
network command a stub: a switch, a NAT and a machine that are not there
answered absent, a host's refusal kept an error, an absent network and
machine made, a machine given dynamic memory between its least and its
most, the gateway and a desktop where the example's machine has one, a
Windows 11 machine's TPM given before its media and Enter
pressed for its first twenty seconds, a machine still installing answered
by its state alone, a VM with two adapters refused, and an installed
machine's media removed.
