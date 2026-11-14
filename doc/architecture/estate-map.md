# The Xmip estate

327 repositories are declared and 277 of them are
mounted in this working tree.

**Generated from `architecture.toml` and from the `.gitmodules` files
of the estate, by `New-XmipEstateMap`.** ADR-0020 clause 5 rules that
a document listing repositories is a second source of truth and will
be wrong within a week; a view of the manifest is not a second source
of it.
`test/EstateMap.Test.ps1` regenerates this file and fails when the
committed one differs. Edit the manifest and regenerate — an edit made
here is lost.

**Maturity is declared, not observed.** It is what the manifest says
about a repository, never what the repository contains, and the two are
known to disagree.

[`repository-model.md`](repository-model.md) section 7 draws where the
modules mount and says why. This is the whole estate, including every
technology, and whether each one is composed here.

Mounted here and not repositories of the estate: `xmip-template-dotnet`,
`xmip-template-rust`. They are declared under `crate.template` rather than in
the estate tree, and are counted nowhere below.

---

## The count

| Domain | Declared | Mounted | Not mounted |
| --- | ---: | ---: | ---: |
| Foundation | 9 | 9 | 0 |
| Library | 1 | 0 | 1 |
| Capability | 23 | 23 | 0 |
| Operation | 8 | 7 | 1 |
| Platform | 4 | 4 | 0 |
| Technology | 282 | 234 | 48 |
| **Total** | 327 | 277 | 50 |

| Maturity | Declared | Mounted | Not mounted |
| --- | ---: | ---: | ---: |
| planned | 1 | 0 | 1 |
| reserved | 49 | 0 | 49 |
| scaffolded | 277 | 277 | 0 |

**Mounted means composed as a submodule, and composition happens at two
levels** (ADR-0016, amended 2026-09-07). The root `.gitmodules` composes
the modules under `module/`, `test/` and `template/`. A technology is
composed by its own parent capability, inside that repository, so the
root cannot see it and this map reads each parent as well. A technology
reported as not mounted is one its parent does not compose — not one
the root forgot.

---

## What is built

One state per user-facing capability, declared in the manifest's
`[implementation]` table: built, in the assembled service — `xmip-service`, or
for an operator's act the surfaces that operate it; built, not in the
assembled service; decided, not built; or open. A document that promises one
cites its state beside the promise, as a link to the entry here, and
`test/Documentation.Test.ps1` fails a citation whose words the manifest does
not say. The requirement stays in the document; this says how much of it is
true now, and changes in the same change as the code that changes it.

### Built, in the assembled service

#### `arrival`

**Receiving a Stream through a node's gates and publishing its Message.** The
runtime receives through a linked transport, identifies, authenticates and
authorizes, writes the Stream to the Ledger in chunks and publishes a Message
with what it learned in its context. Nothing a transport hands over is
dropped: what it observed of the sender (the socket peer, the request line,
the certificate a TLS handshake verified) and its headers reach the first
gate, and the headers the Message Context. `xmip-service` links the identify
technologies that need no configuration (`certificate`, `ip`, `jwt`,
`api-key`, `username`), the `circumstance` authenticator in every build, the
`mutual-tls` authenticator and the `location` policy, and its tcp terminates
TLS where a Receive Location says `tls = true`, presenting the node's
`[provision.receive]` certificate and verifying a client's against its
anchors, the handshake read under its own bound: a Receive Location accepting
`mutual-tls`, narrowed by `accept.party` to Parties `[[parties]]` declares,
each with its UUIDv7 id and its identities by mechanism and purpose, receives
a Stream from such a Party and refuses any other at authentication, auditing
the refused attempt with its claim; and a file Receive Location accepting
`circumstance` receives a dropped file, the `location` policy admits it and
the Send Location the node starts, and a file Send Location writes it in the
directory its address names under the name it was dropped under. No
authenticator a credential store sets up is linked, so a Location accepting a
password-shaped mechanism is refused as the node starts (open problem 33).
Records: ADR-0019 (amendments 2026-10-19 and 2026-10-20), ADR-0024 (amendment
2026-10-20), ADR-0033 (amendments 2026-10-19 and 2026-10-20), ADR-0050
(amendment 2026-10-20), runtime-model.md section 5.

#### `certificate-usage`

**Presenting and verifying certificates an operator supplies.**
`xmip-core-library-tls` presents and verifies PEM certificates; the web host
serves https with them, and Xmip Storage's client and server speak mutual TLS
with them. `xmip-service` presents the node's `[provision.receive]`
certificate on a tcp Receive Location that terminates TLS and verifies a
Party's against the anchors given there; a Send Location presents none yet.
Records: ADR-0033 (amendment 2026-10-19), ADR-0063.

#### `configuration-saving`

**Saving and slicing the cluster's configuration.** The Operation Desktop
saves `cluster.xmip`, validated by the runtime and audited, and slices it
through `xmip_cluster_signed_slice_v1`, each slice signed by the cluster's
authority beside the file; desired state slices it and signs it on the machine
the environment is deployed from (`xmip-service --slice --authority`) and
ships each node its slice and the authority's certificate alone. A node runs
only a slice that verifies against the authority's certificate beside it,
refuses and audits one changed by hand, and one that verifies and that it
cannot start, and runs its active configuration, the last slice that ran,
instead (`runtime::signed`, `runtime::running::activation`); its record at
`<node>/configuration` and `xmip-service --activation` say which, and desired
state asks the latter. A changed slice takes effect when the node starts
again. Records: ADR-0031 (amendments 2026-10-01, 2026-10-05, 2026-11-06,
2026-11-12).

#### `embedded-storage`

