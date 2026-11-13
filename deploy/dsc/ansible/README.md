# An Xmip environment, with Ansible

The same set of templates as `deploy/dsc/msdsc`, in Ansible: an Xmip
environment's machines, made on the host their hypervisor runs on, the
names of the cluster and its nodes on the DNS server, and on each node
machine, Windows and AlmaLinux alike, its node. Both technologies cover both
systems; Ansible is kept for the people who know it and for the project's
support, and an environment uses one of the two, never a mix (ADR-0015,
amendments 2026-10-09 and 2026-10-21; the owner, 2026-10-21: *dotnet is
cross platform, so is Blazor, MAUI and DSC. We keep Ansible and other tech
for familiarity and support for the project.*). It is a template for
creating Xmip environments, never a lab.

`cluster.xmip` is the Essentials' own,
`test/core/essentials/configuration/cluster.xmip`, the one file a test runs
whether its nodes are simulated or on machines of their own (ADR-0028,
amendment 2026-10-21). Which node runs on which machine is the environment
file's, `deploy/dsc/README.md`, never that file's: `Deploy-XmipEnvironment`
with `technology = "ansible"` writes the inventory from it, `inventory.yml`
in the run folder, generated and never configuration, and runs the
playbook.

| File | Is |
| --- | --- |
| `environment.yml` | the playbook: the machines, the names on the DNS server, every node, one machine at a time, then every node started together |
| `roles/xmip_machine` | the machines on their hypervisor, one installation at a time: `tasks/libvirt.yml` on a Linux host, `tasks/hyperv.yml` on a Windows one |
| `roles/xmip_name` | on the DNS server, a Windows DNS server: the zone, and an A record for the cluster and for each node |
| `roles/xmip_node` | one node on its machine: `tasks/windows.yml` and `tasks/linux.yml`, the same steps on each system |

The role `xmip_machine` makes on libvirt, through `community.libvirt`
(`virt_net`, `virt_pool`, `virt`), the network with NAT whose DHCP and DNS
give each machine its address and name and the pool, each started and, in
a task of its own, started with the host — the two modules answer a task
naming a state before they look at `autostart`; each machine's
installation is `deploy/dsc/machine/LibvirtInstallation.ps1`'s, the code
Microsoft DSC's machine resource runs, asked through `machine.ps1`: its ISO
checked against its SHA-256, a new disk and its answer medium put in the
pool whole, its domain defined and started, then, once it answers from its
disk, its media taken out, its answer medium deleted and its domain's
metadata recording it installed and by which technology, refused where a
drive still holds a medium or the answer medium is still in the pool, and a
machine the other technology made refused. On Hyper-V
it uses Microsoft's `microsoft.hyperv` (`hv_vswitch`, `hv_vhd`, `hv_vm`,
`hv_memory`, `hv_processor`, `hv_hard_disk`, `hv_network_adapter`,
`hv_vm_boot`, `hv_dvd_drive`, `hv_vm_state`) and
`ansible.windows.win_powershell` for the host's address and NAT, which no
module covers. What a network, a pool, a domain, a kickstart or an answer
medium is, is never written here: it is asked of `deploy/dsc/machine`,
the code Microsoft DSC's machine resources use, through `machine.ps1` on the
controller. Each AlmaLinux machine's kickstart gives it the host key made
for it on the controller, which the inventory's `known_hosts` holds, so
every login is checked strictly.

