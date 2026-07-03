# Nested Submodule Strategy

Xmip uses nested submodules to avoid making the root repository unmanageable.

## Root level

The root Xmip repository should reference family repositories only.

```text
Xmip
  core        -> xmip-core
  handlers/common      -> xmip-handlers-common
  handlers/messaging   -> xmip-handlers-messaging
  handlers/device      -> xmip-handlers-device
  handlers/industrial  -> xmip-handlers-industrial
  handlers/marine      -> xmip-handlers-marine
  handlers/healthcare  -> xmip-handlers-healthcare
  handlers/business    -> xmip-handlers-business
  handlers/desktop     -> xmip-handlers-desktop
  runtimes             -> xmip-runtimes
  platforms            -> xmip-platforms
```

## Nested level

Family repositories reference specific implementation repositories.

Example:

```text
xmip-handlers-common
  file       -> xmip-handler-file
  ftp        -> xmip-handler-ftp
  http       -> xmip-handler-http
  grpc       -> xmip-handler-grpc
  soap       -> xmip-handler-soap
  web-api    -> xmip-handler-web-api
  websocket  -> xmip-handler-websocket
```

Example:

```text
xmip-handlers-marine
  nmea2000   -> xmip-handler-nmea2000
```

## Checkout rule

Use recursive submodule checkout.

```powershell
git submodule update --init --recursive
```

## Cleanup rule

Loose `xmip-handler-*` repositories are not deleted merely because they are loose today. They should be attached under a family repository, renamed, or explicitly marked for deletion after review.
