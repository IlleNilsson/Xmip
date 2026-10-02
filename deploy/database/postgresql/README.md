# Xmip Storage on PostgreSQL: what IT operators set up

For the people who run a site's database servers. It says what to install,
what to run, in what order, which server settings Xmip depends on and why,
and what to give the Xmip Storage nodes so they can connect. Everything else
about the server — how it is clustered, backed up, encrypted at rest and
failed over — is yours to decide, and the last section points at it.

## What Xmip needs from you

Every Xmip node reads and writes its records through **Xmip Storage**: the
nodes of the cluster that declare the Storage role. Those nodes, and only
those, connect to your database server (`doc/architecture/deployment-model.md`
section 7, option A). Xmip Storage keeps **two databases**, always separate,
which you may place on different servers:

| Database | Holds | Written |
| --- | --- | --- |
| `xmip_runtime` | the Ledger: every Stream in chunks, every Message and Journey, the claims on Journeys, audit records as first written | constantly; read by key |
| `xmip_administration` | node registration, cluster membership, installed Modules, deployment and operator state, and audit records kept over time | rarely; read over time |

Neither holds configuration: each Xmip node reads its own configuration file
as it starts.

Xmip encrypts everything between a node and a Storage node. From the
Storage node on — its connection to your server and the data at rest there —
the decisions are yours (ADR-0063, amendment 2026-10-01). Xmip still
connects to your server over TLS only, and refuses a server that does not
offer it.

**Status, 2026-10-01.** This guide and the scripts beside it are ready, and
generated from the same schema definition Xmip Storage's PostgreSQL backend
reads and writes by. That backend, `xmip-core-persist-postgresql`, is built
next; until it is, a Storage node cannot yet be pointed at your server.

## 1. Install PostgreSQL

Xmip is built against **PostgreSQL 18**, the current major release. The
older major releases the PostgreSQL project still supports are expected to
work and are not tested.

| Platform | How |
| --- | --- |
| Windows Server | The installer from <https://www.postgresql.org/download/windows/>. It installs the server as a Windows service and `psql`. |
| Red Hat Enterprise Linux, AlmaLinux, Rocky Linux | The PostgreSQL project's repository (<https://www.postgresql.org/download/linux/redhat/>), then `dnf install postgresql18-server` and `postgresql-18-setup initdb`. |
| Debian, Ubuntu | The PostgreSQL project's repository (<https://www.postgresql.org/download/linux/ubuntu/>), then `apt install postgresql-18`. |

`psql`, the command-line client, runs the scripts. Install it wherever you
run them from.

## 2. Set the server's settings

In `postgresql.conf`:

| Setting | Value | Why |
| --- | --- | --- |
| `fsync` | `on` (the default) | Xmip counts a write only once the database has it durably (`runtime-model.md` section 3). Off, a crash loses writes Xmip was told were kept. |
| `synchronous_commit` | `on` (the default) | A commit returns once its write-ahead log is on disk. `off` or `local` with replicas you rely on loses acknowledged writes. Your replication may raise it to `remote_apply`; never lower it. |
| `full_page_writes` | `on` (the default) | Without it a crash can leave a torn page. |
| `ssl` | `on` | Xmip connects over TLS only (section 4). |
| `password_encryption` | `scram-sha-256` (the default) | The login's password is stored and checked as SCRAM. |
| `max_connections` | at least 16 for each Storage node, plus your own | A Storage node keeps a connection for each request it has in flight. |

Leave the transaction isolation at its default, `read committed`. A claim is
one conditional `UPDATE` — set the holder where there is none or the last
claim has lapsed — which takes the row's lock, and a hand-on is one
transaction; neither needs more.

## 3. Run the scripts, in order

Each script says at its top what it is, where to run it and as whom. Run
them as a superuser (`postgres`), from the folder they are in, with
`ON_ERROR_STOP` so a failure stops the script:

```shell
psql --host=db-1.example --port=5432 --username=postgres --dbname=postgres --set=ON_ERROR_STOP=1 --file=01-roles.sql
psql --host=db-1.example --port=5432 --username=postgres --dbname=postgres --set=ON_ERROR_STOP=1 --file=02-databases.sql
psql --host=db-1.example --port=5432 --username=postgres --dbname=xmip_runtime --set=ON_ERROR_STOP=1 --file=03-runtime.sql
psql --host=db-1.example --port=5432 --username=postgres --dbname=xmip_administration --set=ON_ERROR_STOP=1 --file=04-administration.sql
```

