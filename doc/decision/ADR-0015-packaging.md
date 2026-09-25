# ADR-0015: Packaging and distribution

## Status

Accepted. Implementation follows in separate reviewed changes.

## In brief

- Theme: Operating Xmip
- Subject: Packaging and distribution
- Name: Packaging and distribution
- Order: 2
- Concepts: arm64, embedded, IoT; MSI, winget, deb, rpm, OCI

Packaging covers the node; Modules are out of scope. MSI via WiX, published
through winget, on Windows. `.deb` and `.rpm` on Linux. An OCI image every
release. A portable archive for people who want no installer at all. x86-64 and
arm64 on both — **arm64 is not optional**, because the IoT and embedded profiles
require it.

## Context

install/install-local.ps1 and install-local.sh create a directory layout and write a node configuration. They install no binary, and they say so: the message they print is that a layout was initialized. deploy/ carries an Ansible role and a DSC configuration, which are the fleet layer and call something underneath them.

Nothing yet puts Xmip on a machine.

Two different things need distributing and they do not behave alike. The node is the runtime and the xmip command: installed rarely, upgraded deliberately, restarted when it changes. A sub-module is the unit of loading and runtime upgrade under ADR-0012: loaded on demand, replaced without a restart, published by whoever wrote it under whatever license they chose.

## Decision

1. Packaging covers the node. Modules are out of scope, for the reason in Consequences.
2. Windows is packaged as an MSI, built with WiX, and published through winget. winget is the channel; the MSI is the artifact behind it.
3. Linux is packaged as .deb and .rpm.
4. An OCI container image is published for every release.
5. A portable archive is published for every platform, for people who want no installer at all.
6. Architectures are x86-64 and arm64 on both Windows and Linux. The iot and embedded profiles mean arm64 is not optional.
7. macOS is a development target: portable archive only, no service registration.
8. MSIX is rejected. Its sandbox conflicts with a service that loads native modules out of a directory, which is what Xmip does.
9. Every artifact for a release is built by CI from one commit.
10. The installed layout is normative and is the one install-local already establishes: bin, config, modules, data, logs. ProgramData\Xmip on Windows, /opt/xmip on Linux.

## Why not one format

An MSI registers a Windows service and can be deployed by Group Policy, which is what a change board expects to see. A .deb or .rpm owns a systemd unit and participates in the distribution upgrade path. A container image is the only sensible answer for cloud and for edge fleets. A portable archive is what someone reaches for when they want to try Xmip without asking anyone for permission, and that matters more than it sounds for a platform that has to displace an incumbent.

winget covers the case Xmip most needs to win: a Windows administrator who already runs BizTalk and wants Xmip on a box this afternoon.

## Consequences

**Modules cannot ship this way.** ADR-0012 makes the sub-module the unit of runtime upgrade. Delivering one through an OS package manager would mean an administrative install and a service restart for something designed to hot-load, and it would put third-party code with third-party licenses into a feed Xmip publishes. Module distribution needs versioning and integrity rather than an installer, which is closer to NuGet or crates.io than to winget. It is a separate decision and is not made here.

**The storage engine decides how hard all of this is.** doc/architecture/database-selection.md selects a RocksDB-style embedded key/value store for runtime persistence and a SQLite-style embedded relational store for management. The word is style, so what is settled is the shape: an embedded store optimized for write volume and replay from known state, separate from the management store.

Which engine fills that shape is a packaging decision as much as a runtime one. RocksDB is a C++ library. Taking it means a C++ toolchain and libclang in every build, cross-compilation to arm64 that is materially harder than changing a target triple, and larger artifacts everywhere including the container image. A pure Rust store keeps cross-compilation to naming a target, which is what clauses 3, 4 and 6 depend on.

The workspace today has neither. Its only store feature is sqlite-store over rusqlite, so runtime persistence is unimplemented rather than implemented differently. The generated node configuration naming rocksdb is a statement of intent, not a defect, and was deliberately left alone.

## Open

**The persistence engine.** Whether the RocksDB-style shape is filled by RocksDB or by a pure Rust store. The tradeoff is write performance and maturity against build and cross-compilation cost, and it should be decided before packaging is built rather than after, because clauses 3, 4 and 6 inherit the answer.

**Module distribution and signing.** If the runtime loads native code out of module/, something must decide whether an unsigned module may load, and where a signed one comes from.

**There is no binary to package yet.** The only binary in the workspace is xmip-tiny-device. ADR-0014 clause 8 says the command is xmip, produced by xmip-core-cli, which does not exist. This ADR records the shape so that the first binary lands into a decided one, not to suggest packaging can be built before there is something to put in it.

## Amendment, 2026-09-21: install/ is deleted

`install/install-local.ps1` and `install-local.sh`, which the Context above
describes, are gone. The owner: *We are designing from scratch, nothing is
released or published. There is no point holding on to old repos or code.*
They created a directory layout and installed no binary, and the estate's
own style gate had called them superseded and awaiting deletion while the
README still offered them.

Clause 10 stands: the installed layout — bin, config, modules and the rest
it names — is normative. What is gone is the one thing that created it by
hand, so until packaging lands nothing lays a node out, which is what the
Context already said of installing one.

## Amendment, 2026-09-25: the persistence engine is RocksDB

The open question above — *whether the RocksDB-style shape is filled by
RocksDB or by a pure Rust store* — is answered by the owner, 2026-09-25:
**RocksDB**, for the runtime store (Messages, Journeys, checkpoints), and an
embedded SQLite for the management store, the two shapes
`database-selection.md` chose before it was folded away on 2026-08-25.

He asked for it believing it was already there. It had been: a RocksDB
runtime store was written on 2026-06-14, its dependency dropped from the
build as unused on 2026-06-26, and the store deleted on 2026-08-20; the
SQLite store did not move when the monolith was distributed on 2026-08-26.
`xmip-core-persist` has held the types and no engine since.

What it costs, as the Open section said and the owner took knowingly: a C++
toolchain and libclang in every build that includes the runtime store,
harder cross-compilation to arm64, larger artifacts. `prerequisite.toml`
declares the toolchain; the AlmaLinux guest verifies the Linux build. Each
engine is a technology under `persist`, so a device build can leave RocksDB
out.

Encryption of what is stored is not the engine's (ADR-0063).

Built 2026-09-25: `xmip-core-persist-rocksdb` and `xmip-core-persist-sqlite`,
each a `persist::Engine` under persist's `EncryptedStore`, tested on Windows
and on the AlmaLinux guest. `prerequisite.toml` declares libclang (and, on
Linux, the C++ compiler); the first Windows build of RocksDB took some twenty
minutes. RocksDB is built without compression, since what it stores is
ciphertext.
