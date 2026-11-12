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
(`deploy/dsc/README.md`), describes eleven machines:

| Machine | Operating system | Role | Memory | CPUs | Disk | Address |
| --- | --- | --- | --- | --- | --- | --- |
| XMIP-DC01 | Windows Server 2025 | domain controller | 4 GiB | 2 | 64 GiB | 10.77.0.10 |
| XMIP-FS01 | Windows Server 2025 | file server | 4 GiB | 2 | 64 GiB | 10.77.0.20 |
| XMIP-DEV01 | Windows 11 | developer machine | 12 GiB | 4 | 128 GiB | 10.77.0.30 |
| XMIP-DB01 | AlmaLinux 10 | PostgreSQL | 4 GiB | 2 | 64 GiB | 10.77.0.41 |
| XMIP-DB02 | AlmaLinux 10 | PostgreSQL, standby of XMIP-DB01 | 4 GiB | 2 | 64 GiB | 10.77.0.42 |
| XMIP-APP01 | Windows Server 2025 | Xmip node | 4 GiB | 2 | 64 GiB | 10.77.0.51 |
| XMIP-APP02 | Windows Server 2025 | Xmip node | 4 GiB | 2 | 64 GiB | 10.77.0.52 |
| XMIP-APP03 | Windows Server 2025 | Xmip node | 4 GiB | 2 | 64 GiB | 10.77.0.53 |
| XMIP-APP04 | Windows Server 2025 | Xmip node | 4 GiB | 2 | 64 GiB | 10.77.0.54 |
| XMIP-IN01 | AlmaLinux 10 | Xmip node | 4 GiB | 2 | 32 GiB | 10.77.0.61 |
| XMIP-OUT01 | AlmaLinux 10 | Xmip node | 4 GiB | 2 | 32 GiB | 10.77.0.71 |

They share an internal switch, `Xmip`, on 10.77.0.0/24. The host is
10.77.0.1 on it, the machines' gateway and the one manual IPv4 address of
the switch's host adapter, with outbound NAT; the domain is `xmip.test`, and
XMIP-DC01's address is the DNS server the AlmaLinux machines are given. The
roles are the environment templates' business; here they are a comment
above each machine.

## What each machine is given

A folder, `<root>\<machine>`, and in it a new dynamic disk, `os.vhdx`, made
once and never resized or replaced. A generation 2 VM holding it, whose own
files Hyper-V keeps in that folder, with static memory, its CPUs, no
automatic checkpoints and the environment's name in its notes; its one
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
  `NAME` in the ISO's `sources\install.wim`), sets the computer name, enables
  the built-in Administrator with the password in the secret file, and
  skips the out-of-box experience. The password is in Windows's answer-file
  encoding, Base64, which keeps it from a glance, not from a reader. A
  Windows ISO boots only after *Press any key to boot from CD or DVD*, so for
  the first twenty seconds of that start the template presses Space through
  Hyper-V's virtual keyboard.
- **AlmaLinux**: the answer medium is labeled `OEMDRV` and holds `ks.cfg`, a
  kickstart, which the installer reads from a volume of that label without
  being told to. It installs from the DVD's own repositories: the host name
  in the domain, the static address on the adapter with the static MAC, the
  gateway and DNS server, the Linux account with the SSH key and sudo without
  a password, root locked, sshd and firewalld on.

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
Add-AppxPackage -Path https://github.com/PowerShell/DSC/releases/download/v3.4.0-preview.2/DSC-3.4.0-preview.2-Win.msixbundle
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
| `../../machine/autounattend.template.xml` | the Windows answer `MachineAnswer.ps1` fills in |

Each document requires DSC `^3.4.0-preview.2`, the latest release.

`test/MsdscHyperV.Test.ps1` holds what can be held without Hyper-V: the
documents read as YAML by DSC, their parameters and elevation, the
manifests found by DSC and every property each requires given, the example
environment as `Deploy-XmipEnvironment` applies it — the network, then each
machine — each step evaluated by DSC with every resource replaced by an
echo, this table of machines against it, the install answers and the answer
medium, and the resources' `get`, `test` and `set` with every Hyper-V and
network command a stub: a switch, a NAT and a machine that are not there
answered absent, a host's refusal kept an error, an absent network and
machine made, a Windows 11 machine's TPM given before its media and Space
pressed for its first twenty seconds, a machine still installing answered
by its state alone, a VM with two adapters refused, and an installed
machine's media removed.
