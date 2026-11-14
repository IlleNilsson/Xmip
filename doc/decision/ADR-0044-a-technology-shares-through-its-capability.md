# ADR-0044: A technology shares through its capability

- Status: Accepted
- Date: 2026-09-09
- Related: ADR-0010 (contract and transport repository boundaries), ADR-0016
  (submodule composition, amendment 2026-09-07), ADR-0033 (one TLS stack),
  doc/architecture/repository-model.md section 4 (dependency rules),
  doc/planning/open-problems.md problem 7

## In brief

- Theme: The shape of the estate
- Subject: Where code two technologies both need lives, and where it never
  does
- Name: A technology shares through its capability
- Order: 11
- Concepts: Shared code; the capability crate; the carrier technology; the vendor crate; copied files; XML reader, the one; third-party backend, its one crate

**Code that two technologies both need lives in the crate both already
depend on: their parent capability, or the technology they both ride on. A
technology never copies a sibling's file. The essentials' adapters follow
the same rule through the essentials' own shared modules.**

## Context

Sixty-five technology repositories were written between 2026-09-07 and
2026-09-09, most of them by assistants working in parallel, each inside one
repository with no view of the others. The result was correct and duplicated.
On 2026-09-09 a scan found: the same HTTP request-and-answer file, byte for
byte, in the s3, azure-blob and google-cloud-storage transports, with the same
endpoint and percent-encoding files beside it; the same flat-XML scan in two of
them; the same RFC 3339 clock in five archive technologies; the same object
layout in three; the metadata pair encoding in all ten. The
transport capability had already absorbed one such case on 2026-09-08 —
`socket.rs`, "opens every socket once" — without the rule being written down,
which is why it happened again the next day.

The owner, 2026-09-09: *So then it is time. Let's consolidate, refactor and
re-engineer if needed.*

Repository-model.md section 4 already fixes the direction: a technology may
depend on its parent capability; a capability never depends on its
technologies; a technology sibling dependency needs a declared justification.
What was missing was the consequence for shared code.

## Decision

### 1. Shared code goes up, never sideways

When two technologies need the same code, it moves to the nearest crate both
already depend on:

- **The parent capability**, when the code is about the capability's own
  subject. `xmip-core-archive` holds the metadata text, the timestamp, the
  name-keyed layout and the receipt checksum — every archive technology's
  item looks the same to an operator because of them. `xmip-core-transport`
  holds sockets, wire framing and the flat-XML scan a protocol document is.
- **The carrier technology**, when the code is about the protocol the two
  ride on. A REST API over HTTP shares HTTP's request-and-answer, endpoint
  and percent-encoding through `xmip-core-transport-http`, which s3,
  azure-blob and google-cloud-storage already carry as their declared
  sibling dependency (ADR-0033 put TLS there for the same reason).

Nothing moves *down* into a technology for another to import, and nothing is
copied. A file with the same content in two repositories is a defect, found
by the scan in `.ai-interaction` and, from this record on, fixed by moving
it up.

### 2. What stays in the technology

The dialect. A `PostgreSQL` row and a SQL Server row share the column set and
the metadata text through the capability; they keep their own quoting, their
own bytes literal and their own way of reading an id back. The rule moves what
is *the same*, not what is *similar*.

### 3. The essentials follows the rule through its own modules

Every adapter file in the essentials — `industrial.rs`, `broker.rs`,
`storage.rs`, `remote.rs` and the rest — shares through `roundtrip.rs`,
`cabinet.rs` and `support.rs`, never by repeating a helper. The scan runs
over the essentials as well.

### 4. Problem 7's lean, applied

Open problem 7 leaned to *keep five modules, share a store trait* so the
`postgres` adapter is not written five times. The archive technologies do it
one step further: archive-postgresql, -mssql, -mariadb, -s3, -azure-blob and
-gcs each ride on the transport technology of the same name for their wire
client, and hold only the archive's own shape. When audit, report and observe
grow technologies, they ride on the same transports.

## Consequences

- `xmip-core-archive` gains `metadata`, `timestamp`, `layout`, `checksum` and
  a `sha2` dependency; ten archive technologies lose their copies.
- `xmip-core-transport-http` gains `message`, `endpoint`, `percent`;
  `xmip-core-transport` gains `xml`; three object-store transports lose theirs.
