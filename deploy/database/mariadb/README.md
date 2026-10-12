# Xmip Storage on MariaDB: what IT operators set up

For the people who run a site's database servers. It says what to install,
what to run, in what order, which server settings Xmip depends on and why,
and what to give the Xmip Storage nodes so they can connect. Everything else
about the server — how it is clustered, backed up, encrypted at rest and
failed over — is yours to decide, and the last section points at it.

## What Xmip needs from you

Every Xmip node reads and writes its records through **Xmip Storage**: the
nodes of the cluster that declare the Storage role. Those nodes, and only
those, connect to your database server (`doc/architecture/deployment-model.md`
section 7, option A). Xmip Storage keeps **three databases**, one to each
data domain, always separate, and each may be on a server of its own:

| Database | Holds | Written |
| --- | --- | --- |
| `xmip_runtime` | the Ledger: every Stream in chunks, every Message and Journey, the claims on Journeys, audit records as first written | constantly; read by key |
| `xmip_administration` | node registration, cluster membership, installed Modules, deployment and operator state | rarely; read over time |
| `xmip_audit` | audit records kept over time, each with its body and the bytes of every Stream it carries, moved there from `xmip_runtime` by the audit keeper | as the keeper moves them; read over time |

Neither holds configuration: each Xmip node reads its own configuration file
as it starts.

Xmip encrypts everything between a node and a Storage node. From the
Storage node on — its connection to your server and the data at rest there —
the decisions are yours (ADR-0063, amendment 2026-10-01). Xmip still
connects to your server over TLS only, and refuses a server that does not
offer it.

**Status, 2026-10-12.** This guide and the scripts beside it are ready, and
generated from the same schema definition Xmip Storage's backends read and
write by. MariaDB stands beside PostgreSQL and SQL Server as a server Xmip
Storage is in front of (ADR-0070, amendment 2026-10-12); until its backend
is built, a Storage node cannot yet be pointed at your server.

## 1. Install MariaDB

Xmip needs **MariaDB 11.4** or a later long-term release, such as 11.8.
The short-term releases between them are expected to work and are not
tested.

| Platform | How |
| --- | --- |
| Windows Server | The MSI package from <https://mariadb.org/download/>. It installs the server as a Windows service and the `mariadb` client. |
| Red Hat Enterprise Linux, AlmaLinux, Rocky Linux | Version 10's AppStream carries `mariadb11.8-server`: `dnf install mariadb11.8-server`. Otherwise the MariaDB Foundation's repository (<https://mariadb.org/download/?t=repo-config>), then `dnf install MariaDB-server MariaDB-client`. |
| Debian, Ubuntu | The MariaDB Foundation's repository (<https://mariadb.org/download/?t=repo-config>), then `apt install mariadb-server mariadb-client`. |

`mariadb`, the command-line client, runs the scripts. Install it wherever
you run them from.

## 2. Set the server's settings

In the server's option file, section `[mariadbd]` (`my.ini` on Windows,
`/etc/my.cnf.d/` on Red Hat and its kind, `/etc/mysql/mariadb.conf.d/` on
Debian and Ubuntu):

| Setting | Value | Why |
| --- | --- | --- |
| `default_storage_engine` | `InnoDB` (the default) | Every Xmip table is InnoDB, which the scripts name; Xmip needs its transactions and its row locks. |
| `innodb_flush_log_at_trx_commit` | `1` (the default) | Xmip counts a write only once the database has it durably (`runtime-model.md` section 3). `0` or `2` return a commit before its log is on disk, and a crash loses writes Xmip was told were kept. |
| `sync_binlog` | `1` | Where the binary log is on, for replication or point-in-time recovery, each commit is in it on disk before it returns, so a replica or a restore never lacks a write Xmip was told was kept. |
| `innodb_doublewrite` | `ON` (the default) | Without it a crash can leave a torn page. |
| `transaction_isolation` | `READ-COMMITTED` | MariaDB's default is `REPEATABLE-READ`. A claim is one conditional `UPDATE` — set the holder where there is none or the last claim has lapsed — which takes the row's lock, and a hand-on is one transaction; neither needs more, and read committed takes no gap locks to wait on. |
| `max_allowed_packet` | `64M` | A Stream is written in chunks of `segments` × `tcp_segment` bytes, 64,240 by default and at most 9,216,000 (1,024 × 9,000, `module/platform/configure/doc/node-configuration.md`); a chunk written as text in a statement takes twice its size. `64M` holds the largest with room to spare. |
| `require_secure_transport` | `ON` | Xmip connects over TLS only (section 4). |
| `max_connections` | at least 16 for each Storage node, plus your own | A Storage node keeps a connection for each request it has in flight. |

