#requires -PSEdition Core
#requires -Version 7.6.5

using namespace System.Collections.Generic

function Test-XmipChangeTree {
    <#
        .SYNOPSIS
            Verifies a landing's modules, dependencies first, against the
            estate's working trees, and stops at the first that fails.

        .DESCRIPTION
            Returns what verified, what could not be verified here, and the
            module that failed ('.' for the platform repository, empty when
            nothing failed). Nothing is pushed here.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Ordered,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]] $Consumer = @(),

        [Parameter()]
        [switch] $Platform,

        [Parameter()]
        [switch] $All,

        [Parameter()]
        [switch] $NoVerify,

        [Parameter()]
        [string] $Message = ''
    )

    # The dependency tree is verified whole, then landed whole (the owner,
    # 2026-10-05: *Do dependecy tree build and stop when a leaf fails*).
    #
    # Every estate crate is patched to its working tree, so the tree verifies
    # before anything is pushed, leaves first, and the first module that
    # fails stops the run with nothing landed. Every build shares the estate's
    # one build directory, `.ai-interaction/target-windows`, so a dependency
    # such as RocksDB compiles once, not once per module.
    [List[string]] $skipped = [List[string]]::new()
    [List[string]] $verified = [List[string]]::new()
    [bool] $runtimeBuilt = $false

    [string] $sharedTarget = if ($env:CARGO_TARGET_DIR) {
        $env:CARGO_TARGET_DIR
    }
    else {
        Join-Path -Path $RepositoryRoot -ChildPath '.ai-interaction/target-windows'
    }
    [string] $previousTarget = $env:CARGO_TARGET_DIR
    [string] $previousModule = $env:XMIP_MODULE_LIBRARY
    $env:CARGO_TARGET_DIR = $sharedTarget

    try {
        [string] $patch = ''

        # The libraries cargo names without a hash, removed whenever another
        # workspace begins (Clear-XmipUnhashedLibrary says why).
        [string[]] $unhashed = @()

        if (-not $NoVerify) {
            $patch = New-XmipLocalPatch -RepositoryRoot $RepositoryRoot
            $unhashed = @(
                Get-XmipEstateCrate -RepositoryRoot $RepositoryRoot |
                    Where-Object -Property Unhashed |
                    ForEach-Object -MemberName Unhashed
            )
        }

        foreach ($module in $Ordered) {
            if ($NoVerify) {
                $verified.Add($module)
                continue
            }

            # A module is verifiable if it has a Cargo.toml or a project file.
            [string] $modulePath = Join-Path -Path $RepositoryRoot -ChildPath $module
            [string] $manifest = Join-Path -Path $modulePath -ChildPath 'Cargo.toml'

            [bool] $verifiable = (Test-Path -LiteralPath $manifest) -or
                @(Find-XmipFile -Path $modulePath -Filter '*.csproj').Count -gt 0

            if (-not $All -and -not $verifiable) {
                [string] $why = "SKIPPED. $module has no Cargo.toml and no project to verify."
                Write-Host $why -ForegroundColor DarkGray
                $skipped.Add($module)

                continue
            }

            # A .NET module tests against the runtime's library, which
            # Xmip.Abi copies from the shared build directory: built once,
            # from the working tree, before the first .NET module verifies.
            [bool] $dotnet = -not (Test-Path -LiteralPath $manifest) -and
                @(Find-XmipFile -Path $modulePath -Filter '*.csproj').Count -gt 0

            # A Rust module whose tests load the runtime's library names the
            # variable that says where it is; it gets the same fresh build.
            [bool] $loadsRuntime = $dotnet -or
                (Test-XmipRuntimeLibraryReader -Path $modulePath)

            [string[]] $failed = @()

            # A failed runtime build fails the module that needed it: a
            # stale library must never be tested in its place.
            if ($loadsRuntime -and -not $runtimeBuilt) {
                [hashtable] $runtimeLibrary = @{
                    RepositoryRoot = $RepositoryRoot
                    Module         = 'module/platform/runtime'
                    Patch          = $patch
                    Library        = $unhashed
                }
                $runtimeBuilt = Build-XmipTestLibrary @runtimeLibrary

                if (-not $runtimeBuilt) {
                    $failed = @($module)
                }

                [string] $file = if ($IsWindows) { 'xmip_core_runtime.dll' }
                else { 'libxmip_core_runtime.so' }
                $env:XMIP_RUNTIME_LIBRARY =
                    Join-Path -Path $env:CARGO_TARGET_DIR -ChildPath "debug/$file"
            }

            # The runtime's tests open the Rust contract module's library:
            # built from the working tree into the shared directory and named
            # to them, never one left in that module's own target.
            if ($module -eq 'module/platform/runtime' -and $failed.Count -eq 0) {
                [hashtable] $contractLibrary = @{
                    RepositoryRoot = $RepositoryRoot
                    Module         = 'module/core/capability/contract/rust'
                    Patch          = $patch
                    Library        = $unhashed
                }

                if (Build-XmipTestLibrary @contractLibrary) {
                    [string] $file = if ($IsWindows) { 'xmip_core_contract_rust.dll' }
                    else { 'libxmip_core_contract_rust.so' }
                    $env:XMIP_MODULE_LIBRARY =
                        Join-Path -Path $env:CARGO_TARGET_DIR -ChildPath "debug/$file"
                }
                else {
                    $failed = @($module)
                }
            }

            [hashtable] $verify = @{
                RepositoryRoot = $RepositoryRoot
                Module         = @($module)
                All            = $All
                Patch          = $patch
                CheckOnly      = $Consumer -contains $module
            }

            if ($failed.Count -eq 0) {
                Clear-XmipUnhashedLibrary -TargetDirectory $sharedTarget -Library $unhashed
                $failed = @(Test-XmipModule @verify)
            }

            if ($failed.Count -gt 0) {
                Write-Host ''
                [string] $stop = "FAILED. Stopping at $module. Nothing landed this run."
                Write-Host $stop -ForegroundColor Red

                if ($verified.Count -gt 0) {
                    [string] $before = "  verified before it: $($verified -join ', ')"
                    Write-Host $before -ForegroundColor Yellow
                }

                Write-Host 'Fix this one and run again.'

                # Verified is false: the run stopped because a module did not
                # verify, and nothing was pushed.
                [string] $stopped =
                    "The landing stopped at $module, which did not verify; nothing landed."
                [hashtable] $stoppedAt = @{
                    Action   = 'Publish-XmipChange'
                    Phase    = 'Failure'
                    Severity = 'Error'
                    Message  = $stopped
                    Property = @{ Module = $module; Verified = $verified; Subject = $Message }
                }
                Write-XmipAudit @stoppedAt
                Write-Error $stopped -ErrorAction Continue

                return [pscustomobject]@{
                    Verified = $verified.ToArray(); Skipped = $skipped.ToArray(); Failed = $module
                }
            }

            $verified.Add($module)
        }

        # The service itself — the root crate, which links every technology
        # its features name — consumes everything, so it is built, tested and
        # linted with its features against the working trees on every landing
        # (an external review, 2026-10-06). Then the root's own test/, when it
        # changed. Both before anything is pushed.
        [hashtable] $service = @{
            RepositoryRoot = $RepositoryRoot
            Module         = @('.')
            Patch          = $patch
        }
        Clear-XmipUnhashedLibrary -TargetDirectory $sharedTarget -Library $unhashed
        [bool] $serviceBroken = -not $NoVerify -and @(Test-XmipModule @service).Count -gt 0

        if ($serviceBroken -or (-not $NoVerify -and $Platform -and
                -not (Test-XmipPlatform -RepositoryRoot $RepositoryRoot))) {
            [string] $unverified = 'The platform repository did not verify; nothing landed.'
            Write-Error $unverified -ErrorAction Continue

            return [pscustomobject]@{
                Verified = $verified.ToArray(); Skipped = $skipped.ToArray(); Failed = '.'
            }
        }
    }
    finally {
        $env:CARGO_TARGET_DIR = $previousTarget
        $env:XMIP_MODULE_LIBRARY = $previousModule
    }

    [pscustomobject]@{ Verified = $verified.ToArray(); Skipped = $skipped.ToArray(); Failed = '' }
}

