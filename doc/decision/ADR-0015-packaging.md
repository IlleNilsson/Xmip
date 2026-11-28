# ADR-0015: Packaging and distribution

## Status

Accepted. Implementation follows in separate reviewed changes.

## In brief

- Theme: Operating Xmip
- Subject: Packaging and distribution
- Name: Packaging and distribution
- Order: 2
- Concepts: arm64, embedded, IoT; MSI, winget, deb, rpm, OCI, pkg, launchd; target, site; archive target; schema version, upgrade; environment template, environment table

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
2026-11-11). Every package carries `xmip`, the command line, and puts it
on `PATH` where it has an installer (amendment 2026-11-19). Every database records its schema version, and a
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
  System Tests', composes executing, operational and monitoring.
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
under `xmip-core-archive` — `aws-s3`, `azure-blob`, `file`,
`google-cloud-storage`, `mariadb`, `mssql`, `parquet`, `postgresql`, `sql`
and `sqlite`. A composed role
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
on XMIP-APP02 and D1 on XMIP-APP03, and the System Tests simulate the rest.

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
declaring the Storage role. The System Tests' cluster file says its Storage
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
able to set up the Core.System on virtual servers with msdsc or Ansible
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
threw *Hyper-V was unable to find a virtual machine with name "XMIP-IN01"*.
A resource that throws for what is not there yet cannot be tested on a
fresh host, and `Deploy-XmipEnvironment` carried an exception for it. The
run's log, trimmed to the step and its error:

```text
== 2026-11-03T13:32:25.2707963Z test XMIP-IN01
2026-11-03T13:32:44.358776Z ERROR PID 9336: Script failed with terminating error at line 0 for statement `` - System.Management.Automation.MethodInvocationException: Exception calling "Invoke" with "4" argument(s): "The running command stopped because the preference variable "ErrorActionPreference" or common parameter is set to Stop: Exception: Hyper-V was unable to find a virtual machine with name "XMIP-IN01"."
2026-11-03T13:32:44.391706Z ERROR Failed to run process 'powershell': Command: Resource 'powershell' [exit code 1]
```

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
the run went once from start to finish. The deciding lines of each
technology's log follow its paragraph.

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
  `changed=2` on the controller alone. That run's recap:

  ```text
  PLAY RECAP *********************************************************************
  XMIP-APP03                 : ok=24   changed=0    unreachable=0    failed=0    skipped=25   rescued=0    ignored=0
  XMIP-APP04                 : ok=24   changed=0    unreachable=0    failed=0    skipped=25   rescued=0    ignored=0
  XMIP-IN01                  : ok=24   changed=0    unreachable=0    failed=0    skipped=25   rescued=0    ignored=0
  localhost                  : ok=22   changed=2    unreachable=0    failed=0    skipped=11   rescued=0    ignored=0
  ```

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
  state's `technology`. That last run's eight steps, each with the test DSC
  made after its set, from the log's step lines and their JSON:

  ```text
  22:57:49Z set network      test 11.6 s  inDesiredState true x2  hadErrors false
  22:58:27Z set XMIP-APP03   test  7.7 s  inDesiredState true x1  hadErrors false
  22:59:03Z set XMIP-APP04   test  7.1 s  inDesiredState true x1  hadErrors false
  22:59:31Z set XMIP-IN01    test  6.9 s  inDesiredState true x1  hadErrors false
  22:59:59Z set D1           test 24.3 s  inDesiredState true x2  hadErrors false
  23:01:40Z set D2           test 24.2 s  inDesiredState true x2  hadErrors false
  23:03:20Z set R1           test 24.3 s  inDesiredState true x2  hadErrors false
  23:05:01Z set started      test  8.1 s  inDesiredState true x1  hadErrors false
  ```

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

## Amendment, 2026-11-13: the PostgreSQL wire Storage reuses is a library

The PostgreSQL wire protocol the 2026-10-01 amendment has Xmip Storage reuse
"in its PostgreSQL transport" is `xmip-core-library-postgresql`'s since
2026-11-13, and the transport, the archive target and
`xmip-core-persist-postgresql` reach it there (ADR-0011, amendment of this
date). Still one implementation, no async runtime.

## Amendment, 2026-11-19: the command line ships in every package

**Provenance.** Decided while designing on 2026-11-18 and told the owner:
`xmip`, the Rust command line, was built on 2026-11-17 (ADR-0014, amendment
of that date), and no package carried it. It answers the Open section's
*There is no binary to package yet*: `xmip-service` has been packaged since
2026-10-13, and `xmip`, the command ADR-0014 clause 8 names, produced by
`xmip-core-cli`, is packaged with it now.

**Three programs in every package**, in `bin`: `xmip-service`, the runtime
library the .NET surfaces load, and `xmip`, the command line, which links
the runtime and needs neither the library nor .NET. `Get-XmipPackageProgram`
is the one list of them, each as its system names its file, with the
estate folder cargo builds it in. `Build-XmipService -Package` builds the
library and `xmip` beside `xmip-service`, with the same cargo arguments;
each is a workspace of its own and builds into a folder of its own under
the target directory, `package-operate` and `package-cli`, through the one
crate build every build of the module runs (`Invoke-XmipCrateBuild`).

**`xmip` on `PATH` where there is an installer**:

| package | `xmip` is | on `PATH` as |
| --- | --- | --- |
| MSI | `Program Files\Xmip\bin\xmip.exe` | `bin` added to the machine's `PATH` (`XmipPath`, last, not permanent), removed with Xmip |
| `.deb`, `.rpm` | `/opt/xmip/bin/xmip`, 0755 | `/usr/bin/xmip`, a link the package owns |
| macOS `.pkg` | `/opt/xmip/bin/xmip` | `/usr/local/bin/xmip`, a link `postinstall` makes; written, not built |
| archive | `xmip/bin/xmip.exe` | not at all: its README says to add `bin` or name the program |

`xmip` takes no other package's name (ADR-0053, amendment 2026-10-22).
winget's installer manifest names it under `Commands`.

**No package ships `cli.toml`.** The command line's build copies the
repository's beside the executable, and that one follows the System Tests,
so the staging copies the three programs alone. `xmip-service --install`
writes the installed node's `<bin>/cli.toml` where there is none —
`Surface = "local"`, `Local` the node's local endpoint, no audit directory
— and removal keeps it (ADR-0040); the command line finds it beside its
own path, on Linux and macOS with every link resolved, so `/usr/bin/xmip`
reads `/opt/xmip/bin/cli.toml`; Windows puts `bin` itself on `PATH`, so
there is no link to follow.

**Signing is unchanged**: nothing is signed (amendment 2026-10-13), and
open problem 42's signing now names the three programs.

**Verified, 2026-11-19**, built from the working trees after `5cecded`
through the local patch, on Windows 11 x64 and in the AlmaLinux 10 guest
under WSL on the same machine. Not installed: neither the `.rpm` nor the
`.deb`; the MSI is not built (WiX 7's terms, the owner's), and the `.pkg`
is written, not built.

The Windows archive, `Build-XmipService -Site personal-computer
-CargoArgument '--release' -Package archive`, unpacked: `bin` holds the
three and no `cli.toml`, though the command line's build had copied one
beside its own executable.

```text
==> OK: archive D:\Repos\Xmip\.local-work\package\0.1.1\xmip-0.1.1-personal-computer-windows-x64.zip
bin: xmip_core_operate.dll  xmip-service.exe  xmip.exe
> bin\xmip.exe abi
module version      1
module entrypoint   xmip_create_module_v1
module file name    xmip_core_transport_file.dll
operate version     1
operate entrypoint  xmip_operate_v1
exit 0
> bin\xmip.exe status 0
    0  Ok
       the call succeeded
       retryable: no   terminal: no
exit 0
```

The `.rpm`, the same command with `-Package rpm` in the guest, and
`rpm -qlp` with each entry's mode; the staged `xmip abi` and
`xmip status 0` answered with exit 0 there too:

```text
==> OK: rpm /mnt/d/Repos/Xmip/.local-work/package/0.1.1/xmip-0.1.1-personal-computer-linux-x64.rpm
-rw-r--r-- /opt/xmip/bin/libxmip_core_operate.so
-rwxr-xr-x /opt/xmip/bin/xmip
-rwxr-xr-x /opt/xmip/bin/xmip-service
l--------- /usr/bin/xmip -> /opt/xmip/bin/xmip
```