## 3. Run the scripts, in order

The scripts are per data domain: the number is the step, the word the
domain. Each says at its top what it is and as whom it runs. Run them as
`root`, or an account holding the same rights, from the folder they are
in. The client stops at the first statement that fails. One server holding
all three databases runs them all, in the order they sort by step:

```shell
mariadb --host=db-1.example --port=3306 --user=root --password --ssl-verify-server-cert --execute="SOURCE 01-roles.sql"
mariadb --host=db-1.example --port=3306 --user=root --password --ssl-verify-server-cert --execute="SOURCE 02-runtime-database.sql"
mariadb --host=db-1.example --port=3306 --user=root --password --ssl-verify-server-cert --execute="SOURCE 02-administration-database.sql"
mariadb --host=db-1.example --port=3306 --user=root --password --ssl-verify-server-cert --execute="SOURCE 02-audit-database.sql"
mariadb --host=db-1.example --port=3306 --user=root --password --ssl-verify-server-cert --execute="SOURCE 03-runtime-schema.sql"
mariadb --host=db-1.example --port=3306 --user=root --password --ssl-verify-server-cert --execute="SOURCE 03-administration-schema.sql"
mariadb --host=db-1.example --port=3306 --user=root --password --ssl-verify-server-cert --execute="SOURCE 03-audit-schema.sql"
```

| Script | Run on | Makes |
| --- | --- | --- |
| `01-roles.sql` | every server holding an Xmip database | the role `xmip_owner`, which may change the schema and which no one logs in as, and `xmip_storage`, the login the Storage nodes connect as, refused without TLS and locked until its password is set |
| `02-runtime-database.sql` | the server holding the runtime database | `xmip_runtime`, in `utf8mb4` compared byte for byte, its schema changeable by `xmip_owner` |
| `02-administration-database.sql` | the server holding the administration database | `xmip_administration`, likewise |
| `02-audit-database.sql` | the server holding the audit database | `xmip_audit`, likewise |
| `03-runtime-schema.sql` | the server holding the runtime database | the tables of `xmip_runtime`, InnoDB, with the indexes a search reads, and the right to read and write them for `xmip_storage` |
| `03-administration-schema.sql` | the server holding the administration database | the same in `xmip_administration` |
| `03-audit-schema.sql` | the server holding the audit database | the same in `xmip_audit` |

**Each database may be on a server of its own** — the audit database on
other servers and storage than the other two, for example. A server
holding one domain runs `01-roles.sql`, then that domain's
`02-<domain>-database.sql` and `03-<domain>-schema.sql`, and nothing of the
others; the domains need nothing of one another.

**A database is its own schema.** MariaDB has no schema inside a database,
as PostgreSQL and SQL Server have `xmip`: the tables are in `xmip_runtime`,
`xmip_administration` and `xmip_audit` themselves.

**Least privilege.** `xmip_storage` may select, insert, update and delete
rows in the three databases, and nothing else: it cannot create, alter or
drop anything. You may not change the schema in any way
([`../README.md`](../README.md)); a new release's scripts are run by an
operator granted `xmip_owner`
(`GRANT xmip_owner TO '<operator>'@'<host>';`, then, as that operator,
`SET ROLE xmip_owner;`).

Then set the login's password and unlock it, so the password is in no file
and no shell history; quote nothing in it with `'`:

```powershell
$password = Read-Host -Prompt 'xmip_storage password' -MaskInput
"ALTER USER 'xmip_storage'@'%' IDENTIFIED BY '$password' ACCOUNT UNLOCK;" |
    mariadb --host=db-1.example --port=3306 --user=root --password --ssl-verify-server-cert
Remove-Variable -Name password
```

`xmip_storage` may log in from any address (`'%'`); keep the Storage nodes'
addresses the only ones that reach the server's port, with your firewall.