- The duplicate scan (`.ai-interaction/dupscan.py`) is the assistant's tool,
  not a gate; the gate is the reviewer reading a new technology against this
  record. If the scan finds a second wave, it becomes a test.
- A shared module changes for every technology at once. That is the point,
  and it is why the change lands capability first, technologies after — the
  order `xgit` already keeps.

## Amendment, 2026-09-24: what one vendor speaks is that vendor's crate

On 2026-09-14 clause 1 put Signature Version 4, the AWS Query API, Azure's
Shared Access Signature and a Service Bus namespace's answers in
`xmip-core-transport-http`, because every technology that needed them rode
on HTTP. The owner ruled on 2026-09-22 that they leave: they are not HTTP,
they are what AWS and Azure speak over it, and a crate that is HTTP should
hold HTTP. Two technologies were approved that day to hold them,
`xmip-core-transport-aws` and `xmip-core-transport-azure`, and created on
2026-09-24.

- **A vendor crate is a carrier technology in clause 1's sense**, one layer
  up: it rides on http, and the vendor's technologies ride on it. s3,
  aws-sqs, aws-sns and aws-kinesis depend on `aws` for Signature Version 4,
  the Query API and the JSON 1.1 protocol; azure-blob, azure-service-bus
  and azure-event-hubs depend on `azure` for the Shared Access Signature,
  Shared Key and a namespace's answers. azure-event-grid's topic key is its
  own and stays with it.
- **The vendor crate is not a transport.** It implements no `Transport`;
  it is the shared dialect of a family, which is why it sits under the
  capability beside the technologies it serves.
- **http keeps HTTP**: the request and its answer, the endpoint,
  percent-encoding, RFC 1123's date and the judgment of a status.
  `x-amz-date` went to the AWS signer that reads it, once the civil
  calendar both dates are written off had moved to `xmip-core-library-codec`
  the same day. *(Later the same day: percent-encoding and a URL's
  authority are a URI's, not HTTP's, and moved to `xmip-core-library-net`,
  which the identity gates and the form shape reach too; http's own
  exchange of a request for its answer follows to `net::http`, the one
  HTTP/1.1 client, so an answer sent in chunks is read in one place.)*
- **A signature is compared by the HMAC's own check**, `verify_slice`,
  which takes the same time however far the two agree. The hand-written
  constant-time compare http carried for the three signers is gone.

Done 2026-09-24: both repositories created and mounted under
`module/core/capability/transport/`, every caller moved, nothing re-exported
from http.

Done 2026-09-25: the exchange followed. The request and its answer, both
halves, are `net::http`, and the URL a Location names `net::Endpoint`; http's
own codec (`message`), its Stream writer (`client`) and its URL reader
(`HttpTarget`) are gone, and every technology riding on HTTP calls net for
the message and http for what is the transport's — the connection and its
TLS (`http::endpoint`), a request served (`http::server`), the judgment of
a status (`http::status`) and RFC 1123's date. The head reader the
transport capability held for HTTP and SMTP went with it, to `net::head`,
and a network failure reaches a transport's `?` through
`From<NetError> for TransportError`, judged by its kind.

Done 2026-09-25, later the same day: HTTP/2 joined it. `net::http2` is the
one HTTP/2 codec, beside `net::http` and carrying the same `Request` and
`Response`, trailers included, so a caller does not care which version a
connection speaks. What stays http's is choosing the version per
connection — ALPN over TLS through `xmip-core-library-tls`, prior knowledge
in the clear where a Location says `h2c` — and a request served, which
answers a connection that opens with HTTP/2's preface in HTTP/2 and any
other in HTTP/1.1. The technologies riding on HTTP connect as before and
speak HTTP/1.1 unchanged (ADR-0043, amendment 2026-09-25).

## Amendment, 2026-09-24: a dialect is a choice, not a copy

Clause 2 left each SQL technology "its own quoting". Five crates read that as
writing the rule itself: a literal between quotes with the quote doubled, an
identifier between delimiters with the closing one doubled. That rule is the
same everywhere; only which delimiter is the dialect's. The `MariaDB` and
`PostgreSQL` far ends had it wrong, reading `` `in``box` `` and `"in""box"` as
ending at the first doubled delimiter.

