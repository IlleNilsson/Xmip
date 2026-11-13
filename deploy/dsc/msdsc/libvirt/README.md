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

`deploy/dsc/libvirt.example.toml`, which `Deploy-XmipEnvironment` reads
(`deploy/dsc/README.md`), describes two machines on 10.77.0.0/24, AlmaLinux
10 both: XMIP-APP03, the Essentials' DS1, and XMIP-IN01, its RX1. The
network's DNS answers `DS1`, `RX1` and the cluster, `CL1`, at the addresses of
the machines that run them, so the environment needs no DNS server of its
own.

## What each machine is given

The installation image, a new qcow2 disk and an answer medium, each a volume
of the pool, so the hypervisor reads them wherever they came from; the image
is named by its SHA-256 and shared by every machine that installs from it,
checked against it and uploaded only where the pool does not hold it yet, so
a DVD's gigabytes are read once, not once per machine. A
domain with UEFI and Secure Boot, the enrolled keys, its memory and CPUs, its
adapter on the network with a static MAC made from its address (52-54-00 and
the address's last three octets), and two DVD drives; a TPM where the host
has `swtpm`, never required. It boots its disk first, then the DVD: the empty
disk does not boot, so the firmware moves on to the ISO, which installs onto
the disk.

What each definition is — the network, the pool, the domain, its volumes
and drives — and the answers are `deploy/dsc/machine`'s, which Ansible's
template asks too: an AlmaLinux machine's kickstart on a volume labeled
`OEMDRV`, with `qemu-guest-agent` for the guest services and the SSH host
key made for it where the environment is deployed from; a Windows machine's
`autounattend.xml`, its disk on SATA and its adapter an e1000e, which the
installer has drivers for. A Windows ISO boots only after *Press any key*,
so for its first twenty seconds Space is sent.

The installation is done when the guest answers at its address, SSH for
AlmaLinux and WinRM for Windows. Until then `set` leaves it, and its state
says so, `installation` `Installing`: a resource writes nothing but its
answer, which DSC reads from its standard output (ADR-0015, amendment
2026-11-11). The next `set` empties both drives, deletes the answer medium
and records the machine installed in its domain's metadata, so it is never
installed again.

## Before the first run

Once, with sudo, on an AlmaLinux 10 host — the WSL AlmaLinux guest included:

```text
sudo dnf install --assumeyes libicu qemu-kvm libvirt virt-install
echo kvm_intel | sudo tee /etc/modules-load.d/kvm.conf
sudo usermod --append --groups libvirt,kvm <account>
sudo systemctl enable --now virtqemud.socket virtnetworkd.socket virtstoraged.socket
```

then sign in again. The rest, none of it with sudo, is
`deploy/dsc/README.md`'s *Before the first run*.

## Running it

As the account in the `libvirt` group, never root;
`Deploy-XmipEnvironment` with `technology = "msdsc"` (`deploy/dsc/README.md`).
It applies `network.dsc.yaml`, then `machine.dsc.yaml` once per machine, one
installation at a time, with this folder on `PATH` so DSC finds the
resources, waiting until each machine is installed before it makes the
next; then the nodes (`deploy/dsc/msdsc/environment`).

## The files

| File | Is |
| --- | --- |
| `network.dsc.yaml` | the network and the pool |
| `machine.dsc.yaml` | one machine |
| `libvirt.resource.ps1` | the resources' entry, run by DSC with the kind and the operation |
| `LibvirtNetwork.ps1` | the network and the pool |
| `LibvirtMachine.ps1` | where the machine's installation is, and moving it on |
| `xmip-libvirt-*.dsc.resource.yaml` | the resource manifests |

`virsh` on the system connection, every definition and each step of an
installation are `deploy/dsc/machine`'s (`LibvirtInstallation.ps1`), which
Ansible's role asks too: the media put in the pool whole, the answer medium
written in a folder of its own, `0700` and named at random, the domain
started, and its installation completed, refused where a drive still holds
a medium or the answer medium is still in the pool, and its record naming
the technology that made it, so the other technology is refused there.

`test/MsdscLibvirt.Test.ps1` holds what can be held without libvirt: the
network's and the domain's definitions, the example as
`Deploy-XmipEnvironment` reads it, the machine's `set` while it installs,
with `virsh` a stub: it leaves the machine to install and writes nothing,
and an ISO hashed only where its volume is not in the pool whole.
