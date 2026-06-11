# Xmip Continuum

This repository's `main` branch represents **Xmip Continuum**.

Xmip Continuum is the forward-moving architecture and runtime line where the Xmip platform is shaped, corrected, expanded, and consolidated.

## Branch strategy

- `main` is Xmip Continuum.
- Xmip Linear belongs on a release branch.
- Fixes made on the Xmip Linear release branch shall be merged back into Xmip Continuum `main` when applicable.
- Continuum may move beyond Linear, but Linear fixes must not be lost.

In short:

```text
Xmip Linear release branch
    -> fixes merge forward into
Xmip Continuum main
```

## Current executable proof

The current Rust executable started as the Xmip Linear Kernel proof.

It is now carried inside Xmip Continuum as executable evidence, not as the branch identity.

The proof models runtime ideas such as:

```text
External Stream
    -> Receive
    -> Identify / Authorize
    -> Accept
    -> Promote
    -> Publish
    -> Process / Send outcome
```

It also contains early code for:

- receive endpoint claims,
- receive acquisition modes,
- receive transport/protocol hints,
- receive identity and authorization,
- send ports and send locations,
- outbound send identity,
- cluster identity,
- runtime persistence records.

## Run the executable proof

```powershell
cargo run
```

The older linear recovery demo may intentionally crash after `Publish` on the first run and continue after checkpoint reload on the next run.

Reset demo state:

```powershell
Remove-Item .\execution-context.pb, .\crash-once.marker -ErrorAction SilentlyContinue
```

The module runtime proof can be run with a selected receive endpoint:

```powershell
cargo run --bin module_runtime -- http
cargo run --bin module_runtime -- file
cargo run --bin module_runtime -- rabbitmq
```

## Important

This is not the full Xmip platform.

This repository is currently the Xmip Continuum design and executable proof line.

Xmip Linear is a release-line concern, not the identity of `main`.
