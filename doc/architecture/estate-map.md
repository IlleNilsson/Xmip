# The Xmip estate

334 repositories are declared and 257 of them are
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
| Foundation | 14 | 14 | 0 |
| Capability | 18 | 18 | 0 |
| Operation | 9 | 8 | 1 |
| Platform | 3 | 3 | 0 |
| Technology | 290 | 214 | 76 |
| **Total** | 334 | 257 | 77 |

| Maturity | Declared | Mounted | Not mounted |
| --- | ---: | ---: | ---: |
| reserved | 77 | 0 | 77 |
| scaffolded | 257 | 257 | 0 |

**Mounted means composed as a submodule, and composition happens at two
levels** (ADR-0016, amended 2026-09-07). The root `.gitmodules` composes
the modules under `module/`, `test/` and `template/`. A technology is
composed by its own parent capability, inside that repository, so the
root cannot see it and this map reads each parent as well. A technology
reported as not mounted is one its parent does not compose — not one
the root forgot.

---

## The tree

Where each repository mounts and what it holds: 145388 lines of production
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
nowhere — work not begun, not work unmounted. There are 77 of them and they
hold no source to count.

```text
├── module/
│   ├── capability/
│   │   ├── authenticate                        2033
│   │   │   ├── saml                             989
│   │   │   ├── kerberos                         830
│   │   │   ├── ntlm                             798
│   │   │   ├── oauth2                           604
│   │   │   ├── ldap                             550
│   │   │   ├── oidc                             510
│   │   │   ├── ssh-key                          509
│   │   │   ├── digest                           477
│   │   │   ├── jwt                              431
│   │   │   ├── windows                          406
│   │   │   ├── scram                            405
│   │   │   ├── pam                              352
│   │   │   ├── api-key                          240
│   │   │   ├── bearer                           210
│   │   │   ├── certificate                      160
│   │   │   ├── mutual-tls                        97
│   │   │   ├── basic                             86
│   │   │   └── password                          81
│   │   ├── transport                           1727
│   │   │   ├── opc-ua                          2380
│   │   │   ├── sftp                            2189
│   │   │   ├── mssql                           2143
│   │   │   ├── mysql                           1833
│   │   │   ├── smb                             1724
│   │   │   ├── http                            1604
│   │   │   ├── nfs                             1585
│   │   │   ├── rabbitmq                        1567
│   │   │   ├── snmp                            1417
│   │   │   ├── oracle                          1312
│   │   │   ├── ibm-mq                          1277
│   │   │   ├── ethercat                        1258
│   │   │   ├── postgresql                      1258
│   │   │   ├── webdav                          1178
│   │   │   ├── kafka                           1165
│   │   │   ├── as4                             1100
│   │   │   ├── amqp                            1097
│   │   │   ├── nats-jetstream                  1069
│   │   │   ├── s7comm                          1021
│   │   │   ├── io-link                         1015
│   │   │   ├── iec-61850                        968
│   │   │   ├── m-bus                            926
│   │   │   ├── canopen                          905
│   │   │   ├── activemq                         891
│   │   │   ├── dicom                            887
│   │   │   ├── peppol                           882
│   │   │   ├── lorawan                          874
│   │   │   ├── hart                             872
│   │   │   ├── secs-gem                         854
│   │   │   ├── mdns                             848
│   │   │   ├── bluetooth                        844
│   │   │   ├── uds                              822
│   │   │   ├── wireless-hart                    811
│   │   │   ├── aws-kinesis                      804
│   │   │   ├── azure-event-grid                 792
│   │   │   ├── aws-sns                          791
│   │   │   ├── ethernet-ip                      791
│   │   │   ├── mqtt                             789
│   │   │   ├── dhcp                             780
│   │   │   ├── j1939                            756
│   │   │   ├── dns                              749
│   │   │   ├── as2                              734
│   │   │   ├── azure-blob                       730
│   │   │   ├── profinet                         730
│   │   │   ├── thread                           729
│   │   │   ├── redis-streams                    718
│   │   │   ├── ftp                              710
│   │   │   ├── imap                             699
│   │   │   ├── azure-service-bus                690
│   │   │   ├── google-pub-sub                   688
│   │   │   ├── knx                              687
│   │   │   ├── cotp                             667
│   │   │   ├── zigbee                           667
│   │   │   ├── nats                             661
│   │   │   ├── aws-sqs                          644
│   │   │   ├── coap                             635
│   │   │   ├── iso-tp                           611
│   │   │   ├── dds                              603
│   │   │   ├── redpanda                         594
│   │   │   ├── pop3                             585
│   │   │   ├── obd-ii                           582
│   │   │   ├── msmq                             573
│   │   │   ├── wireless-m-bus                   560
│   │   │   ├── s3                               557
│   │   │   ├── google-cloud-storage             556
│   │   │   ├── websocket                        543
│   │   │   ├── ssdp                             526
│   │   │   ├── syslog                           518
│   │   │   ├── smtp                             487
│   │   │   ├── named-pipe                       475
│   │   │   ├── azure-event-hubs                 471
│   │   │   ├── ethernet                         468
│   │   │   ├── iec-60870-5-104                  432
│   │   │   ├── dnp3                             421
│   │   │   ├── sqlite                           373
│   │   │   ├── unix-socket                      327
│   │   │   ├── can-bus                          320
│   │   │   ├── modbus                           317
│   │   │   ├── serial                           303
│   │   │   ├── bacnet                           258
│   │   │   ├── mllp                             226
│   │   │   ├── udp                              176
│   │   │   ├── file                             148
│   │   │   └── tcp                              131
│   │   ├── identify                            1278
│   │   │   ├── saml                             350
│   │   │   ├── kerberos                         331
│   │   │   ├── ntlm                             273
│   │   │   ├── api-key                          255
│   │   │   ├── dns                              195
│   │   │   ├── ip                               187
│   │   │   ├── username                         171
│   │   │   ├── jwt                              169
│   │   │   ├── header                           148
│   │   │   ├── certificate                      136
│   │   │   ├── cookie                           131
│   │   │   ├── oidc                             127
│   │   │   ├── transport                        109
│   │   │   ├── ssh-key                           90
│   │   │   ├── contract                          88
│   │   │   ├── party                             88
│   │   │   ├── mac                               86
│   │   │   ├── endpoint                          82
│   │   │   └── message                           81
│   │   ├── route                                879
│   │   │   ├── content                          101
│   │   │   ├── expression                       101
│   │   │   ├── metadata                         101
│   │   │   ├── party                             80
│   │   │   ├── header                            78
│   │   │   ├── contract                          75
│   │   │   ├── regex                             74
│   │   │   └── context                           53
│   │   ├── contract                             472  Rust 366 · PowerShell 106
│   │   │   ├── graphql-schema                   872
│   │   │   ├── sql                              774
│   │   │   ├── xml-schema                       745
│   │   │   ├── avro                             714
│   │   │   ├── toon                             702
│   │   │   ├── protobuf                         690
│   │   │   ├── json-schema                      593
│   │   │   ├── fixed-width                      495
│   │   │   ├── edi-edifact                      452
│   │   │   ├── schematron                       438
│   │   │   ├── edi-x12                          437
│   │   │   ├── wsdl                             373
│   │   │   ├── openapi                          359
│   │   │   ├── yaml                             351
│   │   │   ├── hl7-v2                           312
│   │   │   ├── toml                             297
│   │   │   ├── fhir                             273
│   │   │   ├── rust                             253
│   │   │   ├── asyncapi                         223
│   │   │   ├── regex                            165
│   │   │   ├── java                             113
│   │   │   ├── csv                              112
│   │   │   ├── python                           100
│   │   │   ├── go                                57
│   │   │   ├── c                                 29
│   │   │   ├── cpp                               29
│   │   │   └── dotnet                            19
│   │   ├── authorize                            321
│   │   │   ├── opa                              454
│   │   │   ├── location                         395
│   │   │   ├── abac                             360
│   │   │   ├── cedar                            290
│   │   │   ├── policy                           249
│   │   │   ├── role                             226
│   │   │   ├── artifact                         215
│   │   │   ├── transport                        205
│   │   │   ├── acl                              178
│   │   │   ├── contract                         176
│   │   │   ├── claim                            173
│   │   │   ├── scope                            172
│   │   │   ├── rbac                             166
│   │   │   └── party                            131
│   │   ├── path                                 299
│   │   │   ├── fhirpath                         749
│   │   │   ├── jsonpath                         741
│   │   │   ├── predicate                        582
│   │   │   ├── dot                              355
│   │   │   ├── xpath                            255
│   │   │   ├── regex                            253
│   │   │   ├── index                            216
│   │   │   └── json-pointer                     144
│   │   ├── resilience                           204
│   │   │   ├── circuit-breaker                  135
│   │   │   ├── rate-limit                       108
│   │   │   ├── retry                             88
│   │   │   ├── bulkhead                          83
│   │   │   ├── timeout                           80
│   │   │   └── fallback                          66
│   │   ├── receive                              173
│   │   ├── logic                                152
│   │   │   ├── matter                          1142
│   │   │   ├── soap                             272
│   │   │   ├── http-api                         257
│   │   │   └── grpc                             212
│   │   ├── send                                 143
│   │   ├── demote                                82
│   │   ├── promote                               48
│   │   ├── process                               40
│   │   │       declared, not built 14
│   │   │       bash  c  command  cpp  dotnet  go  grpc  http  java  lua
│   │   │       powershell  python  rust  wasm
│   │   ├── prepare                               29
│   │   │       declared, not built 20
│   │   │       base64  bzip2  canonicalize  charset  checksum  chunking
│   │   │       decrypt  deflate  encrypt  envelope  framing  gzip  hash
│   │   │       line-ending  quoted-printable  sign  tar  verify-signature
│   │   │       zip  zstd
│   │   ├── transform                             29
│   │   │       declared, not built 17
│   │   │       c  cpp  dotnet  go  handlebars  java  jolt  jq  jsonata
│   │   │       liquid  mustache  python  rust  tera  wasm  xquery  xslt
│   │   ├── assign                                28
│   │   └── retain                                27
│   │           declared, not built 5
│   │           azure-blob  file  gcs  s3  sql
│   ├── foundation/
│   │   ├── abi                                 8060  C# 7225 · Rust 835
│   │   ├── message                             1048
│   │   │   ├── xml                              335
│   │   │   ├── protobuf                         332
│   │   │   ├── avro                             304
│   │   │   ├── json                             254
│   │   │   ├── multipart                        194
│   │   │   ├── csv                              149
│   │   │   ├── fixed-width                      105
│   │   │   ├── form-urlencoded                  100
│   │   │   ├── hl7-er7                           93
│   │   │   ├── edi-x12                           77
│   │   │   ├── edi-edifact                       75
│   │   │   ├── ubl                               67
│   │   │   ├── text                              58
│   │   │   ├── edi-tradacoms                     55
│   │   │   └── binary                            38
│   │   ├── core                                 902
│   │   ├── asn1                                 415
│   │   ├── context                              345
│   │   ├── journey                              344
│   │   ├── tls                                  219
│   │   ├── node                                 210
│   │   ├── party                                186
│   │   ├── net                                  164
│   │   ├── codec                                126
│   │   ├── stream                                38
│   │   ├── cluster                               21
│   │   └── event                                 20
│   ├── operation/
│   │   ├── cli                                 3054
│   │   ├── gui                                 1686
│   │   │   └── vscode                           698
│   │   ├── powershell                          1656  C# 1060 · PowerShell 596
│   │   ├── observe                              561
│   │   │       declared, not built 5
│   │   │       etw  journald  otlp  prometheus  windows-event-log
│   │   ├── archive                              461
│   │   │   ├── sql                              320
│   │   │   ├── file                             315
│   │   │   ├── mysql                            191
│   │   │   ├── postgresql                       181
│   │   │   ├── mssql                            180
│   │   │   ├── azure-blob                       165
│   │   │   ├── s3                               155
│   │   │   ├── parquet                          147
│   │   │   ├── gcs                              135
│   │   │   └── sqlite                           133
│   │   ├── audit                                 89
│   │   │       declared, not built 9
│   │   │       elasticsearch  file  kafka  mssql  opensearch  otlp  postgres
│   │   │       sqlite  syslog
│   │   └── report                                18
│   │           declared, not built 6
│   │           csv  html  json  pdf  prometheus  sql
│   └── platform/
│       ├── runtime                             3221
│       ├── configure                            198
│       └── persist                               93
└── test/
    └── playground                              9475
```