**A node as its own embedded Storage node.** A node declaring the Storage role
keeps RocksDB for the runtime database and SQLite for the administration
database under its data directory, and SQLite for the audit database, each
where its table — `[runtime]`, `[administration]`, `[audit]`, its `storage`
and `connection` — says and under the data directory where it is left out, all
sealed under the key store `[store]` names; each database is brought to the
build's schema version as it opens, one newer refused in words, and the
version each holds is published at `<node>/storage/<domain>`; a node declaring
neither the role nor `[storage] nodes` is refused as it starts. Records:
ADR-0015 (amendments 2026-10-01 and 2026-10-20), ADR-0056 (amendment
2026-10-20), ADR-0063, ADR-0070 (amendment 2026-10-10).

#### `operator-acts-through-storage`

**An operator's act written to Xmip Storage, honored by every node.** A pause,
resume, retry, dismiss or replay reaching any node's operate listener is
admitted there by the caller's own role and written to the administration
database's `operator_act` table, asked of the node that owns what it acts on,
with who, how proven, the role, the relay, the door and when: through that
node's Xmip Storage where it runs in the door's process, and otherwise only at
a door declaring the operational role, every other refusing in words. Every
node's act watch in `xmip-service` is told at once by its wait on Xmip
Storage, judges the caller again by its own `[operate]` lists, takes the act
by the one apply, decides it once and audits it; an act asked of a node that
is not running stays asked, never expiring, and is taken as it starts. The
door answers the decision, or `asked` past `[tuning] operate_act`, which every
surface says. Every act reaches its node through a door and Xmip Storage
alone, and a snapshot is never acted on. Records: ADR-0014 (amendments
2026-10-13, acts through Xmip Storage, and 2026-11-13), ADR-0052 (note of
2026-10-13, acts through Xmip Storage; amendment 2026-11-13), ADR-0009
(amendment 2026-11-13), runtime-model.md section 13, deployment-model.md
section 7.

#### `process-declaration`

**Declaring a Work Process.** `[[work_processes]]` and an Application's Work
Processes are read, validated and planned into the execution tree as a node
starts, and a Subscription may lead to one; each is published as planned, not
started. Records: ADR-0018, ADR-0064.

#### `program-audit`

**Every Xmip program audits to its audit file.** `xmip-service`, `xmip`, both
PowerShell modules, the web host, the language server and the Essentials
record through `xmip-core-audit`'s `ProgramAudit` into `audit.toml`,
synchronously: a record is appended before `record` returns, chained in its
writer's audit chain under `audit.lock` (ADR-0070 clause 5), the operating
system's log the fallback; the next append seals a record whose write was
interrupted, kept as written and in no chain; `xmip audit --verify`,
`Get-XmipAudit -Verify` and the Audit view's verify walk the chains and say
each such fragment apart from them. Records: ADR-0062, ADR-0070.

#### `send-port-retry`

**A Send Port's retry.** A Send Port tries each Send Location again by its
`retry = { attempts, backoff }`, and a Message whose every Location failed its
tries is written Failed and waits for Retry or Dismiss. Records: ADR-0013,
runtime-model.md section 10.

#### `storage-nodes`

**Storage nodes reached over mutual TLS.** A node without the Storage role
reaches the Storage nodes `[storage] nodes` lists over Xmip's mutual TLS,
presenting the certificate, key and anchors `[storage]` names — the node's
own, from the cluster's authority — a standby passed over, a primary of an
earlier epoch not asked, and refused at start in words where it names nothing
to present; a node with the Storage role serves Xmip Storage at `[storage]
listen`, and `xmip-service --listening` says its port; every node publishes at
`<node>/storage` which Storage it uses and whether it answered, Done where
none did. Held by the root's `failover` and `wire` tests and the Essentials'
level 1, every node a process. Records: ADR-0056 (amendments 2026-10-01 and
2026-10-22), ADR-0067 (amendment 2026-10-22).

#### `storage-standby`

**Embedded Storage nodes as a primary and its standbys.** Storage nodes that
list every Storage node of the cluster settle which is the primary by asking
each what it is: one is promoted only where every one listed answers and none
is a primary, the one holding most of the latest epoch, the first listed of
equals; each standby copies the primary's engine writes in order,
asynchronously, copied whole first where it cannot take them on (its data keys
handed inside the mutual TLS, wrapped under its own key-encryption key); each
promotion raises the epoch, a primary that meets a later one steps down, and a
primary stopped in order hands on everything it wrote. A primary knows each
standby by the node its certificate names and counts what it hands each, and
its node draws each as *copies to* at the rate it copies; a standby not ready
yet stands Working (amendments 2026-11-13). No witness, so no automatic
failover: a primary that is gone is waited for, never replaced, and automatic
failover returns with a witness (the owner, 2026-11-08). Drafted, for the
owner (ADR-0056, amendment 2026-10-22); promotion decided (amendment
2026-11-08). Records: ADR-0056 (amendments 2026-10-22, 2026-11-08 and
2026-11-13), ADR-0052 (amendment 2026-11-13), ADR-0063 (amendment 2026-10-22),
deployment-model.md sections 7 and 9.

#### `subscription-pause`

**Pausing and resuming a Subscription.** An act the node takes, asked at any
node's door through Xmip Storage (ADR-0014, amendment 2026-11-13): what the
Subscription matches is held in Xmip Storage, surviving a restart, and picked
up oldest first on resume; every surface lists Subscriptions and takes the
act. Records: ADR-0013 (amendments 2026-09-30, 2026-10-01).

#### `subscription-routing`

**Routing by the Subscriptions a node binds.** A node routes every Message it
publishes against the Subscriptions of the Xmip Applications it binds, their
filters compiled as it starts; in the assembled service a Stream a Receive
Location accepts reaches routing, and a Message routed onward to a Send
Location the node starts is admitted there by the `location` policy and sent
(`arrival`). Records: ADR-0013, ADR-0066.

### Built, not in the assembled service

#### `certificate-provisioning`