- **The doubling is `codec::sql::Delimiter`'s** (`xmip-core-library-codec`,
  the lowest crate the SQL transports, the SQL script archive and the SQL
  contract all reach): `quote`, and `read` over the character reader. A
  dialect names the delimiter — `'`, `"`, `[`…`]`, a backtick — and keeps
  what is truly its own: T-SQL's `N` prefix, `MariaDB`'s backslash escapes.
- **An archive in a SQL server's table is one type**, `archive::sql::SqlArchive<D>`
  in the archive capability, with the row, its INSERT and SELECT and the
  receipt. What clause 2 leaves the technology is the `archive::sql::Dialect`
  it implements — quoting, the bytes literal and how they come back, how a
  new row's id is asked for, the moment's form — and the connection through
  its transport technology. `SqlServer`, `MariaDb` and `PostgreSql` are all
  that archive-mssql, -mariadb and -postgresql hold.
- **One protocol is one technology.** `rabbitmq` rode AMQP 0-9-1 with a
  second copy of `amqp`'s frame, methods, content, client and session. It
  now depends on `amqp`, a declared sibling carrier in clause 1's sense, and
  keeps RabbitMQ's idiom: the queue as the Location, the default exchange,
  a durable declaration before a publish, persistence and `rabbitmq://`.

## Provenance

The rule is the assistant's drafting of the owner's instruction of 2026-09-09
to consolidate, on the direction repository-model.md section 4 already fixed.
The socket.rs move of 2026-09-08 is its first instance, recorded here after
the fact.

## Amendment, 2026-09-26: the settings declaration lives in the capability

ADR-0064's amendment of 2026-09-26 has every technology declare its own
settings, so a Location's form, its validation at start and the
technology's own reading of them are one declaration. What every technology
shares of that goes up, as clause 1 says: the **shape** — a setting's name,
kind, default or requirement, meaning and the side that reads it — and the
one reading of a Location's values through it are `xmip-core`'s `settings`,
the lowest crate every capability already reaches, because a transport's
settings and a contract's are the same subject. How a technology of one
capability takes them is that **capability's**: `transport::Configured`
(`configured.rs`: `SETTINGS` and the one constructor from what it read),
and `contract::ContractFactory::settings` beside `load`. What stays in the
technology is its declaration and nothing else: no technology parses a
setting by hand, and no layer above it — `configure`, the runtime, the
language server, the desktop editor — keeps a list of what a technology
takes.

Provenance: the owner's requirement, 2026-09-26 (ADR-0064); the placement is
the assistant's drafting of clause 1.

## Amendment, 2026-09-28: every TCP connection sends at once

Every TCP connection Xmip opens or accepts has Nagle's algorithm off: the
one connect, `net::connect`, and the one accept, `transport::socket`, set it,
and no technology sets it again. Xmip writes a message as a head and then a
body; with Nagle on, the body waits for the peer's delayed acknowledgement of
the head — forty milliseconds a message on Linux — which the millisecond rule
calls a defect. The cost, many small packets, belongs to a program that
writes a byte at a time, and Xmip does not. So it is off on every
connection, not only where latency is asked for, and it is not a setting: a
knob no one needs is one someone gets wrong.

Provenance: the owner, 2026-09-28, asked the pros and cons and left the
choice to the assistant (*I let you decide*); the assistant chose this.

## Amendment, 2026-10-12: SQL is a library of its own

The 2026-09-24 amendment put SQL's doubling rule in `xmip-core-library-codec`
and left two dialects standing: the transport capability's, which every SQL
transport filled for its INSERT, its far end and its `accept` statement, and
the archive capability's `archive::sql::Dialect`, which the same servers'
archive technologies filled again for their row. The transport and the SQL
contract each read a statement's verb their own way. That is SQL written
three times across three domains, and none of them owns it. The owner,
2026-10-12: *Well I guess that SQL should live under a more common
repo/module if it is shared between domains?* — and, approving
`xmip-core-library-sql` at `module/core/library/sql`, *Go ahead, it does not
fit under archive.*

