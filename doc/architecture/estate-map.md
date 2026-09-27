# The Xmip estate

350 repositories are declared and 268 of them are
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
| Technology | 308 | 228 | 80 |
| **Total** | 350 | 268 | 82 |

| Maturity | Declared | Mounted | Not mounted |
| --- | ---: | ---: | ---: |
| reserved | 82 | 0 | 82 |
| scaffolded | 268 | 268 | 0 |

**Mounted means composed as a submodule, and composition happens at two
levels** (ADR-0016, amended 2026-09-07). The root `.gitmodules` composes
the modules under `module/`, `test/` and `template/`. A technology is
composed by its own parent capability, inside that repository, so the
root cannot see it and this map reads each parent as well. A technology
reported as not mounted is one its parent does not compose — not one
the root forgot.

---

## The tree

Where each repository mounts and what it holds: 178625 lines of production
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
nowhere — work not begun, not work unmounted. There are 82 of them and they
hold no source to count.

```text
├── sdk                                          377
├── module/
│   ├── core/
│   │   ├── capability/
│   │   │   ├── authenticate                    2623
│   │   │   │   ├── saml                         953
│   │   │   │   ├── ntlm                         604
│   │   │   │   ├── kerberos                     581
│   │   │   │   ├── ldap                         518
│   │   │   │   ├── oauth2                       471
│   │   │   │   ├── digest                       464
│   │   │   │   ├── ssh-key                      414
│   │   │   │   ├── scram                        405
│   │   │   │   ├── windows                      405
│   │   │   │   ├── pam                          351
│   │   │   │   ├── oidc                         247
│   │   │   │   ├── jwt                          156
│   │   │   │   ├── certificate                  147
│   │   │   │   ├── api-key                      105
│   │   │   │   ├── bearer                       100
│   │   │   │   ├── mutual-tls                    97
│   │   │   │   ├── basic                         88
│   │   │   │   └── password                      80
│   │   │   ├── transport                       2575
│   │   │   │   ├── opc-ua                      2375
│   │   │   │   ├── amqp                        2343
│   │   │   │   ├── mssql                       2115
│   │   │   │   ├── sftp                        2031
│   │   │   │   ├── mysql                       1722
│   │   │   │   ├── smb                         1680
│   │   │   │   ├── nfs                         1650
│   │   │   │   ├── kafka                       1606
│   │   │   │   ├── snmp                        1416
│   │   │   │   ├── oracle                      1333
│   │   │   │   ├── ibm-mq                      1331
│   │   │   │   ├── postgresql                  1274
│   │   │   │   ├── nats-jetstream              1154
│   │   │   │   ├── canopen                     1122
│   │   │   │   ├── http                        1117
│   │   │   │   ├── as4                         1106
│   │   │   │   ├── s7comm                      1084
│   │   │   │   ├── io-link                     1070
│   │   │   │   ├── iec-61850                   1008
│   │   │   │   ├── dicom                        965
│   │   │   │   ├── dns                          956
│   │   │   │   ├── ethercat                     949
│   │   │   │   ├── peppol                       941
│   │   │   │   ├── webdav                       935
│   │   │   │   ├── activemq                     911
│   │   │   │   ├── secs-gem                     904
│   │   │   │   ├── m-bus                        899
│   │   │   │   ├── hart                         882
│   │   │   │   ├── mqtt                         860
│   │   │   │   ├── wireless-hart                859
│   │   │   │   ├── bluetooth                    855
│   │   │   │   ├── uds                          833
│   │   │   │   ├── aws-sns                      830
│   │   │   │   ├── lorawan                      826
│   │   │   │   ├── ethernet-ip                  824
│   │   │   │   ├── j1939                        815
│   │   │   │   ├── profinet                     800
│   │   │   │   ├── redis-streams                787
│   │   │   │   ├── dhcp                         783
│   │   │   │   ├── aws-kinesis                  776
│   │   │   │   ├── azure-event-grid             772
│   │   │   │   ├── thread                       758
│   │   │   │   ├── imap                         752
│   │   │   │   ├── google-pub-sub               747
│   │   │   │   ├── azure-service-bus            741
│   │   │   │   ├── ftp                          740
│   │   │   │   ├── zigbee                       735
│   │   │   │   ├── knx                          730
│   │   │   │   ├── cotp                         728
│   │   │   │   ├── as2                          718
│   │   │   │   ├── nats                         699
│   │   │   │   ├── aws-sqs                      695
│   │   │   │   ├── coap                         676
│   │   │   │   ├── iso-tp                       660
│   │   │   │   ├── mdns                         639
│   │   │   │   ├── azure-blob                   627
│   │   │   │   ├── dds                          626
│   │   │   │   ├── s3                           622
│   │   │   │   ├── redpanda                     619
│   │   │   │   ├── pop3                         612
│   │   │   │   ├── wireless-m-bus               610
│   │   │   │   ├── google-cloud-storage         603
│   │   │   │   ├── syslog                       600
│   │   │   │   ├── obd-ii                       599
│   │   │   │   ├── ssdp                         587
│   │   │   │   ├── msmq                         532
│   │   │   │   ├── ethernet                     528
│   │   │   │   ├── aws                          525
│   │   │   │   ├── azure-event-hubs             518
│   │   │   │   ├── smtp                         491
│   │   │   │   ├── dnp3                         458
│   │   │   │   ├── iec-60870-5-104              457
│   │   │   │   ├── serial                       455
│   │   │   │   ├── named-pipe                   441
│   │   │   │   ├── websocket                    439
│   │   │   │   ├── azure                        436
│   │   │   │   ├── can-bus                      408
│   │   │   │   ├── sqlite                       361
│   │   │   │   ├── modbus                       357
│   │   │   │   ├── unix-socket                  273
│   │   │   │   ├── bacnet                       266
│   │   │   │   ├── mllp                         241
│   │   │   │   ├── rabbitmq                     240
│   │   │   │   ├── udp                          164
│   │   │   │   ├── tcp                          153
│   │   │   │   └── file                         139
│   │   │   ├── path                            2431
│   │   │   │   ├── jsonpath                     660
│   │   │   │   ├── fhirpath                     614
│   │   │   │   ├── dot                          291
│   │   │   │   ├── index                        158
│   │   │   │   ├── regex                        158
│   │   │   │   ├── json-pointer                  60
│   │   │   │   └── xpath                         49
│   │   │   ├── identify                        1397
│   │   │   │   ├── saml                         345
│   │   │   │   ├── api-key                      227
│   │   │   │   ├── dns                          195
│   │   │   │   ├── ip                           184
│   │   │   │   ├── username                     169
│   │   │   │   ├── jwt                          168
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
│   │   │   │   ├── ssh-key                       81
│   │   │   │   └── mac                           71
│   │   │   ├── contract                        1012  Rust 906 · PowerShell 106
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
│   │   │   │   ├── java                         113
│   │   │   │   ├── python                       100
│   │   │   │   ├── rust                          83
│   │   │   │   ├── go                            57
│   │   │   │   ├── c                             29
│   │   │   │   ├── cpp                           29
│   │   │   │   └── dotnet                        19
│   │   │   ├── route                            631
│   │   │   │   ├── metadata                     124
│   │   │   │   ├── contract                      86
│   │   │   │   ├── content                       80
│   │   │   │   ├── regex                         76
│   │   │   │   ├── party                         69
│   │   │   │   ├── header                        68
│   │   │   │   └── context                       47
│   │   │   ├── secret                           497
│   │   │   │   ├── dpapi                        328
│   │   │   │   ├── file                         223
│   │   │   │   ├── keychain                     106
│   │   │   │       declared, not built 5
│   │   │   │       aws-kms  azure-key-vault  keyring  pkcs11  vault
│   │   │   ├── authorize                        321
│   │   │   │   ├── location                     397
│   │   │   │   ├── abac                         360
│   │   │   │   ├── opa                          297
│   │   │   │   ├── cedar                        290
│   │   │   │   ├── policy                       249
│   │   │   │   ├── role                         226
│   │   │   │   ├── artifact                     215
│   │   │   │   ├── transport                    206
│   │   │   │   ├── acl                          178
│   │   │   │   ├── contract                     176
│   │   │   │   ├── claim                        173
│   │   │   │   ├── scope                        168
│   │   │   │   ├── rbac                         166
│   │   │   │   └── party                        131
│   │   │   ├── resilience                       204
│   │   │   │   ├── circuit-breaker              135
│   │   │   │   ├── rate-limit                   108
│   │   │   │   ├── retry                         88
│   │   │   │   ├── bulkhead                      83
│   │   │   │   ├── timeout                       80
│   │   │   │   └── fallback                      66
│   │   │   ├── receive                          174
│   │   │   ├── logic                            156
│   │   │   │   ├── matter                      1129
│   │   │   │   ├── soap                         274
│   │   │   │   ├── http-api                     259
│   │   │   │   └── grpc                         215
│   │   │   ├── send                             143
│   │   │   ├── demote                           106
│   │   │   ├── promote                           75
│   │   │   ├── process                           40
│   │   │   │       declared, not built 14
│   │   │   │       bash  c  command  cpp  dotnet  go  grpc  http  java  lua
│   │   │   │       powershell  python  rust  wasm
│   │   │   ├── transform                         33
│   │   │   │       declared, not built 17
│   │   │   │       c  cpp  dotnet  go  handlebars  java  jolt  jq  jsonata
│   │   │   │       liquid  mustache  python  rust  tera  wasm  xquery  xslt
│   │   │   ├── prepare                           29
│   │   │   │       declared, not built 20
│   │   │   │       base64  bzip2  canonicalize  charset  checksum  chunking
│   │   │   │       decrypt  deflate  encrypt  envelope  framing  gzip  hash
│   │   │   │       line-ending  quoted-printable  sign  tar  verify-signature
│   │   │   │        zip  zstd
│   │   │   ├── assign                            28
│   │   │   └── retain                            27
│   │   │           declared, not built 5
│   │   │           azure-blob  file  gcs  s3  sql
│   │   ├── library/
│   │   │   ├── net                             4426
│   │   │   ├── codec                           2301
│   │   │   ├── ntlm                             804
│   │   │   ├── asn1                             497
│   │   │   ├── tls                              333
│   │   │   └── ssh                              169
│   │   └── operation/
│   │       ├── cli                             3011
│   │       ├── gui                             2795
│   │       │   └── vscode                      1471
│   │       ├── observe                         2047
│   │       │   ├── otlp                         578
│   │       │   └── prometheus                   328
│   │       ├── powershell                      1443  C# 1443 · PowerShell 0
│   │       ├── audit                            878
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
│   │       │   ├── mysql                         91
│   │       │   ├── postgresql                    77
│   │       │   └── mssql                         73
│   │       └── report                            18
│   │               declared, not built 6
│   │               csv  html  json  pdf  prometheus  sql
│   ├── foundation/
│   │   ├── abi                                16231  C# 14537 · Rust 1469 · PowerShell 225
│   │   ├── event                               2687
│   │   │       declared, not built 3
│   │   │       amqp  http  kafka
│   │   ├── core                                1595
│   │   ├── message                             1354
│   │   │   ├── xml                              335
│   │   │   ├── avro                             298
│   │   │   ├── json                             254
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
│   │   ├── node                                 688
│   │   ├── context                              563
│   │   ├── journey                              350
│   │   ├── party                                186
│   │   ├── stream                                86
│   │   └── cluster                               21
│   └── platform/
│       ├── runtime                             5733
│       ├── configure                           1357
│       └── persist                              701
│           ├── sqlite                           107
│           └── rocksdb                          105
└── test/
    └── core/
        └── playground                          9557
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
| `xmip-core-contract` | scaffolded | `module/core/capability/contract` | 27 |
| `xmip-core-demote` | scaffolded | `module/core/capability/demote` | — |
| `xmip-core-identify` | scaffolded | `module/core/capability/identify` | 19 |
| `xmip-core-logic` | scaffolded | `module/core/capability/logic` | 4 |
| `xmip-core-path` | scaffolded | `module/core/capability/path` | 7 |
| `xmip-core-prepare` | scaffolded | `module/core/capability/prepare` | 20 |
| `xmip-core-process` | scaffolded | `module/core/capability/process` | 14 |
| `xmip-core-promote` | scaffolded | `module/core/capability/promote` | — |
| `xmip-core-receive` | scaffolded | `module/core/capability/receive` | — |
| `xmip-core-resilience` | scaffolded | `module/core/capability/resilience` | 6 |
| `xmip-core-retain` | scaffolded | `module/core/capability/retain` | 5 |
| `xmip-core-route` | scaffolded | `module/core/capability/route` | 7 |
| `xmip-core-secret` | scaffolded | `module/core/capability/secret` | 8 |
| `xmip-core-send` | scaffolded | `module/core/capability/send` | — |
| `xmip-core-transform` | scaffolded | `module/core/capability/transform` | 17 |
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

### `xmip-core-contract`, 27 technologies

All 27 composed in `module/core/capability/contract`.

- **scaffolded**, 27 — asyncapi, avro, c, cpp, csv, dotnet, edi-edifact,
  edi-x12, fhir, fixed-width, go, graphql-schema, hl7-v2, java, json-schema,
  openapi, protobuf, python, regex, rust, schematron, sql, toml, toon, wsdl,
  xml-schema, yaml

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

### `xmip-core-process`, 14 technologies

Declared, and none composed: `module/core/capability/process` has no
`.gitmodules`.

- **reserved**, 14 — bash, c, command, cpp, dotnet, go, grpc, http, java, lua,
  powershell, python, rust, wasm

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

### `xmip-core-transform`, 17 technologies

Declared, and none composed: `module/core/capability/transform` has no
`.gitmodules`.

- **reserved**, 17 — c, cpp, dotnet, go, handlebars, java, jolt, jq, jsonata,
  liquid, mustache, python, rust, tera, wasm, xquery, xslt

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