**Obtaining and renewing certificates (ACME, an internal authority).**
`xmip-core-provision` and its technologies obtain and renew a certificate:
`acme` against any ACME directory, Let's Encrypt one option; `internal-ca`,
the cluster's authority, served over ACME; `self-signed` for a lone offline
node; and an operator's files. A person's certificate, purpose `operator`, is
requested by the surface with its own key and signed by the authority
`[provision.operator]` names: `xmip certificate`, `New-XmipCertificate`,
`xmip_operate.h` section 19; on the phone and the desktop the key is made in
the platform's keeper and never leaves it (the Android Keystore, the Secure
Enclave, Windows CNG and the TPM), the request signed there in the two halves
section 19 exports and every handshake signed there through
`xmip-core-library-tls`'s `Sign`. Proved in their tests, offline.
`xmip-service` reads `[provision.receive]` from an operator's files alone, as
it starts, and starts no provisioner: a table naming a `source` is refused. It
serves the cluster's authority, the premises' own ACME service, where
`[provision.node]` names `internal-ca` and `serve`: renewal information (RFC
9773), revocation into the authority's register and its revocation list,
published over plain HTTP; lego, a standard client, is proved against it.
Every surface sets the authority up, inspects, revokes from, exports and backs
up (`xmip certificate`, `New-` and `Get-XmipCertificate`, the desktop's
Authority page, `xmip_operate.h` section 23), and a node's certificate is
carried across an air gap — requested on the node, signed where the authority
is kept, imported — its node saying in its health when the next request is
due. Open problem 27. Records: ADR-0034 (amendments 2026-10-15 and
2026-10-22), ADR-0033 (amendment 2026-10-13).

#### `module-loading`

**Opening a Module at run time.** The loader opens a shared library, resolves
`xmip_create_module_v1`, checks its trait version and configures, starts and
stops its contract table, and opens a work process table as the flow of the
Work Processes naming its units (section 13); the work process table is the
one the message path calls. It is behind the runtime's `dynamic-loading`
feature, which `xmip-service` is not built with; every other technology is
linked by feature, so adding one means running `Build-XmipService` again.
Records: ADR-0025, ADR-0057.

#### `process-execution`

**Compiling a Work Process at design time, and running it.** A BPMN 2.0 design
compiles to a Work Process program and a unit crate exporting it through
`xmip_module.h` section 13 (`xmip-core-process`, `xmip-core-process-bpmn`);
the runtime's Work Process step takes a turn of each Instance from the Ledger,
held by `tests/ledger/work_process.rs` (a Batch in the order received, two
clients at once never overtaking, a node killed mid-process finishing from the
Ledger) and the two crates' tests. A unit is opened from its library behind
the runtime's `dynamic-loading` feature, which `xmip-service` is not built
with; a unit's settings and calls through the standard units are decided, not
built. Records: ADR-0066 (amendment 2026-10-22), runtime-model.md section 22.

#### `regulation-quest`

**The Regulation Quest: a regulation's evidence and gaps.** `xmip-core-report`
holds the Quest seam and the Regulation Quest, its regulations an open set a
module adds to, and GDPR's nine requirements, each citing its article:
encryption at rest, encryption on each Location's wire and the audit probed in
a node's configuration, the rest gaps not yet available in Xmip. It is listed
as the Regulation Report in the one list of every Report (ADR-0072, amendment
2026-11-10), which the runtime's library answers through `xmip_operate.h`
section 25, composing the `Installation` from a node's configuration file or a
cluster's `cluster.xmip` sliced for one node, and recording each probe in the
audit; every surface lists and opens it: the command line as `xmip report`,
PowerShell as `Get-XmipReport` and the GUI's Reports view, which probes the
desktop's `cluster.xmip`. Nothing composes it from a running node yet, and
every transport declares nothing of its wire yet, so every Location is a gap.
Records: ADR-0072.

#### `resilience-guards`

**The six resilience guards.** Retry, timeout, circuit breaker, rate limit,
bulkhead and fallback are guards `xmip-core-resilience` asks in order; the
Event forwarder runs them for the http, amqp and kafka Event wires, and only
tests build a guard. The timeout judges an attempt after it ended; it does not
interrupt one. Records: ADR-0048.

#### `retention-archiving`

**Archiving by retention window.** `xmip-core-retain` and `xmip-core-archive`
are driven by the Essentials on a simulated clock; a node has no retention or
archive step and reads no `[retention]` table. Records: ADR-0040.

### Decided, not built

#### `arrival-validation`

**Holding a Stream to a named Contract.** A node refuses to start a Receive or
Send Location that names a Contract, in words: arrival holds no Stream to one
yet (`xmip-core-runtime`'s `startup.rs`). The contract technologies validate,
and the Essentials holds its generated content to them in its own harness, not
at a node's Location. Records: ADR-0042, ADR-0031 (amendment 2026-10-05).

#### `artifact-scope`

**A reading names its artifact by kind and name.** Every scope a node
publishes still writes a stage and a Location or Work Process beneath its
node, `…/receive/<Location>`, `…/process/<name>` and `…/send/<Location>`; none
writes `ReceivePort`, `ReceiveLocation`, `WorkProcess`, `SendPortGroup`,
`SendPort` or `SendLocation`, no Port is a level, no scope leaves the node
out, and no reading shows the Party involved. Records: ADR-0027 (amendment
2026-10-06).

#### `artifact-steps`

**Prepare, Contract, Promote, Transform, Demote and Assignment on Ports,
Locations and Work Processes.** The keys are decided and none is read;
Assignment and Transformation have the Message's generations ready in
`xmip-core-message` and the runtime's `generation.rs`, with no caller outside
tests. Records: ADR-0031 (amendment 2026-10-05), runtime-model.md section 20.

#### `audit-through-storage`

**Audit written through Xmip Storage and kept by the audit keeper.** Xmip
Storage's `keep_audit` exists and is tested, and nothing calls it outside
tests; only publication and replay records reach the Ledger, each carrying its
Message in full, and the keeper keeps them in the audit database, a data
domain of its own (amendment 2026-10-10), the record's body in chunks of the
runtime's Stream chunk and every Stream's bytes beside the record, each with
its SHA-256 digest and length, verified when read, and chains each record in
its writer's audit chain as it keeps it (ADR-0070 clauses 1, 2, 4 and 5,
amendments 2026-10-10); the runtime's `ledger::verify_audit_chain` walks a
writer's chain, and no surface reads a kept record or calls it. The file sink
is what every program writes. Records: ADR-0062, ADR-0070, deployment-model.md
section 7.

