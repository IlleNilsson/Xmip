# Xmip Architecture Reconciler v1

`Set-XmipArchitecture.ps1` remains the public entry point. The implementation is divided by responsibility under `scripts/architecture/Modules`.

## Modules

- `Xmip.Manifest.psm1` — manifest loading, expansion and version compatibility.
- `Xmip.Validation.psm1` — repository, dependency and submodule validation.
- `Xmip.GitHub.psm1` — GitHub repository discovery and reconciliation.
- `Xmip.Submodules.psm1` — deterministic submodule inspection and reconciliation.
- `Xmip.Cargo.psm1` — non-destructive Cargo workspace reconciliation.
- `Xmip.Drift.psm1` — desired-state versus actual-state comparison.
- `Xmip.Reporting.psm1` — transaction and drift reports.

## Execution contract

The script is a desired-state reconciler and must be safe to run repeatedly.

- Without `-Apply`, it is read-only and reports intended actions.
- With `-Apply`, only explicitly selected operations may change state.
- Unexpected repositories and submodules are reported but never deleted automatically.
- Submodules are pinned to an explicit revision when the manifest defines one.
- Existing Cargo manifests are never replaced wholesale.

## Version contract

The script and manifest use semantic versions:

```json
{
  "schemaVersion": "1.2.0",
  "architectureVersion": "1.0.0",
  "minimumScriptVersion": "1.0.0"
}
```

The script must refuse a manifest whose `minimumScriptVersion` is newer than the script version or whose schema major version is unsupported.

## Repository lifecycle

Repository existence and implementation maturity remain separate. Supported maturity values are:

```text
reserved
scaffolded
implemented
verified
supported
deprecated
retired
```

Actual reconciliation progress is reported separately as:

```text
missing
created
configured
submodule-missing
submodule-present
metadata-missing
metadata-current
misconfigured
unexpected
```

## Freeze criteria

Version 1.0 is ready for broad execution when:

1. PowerShell parsing and Pester tests pass.
2. Plan mode performs no repository, submodule, Cargo or metadata writes.
3. Apply mode is idempotent across two consecutive runs.
4. Transaction reporting accounts for every selected repository.
5. Deprecated, retired and unexpected items are reported without automatic deletion.
6. A small canary architecture builds, installs and runs successfully.

`_origins` remains until Xmip builds, installs and runs successfully.