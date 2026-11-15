#requires -PSEdition Core
#requires -Version 7.7.0

<#
    Where the nodes and surfaces the tooling starts keep their local
    endpoints. Decided by the owner, 2026-11-15 (ADR-0014):
    XMIP_RUNTIME_DIRECTORY names another folder than /run/xmip or
    /var/run/xmip for a run no service manager started, and nothing falls
    back on its own, so whatever starts one sets it. The tooling sets xmip
    under the user's runtime directory on Linux and macOS for every process
    it starts, as it sets XMIP_AUDIT_DIRECTORY; Windows has no folder to
    name. The suite starts nothing.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    $script:Before = @{
        XMIP_RUNTIME_DIRECTORY = $env:XMIP_RUNTIME_DIRECTORY
        XDG_RUNTIME_DIR        = $env:XDG_RUNTIME_DIR
        TMPDIR                 = $env:TMPDIR
    }
}

Describe 'The folder of local endpoints for a run the tooling starts' {
    BeforeEach {
        $env:XMIP_RUNTIME_DIRECTORY = $null
        $env:XDG_RUNTIME_DIR = '/run/user/1000'
        $env:TMPDIR = '/var/folders/x/T/'
    }

    AfterEach {
        foreach ($name in $script:Before.Keys) {
            [Environment]::SetEnvironmentVariable($name, $script:Before[$name])
        }
    }

    It 'is xmip under the user''s runtime directory on Linux' {
        InModuleScope Xmip {
            Mock Get-XmipOperatingSystem { 'linux' }

            Initialize-XmipRuntimeDirectory

            $env:XMIP_RUNTIME_DIRECTORY | Should -Be '/run/user/1000/xmip'
        }
    }

    It 'is xmip under the temporary directory on macOS' {
        InModuleScope Xmip {
            Mock Get-XmipOperatingSystem { 'macos' }

            Initialize-XmipRuntimeDirectory

            $env:XMIP_RUNTIME_DIRECTORY | Should -Be '/var/folders/x/T/xmip'
        }
    }

    It 'keeps a folder the session already names' {
        InModuleScope Xmip {
            Mock Get-XmipOperatingSystem { 'linux' }
            $env:XMIP_RUNTIME_DIRECTORY = '/srv/xmip-run'

            Initialize-XmipRuntimeDirectory

            $env:XMIP_RUNTIME_DIRECTORY | Should -Be '/srv/xmip-run'
        }
    }

    It 'names nothing on Windows, nor where the user''s runtime directory is not said' {
        InModuleScope Xmip {
            Mock Get-XmipOperatingSystem { 'windows' }
            Initialize-XmipRuntimeDirectory
            $env:XMIP_RUNTIME_DIRECTORY | Should -BeNullOrEmpty

            Mock Get-XmipOperatingSystem { 'linux' }
            $env:XDG_RUNTIME_DIR = $null
            Initialize-XmipRuntimeDirectory
            $env:XMIP_RUNTIME_DIRECTORY | Should -BeNullOrEmpty
        }
    }

    It 'is set wherever the audit''s directory is, before a process is started' {
        # Every starter hands its processes the audit's directory
        # (Initialize-XmipAudit); the folder of local endpoints goes with it,
        # and with every cargo and dotnet the module runs.
        [string] $module = Join-Path -Path $script:Root -ChildPath 'Xmip'
        [string] $audited = '(?m)^\s*Initialize-XmipAudit\s*$'
        [string] $placed = '(?m)^\s*Initialize-XmipRuntimeDirectory\s*$'
        [object[]] $starters = @(
            Get-ChildItem -Path $module -Filter 'Start-Xmip*.ps1' |
                Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match $audited }
        )

        $starters.Count | Should -BeGreaterThan 0

        foreach ($file in $starters) {
            [string] $text = Get-Content -LiteralPath $file.FullName -Raw
            [int] $audit = [regex]::Matches($text, $audited).Count

            [regex]::Matches($text, $placed).Count |
                Should -Be $audit -Because "$($file.Name) starts what may reach a node"
        }

        Get-Content -LiteralPath (Join-Path $module 'Invoke-XmipTool.ps1') -Raw |
            Should -Match $placed
    }
}
