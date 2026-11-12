# ADR-0015: Packaging and distribution

## Status

Accepted. Implementation follows in separate reviewed changes.

## In brief

- Theme: Operating Xmip
- Subject: Packaging and distribution
- Name: Packaging and distribution
- Order: 2
- Concepts: arm64, embedded, IoT; MSI, winget, deb, rpm, OCI, pkg, launchd; target, site; archive target; schema version, upgrade; environment template, environment file

Packaging covers the node; Modules are out of scope. MSI via WiX, published
through winget, on Windows. `.deb` and `.rpm` on Linux. An OCI image every
release. A portable archive for people who want no installer at all. x86-64 and
arm64 on both — **arm64 is not optional**, because the edge target, an IoT
gateway or a Raspberry Pi, requires it. What a package is built with is its
site's: a target, node roles and the technologies its end user chose,
turned into a build by `Build-XmipService` (amendments 2026-10-01 and
2026-10-19), every built technology built and tested, archive targets
among them: the site chooses them (amendment 2026-10-20). macOS gets a `.pkg` with a
launchd daemon, and every package installs by running
`xmip-service --install`; the Windows packages are built on Windows and the
`.rpm` on Linux, the macOS `.pkg` not yet (amendments 2026-10-13 and
2026-11-11). Every database records its schema version, and a
release's upgrade scripts only add (amendment 2026-10-20). One environment
file names the technology, Microsoft DSC v3 or Ansible, that makes an
environment's machines and its nodes, in one command, and the environment
keeps it: the other one is refused there (amendment 2026-11-11).

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
6. Architectures are x86-64 and arm64 on both Windows and Linux. The edge target (amendment 2026-10-01) means arm64 is not optional.
7. macOS is a development target: portable archive only, no service registration.
8. MSIX is rejected. Its sandbox conflicts with a service that loads native modules out of a directory, which is what Xmip does.
9. Every artifact for a release is built by CI from one commit.
10. The installed layout is normative and is the one install-local already establishes: bin, config, modules, data, logs. ProgramData\Xmip on Windows, /opt/xmip on Linux.

## Why not one format

An MSI registers a Windows service and can be deployed by Group Policy, which is what a change board expects to see. A .deb or .rpm owns a systemd unit and participates in the distribution upgrade path. A container image is the only sensible answer for hosted nodes and for edge fleets. A portable archive is what someone reaches for when they want to try Xmip without asking anyone for permission, and that matters more than it sounds for a platform that has to displace an incumbent.

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
embedded SQLite for the management store, which holds history and records, never configuration (ADR-0031, amendment 2026-09-26), the two shapes
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

## Amendment, 2026-10-01: a site decides what a package is built with

**Provenance.** The owner, 2026-10-01, on the proposal to replace the
deploy files' two flat module lists with grouped profiles that decide what a
deployment's program is built with: *We can try that and add runtime role
perspective and target node type.* The five targets were proposed and not
objected to. The name `hosted`, the role compositions and the vetoes are
the drafting's, and the owner's to strike.

**What a package is built with is a site's.** A site,
`deploy/site/<name>.xmip`, picks a target and node roles, each a profile
under `deploy/profile`, a TOML file named by its word (ADR-0031), and its
technologies:

