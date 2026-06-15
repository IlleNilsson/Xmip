# HTTP Handler Family Base

Placeholder for the base HTTP handler repository.

The HTTP handler owns shared HTTP behavior:

- HTTP server and client primitives
- request and response handling
- headers
- methods
- routes
- status codes
- TLS configuration
- certificates
- authentication hooks
- authorization hooks
- identity pass-through
- HTTP logging and diagnostics
- common HTTP security policy

Derived HTTP-family handlers use this base repository instead of duplicating HTTP behavior.

Derived repositories include:

- Web API
- SOAP

The base HTTP handler shall not become the Web API handler or the SOAP handler.