#### `bounded-audit-channel`

**A bounded asynchronous audit channel with a capacity policy.** The keeper
`xmip-core-audit` runs is an unbounded queue on one thread, used by Event
delivery records alone, and a program's own record waits for it to drain; no
capacity, discard, sampling or back-pressure policy exists. Records:
audit-record.md, Performance.

#### `configuration-delivery`

**Delivering a slice to its node, its acceptance, and restarting only what
changed.** No Xmip path puts a slice on another node: the desktop delivers
only to the node it starts, a node answers no accepted or refused, and a save
is not versioned, watched for drift or applied by restarting only the threads
or Host Services that changed. Open problem 31. Records: ADR-0031 (amendments
2026-10-05).

#### `database-server`

**Xmip Storage in front of PostgreSQL, SQL Server or MariaDB.** Each data
domain's table — `[runtime]`, `[administration]`, `[audit]` — is read and
checked, its `storage` and its connection in the server's own form, each of
which may name a server or technology of its own, and `[storage.database]` the
secret; IT's scripts are in `deploy/database`, per data domain, each database
recording its schema version, and a release's upgrade is written as the
difference from an earlier one by `xmip database` and
`Get-XmipDatabaseScript`; a node naming a server is refused as it starts,
since no Storage node connects to any kind yet. Records: ADR-0015 (amendments
2026-10-01 and 2026-10-20), ADR-0070 (amendments 2026-10-10 and 2026-10-12),
deployment-model.md section 7.

#### `host-subprocess`

**An Xmip Host Subprocess, named for its parent.** Nothing spawns an Xmip Host
Subprocess: a node runs its one in-process Host Service and refuses a Module
that needs another (`xmip-core-runtime`'s `startup.rs`), so no process is
named for its parent plus a dash and a short readable word. Records: ADR-0018
(amendment 2026-10-06), ADR-0053 (amendment 2026-10-06).

#### `node-listeners`

**A node's sync and alive listeners, each configured as operate is.** The
operate plane listens — its local endpoint always, named `xmip-<node>` unless
`[operate] local` names it, and its network listener where `[operate] listen`
names one — and, on a node declaring the Storage role, the Storage listener
where `[storage] listen` names one (amendment 2026-10-22). No `[sync]` or
`[alive]` section is read, and no node-to-node or heartbeat listener exists in
the service. Records: ADR-0067 (amendments 2026-10-13 and 2026-10-22).

#### `other-runtime-module`

**A Module on another runtime.** A .NET Module in process, on threads, unless
excluded, and another runtime in a process of its own unless configuration
invites it in: no `InProcess` setting, no .NET hosting and no out-of-process
channel exist, and a Host Service of its own is refused at start. Records:
ADR-0018 (amendment 2026-10-05).

#### `security-profile`

**Security profiles: standard, enterprise, regulated.** No configuration key
names a profile and nothing enforces identity isolation at start; the
isolation rule (`IdentityContext::may_share_host_service`) is called by its
tests alone. Records: ADR-0022, deployment-model.md section 4.

#### `send-resilience`

**Guards configured on Send Port Groups, Send Ports and Send Locations.** The
Polly-like pipeline on the send artifacts, a timeout that interrupts an
attempt, and each transport's send completion (answered, confirmed write,
unconfirmed) are decided; none is built. Records: ADR-0048 (amendments
2026-10-06).

#### `shared-subscriptions`

**Subscriptions shared across the cluster through Xmip Storage.** No Storage
record holds a Subscription and no node writes one there; Xmip Storage keeps a
paused Subscription's standing and what it holds, per node. A node routes only
what it received. Records: ADR-0031 (amendment 2026-10-02).

---

## The tree

Where each repository mounts and what it holds: 372631 lines of production
source, every file charged to the deepest repository containing it, so a
parent is its own code and never its children added again. Counted by
`Get-XmipSourceFile`, which is also what `test/Rust.Style.Test.ps1` gates file
length with; a Rust file ends at its first `#[cfg(test)]` and a `*.Test.ps1`
or `*.Test.cs` counts as nothing.

Heaviest first at every level, because that is what a tree of counts is for.
The tables below are alphabetical, for looking a name up. A name ending in `/`
is a directory of the working tree; every other name is a repository.

A repository written in more than one language says what it is made of,
largest first, and one written in a single language says nothing — the estate
is Rust and the exception is what a reader needs told. One total hid that the
largest repository in the estate is almost all C# (the owner, 2026-09-21).

A name under `declared, not built` is declared by the manifest and mounted
nowhere — work not begun, not work unmounted. There are 50 of them and they
hold no source to count.

