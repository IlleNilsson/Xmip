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

**The Windows machines** start from prepared Windows VHDX images, each a
differencing disk over its image, and are configured through PowerShell
Direct: name, static address, the domain (the Windows Server 2025 machines
and XMIP-DEV01 are domain members), then their role.

**The AlmaLinux machines** start from AlmaLinux's own Hyper-V image, the
VHDX inside its Vagrant box for Hyper-V, a differencing disk each, as the
Windows machines do. Each gets a cloud-init NoCloud seed disk, a small FAT32
VHDX labelled `CIDATA`, holding its host name, the lab's SSH key for the
account `xmiplab`, which has no password, and its static address with the
domain controller as its DNS server: a NetworkManager profile matched to the
static MAC the lab gives its adapter, since the image turns cloud-init's own
network step off. The image's `vagrant` account, whose key is public, is
removed at first boot. From then on the host reaches it
over SSH only: it copies the guest's payload to `/opt/xmip-lab`, installs
PowerShell and DSC v3 there from the RPMs you supply, and runs the guest's
own DSC document, `linux/linux.dsc.yaml`, whose resource
`Xmip.Lab/LinuxGuest` is `linux/LabLinuxGuest.ps1`.

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

**Media.** The prepared Windows VHDX images (the enabled built-in
Administrator in both; App Installer registered on Windows 11), the
PowerShell MSI for XMIP-DEV01, and for the AlmaLinux machines:

```powershell
[string] $images = 'D:\Downloads\OS\Images\AlmaLinux'
[string] $version = (Invoke-RestMethod -Uri 'https://vagrantcloud.com/api/v2/box/almalinux/10').current_version.version
[string] $box = "$images\AlmaLinux-$version-hyperv.box"
New-Item -ItemType Directory -Force -Path $images
Invoke-WebRequest -Uri "https://vagrantcloud.com/almalinux/boxes/10/versions/$version/providers/hyperv/amd64/vagrant.box" -OutFile $box
tar -xf $box -C $images 'Virtual Hard Disks/almalinux.vhdx'
Move-Item -LiteralPath "$images\Virtual Hard Disks\almalinux.vhdx" -Destination "$images\AlmaLinux-$version-hyperv.vhdx"
[string] $github = 'https://github.com/PowerShell'
Invoke-WebRequest -Uri "$github/PowerShell/releases/download/v7.6.5/powershell-7.6.5-1.rh.x86_64.rpm" -OutFile 'D:\Installers\powershell-7.6.5-1.rh.x86_64.rpm'
Invoke-WebRequest -Uri "$github/DSC/releases/download/v3.2.3/dsc-3.2.3-1.x86_64.rpm" -OutFile 'D:\Installers\dsc-3.2.3-1.x86_64.rpm'
Get-FileHash -Algorithm SHA256 -Path $box, "$images\*.vhdx", 'D:\Installers\*.rpm', 'D:\Installers\*.msi'
```

Compare each hash with its publisher's — the box with the `checksum` the
same `vagrantcloud.com` API gives its `hyperv` provider, the RPMs with their
GitHub release pages — and copy the example to where the lab reads it,
writing in the verified hashes, the VHDX's as the image's:

```powershell
New-Item -ItemType Directory -Force -Path 'D:\Repos\Xmip\.local-work\hyperv-lab'
Copy-Item -LiteralPath 'D:\Repos\Xmip\deploy\dsc\hyperv-lab\lab.example.json' -Destination 'D:\Repos\Xmip\.local-work\hyperv-lab\lab.json'
```

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

Each resource answers with its `Findings`. `set` stops a machine at a reboot
it starts — a rename, a domain join, the domain controller's promotion — and
the machines after it wait for it, so run `set` again until `test` reports no
finding. The three resources run in order: `Xmip.Lab/HyperVHost` (the switch,
NAT and the Windows VMs), `Xmip.Lab/WindowsGuests`, then
`Xmip.Lab/LinuxGuests` (the base image, the seed, the VMs, then DSC on each
guest), since the AlmaLinux machines resolve names through the domain
controller.

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
| `LabHost.ps1` | `lab.json` read and checked; the switch, NAT and VMs |
| `LabMedia.ps1` | the media checked before Set changes anything |
| `LabGuest.ps1` | a Windows guest, inside it, through PowerShell Direct |
| `LabDevelopment.ps1` | XMIP-DEV01's prerequisites, from `prerequisite.toml` |
| `LabLinux.ps1` | an AlmaLinux guest on the host: base image, seed, VM, its parameters |
| `LabLinuxFleet.ps1` | the AlmaLinux guests over SSH: payload, DSC on the guest |
| `LabXmipNode.ps1` | an Xmip node inside its guest, Windows or Linux |
| `linux/` | the AlmaLinux guest's DSC document, resource and PostgreSQL setup |
| `xmip.toml` | the lab cluster's configuration: its nodes and their roles |
| `Initialize-LabCredential.ps1` | the credential bundle and the SSH key |
| `New-LabCertificate.ps1` | the PostgreSQL machines' TLS files |
| `lab.example.json` | the example the lab's `lab.json` is copied from |

`test/HyperVLab.Test.ps1` holds what can be held without Hyper-V: the
configuration and its refusals, the cluster file against the machines, the
seed, the guests' parameters and payloads, VM creation with every Hyper-V
command a stub, the certificates, and the manifests against the scripts.