---

## Foundation

Things Xmip is.

| Repository | Maturity | Mount | Technologies |
| --- | --- | --- | ---: |
| `xmip-core` | scaffolded | `module/foundation/core` | — |
| `xmip-core-abi` | scaffolded | `module/foundation/abi` | — |
| `xmip-core-asn1` | scaffolded | `module/foundation/asn1` | — |
| `xmip-core-cluster` | scaffolded | `module/foundation/cluster` | — |
| `xmip-core-codec` | scaffolded | `module/foundation/codec` | — |
| `xmip-core-context` | scaffolded | `module/foundation/context` | — |
| `xmip-core-event` | scaffolded | `module/foundation/event` | — |
| `xmip-core-journey` | scaffolded | `module/foundation/journey` | — |
| `xmip-core-message` | scaffolded | `module/foundation/message` | 15 |
| `xmip-core-net` | scaffolded | `module/foundation/net` | — |
| `xmip-core-node` | scaffolded | `module/foundation/node` | — |
| `xmip-core-party` | scaffolded | `module/foundation/party` | — |
| `xmip-core-stream` | scaffolded | `module/foundation/stream` | — |
| `xmip-core-tls` | scaffolded | `module/foundation/tls` | — |

### `xmip-core-message`, 15 technologies

All 15 composed in `module/foundation/message`.

