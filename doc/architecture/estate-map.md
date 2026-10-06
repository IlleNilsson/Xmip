# The Xmip estate

333 repositories are declared and 263 of them are
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
| Foundation | 11 | 11 | 0 |
| Library | 1 | 0 | 1 |
| Capability | 19 | 19 | 0 |
| Operation | 8 | 7 | 1 |
| Platform | 3 | 3 | 0 |
| Technology | 291 | 223 | 68 |
| **Total** | 333 | 263 | 70 |

| Maturity | Declared | Mounted | Not mounted |
| --- | ---: | ---: | ---: |
| reserved | 70 | 0 | 70 |
| scaffolded | 263 | 263 | 0 |

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

#### `configuration-saving`

**Saving and slicing the cluster's configuration.** The Operation Desktop
saves the cluster's `xmip.toml`, validated by the runtime and audited, and
slices it through `xmip_cluster_slices_v1`; desired state slices it on each
node (`xmip-service --slice`). A changed slice takes effect when the node
starts again. Records: ADR-0031 (amendments 2026-10-01, 2026-10-05).

#### `embedded-storage`

**A node as its own embedded Storage node.** RocksDB for the runtime database
and SQLite for the administration database under the node's data directory,
sealed under the key store `[store]` names. Records: ADR-0015 (amendment
2026-10-01), ADR-0063.

#### `process-declaration`

**Declaring an Xmip Process.** `[[xmip_processes]]` and an Application's Xmip
Processes are read, validated and planned into the execution tree as a node
starts, and a Subscription may lead to one; each is published as planned, not
started. Records: ADR-0018, ADR-0064.

#### `program-audit`

**Every Xmip program audits to its audit file.** `xmip-service`, `xmip-cli`,
both PowerShell modules, the web host, the language server and the Playground
record through `xmip-core-audit`'s `ProgramAudit` into `audit.toml`,
synchronously: a record is appended before `record` returns, the operating
system's log the fallback. Records: ADR-0062.

#### `send-port-retry`

**A Send Port's retry.** A Send Port tries each Send Location again by its
`retry = { attempts, backoff }`, and a Journey whose every Location failed its
tries is written Failed and waits for Retry or Dismiss. Records: ADR-0013,
runtime-model.md section 10.

#### `subscription-pause`

**Pausing and resuming a Subscription.** An order the node takes: what the
Subscription matches is held in Xmip Storage, surviving a restart, and picked
up oldest first on resume; every surface lists Subscriptions and takes the
act. Records: ADR-0013 (amendments 2026-09-30, 2026-10-01).

#### `subscription-routing`

**Routing by the Subscriptions a node binds.** A node routes every Message it
publishes against the Subscriptions of the Xmip Applications it binds, their
filters compiled as it starts; in the assembled service no Stream reaches
routing yet (`arrival`). Records: ADR-0013, ADR-0066.

### Built, not in the assembled service

#### `arrival`

**Receiving a Stream through a node's gates and publishing its Message.** The
runtime receives through a linked transport, identifies, authenticates and
authorizes, writes the Stream to the Ledger in chunks and publishes a Message
with what it learned in its context. `xmip-service` links no authenticator and
no authorization policy, and a Receive Location authenticates and permits
nothing without them, so the assembled service refuses every Stream at its
gates; the Playground and the runtime's tests hand both in. Records: ADR-0019,
runtime-model.md section 5.

#### `certificate-usage`

**Presenting and verifying certificates an operator supplies.**
`xmip-core-library-tls` presents and verifies PEM certificates; the web host
serves https with them, and Xmip Storage's client and server speak mutual TLS
with them. `xmip-service` presents none yet: it reaches only its own embedded
Storage node. Records: ADR-0033, ADR-0063.

#### `module-loading`

**Opening a Module at run time.** The loader opens a shared library, resolves
`xmip_create_module_v1`, checks its trait version and configures, starts and
stops its contract table, the only table with a host side; nothing on the
message path calls it. It is behind the runtime's `dynamic-loading` feature,
which `xmip-service` is not built with; every other technology is linked by
feature, so adding one means running `Build-XmipService` again. Records:
ADR-0025, ADR-0057.

#### `resilience-guards`