```text
├── sdk                                          377
├── module/
│   ├── core/
│   │   ├── capability/
│   │   │   ├── transport                       8492
│   │   │   │   ├── amqp                        2707
│   │   │   │   ├── opc-ua                      2513
│   │   │   │   ├── db2                         2475
│   │   │   │   ├── nfs                         2166
│   │   │   │   ├── http                        2041
│   │   │   │   ├── smb                         2025
│   │   │   │   ├── kafka                       2023
│   │   │   │   ├── ibm-mq                      1909
│   │   │   │   ├── ftp                         1839
│   │   │   │   ├── sftp                        1827
│   │   │   │   ├── mssql                       1648
│   │   │   │   ├── snmp                        1448
│   │   │   │   ├── nats-jetstream              1399
│   │   │   │   ├── oracle                      1352
│   │   │   │   ├── as4                         1342
│   │   │   │   ├── s7comm                      1239
│   │   │   │   ├── secs-gem                    1204
│   │   │   │   ├── imap                        1197
│   │   │   │   ├── mqtt                        1192
│   │   │   │   ├── canopen                     1153
│   │   │   │   ├── dns                         1142
│   │   │   │   ├── webdav                      1133
│   │   │   │   ├── iec-61850                   1107
│   │   │   │   ├── nats                        1053
│   │   │   │   ├── ethercat                     994
│   │   │   │   ├── dicom                        992
│   │   │   │   ├── as2                          973
│   │   │   │   ├── ethernet-ip                  943
│   │   │   │   ├── aws-sns                      937
│   │   │   │   ├── m-bus                        931
│   │   │   │   ├── activemq                     921
│   │   │   │   ├── hart                         918
│   │   │   │   ├── j1939                        903
│   │   │   │   ├── uds                          898
│   │   │   │   ├── aws-kinesis                  894
│   │   │   │   ├── bluetooth                    891
│   │   │   │   ├── file                         888
│   │   │   │   ├── redis-streams                884
│   │   │   │   ├── lorawan                      880
│   │   │   │   ├── pop3                         877
│   │   │   │   ├── azure-service-bus            868
│   │   │   │   ├── azure-event-grid             862
│   │   │   │   ├── google-pub-sub               857
│   │   │   │   ├── aws-sqs                      849
│   │   │   │   ├── profinet                     846
│   │   │   │   ├── dhcp                         827
│   │   │   │   ├── wireless-hart                825
│   │   │   │   ├── thread                       796
│   │   │   │   ├── zigbee                       789
│   │   │   │   ├── smtp                         775
│   │   │   │   ├── peppol                       759
│   │   │   │   ├── knx                          751
│   │   │   │   ├── iso-tp                       727
│   │   │   │   ├── syslog                       723
│   │   │   │   ├── iec-60870-5-104              721
│   │   │   │   ├── s3                           717
│   │   │   │   ├── azure-blob                   703
│   │   │   │   ├── mdns                         701
│   │   │   │   ├── cotp                         695
│   │   │   │   ├── dds                          695
│   │   │   │   ├── websocket                    687
│   │   │   │   ├── google-cloud-storage         685
│   │   │   │   ├── io-link                      680
│   │   │   │   ├── dnp3                         668
│   │   │   │   ├── msmq                         656
│   │   │   │   ├── obd-ii                       621
│   │   │   │   ├── ssdp                         621
│   │   │   │   ├── coap                         586
│   │   │   │   ├── modbus                       583
│   │   │   │   ├── redpanda                     578
│   │   │   │   ├── azure-event-hubs             540
│   │   │   │   ├── wireless-m-bus               536
│   │   │   │   ├── serial                       518
│   │   │   │   ├── aws                          511
│   │   │   │   ├── ethernet                     493
│   │   │   │   ├── mysql                        483
│   │   │   │   ├── can-bus                      478
│   │   │   │   ├── sqlite                       471
│   │   │   │   ├── bacnet                       459
│   │   │   │   ├── azure                        452
│   │   │   │   ├── mllp                         449
│   │   │   │   ├── rabbitmq                     434
│   │   │   │   ├── unix-socket                  367
│   │   │   │   ├── named-pipe                   330
│   │   │   │   ├── mariadb                      303
│   │   │   │   ├── tcp                          280
│   │   │   │   ├── postgresql                   240
│   │   │   │   └── udp                          219
│   │   │   ├── provision                       3832
│   │   │   │   ├── internal-ca                 2556
│   │   │   │   ├── acme                        1222
│   │   │   │   ├── self-signed                   81
│   │   │   │       declared, not built 1
│   │   │   │       platform
│   │   │   ├── authenticate                    3318
│   │   │   │   ├── saml                         983
│   │   │   │   ├── kerberos                     796
│   │   │   │   ├── ldap                         781
│   │   │   │   ├── oauth2                       597
│   │   │   │   ├── ntlm                         591
│   │   │   │   ├── digest                       448
│   │   │   │   ├── scram                        393
│   │   │   │   ├── windows                      377
│   │   │   │   ├── pam                          339
│   │   │   │   ├── ssh-key                      268
│   │   │   │   ├── oidc                         233
│   │   │   │   ├── jwt                          214
│   │   │   │   ├── certificate                  152
│   │   │   │   ├── api-key                       99
│   │   │   │   ├── bearer                        94
│   │   │   │   ├── password                      81
│   │   │   │   ├── basic                         76
│   │   │   │   └── mutual-tls                    74
│   │   │   ├── path                            2694
│   │   │   │   ├── jsonpath                     665
│   │   │   │   ├── fhirpath                     619
│   │   │   │   ├── xpath                        359
│   │   │   │   ├── dot                          293
│   │   │   │   ├── hl7-v2                       256
│   │   │   │   ├── edi                          219
│   │   │   │   ├── regex                        163
│   │   │   │   ├── index                        161
│   │   │   │   └── json-pointer                  65
│   │   │   ├── prepare                         2423
│   │   │   │   ├── rpgp                         255
│   │   │   │       declared, not built 9
│   │   │   │       bzip2  canonicalize  checksum  chunking  envelope  framing
│   │   │   │        hash  quoted-printable  tar
│   │   │   ├── process                         2391
│   │   │   │   └── bpmn                        3098
│   │   │   ├── transform                       2015
│   │   │   │       declared, not built 8
│   │   │   │       handlebars  jolt  jq  jsonata  liquid  mustache  tera
│   │   │   │       xquery
│   │   │   ├── identify                        1606
│   │   │   │   ├── saml                         395
│   │   │   │   ├── ip                           231
│   │   │   │   ├── api-key                      226
│   │   │   │   ├── dns                          195
│   │   │   │   ├── username                     169
│   │   │   │   ├── jwt                          165
│   │   │   │   ├── ntlm                         155
│   │   │   │   ├── header                       148
│   │   │   │   ├── certificate                  130
│   │   │   │   ├── cookie                       127
│   │   │   │   ├── oidc                         126
│   │   │   │   ├── kerberos                     116
│   │   │   │   ├── transport                    109
│   │   │   │   ├── party                         88
│   │   │   │   ├── endpoint                      82
│   │   │   │   ├── message                       81
│   │   │   │   ├── mac                           71
│   │   │   │   ├── ssh-key                       63
│   │   │   │   └── contract                      52
│   │   │   ├── secret                          1273
│   │   │   │   ├── dpapi                        317
│   │   │   │   ├── file                         197
│   │   │   │   ├── keychain                     107
│   │   │   │       declared, not built 5
│   │   │   │       aws-kms  azure-key-vault  keyring  pkcs11  vault
│   │   │   ├── contract                         979
│   │   │   │   ├── graphql-schema               874
│   │   │   │   ├── json-schema                  851
│   │   │   │   ├── xml-schema                   822
│   │   │   │   ├── avro                         802
│   │   │   │   ├── toon                         716
│   │   │   │   ├── protobuf                     714
│   │   │   │   ├── sql                          631
│   │   │   │   ├── edi-x12                      534
│   │   │   │   ├── edi-edifact                  521
│   │   │   │   ├── fixed-width                  512
│   │   │   │   ├── yaml                         504
│   │   │   │   ├── schematron                   435
│   │   │   │   ├── hl7-v2                       397
│   │   │   │   ├── wsdl                         389
│   │   │   │   ├── openapi                      385
│   │   │   │   ├── toml                         314
│   │   │   │   ├── fhir                         294
│   │   │   │   ├── asyncapi                     243
│   │   │   │   ├── regex                        207
│   │   │   │   └── csv                          140
│   │   │   ├── route                            739
│   │   │   │   ├── metadata                     125
│   │   │   │   ├── content                      108
│   │   │   │   ├── contract                      86
│   │   │   │   ├── regex                         76
│   │   │   │   ├── party                         69
│   │   │   │   ├── header                        68
│   │   │   │   └── context                       47
│   │   │   ├── authorize                        552
│   │   │   │   ├── location                     397
│   │   │   │   ├── abac                         364
│   │   │   │   ├── opa                          289
│   │   │   │   ├── cedar                        282
│   │   │   │   ├── policy                       249
│   │   │   │   ├── transport                    206
│   │   │   │   ├── role                         200
│   │   │   │   ├── contract                     189
│   │   │   │   ├── artifact                     178
│   │   │   │   ├── scope                        173
│   │   │   │   ├── claim                        168
│   │   │   │   ├── rbac                         163
│   │   │   │   ├── acl                          147
│   │   │   │   └── party                        131
│   │   │   ├── unit                             431
│   │   │   ├── schedule                         263
│   │   │   ├── receive                          178
│   │   │   ├── demote                           175
│   │   │   ├── logic                            164
│   │   │   │   ├── matter                      1129
│   │   │   │   ├── soap                         271
│   │   │   │   ├── http-api                     259
│   │   │   │   └── grpc                         178
│   │   │   ├── promote                          160
│   │   │   ├── resilience                       159
│   │   │   │   ├── circuit-breaker              134
│   │   │   │   ├── rate-limit                   107
│   │   │   │   ├── bulkhead                      83
│   │   │   │   ├── retry                         82
│   │   │   │   ├── timeout                       74
│   │   │   │   └── fallback                      66
│   │   │   ├── send                              88
│   │   │   ├── assign                            39
│   │   │   └── retain                            27
│   │   │           declared, not built 5
│   │   │           azure-blob  file  gcs  s3  sql
│   │   ├── library/
│   │   │   ├── net                             7347
│   │   │   ├── codec                           5861
│   │   │   ├── tls                             4201
│   │   │   ├── mariadb                         1785
│   │   │   ├── ssh                             1744
│   │   │   ├── sql                             1304
│   │   │   ├── postgresql                       963
│   │   │   ├── ntlm                             804
│   │   │   └── asn1                             686
│   │   └── operation/
│   │       ├── cli                            10146
│   │       ├── gui                             7921
│   │       │   └── vscode                      3517
│   │       ├── observe                         7690
│   │       │   ├── otlp                         587
│   │       │   └── prometheus                   328
│   │       ├── audit                           4353
│   │       │       declared, not built 10
│   │       │       elasticsearch  file  kafka  mssql  opensearch  otlp
│   │       │       postgres  sqlite  syslog  windows-event-log
│   │       ├── powershell                      3782  C# 3782 · PowerShell 0
│   │       ├── report                          2250
│   │       │       declared, not built 6
│   │       │       csv  html  json  pdf  prometheus  sql
│   │       └── archive                          631
│   │           ├── file                         292
│   │           ├── sql                          263
│   │           ├── azure-blob                   165
│   │           ├── s3                           155
│   │           ├── parquet                      147
│   │           ├── gcs                          135
│   │           ├── sqlite                       125
│   │           ├── mariadb                       89
│   │           ├── postgresql                    62
│   │           └── mssql                         59
│   ├── foundation/
│   │   ├── abi                                35673  C# 32839 · Rust 2431 · PowerShell 403
│   │   ├── core                                4438
│   │   ├── message                             1830
│   │   │   ├── avro                             300
│   │   │   ├── json                             257
│   │   │   ├── xml                              180
│   │   │   ├── protobuf                         173
│   │   │   ├── csv                              150
│   │   │   ├── fixed-width                      105
│   │   │   ├── multipart                         99
│   │   │   ├── hl7-er7                           94
│   │   │   ├── form-urlencoded                   86
│   │   │   ├── edi-x12                           78
│   │   │   ├── edi-edifact                       76
│   │   │   ├── ubl                               65
│   │   │   ├── text                              59
│   │   │   ├── edi-tradacoms                     56
│   │   │   └── binary                            38
│   │   ├── event                               1430
│   │   │       declared, not built 3
│   │   │       amqp  http  kafka
│   │   ├── node                                1262
│   │   ├── context                             1149
│   │   ├── journey                              751
│   │   ├── stream                               382
│   │   └── party                                193
│   └── platform/
│       ├── runtime                            52790
│       ├── persist                            20658
│       │   ├── rocksdb                          323
│       │   ├── sqlite                           288
│       │       declared, not built 1
│       │       postgresql
│       ├── configure                           8882
│       └── cluster                             4830
└── test/
    └── core/
        ├── essentials                         16473
        └── module                                83
```