The `.deb`, `-Package deb` in the guest, its data listed with `ar` and
`tar`. The run was made after the owner had refused the call that would
have started it; he allowed its result the same day ("Do it").

```text
==> OK: deb /mnt/d/Repos/Xmip/.local-work/package/0.1.1/xmip-0.1.1-personal-computer-linux-x64.deb
-rw-r--r-- root/root  14928480 ./opt/xmip/bin/libxmip_core_operate.so
-rwxr-xr-x root/root  11141648 ./opt/xmip/bin/xmip
-rwxr-xr-x root/root  31302328 ./opt/xmip/bin/xmip-service
l--------- root/root         0 ./usr/bin/xmip -> /opt/xmip/bin/xmip
```

## Amendment, 2026-11-20: the library and the command line are members of the estate's one workspace

**Provenance.** The owner, 2026-11-20: *Go with recommendations*, the first
of which was one Cargo workspace for the estate (ADR-0016, amendment
2026-11-20). What it means for the package's build was decided by the
assistant while building, told to the owner.

The amendment of 2026-11-19 says the runtime library and `xmip` are each a
workspace of their own. Since 2026-11-20 every crate of the estate is a
member of one workspace, resolved once (ADR-0016, amendment 2026-11-20), so
`xmip-core-operate` and `xmip-core-cli` build with the root's resolution.
Each now builds in its folder into the same target directory as
`xmip-service`. The separate folders `package-operate` and `package-cli`
were there so builds with different resolutions could not overwrite each
other, and one resolution has nothing to overwrite: they are gone, with
`Get-XmipPackageProgram`'s `Target`. The dependencies the three programs
share compile once, and nothing else of the package build changes
(decided by the assistant while building, told to the owner).

## Amendment, 2026-11-22: the Hyper-V example is the node plan, its machines sized and fenced per machine

**Provenance.** The owner, 2026-11-22, settling the plan of the machines
Xmip is tested on: twenty-one machines in Hyper-V, Windows Server as Server
Core and Linux minimal but on the people's machines, the internet optional
and on XMIP-RX01 alone; then *Now we need a local test, represented by
processes and another represented by Hyper-V* and *Let's get it to work*.
How the templates carry it was decided by the assistant while building,
told to the owner.

- **The example is the plan.** `deploy/dsc/hyperv.example.toml` lists the
  plan's 21 machines: the domain controller and file storage, the ten
  node machines, the six far-end machines and the three people's
  machines; the Mac is not a VM. XMIP-DB01, XMIP-DB02, XMIP-APP01 to
  XMIP-APP04, XMIP-IN01 and XMIP-OUT01 are deleted from it. Each machine
  is named for what it runs, and the ten nodes the cluster's file declares
  but OP1 each run on a machine of its own.
- **Dynamic memory, per machine.** A machine's `memory_gb` is what it
  starts and installs with; `dynamic_memory = { minimum_gb, maximum_gb }`
  lets Hyper-V give it what it uses between the two, in steps of 2 MiB,
  `minimum_gb <= memory_gb <= maximum_gb`; without it the memory is static,
  as before. `Get-XmipDeployDynamicMemory` reads it once for both
  technologies; `Xmip.HyperV/Machine` sets it and finds a VM that differs,
  and Ansible's Hyper-V tasks set it at install. The example's maxima are
  the plan's figures; Linux starts with 2 GiB, which its installer needs
  (RHEL 10: 1.5 GiB from local media), so the plan's 1 GiB far ends get 2.
- **A way out, per machine.** `internet` in `[network]` says whether its
  machines reach past it, every one where it is left out, as before; a
  machine's own `internet` overrides it. A machine that does not is
  installed with no gateway — no route in its Windows answer, no
  `--gateway` in its kickstart — and reaches the network alone, the host
  on it included. The example says none does but XMIP-RX01. The NAT stays
  for it.
- **A Linux desktop.** A Linux image's `environment` names the kickstart's
  environment group, `minimal-environment` where it names none; one with a
  desktop is started to its graphical target. The example's
  `AlmaLinux10Desktop` is the same DVD with
  `workstation-product-environment`, for XMIP-DEV02.
- **Time without a way out.** On Hyper-V the kickstart gives chrony the
  host's clock, `refclock PHC /dev/ptp_hyperv`, a udev rule naming the
  guest's `hyperv` PTP clock: a machine with no gateway reaches no pool,
  and nodes and far ends on different machines time what they carry.
- **Elevation, found.** Every run of `Deploy-XmipEnvironment` on Hyper-V
  applies the network first, and its document asks for elevation as a
  whole, so no run passes unelevated, a network already in its desired
  state too. Moving the elevation to the resource's set alone does not
  help: DSC 3.4.0-preview.3 refuses the unelevated `dsc config set` before
  it tests (*Operation 'set' for resource 'Xmip.HyperV/Network' requires
  security context 'elevated'*), so the documents stay as they were. A run
  that tests each step and sets only one that differs would pass an
  unchanged network unelevated; it waits on the owner.

## Amendment, 2026-11-22: the System Tests' far ends on machines of their own, registered by the one registration

**Provenance.** The owner's node plan of 2026-11-22 puts the System Tests'
six far ends on machines of their own (ADR-0028, amendment of this date);
the coordinator, the same day: *xmip-service already runs as a Windows
service. The far end's Windows service must call that one implementation,
moved to the lowest layer both can call if needed. Never write a second
integration of windows-service.* Built by the assistant the same day.

- **One registration, one dispatcher, in the runtime.** What applies a
  service definition, registering it with the platform's service manager
  and starting it, or stopping and removing it, is
  `registration::apply`; what runs a registered program under the Windows
  Service Control Manager, its dispatcher, control handler and states, is
  `registration::control_manager`. Both moved from `xmip-service`
  (`install.rs`, `control_manager.rs`), which now calls them with its own
  definition, the account it gives its node and its drain; the root no
  longer depends on the `windows-service` crate, the runtime does, once.
  The System Tests' far end calls the same two with its own definition.
- **A far end's machine.** A machine's `external` names the far end it
  runs; the environment file's `[far_ends.<family>]` names the program,
  `xmip-system-test-external` built for that family. msdsc's
  `far-end.dsc.yaml` applies `far-end-program.dsc.yaml` there: the far
  end's certificate from the cluster's authority, the program placed and
  registered as the service `xmip-<name>` by its own `--install`
  (`Xmip.Node/Program`, new), a firewall opening for the ports its
  `--listening` says, and its service kept running. The names step gives
  the far end's name its machine's address.
- **Bound for them.** `far_end` takes a list, the receiving far ends in the
  order the System Tests name their receivers, each Send Port bound to the one
  of its turn; `listen = true` has each Receive Location listen over HTTP on
  its node (`xmip-service --slice --bind a,b,c --listen`). One far end, the
  host, binds every Location as before. Ansible's inventory passes both;
  its role for a far end's machine is not written.

## Amendment, 2026-11-22: the libvirt example is the node plan under KVM

**Provenance.** The owner, 2026-11-22: *Now we need a local test,
represented by processes and another represented by Hyper-V and a version
for Linux. You can choose the Linux VM engine.* The engine chosen is KVM
through libvirt, which the templates made machines on from nothing on
2026-11-12. How the templates carry the plan there was decided by the
assistant while building, for the owner to strike.

- **The example is the plan.** `deploy/dsc/libvirt.example.toml` lists the
  Hyper-V example's 21 machines, machine for machine: their names,
  addresses, systems, nodes, far ends, the domain's controller as the DNS
  server, XMIP-RX01's way out and XMIP-DEV02's desktop, each through the
  key the Hyper-V example uses (the amendments before this one). XMIP-APP03,
  XMIP-APP04 and XMIP-IN01 are deleted from it.
- **Dynamic memory is a balloon.** On libvirt `dynamic_memory`'s
  `maximum_gb` is the domain's memory, of which a virtio balloon starts with
  `memory_gb`; the balloon gives the guest back up to its most once it runs
  short (`autodeflate`) and the host every page the guest frees
  (`freePageReporting`). libvirt has no least, so `minimum_gb` is
  Hyper-V's alone. Windows has no balloon driver of its own and the one
  there is, virtio-win's, is a third party's, so on libvirt a Windows
  machine's memory is static and its `dynamic_memory` is refused before
  anything is made; the example gives Windows Server 2 GiB, the plan's
  floor, and Windows 11 4 GiB. The owner may take virtio-win's balloon
  instead.
