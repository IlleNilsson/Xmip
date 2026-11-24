# Xmip, the portable archive

For people who want no installer (ADR-0015 clause 5). The archive holds one
folder, `xmip`, with three programs in `bin`:

| file | what it is |
| --- | --- |
| `bin/xmip-service` (`.exe` on Windows) | the Xmip Service: the one program that runs a node |
| `bin/xmip_core_operate.dll` (`libxmip_core_operate.so` or `.dylib` elsewhere) | the runtime library the operator tools load |
| `bin/xmip` (`.exe` on Windows) | the command line, `xmip`: operate the node from a terminal |

Nothing puts `bin` on `PATH`: add it yourself, or name the program, as
below.

Unpack it where the node should live. The folder becomes the installed
layout: `bin`, `config`, `modules`, `data` and `logs` (ADR-0015 clause 10).

Only the Windows archive is built today. Linux and macOS archives follow
the same layout and are not built yet: builds are Windows-only for now.

## Run it as a service

From an elevated prompt (an Administrator terminal on Windows, `sudo` on
Linux and macOS), in the unpacked `xmip` folder:

```powershell
bin/xmip-service --configuration config/cluster.xmip --node <node> --cluster <cluster> --install
```

This is what every Xmip package runs. It writes a starter cluster
configuration, `config/cluster.xmip`, if there is none — one node, declaring
the `storage` role so it keeps its own storage, offline,
operated from this machine on its local endpoint — slices the node's own
configuration, `config/node.xmip`, from it, writes `bin/cli.toml`, which
points the command line at the node's local endpoint, makes the `modules`,
`logs`, `data` and `data/audit` folders, and registers and starts the Xmip
Service, `xmip-<node>`, to start with the machine. A configuration already
there, `bin/cli.toml` included, is never written over.

To remove the service again:

```powershell
bin/xmip-service --configuration config/node.xmip --uninstall
```

It stops the service, waiting for the node to drain, and removes it.
Nothing else is deleted: configuration, `bin/cli.toml`, data, audit and
logs stay (ADR-0040).
Delete the folder yourself when you no longer want them.

## Run it in a terminal instead

Without elevation and without registering anything: write
`config/cluster.xmip` yourself, slice the node's configuration from it, and
run the node until Ctrl+C.

```toml
# config/cluster.xmip
[service]
name = "xmip-<node>"
cluster_name = "<cluster>"

[nodes.<node>]
roles = "storage"
```

Only a node with the `storage` role keeps its own storage; a node without
it, and without `[storage] nodes` naming the nodes that do, is refused as
it starts. The node is offline: it declares no Node capability, and
`capabilities = ["online"]` under `[nodes.<node>]` would give it the
internet (ADR-0056, amendment 2026-11-24).

The node's local operate endpoint always starts, named `xmip-<node>`: a
named pipe on Windows, `/run/xmip/xmip-<node>/xmip-<node>.sock` on Linux and
`/var/run/xmip/xmip-<node>/xmip-<node>.sock` on macOS, the node's folder made
for its account by the service's unit or daemon. Started in a terminal on
Linux or macOS, the node needs `XMIP_RUNTIME_DIRECTORY` to name a folder of
your own, such as `$XDG_RUNTIME_DIR/xmip`, and makes its folder there; name
the same in the terminal you reach it from (ADR-0014, amendment
2026-11-15).

```powershell
bin/xmip-service --configuration config/cluster.xmip --node <node> --slice > config/node.xmip
bin/xmip-service --configuration config/node.xmip --console
```

## Operate it

`bin/xmip` reaches the node at its local endpoint, as the account you run it
as; the node takes its calls from its operators, the account that ran
`--install` among them. In the unpacked `xmip` folder:

```powershell
bin/xmip --local xmip-<node> list
bin/xmip abi
bin/xmip help
```

After `--install`, `bin/cli.toml` names the endpoint, so `bin/xmip list`
reaches the same node; `--local` on the line wins over it.

## What to read next

- The node configuration document:
  `module/platform/configure/doc/node-configuration.md` in the Xmip
  repository, <https://github.com/IlleNilsson/Xmip>.
- The operator tools — the command line, the PowerShell module, the desktop
  and the web — reach the node on its local endpoint, `xmip-<node>`, which
  always starts (ADR-0014, amendments 2026-10-13).
