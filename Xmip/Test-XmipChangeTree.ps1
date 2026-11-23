#requires -PSEdition Core
#requires -Version 7.7.0

using namespace System.Collections.Generic

function Test-XmipChangeTree {
    <#
        .SYNOPSIS
            Verifies a landing's modules against the estate's working trees,
            its independent parts side by side, and says what failed.

        .DESCRIPTION
            Returns what verified, what could not be verified here, and what
            failed (a module, or a part: Rust, .NET, Pester; empty when
            nothing failed). Nothing is pushed here.

            The estate is one Cargo workspace (ADR-0016, amendment
            2026-11-20), so every crate already builds against every working
            tree: the root's [patch] says so, and nothing is written for a
            landing. In order:

            1. What the parts load, built once from the working tree into the
               shared build directory: the runtime's library, its remote
               build where `operate` lands, the test module's library where
               the runtime does. The .NET and Pester parts read a copy of the
               runtime's library, so the Rust part may build over the
               original while they run.
            2. The parts, side by side (Invoke-XmipLandingPart): Rust, every
               changed crate and the root crate in the workspace, every
               consumer linted against the change (Test-XmipRustChange);
               .NET, every changed or consuming .NET project, and a changed
               crate's extension shell and Event bindings
               (Test-XmipDotnetChange); Pester, the root's `test/` when the
               root changed (Test-XmipPlatform).
            3. The timing programs of the changed crates and the root's,
               alone, after every part has passed (rust-style.md 5c).

            The first failure stops the run with nothing landed (the owner,
            2026-10-05: *Do dependency tree build and stop when a leaf
            fails*).

            With -Alone it verifies the modules named and nothing else, for
            Core.Internal (Start-XmipInternalSuite): not the root crate, the
            timing programs' lints or the timing programs, and nothing of it
            is recorded as a landing's, its time or its failure.
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
        [string] $Message = '',

        [Parameter()]
        [switch] $Alone
    )

    [List[string]] $skipped = [List[string]]::new()
    [List[string]] $verified = [List[string]]::new()

    if ($NoVerify) {
        return [pscustomobject]@{ Verified = @($Ordered); Skipped = @(); Failed = '' }
    }

    # Where cargo builds: the estate's one rule (Get-XmipEstateLayout, Build).
    [string] $sharedTarget = (Get-XmipEstateLayout -Root $RepositoryRoot).Build
    [string] $previousTarget = $env:CARGO_TARGET_DIR
    [string] $previousRuntime = $env:XMIP_RUNTIME_LIBRARY
    [string] $previousModule = $env:XMIP_MODULE_LIBRARY
    $env:CARGO_TARGET_DIR = $sharedTarget

    try {
        # What changed, by kind. A consumer of a change is a Rust crate the
        # workspace lints against it, or a .NET project verified whole.
        [List[string]] $crates = [List[string]]::new()
        [List[string]] $crateFolders = [List[string]]::new()
        [List[string]] $dotnet = [List[string]]::new()
        [bool] $loadsRuntime = $Platform

        foreach ($module in $Ordered) {
            [string] $path = Join-Path -Path $RepositoryRoot -ChildPath $module
            [string] $manifest = Join-Path -Path $path -ChildPath 'Cargo.toml'
            [bool] $cargo = Test-Path -LiteralPath $manifest
            [bool] $projects = @(Find-XmipFile -Path $path -Filter '*.csproj').Count -gt 0
            [bool] $consuming = $Consumer -contains $module
            [bool] $other = $projects -or
                (Test-Path -LiteralPath (Join-Path $path 'extension/package.json')) -or
                (Test-Path -LiteralPath (Join-Path $path $script:XmipEventBinding))

            # Cannot be verified here and did not fail are different answers:
            # skipped, or landed unverified under -All.
            if (-not $cargo -and -not $projects) {
                [string] $why = "SKIPPED. $module has no Cargo.toml and no project to verify."
                Write-Host $why -ForegroundColor DarkGray

                if ($All) {
                    $verified.Add($module)
                }
                else {
                    $skipped.Add($module)
                }

                continue
            }

            if ($cargo -and -not $consuming) {
                $crates.Add($module)
                $crateFolders.Add($path)
                $loadsRuntime = $loadsRuntime -or (Test-XmipRuntimeLibraryReader -Path $path)
            }

            if ((-not $cargo -and $projects) -or ($cargo -and -not $consuming -and $other)) {
                $dotnet.Add($module)
                $loadsRuntime = $true
            }

            $verified.Add($module)
        }

        # 1. What the parts load.
        [hashtable] $loads = @{
            RepositoryRoot = $RepositoryRoot; Ordered = $Ordered; Runtime = $loadsRuntime
        }
        [string] $failed = Build-XmipLandingLibrary @loads

        # 2. The parts, side by side.
        if (-not $failed) {
            [string] $landing = (Get-XmipEstateLayout -Root $RepositoryRoot).Landing
            [string] $copy = Join-Path -Path $landing -ChildPath 'runtime'
            [hashtable] $reading = @{ CARGO_TARGET_DIR = $copy }

            if ($env:XMIP_RUNTIME_LIBRARY) {
                [string] $file = Split-Path -Leaf $env:XMIP_RUNTIME_LIBRARY
                $reading.XMIP_RUNTIME_LIBRARY = Join-Path $copy "debug/$file"
            }

            [List[hashtable]] $parts = [List[hashtable]]::new()

            if (-not $Alone -or $crates.Count -gt 0) {
                $parts.Add(@{
                        Name     = 'Rust'
                        Command  = 'Test-XmipRustChange'
                        Argument = @{
                            RepositoryRoot = $RepositoryRoot
                            Module         = $crates.ToArray()
                            Consumer       = $Consumer.Count -gt 0
                            Alone          = [bool] $Alone
                        }
                    })
            }

            if ($dotnet.Count -gt 0) {
                $parts.Add(@{
                        Name        = '.NET'
                        Command     = 'Test-XmipDotnetChange'
                        Argument    = @{
                            RepositoryRoot = $RepositoryRoot
                            Module         = $dotnet.ToArray()
                        }
                        Environment = $reading
                    })
            }

            if ($Platform) {
                $parts.Add(@{
                        Name        = 'Pester'
                        Command     = 'Test-XmipPlatform'
                        Argument    = @{ RepositoryRoot = $RepositoryRoot }
                        Environment = $reading
                    })
            }

            # How long the last landing's parts and timing programs took (the
            # owner, 2026-10-13: *A timer, letting one know how long it is
            # going to take*): side by side, the longest part, then the timing.
            [hashtable] $last = Get-XmipVerifyTime -RepositoryRoot $RepositoryRoot
            [timespan[]] $known = @(
                $parts | ForEach-Object { $last[$_.Name] } | Where-Object { $_ }
            )
            [string] $left = if ($Alone) {
                'the modules named alone'
            }
            elseif ($known.Count -eq $parts.Count -and $last['measured']) {
                [timespan] $longest = $known | Sort-Object -Descending | Select-Object -First 1
                [timespan] $whole = $longest + $last['measured']
                'about {0:N0} minutes left, as the last landing took' -f $whole.TotalMinutes
            }
            else {
                'time left unknown: not yet timed'
            }
            [string] $named = @($parts | ForEach-Object { $_.Name }) -join ', '
            [string] $then = if ($Alone) { '' } else { ', then the timing programs alone' }
            [string] $plan = "$named side by side$then; $left"
            Write-Host $plan -ForegroundColor Cyan

            [object[]] $verdicts = @(
                Invoke-XmipLandingPart -RepositoryRoot $RepositoryRoot -Part $parts
            )
            $failed = @(
                $verdicts | Where-Object { -not $_.Passed } |
                    Select-Object -First 1 -ExpandProperty Name
            ) -join ''

            foreach ($verdict in @($verdicts | Where-Object { $_.Passed -and -not $Alone })) {
                [hashtable] $took = @{ Name = $verdict.Name; Duration = $verdict.Took }
                Set-XmipVerifyTime -RepositoryRoot $RepositoryRoot @took
            }
        }

        # 3. The timing programs, alone, the root's last.
        if (-not $failed -and -not $Alone) {
            [System.Diagnostics.Stopwatch] $clock = [System.Diagnostics.Stopwatch]::StartNew()

            foreach ($folder in @($crateFolders) + $RepositoryRoot) {
                Push-Location -LiteralPath $folder

                try {
                    [string] $manifest = Join-Path -Path $folder -ChildPath 'Cargo.toml'

                    if (-not (Test-XmipMeasuredProgram -ManifestPath $manifest)) {
                        [string] $relative = [IO.Path]::GetRelativePath($RepositoryRoot, $folder)
                        $failed = $relative.Replace('\', '/')
                        break
                    }
                }
                finally {
                    Pop-Location
                }
            }

            if (-not $failed) {
                [hashtable] $timed = @{ Name = 'measured'; Duration = $clock.Elapsed }
                Set-XmipVerifyTime -RepositoryRoot $RepositoryRoot @timed
            }
        }

        if ($failed -and $Alone) {
            Write-Host "FAILED. Stopping at $failed." -ForegroundColor Red

            return [pscustomobject]@{
                Verified = @(); Skipped = $skipped.ToArray(); Failed = $failed
            }
        }

        if ($failed) {
            Write-Host ''
            Write-Host "FAILED. Stopping at $failed. Nothing landed this run." -ForegroundColor Red
            Write-Host 'Fix it and run again.'
            [string] $stopped =
                "The landing stopped at $failed, which did not verify; nothing landed."
            [hashtable] $stoppedAt = @{
                Action   = 'Publish-XmipChange'
                Phase    = 'Failure'
                Severity = 'Error'
                Message  = $stopped
                Property = @{ Module = $failed; Subject = $Message }
            }
            Write-XmipAudit @stoppedAt
            Write-Error $stopped -ErrorAction Continue

            return [pscustomobject]@{
                Verified = @(); Skipped = $skipped.ToArray(); Failed = $failed
            }
        }
    }
    finally {
        $env:CARGO_TARGET_DIR = $previousTarget
        $env:XMIP_RUNTIME_LIBRARY = $previousRuntime
        $env:XMIP_MODULE_LIBRARY = $previousModule
    }

    [pscustomobject]@{ Verified = $verified.ToArray(); Skipped = $skipped.ToArray(); Failed = '' }
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