- **One home for what a hypervisor gives its guest.**
  `deploy/dsc/machine/MachineGuest.ps1` holds the instance's dynamic memory,
  moved from the Hyper-V template, and chrony's clock line, which each
  hypervisor calls with its own device: `ptp_hyperv` on Hyper-V,
  `ptp_kvm` on KVM, its module loaded at every start since AlmaLinux 10's
  kernel builds it as one. The Hyper-V way's own udev rule is deleted:
  systemd 257's rules link both clocks (`50-udev-default.rules`).
- **Windows under KVM, no driver of anyone's.** A Windows guest keeps the
  SATA disk and e1000e adapter its installer knows, and is given what KVM
  gives of Hyper-V's own interface and Hyper-V's clock, as `virt-install`'s
  osinfo gives Windows Server 2025 and Windows 11. An image's `tpm`, which
  the Hyper-V template reads, decides on libvirt too: `true` gives swtpm's
  TPM 2.0, refused where the host has no `swtpm`, and left out, none, where
  libvirt gave one wherever the host had `swtpm`.
- **What waits on the owner.** From a Linux host the Windows machines are
  not made yet, by either technology: their Administrator secret is read on
  Windows alone (`MachineSecret.ps1`), and PowerShell on Linux has no WinRM
  client, which msdsc reaches a Windows machine by where it is not on
  Hyper-V. Ansible reaches Windows over WinRM, and writes no domain
  controller and no far end. How a Linux host holds the secret and reaches
  the Windows machines is the owner's to choose.

## Amendment, 2026-11-23: containers, a sixth way to run the node plan

**Provenance.** The owner, 2026-11-23: *One plan, five ways is missing
Container. So it should be six ways*; of what containers Hyper-V runs,
*Sort out what we can use*, basic tests and demos staying processes on one
computer (ADR-0028, amendment 2026-11-23); *The end user can place the
Containers node on any Node or VM cluster as they wish*; and, of the image,
*Still up to the end user. Local processes, VM machines or containers.
Containers, wherever they live*. Not built.

**Decided by the owner:** how a node runs is the end user's: a local
process, a virtual machine or a container, and a container wherever
containers live, on any machine or VM cluster; so is the image it runs.
Xmip prescribes no layout of its containers. An image per node, drafted by
the assistant, was struck by him the same day.

Drafted by the assistant the same day from what each runtime was that day,
for the owner to strike, what Xmip's containers can run under:

- **On a Windows host**, Linux nodes run in WSL containers, `wslc`, Windows'
  own since its general availability on 2026-09-29, no third party's engine;
  `wslc` has no Compose yet. Windows nodes run in Windows Server Core
  containers on containerd, which Microsoft's script installs with nerdctl:
  process isolation where the host's Windows build is the image's, as on a
  Windows Server host of that build; Hyper-V isolation where it is not, as
  on a Windows 11 host, whose default it is, and where a node needs a
  kernel of its own (the owner, 2026-11-25, of the isolation each host
  takes: *Go as you suggest*).
- **On a Linux host**, Podman, from the system's own repositories;
  `podman kube play` runs the Kubernetes manifest a site's Kubernetes runs,
  so one manifest serves both.
- **At a site**, its Kubernetes; a Windows node there runs on a Windows
  Server worker in process isolation, since not every orchestrator runs
  Hyper-V isolation.
- **Not used:** Docker Desktop, a paid subscription for an organization of
  more than 250 people or more than US$10 million a year, and a third party
  where Windows and the systems have their own.
- **The domain controller stays a machine:** Active Directory runs in no
  container.

## Amendment, 2026-11-24: a Windows ISO is booted with Enter, pressed by one script

**Provenance.** The owner, 2026-11-24, of the review's findings on the
test tooling and the rename: *Do as you propose*. Enter came the day
before, landed without a record (commit 80623b9).

- **Enter, never Space.** Where the amendments above say Space is pressed
  at a Windows ISO's prompt, under Hyper-V and libvirt alike, it is Enter:
  a press that comes after the prompt reaches the Windows Boot Manager and
  stops its countdown, and Space then left a machine waiting at its menu
  for three hours (2026-11-23); Enter chooses Windows Setup there. libvirt
  sends `KEY_ENTER` (`LibvirtInstallation.ps1`).
- **The Hyper-V press is written once.** `deploy/dsc/machine/HyperVBootKey.ps1`
  presses Enter in the VM's console forty times, half a second apart:
  Microsoft DSC's Xmip.HyperV resources dot-source it, and Ansible's
  `xmip_machine` role reads it on the controller and hands it to the host
  whole as `win_powershell`'s script, so it asks for no PowerShell 7 there.
  Of the three rules *What is still written twice, and why* lists, the
  host's address on the switch and the network's NAT and the TPM's key
  protector are still Ansible's own copies, left for once the Hyper-V
  template has run.

Proved by `test/DeployEnvironment.Test.ps1` (one file presses the key, and
both technologies run it) and `test/MsdscHyperV.Test.ps1` (forty presses of
Enter, twenty seconds).

## Amendment, 2026-11-24: four ways to run the node plan in the material; every hypervisor and operating system stays a target of its own

**Provenance.** The owner, 2026-11-24, of the overview's slide *One plan,
six ways to run it*: *Six ways to run it, it does not add up*, the ways
being *Local processes, Containers, VMs and Physical Machines*, each with
its place, Xmip advising and the end user choosing. Asked whether an
operating system is a choice inside each way rather than a way of its own:
*Yes, for presentation and video. Technically, coding: no. It has to be
there.* The wording is the assistant's, the same day, for the owner to
strike.

- **The material presents four ways to run the node plan:** local
  processes, containers, virtual machines and physical machines. Hyper-V,
  KVM with libvirt and VMware are the virtual machines' hypervisors, never
  ways of their own. Each way has its own safety and security trade-offs;
  Xmip advises, and the end user chooses, as how a node runs is theirs
  (the amendment of 2026-11-23). The overview deck, its video and the
  Reference Environment deck say so.
- **Technically nothing merges.** Each hypervisor — Hyper-V, KVM with
  libvirt, VMware — and each operating system — Windows, Linux, macOS —
  stays a target of its own, with its own templates, builds and tests, as
  the amendments above and `deploy/dsc` keep them.
- This supersedes the count in the amendment of 2026-11-23, *containers, a
  sixth way to run the node plan*; its decisions on containers stand.

## Amendment, 2026-11-24: the service links every transport a node in another process reaches

**Provenance.** The owner, 2026-11-24, comparing Xmip with its
competitors, asked what turns more of its checkboxes green, then: *go
through each item and sort it or ask me*. Sorted: the node links the
transports that are written and tested. The criterion and the TLS line
below are the drafting's, and the owner's to strike.

**A transport is linked where a node reaches its far end.** All 86
transports are written and pass their own tests; aws and azure are what
their vendors' transports speak, not transports. One is linked into
`xmip-service` the way every technology is (the amendments of 2026-10-01
and 2026-10-19), a `transport-<technology>` feature of the root crate in
`.src/service/built.rs`'s one list, where a node in a process of its own
sends to the far end its crate stands (ADR-0051) and the far end takes
what it sent whole: the root's service test `linked.rs` drops one file
into one node, which sends it over every linked transport at once, and a
POP3 Location, which only collects, collects a maildrop's mail. 52 of the
88 are linked, 46 of them on this day. Those that are not, and why, are
`architecture.toml`'s `linked-transports`: ten cloud transports whose far
end checks a key, a signature or a token no Location can give them; five
whose far end or Send Location cannot take a node's one send; and nineteen
whose far end lives in one process alone, behind a device no node reaches
here. Three were mended to be linked, each with the test that failed
before: an SMTP Send Location names its recipient, `to`, and sends to it
where it sent to its relay's address; WebSocket's and SNMP's send to their
whole address, which their sends read their scheme from.

**TLS stays off for HTTP.** The http crate leaves HTTPS off by default, so
an edge device carries no TLS stack it never opens, and the service links
http without it; as2, as4, peppol, msmq and webdav ride on it and are
linked the same way, since turning one's `tls` on turns HTTPS on for all of
them. Their secure schemes are refused until a site can choose TLS for
HTTP.

## Amendment, 2026-11-24: the domain controller is the network's way out

