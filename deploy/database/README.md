# Xmip Storage's database schemas

For the people who run a site's database servers. How to set up Xmip
Storage is in [`postgresql/README.md`](postgresql/README.md) and
[`sqlserver/README.md`](sqlserver/README.md); this page holds the rule both
follow.

## Do not change the schemas

**You may not change the database schemas in any way**: no column, index,
table, constraint, trigger or view added, altered or dropped. A changed
schema breaks support from the Xmip Community.

A change is made through a pull request to Xmip, as a bug fix or a new
feature (`CONTRIBUTING.md`). Once it is merged, it reaches your servers in
the next release of these scripts, which are generated from the one schema
definition Xmip Storage reads and writes by.