function Test-XmipPlatform {
    <#
        .SYNOPSIS
            Runs the platform repository's own tests, every file of test/, in a
            fresh pwsh, and says whether they passed.

        .DESCRIPTION
            A change to the root — the landing scripts and their tests among it —
            went straight to the pin step unverified (an external review,
            2026-10-05).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot
    )

    Write-Host '== the platform repository (test/)' -ForegroundColor Cyan

    [string] $tests = Join-Path -Path $RepositoryRoot -ChildPath 'test'
    [string] $manifest = Join-Path -Path $PSScriptRoot -ChildPath 'Xmip.psd1'

    # The estate suite's own Pester configuration — its *.Test.ps1 names
    # among it — never a second one written here.
    [scriptblock] $run = {
        param([string] $Manifest, [string] $Path)

        Import-Module -Name $Manifest
        [PesterConfiguration] $configuration = & (Get-Module -Name Xmip) {
            param([string] $Path) Get-XmipPesterConfiguration -Path $Path
        } $Path
        $configuration.Run.Exit = $true
        $configuration.Output.Verbosity = 'Normal'
        Invoke-Pester -Configuration $configuration
    }

    & pwsh -NoProfile -Command $run -args $manifest, $tests 2>&1 |
        ForEach-Object { Write-Host $_ }

    $LASTEXITCODE -eq 0
}

function Test-XmipRuntimeLibraryReader {
    <#
        .SYNOPSIS
            Whether a Rust module's sources read XMIP_RUNTIME_LIBRARY, the
            variable naming the runtime library its tests load.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    [System.IO.FileInfo[]] $sources = @(
        foreach ($folder in @('.src', 'src')) {
            [string] $at = Join-Path -Path $Path -ChildPath $folder
            if (Test-Path -LiteralPath $at) {
                Get-ChildItem -LiteralPath $at -Recurse -Filter '*.rs' -File
            }
        }
    )

    if ($sources.Count -eq 0) {
        return $false
    }

    [hashtable] $search = @{
        LiteralPath = $sources.FullName
        Pattern     = 'XMIP_RUNTIME_LIBRARY'
        SimpleMatch = $true
        Quiet       = $true
    }

    [bool] (Select-String @search)
}

function Build-XmipTestLibrary {
    <#
        .SYNOPSIS
            Builds one module's library from the working tree into the shared
            build directory, for the tests that load it: the runtime's, which
            Xmip.Abi copies for every .NET module, and the Rust contract
            module's, which the runtime's tests open.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [string] $Module,

        [Parameter(Mandatory)]
        [string] $Patch,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Library
    )

    Write-Host "== $Module's library, for the tests that load it" -ForegroundColor Cyan
    Clear-XmipUnhashedLibrary -TargetDirectory $env:CARGO_TARGET_DIR -Library $Library
    Push-Location -LiteralPath (Join-Path -Path $RepositoryRoot -ChildPath $Module)

    try {
        & cargo build --config $Patch 2>&1 | ForEach-Object { Write-Host $_ }

        $LASTEXITCODE -eq 0
    }
    finally {
        Pop-Location
    }
}
