# Xmip Linear Kernel 0.1.1

Small executable Rust proof for the current Xmip Linear architecture.

This version keeps execution state as a protobuf binary buffer and models:

Stream In -> Deserialize -> Transform -> Promote -> Publish -> Process Lane -> Delivery Lane -> Send Out

## What this proves

- Xmip starts when a stream enters a receive location.
- The stream is deserialized before transformation.
- Transform occurs before property promotion.
- Promoted properties drive subscription resolution.
- Publish creates availability to subscription-driven lanes.
- Process lane and delivery lane are separated.
- Delivery may go direct from publish/send-out subscription.
- Send out can target multiple locations.
- Storage/preservation is always on.
- Recovery reloads protobuf checkpoint state after crash.

## Run on Windows PowerShell

```powershell
cargo run
```

First run intentionally crashes after `Publish`.

Run again:

```powershell
cargo run
```

The second run reloads `execution-context.pb`, continues from the checkpoint, executes the process lane, delivery lane, and send out.

## Reset demo

```powershell
Remove-Item .\execution-context.pb, .\crash-once.marker -ErrorAction SilentlyContinue
```

## Important

This is not the full platform. It is the smallest executable proof of the current runtime idea.
