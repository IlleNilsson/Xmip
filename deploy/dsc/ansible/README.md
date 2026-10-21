# An Xmip environment's machines, with Ansible

The same set of templates as `deploy/dsc/msdsc/environment`, in Ansible:
what runs inside an Xmip environment's machines once they are installed —
the names of the cluster and its nodes on the DNS server, and on each node
machine, Windows and AlmaLinux alike, its node. Both technologies cover
both systems; Ansible is kept for the people who know it and for the
project's support, and an environment uses one of the two, never a mix
(ADR-0015, amendments 2026-10-09 and 2026-10-21; the owner, 2026-10-21:
*dotnet is cross platform, so is Blazor, MAUI and DSC. We keep Ansible and
other tech for familiarity and support for the project.*). It is a template
for creating Xmip environments, never a lab.

The cluster's `xmip.toml` is the Playground's own,
`test/core/playground/configuration/xmip.toml`, the one file a test runs
whether its nodes are simulated or on machines of their own (ADR-0028,
amendment 2026-10-21). Which node runs on which machine is the inventory's,
`inventory.example.yml`, never that file's; the example is the same mapping
as `deploy/dsc/msdsc/environment/README.md`'s table, R1 on XMIP-IN01, S1 on
XMIP-OUT01, P1 on XMIP-APP01, L1 on XMIP-APP02 and D1 on XMIP-APP03, and
`test/MsdscEnvironment.Test.ps1` holds the two equal.

| File | Is |
| --- | --- |
| `environment.yml` | the playbook: the names on the DNS server, then every node |
| `inventory.example.yml` | the example environment: the machines, how each is reached, and the node each runs |
| `roles/xmip_name` | on the DNS server, a Windows DNS server: the zone, and an A record for the cluster and for each node |
| `roles/xmip_node` | one node on its machine: `tasks/windows.yml` and `tasks/linux.yml`, the same steps on each system |

The role `xmip_node` gives each node machine, in order: its account (the
system account `xmip` on AlmaLinux; on Windows the virtual account
`NT SERVICE\xmip-<node>`, which exists with its service); the cluster's
`xmip.toml`; its certificate, key and anchors from the cluster's own
authority into `config/tls`, the key private; the estate's package, told
`XMIP_NODE`, `XMIP_CLUSTER` and `XMIP_ACCOUNT`, whose `xmip-service
--install` slices the file there and registers and starts the service as
that account; its slice as `xmip-service --slice --cluster` prints it,
restarting the node when it changed; a firewall opening for exactly the
ports `xmip-service --listening` says, and none it no longer does; and its
service running and started with the machine. The role writes no starter of
its own: a node given no cluster file gets the package's, written once in
`xmip-service --install`.

ansible-core 2.21 (checked 2026-10-21: 2.21.5 of 2026-10-05) runs the
Windows modules in PowerShell 7 where `ansible_pwsh_interpreter` says, as
the inventory does. The collections are `ansible.windows` and
`ansible.posix`.

## Before the first run

The machines are installed (`deploy/dsc/msdsc/hyperv`), XMIP-DC01 runs the
DNS Server role, PowerShell 7.6 is on every Windows machine, and the
packages and each node's certificate are made on the host, as
`deploy/dsc/msdsc/environment/README.md` says under *Before the first run*
(the certificates under `.local-work/environment/identity/<node>`). The
host's own names and WinRM's trusted hosts are set the same way.

The controller is the WSL AlmaLinux guest, which reads this clone at
`/mnt/d/Repos/Xmip`. Once, there:

```text
python3 -m venv ~/.local/share/xmip-ansible
~/.local/share/xmip-ansible/bin/pip install ansible-core pywinrm
~/.local/share/xmip-ansible/bin/ansible-galaxy collection install ansible.windows ansible.posix
cp /mnt/d/Repos/Xmip/deploy/dsc/ansible/inventory.example.yml /mnt/d/Repos/Xmip/.local-work/environment/inventory.yml
```

In the copy, write in `linux_account` under `all.vars` — the account the
AlmaLinux machines were installed with — and the packages' version.

## Running it

From the guest, in `/mnt/d/Repos/Xmip/deploy/dsc/ansible`; `--check --diff`
says what differs, without it the playbook makes it so. `--ask-pass` asks
the Windows machines' Administrator password:

```text
~/.local/share/xmip-ansible/bin/ansible-playbook -i /mnt/d/Repos/Xmip/.local-work/environment/inventory.yml --ask-pass --check --diff environment.yml
~/.local/share/xmip-ansible/bin/ansible-playbook -i /mnt/d/Repos/Xmip/.local-work/environment/inventory.yml --ask-pass environment.yml
```

Then the Playground runs against the machines as
`deploy/dsc/msdsc/environment/README.md` says under *Running it*, and what
runs today is the same: D1 starts and answers, and a node declaring no
Storage role is refused as it starts until Xmip Storage is reached over the
wire in the assembled service.

## How it is held

`ansible-playbook --syntax-check` and `--list-tasks` over the example
inventory, in the WSL guest; the root crate's `cargo test --test deploy`,
that the role asks `xmip-service` for the slice, the cluster and the ports
and keeps no starter, and that every node the inventory maps is declared by
the cluster's file, which slices for every node and reads as `xmip-service`
reads it; and `test/MsdscEnvironment.Test.ps1`, that the mapping is the DSC
example's. Nothing here has been applied to a machine.
