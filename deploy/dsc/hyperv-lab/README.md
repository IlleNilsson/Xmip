# The Hyper-V lab

Ten virtual machines on one Hyper-V host, set up and kept with Microsoft DSC
v3: a domain, a file server, a developer machine, a PostgreSQL primary and its
standby, and five Xmip nodes on Windows Server and AlmaLinux. Everything is
desired state: `dsc config test` says what differs, in words, and
`dsc config set` makes it so, stopping where a reboot or another machine must
come first.

| Machine | Operating system | Role | Address |
| --- | --- | --- | --- |
| XMIP-DC01 | Windows Server 2025 | domain controller and DNS for `xmip.test` | 10.77.0.10 |
| XMIP-FS01 | Windows Server 2025 | file server, the encrypted `XmipLab` share | 10.77.0.20 |
| XMIP-DEV01 | Windows 11 26H2 | developer machine, the estate's prerequisites | 10.77.0.30 |
| XMIP-DB01 | AlmaLinux 10 | PostgreSQL 18, primary | 10.77.0.41 |
| XMIP-DB02 | AlmaLinux 10 | PostgreSQL 18, streaming standby of XMIP-DB01 | 10.77.0.42 |
| XMIP-APP01 | Windows Server 2025 | Xmip node, `processing` | 10.77.0.51 |
| XMIP-APP02 | Windows Server 2025 | Xmip node, `processing` | 10.77.0.52 |
| XMIP-APP03 | Windows Server 2025 | Xmip node, `processing` | 10.77.0.53 |
| XMIP-IN01 | AlmaLinux 10 | Xmip node, `receiving` | 10.77.0.61 |
| XMIP-OUT01 | AlmaLinux 10 | Xmip node, `sending` | 10.77.0.71 |

The host is the gateway, 10.77.0.1, on an internal switch with outbound NAT.
The machines, their sizes and addresses are `lab.json`'s; the table is the
example's, `lab.example.json`.

## What each machine is given

**Every machine is installed from its operating system's ISO**, unattended,
onto a new disk of its own, `DiskGB` in `lab.json`. Its VM has the disk and
two DVD drives: the ISO, and a small answer medium the lab generates for the
machine, an ISO image written with the image mastering API every Windows host
has, so no tool is installed for it. The disk comes first in the boot order.
While it is empty the firmware moves on to the ISO, which installs Windows or
AlmaLinux onto it; every later boot starts from the disk, so nothing installs
twice. Every machine has a static MAC made from its address and Secure Boot
on, with its operating system's template: `MicrosoftWindows` for Windows,
`MicrosoftUEFICertificateAuthority` for AlmaLinux; Windows 11 also gets a
virtual TPM. Once a machine's guest answers, PowerShell Direct for Windows
and SSH for AlmaLinux, the lab ejects both media and deletes the answer
medium; until then `test` reports the machine as installing from its ISO.

**The Windows machines'** answer medium holds `autounattend.xml`, which
Windows Setup reads from the root of a removable medium. It partitions the
disk for UEFI, installs the image `lab.json` names as the Os's `Edition`, sets
the computer name, enables the built-in Administrator with the lab's password,
and skips the out-of-box experience. Windows keeps a password in an answer
file in an encoding, Base64, not in plain text; that keeps it from a glance,
not from a reader, which is why the medium is deleted once the guest answers.
A Windows ISO boots only after *Press any key to boot from CD or DVD*, and on
Hyper-V nobody is there to press one, so for the first twenty seconds after
the lab starts a machine still installing it presses Space through Hyper-V's
virtual keyboard (`Msvm_Keyboard`), as Packer does. That leaves the ISO as
Microsoft published it, which its hash says; rebuilding it with the
no-prompt boot file instead would take a tool the host does not have and a
copy of every ISO. From then on the machines are configured through
PowerShell Direct: static address, the domain (the Windows Server 2025
machines and XMIP-DEV01 are domain members), then their role.

