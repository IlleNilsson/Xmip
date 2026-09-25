# ADR-0063: Xmip encrypts its own traffic and its own storage

- Status: Accepted
- Accepted: 2026-09-25, the owner, in the words quoted below
- Date: 2026-09-25
- Related: ADR-0015 (packaging; amendment 2026-09-25, the engine is
  RocksDB), ADR-0033 (certificates on Receive and Send; TLS is
  `xmip-core-library-tls` and its key exchange hybrid), ADR-0034 (provisioning
  versus usage), ADR-0052 (the surfaces, local and remote), ADR-0062 (every
  tool audits), `doc/planning/open-problems.md` problems 17, 18 and 29

## In brief

- Theme: Identity and security
- Subject: What of Xmip's own traffic and storage is encrypted, and where
- Name: Xmip encrypts its own traffic and its own storage
- Order: 15
- Concepts: encryption in transit; encryption at rest; the key home

**Every connection between Xmip's own parts — node to node, a surface to a
node or to a web host, a tool to the runtime over a network — is mutual TLS
through `xmip-core-library-tls`, with its hybrid key exchange. Everything
Xmip stores of its own — the runtime store, the management store, what it
archives — is encrypted by one layer in `xmip-core-persist`, authenticated
encryption per record, whatever engine holds the bytes. A database that
belongs to someone else, which a transport only reads or writes, is
encrypted or not as its owner configures. The keys come from one key home: a
new `secret` capability, the operating system's key store by default, and
PKCS#11 and vaults as further technologies of it.**

## Context

The owner, 2026-09-25: *Xmip's internal traffic has to support encryption,
so does the storage in RocksDB and SQLite; is that feasible?* It is. The
same hour he found the runtime store had no engine at all and chose RocksDB
(ADR-0015, amendment 2026-09-25).

What exists: `xmip-core-library-tls` (client, server, STARTTLS upgrade,
X25519MLKEM768 first). What does not: any node-to-node protocol (problems 17
and 18); TLS on the web host and the remote surfaces, which speak plain HTTP
on 127.0.0.1 today; a storage engine; a key home.

## Decision

### 1. Internal traffic is mutual TLS, always

A connection between two parts of Xmip is mutual TLS through the TLS
library, both ends presenting a certificate their own provisioning gave them
(ADR-0034). There is no plain-text mode to turn on; a loopback connection
inside one machine is the one exception, and it is said where it is made.
The node-to-node protocol is born encrypted.

### 2. Stored data is encrypted in one place

`xmip-core-persist` encrypts each record before any engine sees it and
authenticates it when it is read back — AES-256-GCM through aws-lc-rs, the
crypto the TLS library already builds. The engine (RocksDB for the runtime,
SQLite for management) stores ciphertext. A key a store looks records up by
is derived with a keyed hash, so the names of what is stored do not leak
either. RocksDB's own C++ encryption hook and SQLCipher are not used: each
would be a second way, for one engine.

### 3. Someone else's database is theirs

The sqlite, mssql, mysql, postgresql and oracle transports write where a
customer points them. Whether that database is encrypted is that customer's
choice, stated in configuration; Xmip passes the key it is given and holds
no opinion.

### 4. The keys come from one home

Data keys are wrapped by a key-encryption key held in the key home,
`xmip-core-secret`, a capability of its own: by default the platform's key
store — Windows DPAPI or CNG under the Service Identity, the Linux kernel
keyring or a file readable by the Service Identity alone, the macOS keychain
— and a hardware module over PKCS#11 or a vault as further technologies of
the same capability. It is also the home phase D's secrets were missing
(`market-position.md` section 8). The owner chose this, 2026-09-25, from
three: the platform and pluggable, a vault only, or PKCS#11 only.

Built 2026-09-25, clauses 2 and 4 (problem 29, steps 1 to 4). The key home
is `xmip-core-secret`, a Capability: `KeyStore` wraps and unwraps a data key
under a named key-encryption key, and `DataKey` is the one place the estate
seals at rest — AES-256-GCM, HKDF-SHA-256 and HMAC-SHA-256 through aws-lc-rs.
Its technologies are `dpapi` (Windows, user scope), `file` (Linux and every
Unix: `0600` in `0700`, refused when wider) and `keychain` (macOS, built and
not yet run there); `pkcs11`, `vault`, `azure-key-vault` and `aws-kms` are
reserved. The Linux kernel keyring is reserved too and not used: it holds a
key until the machine restarts, and a key-encryption key lost at a restart is
lost data. The layer is `EncryptedStore` in `xmip-core-persist`, over the
`rocksdb` and `sqlite` engines; a record that fails its tag is
`PersistError::Refused` with its scope and reason, which the caller audits.
The keyed hash costs the engine the order of its keys, and the management
store its SQL; `deployment-model.md` section 7 says so. Clause 1 waits for the
web host and the node-to-node protocol (problem 29, step 5).

## Consequences

- The web host and the remote surfaces move to TLS; a browser on another
  machine reaches the monitor over HTTPS.
- A lost key-encryption key is lost data. Rotation and recovery belong to
  the key home's design.
- Encryption is audited like any other act (ADR-0062): a record that fails
  its authentication tag is a failure, with the scope and the reason.

## Provenance

**The owner's**, 2026-09-25: the requirement — internal traffic and stored
data are encrypted — RocksDB and SQLite as the engines, and the key home:
the platform's key store, pluggable, one `secret` capability.

**The assistant's**: mutual TLS as the means, the one layer in `persist`,
AES-256-GCM, the keyed hash for lookup keys, the rule that a customer's
database is the customer's, and each platform's key store named in clause 4. Each is the owner's to
strike.
