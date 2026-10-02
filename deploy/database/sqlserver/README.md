# Xmip Storage on SQL Server: what IT operators set up

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
which you may place on different servers or instances:

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
generated from the same schema definition Xmip Storage's backends read and
write by. SQL Server follows PostgreSQL as a backend (`deployment-model.md`
section 7); until its backend is built, a Storage node cannot yet be
pointed at your server.

## 1. Install SQL Server

Xmip is built against **SQL Server 2025**, the current release; SQL Server
2022 is expected to work and is not tested.

| Edition | For |
| --- | --- |
| Developer | tests and development; free, and not licensed for production |
| Express | a small site; free, each database at most 10 GB, which the runtime database outgrows at any real volume |
| Standard, Enterprise | production |

| Platform | How |
| --- | --- |
| Windows Server | The installer from <https://www.microsoft.com/sql-server/sql-server-downloads>. |
| Red Hat Enterprise Linux, Ubuntu, SUSE Linux Enterprise | Microsoft's repository for your distribution (<https://learn.microsoft.com/sql/linux/sql-server-linux-setup>), then `dnf install mssql-server` or `apt install mssql-server`, and `/opt/mssql/bin/mssql-conf setup`. |

`sqlcmd`, the command-line client, runs the scripts: `winget install
sqlcmd` on Windows, the `mssql-tools18` package on Linux. Install it
wherever you run them from.

## 2. The settings Xmip depends on

| Setting | Value | Why |
| --- | --- | --- |
| Delayed durability, per database | `DISABLED` | Xmip counts a write only once the database has it durably (`runtime-model.md` section 3). `FORCED` returns a commit before its log is on disk, and a crash loses writes Xmip was told were kept. `02-databases.sql` sets it; leave it so. |
| Isolation | `READ COMMITTED`, the default; `READ_COMMITTED_SNAPSHOT` on or off | A claim is one conditional `UPDATE` — set the holder where there is none or the last claim has lapsed — which takes the row's lock, and a hand-on is one transaction; neither needs more. |
| Encryption of connections | Force Strict Encryption | Xmip connects over TLS only (section 4). |
| User connections | at least 16 for each Storage node, plus your own | A Storage node keeps a connection for each request it has in flight. |

## 3. Run the scripts, in order

Each script says at its top what it is and as whom it runs. Run them as a
member of `sysadmin`, from the folder they are in, with `-b` so a failure
stops the script. The login's password is a scripting variable,
`StoragePassword`: give it in the environment for the one command, so it is
in no file and no shell history.

```powershell
$env:StoragePassword = Read-Host -Prompt 'xmip_storage password' -MaskInput
sqlcmd -S tcp:sql-1.example,1433 -E -b -i 01-roles.sql
Remove-Item -Path Env:StoragePassword
sqlcmd -S tcp:sql-1.example,1433 -E -b -i 02-databases.sql
sqlcmd -S tcp:sql-1.example,1433 -E -b -i 03-runtime.sql
sqlcmd -S tcp:sql-1.example,1433 -E -b -i 04-administration.sql
```

`-E` connects with your Windows account; use `-U <login>` with a SQL
Server login of the `sysadmin` role instead where you have none.

| Script | Makes |
| --- | --- |
| `01-roles.sql` | the login `xmip_storage`, which the Storage nodes connect as, with the password policy checked |
| `02-databases.sql` | `xmip_runtime` and `xmip_administration`, each with delayed durability disabled |
| `03-runtime.sql` | in `xmip_runtime`: the role `xmip_owner`, which owns the schema `xmip`; the schema's tables; the user `xmip_storage` and its right to read and write them |
| `04-administration.sql` | the same in `xmip_administration` |

Placing the administration database on another instance: run
`01-roles.sql` on both, and on each the rest for the database that belongs
there.

**Least privilege.** `xmip_storage` may select, insert, update and delete
rows in the `xmip` schema, and nothing else: it cannot create, alter or drop
anything, and holds no server role. A schema change is made by an operator
added to `xmip_owner` (`ALTER ROLE xmip_owner ADD MEMBER <operator>;`).

An identifier is a UUIDv7, kept as `binary(16)`, not `uniqueidentifier`:
SQL Server sorts `uniqueidentifier` by its last bytes first, which would
scatter keys written in time order (`module/platform/persist/doc/record-identifier.md`).

## 4. TLS on the connection

Give the instance a certificate whose name is the host name the Storage
nodes connect to, and turn on **Force Strict Encryption** (SQL Server
Configuration Manager, the instance's network configuration; on Linux,
`mssql-conf set network.forcedencryption 1` with `network.tlscert` and
`network.tlskey`). Strict encryption is TDS 8.0: TLS from the first byte,
which is how Xmip connects.

Give the Xmip operators the certificate of the authority that issued it, as
PEM: it is the Storage node's `trust_anchor` (section 5). Without one, a
Storage node checks the server against its operating system's trust store.

## 5. What a Storage node is given

A Storage node in front of your server names it in its configuration file,
under `[storage.database]` (`module/platform/configure/doc/node-configuration.md`):

```toml
[storage.database]
runtime        = "sqlserver://xmip_storage@sql-1.example:1433/xmip_runtime"
administration = "sqlserver://xmip_storage@sql-1.example:1433/xmip_administration"
password       = "xmip-storage-database"
trust_anchor   = "database-authority.pem"
```

- **`runtime`**, **`administration`**: one connection each,
  `sqlserver://<login>@<host>[:<port>]/<database>`; the port is 1433 where
  it is left out. A named instance is reached by its port: give it a fixed
  one. Nothing else is written in a connection: no password, no option.
- **`password`**: the **name** of the secret the password is kept under on
  the Storage node, resolved through Xmip's key home (ADR-0063 clause 4).
  The password itself is never written in the configuration file. How the
  password is placed in the key home under that name is the key home's to
  provide, and is not built yet.
- **`trust_anchor`**: the authority's certificate from section 4, PEM,
  relative to the configuration file.

So the Xmip operators need from you: each database's host and port, the
login's password (handed over the way your site hands over secrets), and
the authority's certificate. A Storage node logs in as a SQL Server login;
Windows authentication with a group managed service account is not
supported yet.

## 6. Your choices

What follows is yours to decide, and Xmip neither does it nor depends on how
it is done (`deployment-model.md` section 9):

- **Encryption at rest.** Transparent Data Encryption, or encrypted volumes.
- **Backup.** The full recovery model with log backups gives point-in-time
  recovery. The runtime database changes constantly; back it up as a live
  system, not as a nightly copy.
- **Replication and failover.** Always On availability groups, or a failover
  cluster instance. Connect the Storage nodes to the availability group's
  listener; a failover behind it is invisible to Xmip.
- **Retention.** Xmip deletes what its retention says is done (runtime-model
  section 16); do not delete rows by hand.

## Testing against a server

The estate's own test runs Xmip Storage against a real server when it is
given one (`.src/test/database.rs`). Set, where the test runs:

| Variable | Holds |
| --- | --- |
| `XMIP_TEST_SQLSERVER` | the server, as a connection without its database: `sqlserver://xmip_storage@<host>:<port>` |
| `XMIP_TEST_SQLSERVER_PASSWORD` | the login's password |

The server is set up as above. Without `XMIP_TEST_SQLSERVER` the test says
`skipped: no sqlserver server configured` and runs nothing:

```shell
cargo test --test database --features persist -- --nocapture
```

## PostgreSQL

PostgreSQL's guide and scripts are beside this folder, in
`deploy/database/postgresql/`, written from the same schema definition.