**Provenance.** The owner, 2026-11-24, of how the machines of a Hyper-V
test environment reach the internet: *the VM DSC can be a gateway to
internet for those machines that needs it*, and *A good choice would be the
DC*; told that a domain controller on two networks is a known cause of DNS
and Active Directory trouble (KB 272294, and community advice to route on a
member server instead): *The DC would be behind my firewall*. How the
templates carry it was decided by the assistant while building it, the same
day, for the owner to strike. Written and held by its tests; not yet run on
a machine.

- **One way out, named by the file.** `[network] gateway_machine` names a
  Windows machine of the environment, XMIP-DC01 in both examples, and
  `[network] uplink` the switch or bridge its second adapter is on: on
  Hyper-V an external switch onto one of the host's adapters, on libvirt a
  bridge of the host's, its name written in the owner's own copy, never in
  a tracked file. Each machine whose `internet` says so is given the
  gateway machine's address as its gateway in place of the host's, every
  other none, as the first amendment of 2026-11-22 had it; the gateway
  machine is given none on the network, its way out the uplink's, addressed
  by the owner's network. Refused before anything is made: a name that is
  no Windows machine of the environment, no uplink, and the host's `nat`
  beside it, since a network has one way out. Where no `gateway_machine`
  is named the host is the way out through its own NAT, as before: that
  option stays.
- **The uplink is the owner's to make.** It takes a host adapter, so the
  templates find it and never make, change or remove it:
  `deploy/dsc/machine/HyperVUplink.ps1`, which `Xmip.HyperV/Network`
  dot-sources and Ansible's `xmip_machine` hands to the host whole, refuses
  one that is not one external switch, naming the command that makes it.
  The gateway machine's second adapter, `Uplink` on Hyper-V and a bridge
  interface on libvirt, has a static MAC, its first adapter's with the
  first octet 02, a locally administered address, and is never booted
  from; an `Uplink` on any other machine is refused, never removed, as an
  adapter never is (the first amendment of 2026-11-11). On libvirt the
  network forwards with NAT only where `nat` says and is isolated
  otherwise, where it always forwarded.
- **The uplink kept out of the domain**, each by Microsoft's own setting,
  in one script both technologies run on the machine,
  `deploy/dsc/machine/WindowsGateway.ps1`: Microsoft DSC sends it whole into
  the machine's session from the new `Xmip.Environment/Gateway`
  (`gateway.dsc.yaml`, applied after the domain's controller and before the
  names), and Ansible's new role `xmip_gateway`, played after the machines
  and before the names, hands it whole to `win_powershell`. The uplink
  registers nothing in DNS, and both adapters ask the machine's own DNS
  server at the network's address, the one it listens on, where promoting
  it left them asking the loopback; it has no
  NetBIOS over TCP/IP; it is a Public network, and one inbound rule on its
  interface blocks everything arriving on it whatever its profile — a rule
  rather than the Public profile's setting, since Windows Server 2025
  domain controllers have been reported to give their own network the
  Public profile after a restart. Where the machine runs the DNS Server
  service, it listens on the network's address alone, and every record of
  the machine's name, of its zone's own name and of `gc` holding an
  outside address is removed, the steps of Microsoft's *Avoid registering
  unwanted NICs in DNS on a multihomed domain controller* (2026-02-12). A
  machine without its second adapter is refused: the adapter is the
  hypervisor's to give.
- **NAT is Routing and Remote Access's.** Its Routing role service,
  `Install-RemoteAccess -VpnType RoutingOnly`, which Microsoft documents as
  a NAT router a Hyper-V virtual machine may run, with `netsh routing ip
  nat` translating the uplink in full and the network's adapter private,
  read back from netsh's own dump; no PowerShell command covers that NAT.
  WinNAT, `New-NetNat`, the host's own NAT, is not used on the machine:
  Microsoft documents it for a host's internal switch, its virtual machines
  and containers, one per host. `deploy/dsc/README.md`, *The way out*,
  cites each.
- **Not yet known**, until the first Hyper-V run: whether Netlogon's hourly
  registration puts the uplink's address back into DNS (its setting,
  `DnsAvoidRegisterRecords`, is not taken; each later run finds such a
  record and removes it); whether `netsh routing ip nat` and its dump are
  on Windows Server 2025 what the Windows Server 2008 R2 reference says;
  and whether the replies RRAS translates pass the inbound rule. From a
  Linux host the Windows machines are not made yet (the third amendment of
  2026-11-22), so there the host's NAT stays the way out until they are.

