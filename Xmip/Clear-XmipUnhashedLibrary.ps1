#requires -PSEdition Core
#requires -Version 7.6.5

function Clear-XmipUnhashedLibrary {
    <#
        .SYNOPSIS
            Removes the rlib and rmeta cargo writes without a hash for an
            estate crate that builds a cdylib, before another workspace
            builds in the shared build directory.

        .DESCRIPTION
            Every module is its own cargo workspace, and every workspace
            builds in the one shared build directory. A crate's identity is
            hashed from its path relative to the workspace that builds it, so
            module/platform/configure built from the root is a different
            crate from the same folder built from module/platform/runtime.
            Hashed files keep the two apart. A crate that also builds a
            cdylib — the runtime, the Rust contract module — gets no hash:
            its rlib is one file, and the workspace that wrote it last decides
            which of its dependencies it names.

            Cargo does not see that file change hands: the root's record of
            the runtime stays fresh, and the root's tests link a runtime rlib
            built against the runtime workspace's configure beside the root's
            own, two `xmip_core_configure` in one graph (the landing of
            2026-10-06, once xgit built the runtime library for a Rust module
            that loads it). Removed when a workspace begins, the file is
            rebuilt by that workspace, against its own dependencies. The
            cdylib itself stays: the library tests load is read by path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $TargetDirectory,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Library
    )

    [string] $deps = Join-Path -Path $TargetDirectory -ChildPath 'debug/deps'

    foreach ($name in $Library) {
        foreach ($extension in 'rlib', 'rmeta') {
            [string] $file = Join-Path -Path $deps -ChildPath "lib$name.$extension"

            if (Test-Path -LiteralPath $file) {
                Remove-Item -LiteralPath $file -Force
            }
        }
    }
}