- **SQL is `xmip-core-library-sql`'s**, beside codec, net and the other
  libraries: `Delimiter`, the doubling rule, moved out of codec, which keeps
  no copy; `Verb`, the keyword a statement opens with, which the SQL
  contract's allowed set names and a SQL far end answers by; `Literal`; and
  one `Dialect`, the union of the two: the identifier delimiter, what a bare
  identifier takes, the first parameter marker, the string and binary
  literals, how a binary column comes back, and how an INSERT answers its new
  row's id. Through it the one INSERT is written and taken apart and a
  parameter is bound in. The dialects are the ones Xmip already spoke:
  ISO SQL (the SQL script archive), T-SQL, `PostgreSQL`, `MariaDB` and
  `SQLite`.
- **The wire stays with the technology.** A transport keeps its protocol, its
  login and the URI schemes its Locations open with; the transport capability
  keeps where a send target puts its row, the payload column setting and the
  `accept` acknowledgement, each taking the dialect a technology names.
- **The archive keeps what is the archive's.** `SqlArchive<D>` stays in the
  archive capability, with its row, its receipt and `archive::sql::Database`:
  the dialect a server speaks, the receipt's scheme, the moment's form and
  the connection. Clause 2's rule holds: what moved is the same in every
  domain, not what is similar.
- **`MariaDB`.** The dialect, the transport and the archive are named for
  `MariaDB` (the owner, 2026-10-12). MySQL is a transport of its own on the
  same wire, `xmip-core-library-mariadb`, with what MySQL does differently
  kept in it alone (ADR-0011, amendment 2026-10-14).

Provenance: the owner's two sentences above and his approval of the
repository the same day; the shape of the one dialect is the assistant's
drafting of clause 1.

## Amendment, 2026-11-13: one SQL transport, over each technology's wire

After the 2026-10-12 amendment every SQL transport still carried the same
transport itself: the default query, the builder, the receive that turns rows
into arrivals with their `accept` statement, the send that writes one INSERT,
the connections kept per server and database, the settings it declares and
reads, and the loopback. `MariaDB`'s and MySQL's differed in 21 of 266 lines;
PostgreSQL, SQL Server, Oracle Database and IBM DB2 had the same shape with
other names. The owner, 2026-11-13: *"Do we have all code in the modules,
repos that we should. This is a refactoring statement."*

- **The transport is the capability's**: `transport::sql::SqlTransport<W>`,
  the one SQL transport, implements `Transport`, `Configured`, `Loopback`
  and `Accepting` once; the settings every SQL Location declares —
  `database`, `user`, `query`, `timeout` and the default query — are
  `transport::sql::declared`'s, beside the column and `accept` settings
  that were already there, and so are `tls_name` and the one reading of
  `tls` and `tls_name` into the client's TLS settings
  (`transport::sql::client_tls`), which `MariaDB`, MySQL and DB2 each
  carried; what `tls` means — TLS before the login or from the first byte
  — stays each technology's.
