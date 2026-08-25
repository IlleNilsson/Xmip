# This script is intentionally retired.
# Repository desired state is owned by architecture.json.

throw @'
Ensure-XmipHandlerRepositories.ps1 is retired by ADR-0005.

Do not create xmip-handler-* repositories.

Use Xmip-Estate.ps1 in reporting mode to inspect desired state:

    ./Xmip-Estate.ps1 -IncludeReserved

Repository creation remains an explicit apply operation and requires the repository
owner's authorization and a GitHub token supplied outside source control.
'@
