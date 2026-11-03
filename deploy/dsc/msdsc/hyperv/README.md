# Xmip machines on Hyper-V, with Microsoft DSC v3

A template for the virtual machines an Xmip environment runs on, for one
virtualization technology: Hyper-V on a Windows host. It makes the network
and, for each machine, a VM that installs its operating system unattended
from the publisher's ISO. Another technology gets a folder of its own beside
this one, `deploy/dsc/msdsc/<technology>`; Ansible's desired state is
`deploy/dsc/ansible`, and an environment uses one of the two, never a mix
(ADR-0015, amendment 2026-10-09).

What runs inside a machine once it is installed is not this template's. The
Xmip nodes and the names of the cluster and its nodes are the environment
templates', `deploy/dsc/msdsc/environment` and, the same set in Ansible,
`deploy/dsc/ansible`, each for Windows and AlmaLinux alike (ADR-0015,
amendment 2026-10-21); the domain and PostgreSQL are not written yet.

## The example environment

`environment.example.toml`, which `Deploy-XmipEnvironment` reads,
describes ten machines:

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
| XMIP-IN01 | AlmaLinux 10 | Xmip node | 4 GiB | 2 | 32 GiB | 10.77.0.61 |
| XMIP-OUT01 | AlmaLinux 10 | Xmip node | 4 GiB | 2 | 32 GiB | 10.77.0.71 |

They share an internal switch, `Xmip`, on 10.77.0.0/24. The host is
10.77.0.1 on it, the machines' gateway, with outbound NAT; the domain is
`xmip.test`, and XMIP-DC01's address is the DNS server the AlmaLinux
machines are given. The roles are the environment templates' business; here
they are a comment above each machine.

## What each machine is given

A folder, `<root>\<machine>`, and in it a new dynamic disk, `os.vhdx`. A
generation 2 VM with static memory, its CPUs, the disk, its adapter on the
switch with a static MAC made from its address (00-15-5D and the address's
last three octets), Secure Boot on with the template its image names —
`MicrosoftWindows` for Windows, `MicrosoftUEFICertificateAuthority` for
AlmaLinux — and a virtual TPM where its image asks for one (Windows 11). Two
DVD drives, and the boot order disk first, then the two drives.

On its first start the VM holds its ISO, checked against the SHA-256 the
parameters give, and an answer medium this template writes for it, an ISO
image made with the image mastering API every Windows host has. The empty
disk does not boot, so the firmware moves on to the ISO, which installs onto
the disk; every later boot starts from the disk.