**The six resilience guards.** Retry, timeout, circuit breaker, rate limit,
bulkhead and fallback are guards `xmip-core-resilience` asks in order; the
Event forwarder runs them for the http, amqp and kafka Event wires, and only
tests build a guard. The timeout judges an attempt after it ended; it does not
interrupt one. Records: ADR-0048.

#### `retention-archiving`

**Archiving by retention window.** `xmip-core-retain` and `xmip-core-archive`
are driven by the Playground on a simulated clock; a node has no retention or
archive step and reads no `[retention]` table. Records: ADR-0040.

#### `storage-nodes`

**Storage nodes reached over mutual TLS.** `xmip-core-persist`'s Storage
client and server are built and tested; `xmip-service` serves no other node,
and refuses a node whose `[storage] nodes` lists any until its configuration
can name the identity it presents. Records: ADR-0056 (amendment 2026-10-01).

### Decided, not built

#### `arrival-validation`

**Holding a Stream to a named Contract.** A node refuses to start a Receive or
Send Location that names a Contract, in words: arrival holds no Stream to one
yet (`xmip-core-runtime`'s `startup.rs`). The contract technologies validate,
and the Playground holds its generated content to them in its own harness, not
at a node's Location. Records: ADR-0042, ADR-0031 (amendment 2026-10-05).

#### `artifact-steps`

**Prepare, Contract, Promote, Transform, Demote and Assignment on Ports,
Locations and Xmip Processes.** The keys are decided and none is read;
Assignment and Transformation have the Message's generations ready in
`xmip-core-message` and the runtime's `generation.rs`, with no caller outside
tests. Records: ADR-0031 (amendment 2026-10-05), runtime-model.md section 20.

#### `audit-through-storage`

**Audit written through Xmip Storage and kept by the audit keeper.** Xmip
Storage's `keep_audit` exists and is tested, and nothing calls it outside
tests; only publication and replay records reach the Ledger. The file sink is
what every program writes. Records: ADR-0062, deployment-model.md section 7.

#### `bounded-audit-channel`

**A bounded asynchronous audit channel with a capacity policy.** The keeper
`xmip-core-audit` runs is an unbounded queue on one thread, used by Event
delivery records alone, and a program's own record waits for it to drain; no
capacity, discard, sampling or back-pressure policy exists. Records:
audit-record.md, Performance.

#### `certificate-provisioning`

**Obtaining and renewing certificates (ACME, an internal authority).** Nothing
obtains or renews a certificate: there is no ACME client and no
`xmip-core-provision`, and the SDK has no ACME server. Certificates are files
an operator supplies. Open problem 27. Records: ADR-0034, ADR-0033.

#### `configuration-delivery`

**Delivering a slice to its node, its acceptance, and restarting only what
changed.** No Xmip path puts a slice on another node: the desktop delivers
only to the node it starts, a node answers no accepted or refused, and a save
is not versioned, watched for drift or applied by restarting only the threads
or Host Services that changed. Open problem 31. Records: ADR-0031 (amendments
2026-10-05).

#### `database-server`

**Xmip Storage in front of PostgreSQL or SQL Server.** `[storage.database]` is
read and checked, and IT's scripts are in `deploy/database`; no Storage node
connects to either server yet. Records: ADR-0015 (amendment 2026-10-01),
deployment-model.md section 7.

#### `other-runtime-module`

**A Module on another runtime.** A .NET Module in process, on threads, unless
excluded, and another runtime in a process of its own unless configuration
invites it in: no `InProcess` setting, no .NET hosting and no out-of-process
channel exist, and a Host Service of its own is refused at start. Records:
ADR-0018 (amendment 2026-10-05).

#### `process-execution`

**Compiling an Xmip Process at design time, and running it.** Nothing compiles
a design and no engine runs one: a Journey to an Xmip Process ends saying no
runtime runs it yet (`xmip-core-runtime`'s `departure.rs`). Records: ADR-0066,
runtime-model.md section 22.

#### `security-profile`

**Security profiles: standard, enterprise, regulated.** No configuration key
names a profile and nothing enforces identity isolation at start; the
isolation rule (`IdentityContext::may_share_host_process`) is called by its
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

Where each repository mounts and what it holds: 227308 lines of production
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
nowhere — work not begun, not work unmounted. There are 70 of them and they
hold no source to count.

```text
├── sdk                                          377
├── module/
│   ├── core/
│   │   ├── capability/
│   │   │   ├── transport                       4237
│   │   │   │   ├── amqp                        2556
│   │   │   │   ├── opc-ua                      2410
│   │   │   │   ├── nfs                         1983
│   │   │   │   ├── smb                         1941
│   │   │   │   ├── mssql                       1866
│   │   │   │   ├── mysql                       1765
│   │   │   │   ├── ibm-mq                      1742
│   │   │   │   ├── kafka                       1711
│   │   │   │   ├── http                        1630
│   │   │   │   ├── sftp                        1452
│   │   │   │   ├── snmp                        1421
│   │   │   │   ├── oracle                      1394
│   │   │   │   ├── postgresql                  1335
│   │   │   │   ├── nats-jetstream              1333
│   │   │   │   ├── as4                         1310
│   │   │   │   ├── canopen                     1135
│   │   │   │   ├── s7comm                      1128
│   │   │   │   ├── dns                         1112
│   │   │   │   ├── mqtt                        1068
│   │   │   │   ├── webdav                      1056
│   │   │   │   ├── iec-61850                   1031
│   │   │   │   ├── secs-gem                    1025
│   │   │   │   ├── ftp                          987
│   │   │   │   ├── imap                         981
│   │   │   │   ├── ethercat                     964
│   │   │   │   ├── dicom                        948
│   │   │   │   ├── as2                          940
│   │   │   │   ├── m-bus                        919
│   │   │   │   ├── aws-sns                      905
│   │   │   │   ├── hart                         901
│   │   │   │   ├── nats                         898
│   │   │   │   ├── uds                          892
│   │   │   │   ├── j1939                        885
│   │   │   │   ├── bluetooth                    878
│   │   │   │   ├── lorawan                      873
│   │   │   │   ├── activemq                     865
│   │   │   │   ├── aws-kinesis                  860
│   │   │   │   ├── ethernet-ip                  855
│   │   │   │   ├── pop3                         850
│   │   │   │   ├── azure-service-bus            840
│   │   │   │   ├── azure-event-grid             831
│   │   │   │   ├── profinet                     824
│   │   │   │   ├── redis-streams                820
│   │   │   │   ├── google-pub-sub               818
│   │   │   │   ├── wireless-hart                814
│   │   │   │   ├── dhcp                         806
│   │   │   │   ├── zigbee                       783
│   │   │   │   ├── thread                       780
│   │   │   │   ├── aws-sqs                      767
│   │   │   │   ├── peppol                       749
│   │   │   │   ├── knx                          732
│   │   │   │   ├── file                         721
│   │   │   │   ├── iso-tp                       695
│   │   │   │   ├── s3                           695
│   │   │   │   ├── azure-blob                   681
│   │   │   │   ├── mdns                         679
│   │   │   │   ├── cotp                         669
│   │   │   │   ├── io-link                      669
│   │   │   │   ├── google-cloud-storage         663
│   │   │   │   ├── dds                          655
│   │   │   │   ├── iec-60870-5-104              651
│   │   │   │   ├── smtp                         638
│   │   │   │   ├── msmq                         635
│   │   │   │   ├── syslog                       623
│   │   │   │   ├── obd-ii                       608
│   │   │   │   ├── dnp3                         602
│   │   │   │   ├── ssdp                         601
│   │   │   │   ├── coap                         564
│   │   │   │   ├── modbus                       528
│   │   │   │   ├── redpanda                     517
│   │   │   │   ├── wireless-m-bus               517
│   │   │   │   ├── azure-event-hubs             515
│   │   │   │   ├── aws                          513
│   │   │   │   ├── serial                       497
│   │   │   │   ├── ethernet                     482
│   │   │   │   ├── named-pipe                   476
│   │   │   │   ├── can-bus                      459
│   │   │   │   ├── sqlite                       456
│   │   │   │   ├── azure                        449
│   │   │   │   ├── websocket                    442
│   │   │   │   ├── bacnet                       441
│   │   │   │   ├── rabbitmq                     353
│   │   │   │   ├── unix-socket                  308
│   │   │   │   ├── mllp                         287
│   │   │   │   ├── udp                          201
│   │   │   │   └── tcp                          178
│   │   │   ├── authenticate                    2657
│   │   │   │   ├── saml                         947
│   │   │   │   ├── ntlm                         595
│   │   │   │   ├── kerberos                     569
│   │   │   │   ├── ldap                         488
│   │   │   │   ├── oauth2                       465
│   │   │   │   ├── digest                       445
│   │   │   │   ├── scram                        393
│   │   │   │   ├── windows                      377
│   │   │   │   ├── pam                          339
│   │   │   │   ├── ssh-key                      248
│   │   │   │   ├── oidc                         241
│   │   │   │   ├── jwt                          150
│   │   │   │   ├── certificate                  139
│   │   │   │   ├── api-key                       99
│   │   │   │   ├── bearer                        94
│   │   │   │   ├── mutual-tls                    89
│   │   │   │   ├── basic                         76
│   │   │   │   └── password                      68
│   │   │   ├── path                            2431
│   │   │   │   ├── jsonpath                     660
│   │   │   │   ├── fhirpath                     614
│   │   │   │   ├── dot                          291
│   │   │   │   ├── index                        158
│   │   │   │   ├── regex                        158
│   │   │   │   ├── json-pointer                  60
│   │   │   │   └── xpath                         49
│   │   │   ├── identify                        1437
│   │   │   │   ├── saml                         345
│   │   │   │   ├── api-key                      227
│   │   │   │   ├── dns                          195
│   │   │   │   ├── ip                           184
│   │   │   │   ├── username                     169
│   │   │   │   ├── jwt                          165
│   │   │   │   ├── ntlm                         155
│   │   │   │   ├── header                       148
│   │   │   │   ├── cookie                       130
│   │   │   │   ├── oidc                         126
│   │   │   │   ├── certificate                  124
│   │   │   │   ├── kerberos                     116
│   │   │   │   ├── transport                    109
│   │   │   │   ├── contract                      88
│   │   │   │   ├── party                         88
│   │   │   │   ├── endpoint                      82
│   │   │   │   ├── message                       81
│   │   │   │   ├── mac                           71
│   │   │   │   └── ssh-key                       63
│   │   │   ├── contract                         906
│   │   │   │   ├── graphql-schema               846
│   │   │   │   ├── xml-schema                   759
│   │   │   │   ├── avro                         748
│   │   │   │   ├── json-schema                  746
│   │   │   │   ├── toon                         711
│   │   │   │   ├── sql                          710
│   │   │   │   ├── protobuf                     691
│   │   │   │   ├── fixed-width                  512
│   │   │   │   ├── edi-edifact                  470
│   │   │   │   ├── edi-x12                      455
│   │   │   │   ├── wsdl                         390
│   │   │   │   ├── openapi                      385
│   │   │   │   ├── yaml                         368
│   │   │   │   ├── hl7-v2                       329
│   │   │   │   ├── toml                         314
│   │   │   │   ├── fhir                         294
│   │   │   │   ├── asyncapi                     243
│   │   │   │   ├── schematron                   239
│   │   │   │   ├── regex                        207
│   │   │   │   ├── csv                          140
│   │   │   │   ├── rust                          83
│   │   │   │   └── dotnet                        19
│   │   │   ├── route                            643
│   │   │   │   ├── metadata                     124
│   │   │   │   ├── contract                      86
│   │   │   │   ├── content                       80
│   │   │   │   ├── regex                         76
│   │   │   │   ├── party                         69
│   │   │   │   ├── header                        68
│   │   │   │   └── context                       47
│   │   │   ├── secret                           572
│   │   │   │   ├── dpapi                        315
│   │   │   │   ├── file                         207
│   │   │   │   ├── keychain                     106
│   │   │   │       declared, not built 5
│   │   │   │       aws-kms  azure-key-vault  keyring  pkcs11  vault
│   │   │   ├── authorize                        409
│   │   │   │   ├── location                     397
│   │   │   │   ├── abac                         359
│   │   │   │   ├── opa                          297
│   │   │   │   ├── cedar                        290
│   │   │   │   ├── policy                       249
│   │   │   │   ├── transport                    206
│   │   │   │   ├── role                         200
│   │   │   │   ├── artifact                     178
│   │   │   │   ├── claim                        168
│   │   │   │   ├── scope                        168
│   │   │   │   ├── rbac                         163
│   │   │   │   ├── acl                          147
│   │   │   │   ├── contract                     141
│   │   │   │   └── party                        131
│   │   │   ├── logic                            156
│   │   │   │   ├── matter                      1129
│   │   │   │   ├── soap                         274
│   │   │   │   ├── http-api                     259
│   │   │   │   └── grpc                         215
│   │   │   ├── resilience                       129
│   │   │   │   ├── circuit-breaker              135
│   │   │   │   ├── rate-limit                   108
│   │   │   │   ├── bulkhead                      83
│   │   │   │   ├── retry                         82
│   │   │   │   ├── timeout                       74
│   │   │   │   └── fallback                      66
│   │   │   ├── receive                          124
│   │   │   ├── demote                           108
│   │   │   ├── send                              88
│   │   │   ├── process                           42
│   │   │   │       declared, not built 7
│   │   │   │       bash  command  dotnet  grpc  http  rust  wasm
│   │   │   ├── assign                            39
│   │   │   ├── transform                         33
│   │   │   │       declared, not built 12
│   │   │   │       dotnet  handlebars  jolt  jq  jsonata  liquid  mustache
│   │   │   │       rust  tera  wasm  xquery  xslt
│   │   │   ├── prepare                           29
│   │   │   │       declared, not built 20
│   │   │   │       base64  bzip2  canonicalize  charset  checksum  chunking
│   │   │   │       decrypt  deflate  encrypt  envelope  framing  gzip  hash
│   │   │   │       line-ending  quoted-printable  sign  tar  verify-signature
│   │   │   │        zip  zstd
│   │   │   ├── retain                            27
│   │   │   │       declared, not built 5
│   │   │   │       azure-blob  file  gcs  s3  sql
│   │   │   └── promote                           10
│   │   ├── library/
│   │   │   ├── net                             4958
│   │   │   ├── codec                           2744
│   │   │   ├── ssh                             1559
│   │   │   ├── ntlm                             804
│   │   │   ├── tls                              657
│   │   │   └── asn1                             526
│   │   └── operation/
│   │       ├── cli                             6114
│   │       ├── gui                             5366
│   │       │   └── vscode                      1417
│   │       ├── observe                         3683
│   │       │   ├── otlp                         578
│   │       │   └── prometheus                   328
│   │       ├── powershell                      2594  C# 2594 · PowerShell 0
│   │       ├── audit                           1800
│   │       │       declared, not built 10
│   │       │       elasticsearch  file  kafka  mssql  opensearch  otlp
│   │       │       postgres  sqlite  syslog  windows-event-log
│   │       ├── archive                          632
│   │       │   ├── sql                          256
│   │       │   ├── file                         254
│   │       │   ├── azure-blob                   165
│   │       │   ├── s3                           155
│   │       │   ├── parquet                      147
│   │       │   ├── sqlite                       143
│   │       │   ├── gcs                          135
│   │       │   ├── mysql                         92
│   │       │   ├── postgresql                    77
│   │       │   └── mssql                         74
│   │       └── report                            18
│   │               declared, not built 6
│   │               csv  html  json  pdf  prometheus  sql
│   ├── foundation/
│   │   ├── abi                                24061  C# 22020 · Rust 1816 · PowerShell 225
│   │   ├── event                               5670
│   │   │       declared, not built 3
│   │   │       amqp  http  kafka
│   │   ├── core                                1964
│   │   ├── message                             1532
│   │   │   ├── xml                              348
│   │   │   ├── avro                             300
│   │   │   ├── json                             256
│   │   │   ├── protobuf                         173
│   │   │   ├── csv                              150
│   │   │   ├── fixed-width                      105
│   │   │   ├── multipart                         98
│   │   │   ├── hl7-er7                           93
│   │   │   ├── form-urlencoded                   92
│   │   │   ├── edi-x12                           77
│   │   │   ├── edi-edifact                       75
│   │   │   ├── ubl                               67
│   │   │   ├── text                              58
│   │   │   ├── edi-tradacoms                     55
│   │   │   └── binary                            38
│   │   ├── node                                 831
│   │   ├── context                              750
│   │   ├── journey                              569
│   │   ├── stream                               232
│   │   ├── party                                186
│   │   └── cluster                               21
│   └── platform/
│       ├── runtime                            17341
│       ├── persist                             4933
│       │   ├── sqlite                           140
│       │   └── rocksdb                          136
│       └── configure                           3374
└── test/
    └── core/
        └── playground                          9982
```

---

## Foundation

Things Xmip is.

| Repository | Maturity | Mount | Technologies |
| --- | --- | --- | ---: |
| `xmip-core` | scaffolded | `module/foundation/core` | — |
| `xmip-core-abi` | scaffolded | `module/foundation/abi` | — |
| `xmip-core-cluster` | scaffolded | `module/foundation/cluster` | — |
| `xmip-core-context` | scaffolded | `module/foundation/context` | — |
| `xmip-core-event` | scaffolded | `module/foundation/event` | 3 |
| `xmip-core-journey` | scaffolded | `module/foundation/journey` | — |
| `xmip-core-message` | scaffolded | `module/foundation/message` | 15 |
| `xmip-core-node` | scaffolded | `module/foundation/node` | — |
| `xmip-core-party` | scaffolded | `module/foundation/party` | — |
| `xmip-core-sdk` | scaffolded | `sdk` | — |
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
| `xmip-core-library` | reserved | not mounted | 6 |

### `xmip-core-library`, 6 technologies

The parent is not composed here, so what it composes cannot be read; every
technology below is declared only.

- **scaffolded**, 6 — asn1, codec, net, ntlm, ssh, tls

---

## Capability

Things Xmip does.

| Repository | Maturity | Mount | Technologies |
| --- | --- | --- | ---: |
| `xmip-core-assign` | scaffolded | `module/core/capability/assign` | — |
| `xmip-core-authenticate` | scaffolded | `module/core/capability/authenticate` | 18 |
| `xmip-core-authorize` | scaffolded | `module/core/capability/authorize` | 14 |
| `xmip-core-contract` | scaffolded | `module/core/capability/contract` | 22 |
| `xmip-core-demote` | scaffolded | `module/core/capability/demote` | — |
| `xmip-core-identify` | scaffolded | `module/core/capability/identify` | 19 |
| `xmip-core-logic` | scaffolded | `module/core/capability/logic` | 4 |
| `xmip-core-path` | scaffolded | `module/core/capability/path` | 7 |
| `xmip-core-prepare` | scaffolded | `module/core/capability/prepare` | 20 |
| `xmip-core-process` | scaffolded | `module/core/capability/process` | 7 |
| `xmip-core-promote` | scaffolded | `module/core/capability/promote` | — |
| `xmip-core-receive` | scaffolded | `module/core/capability/receive` | — |
| `xmip-core-resilience` | scaffolded | `module/core/capability/resilience` | 6 |
| `xmip-core-retain` | scaffolded | `module/core/capability/retain` | 5 |
| `xmip-core-route` | scaffolded | `module/core/capability/route` | 7 |
| `xmip-core-secret` | scaffolded | `module/core/capability/secret` | 8 |
| `xmip-core-send` | scaffolded | `module/core/capability/send` | — |
| `xmip-core-transform` | scaffolded | `module/core/capability/transform` | 12 |
| `xmip-core-transport` | scaffolded | `module/core/capability/transport` | 86 |

### `xmip-core-authenticate`, 18 technologies

All 18 composed in `module/core/capability/authenticate`.

- **scaffolded**, 18 — api-key, basic, bearer, certificate, digest, jwt,
  kerberos, ldap, mutual-tls, ntlm, oauth2, oidc, pam, password, saml, scram,
  ssh-key, windows

### `xmip-core-authorize`, 14 technologies

All 14 composed in `module/core/capability/authorize`.

- **scaffolded**, 14 — abac, acl, artifact, cedar, claim, contract, location,
  opa, party, policy, rbac, role, scope, transport

### `xmip-core-contract`, 22 technologies

All 22 composed in `module/core/capability/contract`.

- **scaffolded**, 22 — asyncapi, avro, csv, dotnet, edi-edifact, edi-x12,
  fhir, fixed-width, graphql-schema, hl7-v2, json-schema, openapi, protobuf,
  regex, rust, schematron, sql, toml, toon, wsdl, xml-schema, yaml

### `xmip-core-identify`, 19 technologies

All 19 composed in `module/core/capability/identify`.

- **scaffolded**, 19 — api-key, certificate, contract, cookie, dns, endpoint,
  header, ip, jwt, kerberos, mac, message, ntlm, oidc, party, saml, ssh-key,
  transport, username

### `xmip-core-logic`, 4 technologies

All 4 composed in `module/core/capability/logic`.

- **scaffolded**, 4 — grpc, http-api, matter, soap

### `xmip-core-path`, 7 technologies

All 7 composed in `module/core/capability/path`.

- **scaffolded**, 7 — dot, fhirpath, index, json-pointer, jsonpath, regex,
  xpath

### `xmip-core-prepare`, 20 technologies

Declared, and none composed: `module/core/capability/prepare` has no
`.gitmodules`.

- **reserved**, 20 — base64, bzip2, canonicalize, charset, checksum, chunking,
  decrypt, deflate, encrypt, envelope, framing, gzip, hash, line-ending,
  quoted-printable, sign, tar, verify-signature, zip, zstd

### `xmip-core-process`, 7 technologies

Declared, and none composed: `module/core/capability/process` has no
`.gitmodules`.

- **reserved**, 7 — bash, command, dotnet, grpc, http, rust, wasm

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

### `xmip-core-transform`, 12 technologies

Declared, and none composed: `module/core/capability/transform` has no
`.gitmodules`.

- **reserved**, 12 — dotnet, handlebars, jolt, jq, jsonata, liquid, mustache,
  rust, tera, wasm, xquery, xslt

### `xmip-core-transport`, 86 technologies

All 86 composed in `module/core/capability/transport`.

- **scaffolded**, 86 — activemq, amqp, as2, as4, aws, aws-kinesis, aws-sns,
  aws-sqs, azure, azure-blob, azure-event-grid, azure-event-hubs,
  azure-service-bus, bacnet, bluetooth, can-bus, canopen, coap, cotp, dds,
  dhcp, dicom, dnp3, dns, ethercat, ethernet, ethernet-ip, file, ftp,
  google-cloud-storage, google-pub-sub, hart, http, ibm-mq, iec-60870-5-104,
  iec-61850, imap, io-link, iso-tp, j1939, kafka, knx, lorawan, m-bus, mdns,
  mllp, modbus, mqtt, msmq, mssql, mysql, named-pipe, nats, nats-jetstream,
  nfs, obd-ii, opc-ua, oracle, peppol, pop3, postgresql, profinet, rabbitmq,
  redis-streams, redpanda, s3, s7comm, secs-gem, serial, sftp, smb, smtp,
  snmp, sqlite, ssdp, syslog, tcp, thread, udp, uds, unix-socket, webdav,
  websocket, wireless-hart, wireless-m-bus, zigbee

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
| `xmip-core-test` | reserved | not mounted | 1 |

### `xmip-core-archive`, 10 technologies

All 10 composed in `module/core/operation/archive`.

- **scaffolded**, 10 — azure-blob, file, gcs, mssql, mysql, parquet,
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

### `xmip-core-test`, one technology

The parent is not composed here, so what it composes cannot be read; every
technology below is declared only.

- **scaffolded**, 1 — playground

---

## Platform

Platform-wide runtime services.

| Repository | Maturity | Mount | Technologies |
| --- | --- | --- | ---: |
| `xmip-core-configure` | scaffolded | `module/platform/configure` | — |
| `xmip-core-persist` | scaffolded | `module/platform/persist` | 2 |
| `xmip-core-runtime` | scaffolded | `module/platform/runtime` | — |

### `xmip-core-persist`, 2 technologies

All 2 composed in `module/platform/persist`.

- **scaffolded**, 2 — rocksdb, sqlite

---
