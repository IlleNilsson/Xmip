#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    What the landing's parts load, built once from the working tree before
    they run: the runtime's library, its remote builds and the test module's
    library.

.DESCRIPTION
    Test-XmipChangeTree builds them first, so the Rust part may build over
    the originals while the .NET and Pester parts read their copies.

    Style: doc/governance/powershell-style.md
#>

# The runtime's remote build a module's build reads, by the module: the
# Desktop one Xmip.Operate's tests load, the Android ones the phone host,
# Xmip.Operations, packages (Build-XmipRemoteRuntime.ps1).
[hashtable] $script:XmipRemoteBuildFor = @{
    'module/core/operation/operate' = 'Desktop'
    'module/core/operation/gui'     = 'Android'
}

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
            it, and its Android build where the phone host's module lands,
            which Xmip.Operations packages, never the last one built by
            hand, each also where a module holds that module as its own, as
            the root does on a test computer (Get-XmipRemoteBuildRead); the
            test module's library where the runtime lands, whose tests open
            it (XMIP_MODULE_LIBRARY). A failed build fails the landing: a
            stale library is never tested in its place.

        .PARAMETER Ordered
            The modules the landing verifies here, in its order: none it
            skipped (Get-XmipLandingSkipReason).
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

    # Each before any part runs, once, in the landing's order; the first that
    # fails names the module that needs it.
    [hashtable] $made = @{}

    foreach ($reader in $Ordered) {
        [hashtable] $reading = @{ RepositoryRoot = $RepositoryRoot; Module = $reader }

        foreach ($platform in @(Get-XmipRemoteBuildRead @reading)) {
            if ($made.ContainsKey($platform)) {
                continue
            }

            $made[$platform] = $true

            try {
                $null = Build-XmipRemoteRuntime -Root $RepositoryRoot -Platform $platform
            }
            catch {
                Write-Host $_.Exception.Message -ForegroundColor Red
                return $reader
            }
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

function Get-XmipLandingSkipReason {
    <#
        .SYNOPSIS
            Why the landing cannot verify a module here, because what its
            build reads cannot be built here, in one sentence; nothing where
            it can.

        .DESCRIPTION
            The phone host's module builds Xmip.Operations for Android, which
            packages the runtime's Android build, and that build needs the
            Android NDK, an optional prerequisite (prerequisite.toml,
            android-ndk). The one rule: the landing skips that module by it,
            builds no Android library by it (Get-XmipRemoteBuildRead), and
            skips Xmip.Operations' Android target by it where another module
            holds the phone host's as its own (Get-XmipProjectFramework).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Module
    )

    if ($script:XmipRemoteBuildFor[$Module] -eq 'Android' -and -not (Find-XmipAndroidNdk)) {
        return "$Module builds the phone host for Android, and the Android NDK is absent here."
    }

    ''
}

function Get-XmipRemoteBuildRead {
    <#
        .SYNOPSIS
            The runtime's remote builds a module's build reads, by Platform:
            that of each module in $script:XmipRemoteBuildFor it is or holds
            as its own folder (Test-XmipOwnFolder), but where that module is
            skipped here (Get-XmipLandingSkipReason).

        .DESCRIPTION
            The root on a test computer holds them both, so its .NET part
            builds Xmip.Operate's tests and Xmip.Operations with the rest
            (open problem 195), and reads both builds as those modules do.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [string] $Module
    )

    [string] $top = Join-Path -Path $RepositoryRoot -ChildPath $Module

    foreach ($reader in @($script:XmipRemoteBuildFor.Keys | Sort-Object)) {
        [string] $folder = Join-Path -Path $RepositoryRoot -ChildPath $reader

        if ((Test-XmipOwnFolder -Top $top -Folder $folder) -and
            -not (Get-XmipLandingSkipReason -Module $reader)) {
            $script:XmipRemoteBuildFor[$reader]
        }
    }
}

function Get-XmipProjectFramework {
    <#
        .SYNOPSIS
            The target frameworks the landing builds a .NET project for here,
            each by -f: one empty name, for every one the project names,
            where all can be built here; else each that can, after one line
            that says which cannot and why; none where none can.

        .DESCRIPTION
            A project in a module the landing skips here
            (Get-XmipLandingSkipReason) cannot be built for that module's
            Platform: Xmip.Operations for Android where the Android NDK is
            absent. Only a module holding that one as its own meets such a
            project, the root on a test computer (open problem 195), and only
            then is the project asked its frameworks (dotnet msbuild
            -getProperty:TargetFrameworks).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [System.IO.FileInfo] $Project
    )

    foreach ($reader in @($script:XmipRemoteBuildFor.Keys | Sort-Object)) {
        [string] $folder = Join-Path -Path $RepositoryRoot -ChildPath $reader
        [string] $why = if (Test-XmipOwnFolder -Top $folder -Folder $Project.DirectoryName) {
            Get-XmipLandingSkipReason -Module $reader
        }

        if ([string]::IsNullOrEmpty($why)) {
            continue
        }

        [string[]] $asked = @(
            'msbuild', $Project.FullName, '-getProperty:TargetFrameworks', '-nologo'
        )
        $named = Invoke-XmipTool -Tool dotnet -Argument $asked -Output Keep
        [string[]] $all = @(
            ($named.Said -join ';') -split ';' | ForEach-Object { $_.Trim() } |
                Where-Object { $_ -match '^net\d+\.\d+(-[a-z]+[\d.]*)?$' }
        )
        [string] $platform = $script:XmipRemoteBuildFor[$reader]
        [string[]] $cannot = @(
            $all | Where-Object { $_ -match '-([a-z]+)[\d.]*$' -and $Matches[1] -eq $platform }
        )

        if (-not $named.Passed -or $cannot.Count -eq 0) {
            continue
        }

        [string] $said = "   SKIPPED. $($Project.BaseName) for $($cannot -join ' and '): $why"
        Write-Host $said -ForegroundColor DarkGray

        return @($all | Where-Object { $_ -notin $cannot })
    }

    return @('')
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
