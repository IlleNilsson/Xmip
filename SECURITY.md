# Xmip Security Policy

Xmip is under active architectural development. Security reports should be handled privately until a fix or mitigation is available.

## Reporting a vulnerability

Do not open a public issue containing exploit details, credentials, secrets, private keys, personal data or instructions that would enable abuse.

Report the vulnerability to the project owner through a private GitHub security advisory when available. Include:

- affected repository and version or commit;
- affected platform and runtime;
- reproduction conditions;
- expected and observed behavior;
- likely impact;
- suggested mitigation, when known.

## Scope

Security-sensitive areas include:

- authentication and authorization;
- credential, certificate and token handling;
- transport security;
- message integrity and immutability;
- deserialization and contract validation;
- plugin and script execution boundaries;
- node and cluster communication;
- configuration distribution;
- durable storage, deduplication and recovery;
- logging, tracking and accidental disclosure.

## Supported versions

Until the first Xmip Linear release, only `main`, Xmip Continuum, is supported, and only it receives security fixes. See [the release model](doc/governance/release-model.md).

## Disclosure

The project will coordinate validation, remediation and disclosure according to severity and operational risk. Credit may be given to reporters who act responsibly and request attribution.