Proved by `test/DeployGateway.Test.ps1` (the file's reading and refusals,
the step's place, the inventory, and the script with every Windows command
a stub over a machine held in memory), `test/MsdscHyperV.Test.ps1` (the
uplink found and never made, the gateway machine's two adapters) and
`test/MsdscLibvirt.Test.ps1` (the isolated network, the bridge interface).

## Amendment, 2026-11-25: an environment is its cluster file's `[environment]` table, the host's facts are defaults, and its kind follows the host

**Provenance.** The owner, 2026-11-25, of running the System Tests, the
Systems Tests and the demo on virtual machines (ADR-0028, amendment of this
date): *I'd like it to be a switch to minimize the number of files and
duplication of configuration*; *I still don't get why there is a need for
two files?*; *Yes* to one file, the cluster file, and one switch; and of
each machine, *When you set up virtual machines, there is a description
field. I want it to state Role and OS type*. The coordinator settled
the rest the same day, for the owner to strike: the System Tests' tracked
file names no network, a free private /24 picked on the host where
`network` is left out; on a Linux host the Windows machines are refused in
words, a smaller plan being a smaller cluster file; on Windows the WSL
command named for Ansible carries the Windows host's kind and
`-WindowsHost`; and the Hyper-V environment is made again from nothing, the
owner having had every machine deleted that day. The keys, the defaults and
the refusals below are the coordinator's drafting. Written; not yet run on
a machine.

- **One file.** Where a cluster runs on virtual machines is its cluster
  file's `[environment]` table, and no other file says it:
  `deploy/dsc/hyperv.example.toml`, `deploy/dsc/libvirt.example.toml` and
  the System Tests' `configuration/external.xmip` are deleted, and the
  System Tests' `configuration/Xmip-reference-environment.xmip` carries the table, the
  owner's node plan of 2026-11-22 in it. No node is given the table: slicing leaves
  it out (ADR-0031, the second amendment of this date), and a run as local
  processes reads only its far ends from it (ADR-0028, amendment of this
  date). It names no cluster, no machine's address and no absolute path, as
  the file never did (ADR-0028, amendment 2026-10-21).
- **What the table says** (`deploy/dsc/README.md`, *The environment
  table*):
  - `network`, optional, `"<prefix>/<length>"`. Left out, the command picks
    a free private /24 on the host and keeps it in the environment's state.
    The host takes the range's first address, then the machines in order:
    the `[environment.machines]` entries that run no node and no far end, in
    the file's order, then the far ends, senders then receivers, then the
    nodes, in the file's order.
  - `domain`, the DNS domain, `xmip.test` where left out.
  - `domain_controller`, optional: a Windows machine of the environment,
    the first controller of a new forest and the network's DNS server.
    Without one the host answers names.
  - `gateway`, optional: a Windows machine that is the network's way out,
    NAT by Routing and Remote Access out of a second adapter on the host's
    uplink, as the amendment of 2026-11-24 has it. Left out, the host's own
    NAT is the way out where any node is online, and the network is
    isolated otherwise.
  - `[environment.machine]`, every virtual machine's defaults: `os`, an
    image's name, `cpu`, `memory_gb`, `dynamic_memory = { minimum_gb,
    maximum_gb }` and `disk_gb`. Built in: 2 processors, 2 GiB and 64 GiB;
    no `os`.
  - `[environment.machines.<name>]`, the same keys. For a node or a far end
    of that name, its machine where it differs; any other name is a machine
    of its own that runs no node and no far end — the domain controller, the
    file storage, the people's machines — and needs an `os`, and may say a
    `purpose`.
  - `[environment.far_ends]`, `senders = [...]` and `receivers = [...]`,
    what `external.xmip` named.
  - `[environment.images.<os>]`: `name`, the system in plain words,
    `sha256`, `family` (`Windows` or `Linux`), `edition`,
    `secureBootTemplate`, `tpm` and `environment`, the kickstart's group. No
    path: the image is found on the host by its SHA-256.
- **Derived, never written.** A machine is `XMIP-<name>`: XMIP-RX1 for the
  node RX1, XMIP-DC01 for the entry DC01. The network, the switch and the
  pool are `Xmip-<cluster>`. A node's machine reaches past the network where
  the node declares the Node capability `online` (ADR-0056, amendment
  2026-11-24); a far end's machine and a machine of its own do not.
- **Each machine says what it is.** Its description field, Hyper-V's Notes
  and libvirt's `<description>`, states its role and its operating system
  in one line: the role from what the cluster file declares — a node's
  roles, a far end's side, the domain controller or the gateway, and for
  any other machine of its own its `purpose` — and the system from its
  image's `name`: *Receiving node RX1 · AlmaLinux 10*, *Sender far end
  EXTTX1 · AlmaLinux 10*, *Domain controller and gateway DC01 ·* and its
  image's name.
- **The command.** `Deploy-XmipEnvironment -Path <cluster file> -Cluster
  <name>`, both required. `-Technology msdsc|ansible`, msdsc where left
  out, held by the state as before (the second amendment of 2026-11-11);
  `-Hypervisor hyperv|libvirt`, the host's kind where left out: Hyper-V on
  Windows, KVM through libvirt on Linux, refused in words on macOS.
- **The host's facts are defaults.** What the command cannot choose is
  given once, as a parameter, and then kept in the state:
  - `-ImageFolder`: the installation images, found there by their SHA-256,
    and the tool archives, found there by name; left out, the account's
    Xmip folder's `images`,
    `%LOCALAPPDATA%\Xmip\images` on Windows and `xmip/images` under
    `$XDG_STATE_HOME` or `~/.local/state` elsewhere.
  - `-DiskFolder`: Hyper-V's virtual hard disk path, or
    `/var/lib/libvirt/images`, with `Xmip-<cluster>` in it.
  - `-Uplink`, where `gateway` is named: the host's one external switch on
    Hyper-V, or its one bridge on Linux; refused where there is none or
    several, naming the switches found.
  - `-WindowsHost`: Ansible's view of the Windows host, for Ansible on
    Hyper-V.
  - `-Operator`: who else operates the nodes, each a certificate's subject,
    `CN=<person>`, or an account, listed among every node's `[operate]
    operators` beside this account's person (below).
- **Taken with no parameter:**
  - the packages, the module libraries, the far ends' programs and the
    slicer, from the build under `.local-work/package/<version>/`, refused
    naming `Build-XmipService` where absent;
  - the environment's authority, which signs every slice and issues every
    certificate, kept in the private state's `authority` folder and made
    there where none is, with `operator.xmip` beside it: the slice of the
    node the cluster file declares `[provision.operator]` for, signed by
    that authority, by which the operator's request is signed
    (`Write-XmipOperatorSlice`, the one the System Tests' authority is
    written with too);
  - every certificate, made in the private state where none is
    (`Initialize-XmipDeployIdentity`): each node's and far end's in
    `identity/<name>`, issued by `New-XmipCertificate -Node`; and the
    operator's in `operator/`, `operator.pem`, `operator.key` and
    `anchors.pem`, for this account's person, `CN=<account name>`, whom
    every node lists among its `[operate] operators` with each `-Operator`
    given, and with which `Start-XmipTest -VirtualMachine` asks the nodes;
  - the Windows machines' Administrator secret, generated once into the
    state, `Export-Clixml`, encrypted by Windows' Data Protection API;
  - the AlmaLinux machines' account, `xmip-admin`;
  - the tools Microsoft DSC brings to each machine, their archives' names
    and SHA-256 in `prerequisite.toml`, `[prerequisite.powershell.archive]`
    and `[prerequisite.dsc.archive]`, found by name under `-ImageFolder`.
- **Refused in words:** on Windows, a run not elevated, naming an elevated
  Xmip PowerShell Console, which it never starts; on a Linux host, every
  Windows machine, naming the third amendment of 2026-11-22, by which
  Windows machines are not made from a Linux host yet — a smaller plan is a
  smaller cluster file; and Ansible on Windows, naming the WSL command,
  which carries `-Hypervisor hyperv` and `-WindowsHost`.
- **What a run leaves.** The run folder is `.local-work/deploy/<cluster>`.
  A run that applies writes `deployed.toml` into the private state: the
  cluster file's path and SHA-256, the technology, the hypervisor, and each
  node's and far end's machine and address, which `Start-XmipTest
  -VirtualMachine` reads, for the System Tests and the Systems Tests alike
  (ADR-0028, amendment of this date). Its third switch, `-Container`, is
  refused until the tests run in containers, one of the four ways of the
  amendment of 2026-11-24, which the tests do not take yet.
- **Made again from nothing.** The Hyper-V environment the earlier
  amendments made is not carried over: its machines were deleted on
  2026-11-25 (`deploy/dsc/README.md`, *Starting again from nothing*).

This supersedes, without editing them:

- the amendment of 2026-10-21, *the environment templates, one set per
  technology*, where the mapping of nodes onto machines is the templates'
  parameters, never the cluster's file;
- the second amendment of 2026-11-11, *an environment in one command, in
  either technology*, its *One environment file, the technology a value in
  it*: the technology is a parameter, and the file is the cluster's;
- the bullets *The example is the plan* of the first and third amendments
  of 2026-11-22, and the first's *A way out, per machine*: a machine's
  `internet` is its node's Node capability `online`;
- of the second amendment of 2026-11-22, a machine's `external` and the
  environment file's `[far_ends.<family>]`, `far_end` and `listen`: a far
  end's machine is its name's in `[environment.far_ends]`, its program the
  build's, and every Send Port is bound to the receiver of its turn and
  every Receive Location listens on its node, as the plan's environment had
  it;
- of the amendment of 2026-11-24, *the domain controller is the network's
  way out*, the keys `[network] gateway_machine`, `uplink`, `nat` and
  `internet`: the way out is `gateway`, `-Uplink` and the Node capability
  `online`. What that amendment found, and what it says is not yet known,
  stand.

## Amendment, 2026-11-25: nine transports more, each proven through a node

**Provenance.** The owner, 2026-11-25, asked what the 36 transports not
linked need, then: *I can do a physical TX device via USB, but just do your
best for now*. The eighteen that need nothing bought were taken: five a far
end in a process of its own reaches on any computer, thirteen through
Linux's virtual devices. How each far end is stood is the drafting's, and
the owner's to strike.

**61 of the 88 are linked**, by the criterion of the amendment of
2026-11-24: a node in a process of its own sends to the far end and the far
end takes what it sent whole (`.src/test/service/linked.rs`).

- **bacnet, coap, dhcp, mdns and ssdp, proven on every platform** (open
  problem 170). CoAP's and BACnet/IP's own far ends take a node's one send:
  the first POST or NPDU shorter than a message carries closes the Stream,
  as a last block does, where only an empty one closed it, which no node
  sends. CoAP's, DHCP's and mDNS's Send Locations send to their whole
  address, which their sends read their scheme from, as WebSocket's and
  SNMP's do since 2026-11-24. mDNS, SSDP and DHCP announce or answer in one
  datagram, and their crates' far ends ask the sender back for a Stream in
  chunks or play the other side, so the far end in the service test is what
  hears that datagram — a browser, a control point, a client — read by the
  technology's own reading. Each is sent a document its protocol carries
  whole, TXT strings, a notification, an offer's options, dropped as a file
  of its own, which its Subscription takes by `file.name`.
- **serial, hart, io-link and m-bus, linked on every platform and proven on
  Linux and macOS** through a pseudo-terminal: the node opens its line's
  end by path as it opens a device's port, and the far end at the device's
  end is serial's `terminal::Terminal`, taking the one frame a serial Send
  Location writes, or answering each frame a protocol's master writes as
  the protocol's own device answers it on the SDK's bus in process, until
  it holds the Stream. Windows has no pseudo-terminal, so there the four
  are linked and not proven. A HART Location takes a serial port as its
  line at 1200 baud, where every address but `loopback` was refused; an
  IO-Link master message says its length in its first two bytes, and a
  device says when it is between two transfers; a build linking io-link
  brings serial's port, which io-link's own dependency leaves out.
- **can-bus, canopen, iso-tp, j1939, obd-ii and uds are not linked.** Each
  reaches a CAN interface of the kernel's (`socketcan`), and only an
  administrator makes one, a virtual one too; the commands were handed to
  the owner, and the far ends are written once an interface stands.
- **ethernet, ethercat and profinet are not linked.** Their one link is the
  in-process one: the kernel's raw socket (`AF_PACKET`) asks a binding the
  estate does not write without `unsafe` (ADR-0050) and a capability,
  `CAP_NET_RAW`, only an administrator grants. Which way, the owner's.
- **Receiving stays unproven, for these as for the 52.** A node built with
  the `ip` identifier claims a datagram's peer, and no authenticator the
  service links verifies `ip`, so a Stream over a network not mutually
  authenticated by TLS is refused at authentication (ADR-0019).

## Amendment, 2026-11-25: the kernel's links, made in a namespace of the test's own

**Provenance.** The amendment above left CAN and Ethernet unlinked for want
of an administrator to make their interfaces and a binding for the raw
socket. The same day it was found that a user and network namespace grants
both with no administrator: `unshare --user --map-root-user --net` makes
the account's user root of a network namespace of its own, holding
`CAP_NET_ADMIN` and `CAP_NET_RAW` over it alone, where a virtual CAN
interface and a veth pair are made. How the test and the link are built is
the drafting's, and the owner's to strike.

**70 of the 88 are linked**, the nine below on Linux alone.

- **can-bus, canopen, iso-tp, j1939, obd-ii and uds reach the kernel's CAN
  interface** through can-bus's `socketcan`, which each one's feature of
  the root crate brings (open problem 198).
- **ethernet, ethercat and profinet reach the kernel's raw socket**,
  ethernet's new `packet` link: an `AF_PACKET` socket bound to the
  interface a Location names, through `nix`'s safe calls, its address the
  interface's own `sockaddr_ll` as the kernel lists it (`getifaddrs`), so
  the estate writes no `unsafe` and adds no dependency (open problem 199).
  Of the three crates in the lock that bind a socket, `rustix` reaches no
  link-layer address but through an `unsafe` constructor, and `socket2`
  none but through one; `nix` lists the interface's own. It needs
  `CAP_NET_RAW`: a box's grant to a node, or a namespace's.
- **Linked on Linux alone** (`built.rs`, `kernel_transports`): elsewhere a
  CAN Location would open a bus inside the node alone, and a raw socket is
  Linux's in this build.
- **Proven as the rest are, by a node's one send** (`namespaced.rs`): the
  service test runs itself again in such a namespace, brings its loopback
  interface up, turns IPv6 off so no interface speaks on its own, makes a
  virtual CAN interface for each CAN technology — ISO-TP, UDS and OBD-II
  answer under the same identifiers — and a veth pair for each Ethernet one,
  and drives one node and the far ends there, each the end its own crate
  stands in process, on the kernel's link: an ECU collecting, a receiver
  clearing a transfer, a tester polling, a `CANopen` node and an `EtherCAT`
  ring answering until their object holds the Stream, a PROFINET device
  taking its cycles. Where a machine grants no such namespace, the test
  says so and runs nothing.

## Amendment, 2026-11-25: the tests' containers are Linux, WSL containers on Windows and Podman on Linux

**Provenance.** Open problem 188: the tests and the demo run in containers,
*WSL containers or containerd on Windows, Podman on Linux, one container per
node and far end, made from the same cluster file*, recorded with
`Start-XmipTest -Container` (the owner, 2026-11-25: *We missed a switch -As
Container*, *Aliased as C*), the containers being where the amendment of
2026-11-23 has them (*Containers, wherever they live*). Building it, the
workers settled the rest the same day, for the owner to strike; ADR-0028's
amendment of this date says how a run makes and reads them.

- **Linux containers wherever they live.** On a Windows host, WSL
  containers, `wslc`, Windows' own and no administrator's to run; on a
  Linux host, Podman, the system's own, rootless; Docker Desktop is not
  used, as the amendment of 2026-11-23 has it. The two take the same verbs
  and switches, so the module runs either through one function
  (`Invoke-XmipContainerTool`) and knows which by the host alone
  (`Get-XmipContainerTool`), refusing in words, naming what installs it,
  where it is absent.
- **Every node and far end of a run in containers is Linux.** A machine's
  `os` in the cluster file is its virtual machine's; a run in containers
  gives every node and far end the Linux build, as a run as local
  processes runs every node on this computer's own system. The Windows
  Server Core containers on containerd that the amendment of 2026-11-23
  gives Windows nodes stand, with the isolation each host takes, process
  isolation where the host's Windows build is the image's and Hyper-V
  isolation where it is not, as on a Windows 11 host (the owner,
  2026-11-25: *Go as you suggest*); they are not built: they take
  containerd and the Windows Containers feature, which an administrator
  installs, every program built for Windows given to them, and a network
  where a Linux and a Windows container find each other by name. Recorded
  as an open problem.
- **No image of Xmip's yet.** Clause 4's image per release is not built.
  The cluster file names the image every container runs, `[environment.container]
  image`, the System Tests' AlmaLinux's own minimal image from its
  publisher's registry, as their Linux machines install AlmaLinux from its
  publisher's ISO; the container tool pulls it where it has none. The
  programs are not in it: one copy of the Linux build is mounted read-only
  into every container, and each container's configuration is copied in,
  since a copy from Windows keeps no mode and a program copied so would not
  run.
- **A container is given what a Linux machine is given**: the Linux build
  under `.local-work/package/<version>`, the `.rpm`'s staged
  `xmip-service`, the far ends' program and the module libraries built for
  Linux. Where that build keeps each is said once, `Get-XmipBuiltProgram`,
  which `Deploy-XmipEnvironment`'s `Add-XmipDeployBuild` asks too, where it
  spelled the layout itself.
- **What each was, 2026-11-25.** WSL 3.0.5 (2026-11-03) is the latest
  release, WSL containers generally available since WSL 3.0.1 (2026-09-29;
  [Microsoft](https://blogs.windows.com/windowsdeveloper/2026/09/29/wsl-containers-now-generally-available/),
  [the WSL releases](https://github.com/microsoft/WSL/releases)), without
  Compose yet; its `wslc` 5.0.1 mounts a Windows folder into a container,
  finds a container on its network by its alias, publishes a port on
  127.0.0.1, refuses one in a range Windows reserves, and answers the
  inspection of a network that is not there with success and an empty
  list, so whether one is there is read from the answer. Podman 6.2 is the
  latest release
  ([its releases](https://github.com/podman-container-tools/podman/releases),
  [endoflife.date](https://endoflife.date/podman)); a system based on
  Ubuntu 24.04 carries 4.9.3 in its own repositories, below the floor, and
  installing any of it takes an administrator.

This supersedes, without editing it, the first amendment of this date's
*Its third switch, `-Container`, is refused until the tests run in
containers*; the amendment of 2026-11-23 stands whole.

Proved by `test/SystemTestContainer.Test.ps1` and `test/XmipTest.Test.ps1`,
and by a System Tests roll in WSL containers (ADR-0028, amendment of this
date).

## Amendment, 2026-11-25: the cloud transports present their secret and are linked

**Provenance.** The owner, 2026-11-25: *Go ahead with bigger things*. The
amendment of 2026-11-24 left ten transports unlinked because their far end
checks a key, a signature or a token no Location gave them, while the way a
Location names its proof was decided and built for others: `secret =
"<name>"`, kept sealed in the Administration Database's `secret` table and
read as the Location connects (ADR-0019, amendments 2026-10-29 and
2026-11-10). How each presents it is the drafting's, and the owner's to
strike.

**80 of the 88 are linked.** Not linked: aws and azure, what their vendors'
transports speak and no transports; and the six radios, bluetooth, lorawan,
thread, wireless-hart, wireless-m-bus and zigbee, whose far end lives
inside one process and whose radio no node reaches here.

- **Each presents the secret its Location names**, through one function of
  the transport capability, `transport::secured::presented`: the text the
  secret holds, read now, or what the transport was built with where the
  Location names none. `logged_in`, the way a technology with a user and a
  password presents one, calls it, so the rule is written once. aws-kinesis,
  aws-s3, aws-sns and aws-sqs sign with it as the secret access key
  (Signature Version 4); azure-blob as the account key (Shared Key);
  azure-event-grid sends it as the topic key; azure-event-hubs and
  azure-service-bus make a Shared Access Signature with it as the policy's
  key; google-cloud-storage and google-pub-sub send it as the bearer token.
- **A `password` secret**: each is one UTF-8 text the far end checks, so no
  kind is added (ADR-0019, amendment 2026-10-29, has `password`, `key` and
  `certificate`).
- **Read at each request**, as HTTP reads its Basic password: Signature
  Version 4, Shared Key and a Shared Access Signature sign every request, so
  a secret set or replaced reaches the next request without a restart. One
  point read of Xmip Storage per request of these ten; nothing else on the
  message path reads one.
- **Who signs is a setting, where the protocol names one**, as IMAP's `user`
  and MQTT's `username` are: the four AWS technologies' `access_key_id`,
  declared once in the aws crate (`aws::access_key`); Event Hubs' and
  Service Bus' `key_name`, the shared access policy; Blob's `account`, which
  it already required. Event Grid's topic key and Google's token name no
  one. A Location naming a secret and no `access_key_id` or `key_name` is
  refused as the node starts, as MQTT refuses a password with no user name,
  by the one refusal of a secret named without whose it is,
  `transport::secured::without_holder` (ADR-0019, amendment 2026-11-25).
- **A Location that receives by being connected to presents nothing**: an
  SNS or Event Grid Receive Location is the webhook a subscription
  delivers to, as an HTTP Receive Location is.
- **Linked without TLS**, as HTTP and what rides on it are (the amendment of
  2026-11-24): the ten ride on HTTP, so an `https://` endpoint, which every
  vendor's own service is, is refused until a site can choose TLS for HTTP.
  Until then they reach an `http://` endpoint, an emulator's or a stand-in's.