An identifier is a UUIDv7, kept as `binary(16)` and compared byte for byte,
so keys written in time order stay in order
(`module/platform/persist/doc/record-identifier.md`). A time is
`datetime(6)`, in UTC, to the microsecond. MariaDB keeps no partial index:
the index of failed audit records, partial on the other servers, holds every
audit record here.

## 4. TLS on the connection

Give the server a certificate and its key, and require TLS:

- In `[mariadbd]`: `ssl_cert = server.crt`, `ssl_key = server.key`,
  `tls_version = TLSv1.3` (Xmip's TLS speaks TLS 1.3 first, ADR-0033), and
  `require_secure_transport = ON`.
- `xmip_storage` is made `REQUIRE SSL` by `01-roles.sql`: it is refused
  without TLS even where `require_secure_transport` is off.

MariaDB 11.4 and later make a certificate of their own where none is
given; that one names no host and no authority a Storage node trusts, so
give the server yours. The certificate's name is the host name the Storage
nodes connect to. Give the Xmip operators the certificate of the authority
that issued it, as PEM: it is the Storage node's `trust_anchor` (section 5).
Without one, a Storage node checks the server against its operating
system's trust store.

## 5. What a Storage node is given

A Storage node in front of your server names it in its configuration file,
a table for each data domain your server holds, and the secret and the
authority in `[storage.database]`
(`module/platform/configure/doc/node-configuration.md`):

```toml
[runtime]
storage    = "mariadb"
connection = "Server=db-1.example;Port=3306;Database=xmip_runtime;User=xmip_storage"

[administration]
storage    = "mariadb"
connection = "Server=db-1.example;Port=3306;Database=xmip_administration;User=xmip_storage"

[audit]
storage    = "mariadb"
connection = "Server=db-2.example;Port=3306;Database=xmip_audit;User=xmip_storage"

[storage.database]
password     = "xmip-storage-database"
trust_anchor = "database-authority.pem"
```

- **`[runtime]`**, **`[administration]`**, **`[audit]`**: each its
  `storage`, `mariadb`, and its `connection`, in the keywords of MariaDB's
  own Connector/ODBC, `Server=<host>[;Port=<port>];Database=<database>
  [;User=<login>]`, to the server that holds it; the port is 3306 where it
  is left out. Nothing else is written in a connection: no password, no
  option. Each domain may be on another server, or another technology.
- **`password`**: the **name** of the secret the password is kept under on
  the Storage node, resolved through Xmip's key home (ADR-0063 clause 4).
  The password itself is never written in the configuration file. How the
  password is placed in the key home under that name is the key home's to
  provide, and is not built yet.
- **`trust_anchor`**: the authority's certificate from section 4, PEM,
  relative to the configuration file.

So the Xmip operators need from you: each database's host and port, the
login's password (handed over the way your site hands over secrets), and
the authority's certificate.

## 6. Your choices

What follows is yours to decide, and Xmip neither does it nor depends on how
it is done (`deployment-model.md` section 9):

- **Encryption at rest.** InnoDB's data-at-rest encryption with a key
  management plugin, or encrypted volumes (BitLocker, LUKS, your storage's
  own).
- **Backup.** `mariadb-backup` with the binary log gives point-in-time
  recovery. The runtime database changes constantly; back it up as a live
  system, not as a nightly copy.
- **Replication and failover.** Asynchronous or semi-synchronous replication
  with a manager such as MaxScale, or a Galera cluster. A Storage node
  reconnects to the host name it was given; a failover that moves that name
  is invisible to Xmip.
- **Retention.** Xmip deletes what its retention says is done (runtime-model
  section 16); do not delete rows by hand.

## Testing against a server

The estate's own test runs Xmip Storage against a real server when it is
given one (`.src/test/database.rs`). Set, where the test runs:

| Variable | Holds |
| --- | --- |
| `XMIP_TEST_MARIADB` | the server, as a connection string without its database: `Server=<host>;Port=<port>;User=xmip_storage` |
| `XMIP_TEST_MARIADB_PASSWORD` | the login's password |

The server is set up as above. Without `XMIP_TEST_MARIADB` the test says
`skipped: no mariadb server configured` and runs nothing:

```shell
cargo test --test database --features persist -- --nocapture
```

## PostgreSQL and SQL Server

Their guides and scripts are beside this folder, in
`deploy/database/postgresql/` and `deploy/database/mssql/`, written from the
same schema definition.