- **Windows**: the answer medium holds `autounattend.xml`, which Windows
  Setup reads from the root of a removable medium. It partitions the disk for
  UEFI, installs the image the parameters name as `edition` (the image's
  `NAME` in the ISO's `sources\install.wim`), sets the computer name, enables
  the built-in Administrator with the password in the credential file, and
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
answers SSH at its address. The next `set` then empties both DVD drives,
deletes the answer medium and writes `installed` in the machine's folder, so a
VM found off later is started from its disk and never installed again.
Delete that file and the disk to install a machine anew.

## Before the first run

Once, in an elevated Xmip PowerShell Console, then restart the host. Hyper-V,
Microsoft DSC v3, and the two Windows PowerShell DSC modules the documents use
(HyperVDsc has only prerelease versions on the PowerShell Gallery):

```powershell
Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All
winget install --id Microsoft.DSC --exact
[string] $modules = 'C:\Program Files\WindowsPowerShell\Modules'
Save-PSResource -Name HyperVDsc -Prerelease -Repository PSGallery -Path $modules -TrustRepository
Save-PSResource -Name NetworkingDsc -Repository PSGallery -Path $modules -TrustRepository
```

The two Windows PowerShell DSC modules run in Windows PowerShell 5.1 through
DSC's adapter, whose default execution policy refuses every script; the
policy for the user alone was not enough (2026-11-03), so it is set for the
machine, once, in the same console:

```powershell
powershell.exe -NoProfile -Command 'Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force'
```

The ISOs go where the environment file names them, under
`D:\Downloads\OS\Images`. Then, as the Windows user that will run DSC, not
elevated: the Administrator credential of the Windows machines, encrypted to
that user on this host, the SSH key of the AlmaLinux machines, and the
environment file copied to where it is yours:

```powershell
[string] $local = 'D:\Repos\Xmip\.local-work\hyperv'
New-Item -ItemType Directory -Force -Path "$local\ssh"
Get-Credential -UserName 'Administrator' -Message 'The Windows machines' |
    Export-Clixml -LiteralPath "$local\credential.xml"
ssh-keygen -t ed25519 -N '' -f "$local\ssh\xmip"
[string] $example = 'D:\Repos\Xmip\deploy\dsc\msdsc\hyperv\environment.example.toml'
Copy-Item -LiteralPath $example -Destination 'D:\Repos\Xmip\.local-work\deploy\hyperv.toml'
```

In the copy, write in `linux_account`, the account the kickstart creates on
the AlmaLinux machines, `ssh_public_key` and `credential`, and strike the
machines you do not want.

## Running it

In an elevated Xmip PowerShell Console, as the same user; the documents
refuse to run unelevated. One command makes the network and every machine,
and waits until each is installed; `-WhatIf` says what differs and changes
nothing:

```powershell
Deploy-XmipEnvironment -Path 'D:\Repos\Xmip\.local-work\deploy\hyperv.toml' -WhatIf
Deploy-XmipEnvironment -Path 'D:\Repos\Xmip\.local-work\deploy\hyperv.toml'
```

It applies `network.dsc.yaml`, then `machine.dsc.yaml` once per machine,
each on its own with the parameters it declares, and writes one line per
step with the time left. It does not use `Microsoft.DSC/Include`: DSC reads
an included document's state before it sets anything, and NetworkingDsc's
address and HyperVDsc's DVD drives throw where the switch or the VM is not
there yet. An installation runs on its own; while a machine installs, its
document is applied again every thirty seconds until it is installed, its
media gone, and running. Everything DSC says goes to
`.local-work\deploy\<environment>\run.log`.

## The files

| File | Is |
| --- | --- |
| `network.dsc.yaml` | the switch, the host's address on it, NAT |
| `machine.dsc.yaml` | one machine: folder, disk, VM, DVD drives, hardware, installation |
| `environment.example.toml` | the example environment: the network and its ten machines, as `Deploy-XmipEnvironment` reads it |
| `HyperVMachine.ps1` | the hardware and the installation, run by `machine.dsc.yaml` |
| `../answer/MachineAnswer.ps1` | the install answers and the answer medium, shared with the libvirt template |
| `../answer/autounattend.template.xml` | the Windows answer `MachineAnswer.ps1` fills in |

The resources, and where a script stands in for one:

| Instance | Resource |
| --- | --- |
| switch | `HyperVDsc/VMSwitch` |
| host address | `NetworkingDsc/IPAddress` |
| NAT | a script: no DSC resource manages a NetNat |
| machine folder | `PSDesiredStateConfiguration/File` |
| disk | `HyperVDsc/Vhd` |
| VM | `HyperVDsc/VMHyperV` |
| DVD drives | `HyperVDsc/VMDvdDrive` |
| static MAC, Secure Boot template, TPM, boot order | a script: HyperVDsc sets none of them |
| answer medium, media in and out, start | a script: no resource writes or removes them |

The Windows PowerShell DSC modules run through the
[`Microsoft.Adapter/WindowsPowerShell`][adapter]
adapter, the scripts through `Microsoft.DSC.Transitional/PowerShellScript` in
PowerShell 7. The documents ask for elevation with the `securityContext`
directive, the form DSC 3.3 reads.
HyperVDsc is [dsccommunity/HyperVDsc](https://github.com/dsccommunity/HyperVDsc),
NetworkingDsc [dsccommunity/NetworkingDsc](https://github.com/dsccommunity/NetworkingDsc).

`test/MsdscHyperV.Test.ps1` holds what can be held without Hyper-V: the
documents read as YAML by DSC, their parameters, the example environment as
`Deploy-XmipEnvironment` applies it, each step evaluated by DSC with every
resource replaced by an echo, this table of
machines against it, the install answers and the answer medium.

[adapter]: https://learn.microsoft.com/powershell/dsc/reference/resources/microsoft/windows/windowspowershell