**The AlmaLinux machines'** answer medium is labelled `OEMDRV` and holds
`ks.cfg`, a kickstart, which AlmaLinux's installer reads from a volume of that
label without being told to. The DVD's boot menu starts its default entry,
which checks the DVD first, after its sixty seconds; the kickstart installs
from the DVD's own repositories, with no network: the host name, the static
address on the adapter with the static MAC, the domain controller as its DNS
server, the account `xmiplab` with the lab's SSH key, no password and sudo
without one, root locked, sshd and firewalld on. From then on the host reaches
it over SSH only: it copies the guest's payload to `/opt/xmip-lab`, installs
PowerShell and DSC v3 there from the RPMs you supply, and runs the guest's
own DSC document, `linux/linux.dsc.yaml`, whose resource
`Xmip.Lab/LinuxGuest` is `linux/LabLinuxGuest.ps1`.

The answers are each written by one function, `Get-LabWindowsAnswer` and
`Get-LabKickstart` in `LabAnswer.ps1`, and are text and nothing else, so
another desired-state technology installing the same machines can take them.

The AlmaLinux machines are not domain members; the domain controller holds a
DNS record for each, so every machine reaches them by name.

**PostgreSQL** is installed from the PostgreSQL project's repository and set
up as `deploy/database/postgresql/README.md` tells IT to: the settings Xmip
depends on, TLS 1.3, `xmip_storage` admitted over TLS from the lab network
only and nothing remote in the clear, and the four generated scripts run on
the primary, each only where what it makes is missing. The standby is a
streaming replica of the primary over a physical replication slot, copied
with `pg_basebackup` over TLS checked against the lab's authority by name.
Replication and failover are the lab's, as they are IT's at a site
(`doc/architecture/deployment-model.md` section 9); a machine is a standby
because `lab.json` says `"StandbyOf"`.