- **A technology is its `Wire`**: its name and schemes, its declaration
  (the shared settings and its own: TLS for `MariaDB`, MySQL and DB2,
  Oracle's `service` in place of a database), the dialect it writes in and
  the one its session reads where that may differ (`MariaDB`'s
  `NO_BACKSLASH_ESCAPES`), the client — connect, query, execute, committed
  where the server commits nothing until told — and its loopback's far
  end. `MariaDbTransport`, `MySqlTransport`, `PostgresTransport`,
  `MssqlTransport`, `OracleTransport` and `Db2Transport` are
  `SqlTransport` over their wire; every repository stays, thinner.
- **What a far end took** carries one origin,
  `<scheme>://peer/database/table/column` (`SqlTransport::inserted`), and
  a refused row is remembered by one stamp of its body
  (`transport::sql::accept::stamp`), the `SQLite` queue's included. `SQLite`
  keeps its own transport: an embedded file queue claimed by a column, with
  no server, login, query or `accept` statement, is not this shape.
- **The archive writes as the session reads**, as the transports do:
  `archive::sql::Database::dialect` is the dialect a connection's session
  reads, `Database::DIALECT` unless the session says otherwise, and the
  `MariaDB` archive answers it with `mariadb::Client::dialect`, the one rule
  the transports also call. Until 2026-11-13 the archive wrote every
  INSERT in the backslash-escaping mode, whatever mode the server was in.

Provenance: the owner's sentence above; the placement audit of the same day
found the repetition and the shape of the seam is the assistant's drafting.

## Amendment, 2026-11-13: a primitive every layer needs is the library's, not a capability's

The owner, 2026-11-13: *Do we have all code in the modules, repos that we
should. This is a refactoring statement*. The capability crate is where two
technologies share, and `xmip-core-authenticate`'s credential store had
grown into the estate's SHA-256, HMAC-SHA256 and PBKDF2, exported for its
technologies while twelve crates elsewhere took `sha2` and seven `hmac`
for the same three functions, provisioning and the TLS library hashed
through aws-lc-rs, and Kerberos took `sha1`, `hmac` and `pbkdf2` again:

- **A primitive no capability owns goes below every capability.**
  `codec::digest` is the one SHA-256 (`sha256`, `Sha256` in parts),
  HMAC-SHA256 (`hmac_sha256`, `HmacSha256`, its check in constant time) and
  PBKDF2, from `sha2` and `hmac`, pure Rust; HMAC-SHA1 and PBKDF2-HMAC-SHA1
  are RFC 2104's construction over codec's own SHA-1 (`hmac_by`), which
  NTLM's HMAC-MD5 takes over its `md-5`. `authenticate::store` keeps
  `salted_password`, RFC 5802's term, and nothing else of it.
- **Every caller calls it.** `api-key` and `bearer` (both gates),
  `digest`, `scram`, `jwt`, `kerberos`, `ntlm`, the X.509 mint, the JOSE
  key set's HS256, the AS2, AWS, Azure, MQTT and MySQL transports, the SSH
  library (its packet HMAC keyed once a direction), the archive's checksum,
  provisioning and the TLS library. `sha2`, `hmac`, `sha1` and `pbkdf2` are
  direct dependencies of `xmip-core-library-codec` alone; the `sha2` and
  `sha1` that `rsa` 0.9's signature and OAEP types name stay rsa's.
- **The audit chain followed the same day:** Xmip Storage's and the file
  sink's chain are formed by one rule, `xcore::audit_chain`, over
  `codec::digest` (ADR-0070, amendment 2026-11-13), and `sha2` left
  `xmip-core-persist` and `xmip-core-audit` with it.

Proved by `codec::digest`'s published vectors (FIPS 180-4, RFC 4231, RFC
2202, RFC 6070, RFC 7914) and every caller's tests, unchanged.

Provenance: the audit is the coordinator's, the backend the coordinator's
choice; the generic construction for the legacy hashes is the assistant's
drafting, 2026-11-13, for the owner to overrule.

## Amendment, 2026-11-13: one XML reader, in the library

The owner, 2026-11-13: *Do we have all code in the modules, repos that we
should. This is a refactoring statement*, then *Good that you found it, fix
it* and *Speed it up*. XML was read eight ways: the flat scan in
`codec::xml`, with a tag walk of its own; `roxmltree` in the XML Schema,
Schematron and WSDL contracts and the SOAP logic technology; `quick-xml` in
Convert, the stylesheet's version and the BPMN design reader;
`sxd-document`'s parser in the `XPath` path technology and Schematron; and a
reader of its own each in the XML shape, the SAML authenticator, the SAML
identifier and Peppol's payload check. The same document was well-formed to
one and not to the next, and a namespace was resolved by two of them.

- **One reader, below every capability.** `codec::xml` in
  `xmip-core-library-codec`. `quick-xml` cuts the pieces, the one XML
  backend the estate links, and `event` gives them back in the estate's
  terms with where each lies. `Reader` reads text in memory a piece at a
  time and holds a document to its order — one root, every element closed
  by its own end tag — saying the byte where it leaves it; `streamed` does
  the same over bytes as they arrive, holding one piece; `tree` reads a
  document into nodes in document order, its namespaces resolved, its text
  read as XML 1.0 reads it, a document type declaration refused and its
  depth capped by `codec::depth` or fewer where a caller says; the flat scan
  reads through `Reader`.
- **Every caller calls it.** The XML shape and UBL walk through `Reader`;
  the contracts, SOAP, BPMN, both SAML gates and `XPath` read the tree,
  the authenticator's `Element` and BPMN's `Element` built from it;
  Convert streams; the protocols' scans are unchanged.
