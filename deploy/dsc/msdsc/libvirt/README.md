# Xmip machines on libvirt, with Microsoft DSC v3

A template for the virtual machines an Xmip environment runs on, for a Linux
host: KVM through libvirt, as `deploy/dsc/msdsc/hyperv` is for a Windows host.
It makes the network, the pool and, for each machine, a domain that installs
its operating system unattended from the publisher's ISO. What runs inside a
machine once it is installed is the environment templates'
(`deploy/dsc/msdsc/environment`).

DSC v3 has no resource for libvirt, and none is published by anyone else
(checked 2026-11-03), so the template's resources are Xmip's own: PowerShell 7
behind resource manifests, as `Xmip.Node` is, asking libvirt's own client,
`virsh`, on the system connection, `qemu:///system`. Every rule about a
network, a pool or a domain is libvirt's.

| Resource | Is |
| --- | --- |
| `Xmip.Libvirt/Network` | a network with NAT, the host its gateway; its DHCP gives each machine its address by its static MAC, its DNS answers each machine's name and the names the environment adds |
| `Xmip.Libvirt/Pool` | a directory pool for the machines' disks, images and answer media |
| `Xmip.Libvirt/Machine` | one machine, a domain installed unattended from its ISO |

## The example environment

`environment.example.xmip`, which `Deploy-XmipEnvironment` reads, describes
one machine, XMIP-IN01, AlmaLinux 10, the Essentials' R1, on 10.77.0.0/24.
The network's DNS answers `R1` and the cluster, `C1`, at the addresses of the
machines that run them, so the environment needs no DNS server of its own.

## What each machine is given

The installation image, a new qcow2 disk and an answer medium, each a volume
of the pool, so the hypervisor reads them wherever they came from; the image
is named by its SHA-256 and shared by every machine that installs from it. A
domain with UEFI and Secure Boot, the enrolled keys, its memory and CPUs, its
adapter on the network with a static MAC made from its address (52-54-00 and
the address's last three octets), and two DVD drives; a TPM where the host
has `swtpm`, never required. It boots its disk first, then the DVD: the empty
disk does not boot, so the firmware moves on to the ISO, which installs onto
the disk.

The answers are the Hyper-V template's, `deploy/dsc/msdsc/answer`: an
AlmaLinux machine's kickstart on a volume labeled `OEMDRV`, with
`qemu-guest-agent` for the guest services; a Windows machine's
`autounattend.xml`, its disk on SATA and its adapter an e1000e, which the
installer has drivers for. A Windows ISO boots only after *Press any key*,
so for its first twenty seconds Space is sent.

The installation is done when the guest answers at its address, SSH for
AlmaLinux and WinRM for Windows. The next `set` empties both drives, deletes
the answer medium and records the machine installed in its domain's
metadata, so it is never installed again.

## Before the first run

Once, with sudo, on an AlmaLinux 10 host — the WSL AlmaLinux guest included:

```text
sudo dnf install --assumeyes libicu qemu-kvm libvirt virt-install
echo kvm_intel | sudo tee /etc/modules-load.d/kvm.conf
sudo usermod --append --groups libvirt,kvm <account>
sudo systemctl enable --now virtqemud.socket virtnetworkd.socket virtstoraged.socket
```

then sign in again. PowerShell 7.7 and Microsoft DSC 3.3 on `PATH`, and the
Xmip module's prerequisites, `Install-XmipPrerequisite -Role operator
-Install`. Copy the example to `.local-work/deploy/libvirt.xmip` and write
in `linux_account` and `ssh_public_key`.

## Running it

As the account in the `libvirt` group, never root; `-WhatIf` says what
differs and changes nothing:

```text
pwsh -Command "Import-Module /mnt/d/Repos/Xmip/Xmip/Xmip.psd1; Deploy-XmipEnvironment -Path /mnt/d/Repos/Xmip/.local-work/deploy/libvirt.xmip"
```

It applies `network.dsc.yaml`, then `machine.dsc.yaml` once per machine,
with this folder on `PATH` so DSC finds the resources, and waits until each
machine is installed. On 2026-11-03 XMIP-IN01 installed in seven minutes in
the WSL guest.

## The files

| File | Is |
| --- | --- |
| `network.dsc.yaml` | the network and the pool |
| `machine.dsc.yaml` | one machine |
| `environment.example.xmip` | the example environment |
| `libvirt.resource.ps1` | the resources' entry, run by DSC with the kind and the operation |
| `LibvirtCommon.ps1` | `virsh` and the static MAC |
| `LibvirtNetwork.ps1` | the network and the pool |
| `LibvirtMachine.ps1` | the machine and its installation |
| `xmip-libvirt-*.dsc.resource.yaml` | the resource manifests |

`test/MsdscLibvirt.Test.ps1` holds what can be held without libvirt: the
network's and the domain's definitions, and the example as
`Deploy-XmipEnvironment` reads it.
