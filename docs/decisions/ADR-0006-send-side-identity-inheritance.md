# ADR-0006: Send-side identity inheritance

## Status

Accepted.

## Decision

Xmip send-side execution must resolve the identity exposed to the target independently of receive-side identity.

A Send Location may expose its own identity.

If the Send Location has no identity, identity is inherited from its parent Send Port.

If the Send Port has no identity, identity is inherited from its parent Send Port Group.

If the Send Port Group has no identity, identity is inherited from the Xmip Sending Process.

## Resolution order

```text
Send Location
Send Port
Send Port Group
Xmip Sending Process
```

The first identity found in that order is used.

## Rationale

Xmip is a pub/sub platform. A message may be sent because of orchestration, subscription, replay, recovery, or operational action. The send side must therefore not depend on the original receive identity.

Targets only care which identity Xmip exposes when sending.

## Rule

Identity resolution is part of send runtime, not receive runtime.

Transport handlers receive the resolved send identity and apply it using their own technology-specific mechanism.
