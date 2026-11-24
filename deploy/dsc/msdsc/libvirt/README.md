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
| `Xmip.Libvirt/Network` | a network with NAT, the host its gateway, where `nat` says, isolated where a gateway machine is the way out or none is; its DHCP gives each machine its address by its static MAC, its DNS answers each machine's name and the names the environment adds |
| `Xmip.Libvirt/Pool` | a directory pool for the machines' disks, images and answer media |
| `Xmip.Libvirt/Machine` | one machine, a domain installed unattended from its ISO |

## The example environment

`deploy/dsc/libvirt.example.toml`, which `Deploy-XmipEnvironment` reads
(`deploy/dsc/README.md`), is the owner's node plan of 2026-11-22 under KVM:
the Hyper-V example's 21 machines on 10.77.0.0/24, machine for machine, with
the same names, addresses, systems, nodes and far ends
(`deploy/dsc/msdsc/environment/README.md`). XMIP-DC01, the domain
controller, is the network's DNS server and its way out, its
`gateway_machine`, with a second adapter on the bridge your copy's `uplink`
names (`deploy/dsc/README.md`, *The way out*), and the network is isolated;
XMIP-RX01 alone reaches past the network, through it; XMIP-DEV02 is
AlmaLinux with a desktop. An AlmaLinux machine starts
with 2 GiB and is given up to the plan's figure; a Windows machine has the
plan's floor, static: 2 GiB for Windows Server, 4 GiB for Windows 11
(ADR-0015, amendment 2026-11-22).

From a Linux host the Windows machines wait on two things the owner
decides: their Administrator secret, which only Windows reads
(`deploy/dsc/machine/MachineSecret.ps1`), and how msdsc reaches them, since
PowerShell on Linux has no WinRM client. Until they are made, XMIP-DC01 is
not either: name no `gateway_machine` and set `nat = true`, and the host is
the network's way out, through libvirt's NAT.

## What each machine is given

The installation image, a new qcow2 disk and an answer medium, each a volume
of the pool, so the hypervisor reads them wherever they came from; the image
is named by its SHA-256 and shared by every machine that installs from it,
checked against it and uploaded only where the pool does not hold it yet, so
a DVD's gigabytes are read once, not once per machine. A
domain with UEFI and Secure Boot, the enrolled keys, its memory and CPUs, its
adapter on the network with a static MAC made from its address (52-54-00 and
the address's last three octets), the gateway machine a second on the
uplink, a bridge of the host's, its MAC the same with its first octet 02,
and two DVD drives; a TPM 2.0 from
`swtpm` where its image says `tpm = true`, as Windows 11's does, refused
where the host has no `swtpm`. It boots its disk first, then the DVD: the
empty disk does not boot, so the firmware moves on to the ISO, which
installs onto the disk.

Its memory is `memory_gb`, static, or, where its `dynamic_memory` names
its most, that most, of which a virtio balloon starts with `memory_gb`:
the balloon gives the guest back up to its most once it runs short
(`autodeflate`), and the host is given back every page the guest frees
(`freePageReporting`). libvirt has no least, so `minimum_gb` is Hyper-V's
alone. Windows has no balloon driver of its own (virtio-win's is a third
party's), so a Windows machine gets no balloon, and its
`dynamic_memory` is refused before anything is made. A Windows machine
gets instead what KVM gives of Hyper-V's own interface, which Windows uses
as it does on Hyper-V, and Hyper-V's clock, as `virt-install`'s osinfo gives
Windows Server 2025 and Windows 11: no driver of anyone's.

An AlmaLinux machine's chrony keeps KVM's clock, `refclock PHC
/dev/ptp_kvm`, the module `ptp_kvm` loaded at every start, which AlmaLinux
10's kernel builds as a module, and the device systemd's own udev rules
link: a machine with no way out reaches no pool, and nodes and far ends on
different machines time what they carry on one clock.

What each definition is — the network, the pool, the domain, its volumes
and drives — and the answers are `deploy/dsc/machine`'s, which Ansible's
template asks too: an AlmaLinux machine's kickstart on a volume labeled
`OEMDRV`, with `qemu-guest-agent` for the guest services and the SSH host
key made for it where the environment is deployed from; a Windows machine's
`autounattend.xml`, its disk on SATA and its adapter an e1000e, which the
installer has drivers for. A Windows ISO boots only after *Press any key*,
so for its first twenty seconds Enter is sent: a later press stops the
Windows Boot Manager's countdown, and only Enter then chooses Windows Setup.

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
sudo dnf install --assumeyes libicu qemu-kvm libvirt virt-install swtpm swtpm-tools
echo kvm_intel | sudo tee /etc/modules-load.d/kvm.conf
sudo usermod --append --groups libvirt,kvm <account>
sudo systemctl enable --now virtqemud.socket virtnetworkd.socket virtstoraged.socket
```

then sign in again. The rest, none of it with sudo, is
`deploy/dsc/README.md`'s *Before the first run*. Where the file names a
`gateway_machine`, its `uplink` is a bridge of the host's holding its
adapter on your network, made once with the system's own network tools, as
your network wants it; the templates name it and never make it, and
libvirt refuses to start a domain whose bridge is not there.

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
network's and the domain's definitions, the network isolated without
`nat`, the gateway machine's second adapter on the uplink's bridge, their
memory, balloon, TPM and Windows' interface and clock; an AlmaLinux
machine's answer given KVM's
clock; the example as `Deploy-XmipEnvironment` reads it, the Hyper-V
example's plan machine for machine, every machine's domain defined, and a
Windows machine's dynamic memory refused; the machine's `set` while it
installs, with `virsh` a stub: it leaves the machine to install and writes
nothing, and an ISO hashed only where its volume is not in the pool whole.
