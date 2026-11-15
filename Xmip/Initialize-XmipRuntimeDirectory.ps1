#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    Where the nodes the tooling starts, and the surfaces it runs, keep their
    local endpoints on Linux and macOS: the folder XMIP_RUNTIME_DIRECTORY
    names.

.DESCRIPTION
    A node no service manager started has no /run/xmip or /var/run/xmip of
    its own: those are root's, made by systemd or launchd. Decided by the
    owner, 2026-11-15 (ADR-0014): XMIP_RUNTIME_DIRECTORY names another folder
    for such a run, and nothing falls back on its own, so whatever starts
    one sets it. The tooling is such a starter: it names a folder under the
    user's own runtime directory, and every process it starts inherits it,
    the node binding there and every surface connecting there.

    Style: doc/governance/powershell-style.md
#>


function Initialize-XmipRuntimeDirectory {
    <#
        .SYNOPSIS
            Points this session's local endpoints at xmip under the user's
            runtime directory on Linux ($XDG_RUNTIME_DIR) and macOS
            ($TMPDIR), unless XMIP_RUNTIME_DIRECTORY already names a folder.
            Windows has no folder to name. Private.

        .DESCRIPTION
            Called, as Initialize-XmipAudit is, by Invoke-XmipTool and by
            every command that starts a process before it starts it, so a
            test run, a roll and its nodes, and the surfaces beside them find
            one another. Where the user's runtime directory is not said, the
            variable stays unset and a node refuses in words naming it.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    if (-not [string]::IsNullOrWhiteSpace($env:XMIP_RUNTIME_DIRECTORY)) {
        return
    }

    [string] $own = switch (Get-XmipOperatingSystem) {
        'linux' { $env:XDG_RUNTIME_DIR }
        'macos' { $env:TMPDIR }
        default { '' }
    }

    if ([string]::IsNullOrWhiteSpace($own)) {
        return
    }

    $env:XMIP_RUNTIME_DIRECTORY = "$($own.TrimEnd('/'))/xmip"
}