- **`XPath` keeps its engine.** `sxd-xpath` evaluates over `sxd-document`'s
  model and nothing else, so `xmip-core-path-xpath` fills that model from
  codec's tree and never parses text itself, and it is the one crate that
  names either. Schematron evaluates through its `Expression` and
  `Document`, and a selected node's location is written there once. An
  `XPath` evaluation over codec's tree would let the pair go; not now.
- **Held by a test.** `test/ThirdParty.Test.ps1` lists each backend with
  the crates that may name it — `quick-xml` codec alone, `encoding_rs`
  codec alone, `sxd-document` and `sxd-xpath` path-xpath alone,
  `roxmltree` and eight other XML readers none — and fails a second
  reader in the change that brings it.
- **One decoding of text.** `codec::charset` reads the WHATWG encodings
  into UTF-8 and writes them from it, whole or a piece at a time, strictly,
  over `encoding_rs`. The XML reader's edge and the Character Encoding
  prepare unit both go through it; until the same day prepare took
  `encoding_rs` itself.

What changed for a reader of XML. A document is read in the encoding its
byte order mark or its XML declaration names, UTF-8 where neither does
(XML 1.0 appendix F): `codec::xml::decoded` decodes it at the reader's
edge through `codec::charset`, strictly, refusing bytes wrong for the encoding
at the first, and the XML shape reads through it, so a document declared
ISO-8859-1 or Windows-1252, or written in UTF-16 behind its mark, is one
document as BizTalk and MuleSoft read it; ISO-8859-1 is read as
Windows-1252, as WHATWG's encodings read it. A document type declaration is
refused by the tree everywhere. The SAML identifier reads the same tree as the
authenticator, so a document that is not namespace-well-formed is refused
at the first gate rather than the second. An attribute's value is read as
XML 1.0 normalizes it, which the authenticator's canonical form now
renders as the specification does.

Measured on the estate's own test documents, each reader against the one it
replaced in the same run, rounds taken in turn, the fastest of nine — on a
machine every other worker was building on, so the times are inflated and
the ratios are what to read, within some fifteen to twenty percent from
run to run. First, as the reader landed: the `XPath` and Schematron parse
61 to 79 percent faster than `sxd-document`'s parser; the signed assertion
7 to 14 percent faster; the BPMN design and Convert's streamed read as fast
as before; the tree up to 32 percent slower than `roxmltree` on a schema of
61 KB; the shape's walk 22 to 30 percent slower on a design and a schema;
the protocols' flat scan 45 percent slower over an S3 listing of a thousand
keys; and the SAML identifier, then a tree, 227 percent slower.

Then, the same day, the message path brought back to what it was (the
coordinator: *nothing on the message path gets slower*). The flat scan
reads `quick-xml`'s pieces straight, making nothing of a piece but the
names it compares: 9 percent faster to 15 percent slower over the S3
listing in two runs of one build, parity within the noise. The shape walks
with `Reader::read_tag`, which holds the document's order but makes no
piece of what lies inside the root and is no tag: 7 percent faster on the
61 KB schema and 1 percent on the design. The tree sizes its vectors from
the text once: 8 percent slower than `roxmltree` on the schema and 10
percent faster on the design. The SAML identifier reads in one pass of
`Reader` and stops where the assertion ends, building no tree: from 227 to
54 percent slower. Two remain slower, and the backend is why: measured
bare, `quick-xml` cuts the S3 listing 72 percent slower than the old walk
did, since it gives each run of text and each entity reference as a piece
of its own and checks each for UTF-8 where the old walk passed text over
with one search, and the shape's walk there is 132 percent slower; and on
a document of a hundred bytes, creating the reader is most of the cost,
the walk 44 percent slower (1.9 to 2.7 microseconds) and the tree 26.
Every one is within microseconds of what it was and far under the
millisecond (CONTRIBUTING.md); parity on those two asks the backend's
speed on a short or entity-dense document, or a cut of the estate's own.

Provenance: the audit, the backend and keeping the `XPath` engine are the
coordinator's plan of the same day; the reader's shape, its API and the
measurements are the assistant's drafting, for the owner to overrule.
