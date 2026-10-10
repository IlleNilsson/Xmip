# ADR-0015: Packaging and distribution

## Status

Accepted. Implementation follows in separate reviewed changes.

## In brief

- Theme: Operating Xmip
- Subject: Packaging and distribution
- Name: Packaging and distribution
- Order: 2
- Concepts: arm64, embedded, IoT; MSI, winget, deb, rpm, OCI; target, domain, site

Packaging covers the node; Modules are out of scope. MSI via WiX, published
through winget, on Windows. `.deb` and `.rpm` on Linux. An OCI image every
release. A portable archive for people who want no installer at all. x86-64 and
arm64 on both — **arm64 is not optional**, because the edge target, an IoT
gateway or a Raspberry Pi, requires it. What a package is built with is its
site's: a target, node roles and domains, turned into a build by
`Build-XmipService` (amendment 2026-10-01).

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
objected to; the domains were accepted as the axis to try. The names
`hosted` and `managed-service`, the domains beyond healthcare, industrial,
b2b and managed-service, the role compositions and the vetoes are the
drafting's, and the owner's to strike.

**What a package is built with is a site's.** A site,
`deploy/site/<name>.toml`, picks three things, each a profile under
`deploy/profile`, each a TOML file named by its word (ADR-0031):

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
  stores are a target's business and no domain's. A cluster and a hybrid
  are arrangements of nodes, each on a target, and not targets
  (deployment-model.md section 1).
- **Node roles**, what the node is for (`deploy/profile/role`), one file
  per `NodeRole` word (ADR-0056): `receiving`, `processing` and `sending`
  each pull the capability features their stage needs; `executing` is their
  sum and adds nothing (`roles = ["receiving", "processing", "sending"]`);
  `operational` brings cluster, event, persist, retain, archive and
  resilience; `monitoring` brings event and report; `development`, the
  Playground's, composes executing, operational and monitoring.
  `xmip-service`'s own features — node, audit, observe — are always on, and
  say so in one place: its `[[bin]] required-features` in `Cargo.toml`.
- **Domains**, what it integrates (`deploy/profile/domain`): a
  description and the standards the domain serves. A standard is the leaf
  of a technology's position in `architecture.toml` (`hl7-v2`, `mllp`,
  `aws-sqs`), so a domain's members are every built technology whose leaf
  it lists, across capabilities, less what a target claims. Thirteen:
  healthcare, industrial, building-automation, vehicle, b2b,
  managed-service (the managed services a hosting provider sells),
  enterprise-messaging, database, file-exchange, mail, web-service,
  network, and integration, the mechanisms every integration uses
  (authenticate, authorize, identify, resilience, route, the common shapes,
  paths and observation). Every built technology is in a domain or claimed
  by a target, and `test/Deploy.Test.ps1` fails when one is not.

**One place turns a site into a build: `Build-XmipService -Site`.** The
features are the target's, every role's (executing expanded), each domain
technology the root crate links through a feature (a feature listing
`dep:<alias>` whose dependency's `package` is the technology: today the
four transports and the two store engines), and xmip-service's required
ones; the command is `cargo build --bin xmip-service --no-default-features
--features <them>`, run at the estate root. A domain technology
xmip-service has no feature for yet is said under `Unlinked`, in words, and
not refused: the build links what exists. `-WhatIf` returns the plan and the
command and builds nothing. The rule that says which technologies are built
moved from `Update-XmipDeployList.ps1` to `Get-XmipBuiltTechnology`, once.

**The target vetoes.** A role or a domain needing a feature the target
refuses is REFUSED in words naming the role or domain, the feature and the
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