- **Proven as the rest are** (`.src/test/service/linked.rs`,
  `far_ends/secured.rs`): each far end is its crate's own loopback, stood
  checking a value the test draws from the operating system's random source;
  the node's Send Port names a secret of its own name, and the test sets it
  through the node's local endpoint as an operator sets one
  (`Set-XmipSecret`), before it drops the file, so the node reads it from
  its Administration Database as it sends. FTP's far end, which admits the
  user its address names with the password the Location's secret holds, is
  proven the same way; until this amendment no test set it a secret, and
  FTP was carried through no node.

Not built, and open: a Send Location of an object store — aws-s3,
azure-blob, google-cloud-storage — names its object by the target a node
sends to, which is the Location's own address, so a node puts the object
under its endpoint's URL and not the Message's file name, as a folder or an
SFTP server would (`transport::file_name`; found 2026-11-24 with open
problem 169); and a bearer token Google issues expires within the hour, so
a Location's token is set again before then, and exchanging a service
account's key for one is not built.

## Amendment, 2026-11-27: wireless M-Bus reaches a receiver stick on a serial port, LoRaWAN a node the network server behind its gateways, and both are linked

**Provenance.** The owner, 2026-11-27, on the transports that need
hardware: *let's do your best for now. I'm not going to buy all that
hardware*. Wireless M-Bus and LoRaWAN each had an in-process radio alone,
so no node in a process of its own reached their far ends and neither was
linked (the amendment of 2026-11-25). Wireless M-Bus's air is now a USB
receiver stick on a serial port; LoRaWAN's far end now leaves the node's
process, a gateway's packet forwarder over UDP, which a node is the
network server behind (ADR-0051, amendment 2026-11-27). Which stick, its
protocol, the boundaries and linking both are the assistant's choice, for
the owner to strike or keep.

