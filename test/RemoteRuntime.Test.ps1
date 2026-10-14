#requires -PSEdition Core
#requires -Version 7.6.5

<#
    The runtime's remote build (ADR-0014, amendment 2026-10-14), built once in
    Build-XmipRemoteRuntime.ps1: the Desktop one Xmip.Abi's tests load and the
    Android ones Xmip.Operations packages through Xmip.Abi.Native.props.
    Before 2026-10-14 a hand-run script built the ARM64 one and nothing built
    the x86_64 one, so the phone build failed on a missing file with a raw zip
    exception. What can be checked without building is checked here: where
    the NDK is found, the cargo command each build is, that the props file
    reads where the build writes and names the command that builds it, and
    that a landing skips the phone host where the NDK is absent.
#>

BeforeAll {
    $script:AuditBefore = $env:XMIP_AUDIT_DIRECTORY
    $env:XMIP_AUDIT_DIRECTORY = Join-Path -Path $TestDrive -ChildPath 'audit'

    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    [string[]] $script:Variable = @('ANDROID_NDK_HOME', 'ANDROID_HOME')
    [hashtable] $script:Before = @{}

    foreach ($name in $script:Variable) {
        $script:Before[$name] = [Environment]::GetEnvironmentVariable($name)
    }

    [string] $script:HostFolder = if ($IsWindows) { 'windows-x86_64' }
    elseif ($IsMacOS) { 'darwin-x86_64' }
    else { 'linux-x86_64' }

    function New-XmipTestNdk {
        param([string] $Path)

        [string] $bin = Join-Path -Path $Path -ChildPath (
            "toolchains/llvm/prebuilt/$script:HostFolder/bin")
        $null = New-Item -ItemType Directory -Path $bin -Force

        return $bin
    }

    function Get-XmipTestBuild {
        param([string] $Platform, [string] $Ndk = '', [string] $Patch = '')

        InModuleScope Xmip -Parameters @{
            Root = $script:Root; Platform = $Platform; Ndk = $Ndk; Patch = $Patch
        } {
            param($Root, $Platform, $Ndk, $Patch)
            @(Get-XmipRemoteRuntimeBuild -Root $Root -Platform $Platform -Ndk $Ndk -Patch $Patch)
        }
    }
}

AfterAll {
    foreach ($name in $script:Variable) {
        [Environment]::SetEnvironmentVariable($name, $script:Before[$name])
    }

    $env:XMIP_AUDIT_DIRECTORY = $script:AuditBefore
}

Describe 'The Android NDK is found where the prerequisite puts it' {
    BeforeEach {
        foreach ($name in $script:Variable) {
            [Environment]::SetEnvironmentVariable($name, $null)
        }
    }

    It 'takes ANDROID_NDK_HOME first' {
        [string] $bin = New-XmipTestNdk -Path (Join-Path $TestDrive 'home-ndk')
        $env:ANDROID_NDK_HOME = Join-Path $TestDrive 'home-ndk'
        $env:ANDROID_HOME = Join-Path $TestDrive 'empty-sdk'

        InModuleScope Xmip { Find-XmipAndroidNdk } | Should -Be $bin
    }

    It 'takes the newest version under the SDK, by version and not by text' {
        [string] $sdk = Join-Path $TestDrive 'sdk'
        $null = New-XmipTestNdk -Path (Join-Path $sdk 'ndk/9.1.0')
        [string] $newest = New-XmipTestNdk -Path (Join-Path $sdk 'ndk/30.0.16248370')
        $null = New-Item -ItemType Directory -Path (Join-Path $sdk 'ndk/not-a-version') -Force
        $env:ANDROID_HOME = $sdk

        InModuleScope Xmip { Find-XmipAndroidNdk } | Should -Be $newest
    }

    It 'says nothing where there is no NDK' {
        $env:ANDROID_HOME = Join-Path $TestDrive 'no-sdk'

        InModuleScope Xmip { Find-XmipAndroidNdk } | Should -BeNullOrEmpty
    }

    It 'refuses an Android build in words where there is no NDK' {
        $env:ANDROID_HOME = Join-Path $TestDrive 'no-sdk'

        {
            InModuleScope Xmip -Parameters @{ Root = $script:Root } {
                param($Root)
                Build-XmipRemoteRuntime -Root $Root -Platform Android
            }
        } | Should -Throw -ExpectedMessage 'FAILED: the Android NDK is absent*'
    }
}