- **scaffolded**, 15 — avro, binary, csv, edi-edifact, edi-tradacoms, edi-x12,
  fixed-width, form-urlencoded, hl7-er7, json, multipart, protobuf, text, ubl,
  xml

---

## Capability

Things Xmip does.

| Repository | Maturity | Mount | Technologies |
| --- | --- | --- | ---: |
| `xmip-core-assign` | scaffolded | `module/capability/assign` | — |
| `xmip-core-authenticate` | scaffolded | `module/capability/authenticate` | 18 |
| `xmip-core-authorize` | scaffolded | `module/capability/authorize` | 14 |
| `xmip-core-contract` | scaffolded | `module/capability/contract` | 27 |
| `xmip-core-demote` | scaffolded | `module/capability/demote` | — |
| `xmip-core-identify` | scaffolded | `module/capability/identify` | 19 |
| `xmip-core-logic` | scaffolded | `module/capability/logic` | 4 |
| `xmip-core-path` | scaffolded | `module/capability/path` | 8 |
| `xmip-core-prepare` | scaffolded | `module/capability/prepare` | 20 |
| `xmip-core-process` | scaffolded | `module/capability/process` | 14 |
| `xmip-core-promote` | scaffolded | `module/capability/promote` | — |
| `xmip-core-receive` | scaffolded | `module/capability/receive` | — |
| `xmip-core-resilience` | scaffolded | `module/capability/resilience` | 6 |
| `xmip-core-retain` | scaffolded | `module/capability/retain` | 5 |
| `xmip-core-route` | scaffolded | `module/capability/route` | 8 |
| `xmip-core-send` | scaffolded | `module/capability/send` | — |
| `xmip-core-transform` | scaffolded | `module/capability/transform` | 17 |
| `xmip-core-transport` | scaffolded | `module/capability/transport` | 84 |

