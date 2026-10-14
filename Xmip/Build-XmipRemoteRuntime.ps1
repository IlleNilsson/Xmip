#requires -PSEdition Core
#requires -Version 7.6.5

using namespace System.Collections.Generic

<#
.SYNOPSIS
    The runtime's remote build: --no-default-features --features remote,
    the phone's (ADR-0014, amendment 2026-10-14).

.DESCRIPTION
    Three builds of it, each into its own directory in the working area. The
    Desktop one, for this machine, debug, into .ai-interaction/target-remote,
    is what Xmip.Abi's tests load (RemoteBuildTest). The Android one,
    release, one library per Rust target into .ai-interaction/target-android,
    is what Xmip.Operations packages for a phone through
    Xmip.Abi.Native.props: aarch64-linux-android for a device and
    x86_64-linux-android for the emulator, linked by the Android NDK's clang
    at API level 26. The iOS one, release, only on macOS, where Apple's tools
    run: a static library for aarch64-apple-ios (a device) and one for
    aarch64-apple-ios-sim (the simulator) into .ai-interaction/target-ios,
    for iOS 15, joined by xcodebuild into xmip_core_runtime.xcframework
    there, which Xmip.Operations links whole.

    Built here once, for Build-XmipService -Remote, for the landing before
    it verifies module/foundation/abi and module/core/operation/gui, and for
    the CI's phone-ios job (.github/workflows/rust.yml).

    Style: doc/governance/powershell-style.md
#>


function Find-XmipAndroidNdk {
    <#
        .SYNOPSIS
            The Android NDK's toolchain bin directory, holding the clang that
            links the runtime for Android; empty when this machine has none.

        .DESCRIPTION
            ANDROID_NDK_HOME names an NDK itself. Else the newest version
            under the Android SDK's ndk directory: ANDROID_HOME's when that
            is set, else the per-user SDK, %LOCALAPPDATA%\Android\Sdk on
            Windows and ~/Android/Sdk elsewhere (prerequisite.toml,
            android-ndk). The first whose bin directory is there wins.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    [string] $hostFolder = if ($IsWindows) { 'windows-x86_64' }
    elseif ($IsMacOS) { 'darwin-x86_64' }
    else { 'linux-x86_64' }

    [string] $sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME }
    elseif ($IsWindows) { Join-Path -Path "$env:LOCALAPPDATA" -ChildPath 'Android/Sdk' }
    else { Join-Path -Path $HOME -ChildPath 'Android/Sdk' }

    [List[string]] $candidate = [List[string]]::new()

    if ($env:ANDROID_NDK_HOME) {
        $candidate.Add($env:ANDROID_NDK_HOME)
    }

    [string] $versions = Join-Path -Path $sdk -ChildPath 'ndk'

    if (Test-Path -LiteralPath $versions -PathType Container) {
        [version] $parsed = $null
        Get-ChildItem -LiteralPath $versions -Directory |
            Where-Object { [version]::TryParse($_.Name, [ref] $parsed) } |
            Sort-Object -Property { [version] $_.Name } -Descending |
            ForEach-Object { $candidate.Add($_.FullName) }
    }

    foreach ($ndk in $candidate) {
        [string] $bin = Join-Path -Path $ndk -ChildPath (
            "toolchains/llvm/prebuilt/$hostFolder/bin")

        if (Test-Path -LiteralPath $bin -PathType Container) {
            return $bin
        }
    }

    return ''
}


