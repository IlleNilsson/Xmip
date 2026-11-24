#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    What the landing's parts load, built once from the working tree before
    they run: the runtime's library, its remote build and the test module's
    library.

.DESCRIPTION
    Test-XmipChangeTree builds them first, so the Rust part may build over
    the originals while the .NET and Pester parts read their copies.

    Style: doc/governance/powershell-style.md
#>

function Build-XmipLandingLibrary {
    <#
        .SYNOPSIS
            Builds what the landing's parts load, once, from the working
            tree, and names it to them; the module whose build failed, or
            nothing.

        .DESCRIPTION
            The runtime's library, which Xmip.Operate copies for every .NET
            project and the root's `test/` loads through Xmip.Surface, named
            by XMIP_RUNTIME_LIBRARY and copied for the parts that read it, so
            the Rust part may build over the original while they run; the
            runtime's remote build where `operate` lands, whose tests load
            it; the test module's library where the runtime lands, whose
            tests open it (XMIP_MODULE_LIBRARY). A failed build fails the
            landing: a stale library is never tested in its place.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Ordered,

        [Parameter()]
        [switch] $Runtime
    )

    [string] $built = Join-Path -Path $env:CARGO_TARGET_DIR -ChildPath 'debug'

    if ($Runtime) {
        $library = Get-XmipPackageProgram | Where-Object -Property Kind -EQ 'Library'

        if (-not (Build-XmipTestLibrary -RepositoryRoot $RepositoryRoot -Module $library.Folder)) {
            return $library.Folder
        }

        # Just built where cargo builds, so it is found and named, not built again.
        $env:XMIP_RUNTIME_LIBRARY = Build-XmipRuntimeLibrary -Root $RepositoryRoot
        [string] $landing = (Get-XmipEstateLayout -Root $RepositoryRoot).Landing
        [string] $copy = Join-Path -Path $landing -ChildPath 'runtime/debug'
        $null = New-Item -ItemType Directory -Path $copy -Force
        Copy-Item -LiteralPath $env:XMIP_RUNTIME_LIBRARY -Destination $copy -Force
    }

    if ($Ordered -contains 'module/core/operation/operate') {
        try {
            $null = Build-XmipRemoteRuntime -Root $RepositoryRoot -Platform Desktop
        }
        catch {
            Write-Host $_.Exception.Message -ForegroundColor Red
            return 'module/core/operation/operate'
        }
    }

    if ($Ordered -contains 'module/platform/runtime') {
        [hashtable] $module = @{ RepositoryRoot = $RepositoryRoot; Module = 'test/core/module' }

        if (-not (Build-XmipTestLibrary @module)) {
            return 'test/core/module'
        }

        [string] $file = if ($IsWindows) { 'xmip_core_test_module.dll' }
        else { 'libxmip_core_test_module.so' }
        $env:XMIP_MODULE_LIBRARY = Join-Path -Path $built -ChildPath $file
    }
}

function Build-XmipTestLibrary {
    <#
        .SYNOPSIS
            Builds one module's library from the working tree into the shared
            build directory, for the tests that load it.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [string] $Module
    )

    Write-Host "== $Module's library, for the tests that load it" -ForegroundColor Cyan
    Push-Location -LiteralPath (Join-Path -Path $RepositoryRoot -ChildPath $Module)

    try {
        (Invoke-XmipTool -Tool cargo -Argument @('build')).Passed
    }
    finally {
        Pop-Location
    }
}
