# Xmip Storage's database schemas

For the people who run a site's database servers. How to set up Xmip
Storage is in [`postgresql/README.md`](postgresql/README.md),
[`mssql/README.md`](mssql/README.md) and
[`mariadb/README.md`](mariadb/README.md); this page holds the rules all
three follow.

## Do not change the schemas

**You may not change the database schemas in any way**: no column, index,
table, constraint, trigger or view added, altered or dropped. A changed
schema breaks support from the Xmip Community.

A change is made through a pull request to Xmip, as a bug fix or a new
feature (`CONTRIBUTING.md`). Once it is merged, it reaches your servers in
the next release of these scripts, which are generated from the one schema
definition Xmip Storage reads and writes by.

## Every database records its schema version

Each database keeps the schema versions it has held in its table
`xmip.schema_version` — on MariaDB `schema_version` in the database — a
row for each, with when it was recorded: the version its
`03-<domain>-schema.sql` made it at, and each an upgrade reached. The
version it holds is the highest. A Storage node reads it as it starts and
refuses a database newer than its build, saying both versions; every
operator surface shows the version each database holds, at
`xmip:///<cluster>/node/<node>/storage/<domain>`.

## A new release

A new release's schema only adds to the one before: a table, a column, an
index. Nothing is dropped or renamed. Its upgrade scripts are generated as
the difference between the two releases, one to each database,
`04-<domain>-upgrade-<from>-<to>.sql`, and run as the schema scripts are,
by the operator who owns the schema, after the release's own: one for each
release in between, in order of their versions. Each records the version
it reached. A database made by a release's `03-<domain>-schema.sql` is at
that release already and runs none. `xmip-cli database <server> --from <version>` and
`Get-XmipDatabaseScript` write the scripts from any release to the one
installed. Until the first release the schema is version 1 and there is
no upgrade.

## Read with SELECT, and nothing else

**You may run SELECT against Xmip's schema objects, and nothing else**: no
insert, update, delete or any other statement. The Xmip Community takes no
responsibility for performance if you do run SELECT against them.
