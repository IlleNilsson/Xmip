# Xmip

Xmip is a cross-platform messaging and integration platform built around immutable Streams, immutable Messages, long-running Journeys, modular capabilities and implied Contracts.

This repository is the integration and architecture repository. Purpose-specific repositories are created and reconciled from [`xmip-architecture.json`](xmip-architecture.json) and referenced as Git submodules where defined.

## Authoritative architecture

The current architecture baseline is:

- [`docs/Xmip-Architecture-Specification-v1.1.md`](docs/Xmip-Architecture-Specification-v1.1.md)
- [`xmip-architecture.json`](xmip-architecture.json)
- [`Set-XmipArchitecture.ps1`](Set-XmipArchitecture.ps1)

Architecture changes must update the specification and manifest together.

## Runtime lifecycle

```text
Incoming Stream
    -> Transport identification
    -> Transport authentication
    -> Transport authorization
    -> Message creation
    -> Default promotion
    -> Optional message identification
    -> Optional message authentication
    -> Optional message authorization
    -> Contract implication
    -> Optional deserialization
    -> Validation
    -> Journey creation
```

Transport security is completed before Message creation. A Journey begins only after required validation succeeds.

## Core vocabulary

**Stream**  
Immutable data received by or produced within Xmip.

**Message**  
An immutable Xmip object containing one or more immutable sections. Each accepted incoming Stream becomes a section with its own identifier.

**Message Context**  
Metadata and promoted values available to configuration, routing and processing.

**Journey**  
The execution context and lineage of related Messages and actions after required validation has succeeded.

**Contract**  
A schema, profile, standard or code used to imply and evaluate structural expectations. A Contract does not execute itself.

**Artifact Definition**  
TOML configuration describing intended Xmip behaviour.

**Artifact Instance**  
An Artifact Definition bound at runtime to loaded module code satisfying Xmip contracts.

## Contract implication

Xmip does not merely select a Contract by name.

```text
Receive Configuration
+ Incoming Stream
+ Message Context
    -> Implied Contract
    -> Evaluation and validation
```

`xmip-contract` owns Contract implication, evaluation coordination and results. Technology repositories implement specific Contract technologies such as XML Schema and JSON Schema.

## Representation, Contract and Path

These responsibilities are independent:

- **Message representation:** XML, JSON, CSV, HL7 ER7, binary and similar forms.
- **Contract:** XML Schema, JSON Schema, FHIR profiles, HL7 profiles and custom code.
- **Path:** XPath, JSONPath, dot paths, indexes, JSON Pointer and FHIRPath.

FHIR is a Contract and domain-standard family represented through XML or JSON. SOAP is an envelope/protocol concern, not a generic Message representation.

## Send security responsibility

A Send Location presents configured identity material such as credentials, certificates, tokens and claims. The external receiver performs identification, authentication and authorization.

## Repository classification

```text
Foundation   Things Xmip is
Capabilities Things Xmip does
Technology   How a capability is implemented
Operations   Running and governing Xmip
Platform     Platform-wide runtime services
```

Technology repositories are direct children of their common capability repository and become first-party Git submodules according to the manifest.

## Reconcile the architecture

Plan mode is read-only:

```powershell
./Set-XmipArchitecture.ps1 -IncludeReserved
```

Apply the desired state explicitly:

```powershell
./Set-XmipArchitecture.ps1 `
  -IncludeReserved `
  -Apply `
  -CreateRepositories `
  -ConfigureRepositories `
  -SynchronizeSubmodules
```

The script reports missing, unexpected, deprecated, retired and misconfigured items. It never deletes repositories automatically.