- **One target**, what the program runs on (`deploy/profile/target`):
  `device`, a Meadow-class microcontroller, no_std, no store, no TLS
  server; `edge`, a Raspberry Pi, industrial PC or gateway under systemd,
  SQLite and the file key store; `computer`, a person's Windows or Mac
  machine, SQLite and DPAPI or the keychain; `server`, an on-premises
  Windows or Linux service, RocksDB and DPAPI or the file key store; and
  `hosted`, a virtual machine or container at a hosting provider, RocksDB
  and the file key store, headless. A target names the root crate features
  it always brings (its store's engine, which brings the key store), the
  features it refuses, each with a reason sentence, the Rust triples it is
  built for, and the technologies it claims: the store engines and key
  stores. A cluster and a hybrid
  are arrangements of nodes, each on a target, and not targets
  (deployment-model.md section 1).
- **Node roles**, what the node is for (`deploy/profile/role`), one file
  per `NodeRole` word (ADR-0056): `receiving`, `processing` and `sending`
  each pull the capability features their stage needs; `executing` is their
  sum and adds nothing (`roles = ["receiving", "processing", "sending"]`);
  `operational` brings cluster, event, persist, retain, archive and
  resilience; `monitoring` brings event and report; `development`, the
  Essentials', composes executing, operational and monitoring.
  `xmip-service`'s own features — node, audit, observe — are always on, and
  say so in one place: its `[[bin]] required-features` in `Cargo.toml`.
- **Technologies**, what it integrates with (`technologies`): the
  repository names of the built technologies its end user chose, across
  capabilities (amendment 2026-10-19).

**One place turns a site into a build: `Build-XmipService -Site`.** The
features are the target's, every role's (executing expanded), each chosen
technology the root crate links through a feature (a feature listing
`dep:<alias>` whose dependency's `package` is the technology), and
xmip-service's required ones; the command is `cargo build --bin
xmip-service --no-default-features --features <them>`, run at the estate
root. A chosen technology xmip-service has no feature for yet is said under
`Unlinked`, in words, and not refused: the build links what exists. `-WhatIf` returns the plan and the
command and builds nothing. The rule that says which technologies are built
moved from `Update-XmipDeployList.ps1` to `Get-XmipBuiltTechnology`, once.

**The target vetoes.** A role or a technology needing a feature the target
refuses is REFUSED in words naming what needs it, the feature and the
target's reason (ADR-0055): an operational node on a person's computer
needs `cluster`, which the computer target refuses because a computer
sleeps, roams and is shut down by its user. **A device site is refused, not
redirected.** `xmip-service` needs the standard library and a device has
none, so `Build-XmipService` refuses a device site, saying so and giving the
command that does build for a device: `xmip-core` alone, no_std,
`--target thumbv7em-none-eabihf`. A cmdlet named for xmip-service that
quietly built something else would say one thing and do another.

**The Cargo profiles are deleted.** `server-profile`, `desktop-profile`
and `tiny-profile` were a second home for what the profiles now say, and
`desktop-profile` was `server-profile` under another name. **`default` is
empty**: a plain `cargo build` is the assembly library with the modules
every node has, and a default that named the bin's features plus a store
would have been a profile under another name. The root's own tests take
`--all-features`, which is what the workflow runs; its site job builds each
example site through `Build-XmipService`, and xmip-core for the device.

**How it fits "module selection is configuration".** Two steps. The build
sets what is possible: the site's profiles decide which features the
program carries. The node's TOML picks from that at run time: which
Locations, transports and store it starts, and a name the build left out is
refused as the node starts (ADR-0025, amendment 2026-09-28; ADR-0018,
amendment 2026-09-30).

**The deploy lists are gone** (ADR-0060, amendment 2026-10-01): the DSC
document and the Ansible role each name the site their node is built from,
`metadata.xmip.site` and `xmip_site`.

Five example sites, one per target: `hospital-interface` (server),
`factory-gateway` (edge), `personal-computer` (computer), `b2b-exchange`
(hosted) and `field-sensor` (device, refused as above).

## Amendment, 2026-10-01: Xmip Storage, and RocksDB always the embedded runtime engine

**Provenance.** The owner, 2026-10-01, validated part by part with the
assistant, and re-decided later the same day: *to have one or more Xmip Nodes
with role Storage would be a safety… Xmip could just do a round robin over
Xmip Nodes roled Storage*; *The storage node may or may not carry the SQL
storage, it is an IT-infrastructure question… How IT-infrastructure designs
their Database servers is their concern*; and, on a shared database server
IT runs, option A, *Go ahead*. The split of the
embedded store is his too: *RocksDB is the first storage for audit records,
then transferred to SQLite, RocksDB for speed, SQLite for persistence over
time*.

**No node opens a database of its own.** Every node calls Xmip Storage, the
nodes declaring the Storage role (ADR-0056, amendment of this date), round
robin. Xmip Storage always keeps two databases, the runtime database (the
Ledger) and the administration database (the owner: *We still need the
distinction between runtime and administration databases, regardless of
backend database technology*). Behind the Storage nodes is one of two forms
(`deployment-model.md` section 7):

- **a shared database server IT runs** on the internal network —
  PostgreSQL first, SQL Server later — chosen as option A; the two databases are
  separate databases there, which IT may place on different servers, and
  their clustering, failover and backup are IT's;
- **one embedded Storage node**, for a single machine and an edge site:
  RocksDB for the runtime database and SQLite for the administration
  database, both through `xmip-core-persist`, with no failover.

**On the embedded Storage node the runtime engine is always RocksDB.** SQLite
is never the runtime engine there; it is the administration database. On
every backend the audit keeper moves audit records from the runtime database
to the administration database. So the earlier amendment of this
date is superseded where it paired `edge` and `computer` with SQLite as
their store, and the `[store] engine` choice of ADR-0018's amendment of
2026-09-30 is removed (ADR-0018, amendment of this date). The device target
keeps no store and carries neither engine. What the 2026-09-25 amendment
priced — a C++ toolchain and libclang in every build with the runtime store,
harder cross-compilation to arm64 — is priced wherever an embedded Storage
node is built.

**A Storage node under test** (the owner, 2026-10-01: *for testing purposes
the Xmip Nodes of Storage type can use SQLite in memory for administration
and RocksDB for runtime*) keeps its administration database in SQLite in
memory and its runtime database in RocksDB, on disk in the test's directory,
so a kill test still proves the runtime database durable.

**Configuration is TOML, read as a Host Service starts; the Subscriptions
are shared through Xmip Storage** (the owner, 2026-10-02: *Routes are
defined in TOML, read into Storage at Xmip Host Service startup, read from
Storage when needed and kept in memory until "not used for a while"*, and
*They are shared*). Each node reads its TOML configuration as it starts and
holds its Locations, Xmip Processes and Send Ports as its **execution
tree**, which `build_execution_tree` in `xmip-core-runtime` builds. Its
Subscriptions it writes into Xmip Storage's administration database, so any
node with a routing role routes a Message another node received; routing
reads them from Xmip Storage when it needs them, compiles their filters and
keeps them in memory until they have not been used for a while. The
operation tools and editors change the TOML file, never a database, and a
changed TOML file takes effect when the Host Service that reads it is
started again, never mid-flight (ADR-0031, amendments 2026-10-01 and
2026-10-02).

**Later, only if option A's latency is too slow:** option C, an embedded
engine per Storage node with Xmip copying from a claimed primary to standbys
and a witness holding the claim, and option D, C for the hot Ledger and A
for history. **Rejected:** option B, an embedded engine on a shared disk —
RocksDB is not supported on network file systems.

**PostgreSQL is the first database server Xmip Storage supports** (the
owner, 2026-10-01: *Don't leave out the elephant, Postgres*), as a persist
technology, `xmip-core-persist-postgresql`, reusing the PostgreSQL wire
protocol the estate already speaks in its PostgreSQL transport — one
implementation, no async runtime. SQL Server follows later. A Storage node
in front of a database server is built with it. This closes the question
this amendment had left open.

Audit is written through Xmip Storage (ADR-0062, amendment of this date),
and Xmip Storage is reached over Xmip's TLS (ADR-0063, amendment of this
date). The target profiles follow this record since the build of the same
day: every target that keeps a store carries RocksDB and claims both
engines, none refuses either, and the storage role,
`deploy/profile/role/storage.toml`, brings SQLite for the administration
database.

**An operator guide per database server** (the owner, 2026-10-01: *We have
to give PostgreSQL and MSSQL IT-operators help in regards to settings and
database schemas. A new readme & scripts perhaps*; and later the same day:
*I can set us up with both PostgreSQL and MS SQL later for tests, you just
need to prepare what I, future IT-operators have to do. A connection string,
software to install or whatever*). Each server Xmip Storage is in front of
has `deploy/database/<server>/`: a README for its IT operators — the
software and the versions, the steps in order, the scripts, the settings
Xmip depends on and why, TLS on the database connection, the connection
string and where it goes, and pointers to what stays theirs (encryption at
rest, backup, replication and failover) — and the scripts that make both
databases, their schema and their least-privilege roles. The scripts are
generated from the one schema definition the backend reads and writes by
(`xmip-core-persist`, `storage::schema`), and `cargo test --test database`
at the estate root fails when they differ, so the two cannot drift.
PostgreSQL's and SQL Server's are both written now, ahead of SQL Server's
backend; the same test runs Xmip Storage against a real server named by
`XMIP_TEST_POSTGRESQL` or `XMIP_TEST_MSSQL`, and says it skipped where
none is. A Storage node names its server in its configuration as
`[storage.database]` — two connections,
`<server>://<login>@<host>[:<port>]/<database>`, and the name of the secret
the password is kept under, never the password — which is the assistant's
drafting of the owner's *a connection string*, and his to strike.

## Amendment, 2026-10-08: a device node runs the whole message path

The owner, 2026-10-08: *An MCU node does Receive (validate), Prepare,
Transform, Process & Send (validate) like any other node type. It does not
have Operation.*

- **A device is a node, not an endpoint client.** A `device` site's node
  receives and validates against the Contract, prepares, transforms,
  processes and sends, validating what it sends, as a node of any other
  target does. The message path's semantics are the same on every target
  (`deployment-model.md` section 1).
- **No Operation on a device.** The device target refuses the operational
  role (amendment 2026-10-01, *the target vetoes*); a device is observed and
  configured through another node.
- **What follows, not yet decided or built:** the message path, Contract
  validation, Transform and the Work Process are to build `no_std`, beside
  `xmip-core`; until they do, `Build-XmipService` keeps refusing a device
  site as above. Where a device keeps its Ledger and what a device transport
  is stay open.

Provenance: the stages and *no Operation* are the owner's, 2026-10-08,
quoted above; reading *Operation* as the operational role, and the refusal
staying until the path builds `no_std`, are the assistant's drafting, his to
strike.

## Amendment, 2026-10-09: desired state, one folder per technology

The owner, 2026-10-09: *deploy/dsc should contain ansible and msdsc*, and of
the DSC v3 document, `xmip-node.dsc.yaml`: *you can delete it*. Desired state
lives under `deploy/dsc`, one folder per technology: `deploy/dsc/ansible`
holds the role `xmip_node`, and `deploy/dsc/msdsc` is Microsoft DSC v3's: a
template per virtualization technology for an environment's machines,
`hyperv` the first (the owner, 2026-10-09: *template for virtual nodes via
selected tech*), and no node document yet. A deployment uses one of them, never a mix
(the owner, 2026-10-08: *it is either DSC V3 or Ansible, not a mix*).
Microsoft DSC v3 stays one of the two technologies (`deployment-model.md`
section 8).

## Amendment, 2026-10-13: packages an end user installs, macOS among them

**Provenance.** The owner, 2026-10-13: *In the deploy folder we need some
kind of setup binaries to get things started for End Users* — and:
*We'll do the Windows, Linux and hopefully the OS X setup.* Builds are
Windows-only by his choice of the moment, so the Windows packages are built
and tested, and the Linux and macOS ones are written complete and not built.

**`deploy/package`, one folder per form:**

- `windows/` — clause 2's MSI, one per architecture (x64, arm64), from
  `Xmip.wixproj`, an SDK-style project on WiX Toolset 7 (NuGet
  `WixToolset.Sdk` 7.0.0, released 2026-04-06, current on 2026-10-13), built
  by `dotnet build`; and its winget manifest, three files on manifest schema
  1.28.0 (the newest in `microsoft/winget-cli` on 2026-10-13), generated from
  the MSI — its SHA-256 and ProductCode — and never kept by hand. Binaries go
  to `Program Files\Xmip\bin`, the rest of clause 10's layout to
  `ProgramData\Xmip`: a service's programs in a folder only administrators
  write, which refines clause 10's `ProgramData\Xmip` and is the drafting's,
  the owner's to strike.
- `linux/` — clause 3's `.deb` and `.rpm` from one nfpm 2.48 definition, a
  systemd unit, `/opt/xmip`. nfpm, not `cargo-deb` or
  `cargo-generate-rpm`: those build from the crate's own manifest and
  features, and a package carries what `Build-XmipService -Site` built.
  **Written, not built.**
- `macos/` — **clause 7 is amended**: macOS is no longer archive only. A
  `.pkg`, pkgbuild's component in productbuild's distribution, registers a
  launchd daemon, as ADR-0018's amendment of 2026-09-28 already runs
  `xmip-service` under launchd; `/opt/xmip`. **Written, not built.** A
  `.pkg` Gatekeeper opens is signed with a Developer ID Installer
  certificate and notarized, and both need an Apple Developer Program
  membership: the owner's.
- `archive/` — clause 5's portable archive, a zip on Windows, with a README
  for the person who wants no installer.

There is no container file in the estate, so clause 4's OCI image is not
among them yet.

**One command installs, in every package.** A package carries two files,
`xmip-service` and the runtime library, and runs
`xmip-service --configuration <layout>/config/cluster.xmip --node <node>
--cluster <cluster> --install` (`.src/service/install.rs`): it writes a
starter cluster `cluster.xmip` where there is none — one node, offline
(ADR-0045), its operate listener's local endpoint named `xmip-<node>` like
its service (ADR-0014, amendment 2026-10-13), the account that installs it
its one operator, `[operate] operators`, as the operating system names that
account (ADR-0009, amendment 2026-11-07) — slices `node.xmip` from
it, makes `modules`, `logs`, the data directory and `data/audit`, and
registers and starts the Xmip Service that `registration.rs` defines, to
start with the machine. `--configuration <layout>/config/node.xmip
--uninstall` stops the service, waits for the drain and removes it, and
deletes nothing else (ADR-0040): no configuration, data, audit or log. A
configuration already there is never written over. So an installer
*registers what the runtime writes rather than a copy of it* (ADR-0018,
amendment 2026-09-28), and the layout and the starter are written once.
The service's environment carries `XMIP_AUDIT_DIRECTORY`, the node's
`data/audit` (ADR-0062), from the definition `--definition` prints. The
node and cluster default to the machine's name — the MSI's `XMIP_NODE` and
`XMIP_CLUSTER`, the Linux and macOS scripts' environment of the same names
— which is the drafting's.

**One entry point builds them: `Build-XmipService -Package`** — `msi`,
`deb`, `rpm`, `pkg`, `archive` — a parameter on the known noun, no new
command. On Windows it builds the runtime library beside `xmip-service`
with the same cargo arguments, then the MSI with `dotnet build` and the
winget manifest, and the zip, under `.local-work/package/<version>`; the
architecture is the `--target` triple's, else the machine's. `deb`, `rpm`
and `pkg` are REFUSED in words naming what their build needs.

**Open for the owner:**

- **WiX's fee.** WiX Toolset 6 and later carry the Open Source Maintenance
  Fee for commercial users; WiX 7's EULA (OSMF EULA 1.1) asks an
  organization with more than US$10,000 a year in revenue to sponsor the
  `wixtoolset` GitHub organization, and WiX 7 builds nothing until the EULA
  is accepted, once per user and machine
  (<https://docs.firegiant.com/wix/osmf/>). Whether Xmip accepts it is his
  decision, not taken here: nothing in the estate accepts it, and
  `-Package msi` is REFUSED, naming the command that would, until he has.
- **The service account.** No record names the account a node's service
  runs as: `deployment-model.md` section 5 lists the kinds per platform,
  `registration.rs` says the platform default — LocalSystem on Windows,
  root under systemd and launchd — is not what a production node wants, and
  open problem 28 has the group Managed Service Account. The packages
  register the platform default until he names one.
- **The names a package publishes under**: winget's `Xmip.Xmip`, the
  download address of a GitHub release, the macOS identifier
  `io.github.illenilsson.xmip`, and the publisher `Xmip`. Nothing is
  published yet.
- **What the local endpoint grants.** The starter lists the account that
  installs as the node's one operator, so the node is not closed to
  everyone; any other account is refused every call, reading included,
  until the configuration names it (ADR-0009, amendment 2026-11-07). That
  account is the one `xmip-service --install` runs as: the person who
  unpacked the archive and ran it, but the MSI's deferred action and the
  Linux packages' `postinstall.sh` run it as LocalSystem and root, so a
  package's starter lists those until the package hands over the person
  who installed; how it does, and whether every node serves a local
  endpoint by default, stay his (ADR-0014, amendment 2026-10-13).
- **Signing.** Nothing is signed: no Authenticode on the MSI or the
  programs, no Developer ID on macOS, no package signature on Linux.
- **Two starters.** The Ansible role writes its own starter from a template
  (`deploy/dsc/ansible`); it could run `--install` instead.
- **The event source.** The MSI does not register the Windows event source
  `Xmip` (ADR-0062 clause 3); `Install-XmipPrerequisite` still does.
- **A site whose node starts on its own.** A one-machine node is its own
  embedded Storage node and needs SQLite for its administration and audit
  databases, which only the `storage` role brings; no example site has it,
  so a package built from `personal-computer` installs a node that is
  refused as it starts (*was not built with xmip-core-persist-sqlite*).
  `personal-computer` with `storage` among its roles resolves and starts;
  which site an end user's package is built from is his.

**Verified, 2026-10-13, on Windows x64.** `xmip-service`'s and
`registration.rs`'s unit tests, clippy and rustfmt pass. The zip was built by
`Build-XmipService -Package archive`, unpacked, and `--install` run from it
without elevation: it wrote the starter, the slice and the folders, and the
Service Control Manager refused the registration with access denied, which
`--install` reported in its words with exit 2; `--definition` printed the
same registration, `--uninstall` said nothing was registered, and the node,
built with SQLite as above, started in a console and served its local
endpoint 275 ms after start. **The MSI is written and not built:** WiX 7
refused the build with WIX7015 until its EULA is accepted, so neither the
MSI nor its winget manifest has been made, validated or installed, and
nothing was installed elevated (no UAC prompt is ever launched). `-Package
deb`, `rpm` and `pkg` are refused in words.

## Amendment, 2026-10-14: the archiving roles carry the archive targets

**Provenance.** The owner, 2026-10-14: *Parquet is for archiving as other
storage technologies.* Asked whether the roles that archive should carry
the archive targets, he answered *Yes*.

*Amended 2026-10-20: the site chooses its archive targets; the roles keep
only the `archive` feature.*

**Archive targets are chosen by the roles that archive.** The roles that
carry the `archive` feature, `deploy/profile/role/sending.toml` and
`operational.toml`, name the archive targets they carry in `archives`, by
repository name, as a target names its technologies in `claims`: the ten
under `xmip-core-archive` — `azure-blob`, `file`, `gcs`, `mariadb`,
`mssql`, `parquet`, `postgresql`, `s3`, `sql` and `sqlite`. A composed role
carries its parts' (executing is receiving, processing and sending, so it
carries sending's).

**One reader.** `Get-XmipRoleArchive` reads a role's `archives`, its
composed roles expanded through `Get-XmipRoleComposition`, which
`Get-XmipRoleFeature` uses as well; `Get-XmipArchiveTarget` is every role's.
`Build-XmipService` carries a site's roles' archive targets beside its
chosen technologies, links each the root crate has a feature for, says the
rest under `Unlinked`, and shows them in the plan as `Archives`.
`test/Deploy.Test.ps1` fails when a role carrying `archive` names none or a
role not carrying it names one, or when a role names something that is not
a built archive target.

## Amendment, 2026-10-14: databases are technologies, not a domain

**Provenance.** The owner, 2026-10-14: *I guess the profile domain is
a bit wonky. Database.toml. Databases are technologies, not a domain. When
building & testing transports, there is where the build & tests shall
occur.* He answered *Go ahead* to deleting the `database` domain and the
requirement that a profile places every built technology.

**A technology is built and tested where it lands.** A transport, like
every technology, is built and tested in its own module when it lands
(`Publish-XmipChange`); no profile has to place it.

## Amendment, 2026-10-19: no domains; a site names its technologies

**Provenance.** The owner, 2026-10-19, on `deploy/profile/domain`: mail,
network and web-service are not domains, and neither is integration. Then:
*I guess the main reason was for your node configuration and slicing. You
have to let that go. Every end user will choose. We just have to show the
possibilities and test all.*

**The domain axis is deleted**, with every use: `deploy/profile/domain`
and its twelve profiles, a site's `domains`, `Get-XmipDomainTechnology` and
the plan's `Domains`. Nothing in the estate groups technologies for a
deployment.

**A site names its technologies.** `technologies` in
`deploy/site/<name>.xmip` lists, by repository name as a role names its
archive targets, the built technologies its end user chose, across
capabilities. `Resolve-XmipSite` REFUSES, in words, a name that is no
built technology (`Get-XmipBuiltTechnology`), links each the root crate has
a feature for, says the rest under `Unlinked`, and shows them in the plan
as `Technologies`; the target vetoes a technology's feature as it vetoes a
role's. The five example sites name what their descriptions say.

**Every built technology is built and tested.** `test/Deploy.Test.ps1`
holds each technology `architecture.toml` declares built to being mounted
as a declared module, which the landing builds with every feature it
declares and tests (`Publish-XmipChange`, `Test-XmipModule`), and to having
tests of its own. It found `xmip-core-persist-postgresql` declared
`scaffolded` with no repository; it is `planned`, nothing exists (ADR-0060),
as `deploy/database/postgresql/README.md` already said.

**Open for the owner:**

- Naming a technology by its repository name is the drafting's, his to
  strike.
- **How the possibilities are shown.** Nothing is built for it here.
- **A target's `claims`.** It kept the store engines and key stores out of
  the domains; now only the test that a target claims built technologies
  reads it. Whether it stays is his. *Answered 2026-10-19: deleted
  (amendment 2026-10-20).*

## Amendment, 2026-10-20: the site chooses its archive targets; only Storage stores

**Provenance.** The owner, 2026-10-20, on whether the archive targets stay
with the roles that archive: *Site chooses*. And on a target's `claims`, the
open question of the amendment of 2026-10-19, the same owner on 2026-10-19:
delete. And that only a node with the Storage role stores (ADR-0056,
amendment 2026-10-20).

**The amendment of 2026-10-14 is amended: archive targets leave the
roles.** A site names the archive targets its end user chose in its
`technologies`, by repository name, as it names every other technology
(amendment 2026-10-19). The roles that archive keep the `archive` feature —
`sending.toml` and `operational.toml` — and name no target. Deleted, with
every use: the roles' `archives`, `Get-XmipRoleArchive`,
`Get-XmipArchiveTarget`, the plan's `Archives`, and the tests that held a
role carrying `archive` to naming targets and a site's archiving roles to
building them. `test/Deploy.Test.ps1` holds instead that a site naming an
archive target builds it beside its role's `archive` feature.

**A target's `claims` is deleted**, with its reader `Get-XmipTargetClaim`
and the test *claims only built technologies*. A target still names the
features it always brings and the ones it refuses; the key store a node
seals its Storage under is its configuration's `[store]`, from what the
build carries.

**`retain` joins the sending role's features** (the owner, 2026-10-20).

**Only a node with the Storage role stores.** `development.toml` composes
`storage` beside executing, operational and monitoring, and the example
site `personal-computer`, one machine, declares `storage`: this answers
the 2026-10-13 open item *a site whose node starts on its own*. The other
example sites declare what they did; a one-machine node built from one of
them is refused as it starts, in words (ADR-0056, amendment 2026-10-20).
The starter `--install` writes, and the Ansible role's, declare `storage`
for their one node.

*Later the same day, the owner: a one-machine node carries the Storage
role.* `factory-gateway`, `hospital-interface` and `b2b-exchange`, the
Ansible role's default site, declare `storage` beside their roles, so no
example site of one machine is refused as it starts; `field-sensor`'s
device target refuses `persist` and builds no `xmip-service`, so it gains
nothing. `personal-computer` also names `xmip-core-authorize-location`: a
node built without a policy permits nothing, and with it a file dropped
in is received and sent on (ADR-0050, amendment 2026-10-20). Every build
of `xmip-service` carries the authenticate capability, its `circumstance`
verifier among it (ADR-0019, amendment 2026-10-20).

## Amendment, 2026-10-20: every database records its schema version, and an upgrade only adds

**Provenance.** Open problem 41. The owner, 2026-10-12: *The database
creation scripts are very static, that might be good since we have not
published. But when we have they have to alter databases and schema
objects.* And on 2026-10-19, agreeing to the problem's proposal as written:
*each database records its schema version, and the upgrade scripts are
generated as the difference between releases, adding only*.

**Every Xmip database records the schema version it holds**, the runtime,
the administration and the audit database alike, on every engine and
server: a table of its own, `schema_version`, its columns `version` and
`recorded_at`, a row for each version the database has held — the one it
was made at and each an upgrade reached. The version it holds is the
highest. This build's is `persist::storage::schema::VERSION`; until the
first release the schema is version 1 and changes in place, as nothing is
released, and nothing of a schema before this is kept or migrated
(CONTRIBUTING: until the first release, nothing is deprecated).

**A release's schema only adds to the one before.** Every table, column and
index of the one schema definition says the version that added it
(`since`). The schema at a version is everything added at it or before; the
difference between two releases is everything added after the first, up to
the second: a table made, a column added to a table already there, an index
made. Nothing is dropped or renamed — the definition has no way to say it —
and its test holds what it may say: a column added to a table already made
may hold nothing, a key is the table's from the first, and a released
schema's fingerprint (`RELEASED`) never changes.

**The upgrade scripts are generated from it**, one to each database,
`04-<domain>-upgrade-<from>-<to>.sql`, beside the scripts that make a
database (`deploy/database/<server>/`, held by `cargo test --test
database`): one for each release after the first, run in order of their
versions, each recording the version it reached. `03-<domain>-schema.sql`
makes `schema_version` and records the version it made. Generating them is
a tool act, `xmip-cli database <server> --from <version> [--to <version>]
[--out <folder>]` and `Get-XmipDatabaseScript -Server -From [-To] [-Path]`,
over one export, `xmip_database_upgrade_v1` (`xmip_operate.h` section 20):
from any release to the build's.

**At its start a Storage node reads each database's version.** The
embedded Storage node records each version after the one a database holds
— a step adds nothing else there: a table is a kind of record, a column a
value of the sealed body — and refuses a database newer than its build, in
words naming both versions; a database is never stepped down. Every node
that keeps databases publishes each at `<node>/storage/<domain>`, its
evidence `schema version <n> on <engine>`, so every surface shows the
version each holds.

**Decided by the owner, 2026-10-21**, as drafted here on 2026-10-20:

- An index added to a table already made is refused by the definition's
  test until the embedded engines can write its entries for the records
  they keep; the server's script would make it, but an embedded Storage
  node's index would hold only what is written after.
- A database that recorded no version is recorded at the build's version
  as it opens: every store before this change was made at version 1, and
  none is released.
- On a database server, whose login may not alter the schema, a Storage
  node refuses a database older than its build too, naming the upgrade
  scripts IT runs — once that backend is built.
- Version 1's fingerprint is recorded in `RELEASED` at the first release.

## Amendment, 2026-10-21: the environment templates, one set per technology

The owner, 2026-10-21: *one TOML file that can be run for tests regardless
of node faking or actual nodes* (ADR-0028, amendment of the same date); and
of the two technologies: *dotnet is cross platform, so is Blazor, MAUI and
DSC. We keep Ansible and other tech for familiarity and support for the
project.* Microsoft DSC v3 and Ansible each cover Windows and Linux alike;
Ansible is kept for the people who know it and for the project's support,
not for something DSC lacks. A deployment uses one of them, never a mix
(the amendment of 2026-10-09).

**What runs inside a machine** — the part the Hyper-V template's README
said was not written — is written twice, the same set in each technology,
and each does all five of the example's node machines, Windows Server 2025
and AlmaLinux 10 alike, and the DNS server: `deploy/dsc/msdsc/environment`
and `deploy/dsc/ansible` (the playbook `environment.yml`, the role
`xmip_node`, extended, and the role `xmip_name`). Given a cluster's
`cluster.xmip` and the machines, each:

- gives the environment's DNS server an A record for the cluster, holding
  every node machine's address, and one for each node, holding its
  machine's;
- gives each node machine its node's account — a virtual account of its
  own, `NT SERVICE\xmip-<node>`, on Windows, a system account, `xmip`, on
  Linux — `cluster.xmip`, and its certificate, key and anchors
  from the cluster's own authority (Xmip's internal CA, never the
  platform's), issued beforehand by `New-XmipCertificate -Node` on the
  operator's machine, the key private to the node;
- installs the estate's package, telling it the node, the cluster and the
  account (`XMIP_NODE`, `XMIP_CLUSTER`, `XMIP_ACCOUNT`), so the package's
  `xmip-service --install` slices the file already there, gives the
  account what it reads and writes, and registers and starts the service
  as that account;
- keeps the node's slice as `xmip-service --slice --cluster` prints it,
  restarting the node when it changed;
- opens the firewall for exactly the ports `xmip-service --listening` says
  the node's configuration listens on, and closes what it no longer does;
- holds the node's service running and started with the machine.

Every rule about the node is `xmip-service`'s, which the templates ask; no
template reads the TOML, slices it or knows a port. The mapping of nodes
onto machines is each template's parameters —
`environment.example.parameters.yaml` and `inventory.example.yml`, held
equal by `test/MsdscEnvironment.Test.ps1`; since the second amendment of
2026-11-11 the environment file's alone, the YAML written from it — and
never the cluster's file:
the example runs R1 on XMIP-IN01, S1 on XMIP-OUT01, P1 on XMIP-APP01, L1
on XMIP-APP02 and D1 on XMIP-APP03, and the Essentials simulates the rest.

**Microsoft DSC v3 as it is** (checked 2026-10-21: 3.3.0 current, 3.2.0
general availability 2026-04-29, 3.2.3 on the owner's machine). DSC is a
standalone command, its resources any executable speaking JSON. The
documents use a built-in resource wherever one fits —
`Microsoft.Windows/Service` for the Windows service — and Xmip resources of
their own folder, PowerShell 7 scripts behind resource manifests, for the
rest: `Xmip.Node/Account`, `File`, `Package`, `Slice`, `Opening` and
`Service`, `Xmip.Environment/Name` and `Xmip.Environment/Machine`. The
firewall is Xmip's own resource rather than the built-in
`Microsoft.Windows/FirewallRuleList`, because its ports are what the
configuration listens on, which the built-in would take typed. DSC applies
a document on the machine it runs on, so `Xmip.Environment/Machine` copies
the folder and a node's files to its machine — WinRM to Windows as its
Administrator, SSH to AlmaLinux with its key — and runs `dsc` there,
elevated. The documents require DSC `^3.2` and each resource `^0.1`. The
Windows PowerShell adapter is used nowhere in them. The Hyper-V template
keeps `PSDesiredStateConfiguration/File` and the HyperVDsc and
NetworkingDsc resources through that adapter: no built-in of 3.2 or 3.3
replaces any of them (superseded by the amendment of 2026-11-11: the
template's resources are Xmip's own).

**Ansible as it is** (ansible-core 2.21.5, 2026-10-05): PowerShell 7 on
the Windows machines (`ansible_pwsh_interpreter`), WinRM to them and SSH to
AlmaLinux, `ansible.windows`, `ansible.posix` and the builtin modules. The
role's starter template, `templates/cluster.xmip.j2`, is deleted: a node with
no cluster file of its own is given the package's starter, written once in
`xmip-service --install`.

**What xmip-service gained** (`.src/service`). `--account <account>` with
`--install`, the packages' `XMIP_ACCOUNT` (the MSI, the `.rpm` and `.deb`,
the macOS `.pkg`): the service runs as that account, which is given read on
the node's configuration and its key's folder and write on its data and
logs (`account.rs`; on Windows after the registration, when a virtual
account exists, and before the start); without it the platform's default,
as before. `--cluster` with `--slice`, and with `--install` where the
machine's `cluster.xmip` names no cluster: the one file names none
(`configure::slice_named`). `--listening`: the ports a node's configuration
listens on, one line each, `<port>/tcp <listener>` — its operate listener,
and each started Receive Location whose address names a port
(`listening.rs`); a transport does not yet say which protocol it listens
on, so a UDP one is said as TCP.

**A node's certificate from the cluster's own authority.** `xmip-service`
starts no provisioner yet (open problem 27), so a node is issued its key
and certificate on the operator's machine, before it is installed:
`provision::node::issue_into` keeps the cluster's authority in a folder, or
makes it there, and writes `node.pem` — server and client authentication,
for the node's name and every name it is reached by — `node.key` and
`anchors.pem` into the folder the templates ship, the files the cluster
file's `[operate]` names (`xmip_operate.h` section 22,
`xmip_node_issue_v1`; `New-XmipCertificate -Node`, `xmip-cli certificate
--node`). Ninety days is the assistant's draft of 2026-10-21, for the owner
to strike. The tester's operator certificate is signed by the same
authority, as section 19 signs any. The operation GUIs issue none: a node's
certificate is made where the authority is kept.

**Validated, never applied.** The documents are read and evaluated by DSC
with every resource replaced by an echo, and the Xmip resources' steps are
held with the machine's commands stubbed (`test/MsdscEnvironment.Test.ps1`);
the playbook passes `ansible-playbook --syntax-check` and `--list-tasks` in
the WSL AlmaLinux guest. Neither has been run against a machine; both were
on 2026-11-11 (the second amendment of that date).

Which account a node runs as was open (the amendment of 2026-10-13); the
virtual account and `xmip` are the assistant's draft of 2026-10-21, for the
owner to strike. DSC and Ansible are optional prerequisites, for test level
2 alone (`prerequisite.toml`).

## Amendment, 2026-10-22: every node of the example environment runs

A node that declares no Storage role reaches Xmip Storage over the wire in
the assembled service (ADR-0056, amendment of this date), so every node the
templates of the amendment of 2026-10-21 put on a machine starts, where
until today only D1 did. Nothing the templates do changed: each node's
certificate from the cluster's authority is what it presents to the
Storage nodes as well as on its operate listener, and the firewall opening
follows `xmip-service --listening`, which says `7443/tcp storage` on a node
declaring the Storage role. The Essentials' cluster file says its Storage
nodes once for every node, `[storage]`; the example's D2 is on no machine,
and every node passes it over. The assistant's, 2026-10-22.

## Amendment, 2026-10-29: the administration database keeps the secrets Locations name

The administration database gains a table of its own, `secret`, for the
secrets a Location presents to the party it connects to (ADR-0019,
amendment of this date): every value but the secret's own in a column of
its own — its `UUIDv7`, its unique `name`, its `kind`, `set_at` and
`set_by` — the value in `sealed`, sealed by Xmip before any store keeps
it, so a database server holds ciphertext alone (ADR-0063, amendment of
this date), and an index by name, `secret_name`, which
on an embedded Storage node holds the name alone. Its own table, never the
generic `administration` one, by the owner's rule that every type of data
has its own table and columns. Added in place at schema version 1, since
nothing is released (open problem 41); the scripts under
`deploy/database/<server>/` are written again from the one definition.

## Amendment, 2026-11-03: the machines in one command, on Hyper-V or libvirt

The owner, 2026-11-03: *It should be easy, now it is hard*; *one should be
able to set up the Core.Essentials on virtual servers with msdsc or Ansible
by a command*; *From whatever platform, you should be able fire up the test
environment with DSC*; and of the language of what manages it: *.NET or
PowerShell. That is for management, Rust is for runtime.*

**One command.** `Deploy-XmipEnvironment -Path <environment.toml>` makes an
environment's machines and waits until each is installed — and since the
second amendment of 2026-11-11 its nodes too, in the technology the file
names, one installation at a time. The environment
file is TOML, Xmip's configuration: the hypervisor, whose template it
selects (`deploy/dsc/msdsc/<hypervisor>`), the network, the images and the
machines, with the nodes each runs. It applies the template's
`network.dsc.yaml`, then `machine.dsc.yaml` once per machine, each on its
own with the parameters it declares, and applies a machine's again every
thirty seconds while it installs. One line per step says the time left.
`-WhatIf` tests and changes nothing. `environment.example.dsc.yaml` and
its parameters, which included each machine with `Microsoft.DSC/Include`,
are deleted: DSC reads an included document's state before it sets
anything, and NetworkingDsc's address and HyperVDsc's DVD drives throw
where the switch or VM is not yet there.

**Hyper-V keeps its DSC resources.** HyperVDsc and NetworkingDsc stay, run
through the Windows PowerShell adapter; that adapter needs the machine's
execution policy at RemoteSigned, set once. The documents ask for
elevation with the `securityContext` directive, DSC 3.3's form (superseded
by the amendment of 2026-11-11: Xmip's own resources, and only the
network's document elevated).

**libvirt, for a Linux host.** DSC v3 has no resource for libvirt and none
is published (checked 2026-11-03), so `deploy/dsc/msdsc/libvirt` brings
three of Xmip's own, in PowerShell 7 behind manifests as `Xmip.Node` is:
`Xmip.Libvirt/Network` (NAT, and DHCP and DNS giving each machine its
address and name and answering the nodes' and the cluster's names, so no
DNS server of the environment's own is needed), `Xmip.Libvirt/Pool` and
`Xmip.Libvirt/Machine`. It ran on 2026-11-03 in the WSL AlmaLinux guest:
XMIP-IN01 installed unattended through Secure Boot in seven minutes. A TPM
is given where the host has one to give, never required (the owner, the
same day: *TPM should not be required, just a plus*). A macOS host is not
written yet.

**The answers are one code for both.** The Windows answer file, the
kickstart and the answer medium moved to `deploy/dsc/msdsc/answer`; the MAC
prefix and the guest services' package are each hypervisor's, and the
medium is written with the image mastering API where the host has it, with
xorriso otherwise.

## Amendment, 2026-11-11: the Hyper-V template's resources are Xmip's own

The Hyper-V template's last real run, 2026-11-03, stopped at its first
machine: HyperVDsc's DVD drive resource, tested before XMIP-IN01 was made,
threw *Hyper-V was unable to find a virtual machine with name "XMIP-IN01"*
(`.local-work/deploy/Xmip-HyperV/run.log`). A resource that throws for what
is not there yet cannot be tested on a fresh host, and
`Deploy-XmipEnvironment` carried an exception for it.

**Xmip's own, as libvirt's are.** `deploy/dsc/msdsc/hyperv` brings two
resources in PowerShell 7 behind manifests, as `deploy/dsc/msdsc/libvirt`
does (the amendment of 2026-11-03). `Xmip.HyperV/Network`: an internal
switch, the host's address on it as its adapter's one manual IPv4 address,
and NAT for the network's prefix, named for the environment, or none where
the environment turns it off. `Xmip.HyperV/Machine`: the machine's folder
and dynamic disk, made once and never resized or replaced; a generation 2
VM with static memory, its processors, its one adapter on the switch with a
static MAC of Hyper-V's prefix, 00155D, two DVD drives, Secure Boot with
its image's template and a virtual TPM where its image asks for one, the
disk booted first; and its installation from the ISO with the answer
medium of `deploy/dsc/msdsc/answer`, started, its media removed once the
guest answers. Each `get` and `test` answers what is not there yet as
absent, `_exist` false with a finding that says so, never as a failure:
every switch, address, NAT and VM is listed and the instance looked for in
the list, so the host's own refusal, Hyper-V's permission for one, is still
an error. Hardware changes only while the VM is off; one running is
refused, never stopped, and so is one with more than one adapter, since
each would be given the machine's MAC: an adapter is never removed.

**A resource writes its answer alone.** DSC 3.4.0-preview.2 reads the first
line a resource writes on its standard output as its answer, and
`pwsh -File` writes a warning there too, before it. A machine still
installing is said by its state alone, `installation` `Installing` and its
finding, and the warning both templates' machines wrote on a `set` while
they installed, Hyper-V's and libvirt's (the amendment of 2026-11-03), is
deleted: with it, `dsc` failed with *JSON: expected value at line 1 column
1*, so `Deploy-XmipEnvironment` refused the first round in which a machine
was still installing, and no installation could finish through it.

**HyperVDsc and NetworkingDsc are deleted** from the template, its
prerequisites and its documents, with the Windows PowerShell adapter,
`PSDesiredStateConfiguration/File`, the two
`Microsoft.DSC.Transitional/PowerShellScript` resources and the
machine-wide execution policy the adapter needed. `Deploy-XmipEnvironment`
no longer reads a failed `test` as a step not yet made: every template's
resources answer absent, so a failure is refused, tested or set. The steps'
`template` value, which only the script resources read, is deleted, and so
is `switchName`, a second name for the network's `name`, which the switch
now takes as libvirt's network does. So the amendment of 2026-11-03 is
superseded where it kept HyperVDsc and NetworkingDsc, and the amendment of
2026-10-21 where it kept them and `PSDesiredStateConfiguration/File`
through the adapter.

**Elevation.** The network's document keeps `securityContext: elevated`: a
switch's host address and NAT are an administrator's to set. The machine's
document asks for none: a member of the host's Hyper-V Administrators group
manages VMs unelevated (the owner was told to join it, 2026-11-11), and the
template's README makes the account one, once, by the group's SID,
S-1-5-32-578. No manifest elevates a method.

**Validated, not yet run.** `test/MsdscHyperV.Test.ps1` holds the manifests
found by DSC, every property each requires given by its document, the
document order, and the resources' `get`, `test` and `set` with every
Hyper-V and network command a stub: a switch, a NAT and a machine that are
not there answered absent, the host's refusal kept an error, an absent
network and machine made, a Windows 11 machine's TPM given before its media
and Space pressed for its first twenty seconds, a machine still installing
answered by its state alone, a VM with two adapters refused, an installed
machine's media removed; `test/MsdscLibvirt.Test.ps1` holds libvirt's
machine left to install with nothing written. The template has not been
run against Hyper-V since. Not yet known: whether a member of Hyper-V
Administrators gives XMIP-DEV01 its virtual TPM unelevated. Its local key
protector rests on the host's Untrusted Guardian, whose certificates
Windows keeps in the LocalMachine store *Shielded VM Local Certificates*,
not on this host yet; the first run shows it, and the documents follow.
The assistant's, 2026-11-11.

## Amendment, 2026-11-11: an environment in one command, in either technology

The owner, 2026-11-11: *I won't see the full picture until we get msdsc and
ansible running on Windows & Linux.* The amendment of 2026-11-03 made the
machines in one command; this one makes the nodes on them too, in either
technology, from one file (`deploy/dsc/README.md`).

**One environment file, the technology a value in it.** The environment
file, TOML, is the only place that says what an environment is:
`technology`, `msdsc` or `ansible`, the template set that makes all of it,
never a mix (the amendment of 2026-10-09); the hypervisor; the network, the
images and the machines, each with the node it runs, one at most, since a
package lays one node out in one folder, the assistant's for the owner to
strike; and what a node is given — the cluster's file, this machine's
`xmip-service` that slices and signs, the authority, each node's
certificate folder, the far end, the package per family and, for msdsc,
the tools DSC is brought with. A file naming no technology is refused,
naming the line to add. `Deploy-XmipEnvironment` reads it and writes the
YAML each tool reads into the run folder — DSC's parameters, Ansible's
`inventory.yml` — generated, never configuration. The mapping the
amendment of 2026-10-21 wrote twice and held equal by a test is written
once: `environment.example.dsc.yaml`, `environment.example.parameters.yaml`
and `inventory.example.yml` are deleted, and the examples are
`deploy/dsc/hyperv.example.toml` and `libvirt.example.toml`, an environment
in either technology. Both map D2 beside D1: neither Storage node serves
until both answer (ADR-0056, amendments 2026-11-08 and of this date).

**msdsc, the nodes too.** After the network and the machines, one
installation at a time — a machine is applied again every thirty seconds
until it answers, and only then is the next made — the command applies
`names.dsc.yaml` where a machine is the network's DNS server, then
`environment/machine.dsc.yaml` once for each node in the order the file
lists the machines, and last `started.dsc.yaml`. An AlmaLinux machine needs
nothing but its sshd: `Xmip.Environment/Machine` reaches it with OpenSSH,
brings DSC there — the `pwsh` and `dsc` tarballs the file names, refused
where a SHA-256 differs, copied once and unpacked under
`/var/tmp/xmip-environment/tools`, never installed for the machine — and
runs `dsc` there with sudo; a Windows machine is reached over WinRM as
before and still has PowerShell 7 and DSC put on it once. `node.dsc.yaml`
names no built-in resource: DSC refuses a document naming a resource its
machine has none of, a condition notwithstanding, so
`Microsoft.Windows/Service` gave way to `Xmip.Node/Service` for both
families. `Xmip.Node/Package` compares an installed `.rpm` with the shipped
one by its header's SHA-256, so a build made again under one version
reaches the machine. A node refuses to accept work until its cluster's
Xmip Storage answers, and a Storage node until every one listed does, so
no node of them starts alone, one machine after another: each node's
document enables its service and starts it waiting for nothing, and
`Xmip.Environment/Started` starts them together, and again every five
seconds each one that stopped, until every one runs or 180 seconds are
spent. A resource answers a machine that does not answer yet, and openings
before the package, as absent.

**Ansible, the machines too.** The role `xmip_machine` makes them —
`community.libvirt` on libvirt, Microsoft's `microsoft.hyperv` on Hyper-V
— one installation at a time; then `xmip_name`; then `xmip_node`, one
machine at a time; and a last play starts every node together, as msdsc
does. Ansible's controller does not run on Windows, so there the command
refuses `technology = "ansible"` and names the WSL command. Its `-WhatIf`
is `--check`, and answers what msdsc's test does: every task that only
reads runs under it (`check_mode: false`), the `.rpm`'s headers,
`--listening` and the ports firewalld holds among them; every command that
changes names the file it needs in `removes`, which is how the command
module says under `--check` that it would run; a host is in its desired
state only where nothing would change; and a machine not made yet is
answered unreached, never refused, a domain not defined yet is not asked
to run.

**What a machine is, written once.** The network, pool and domain
definitions, the Hyper-V machine's files, MAC and drives, the kickstart,
the Windows answer and the answer medium moved to `deploy/dsc/machine`,
plain PowerShell 7: DSC's machine resources dot-source it and Ansible's
role asks `machine.ps1`; no task writes a definition of its own. After the
review of the same day so did each step of a libvirt machine's
installation, `LibvirtInstallation.ps1`: `virsh`, the media put in the
pool, the domain started with Space pressed for a Windows ISO, and the
installation completed. Ansible's role asks `machine.ps1` for `State`,
`Install` and `Complete`, and `Xmip.Libvirt/Machine` keeps only where a
machine is and moving it on. An ISO's volume is named by its SHA-256 and
made only once it was checked, so its gigabytes are read once, not once
per machine; it is made sparse and uploaded, and trusted by its name only
where libvirt says all of it is allocated, so one an upload that stopped
left short is deleted and uploaded again. The answer medium, which holds a
machine's host key or a Windows Administrator's password, is written in a
folder made for it alone, named at random and, off Windows, `0700`, as
.NET's `Directory.CreateTempSubdirectory` makes it — never at a name in
`/tmp` another account could know or make first — and the folder is
removed. A machine is recorded installed only once both its drives are
empty and its answer medium is gone from the pool: either left is refused
before the record, and the next run tries again. How the Windows machines'
Administrator secret is read is placed once too, `MachineSecret.ps1`: off
Windows `Export-Clixml` keeps a password as plain text, a Unicode
character array
([Microsoft](https://learn.microsoft.com/powershell/module/microsoft.powershell.utility/export-clixml)),
so a file whose password is not encrypted by Windows' Data Protection API
is refused wherever it is read, and an encrypted one is read on Windows
alone.

**One technology, held.** An environment is made by one technology, never a
mix (the amendment of 2026-10-09), and the environment now keeps which: the
first run that applies writes it into the private state, `technology`, and
a run of the other one, `-WhatIf` too, is refused until the environment is
removed (`deploy/dsc/README.md`, *Starting again from nothing*); a libvirt
machine's record in its domain names the technology that made it, and the
other is refused there, by the one function both technologies ask. On a
node machine msdsc stages in its own folder, the login's alone, `0700`,
one another account owns refused, and what a node is given, its key among
it, is removed from it once `dsc` has run; Ansible stages the package in a
folder of its own, `/var/tmp/xmip-ansible`.

**Keys known in advance.** The command keeps an environment's private
state — on Linux under `~/.local/state/xmip/deploy/<name>`, on Windows in
the run folder, its access the account's alone — and in it the
environment's own SSH key, which each AlmaLinux machine's account is
given; a host key for each AlmaLinux machine, which its kickstart writes;
and `known_hosts` holding exactly those, so every login is checked strictly
and none trusts on first use. The run takes the folder's `run.lock` before
it writes any of that, so a run refused changes no key and no
`known_hosts` the running one reads. The environment file's
`ssh_public_key` is deleted: the owner's key carried a passphrase, so no
run could go unattended, and on a Windows drive mounted in WSL every file
shows as `0777`, which OpenSSH refuses for a private key. The key made in
its place has no passphrase, and every AlmaLinux machine gives its account
sudo without a password, so whoever reads that one file is root on every
node — and on Windows the file is inside the clone. That trade is the
assistant's, made without the owner: it is not a decision of his, and it
waits on him (below). `credential` is `secret`, as the owner's word for it
is.

**The `.rpm`, built and installed.** `Build-XmipService -Package rpm` on
Linux makes it with nfpm 2.48.0 from `deploy/package/linux/nfpm.yaml`
(`New-XmipLinuxPackage`), and still refuses it off Linux. Built in the WSL
AlmaLinux guest, the systemd branches of `install.rs` compiled for the
first time, warnings denied, with no change.

**The first runs**, in the WSL AlmaLinux guest, on libvirt: three AlmaLinux
10.2 machines of two virtual processors and 4 GiB — XMIP-APP03 for D1,
XMIP-APP04 for D2, XMIP-IN01 for R1 — one installation at a time, twelve
to twenty-two minutes each beside builds, each answering SSH with the host
key `known_hosts` held. **msdsc**, from a clean state: the network, the
pool and the machines; the nodes' first step found a defect, a package
step that failed on a machine with no package, fixed with its test; the
next run brought DSC to each machine, placed its slice, certificate and
account, installed the `.rpm` — its `postinstall.sh` ran `xmip-service
--install` — opened exactly the ports `--listening` says, `7401/tcp`, and
`7443/tcp` on D1 and D2, and started the three together. Each unit was
`active` and `enabled`, each journal said `accepts work`, R1 and D2 were
connected to D1 on 7443, `node.xmip` was `xmip:root 0640` and
`tls/node.key` `0600`, with no SELinux denial. A line appended to R1's
`node.xmip`, and a restart: refused, the node running its accepted slice;
the next run put the shipped slice back, every one of its eight steps in
its desired state, exit 0. A node's step took four to nine minutes: DSC
and PowerShell 7 start once for each resource and method on a
two-processor machine, and the document runs there three times a step, a
set and two tests; to be measured and cut. Those runs used the code as it
stood before the private state moved under `~/.local/state`, before
`run.lock`, `Invoke-XmipDeployRun` and the later edits of the day to
`Deploy-XmipEnvironment.ps1` and `Initialize-XmipDeployState.ps1`, and no
log of them was kept.

**Ansible**, on the same host and file, with ansible-core 2.22.0 on Python
3.13: from a clean state its machines play made the network, the pool and
the three machines, one installation at a time, in 57 minutes beside
builds. Its runs found three defects, each fixed with its test or its run.
`register_secret`, which masks the node's key, is ansible-core 2.22's, so
the controller is 2.22 (`prerequisite.toml`). firewalld refuses a service
made permanent and enabled at once (`INVALID_SERVICE`), so the role makes
it permanent and reloads, and asks the running firewall, reloading where a
run that stopped before its handlers left it without: D1's opening missing,
D2 and R1 never reached it and refused to accept work. And a second run was
started while the first still started its nodes, so `Deploy-XmipEnvironment`
holds the environment's private state through `run.lock` and refuses a
second run while one runs. No one of those runs took the node play from
fresh machines to running nodes, though: the first failed on XMIP-APP03
after seven changes, the second there too, the third installed the nodes
on XMIP-APP04 and XMIP-IN01 and failed at the last play while a fourth
was started beside it, and the fourth, first offered here as the proof,
changed one thing per host, the firewall reloaded — the account, slice,
certificate, key, package and firewalld service were there from before.
Its tasks read a machine's facts through `ansible_facts`, as ansible-core
2.24 requires once it injects none as variables, the inventory names each
AlmaLinux machine's Python rather than discovering it, and every group is
written, an empty one too, so no run warns. The review of the same day
said all of this.

**From nothing, after the review**, the same day, on the code as it
stands: before each run every machine, every volume of the pool, the ISO's
among them, the pool, the network, the run folder and the private state
were removed (`deploy/dsc/README.md`, *Starting again from nothing*), and
the run went once from start to finish, its log kept beside the run
folder, `.local-work/deploy/xmip.*.run.log`.

- **Ansible.** `-WhatIf` against the empty host made nothing: the machines
  play would change eleven things, and XMIP-APP03 was not reached. The
  play run a host at a time stopped there and its recap named no other
  host, so since then a host the recap lacks is answered unreached too.
  Then one run made the network, the pool,
  the ISO uploaded whole (10,106,380,288 bytes allocated of 10,106,372,096),
  the three machines, the nodes and their start in 30 minutes 2 seconds:
  `failed=0` on every host, each node machine `ok=30 changed=17`, the
  controller `ok=30 changed=11`, exit 0. Each unit `active` and `enabled`,
  each journal `accepts work`, D1 serving five connections on 7443 — R1's
  three and D2's two — firewalld's service for each node holding
  `7401/tcp`, and `7443/tcp` on D1 and D2, `node.xmip` `xmip:root 0640` and
  `tls/node.key` `xmip:root 0600`, no SELinux denial, nothing in msdsc's
  staging folder, no answer medium in `/tmp`, and each domain's record
  `installed="yes" technology="ansible"`. `-WhatIf` over it: `changed=0`
  everywhere. A port added by hand to R1's firewalld service, `7999/tcp`:
  `-WhatIf` answered XMIP-IN01 not in its desired state, the close counted
  as a change, and the next run closed it and reloaded the firewall,
  `changed=2` there and 0 elsewhere. `-WhatIf` with `technology = "msdsc"`
  over it was refused by the state's `technology` and, that record set
  aside, by XMIP-APP03's own: `REFUSED: XMIP-APP03 was made by 'ansible',
  not msdsc`. msdsc's test of the network and the pool found what that run
  had left undone: neither was started with the host, since `virt_net` and
  `virt_pool` answer a task naming a state before they look at `autostart`
  (community.libvirt 2.4.0, `core`); starting and starting with the host
  are a task each now, with their test, and the next run set both,
  `changed=2` on the controller alone.
- **msdsc.** `-WhatIf` against the empty host: each of its eight steps not
  in its desired state, nothing made and no technology recorded. The first
  run made the network, the pool and the machines and placed every node,
  and no node started: `xmip-service` was refused reading
  `authority/authority.pem`, *Permission denied*. The staging folder now
  makes the node's files `0600`, and a copy keeps its source's mode, so the
  authority's certificate, root's, was no longer the node account's to
  read. `Xmip.Node/File` gives a file named not private `0644` whatever
  its source's mode, and checks it, with its test. The next run from
  nothing: every one of its eight steps in its desired state, exit 0, in
  36 minutes 42 seconds — each machine eight to ten minutes, each node's
  step two and a half, the start 37 seconds. Each unit `active` and
  `enabled`, each journal `accepts work`, D1 serving four connections on
  7443, the same ports, `node.xmip` and `tls/node.key` as Ansible's,
  `node.pem`, `anchors.pem` and `authority/authority.pem` `0644`, no
  SELinux denial, the staging folder `0700` and the login's with no
  `files` left in it, no answer medium in `/tmp`, the network and the pool
  started with the host, and each domain's record `installed="yes"
  technology="msdsc"`. Run again, every step was in its desired state in
  7 minutes 19 seconds, and every node restarted: DSC asks
  `Xmip.Environment/Slice` to set without a test first
  (`implementsPretest`), and each set signed the slice anew, so each
  machine's `node.xmip` was replaced for a new signature. A slice whose
  signed text is the one there is kept now, with its test, and the next
  run, 7 minutes 46 seconds, every step in its desired state, restarted no
  node. `-WhatIf` with `technology = "ansible"` over it was refused by the
  state's `technology`.
- **Ansible once more from nothing**, on the code with both fixes.
  `-WhatIf` against the empty host: the controller's play would change
  thirteen things, and all three node machines were answered unreached.
  Then one run, 28 minutes 15 seconds: `failed=0` on every host, each node
  machine `ok=30 changed=17`, the controller `ok=32 changed=13`, exit 0;
  each unit `active` and `enabled`, each journal `accepts work` once, D1
  serving five connections on 7443, the ports, modes and records as the
  first, the network and the pool started with the host. Run again:
  `changed=0` on every host in 1 minute 36 seconds, and no node restarted.
  The environment is left as that run made it, its machines shut down.

**What is still written twice, and why.** Ansible's Hyper-V tasks carry
three rules the msdsc Hyper-V resources hold: the host's address on the
switch and the network's NAT (`HyperVNetwork.ps1`), the TPM's key
protector (`HyperVHardware.ps1`) and Space pressed at a Windows ISO's
prompt (`HyperVInstallation.ps1`), inside `win_powershell` scripts the
analyzers and Pester never read. They run on the Windows host, where no
file of the controller's is, and the resources they copy were being
rebuilt by another worker that day; the way to place them once is a
script of `deploy/dsc/machine` that both call, Ansible handing it to the
host as `win_powershell`'s script. That is left for once the Hyper-V
template has run. The `.rpm` header comparison is the other copy: an
Ansible node machine has no PowerShell 7, so its role asks `rpm` for
`%{SHA256HEADER}` itself, as `Xmip.Node/Package` does on an msdsc one; the
rule is `rpm`'s, and each technology asks it.

**What waits on the owner.** Hyper-V, either technology: membership of
Hyper-V Administrators, which the owner's account has not joined yet, so
the Hyper-V way of `doc/getting-started.md` has never run. For Ansible
there: how its Linux controller reaches the host — the file's `host`,
`ANSIBLE_REMOTE_USER` and its password, asked — and how that controller is
given the Windows machines' Administrator password, which a secret file
cannot carry off Windows: asked at each run, Ansible Vault, or Xmip's own
secret store (`Set-XmipSecret`). Until he chooses, a Windows machine is
made by msdsc on a Windows host. The environment's SSH key: kept without a
passphrase, so whoever reads it is root on every AlmaLinux node, and on
Windows inside the clone; the ways the review named are an `ssh-agent`
holding a key with a passphrase, or the owner's own protected key loaded
into an agent for the run, and the Windows state moved out of the clone,
under `%LOCALAPPDATA%`. His answer is to be recorded here. The `.rpm`
needs a Linux build of `xmip-service`, made in the guest against his
choice of 2026-11-02 to build Windows alone; the assistant read his words
of 2026-11-11 as lifting it for the Linux package, which is his to
confirm. The MSI (WiX 7's terms). Ansible on Hyper-V is written and held
by `--syntax-check`, `--list-tasks` and `ansible-doc`, never run.
ansible-core 2.22 needs Python
3.13, on AlmaLinux 10.2 EPEL's `python3.13`, which `dnf` installs with sudo:
the guest runs it from those packages unpacked into its account, its
library named by `LD_LIBRARY_PATH`, until it is installed so. A
switch that takes an environment down is not built; the run sheet does it
with `virsh` (`deploy/dsc/README.md`). Deploy is management tooling in
PowerShell, not an act on a node: the ABI, the CLI and the GUIs have
nothing to follow. The mapping of 2026-10-21 and its *Validated, never
applied* are answered here; the amendment of 2026-11-03 now covers the
nodes too.
