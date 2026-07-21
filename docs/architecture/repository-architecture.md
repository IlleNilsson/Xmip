# Xmip Repository Architecture

`xmip-architecture.json` is the authoritative desired state for Xmip repositories and their future Git submodule relationships.

`Set-XmipArchitecture.ps1` reconciles GitHub and local parent repositories with that manifest. It is intended to be run repeatedly and remain idempotent.

## Classification

- Foundation: things Xmip is.
- Capabilities: things Xmip does.
- Technology: how a capability is implemented.
- Operations: running and governing Xmip.
- Platform: platform-wide runtime services.

Technology repositories are children of common capability repositories. Their physical submodule path follows the capability hierarchy, for example:

```text
xmip-path/
└── modules/
    ├── xpath/
    ├── jsonpath/
    ├── dot/
    └── index/
```

## Naming

Repository names use the recognized technology or standard name rather than a file extension or informal abbreviation.

Examples:

```text
xmip-contract-xml-schema
xmip-contract-json-schema
xmip-contract-protocol-buffers
xmip-path-xpath
xmip-path-dot
xmip-path-index
```

## Maturity

Supported maturity values are:

```text
reserved
scaffolded
implemented
verified
supported
deprecated
retired
```

Repository existence is independent of implementation maturity. Reserved repositories are intentionally created because the Xmip territory and technology families are known.

Deprecated and retired repositories are reported on every run. They are excluded from normal creation and submodule synchronization, and active dependencies on them are reported.

## Plan mode

```powershell
./Set-XmipArchitecture.ps1 `
  -ManifestPath ./xmip-architecture.json `
  -IncludeReserved
```

## Apply desired state

```powershell
./Set-XmipArchitecture.ps1 `
  -ManifestPath ./xmip-architecture.json `
  -IncludeReserved `
  -Apply `
  -CreateRepositories `
  -ConfigureRepositories `
  -SynchronizeSubmodules `
  -GenerateMetadata `
  -GenerateCargoWorkspaces `
  -CommitChanges `
  -PushChanges
```

The generated deprecation report is written by default to:

```text
.xmip-work/xmip-deprecated-items.json
```
