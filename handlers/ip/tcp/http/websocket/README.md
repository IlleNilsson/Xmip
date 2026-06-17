# WebSocket Handler

Placeholder for the WebSocket handler repository.

WebSocket is derived from the base HTTP handler because the connection starts as an HTTP upgrade.

This repository owns WebSocket specific behavior:

- HTTP upgrade handling
- long-lived connection lifecycle
- bidirectional message flow
- frame handling
- connection identity
- authentication and authorization policy after upgrade
- connection-level audit and tracing
- stream handoff to Xmip

Shared HTTP primitives and shared HTTP security belong in the base HTTP handler repository.