function Get-XmipRemoteRuntimeBuild {
    <#
        .SYNOPSIS
            The cargo builds a Platform's remote build is: per Rust target,
            its target directory, its cargo subcommand (`build --lib`, or
            `rustc --lib --crate-type staticlib` for iOS) and the arguments
            after it, the environment it needs and the library it makes.
            iOS is REFUSED off macOS (Assert-XmipMacOS).

        .PARAMETER Ndk
            The NDK's toolchain bin directory (Find-XmipAndroidNdk), for
            Android.

        .PARAMETER Patch
            The landing's patch file, so the build reads the estate's working
            trees; empty outside a landing.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Desktop', 'Android', 'iOS')]
        [string] $Platform,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Ndk = '',

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Patch = ''
    )

    [string[]] $common = @('-j', '2', '--no-default-features', '--features', 'remote')

    if ($Patch) {
        $common += @('--config', $Patch)
    }

    [string[]] $library = @('build', '--lib')

    if ($Platform -eq 'Desktop') {
        [string] $into = Join-Path -Path $Root -ChildPath '.ai-interaction/target-remote'
        [string] $file = if ($IsWindows) { 'xmip_core_runtime.dll' }
        elseif ($IsMacOS) { 'libxmip_core_runtime.dylib' }
        else { 'libxmip_core_runtime.so' }

        return [pscustomobject] @{
            Platform        = $Platform
            Triple          = ''
            TargetDirectory = $into
            Subcommand      = $library
            CargoArgument   = $common
            Environment     = @{}
            Library         = Join-Path -Path $into -ChildPath "debug/$file"
        }
    }

    if ($Platform -eq 'iOS') {
        Assert-XmipMacOS
        [string] $ios = Join-Path -Path $Root -ChildPath '.ai-interaction/target-ios'

        foreach ($triple in @('aarch64-apple-ios', 'aarch64-apple-ios-sim')) {
            [pscustomobject] @{
                Platform        = $Platform
                Triple          = $triple
                TargetDirectory = $ios
                Subcommand      = @('rustc', '--lib', '--crate-type', 'staticlib')
                CargoArgument   = @('--release', '--target', $triple) + $common
                # The oldest iOS Xmip.Operations runs on (its csproj).
                Environment     = @{ IPHONEOS_DEPLOYMENT_TARGET = '15.0' }
                Library         = Join-Path -Path $ios -ChildPath (
                    "$triple/release/libxmip_core_runtime.a")
            }
        }

        return
    }

    [string] $android = Join-Path -Path $Root -ChildPath '.ai-interaction/target-android'
    [string] $script = if ($IsWindows) { '.cmd' } else { '' }
    [string] $archiver = if ($IsWindows) { 'llvm-ar.exe' } else { 'llvm-ar' }

    foreach ($triple in @('aarch64-linux-android', 'x86_64-linux-android')) {
        [string] $clang = Join-Path -Path $Ndk -ChildPath "${triple}26-clang$script"
        [string] $under = $triple -replace '-', '_'
        [string] $ar = Join-Path -Path $Ndk -ChildPath $archiver

        [pscustomobject] @{
            Platform        = $Platform
            Triple          = $triple
            TargetDirectory = $android
            Subcommand      = $library
            CargoArgument   = @('--release', '--target', $triple) + $common
            Environment     = @{
                "CARGO_TARGET_$($under.ToUpperInvariant())_LINKER" = $clang
                "CC_$under"                                        = $clang
                "AR_$under"                                        = $ar
            }
            Library         = Join-Path -Path $android -ChildPath (
                "$triple/release/libxmip_core_runtime.so")
        }
    }
}


function Assert-XmipMacOS {
    <#
        .SYNOPSIS
            REFUSED in words on any machine but macOS: the iOS build needs
            Apple's tools, the iOS SDK and xcodebuild, run nowhere else.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param()

    if (-not $IsMacOS) {
        throw ('REFUSED: the runtime builds for iOS only on macOS, where Apple''s ' +
            'tools (the iOS SDK, xcodebuild) run. The estate''s CI builds it there: ' +
            '.github/workflows/rust.yml, job phone-ios.')
    }
}


function Get-XmipRemoteRuntimeBundle {
    <#
        .SYNOPSIS
            What joins a Platform's libraries into the one its host links:
            for iOS, xcodebuild -create-xcframework over the device's and the
            simulator's static library into target-ios; for others nothing.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Build
    )

    [object[]] $static = @($Build | Where-Object -Property Platform -EQ -Value 'iOS')

    if ($static.Count -eq 0) {
        return
    }

    [string] $output = Join-Path -Path $Root -ChildPath (
        '.ai-interaction/target-ios/xmip_core_runtime.xcframework')
    [string[]] $library = @($static | ForEach-Object { '-library', $_.Library })

    [pscustomobject] @{
        Command  = 'xcodebuild'
        Argument = @('-create-xcframework') + $library + @('-output', $output)
        Output   = $output
    }
}