---

## Foundation

Things Xmip is.

| Repository | Maturity | Mount | Technologies |
| --- | --- | --- | ---: |
| `xmip-core` | scaffolded | `module/foundation/core` | — |
| `xmip-core-abi` | scaffolded | `module/foundation/abi` | — |
| `xmip-core-context` | scaffolded | `module/foundation/context` | — |
| `xmip-core-event` | scaffolded | `module/foundation/event` | 3 |
| `xmip-core-journey` | scaffolded | `module/foundation/journey` | — |
| `xmip-core-message` | scaffolded | `module/foundation/message` | 15 |
| `xmip-core-node` | scaffolded | `module/foundation/node` | — |
| `xmip-core-party` | scaffolded | `module/foundation/party` | — |
| `xmip-core-stream` | scaffolded | `module/foundation/stream` | — |

### `xmip-core-event`, 3 technologies

Declared, and none composed: `module/foundation/event` has no `.gitmodules`.

- **reserved**, 3 — amqp, http, kafka

### `xmip-core-message`, 15 technologies

All 15 composed in `module/foundation/message`.

- **scaffolded**, 15 — avro, binary, csv, edi-edifact, edi-tradacoms, edi-x12,
  fixed-width, form-urlencoded, hl7-er7, json, multipart, protobuf, text, ubl,
  xml

