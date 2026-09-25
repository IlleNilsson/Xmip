# The Xmip estate

351 repositories are declared and 267 of them are
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
| Technology | 309 | 227 | 82 |
| **Total** | 351 | 267 | 84 |

| Maturity | Declared | Mounted | Not mounted |
| --- | ---: | ---: | ---: |
| reserved | 84 | 0 | 84 |
| scaffolded | 267 | 267 | 0 |

**Mounted means composed as a submodule, and composition happens at two
levels** (ADR-0016, amended 2026-09-07). The root `.gitmodules` composes
the modules under `module/`, `test/` and `template/`. A technology is
composed by its own parent capability, inside that repository, so the
root cannot see it and this map reads each parent as well. A technology
reported as not mounted is one its parent does not compose — not one
the root forgot.

---

## The tree

Where each repository mounts and what it holds: 154536 lines of production
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
nowhere — work not begun, not work unmounted. There are 84 of them and they
hold no source to count.

```text
├── sdk                                          377
├── module/
│   ├── core/
│   │   ├── capability/
│   │   │   ├── authenticate                    2654
│   │   │   │   ├── saml                         953
│   │   │   │   ├── ntlm                         618
│   │   │   │   ├── kerberos                     581
│   │   │   │   ├── ldap                         530
│   │   │   │   ├── oauth2                       468
│   │   │   │   ├── ssh-key                      468
│   │   │   │   ├── digest                       464
│   │   │   │   ├── windows                      405
│   │   │   │   ├── scram                        404
│   │   │   │   ├── pam                          351
│   │   │   │   ├── oidc                         247
│   │   │   │   ├── jwt                          156
│   │   │   │   ├── certificate                  147
│   │   │   │   ├── api-key                      105
│   │   │   │   ├── bearer                       100
│   │   │   │   ├── mutual-tls                    97
│   │   │   │   ├── basic                         88
│   │   │   │   └── password                      80
│   │   │   ├── transport                       1929
│   │   │   │   ├── opc-ua                      2333
│   │   │   │   ├── sftp                        2089
│   │   │   │   ├── mssql                       2061
│   │   │   │   ├── mysql                       1680
│   │   │   │   ├── smb                         1609
│   │   │   │   ├── amqp                        1566
│   │   │   │   ├── nfs                         1561
│   │   │   │   ├── snmp                        1344
│   │   │   │   ├── oracle                      1302
│   │   │   │   ├── ibm-mq                      1273
│   │   │   │   ├── postgresql                  1221
│   │   │   │   ├── nats-jetstream              1068
│   │   │   │   ├── canopen                     1061
│   │   │   │   ├── s7comm                      1016
│   │   │   │   ├── as4                         1007
│   │   │   │   ├── kafka                       1007
│   │   │   │   ├── io-link                      993
│   │   │   │   ├── iec-61850                    967
│   │   │   │   ├── http                         915
│   │   │   │   ├── webdav                       914
│   │   │   │   ├── dns                          892
│   │   │   │   ├── activemq                     890
│   │   │   │   ├── dicom                        886
│   │   │   │   ├── ethercat                     875
│   │   │   │   ├── peppol                       870
│   │   │   │   ├── lorawan                      860
│   │   │   │   ├── secs-gem                     853
│   │   │   │   ├── m-bus                        846
│   │   │   │   ├── hart                         839
│   │   │   │   ├── bluetooth                    813
│   │   │   │   ├── wireless-hart                794
│   │   │   │   ├── mqtt                         791
│   │   │   │   ├── ethernet-ip                  782
│   │   │   │   ├── uds                          764
│   │   │   │   ├── azure-event-grid             750
│   │   │   │   ├── aws-sns                      748
│   │   │   │   ├── dhcp                         745
│   │   │   │   ├── profinet                     719
│   │   │   │   ├── redis-streams                717
│   │   │   │   ├── thread                       711
│   │   │   │   ├── ftp                          709
│   │   │   │   ├── j1939                        708
│   │   │   │   ├── imap                         694
│   │   │   │   ├── aws-kinesis                  692
│   │   │   │   ├── knx                          672
│   │   │   │   ├── as2                          670
│   │   │   │   ├── azure-service-bus            669
│   │   │   │   ├── google-pub-sub               669
│   │   │   │   ├── cotp                         660
│   │   │   │   ├── nats                         660
│   │   │   │   ├── zigbee                       650
│   │   │   │   ├── coap                         621
│   │   │   │   ├── aws-sqs                      616
│   │   │   │   ├── iso-tp                       592
│   │   │   │   ├── dds                          588
│   │   │   │   ├── mdns                         578
│   │   │   │   ├── redpanda                     576
│   │   │   │   ├── pop3                         566
│   │   │   │   ├── azure-blob                   546
│   │   │   │   ├── s3                           537
│   │   │   │   ├── google-cloud-storage         535
│   │   │   │   ├── wireless-m-bus               524
│   │   │   │   ├── obd-ii                       517
│   │   │   │   ├── aws                          515
│   │   │   │   ├── ssdp                         513
│   │   │   │   ├── syslog                       500
│   │   │   │   ├── msmq                         489
│   │   │   │   ├── smtp                         478
│   │   │   │   ├── named-pipe                   458
│   │   │   │   ├── azure-event-hubs             450
│   │   │   │   ├── websocket                    445
│   │   │   │   ├── ethernet                     435
│   │   │   │   ├── azure                        434
│   │   │   │   ├── iec-60870-5-104              431
│   │   │   │   ├── dnp3                         405
│   │   │   │   ├── serial                       366
│   │   │   │   ├── sqlite                       338
│   │   │   │   ├── modbus                       316
│   │   │   │   ├── unix-socket                  313
│   │   │   │   ├── can-bus                      312
│   │   │   │   ├── bacnet                       244
│   │   │   │   ├── mllp                         225
│   │   │   │   ├── rabbitmq                     192
│   │   │   │   ├── udp                          157
│   │   │   │   ├── tcp                          130
│   │   │   │   └── file                         129
│   │   │   ├── identify                        1442
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
│   │   │   ├── route                            906
│   │   │   │   ├── expression                   101
│   │   │   │   ├── metadata                     101
│   │   │   │   ├── content                       91
│   │   │   │   ├── contract                      75
│   │   │   │   ├── regex                         70
│   │   │   │   ├── header                        67
│   │   │   │   ├── party                         65
│   │   │   │   └── context                       43
│   │   │   ├── contract                         831  Rust 725 · PowerShell 106
│   │   │   │   ├── graphql-schema               829
│   │   │   │   ├── xml-schema                   745
│   │   │   │   ├── avro                         724
│   │   │   │   ├── toon                         702
│   │   │   │   ├── sql                          692
│   │   │   │   ├── protobuf                     654
│   │   │   │   ├── json-schema                  593
│   │   │   │   ├── fixed-width                  495
│   │   │   │   ├── edi-edifact                  452
│   │   │   │   ├── schematron                   438
│   │   │   │   ├── edi-x12                      437
│   │   │   │   ├── wsdl                         373
│   │   │   │   ├── openapi                      361
│   │   │   │   ├── yaml                         351
│   │   │   │   ├── hl7-v2                       312
│   │   │   │   ├── toml                         297
│   │   │   │   ├── fhir                         273
│   │   │   │   ├── asyncapi                     225
│   │   │   │   ├── regex                        165
│   │   │   │   ├── csv                          114
│   │   │   │   ├── java                         113
│   │   │   │   ├── python                       100
│   │   │   │   ├── rust                          66
│   │   │   │   ├── go                            57
│   │   │   │   ├── c                             29
│   │   │   │   ├── cpp                           29
│   │   │   │   └── dotnet                        19
│   │   │   ├── secret                           497
│   │   │   │   ├── file                         223
│   │   │   │   ├── dpapi                        180
│   │   │   │   ├── keychain                     106
│   │   │   │       declared, not built 5
│   │   │   │       aws-kms  azure-key-vault  keyring  pkcs11  vault
│   │   │   ├── authorize                        321
│   │   │   │   ├── location                     397
│   │   │   │   ├── abac                         360
│   │   │   │   ├── cedar                        290
│   │   │   │   ├── opa                          290
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
│   │   │   ├── path                             299
│   │   │   │   ├── fhirpath                     742
│   │   │   │   ├── jsonpath                     724
│   │   │   │   ├── predicate                    584
│   │   │   │   ├── dot                          355
│   │   │   │   ├── xpath                        255
│   │   │   │   ├── regex                        253
│   │   │   │   ├── index                        216
│   │   │   │   └── json-pointer                 144
│   │   │   ├── resilience                       204
│   │   │   │   ├── circuit-breaker              135
│   │   │   │   ├── rate-limit                   108
│   │   │   │   ├── retry                         88
│   │   │   │   ├── bulkhead                      83
│   │   │   │   ├── timeout                       80
│   │   │   │   └── fallback                      66
│   │   │   ├── receive                          174
│   │   │   ├── logic                            152
│   │   │   │   ├── matter                      1128
│   │   │   │   ├── soap                         272
│   │   │   │   ├── http-api                     257
│   │   │   │   └── grpc                         212
│   │   │   ├── send                             143
│   │   │   ├── demote                            82
│   │   │   ├── promote                           48
│   │   │   ├── process                           40
│   │   │   │       declared, not built 14
│   │   │   │       bash  c  command  cpp  dotnet  go  grpc  http  java  lua
│   │   │   │       powershell  python  rust  wasm
│   │   │   ├── prepare                           29
│   │   │   │       declared, not built 20
│   │   │   │       base64  bzip2  canonicalize  charset  checksum  chunking
│   │   │   │       decrypt  deflate  encrypt  envelope  framing  gzip  hash
│   │   │   │       line-ending  quoted-printable  sign  tar  verify-signature
│   │   │   │        zip  zstd
│   │   │   ├── transform                         29
│   │   │   │       declared, not built 17
│   │   │   │       c  cpp  dotnet  go  handlebars  java  jolt  jq  jsonata
│   │   │   │       liquid  mustache  python  rust  tera  wasm  xquery  xslt
│   │   │   ├── assign                            28
│   │   │   └── retain                            27
│   │   │           declared, not built 5
│   │   │           azure-blob  file  gcs  s3  sql
│   │   ├── library/
│   │   │   ├── codec                           1938
│   │   │   ├── ntlm                             804
│   │   │   ├── net                              798
│   │   │   ├── asn1                             497
│   │   │   └── tls                              219
│   │   └── operation/
│   │       ├── cli                             3026
│   │       ├── gui                             2434
│   │       │   └── vscode                       802
│   │       ├── powershell                      2125  C# 1361 · PowerShell 764
│   │       ├── observe                         1728
│   │       │       declared, not built 5
│   │       │       etw  journald  otlp  prometheus  windows-event-log
│   │       ├── audit                            889
│   │       │       declared, not built 10
│   │       │       elasticsearch  file  kafka  mssql  opensearch  otlp
│   │       │       postgres  sqlite  syslog  windows-event-log
│   │       ├── archive                          626
│   │       │   ├── sql                          256
│   │       │   ├── file                         254
│   │       │   ├── azure-blob                   165
│   │       │   ├── s3                           155
│   │       │   ├── parquet                      147
│   │       │   ├── sqlite                       144
│   │       │   ├── gcs                          135
│   │       │   ├── mysql                         91
│   │       │   ├── postgresql                    77
│   │       │   └── mssql                         73
│   │       └── report                            18
│   │               declared, not built 6
│   │               csv  html  json  pdf  prometheus  sql
│   ├── foundation/
│   │   ├── abi                                11966  C# 10758 · Rust 1208
│   │   ├── message                             1293
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
│   │   ├── core                                 902
│   │   ├── node                                 505
│   │   ├── context                              473
│   │   ├── journey                              350
│   │   ├── party                                186
│   │   ├── stream                                38
│   │   ├── cluster                               21
│   │   └── event                                 20
│   └── platform/
│       ├── runtime                             4531
│       ├── persist                              701
│       │   ├── sqlite                           107
│       │   └── rocksdb                          105
│       └── configure                            131
└── test/
    └── core/
        └── playground                          9327
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
| `xmip-core-event` | scaffolded | `module/foundation/event` | — |
| `xmip-core-journey` | scaffolded | `module/foundation/journey` | — |
| `xmip-core-message` | scaffolded | `module/foundation/message` | 15 |
| `xmip-core-node` | scaffolded | `module/foundation/node` | — |
| `xmip-core-party` | scaffolded | `module/foundation/party` | — |
| `xmip-core-sdk` | scaffolded | `sdk` | — |
| `xmip-core-stream` | scaffolded | `module/foundation/stream` | — |

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
| `xmip-core-library` | reserved | not mounted | 5 |

### `xmip-core-library`, 5 technologies

The parent is not composed here, so what it composes cannot be read; every
technology below is declared only.

- **scaffolded**, 5 — asn1, codec, net, ntlm, tls

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
| `xmip-core-path` | scaffolded | `module/core/capability/path` | 8 |
| `xmip-core-prepare` | scaffolded | `module/core/capability/prepare` | 20 |
| `xmip-core-process` | scaffolded | `module/core/capability/process` | 14 |
| `xmip-core-promote` | scaffolded | `module/core/capability/promote` | — |
| `xmip-core-receive` | scaffolded | `module/core/capability/receive` | — |
| `xmip-core-resilience` | scaffolded | `module/core/capability/resilience` | 6 |
| `xmip-core-retain` | scaffolded | `module/core/capability/retain` | 5 |
| `xmip-core-route` | scaffolded | `module/core/capability/route` | 8 |
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

### `xmip-core-path`, 8 technologies

All 8 composed in `module/core/capability/path`.

- **scaffolded**, 8 — dot, fhirpath, index, json-pointer, jsonpath, predicate,
  regex, xpath

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

### `xmip-core-route`, 8 technologies

All 8 composed in `module/core/capability/route`.

- **scaffolded**, 8 — content, context, contract, expression, header,
  metadata, party, regex

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
| `xmip-core-observe` | scaffolded | `module/core/operation/observe` | 5 |
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

### `xmip-core-observe`, 5 technologies

Declared, and none composed: `module/core/operation/observe` has no
`.gitmodules`.

- **reserved**, 5 — etw, journald, otlp, prometheus, windows-event-log

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
