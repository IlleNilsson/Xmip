# Xmip Installer

Xmip shall have a simple installer.

The preferred installation path is through package managers.

The installer shall install:

- Xmip runtime binaries,
- Xmip management binaries,
- default TOML configuration,
- service definitions where supported,
- bundled runtime persistence database,
- bundled management database.

## Package manager first

Xmip should be installable through platform package managers where practical.

Examples:

- Windows package manager,
- Linux package packages,
- macOS package manager,
- container image package flow.

Manual archive installation may exist, but package-manager installation is the preferred user path.

## Two bundled databases

Xmip installation includes two local databases by default.

### Runtime persistence database

Default engine: RocksDB-style embedded key/value store.

The runtime persistence database stores runtime truth.

It stores:

- messages,
- stream references or payloads according to policy,
- interchange chains,
- interchange history,
- process state,
- retry state,
- failure state,
- replay checkpoints,
- recovery state,
- runtime audit records.

### Management database

Default engine: SQLite-style embedded relational store.

The management database stores management truth.

It stores:

- node registration,
- cluster membership,
- installed modules,
- available handlers,
- available extensions,
- configuration versions,
- deployment state,
- operator metadata,
- management audit,
- queryable administration views.

## Rule

Runtime persistence and management persistence are separate databases.

Runtime persistence is the source of truth for replay.

Management persistence is the source of truth for administration.

## Default local layout

```text
xmip/
    bin/
    config/
    modules/
    data/
        persistence-rocksdb/
        management.sqlite
    logs/
```

## Installer responsibility

The installer creates the directory layout, initializes the two databases, installs default configuration, and registers the Xmip service where the platform supports services.