The role `xmip_node` gives each node machine, in order: its account (the
system account `xmip` on AlmaLinux; on Windows the virtual account
`NT SERVICE\xmip-<node>`, which exists with its service); its slice,
`node.xmip`, as the controller's `xmip-service --slice --cluster --bind
--nodes --authority` prints it (`tasks/slice.yml`, `xmip_slicer`), signed by
the environment's authority kept on the controller in `xmip_authority`, with
that authority's certificate in `config/authority/authority.pem`, replaced
only where the text it signs differs and restarting the node when it
changed, or where the node does not run the slice it holds — the node
never slices and never holds the authority's key, so a `node.xmip` edited
on it is refused there, and the first slice it admits pins that authority,
its name and the highest serial it has seen in its data folder, apart from
its active configuration, the last slice that ran, so a swapped
certificate, an older slice or another node's is refused too, and a
correctly signed slice the node cannot start is refused as it starts while
the active configuration runs, and is tried again at the next start
(ADR-0031, amendments 2026-11-06, 2026-11-07 and 2026-11-12) —
every Receive Location and
Send Port the cluster's file designs placed over the inventory's
`xmip_nodes`, round robin by their roles, and bound over SFTP on the
Parties' far end the Essentials serves at `xmip_far_end`, port 7422, each a
user of its own there (ADR-0028, amendment 2026-10-22); a firewall opening
for exactly the ports `xmip-service --listening` says, and none it no
longer does — none for the far end, which a node reaches and never serves —
kept by firewalld and reloaded, and reloaded too where the running firewall
lacks it, as a run that stopped before its handlers leaves it; its
certificate, key and anchors from the cluster's own authority into
`config/tls`, the key private; the estate's package, told `XMIP_NODE`,
`XMIP_CLUSTER` and `XMIP_ACCOUNT`, whose `xmip-service --install` lays the
node out by its slice and registers and starts the service as that account,
installed over another build of the same version where the installed
`.rpm`'s header differs from the shipped one's; and its service started
with the machine. The playbook's last play starts every node together
(`tasks/started.yml`), again every five seconds until each runs or
`xmip_started_window`, 180 seconds, is spent: a node refuses to accept work
until its cluster's Xmip Storage answers, and a Storage node until every
Storage node the cluster lists does (ADR-0056, amendment 2026-11-08), so
none of them starts alone, one machine after another. Then each node is
asked `xmip-service --activation`, and fails the run, in the node's words,
until it runs the slice it was shipped: a service that started does not
say its slice took (ADR-0031, amendment 2026-11-12). The role writes no
starter of its own: a node given no cluster file gets the package's,
written once in `xmip-service --install`.

The node's `node.xmip` is its alone to write (ADR-0031, amendment
2026-11-06, point 4), the package's starter included: on AlmaLinux owned by
the node's account, group root, mode 0640; on Windows inheriting nothing,
SYSTEM and the administrators in full control and the node's account with
Modify, set once the package has registered the service its virtual account
exists with.

ansible-core (checked 2026-11-11: 2.22.0 of 2026-11-02, which needs Python
3.13) runs the Windows modules in PowerShell 7 where
`ansible_pwsh_interpreter` says, and the AlmaLinux ones in the machine's own
`/usr/bin/python3`, named by `ansible_python_interpreter` rather than
discovered, as the inventory does. The tasks read a machine's facts through
`ansible_facts` alone, as ansible-core 2.24 requires once it no longer
injects them as variables, and the inventory writes every group, an empty
one too, so a play to one plays to none without a warning. The collections are
`ansible.windows`, `ansible.posix`, `community.libvirt` (2.4.0, with
libvirt's Python binding and lxml from the distribution on the libvirt
host) and `microsoft.hyperv` (1.1.0). Its secret masking redacts every
registered secret as `$REDACTED$` in whatever Ansible shows: the
Administrator password `--ask-pass` reads is registered by Ansible itself,
and the one secret the role ships, the node's `node.key`, is read on the
controller through the `register_secret` filter and copied by a task of its
own with `no_log` and `diff: false`, so even `--check --diff` never prints
it. No task handles a Location's secret: a Location names its secret, whose
value is kept in the Xmip Administration Database, set with
`Set-XmipSecret`, never in a file the role ships.

## The controller

Ansible's control node does not run on Windows
(<https://docs.ansible.com/ansible/latest/os_guide/intro_windows.html>), so
the controller is a Linux machine: the WSL AlmaLinux guest, which reads
this clone at `/mnt/d/Repos/Xmip`. WSL is not what Ansible supports for
production; here it is a test level 2 controller. `Deploy-XmipEnvironment`
on Windows refuses `technology = "ansible"` and names the command to run in
the guest. Once, there, `prerequisite.toml`'s `[prerequisite.ansible]`, its
bin on `PATH`, and `deploy/dsc/README.md`'s *Before the first run*.

## Running it

```text
pwsh -Command "Import-Module /mnt/d/Repos/Xmip/Xmip/Xmip.psd1; Deploy-XmipEnvironment -Path /mnt/d/Repos/Xmip/.local-work/deploy/libvirt.toml"
```

with `technology = "ansible"` in the file. `-WhatIf` runs the playbook with
`--check --diff`, which says what differs: every task that only reads runs
(`check_mode: false`), and every command that changes names in `removes`
the file it needs, which is how the command module says under `--check`
that it would run; a host is then in its desired state only where nothing
would change, and a machine not made yet is answered unreached, never
refused. Where a Windows host or machine is in the environment, the
Administrator's password is asked. Neither asks for elevation on the
controller; the playbook becomes the Administrator or root on each machine
itself. A run is in its desired state when every host's recap says
`failed=0` and `unreachable=0`, and a second run changes nothing.

A Windows machine's answer is written on the controller, and the
Administrator secret file it reads is `Export-Clixml`'s, encrypted for a
Windows account, which a Linux controller cannot read; one written off
Windows keeps the password as plain text and is refused
(`deploy/dsc/machine/MachineSecret.ps1`). How a Linux controller is given
that password — asked at each run, Ansible Vault, or Xmip's own secret
store — waits on the owner, so Windows machines are made with msdsc on a
Windows host until he chooses.

The package is staged on a node machine in Ansible's own folder,
`/var/tmp/xmip-ansible` or `C:\ProgramData\Xmip\ansible`, never the one
Microsoft DSC's template stages in.

On Hyper-V the controller reaches the Windows host at the file's `host`,
over WinRM, as `ANSIBLE_REMOTE_USER`; that host's address, the account and
its rights wait on the owner's Hyper-V run.

Then the Essentials runs against the machines as
`deploy/dsc/msdsc/environment/README.md` says under *Running it*, typing
exactly the environment's nodes, and what runs is the same: the real nodes
reach DS1 for Xmip Storage, and the Essentials drives them through the
Parties' far end it serves on the host, counting at `xmip:///CL1/carried`
what they carried.

## How it is held

`test/MsdscEnvironment.Test.ps1` runs `ansible-playbook --syntax-check` and
`--list-tasks` over the inventory each example environment file writes,
where Ansible is on `PATH`, SKIPPED where it is not;
`test/DeployEnvironment.Test.ps1` holds that the inventory maps the nodes
as the msdsc steps do, reaches each AlmaLinux machine strictly, that no
task writes a network, pool, domain or kickstart of its own, that every
read runs under `--check` and every command that changes says it would,
that firewalld's service is made permanent alone and the running firewall
asked and reloaded after it, that the package's headers are compared
before it is upgraded, and that a recap that would change or was not
reached answers not in its desired state; `test/DeployMachine.Test.ps1`
holds the installation's steps both technologies share; the root
crate's `cargo test --test deploy` holds that the role asks `xmip-service`
for the slice, the cluster and the ports, binds the Locations and keeps no
starter, that every node an example maps is declared by the cluster's file,
and that each mapped node's slice with its Locations bound on the far end
reads as `xmip-service` reads it. The machines themselves are proved by
running `Deploy-XmipEnvironment` (`deploy/dsc/README.md`).