---

## Library

What capabilities are built out of.

| Repository | Maturity | Mount | Technologies |
| --- | --- | --- | ---: |
| `xmip-core-library` | reserved | not mounted | 9 |

### `xmip-core-library`, 9 technologies

The parent is not composed here, so what it composes cannot be read; every
technology below is declared only.

- **scaffolded**, 9 — asn1, codec, mariadb, net, ntlm, postgresql, sql, ssh,
  tls

---

## Capability

Things Xmip does.

| Repository | Maturity | Mount | Technologies |
| --- | --- | --- | ---: |
| `xmip-core-assign` | scaffolded | `module/core/capability/assign` | — |
| `xmip-core-authenticate` | scaffolded | `module/core/capability/authenticate` | 18 |
| `xmip-core-authorize` | scaffolded | `module/core/capability/authorize` | 14 |
| `xmip-core-contract` | scaffolded | `module/core/capability/contract` | 20 |
| `xmip-core-demote` | scaffolded | `module/core/capability/demote` | — |
| `xmip-core-identify` | scaffolded | `module/core/capability/identify` | 19 |
| `xmip-core-logic` | scaffolded | `module/core/capability/logic` | 4 |
| `xmip-core-path` | scaffolded | `module/core/capability/path` | 9 |
| `xmip-core-prepare` | scaffolded | `module/core/capability/prepare` | 10 |
| `xmip-core-process` | scaffolded | `module/core/capability/process` | 1 |
| `xmip-core-promote` | scaffolded | `module/core/capability/promote` | — |
| `xmip-core-provision` | scaffolded | `module/core/capability/provision` | 4 |
| `xmip-core-receive` | scaffolded | `module/core/capability/receive` | — |
| `xmip-core-resilience` | scaffolded | `module/core/capability/resilience` | 6 |
| `xmip-core-retain` | scaffolded | `module/core/capability/retain` | 5 |
| `xmip-core-route` | scaffolded | `module/core/capability/route` | 7 |
| `xmip-core-schedule` | scaffolded | `module/core/capability/schedule` | — |
| `xmip-core-sdk` | scaffolded | `sdk` | — |
| `xmip-core-secret` | scaffolded | `module/core/capability/secret` | 8 |
| `xmip-core-send` | scaffolded | `module/core/capability/send` | — |
| `xmip-core-transform` | scaffolded | `module/core/capability/transform` | 8 |
| `xmip-core-transport` | scaffolded | `module/core/capability/transport` | 88 |
| `xmip-core-unit` | scaffolded | `module/core/capability/unit` | — |

### `xmip-core-authenticate`, 18 technologies

All 18 composed in `module/core/capability/authenticate`.

- **scaffolded**, 18 — api-key, basic, bearer, certificate, digest, jwt,
  kerberos, ldap, mutual-tls, ntlm, oauth2, oidc, pam, password, saml, scram,
  ssh-key, windows

### `xmip-core-authorize`, 14 technologies

All 14 composed in `module/core/capability/authorize`.

- **scaffolded**, 14 — abac, acl, artifact, cedar, claim, contract, location,
  opa, party, policy, rbac, role, scope, transport

### `xmip-core-contract`, 20 technologies

All 20 composed in `module/core/capability/contract`.

- **scaffolded**, 20 — asyncapi, avro, csv, edi-edifact, edi-x12, fhir,
  fixed-width, graphql-schema, hl7-v2, json-schema, openapi, protobuf, regex,
  schematron, sql, toml, toon, wsdl, xml-schema, yaml

### `xmip-core-identify`, 19 technologies

All 19 composed in `module/core/capability/identify`.

- **scaffolded**, 19 — api-key, certificate, contract, cookie, dns, endpoint,
  header, ip, jwt, kerberos, mac, message, ntlm, oidc, party, saml, ssh-key,
  transport, username

### `xmip-core-logic`, 4 technologies

All 4 composed in `module/core/capability/logic`.

- **scaffolded**, 4 — grpc, http-api, matter, soap

### `xmip-core-path`, 9 technologies

All 9 composed in `module/core/capability/path`.

