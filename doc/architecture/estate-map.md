# The Xmip estate

330 repositories are declared and 253 of them are
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
| Foundation | 10 | 10 | 0 |
| Capability | 18 | 18 | 0 |
| Operation | 9 | 8 | 1 |
| Platform | 3 | 3 | 0 |
| Technology | 290 | 214 | 76 |
| **Total** | 330 | 253 | 77 |

| Maturity | Declared | Mounted | Not mounted |
| --- | ---: | ---: | ---: |
| planned | 6 | 6 | 0 |
| reserved | 156 | 79 | 77 |
| scaffolded | 168 | 168 | 0 |

**Mounted means composed as a submodule, and composition happens at two
levels** (ADR-0016, amended 2026-09-07). The root `.gitmodules` composes
the modules under `module/`, `test/` and `template/`. A technology is
composed by its own parent capability, inside that repository, so the
root cannot see it and this map reads each parent as well. A technology
reported as not mounted is one its parent does not compose — not one
the root forgot.

---

## Foundation

Things Xmip is.

| Repository | Maturity | Mount | Technologies |
| --- | --- | --- | ---: |
| `xmip-core` | reserved | `module/foundation/core` | — |
| `xmip-core-abi` | planned | `module/foundation/abi` | — |
| `xmip-core-cluster` | reserved | `module/foundation/cluster` | — |
| `xmip-core-context` | reserved | `module/foundation/context` | — |
| `xmip-core-event` | reserved | `module/foundation/event` | — |
| `xmip-core-journey` | reserved | `module/foundation/journey` | — |
| `xmip-core-message` | reserved | `module/foundation/message` | 15 |
| `xmip-core-node` | reserved | `module/foundation/node` | — |
| `xmip-core-party` | reserved | `module/foundation/party` | — |
| `xmip-core-stream` | planned | `module/foundation/stream` | — |

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
| `xmip-core-assign` | reserved | `module/capability/assign` | — |
| `xmip-core-authenticate` | reserved | `module/capability/authenticate` | 18 |
| `xmip-core-authorize` | reserved | `module/capability/authorize` | 14 |
| `xmip-core-contract` | reserved | `module/capability/contract` | 27 |
| `xmip-core-demote` | reserved | `module/capability/demote` | — |
| `xmip-core-identify` | reserved | `module/capability/identify` | 19 |
| `xmip-core-logic` | scaffolded | `module/capability/logic` | 4 |
| `xmip-core-path` | reserved | `module/capability/path` | 8 |
| `xmip-core-prepare` | reserved | `module/capability/prepare` | 20 |
| `xmip-core-process` | reserved | `module/capability/process` | 14 |
| `xmip-core-promote` | reserved | `module/capability/promote` | — |
| `xmip-core-receive` | reserved | `module/capability/receive` | — |
| `xmip-core-resilience` | reserved | `module/capability/resilience` | 6 |
| `xmip-core-retain` | reserved | `module/capability/retain` | 5 |
| `xmip-core-route` | reserved | `module/capability/route` | 8 |
| `xmip-core-send` | reserved | `module/capability/send` | — |
| `xmip-core-transform` | reserved | `module/capability/transform` | 17 |
| `xmip-core-transport` | planned | `module/capability/transport` | 84 |

### `xmip-core-authenticate`, 18 technologies

All 18 composed in `module/capability/authenticate`.

- **reserved**, 16 — api-key, basic, bearer, digest, jwt, kerberos, ldap,
  ntlm, oauth2, oidc, pam, password, saml, scram, ssh-key, windows
- **scaffolded**, 2 — certificate, mutual-tls

### `xmip-core-authorize`, 14 technologies

All 14 composed in `module/capability/authorize`.

- **reserved**, 14 — abac, acl, artifact, cedar, claim, contract, location,
  opa, party, policy, rbac, role, scope, transport

### `xmip-core-contract`, 27 technologies

All 27 composed in `module/capability/contract`.

- **scaffolded**, 27 — asyncapi, avro, c, cpp, csv, dotnet, edi-edifact,
  edi-x12, fhir, fixed-width, go, graphql-schema, hl7-v2, java, json-schema,
  openapi, protobuf, python, regex, rust, schematron, sql, toml, toon, wsdl,
  xml-schema, yaml