| Script | Makes |
| --- | --- |
| `01-roles.sql` | `xmip_owner`, which owns the schema and which no one logs in as, and `xmip_storage`, the login the Storage nodes connect as |
| `02-databases.sql` | `xmip_runtime` and `xmip_administration`, owned by `xmip_owner`, connectable by `xmip_storage` and nobody else |
| `03-runtime.sql` | the schema `xmip` and its tables in `xmip_runtime`, and the right to read and write them for `xmip_storage` |
| `04-administration.sql` | the same in `xmip_administration` |

Placing the administration database on another server: run `01-roles.sql`
on both servers, and `02-databases.sql` with the database that belongs
there.

**Least privilege.** `xmip_storage` may connect to the two databases and
select, insert, update and delete rows in the `xmip` schema's tables, and
nothing else: it cannot create, alter or drop anything. A schema change is
made by an operator granted `xmip_owner` (`GRANT xmip_owner TO <operator>;`).

Then set the login's password, interactively, so it is in no file and no
shell history:

```shell
psql --host=db-1.example --port=5432 --username=postgres --dbname=postgres --command="\password xmip_storage"
```

## 4. TLS on the connection

Give the server a certificate and its key, and require TLS from
`xmip_storage`:

- `postgresql.conf`: `ssl = on`, `ssl_cert_file = 'server.crt'`,
  `ssl_key_file = 'server.key'`, and `ssl_min_protocol_version = 'TLSv1.3'`;
  Xmip's TLS speaks TLS 1.3 first (ADR-0033).
- `pg_hba.conf`: let `xmip_storage` in over TLS only, from the Storage
  nodes' addresses, and refuse it otherwise:

  ```text
  hostssl   xmip_runtime,xmip_administration  xmip_storage  10.0.20.0/24  scram-sha-256
  hostnossl all                               xmip_storage  0.0.0.0/0     reject
  ```

The certificate's name is the host name the Storage nodes connect to. Give
the Xmip operators the certificate of the authority that issued it, as PEM:
it is the Storage node's `trust_anchor` (section 5). Without one, a Storage
node checks the server against its operating system's trust store.

## 5. What a Storage node is given

A Storage node in front of your server names it in its configuration file,
under `[storage.database]` (`module/platform/configure/doc/node-configuration.md`):

```toml
[storage.database]
runtime        = "postgresql://xmip_storage@db-1.example:5432/xmip_runtime"
administration = "postgresql://xmip_storage@db-1.example:5432/xmip_administration"
password       = "xmip-storage-database"
trust_anchor   = "database-authority.pem"
```

- **`runtime`**, **`administration`**: one connection each,
  `postgresql://<login>@<host>[:<port>]/<database>`; the port is 5432 where
  it is left out. Nothing else is written in a connection: no password, no
  option.
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

- **Encryption at rest.** PostgreSQL has no built-in encryption of its
  files; encrypted volumes (BitLocker, LUKS, your storage's own) are the
  usual answer.
- **Backup.** Continuous archiving of the write-ahead log with base backups
  (`pg_basebackup`, or a tool such as pgBackRest or Barman) gives
  point-in-time recovery. The runtime database changes constantly; back it
  up as a live system, not as a nightly copy.
- **Replication and failover.** Streaming replication, and a manager such as
  Patroni for failover. A Storage node reconnects to the host name it was
  given; a failover that moves that name is invisible to Xmip.
- **Retention.** Xmip deletes what its retention says is done (runtime-model
  section 16); do not delete rows by hand.

## Testing against a server

The estate's own test runs Xmip Storage against a real server when it is
given one (`.src/test/database.rs`). Set, where the test runs:

| Variable | Holds |
| --- | --- |
| `XMIP_TEST_POSTGRESQL` | the server, as a connection without its database: `postgresql://xmip_storage@<host>:<port>` |
| `XMIP_TEST_POSTGRESQL_PASSWORD` | the login's password |

The server is set up as above. Without `XMIP_TEST_POSTGRESQL` the test says
`skipped: no postgresql server configured` and runs nothing:

```shell
cargo test --test database --features persist -- --nocapture
```

## SQL Server

SQL Server's guide and scripts are beside this folder, in
`deploy/database/sqlserver/`, written from the same schema definition.
