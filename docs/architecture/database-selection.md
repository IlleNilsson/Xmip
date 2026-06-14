# Xmip Database Selection

Xmip uses two embedded databases by default.

## Runtime persistence database

Selected default: RocksDB-style embedded key/value store.

Purpose:

- persist message state,
- persist stream references or payloads according to policy,
- persist interchange chains,
- persist interchange history,
- persist process state,
- persist retry state,
- persist failure state,
- persist replay checkpoints,
- persist runtime audit events.

The runtime persistence database is optimized for high write volume and replay from known state.

## Management database

Selected default: SQLite-style embedded relational store.

Purpose:

- node registration,
- cluster membership,
- module inventory,
- handler inventory,
- extension inventory,
- configuration versions,
- deployment state,
- operator metadata,
- management audit,
- queryable administration views.

The management database is optimized for structured management queries and configuration state.

## Audit rule

A successful message handling path shall be auditable.

A failed message handling path shall be auditable and replayable from a persisted state.

Runtime audit is stored with runtime persistence first.

Management may index or report audit information, but runtime persistence is the source of truth for replay.

## Replay rule

Xmip shall persist enough state to replay from an error state.

Replay requires:

- message id,
- interchange chain,
- current interchange id,
- message state,
- process state where applicable,
- send port state where applicable,
- retry state where applicable,
- audit trail,
- failure reason.

## Separation rule

Runtime persistence and management persistence are separate databases.

They may be bundled together by the installer, but they must remain separate stores.
