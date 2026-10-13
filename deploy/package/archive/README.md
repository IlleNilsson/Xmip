# Xmip, the portable archive

For people who want no installer (ADR-0015 clause 5). The archive holds one
folder, `xmip`, with two programs in `bin`:

| file | what it is |
| --- | --- |
| `bin/xmip-service` (`.exe` on Windows) | the Xmip Service: the one program that runs a node |
| `bin/xmip_core_runtime.dll` (`libxmip_core_runtime.so` or `.dylib` elsewhere) | the runtime library the operator tools load |

Unpack it where the node should live. The folder becomes the installed
layout: `bin`, `config`, `modules`, `data` and `logs` (ADR-0015 clause 10).

Only the Windows archive is built today. Linux and macOS archives follow
the same layout and are not built yet: builds are Windows-only for now.

## Run it as a service

From an elevated prompt (an Administrator terminal on Windows, `sudo` on
Linux and macOS), in the unpacked `xmip` folder:

```powershell
bin/xmip-service --configuration config/xmip.toml --node <node> --cluster <cluster> --install
```

This is what every Xmip package runs. It writes a starter cluster
configuration, `config/xmip.toml`, if there is none — one node, offline,
operated from this machine on its local endpoint — slices the node's own
configuration, `config/xmip-node.toml`, from it, makes the `modules`,
`logs`, `data` and `data/audit` folders, and registers and starts the Xmip
Service, `xmip-<node>`, to start with the machine. A configuration already
there is never written over.

To remove the service again:

```powershell
bin/xmip-service --configuration config/xmip-node.toml --uninstall
```

It stops the service, waiting for the node to drain, and removes it.
Nothing else is deleted: configuration, data, audit and logs stay (ADR-0040).
Delete the folder yourself when you no longer want them.

## Run it in a terminal instead

Without elevation and without registering anything: write
`config/xmip.toml` yourself, slice the node's configuration from it, and
run the node until Ctrl+C.

```toml
# config/xmip.toml
[service]
name = "xmip-<node>"
cluster_name = "<cluster>"

[nodes.<node>.service]
online = false
```

The node's local operate endpoint always starts, named `xmip-<node>`: a
named pipe on Windows, `/run/xmip/xmip-<node>.sock` on Linux and
`/var/run/xmip/xmip-<node>.sock` on macOS. In a terminal on Linux or macOS
that folder must exist and be yours; the service's unit or daemon makes it.

```powershell
bin/xmip-service --configuration config/xmip.toml --node <node> --slice > config/xmip-node.toml
bin/xmip-service --configuration config/xmip-node.toml --console
```

## What to read next

- The node configuration document:
  `module/platform/configure/doc/node-configuration.md` in the Xmip
  repository, <https://github.com/IlleNilsson/Xmip>.
- The operator tools — the command line, the PowerShell module, the desktop
  and the web — reach the node on its local endpoint, `xmip-<node>`, which
  always starts (ADR-0014, amendments 2026-10-13).
