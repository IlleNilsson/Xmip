#requires -PSEdition Core
#requires -Version 7.6.5

<#
    ADR-0021 for .NET: every project the estate ships targets the framework
    architecture.toml declares, and a project a host loads targets the one
    that host runs.
#>

Describe 'ADR-0021: the .NET surfaces are on the latest target' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

        $manifest = Get-XmipManifest -Path (Join-Path $script:Root 'architecture.toml')

        $script:Policy = $manifest.project

        # Every .NET project the estate ships, plus the template every new
        # repository is generated from. Build output is never walked.
        [System.IO.FileInfo[]] $script:Csproj = @(
            InModuleScope Xmip -Parameters @{ Root = $script:Root } {
                param($Root)
                Find-XmipFile -Path $Root -Filter '*.csproj'
            }
        )

        <#
            .SYNOPSIS
            The target framework in force for a project file.

            .DESCRIPTION
            A project may set it or inherit it from a Directory.Build.props
            beside or above it — the template does the second, deliberately,
            because two manifests that must agree eventually stop agreeing.
            Returns '' when neither states one.
        #>
        function Get-TargetFramework {
            [CmdletBinding()]
            [OutputType([string])]
            param(
                [Parameter(Mandatory = $true)]
                [System.IO.FileInfo] $File
            )

            [string] $text = Get-Content -LiteralPath $File.FullName -Raw

            if ($text -match '<TargetFramework>([^<]+)</TargetFramework>') {
                return $Matches[1]
            }

            [System.IO.DirectoryInfo] $folder = $File.Directory

            while ($null -ne $folder) {
                [string] $props = Join-Path $folder.FullName 'Directory.Build.props'

                if (Test-Path -LiteralPath $props) {
                    [string] $shared = Get-Content -LiteralPath $props -Raw

                    if ($shared -match '<TargetFramework>([^<]+)</TargetFramework>') {
                        return $Matches[1]
                    }
                }

                $folder = $folder.Parent
            }

            return ''
        }
    }

    It 'declares a target framework in the manifest' {
        [string]::IsNullOrWhiteSpace($script:Policy.targetFramework) | Should -BeFalse
    }

    It 'gives every project the target the manifest declares' {
        # The exception is declared, not assumed. A project under a module
        # named by hostedBy is loaded by a host that owns the runtime — pwsh
        # runs .NET 10 and refuses a net11.0 assembly at Import-Module — so it
        # targets hostedTargetFramework, and so does the one .NET binding it
        # loads (abi, ADR-0014 amendment 2026-09-09). Everything else takes
        # the latest.
        [string[]] $wrong = @()
        [string] $hosts = @($script:Policy.hostedBy) -join '|'

        foreach ($file in $script:Csproj) {
            [string] $where = $file.FullName.Replace($script:Root, '').TrimStart('\', '/')
            [bool] $hosted = $where -match "[\\/]($hosts)[\\/]"

            [string] $expected = if ($hosted) {
                $script:Policy.hostedTargetFramework
            }
            else {
                $script:Policy.targetFramework
            }

            [string] $actual = Get-TargetFramework -File $file

            # A platform suffix is the version, not a different version. A MAUI
            # Windows app must target net11.0-windows10.0.19041.0 — the suffix
            # is required by the framework, not drift from it — so the declared
            # target is a prefix the actual one must start with. net11.0 still
            # refuses net10.0. Added when the desktop host landed, 2026-09-05.
            [string] $suffix = "$expected-"
            [bool] $ok =
                $actual -eq $expected -or
                $actual.StartsWith($suffix, [System.StringComparison]::Ordinal)

            if (-not $ok) {
                $wrong += "$where is '$actual', expected '$expected' (hosted: $hosted)"
            }
        }

        $wrong.Count | Should -Be 0 -Because ($wrong -join "`n")
    }
}
