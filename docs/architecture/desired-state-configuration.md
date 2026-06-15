# Xmip Desired State Configuration

Xmip shall support Desired State Configuration for installation and node configuration.

Initial supported approaches:

- Microsoft DSC v3,
- Ansible.

## Purpose

Desired state tooling shall be able to install Xmip and keep a node in the configured state.

It shall support:

- package installation,
- directory layout,
- runtime persistence store path,
- management store path,
- module folder,
- node configuration TOML,
- service registration where supported,
- service running state where supported.

## Rule

Package-manager installation is preferred.

Desired state configuration shall orchestrate package installation and node configuration.

Desired state configuration shall not replace Xmip TOML configuration.

Xmip TOML remains the node and runtime configuration source.

## First targets

### DSC v3

Used primarily for Windows and cross-platform PowerShell-driven environments.

### Ansible

Used primarily for Linux, server automation, and mixed infrastructure environments.

## Default state

A configured Xmip node shall have:

- Xmip installed,
- config folder present,
- module folder present,
- RocksDB-style runtime persistence path present,
- SQLite-style management database path present,
- node TOML present,
- service registered and running where services are supported.