**82 of the 88 are linked**, wireless-m-bus and lorawan with the 80, by the
criterion of the amendment of 2026-11-24. Not linked: aws and azure, what
their vendors' transports speak and no transports; and the four radios,
bluetooth, thread, wireless-hart and zigbee, whose far end lives inside one
process and whose radio no node reaches here.

Wireless M-Bus:

- **The air is a receiver stick on a serial port.** A wireless M-Bus
  Location's address is the port a USB receiver stick is on, `/dev/ttyUSB0`
  or `COM3`, opened by the serial technology as every serial port is;
  `loopback` stays the radio in process. The transport speaks the stick's
  host protocol through a `Line`, `Receiver`, so all above the air is the
  same for both.
- **The stick is IMST's iU891A-XL or iU893A-XL**, and its protocol the host
  controller interface of IMST's Wireless M-Bus Gateway firmware (IMST,
  *Wireless M-Bus Gateway Firmware — Host Controller Interface Protocol*,
  version 2.4, 2026-06-03, document 4000/40140/0178,
  [wireless-solutions.de](https://wireless-solutions.de/data/assets/uploads/WM_Bus_Gateway_HCI_Protocol_Specification_V2_4.pdf)):
  SLIP frames at 115 200 baud, each a service access point, a message
  identifier, a payload and a CRC-16/IBM-SDLC. Chosen on 2026-11-27 from
  what [wmbusmeters](https://github.com/wmbusmeters/wmbusmeters) drives —
  IMST's iM871A and iU891A, the AMB8465 and AMB3665, the CUL family,
  Radiocraft's RC1180, and an RTL-SDR radio, which the host decodes itself
  with no host protocol: the iM871A, the first of them, is discontinued, and
  IMST's
  [end-of-life notice](https://wireless-solutions.de/data/assets/uploads/iM871A_iM871A_usb_EoL_Notification_2.pdf)
  names these two its successors; their protocol is one public document,
  current and complete, the bytes of a ping among it, which the tests hold;
  the AMB8465's manual leaves its command set to a second document, which
  refused an automated download.
- **Written once, in the lowest layer.** SLIP (RFC 1055) is a serial line's
  framing, so it is the serial technology's, `Framing::Slip`, beside its
  delimiter, fixed length and measure; CRC-16/IBM-SDLC is codec's, beside
  EN 13757-4's own. The frame and its block CRCs stay wireless-m-bus's, and
  the records and the meter m-bus's; a stick hands its host the frame with
  its CRCs stripped and takes it so, `Frame::plain`. The stick's messages
  are wireless-m-bus's `hci.rs`.
- **Set at the first use, then used.** At the first use of a stick's port,
  and again after a use failed, as a stick unplugged and plugged in again forgets
  it, its active configuration is read, its link mode set to the Location's
  `mode`, every heard telegram handed to the host and the address filter
  taken off, the rest as it was, and written back to its memory, not its
  default. A frame goes out in one send request, answered within the
  specification's second; a telegram comes in as the stick's event. Two
  settings are new: `mode`, the meter's, `s`, `t` or `c`, `t` where it is
  left out, and `power`, -1 to +13 dBm, 10 where it is left out.
- **One stick, every Location of a node on it.** The node's Locations
  naming the port share its one port, as serial's do (ADR-0064, amendment
  2026-11-15), and what it heard: each takes its own meter's telegrams, the
  one whose receive reads the port keeps the others' for theirs and tells
  them at once, one receive reading at a time while the rest wait holding
  nothing, so no telegram waits on a Location's timeout. A meter's last 16
  telegrams are kept, one heard before a request to it is let go, and a
  meter no Location listens for is let go.
- **Proven as serial, hart, io-link and m-bus are** (`.src/test/service/linked.rs`,
  `far_ends/terminal.rs`): the node's Send Location opens the line's end of
  a pseudo-terminal pair, and the far end at the device's end answers as
  the crate's `stick::Stick` does, a meter on its air, until the meter holds
  the Stream. Windows has no virtual serial pair without a third-party
  driver, so there the test says SKIPPED, and why, for the five; the System
  Tests' `-Container` way runs Linux containers, where the pair stands. No
  stick was plugged in: the crate's tests drive a Location through the
  stick in process on a port in process on every platform, and on a
  pseudo-terminal pair on Unix.

Not built: the stick's encryption and decryption, sending under its own
address, its scan mode, its firmware update and its reset over USB. The
specification's table of message identifiers gives the send request as
the radio modules' alone, where its own section names the iU891A-XL too;
the crate goes by the section, and a stick that refuses it says so in the
specification's words.

LoRaWAN:

- **lorawan, linked and proven on every platform**
  (`.src/test/service/far_ends/gateway.rs`): the node's Send Port listens
  where its address says, a port of loopback the far end draws, and the
  far end is a device
  behind a gateway pointed there, both the technology's own — its packet
  forwarder and its device, with the frame, the keys and the fragments the
  node's side is written with. The gateway asks for downlinks every tenth
  of a second, so the Send Location, which binds its socket as it first
  sends, is asked at once; the node sends the document down in a
  `PULL_RESP`, the gateway answers `TX_ACK`, and the device opens the frame
  and takes the Stream whole.
- **The session keys are the secret the Send Port names**, a `password`
  secret of 64 hexadecimal digits drawn for the far end from the operating
  system's random source and set on the node through its local endpoint
  before the file is dropped, as the vendors' are (the amendment of
  2026-11-25); its `dev_addr` is a setting.
- **Receiving is proven by the technology's own tests**, a device sending
  up through its gateway to a node's network server on this machine, its
  confirmed frames answered in their first receive window; through a node,
  receiving stays unproven, as for the rest (the amendment of 2026-11-25).

## Amendment, 2026-11-27: Bluetooth reaches a controller through the kernel's L2CAP sockets, and is linked on Linux

**Provenance.** The owner, 2026-11-27, on the transports that need
hardware: *let's do your best for now. I'm not going to buy all that
hardware*. Bluetooth had an in-process radio alone, so no node in a
process of its own reached its far end and it was not linked (the amendment
above). The boundary, the settings, the two controllers it is proven on and
linking it are the assistant's choice, for the owner to strike or keep.

**bluetooth is linked, on Linux alone**, one more than the 82 of the
amendment above: 83 of the 88, by the criterion of the amendment of
2026-11-24. Not linked: aws and azure, what their vendors' transports speak
and no transports; and the three radios thread, wireless-hart and zigbee,
whose far end lives inside one process and whose radio no node reaches
here.

- **The boundary is the kernel's L2CAP socket**, the least privileged one
  Linux has: `AF_BLUETOOTH`, `SOCK_SEQPACKET`, `BTPROTO_L2CAP`, on a dynamic
  PSM, 4097 (0x1001) or above, which a process binds without
  `CAP_NET_BIND_SERVICE`. Each SDU is one RFCOMM frame, handed whole; the
  kernel pages the peer, opens the ACL link and the channel and segments
  it, and RFCOMM above it is Xmip's own, as on the radio in process. The
  HCI user channel, which would hand Xmip the ACL link for its own L2CAP,
  asks for `CAP_NET_ADMIN` and takes the controller from the kernel and
  `bluetoothd`; and the kernel's RFCOMM, which holds PSM 3 on Linux, would
  leave Xmip's unused. So a peer is one speaking Xmip's RFCOMM on the PSM
  the Location names (open problem 229).
- **A Location's address names the device**: the peer a Send Location
  connects to, `bt://70:a8:d3:36:de:ad`, or the controller of this machine
  a Receive Location listens on, `00:00:00:00:00:00` for any; `loopback`
  stays the radio in process. Two settings are new: `psm`, 4097 where it
  is left out, odd with its upper octet even, as a dynamic PSM is; and, on
  the send side, `controller`, the device address of this machine's
  controller to connect from, the kernel's choice where it is left out. A
  device address is read as IEEE 802 writes a hardware address, by
  `net::mac`. A Receive Location's listener is bound as its transport is
  opened (`Configured::listening`), kept by `transport::kept::Kept`, and its
  receive waits on it through `transport::socket::ready`.
- **Written once.** RFCOMM's dialogue and its session run on a `Channel`
  whichever `Link` carries it (`link.rs`, `session.rs`): the kernel's socket
  (`socket.rs`), or Xmip's own L2CAP on an ACL link (`l2cap.rs`), which the
  radio in process and any `Radio` handed in speak. The session held Xmip's
  L2CAP signaling and RFCOMM together until then.
- **One file of unsafe code.** Every call on the socket is rustix's, safe;
  the address it does not write, `struct sockaddr_l2`, handed to `bind` and
  `connect` and read back from `accept`, is `src/system.rs`, which
  `test/Unsafe.Test.ps1` lists (ADR-0050, amendment 2026-09-25).
- **Proven on two virtual controllers** (`.src/test/service/linked.rs`,
  `far_ends/controller.rs`): whoever opens `/dev/vhci` has the kernel make
  a controller and answers its HCI commands, so the crate opens two and is
  both (`controller`, behind `test-support`), a BR/EDR controller with no
  Secure Simple Pairing and no LE, carrying pages and ACL data between
  them; the kernel's stack, `bluetoothd` and every socket on them are the
  real ones. BlueZ's `btvirt` does as much, from its test tools, which the
  Linux test computer did not have. `bluetoothd` powers each controller as
  it comes (`AutoEnable=true`) and keeps a BR/EDR controller answering
  pages only from devices it knows — the test computer's own controller is
  powered and not connectable — so the second is made discoverable through
  it over D-Bus (`busctl`), and the far end listens there; the node's Send
  Location connects from the first. Where `/dev/vhci` is not the user's or
  `bluetoothd` is not on the system bus, the test says SKIPPED and why; off
  Linux it says so too. On the Linux test computer the module is loaded and
  a udev rule gives `/dev/vhci` to the user, so no step of the owner's was
  needed. The crate's own tests carry a Stream of 64 KiB the same way, and
  hold a page no controller answers refused, naming the device.

Not built: a channel at more than the kernel's default security, so no
pairing and no encryption; finding a peer's server channel through SDP;
and more than one Receive Location on one controller and PSM, each binding
its own listener. No real radio and no other RFCOMM stack is driven (open
problem 229), and no controller is reached off Linux (open problem 230).

## Amendment, 2026-11-27: Thread, Zigbee and WirelessHART reach an 802.15.4 interface of Linux's kernel, and are linked there

**Provenance.** The owner, 2026-11-27, on the transports that need
hardware: *let's do your best for now. I'm not going to buy all that
hardware*. Thread, Zigbee and WirelessHART had a radio held in their own
process alone, so no node in a process of its own reached their far ends
(the amendment of 2026-11-25). Each now rides one IEEE 802.15.4 radio, an
interface of Linux's kernel through an `AF_IEEE802154` datagram socket
(ADR-0051, amendment 2026-11-27). Linking them, and how they are proven,
are the assistant's choice, for the owner to strike or keep.

**86 of the 88 are linked**, thread, wireless-hart and zigbee with the 83
of the amendment above, by the criterion of the amendment of 2026-11-24.
Not linked: aws and azure, what their vendors' transports speak and no
transports.

- **On Linux alone**, in `built.rs`'s `kernel_transports()` beside CAN,
  Ethernet and Bluetooth, their crates Linux's dependencies of the root: elsewhere the
  kernel offers no 802.15.4 socket, and a Location there could open only a
  radio inside the node.
- **Proven one at a time, on the machine's own pair of radios**
  (`.src/test/service/aired.rs`, `far_ends/radio.rs`): for each, a node of
  its own whose Send Location opens `wpan0`, its far end its crate's own on
  `wpan1` — a Thread node, a Zigbee node acknowledging, a WirelessHART
  device — and a file dropped in taken whole. Not in `linked.rs`'s one
  node: every socket bound to an interface hears every frame sent to it, so
  three far ends on one interface at once would each read the others'
  frames. Not in a namespace of the test's own: the kernel makes no
  802.15.4 socket outside the first network namespace. Where the machine
  has no such pair, or its kernel makes no 802.15.4 socket, each says
  SKIPPED and why, and on Windows and macOS the test says so once. A
  machine that is to prove them loads `mac802154_hwsim` with two radios,
  gives both one PAN and a short address each, brings them up and keeps
  NetworkManager off them, and loads `ieee802154_socket`.
- **Sending is what the node proves**; Thread's and Zigbee's receive over
  an interface is what their far ends take with, and through a node
  receiving stays unproven, as for the rest (the amendment of 2026-11-25).

## Amendment, 2026-11-28: the cluster's file names the environment

The owner, 2026-11-28: *CT should not exist* (ADR-0028, amendment
2026-11-28). `Deploy-XmipEnvironment -Path <cluster file>` takes no
`-Cluster`: the environment is named for the cluster its file names, its
`[service] cluster_name` or else its short name (`Get-XmipClusterName`,
the runtime's `configure::cluster::cluster_name`), as `Xmip-<cluster>`,
`XMIP-<name>` and `.local-work/deploy/<cluster>`; a file naming no cluster
is refused. *The command* above, `-Path <cluster file> -Cluster <name>`,
reads as `-Path <cluster file>`, and the WSL command a refusal names
carries no `-Cluster` either.