- **scaffolded**, 9 — dot, edi, fhirpath, hl7-v2, index, json-pointer,
  jsonpath, regex, xpath

### `xmip-core-prepare`, 10 technologies

1 of 10 composed in `module/core/capability/prepare`; a name marked `*` is one
the parent does not compose.

- **reserved**, 9 — bzip2*, canonicalize*, checksum*, chunking*, envelope*,
  framing*, hash*, quoted-printable*, tar*
- **scaffolded**, 1 — rpgp

### `xmip-core-process`, one technology

Composed in `module/core/capability/process`.

- **scaffolded**, 1 — bpmn

### `xmip-core-provision`, 4 technologies

3 of 4 composed in `module/core/capability/provision`; a name marked `*` is
one the parent does not compose.

- **reserved**, 1 — platform*
- **scaffolded**, 3 — acme, internal-ca, self-signed

### `xmip-core-resilience`, 6 technologies

All 6 composed in `module/core/capability/resilience`.

- **scaffolded**, 6 — bulkhead, circuit-breaker, fallback, rate-limit, retry,
  timeout

### `xmip-core-retain`, 5 technologies

Declared, and none composed: `module/core/capability/retain` has no
`.gitmodules`.

- **reserved**, 5 — azure-blob, file, gcs, s3, sql

### `xmip-core-route`, 7 technologies

All 7 composed in `module/core/capability/route`.

- **scaffolded**, 7 — content, context, contract, header, metadata, party,
  regex

### `xmip-core-secret`, 8 technologies

3 of 8 composed in `module/core/capability/secret`; a name marked `*` is one
the parent does not compose.

- **reserved**, 5 — aws-kms*, azure-key-vault*, keyring*, pkcs11*, vault*
- **scaffolded**, 3 — dpapi, file, keychain

### `xmip-core-transform`, 8 technologies

Declared, and none composed: `module/core/capability/transform` has no
`.gitmodules`.

- **reserved**, 8 — handlebars, jolt, jq, jsonata, liquid, mustache, tera,
  xquery

### `xmip-core-transport`, 88 technologies

All 88 composed in `module/core/capability/transport`.

- **scaffolded**, 88 — activemq, amqp, as2, as4, aws, aws-kinesis, aws-sns,
  aws-sqs, azure, azure-blob, azure-event-grid, azure-event-hubs,
  azure-service-bus, bacnet, bluetooth, can-bus, canopen, coap, cotp, db2,
  dds, dhcp, dicom, dnp3, dns, ethercat, ethernet, ethernet-ip, file, ftp,
  google-cloud-storage, google-pub-sub, hart, http, ibm-mq, iec-60870-5-104,
  iec-61850, imap, io-link, iso-tp, j1939, kafka, knx, lorawan, m-bus,
  mariadb, mdns, mllp, modbus, mqtt, msmq, mssql, mysql, named-pipe, nats,
  nats-jetstream, nfs, obd-ii, opc-ua, oracle, peppol, pop3, postgresql,
  profinet, rabbitmq, redis-streams, redpanda, s3, s7comm, secs-gem, serial,
  sftp, smb, smtp, snmp, sqlite, ssdp, syslog, tcp, thread, udp, uds,
  unix-socket, webdav, websocket, wireless-hart, wireless-m-bus, zigbee

---

## Operation

Running and governing Xmip.

| Repository | Maturity | Mount | Technologies |
| --- | --- | --- | ---: |
| `xmip-core-archive` | scaffolded | `module/core/operation/archive` | 10 |
| `xmip-core-audit` | scaffolded | `module/core/operation/audit` | 10 |
| `xmip-core-cli` | scaffolded | `module/core/operation/cli` | — |
| `xmip-core-gui` | scaffolded | `module/core/operation/gui` | 1 |
| `xmip-core-observe` | scaffolded | `module/core/operation/observe` | 2 |
| `xmip-core-powershell` | scaffolded | `module/core/operation/powershell` | — |
| `xmip-core-report` | scaffolded | `module/core/operation/report` | 6 |
| `xmip-core-test` | reserved | not mounted | 2 |

### `xmip-core-archive`, 10 technologies

All 10 composed in `module/core/operation/archive`.

- **scaffolded**, 10 — azure-blob, file, gcs, mariadb, mssql, parquet,
  postgresql, s3, sql, sqlite

### `xmip-core-audit`, 10 technologies

Declared, and none composed: `module/core/operation/audit` has no
`.gitmodules`.

- **reserved**, 10 — elasticsearch, file, kafka, mssql, opensearch, otlp,
  postgres, sqlite, syslog, windows-event-log

### `xmip-core-gui`, one technology

Composed in `module/core/operation/gui`.

- **scaffolded**, 1 — vscode

### `xmip-core-observe`, 2 technologies

All 2 composed in `module/core/operation/observe`.

- **scaffolded**, 2 — otlp, prometheus

### `xmip-core-report`, 6 technologies

Declared, and none composed: `module/core/operation/report` has no
`.gitmodules`.

- **reserved**, 6 — csv, html, json, pdf, prometheus, sql

### `xmip-core-test`, 2 technologies

The parent is not composed here, so what it composes cannot be read; every
technology below is declared only.

- **scaffolded**, 2 — essentials, module

---

## Platform

Platform-wide runtime services.

| Repository | Maturity | Mount | Technologies |
| --- | --- | --- | ---: |
| `xmip-core-cluster` | scaffolded | `module/platform/cluster` | — |
| `xmip-core-configure` | scaffolded | `module/platform/configure` | — |
| `xmip-core-persist` | scaffolded | `module/platform/persist` | 3 |
| `xmip-core-runtime` | scaffolded | `module/platform/runtime` | — |

### `xmip-core-persist`, 3 technologies

2 of 3 composed in `module/platform/persist`; a name marked `*` is one the
parent does not compose.

- **planned**, 1 — postgresql*
- **scaffolded**, 2 — rocksdb, sqlite

---