Describe 'Each remote build is one cargo command' {
    It 'builds Android for a device and the emulator, release, API level 26, -j 2' {
        [string] $ndk = Join-Path $TestDrive 'ndk-bin'
        [object[]] $build = Get-XmipTestBuild -Platform Android -Ndk $ndk
        [string] $script = if ($IsWindows) { '.cmd' } else { '' }

        $build.Triple | Should -Be @('aarch64-linux-android', 'x86_64-linux-android')

        foreach ($one in $build) {
            [string] $triple = $one.Triple
            [string] $under = $triple -replace '-', '_'
            [string] $clang = Join-Path $ndk "${triple}26-clang$script"

            ($one.CargoArgument -join ' ') | Should -Be (
                "--release --target $triple -j 2 --no-default-features --features remote")
            $one.Environment["CARGO_TARGET_$($under.ToUpperInvariant())_LINKER"] |
                Should -Be $clang
            $one.Environment["CC_$under"] | Should -Be $clang
            $one.Environment["AR_$under"] | Should -BeLike (Join-Path $ndk 'llvm-ar*')
            $one.Library | Should -Be (Join-Path $script:Root (
                    ".ai-interaction/target-android/$triple/release/libxmip_core_runtime.so"))
        }
    }

    It 'builds Desktop where Xmip.Abi''s tests load it, debug, -j 2' {
        [object[]] $build = Get-XmipTestBuild -Platform Desktop
        [string] $into = Join-Path $script:Root '.ai-interaction/target-remote'

        $build.Count | Should -Be 1
        [string] $command = $build[0].CargoArgument -join ' '
        $command | Should -Be '-j 2 --no-default-features --features remote'
        $build[0].TargetDirectory | Should -Be $into
        $build[0].Library | Should -BeLike (Join-Path $into 'debug/*xmip_core_runtime.*')
    }

    It 'reads the working trees in a landing, through its patch' {
        [object[]] $build = Get-XmipTestBuild -Platform Desktop -Patch 'patch.toml'

        ($build[0].CargoArgument -join ' ') | Should -BeLike '* --config patch.toml'
    }
}

Describe 'The phone host reads what the build writes' {
    BeforeAll {
        [string] $props = Join-Path $script:Root (
            'module/foundation/abi/dotnet/build/Xmip.Abi.Native.props')
        $script:Props = Get-Content -Raw -LiteralPath $props
    }

    It 'names the build''s own path for each library' {
        $script:Props | Should -BeLike '*.ai-interaction/target-android</XmipRuntimeAndroid>*'

        foreach ($triple in 'aarch64-linux-android', 'x86_64-linux-android') {
            [string] $library = "$triple/release/libxmip_core_runtime.so"
            $script:Props | Should -BeLike "*`$(XmipRuntimeAndroid)/$library*"
        }
    }

    It 'stops a build that lacks one with the command that builds it, and the command is there' {
        $script:Props | Should -BeLike '*<Error *Build-XmipService -Remote Android*'

        $remote = (Get-Command -Name Build-XmipService).Parameters['Remote']
        $remote.Attributes.ValidValues | Should -Contain 'Android'
    }
}

Describe 'A landing builds the remote build before the module that needs it' {
    BeforeEach {
        InModuleScope Xmip {
            Mock New-XmipLocalPatch { 'patch.toml' }
            Mock Get-XmipEstateCrate { }
            Mock Get-XmipVerifyTime { @{} }
            Mock Set-XmipVerifyTime { }
            Mock Clear-XmipUnhashedLibrary { }
            Mock Build-XmipTestLibrary { $true }
            Mock Test-XmipModule { }
            Mock Build-XmipRemoteRuntime { }
            Mock Write-Host { }
        }
    }

    It 'skips the phone host, with the reason, where the NDK is absent' {
        InModuleScope Xmip -Parameters @{ Root = $script:Root } {
            param($Root)
            Mock Find-XmipAndroidNdk { '' }

            $tree = Test-XmipChangeTree -RepositoryRoot $Root -Ordered @(
                'module/core/operation/gui')

            $tree.Skipped | Should -Be @('module/core/operation/gui')
            $tree.Failed | Should -BeNullOrEmpty
            Should -Invoke Build-XmipRemoteRuntime -Times 0
            Should -Invoke Write-Host -ParameterFilter {
                "$Object" -like 'SKIPPED.*the Android NDK is absent here.'
            }
        }
    }

    It 'builds Android before the phone host and Desktop before Xmip.Abi, once each' {
        InModuleScope Xmip -Parameters @{ Root = $script:Root } {
            param($Root)
            Mock Find-XmipAndroidNdk { 'ndk-bin' }

            $tree = Test-XmipChangeTree -RepositoryRoot $Root -Ordered @(
                'module/foundation/abi', 'module/core/operation/gui')

            $tree.Verified.Count | Should -Be 2
            Should -Invoke Build-XmipRemoteRuntime -Times 1 -Exactly -ParameterFilter {
                $Platform -eq 'Desktop' -and $Patch -eq 'patch.toml'
            }
            Should -Invoke Build-XmipRemoteRuntime -Times 1 -Exactly -ParameterFilter {
                $Platform -eq 'Android'
            }
        }
    }

    It 'fails the module whose remote build failed, and verifies nothing after' {
        InModuleScope Xmip -Parameters @{ Root = $script:Root } {
            param($Root)
            Mock Build-XmipRemoteRuntime { throw 'FAILED: cargo' }
            Mock Write-XmipAudit { }

            $tree = Test-XmipChangeTree -RepositoryRoot $Root -Ordered @(
                'module/foundation/abi') 2>$null

            $tree.Failed | Should -Be 'module/foundation/abi'
            Should -Invoke Test-XmipModule -Times 0
        }
    }
}