**An Xmip node** gets the layout under `C:\ProgramData\Xmip` or `/opt/xmip`,
the program you built, and the lab cluster's `xmip.toml`, which declares
each node and its roles. Its `config/xmip-node.toml` is what
`xmip-service --configuration xmip.toml --node <name> --slice` prints: the
one slicing (`deployment-model.md` section 8). A node's name is its machine's,
and the roles are the cluster file's alone; change them there. The program is
not registered as a service: desired state places and slices, as
`deploy/dsc/xmip-node.dsc.yaml` and the Ansible role do. No node declares
`storage`: Storage nodes reached over the wire are
[built, not in the assembled service](../../../doc/architecture/estate-map.md#storage-nodes),
and Xmip Storage in front of PostgreSQL is
[decided, not built](../../../doc/architecture/estate-map.md#database-server).

## Before the first run

In an elevated Xmip PowerShell Console on the host, once, then reboot:

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
winget install --id Microsoft.DSC --exact
```

**Media.** The three ISOs, each in `D:\Downloads\OS\Images\<publisher>`, the
PowerShell MSI for XMIP-DEV01, and the PowerShell and DSC RPMs for the
AlmaLinux machines:

```powershell
[string] $images = 'D:\Downloads\OS\Images'
New-Item -ItemType Directory -Force -Path "$images\Microsoft", "$images\AlmaLinux", 'D:\Installers'
Invoke-WebRequest -Uri 'https://go.microsoft.com/fwlink/?linkid=2293312&clcid=0x409&culture=en-us&country=us' -OutFile "$images\Microsoft\WindowsServer2025-Eval-26100.1742-en-us.iso"
Invoke-WebRequest -Uri 'https://go.microsoft.com/fwlink/?LinkId=2382600&clcid=0x409&culture=en-us&country=us' -OutFile "$images\Microsoft\Windows11-Enterprise-Eval-26H2-26300.9457-en-us.iso"
[string] $alma = 'https://repo.almalinux.org/almalinux/10/isos/x86_64'
Invoke-WebRequest -Uri "$alma/AlmaLinux-10.2-x86_64-dvd.iso" -OutFile "$images\AlmaLinux\AlmaLinux-10.2-x86_64-dvd.iso"
Invoke-WebRequest -Uri "$alma/CHECKSUM" -OutFile "$images\AlmaLinux\CHECKSUM"
[string] $github = 'https://github.com/PowerShell'
Invoke-WebRequest -Uri "$github/PowerShell/releases/download/v7.6.5/powershell-7.6.5-1.rh.x86_64.rpm" -OutFile 'D:\Installers\powershell-7.6.5-1.rh.x86_64.rpm'
Invoke-WebRequest -Uri "$github/DSC/releases/download/v3.2.3/dsc-3.2.3-1.x86_64.rpm" -OutFile 'D:\Installers\dsc-3.2.3-1.x86_64.rpm'
Get-FileHash -Algorithm SHA256 -Path "$images\Microsoft\*.iso", "$images\AlmaLinux\*.iso", 'D:\Installers\*.rpm', 'D:\Installers\*.msi'
```

Microsoft's links name no build; name each Windows ISO for the build it
holds if it is another. Compare each hash with its publisher's — the
AlmaLinux ISO with its line in `CHECKSUM`, the Windows ISOs with the SHA256
Microsoft's Evaluation Center lists beside each download where it lists one,
the RPMs with their GitHub release pages — and copy the example to where the
lab reads it, writing in the verified hashes:

```powershell
New-Item -ItemType Directory -Force -Path 'D:\Repos\Xmip\.local-work\hyperv-lab'
Copy-Item -LiteralPath 'D:\Repos\Xmip\deploy\dsc\hyperv-lab\lab.example.json' -Destination 'D:\Repos\Xmip\.local-work\hyperv-lab\lab.json'
```

Each Windows image's `Edition` is the `NAME` of the image in its ISO's
`sources\install.wim`, which Setup matches, not the longer display name. On
the Windows Server 2025 evaluation ISO they are `Windows Server 2025
SERVERDATACENTER` (Datacenter with the Desktop Experience, the example's),
`SERVERDATACENTERCORE`, `SERVERSTANDARD` and `SERVERSTANDARDCORE`; the Windows
11 evaluation ISO holds one, `Windows 11 Enterprise Evaluation`.

**The program.** Any server site whose roles cover receiving, processing and
sending builds it; `hospital-interface` declares `executing`, their sum.
Windows on the host, Linux in the AlmaLinux 10 WSL distribution:

```powershell
Import-Module -Name 'D:\Repos\Xmip\Xmip\Xmip.psd1' -Force
$env:CARGO_TARGET_DIR = 'D:\Repos\Xmip\.ai-interaction\target-windows'
Build-XmipService -Site hospital-interface
New-Item -ItemType Directory -Force -Path 'D:\Repos\Xmip\.local-work\hyperv-lab\windows', 'D:\Repos\Xmip\.local-work\hyperv-lab\linux'
Copy-Item -LiteralPath "$env:CARGO_TARGET_DIR\debug\xmip-service.exe" -Destination 'D:\Repos\Xmip\.local-work\hyperv-lab\windows'
[string] $cargo = (Build-XmipService -Site hospital-interface -WhatIf).Command
wsl.exe --distribution AlmaLinux-10 --exec sh -c ('cd /mnt/d/Repos/Xmip && CARGO_TARGET_DIR=$HOME/.xmip-target/lab $HOME/.cargo/bin/' + $cargo + ' -j 2 && cp $HOME/.xmip-target/lab/debug/xmip-service /mnt/d/Repos/Xmip/.local-work/hyperv-lab/linux/')
```

**Secrets and certificates**, as the Windows user that will run DSC. The
credential bundle is DPAPI-encrypted to that user on this host; the SSH key
is made beside it; nothing is written into the repository. Xmip obtains no
certificate ([decided, not built](../../../doc/architecture/estate-map.md#certificate-provisioning)),
so the lab makes its own authority and a certificate for each PostgreSQL
machine, and keeps the authority's key nowhere:

```powershell
$secret = @{
    Path = 'D:\Repos\Xmip\.local-work\hyperv-lab\credential.xml'
    SshKeyPath = 'D:\Repos\Xmip\.local-work\hyperv-lab\ssh\xmip-lab'
    LocalAdministrator = Get-Credential -UserName Administrator
    DsrmPassword = Read-Host -Prompt 'DSRM' -AsSecureString
    StoragePassword = Read-Host -Prompt 'xmip_storage' -AsSecureString
    ReplicationPassword = Read-Host -Prompt 'xmip_replication' -AsSecureString
}
& 'D:\Repos\Xmip\deploy\dsc\hyperv-lab\Initialize-LabCredential.ps1' @secret
& 'D:\Repos\Xmip\deploy\dsc\hyperv-lab\New-LabCertificate.ps1' -ConfigPath 'D:\Repos\Xmip\.local-work\hyperv-lab\lab.json'
```

## Running it

In an elevated Xmip PowerShell Console, as the same user. DSC finds the lab's
resources, `xmip-lab.dsc.manifests.json`, on `PATH`; the document reads
`D:/Repos/Xmip/.local-work/hyperv-lab/lab.json` unless its `labConfig`
parameter names another.

```powershell
$env:PATH = "D:\Repos\Xmip\deploy\dsc\hyperv-lab;$env:PATH"
dsc config test --file 'D:\Repos\Xmip\deploy\dsc\hyperv-lab\hyperv-lab.dsc.yaml'
dsc config set --file 'D:\Repos\Xmip\deploy\dsc\hyperv-lab\hyperv-lab.dsc.yaml'
```

Each resource answers with its `Findings`. `set` stops a machine where it
must wait — its installation from the ISO, which runs on its own once the VM
starts, or a reboot it starts, a domain join or the domain controller's
promotion — and the machines after it wait for it, so run `set` again until
`test` reports no finding. The three resources run in order:
`Xmip.Lab/HyperVHost` (the switch, NAT and the Windows VMs, each created and
started installing), `Xmip.Lab/WindowsGuests` (each guest's media ejected
once it answers, then its configuration), then `Xmip.Lab/LinuxGuests` (the
AlmaLinux VMs, created and started installing, then, once each answers over
SSH, its media ejected and DSC on the guest), since the AlmaLinux machines
resolve names through the domain controller.

A guest's own state, from the host:

```powershell
ssh -i 'D:\Repos\Xmip\.local-work\hyperv-lab\ssh\xmip-lab' xmiplab@10.77.0.42 'sudo PATH=/opt/xmip-lab:/usr/bin:/usr/sbin dsc config --parameters-file /opt/xmip-lab/machine.json test --file /opt/xmip-lab/linux.dsc.yaml'
```

## The files

| File | Is |
| --- | --- |
| `hyperv-lab.dsc.yaml` | the lab's DSC document: the three resources |
| `xmip-lab.dsc.manifests.json` | the three resources' manifests |
| `LabResource.ps1` | what DSC runs for each: Get, Test or Set, for a scope |
| `LabHost.ps1` | `lab.json` read and checked; the switch and NAT |
| `LabMachine.ps1` | a VM: created, installed from its ISO, its findings, its media ejected |
| `LabAnswer.ps1` | the install answers: `autounattend.xml` and the kickstart |
| `LabMedia.ps1` | the media checked before Set changes anything |
| `LabGuest.ps1` | a Windows guest, inside it, through PowerShell Direct |
| `LabDevelopment.ps1` | XMIP-DEV01's prerequisites, from `prerequisite.toml` |
| `LabLinux.ps1` | an AlmaLinux guest on the host: its account, key and parameters |
| `LabLinuxFleet.ps1` | the AlmaLinux guests over SSH: payload, DSC on the guest |
| `LabXmipNode.ps1` | an Xmip node inside its guest, Windows or Linux |
| `linux/` | the AlmaLinux guest's DSC document, resource and PostgreSQL setup |
| `xmip.toml` | the lab cluster's configuration: its nodes and their roles |
| `Initialize-LabCredential.ps1` | the credential bundle and the SSH key |
| `New-LabCertificate.ps1` | the PostgreSQL machines' TLS files |
| `lab.example.json` | the example the lab's `lab.json` is copied from |

`test/HyperVLab.Test.ps1` holds what can be held without Hyper-V: the
configuration and its refusals, the cluster file against the machines, the
install answers and the answer medium, the guests' parameters and payloads,
VM creation, findings and ejection with every Hyper-V command a stub, the
certificates, and the manifests against the scripts.