function Get-XmipRemoteRuntimeCommand {
    <#
        .SYNOPSIS
            The command lines a Platform's remote build runs, in order, as
            -WhatIf says them: one cargo line per Rust target, then iOS's
            xcodebuild line.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Desktop', 'Android', 'iOS')]
        [string] $Platform,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Ndk = ''
    )

    [object[]] $build = @(Get-XmipRemoteRuntimeBuild -Root $Root -Platform $Platform -Ndk $Ndk)

    foreach ($one in $build) {
        "cargo $(($one.Subcommand + $one.CargoArgument) -join ' ')"
    }

    foreach ($bundle in @(Get-XmipRemoteRuntimeBundle -Root $Root -Build $build)) {
        "$($bundle.Command) $($bundle.Argument -join ' ')"
    }
}


function Build-XmipRemoteRuntime {
    <#
        .SYNOPSIS
            Builds the runtime's remote build for a Platform, every Rust
            target of it, one at a time, then for iOS the xcframework of
            them. Returns Platform, Triple, Path and Length per library and
            per xcframework (the bytes of its files, its Triple empty);
            throws FAILED when cargo or xcodebuild does, and when Android is
            asked of a machine without the Android NDK; REFUSED when iOS is
            asked of any machine but macOS.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Desktop', 'Android', 'iOS')]
        [string] $Platform,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Patch = ''
    )

    [string] $ndk = ''

    if ($Platform -eq 'Android') {
        $ndk = Find-XmipAndroidNdk

        if ([string]::IsNullOrEmpty($ndk)) {
            throw ('FAILED: the Android NDK is absent, so the runtime cannot be built for ' +
                'Android. Install-XmipPrerequisite -Role developer says where it goes.')
        }
    }

    [hashtable] $asked = @{ Root = $Root; Platform = $Platform; Ndk = $ndk; Patch = $Patch }

    [object[]] $builds = @(Get-XmipRemoteRuntimeBuild @asked)

    foreach ($build in $builds) {
        [string] $named = if ($build.Triple) { $build.Triple } else { $Platform }
        Write-Host "== the runtime's remote build, $named" -ForegroundColor Cyan
        Invoke-XmipRemoteRuntimeBuild -Root $Root -Build $build

        [pscustomobject] @{
            Platform = $Platform
            Triple   = $build.Triple
            Path     = $build.Library
            Length   = (Get-Item -LiteralPath $build.Library).Length
        }
    }

    foreach ($bundle in @(Get-XmipRemoteRuntimeBundle -Root $Root -Build $builds)) {
        Write-Host "== the runtime's remote build, $Platform, joined" -ForegroundColor Cyan
        Remove-Item -LiteralPath $bundle.Output -Recurse -Force -ErrorAction SilentlyContinue
        [string] $tool = $bundle.Command
        [string[]] $argument = $bundle.Argument
        & $tool @argument 2>&1 | ForEach-Object { Write-Host "     $tool| $_" }

        if ($LASTEXITCODE -ne 0) {
            throw "FAILED: $tool $($argument -join ' ') exited $LASTEXITCODE."
        }

        [pscustomobject] @{
            Platform = $Platform
            Triple   = ''
            Path     = $bundle.Output
            Length   = (Get-ChildItem -LiteralPath $bundle.Output -File -Recurse |
                    Measure-Object -Property Length -Sum).Sum
        }
    }
}


function Invoke-XmipRemoteRuntimeBuild {
    <#
        .SYNOPSIS
            Runs one remote build through Build-XmipRuntimeLibrary with its
            environment set, and gives the session's environment back after.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        [pscustomobject] $Build
    )

    [hashtable] $was = @{}

    foreach ($name in $Build.Environment.Keys) {
        $was[$name] = [Environment]::GetEnvironmentVariable($name)
        [Environment]::SetEnvironmentVariable($name, $Build.Environment[$name])
    }

    try {
        [hashtable] $library = @{
            Root            = $Root
            TargetDirectory = $Build.TargetDirectory
            Subcommand      = $Build.Subcommand
            CargoArgument   = $Build.CargoArgument
        }
        Build-XmipRuntimeLibrary @library
    }
    finally {
        foreach ($name in $was.Keys) {
            [Environment]::SetEnvironmentVariable($name, $was[$name])
        }
    }
}