### `xmip-core-identify`, 19 technologies

All 19 composed in `module/capability/identify`.

- **reserved**, 19 — api-key, certificate, contract, cookie, dns, endpoint,
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

- **reserved**, 2 — peppol, sftp
- **scaffolded**, 82 — activemq, amqp, as2, as4, aws-kinesis, aws-sns,
  aws-sqs, azure-blob, azure-event-grid, azure-event-hubs, azure-service-bus,
  bacnet, bluetooth, can-bus, canopen, coap, cotp, dds, dhcp, dicom, dnp3,
  dns, ethercat, ethernet, ethernet-ip, file, ftp, google-cloud-storage,
  google-pub-sub, hart, http, ibm-mq, iec-60870-5-104, iec-61850, imap,
  io-link, iso-tp, j1939, kafka, knx, lorawan, m-bus, mdns, mllp, modbus,
  mqtt, msmq, mssql, mysql, named-pipe, nats, nats-jetstream, nfs, obd-ii,
  opc-ua, oracle, pop3, postgresql, profinet, rabbitmq, redis-streams,
  redpanda, s3, s7comm, secs-gem, serial, smb, smtp, snmp, sqlite, ssdp,
  syslog, tcp, thread, udp, uds, unix-socket, webdav, websocket,
  wireless-hart, wireless-m-bus, zigbee

---

## Operation

Running and governing Xmip.

| Repository | Maturity | Mount | Technologies |
| --- | --- | --- | ---: |
| `xmip-core-archive` | reserved | `module/operation/archive` | 10 |
| `xmip-core-audit` | reserved | `module/operation/audit` | 9 |
| `xmip-core-cli` | scaffolded | `module/operation/cli` | — |
| `xmip-core-gui` | scaffolded | `module/operation/gui` | 1 |
| `xmip-core-observe` | reserved | `module/operation/observe` | 5 |
| `xmip-core-powershell` | scaffolded | `module/operation/powershell` | — |
| `xmip-core-report` | reserved | `module/operation/report` | 6 |
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
| `xmip-core-configure` | planned | `module/platform/configure` | — |
| `xmip-core-persist` | planned | `module/platform/persist` | — |
| `xmip-core-runtime` | planned | `module/platform/runtime` | — |

---

## Retired

Named here because a reader who remembers one of these and cannot find
it above should be told what happened to it. The GitHub repository is
archived rather than deleted in every case.

- **`xmip-core-exclusiveness`**, 2026-08-27 — ADR-0024. ResourceClaim in
  xmip-core-transport replaces it. Archived rather than deleted because
  ADR-0017 is part of the record.

- **`xmip-core-webapi`**, 2026-09-06 — ADR-0014 amendment 2026-08-26. The web
  API belongs to the Logic axis (xmip-core-logic-http-api over
  xmip-core-transport-http), not a module of its own; it was declared, mounted
  nowhere, and deprecated. Retired rather than deleted because the amendment
  is part of the record; may return with the Logic axis.

- **`xmip-core-migrate`**, 2026-09-19 — ADR-0058 amendment 2026-09-19, on the
  owner's instruction. One lib.rs with no implementation and no consumer; a
  name the estate paid for on every clone, landing and survey. The GitHub
  repository is untouched and the capability is still planned by the record
  that names it. A first implementation brings the mount back.

- **`xmip-core-schedule`**, 2026-09-19 — ADR-0058 amendment 2026-09-19, on the
  owner's instruction. Six lines and no public API; clause 7 of that record
  kept it and the amendment supersedes clause 7. The GitHub repository is
  untouched and open problem 23 still names the work. A first implementation,
  which waits on a RuntimeStore backend, brings the mount back.

- **`xmip-core-diagnose`**, 2026-09-19 — ADR-0058 amendment 2026-09-19, on the
  owner's instruction. One lib.rs with no implementation and no consumer. The
  GitHub repository is untouched and ADR-0025 still names diagnosis as an
  Operation capability. A first implementation brings the mount back.
