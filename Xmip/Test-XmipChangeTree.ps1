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

    # The runtime's remote build, from the working tree, before the module
    # that needs it: the Desktop one Xmip.Abi's tests load, the Android ones
    # the phone host packages (Build-XmipRemoteRuntime.ps1).
    [hashtable] $remoteFor = @{
        'module/foundation/abi'     = 'Desktop'
        'module/core/operation/gui' = 'Android'
    }

    [string] $sharedTarget = if ($env:CARGO_TARGET_DIR) {
        $env:CARGO_TARGET_DIR
    }
    else {
        Join-Path -Path $RepositoryRoot -ChildPath '.ai-interaction/target-windows'
    }
    [string] $previousTarget = $env:CARGO_TARGET_DIR
    [string] $previousModule = $env:XMIP_MODULE_LIBRARY
    [string] $previousConfig = $env:XMIP_CARGO_CONFIG
    $env:CARGO_TARGET_DIR = $sharedTarget

    try {
        [string] $patch = ''

        # The libraries cargo names without a hash, removed whenever another
        # workspace begins (Clear-XmipUnhashedLibrary says why).
        [string[]] $unhashed = @()

        if (-not $NoVerify) {
            $patch = New-XmipLocalPatch -RepositoryRoot $RepositoryRoot
            # A test that runs cargo itself, as the Playground's build of its
            # binaries does, resolves through the same working trees: cargo
            # passes no --config down to a cargo a test starts.
            $env:XMIP_CARGO_CONFIG = $patch
            $unhashed = @(
                Get-XmipEstateCrate -RepositoryRoot $RepositoryRoot |
                    Where-Object -Property Unhashed |
                    ForEach-Object -MemberName Unhashed
            )
        }

        # The runtime's library, built once from the working tree into the
        # shared directory and named by XMIP_RUNTIME_LIBRARY to whatever loads
        # it next: a module's tests, and the root's own test/, whose cmdlets
        # load it through Xmip.Surface. Dot-sourced, so $runtimeBuilt holds.
        [scriptblock] $useRuntime = {
            if ($runtimeBuilt) {
                return
            }

            [hashtable] $runtimeLibrary = @{
                RepositoryRoot = $RepositoryRoot
                Module         = 'module/platform/runtime'
                Patch          = $patch
                Library        = $unhashed
            }
            $runtimeBuilt = Build-XmipTestLibrary @runtimeLibrary

            [string] $file = if ($IsWindows) { 'xmip_core_runtime.dll' }
            else { 'libxmip_core_runtime.so' }
            $env:XMIP_RUNTIME_LIBRARY =
                Join-Path -Path $env:CARGO_TARGET_DIR -ChildPath "debug/$file"
        }

        # A line before each module saying where the landing is and about how
        # long is left (the owner, 2026-10-13: *A timer, letting one know how
        # long it is going to take*): from this run's modules once one is
        # measured, before that from the last landing's, which is recorded.
        [hashtable] $lastTime = if ($NoVerify) { @{} }
        else { Get-XmipVerifyTime -RepositoryRoot $RepositoryRoot }
        [string[]] $finalStep = if ($Platform) { @('.', 'test/') } else { @('.') }
        [bool] $finalKnown =
            @($finalStep | Where-Object { -not $lastTime.ContainsKey($_) }).Count -eq 0
        [hashtable] $progress = @{
            Total     = $Ordered.Count
            Recorded  = @($Ordered | Where-Object { $lastTime.ContainsKey($_) } |
                    ForEach-Object { $lastTime[$_] })
            Final     = if ($finalKnown) {
                [timespan]::FromTicks(($finalStep | ForEach-Object { $lastTime[$_].Ticks } |
                            Measure-Object -Sum).Sum)
            }
            FinalName = if ($Platform) { 'the root crate and test/' } else { 'the root crate' }
        }
        [List[timespan]] $measured = [List[timespan]]::new()
        [int] $position = 0
        [System.Diagnostics.Stopwatch] $clock = [System.Diagnostics.Stopwatch]::new()

        foreach ($module in $Ordered) {
            if ($NoVerify) {
                $verified.Add($module)
                continue
            }

            $position++
            [string] $remaining =
                Get-XmipRemainingTime -Index $position -Measured $measured.ToArray() @progress
            Write-Host $remaining -ForegroundColor Cyan
            $clock.Restart()

            # A module is verifiable if it has a Cargo.toml or a project file.
            [string] $modulePath = Join-Path -Path $RepositoryRoot -ChildPath $module
            [string] $manifest = Join-Path -Path $modulePath -ChildPath 'Cargo.toml'

            [bool] $verifiable = (Test-Path -LiteralPath $manifest) -or
                @(Find-XmipFile -Path $modulePath -Filter '*.csproj').Count -gt 0

            # A phone build needs the Android NDK, an optional prerequisite.
            [string] $why = ''

            if (-not $verifiable) {
                $why = "$module has no Cargo.toml and no project to verify."
            }
            elseif ($remoteFor[$module] -eq 'Android' -and -not (Find-XmipAndroidNdk)) {
                $why = "$module builds for Android, and the Android NDK is absent here."
            }

            if (-not $All -and $why) {
                Write-Host "SKIPPED. $why" -ForegroundColor DarkGray
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
            if ($loadsRuntime) {
                . $useRuntime

                if (-not $runtimeBuilt) {
                    $failed = @($module)
                }
            }

            if ($remoteFor.ContainsKey($module) -and $failed.Count -eq 0) {
                [hashtable] $remote = @{
                    Root     = $RepositoryRoot
                    Platform = $remoteFor[$module]
                    Patch    = $patch
                }

                try {
                    $null = Build-XmipRemoteRuntime @remote
                }
                catch {
                    Write-Host $_.Exception.Message -ForegroundColor Red
                    $failed = @($module)
                }
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
            [timespan] $took = $clock.Elapsed
            $measured.Add($took)
            Set-XmipVerifyTime -RepositoryRoot $RepositoryRoot -Name $module -Duration $took
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

        if (-not $NoVerify) {
            [string] $remaining = Get-XmipRemainingTime -Index ($Ordered.Count + 1) -Measured (
                $measured.ToArray()) @progress
            Write-Host $remaining -ForegroundColor Cyan
        }

        $clock.Restart()
        Clear-XmipUnhashedLibrary -TargetDirectory $sharedTarget -Library $unhashed
        [bool] $serviceBroken = -not $NoVerify -and @(Test-XmipModule @service).Count -gt 0

        if (-not $NoVerify -and -not $serviceBroken) {
            Set-XmipVerifyTime -RepositoryRoot $RepositoryRoot -Name '.' -Duration $clock.Elapsed
        }

        # The root's test/ loads the runtime too: never the stale one a
        # module's own target directory may still hold.
        $clock.Restart()

        if (-not $NoVerify -and $Platform) {
            . $useRuntime
        }

        [bool] $platformBroken = -not $NoVerify -and $Platform -and
            (-not $runtimeBuilt -or -not (Test-XmipPlatform -RepositoryRoot $RepositoryRoot))

        if (-not $NoVerify -and $Platform -and -not $platformBroken) {
            [timespan] $took = $clock.Elapsed
            Set-XmipVerifyTime -RepositoryRoot $RepositoryRoot -Name 'test/' -Duration $took
        }

        if ($serviceBroken -or $platformBroken) {
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
        $env:XMIP_CARGO_CONFIG = $previousConfig
    }

    [pscustomobject]@{ Verified = $verified.ToArray(); Skipped = $skipped.ToArray(); Failed = '' }
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
