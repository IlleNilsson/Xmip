#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    The one way the module builds a crate of the estate with cargo: in the
    crate's folder, into the target directory it is given, with the
    session's folder and CARGO_TARGET_DIR given back after.

.DESCRIPTION
    xmip-service at the estate root (Build-XmipService), the runtime library
    and the command line a package carries (New-XmipPackage), the runtime
    library's remote builds (Build-XmipRemoteRuntime) and RocksDB's one
    compile (Install-XmipNativeLibrary) all build through it. Every crate is
    a member of the estate's one workspace, resolved once (ADR-0016,
    amendment 2026-11-20): the folder chooses the crate cargo builds, and
    the caller the target directory.

    Style: doc/governance/powershell-style.md
#>


function Invoke-XmipCrateBuild {
    <#
        .SYNOPSIS
            Runs cargo with Argument in Folder of the estate, into
            TargetDirectory; FAILED in words, naming the command and the
            crate's full path, when cargo fails.

        .PARAMETER Folder
            The crate's folder, relative to Root: `.` for the root crate.

        .PARAMETER Argument
            Everything after `cargo`: the subcommand first.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        [string] $Folder,

        [Parameter(Mandatory = $true)]
        [string] $TargetDirectory,

        [Parameter(Mandatory = $true)]
        [string[]] $Argument
    )

    [string] $crate = [IO.Path]::GetFullPath((Join-Path $Root $Folder))
    [string] $was = $env:CARGO_TARGET_DIR
    $env:CARGO_TARGET_DIR = $TargetDirectory
    Push-Location -LiteralPath $crate

    try {
        if (-not (Invoke-XmipTool -Tool cargo -Argument $Argument -Prefix '     cargo| ').Passed) {
            throw "FAILED: cargo $($Argument -join ' '), in $crate."
        }
    }
    finally {
        Pop-Location

        if ($was) {
            $env:CARGO_TARGET_DIR = $was
        }
        else {
            Remove-Item -Path 'env:CARGO_TARGET_DIR' -ErrorAction SilentlyContinue
        }
    }
}
