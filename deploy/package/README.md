# Packages: what puts a node on a machine

What an end user installs to get Xmip started (ADR-0015, amendment
2026-10-13). Each package carries two files, `xmip-service` and the runtime
library, both built from a site by `Build-XmipService -Site <name>`
(`deploy/site`), and runs one command once they are on disk:

```text
xmip-service --configuration <layout>/config/xmip.toml \
  --node <node> --cluster <cluster> --install
```

That command — written once, in `xmip-service` (`.src/service/install.rs`)
— lays the node out (`bin`, `config`, `modules`, `data`, `logs`; clause 10),
writes a starter cluster `xmip.toml` where there is none (one node,
offline; its local operate endpoint, `xmip-<node>`, always starts and needs
no line), slices the
node's `xmip-node.toml` from it, makes `data/audit`, and registers the Xmip
Service `xmip-<node>` the way `registration.rs` defines it, to start with
the machine, and starts it. Removal runs
`xmip-service --configuration <layout>/config/xmip-node.toml --uninstall`,
which stops the service, waits for the drain and removes it; configuration,
data, audit and logs stay (ADR-0040). No package keeps its own copy of the
layout, the starter or the registration.

| folder | package | status |
| --- | --- | --- |
| `windows/` | MSI per architecture (x64, arm64), WiX Toolset 7, and its winget manifest | **written, not built**: WiX 7 refuses to build until its EULA is accepted (below) |
| `linux/` | `.deb` and `.rpm` from one nfpm definition, systemd | **written, not built** |
| `macos/` | `.pkg` (pkgbuild and productbuild), launchd | **written, not built** |
| `archive/` | the portable archive, zip | built and run on Windows x64; tar.gz for Linux and macOS not built |

Builds are Windows-only for now, the owner's choice of the moment. The
Linux and macOS definitions are complete as written and have never been
built or installed; nothing here claims they work.

**Build from a site whose node starts on its own.** A one-machine node is
its own embedded Storage node and needs SQLite, which only the `storage`
role brings. No example site has it yet, so a node built from
`personal-computer` is refused as it starts; the owner decides which site
an end user's package is built from (ADR-0015, amendment 2026-10-13).

## Windows

```powershell
Build-XmipService -Site personal-computer -CargoArgument '--release' -Package msi, archive
```

Makes, under `.local-work/package/<version>/`:
`xmip-<version>-<site>-x64.msi`, `winget/<version>/` (the manifest, three
files, schema 1.28.0, generated from the MSI) and
`xmip-<version>-<site>-windows-x64.zip`. `--target aarch64-pc-windows-msvc`
in `-CargoArgument` makes the arm64 MSI.

- **WiX 7 needs its EULA accepted.** WiX Toolset 7 (NuGet
  `WixToolset.Sdk` 7.0.0) is under the Open Source Maintenance Fee, and it
  builds nothing until its EULA is accepted once per user and machine.
  That is the owner's decision; until it is made, `-Package msi` is
  REFUSED, naming the command that accepts it.
- **Install**: `msiexec /i <msi>` from an elevated prompt, optionally with
  `XMIP_NODE=<node> XMIP_CLUSTER=<cluster>`; each is the computer's name
  otherwise. Binaries go to `Program Files\Xmip\bin`, the rest of the layout
  to `ProgramData\Xmip`. The service runs as LocalSystem, the platform
  default: which account it should run as is open (ADR-0015, amendment
  2026-10-13).
- **Remove**: Apps in Settings, or `msiexec /x <msi>`.

## Linux (written, not built)

```text
XMIP_BINARY_DIRECTORY=<built> XMIP_VERSION=<version> XMIP_ARCH=amd64 \
  nfpm package --config deploy/package/linux/nfpm.yaml --packager deb
```

and `--packager rpm` for the `.rpm`; `XMIP_ARCH=arm64` for arm64. The layout
is `/opt/xmip`; the unit is `/etc/systemd/system/xmip-<node>.service`, and
its `RuntimeDirectory=xmip` makes `/run/xmip` for the node's account, where
the node's local endpoint is, `/run/xmip/xmip-<node>.sock`.
`postinstall.sh` runs `--install`, `preremove.sh` runs `--uninstall` on
removal only, never on an upgrade.

## macOS (written, not built)

Stage the two binaries under `<staging>/opt/xmip/bin`, then:

```text
pkgbuild --root <staging> --identifier io.github.illenilsson.xmip \
  --version <version> --scripts deploy/package/macos/scripts \
  --install-location / xmip-node.pkg
productbuild --distribution deploy/package/macos/distribution.xml \
  --package-path <folder of xmip-node.pkg> xmip-<version>.pkg
```

The layout is `/opt/xmip`; the daemon is
`/Library/LaunchDaemons/xmip-<node>.plist`, and beside it
`xmip-<node>.run.plist` makes `/var/run/xmip` for the node's account at
every boot, since macOS empties `/var/run` as it starts; the node's local
endpoint is `/var/run/xmip/xmip-<node>.sock`. macOS has no removal for a
package: `sudo /opt/xmip/bin/xmip-service --configuration
/opt/xmip/config/xmip-node.toml --uninstall` removes the daemon and keeps
everything else. A `.pkg` people can open is signed with a Developer ID
Installer certificate and notarized, which needs the owner's Apple
Developer Program membership.

## The archive

`archive/README.md` is the archive's own README, for a person who wants no
installer: the same `--install` and `--uninstall`, or a node in a terminal
without registering anything.