### `xmip-core-authenticate`, 18 technologies

All 18 composed in `module/capability/authenticate`.

- **scaffolded**, 18 — api-key, basic, bearer, certificate, digest, jwt,
  kerberos, ldap, mutual-tls, ntlm, oauth2, oidc, pam, password, saml, scram,
  ssh-key, windows

### `xmip-core-authorize`, 14 technologies

All 14 composed in `module/capability/authorize`.

- **scaffolded**, 14 — abac, acl, artifact, cedar, claim, contract, location,
  opa, party, policy, rbac, role, scope, transport

### `xmip-core-contract`, 27 technologies

All 27 composed in `module/capability/contract`.

- **scaffolded**, 27 — asyncapi, avro, c, cpp, csv, dotnet, edi-edifact,
  edi-x12, fhir, fixed-width, go, graphql-schema, hl7-v2, java, json-schema,
  openapi, protobuf, python, regex, rust, schematron, sql, toml, toon, wsdl,
  xml-schema, yaml

### `xmip-core-identify`, 19 technologies

All 19 composed in `module/capability/identify`.

- **scaffolded**, 19 — api-key, certificate, contract, cookie, dns, endpoint,
  header, ip, jwt, kerberos, mac, message, ntlm, oidc, party, saml, ssh-key,
  transport, username

