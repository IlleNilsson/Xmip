# ADR-0006: Send-side identity inheritance

## Status

Accepted.

## In brief

- Theme: Identity and security
- Subject: Send-side identity is resolved independently
- Name: Send-side identity inheritance
- Order: 2
- Concepts: Send Location, Send Port

What Xmip presents outward is resolved without reference to what it
authenticated inbound. A Send Location may carry its own identity; where it has
none, it inherits from its parent Send Port.

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

## Amendment, 2026-09-28: resolved at departure, not yet handed over

The runtime's departure walks the chain for every Send Location a Message
reaches (`SendChain::resolve`, `xmip-core-runtime`'s `departure.rs`) and
records on each departure the level that decided and the value of the
identity that Party holds for sending (`Departed::Sent`'s `presented_from`
and `presented`). The Rule's last sentence is not built: a Send Location's
transport is built through `xmip-core-transport`'s one trait, whose `send`
takes a target and bytes and no identity, and `xmip-core-send`'s
`SendTransport`, which carried one and which no technology implemented, is
deleted as a second transport trait (the owner, 2026-09-28: *no code should
be duplicated*). A Location presents what its own settings give its
technology. Whether the one trait's `send` gains the resolved identity is the
owner's to decide.
