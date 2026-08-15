# This script is intentionally retired.
# Crate desired state follows xmip-architecture.json and the Xmip repository template.

throw @'
Initialize-XmipHandlerCrates.ps1 is retired by ADR-0005.

Do not generate xmip-handler-* crates.

Each repository has one primary Rust crate whose name matches the repository name.
Create repository scaffolds from https://github.com/IlleNilsson/xmip-template only
after the repository is accepted in xmip-architecture.json.

This command performs no generation.
'@