### `xmip-core-logic`, 4 technologies

All 4 composed in `module/capability/logic`.

- **scaffolded**, 4 — grpc, http-api, matter, soap

### `xmip-core-path`, 8 technologies

All 8 composed in `module/capability/path`.

- **scaffolded**, 8 — dot, fhirpath, index, json-pointer, jsonpath, predicate,
  regex, xpath

### `xmip-core-prepare`, 20 technologies

Declared, and none composed: `module/capability/prepare` has no `.gitmodules`.

- **reserved**, 20 — base64, bzip2, canonicalize, charset, checksum, chunking,
  decrypt, deflate, encrypt, envelope, framing, gzip, hash, line-ending,
  quoted-printable, sign, tar, verify-signature, zip, zstd

### `xmip-core-process`, 14 technologies

Declared, and none composed: `module/capability/process` has no `.gitmodules`.

- **reserved**, 14 — bash, c, command, cpp, dotnet, go, grpc, http, java, lua,
  powershell, python, rust, wasm

### `xmip-core-resilience`, 6 technologies

All 6 composed in `module/capability/resilience`.

- **scaffolded**, 6 — bulkhead, circuit-breaker, fallback, rate-limit, retry,
  timeout

### `xmip-core-retain`, 5 technologies

Declared, and none composed: `module/capability/retain` has no `.gitmodules`.

- **reserved**, 5 — azure-blob, file, gcs, s3, sql

### `xmip-core-route`, 8 technologies

All 8 composed in `module/capability/route`.

- **scaffolded**, 8 — content, context, contract, expression, header,
  metadata, party, regex

### `xmip-core-transform`, 17 technologies

Declared, and none composed: `module/capability/transform` has no
`.gitmodules`.

- **reserved**, 17 — c, cpp, dotnet, go, handlebars, java, jolt, jq, jsonata,
  liquid, mustache, python, rust, tera, wasm, xquery, xslt

### `xmip-core-transport`, 84 technologies

All 84 composed in `module/capability/transport`.

- **scaffolded**, 84 — activemq, amqp, as2, as4, aws-kinesis, aws-sns,
  aws-sqs, azure-blob, azure-event-grid, azure-event-hubs, azure-service-bus,
  bacnet, bluetooth, can-bus, canopen, coap, cotp, dds, dhcp, dicom, dnp3,
  dns, ethercat, ethernet, ethernet-ip, file, ftp, google-cloud-storage,
  google-pub-sub, hart, http, ibm-mq, iec-60870-5-104, iec-61850, imap,
  io-link, iso-tp, j1939, kafka, knx, lorawan, m-bus, mdns, mllp, modbus,
  mqtt, msmq, mssql, mysql, named-pipe, nats, nats-jetstream, nfs, obd-ii,
  opc-ua, oracle, peppol, pop3, postgresql, profinet, rabbitmq, redis-streams,
  redpanda, s3, s7comm, secs-gem, serial, sftp, smb, smtp, snmp, sqlite, ssdp,
  syslog, tcp, thread, udp, uds, unix-socket, webdav, websocket,
  wireless-hart, wireless-m-bus, zigbee

---

## Operation

Running and governing Xmip.

| Repository | Maturity | Mount | Technologies |
| --- | --- | --- | ---: |
| `xmip-core-archive` | scaffolded | `module/operation/archive` | 10 |
| `xmip-core-audit` | scaffolded | `module/operation/audit` | 9 |
| `xmip-core-cli` | scaffolded | `module/operation/cli` | — |
| `xmip-core-gui` | scaffolded | `module/operation/gui` | 1 |
| `xmip-core-observe` | scaffolded | `module/operation/observe` | 5 |
| `xmip-core-powershell` | scaffolded | `module/operation/powershell` | — |
| `xmip-core-report` | scaffolded | `module/operation/report` | 6 |
| `xmip-test` | reserved | not mounted | — |
| `xmip-test-playground` | scaffolded | `test/playground` | — |

### `xmip-core-archive`, 10 technologies

All 10 composed in `module/operation/archive`.

- **scaffolded**, 10 — azure-blob, file, gcs, mssql, mysql, parquet,
  postgresql, s3, sql, sqlite

### `xmip-core-audit`, 9 technologies

Declared, and none composed: `module/operation/audit` has no `.gitmodules`.

- **reserved**, 9 — elasticsearch, file, kafka, mssql, opensearch, otlp,
  postgres, sqlite, syslog

### `xmip-core-gui`, one technology

Composed in `module/operation/gui`.

- **scaffolded**, 1 — vscode

### `xmip-core-observe`, 5 technologies

Declared, and none composed: `module/operation/observe` has no `.gitmodules`.

- **reserved**, 5 — etw, journald, otlp, prometheus, windows-event-log

### `xmip-core-report`, 6 technologies

Declared, and none composed: `module/operation/report` has no `.gitmodules`.

- **reserved**, 6 — csv, html, json, pdf, prometheus, sql

---

## Platform

Platform-wide runtime services.

| Repository | Maturity | Mount | Technologies |
| --- | --- | --- | ---: |
| `xmip-core-configure` | scaffolded | `module/platform/configure` | — |
| `xmip-core-persist` | scaffolded | `module/platform/persist` | — |
| `xmip-core-runtime` | scaffolded | `module/platform/runtime` | — |

---

## Retired

Named here because a reader who remembers one of these and cannot find
it above should be told what happened to it. Each says whether its
GitHub repository was kept or deleted.

- **`xmip-core-exclusiveness`**, 2026-08-27 — ADR-0024. ResourceClaim in
  xmip-core-transport replaces it. The GitHub repository was deleted on
  2026-09-21 on the owner's word — nothing is released, and ADR-0017 and
  ADR-0024 keep the record of why it existed and why it went.

- **`xmip-core-webapi`**, 2026-09-06 — ADR-0014 amendment 2026-08-26. The web
  API belongs to the Logic axis (xmip-core-logic-http-api over
  xmip-core-transport-http), not a module of its own; it was declared, mounted
  nowhere, and deprecated. The GitHub repository was deleted on 2026-09-22 on
  the owner's word; xmip-core-logic-http-api is the web API, and ADR-0014
  keeps the record of why.

- **`xmip-core-migrate`**, 2026-09-19 — ADR-0058 amendment 2026-09-19, on the
  owner's instruction. One lib.rs with no implementation and no consumer; a
  name the estate paid for on every clone, landing and survey. The GitHub
  repository is retained by the owner's rule of 2026-09-22 as the only home
  for Xmip's own migration code — moving integrations from other platforms
  onto Xmip; none has been written yet. A third party may keep its own under
  its own provider name (ADR-0011). The first of it brings the mount back.

- **`xmip-core-schedule`**, 2026-09-19 — ADR-0058 amendment 2026-09-19, on the
  owner's instruction. Six lines and no public API; clause 7 of that record
  kept it and the amendment supersedes clause 7. The GitHub repository is
  retained by the owner's rule of 2026-09-22, and it is the only home for
  Xmip's own scheduling code — what decides when work runs: a timer, an
  interval, a polled pickup; none has been written yet. A third party may keep
  its own under its own provider name (ADR-0011). The first of it brings the
  mount back.

- **`xmip-core-diagnose`**, 2026-09-19 — ADR-0058 amendment 2026-09-19, on the
  owner's instruction. One lib.rs with no implementation and no consumer. The
  GitHub repository is retained by the owner's rule of 2026-09-22, and it is
  the only home for Xmip's own diagnosis code — explaining why a running node,
  Journey or endpoint is in the state it is; none has been written yet. A
  third party may keep its own under its own provider name (ADR-0011).
  ADR-0025 names diagnosis as an Operation capability. The first of it brings
  the mount back.
