#requires -PSEdition Core
#requires -Version 7.7.0

<#
    ADR-0021 for .NET: every project the estate ships targets the framework
    architecture.toml declares, the PowerShell module and the binding pwsh
    loads included, and every repository builds with one SDK on the channel
    it declares.
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

        # A .NET repository is a folder holding a global.json.
        [System.IO.FileInfo[]] $script:Sdks = @(
            InModuleScope Xmip -Parameters @{ Root = $script:Root } {
                param($Root)
                Find-XmipFile -Path $Root -Filter 'global.json'
            }
        )

        <#
            .SYNOPSIS
            The target frameworks in force for a project file.

            .DESCRIPTION
            A project may set it or inherit it from a Directory.Build.props
            beside or above it — the template does the second, deliberately,
            because two manifests that must agree eventually stop agreeing.
            A project built for several platforms names each in
            TargetFrameworks, under whatever condition, and every one is
            returned. Returns '' when none is stated.
        #>
        function Get-TargetFramework {
            [CmdletBinding()]
            [OutputType([string[]])]
            param(
                [Parameter(Mandatory = $true)]
                [System.IO.FileInfo] $File
            )

            [string] $text = Get-Content -LiteralPath $File.FullName -Raw

            [string[]] $several = @(
                [regex]::Matches($text, '<TargetFrameworks[^>]*>([^<]+)</TargetFrameworks>') |
                    ForEach-Object { $_.Groups[1].Value -split ';' } |
                    Where-Object { $_ -ne '' -and $_ -ne '$(TargetFrameworks)' }
            )

            if ($several.Count -gt 0) {
                return $several
            }

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
        # No exception: the PowerShell module and the binding it loads were
        # net10.0 while pwsh hosted .NET 10, and pwsh 7.7, the floor, hosts
        # .NET 11 (ADR-0014, amendment 2026-11-02).
        [string[]] $wrong = @()
        [string] $expected = $script:Policy.targetFramework

        foreach ($file in $script:Csproj) {
            [string] $where = $file.FullName.Replace($script:Root, '').TrimStart('\', '/')

            # A platform suffix is the version, not a different version. A MAUI
            # Windows app must target net11.0-windows10.0.19041.0 — the suffix
            # is required by the framework, not drift from it — so the declared
            # target is a prefix the actual one must start with. net11.0 still
            # refuses net10.0. Added when the desktop host landed, 2026-09-05.
            [string] $suffix = "$expected-"

            foreach ($actual in @(Get-TargetFramework -File $file)) {
                [bool] $ok =
                    $actual -eq $expected -or
                    $actual.StartsWith($suffix, [System.StringComparison]::Ordinal)

                if (-not $ok) {
                    $wrong += "$where is '$actual', expected '$expected'"
                }
            }
        }

        $wrong.Count | Should -Be 0 -Because ($wrong -join "`n")
    }

    It 'names one SDK in every .NET repository, on the channel the manifest declares' {
        # Each repository keeps its own global.json, since a submodule reads
        # no other's. On the stable channel none takes a prerelease, so a
        # release candidate still installed never builds (ADR-0014,
        # amendment 2026-11-12).
        [bool] $preview = $script:Policy.sdk -eq 'preview'
        [string[]] $versions = @()
        [string[]] $named = @()
        [string[]] $wrong = @()

        $script:Sdks.Count | Should -BeGreaterThan 0

        foreach ($sdk in $script:Sdks) {
            [string] $where = $sdk.FullName.Replace($script:Root, '').TrimStart('\', '/')
            $said = (Get-Content -LiteralPath $sdk.FullName -Raw | ConvertFrom-Json).sdk

            $versions += [string] $said.version
            $named += "$where names $($said.version)"

            if ([bool] $said.allowPrerelease -ne $preview) {
                [string] $channel = $script:Policy.sdk
                $wrong += "$where allowPrerelease $($said.allowPrerelease), channel $channel"
            }
        }

        @($versions | Sort-Object -Unique).Count | Should -Be 1 -Because ($named -join "`n")
        $wrong.Count | Should -Be 0 -Because ($wrong -join "`n")
    }

    It 'gives every .NET repository nuget.org alone, at the age the manifest declares' {
        # Its nuget.config clears the inherited sources, so a machine's own
        # feed is never asked, and names each source it keeps with the
        # manifest's nugetMinimumAgeHours (ADR-0021, amendment 2026-11-07).
        [string] $age = [string] $script:Policy.nugetMinimumAgeHours
        [string[]] $wrong = @()

        $script:Sdks.Count | Should -BeGreaterThan 0

        foreach ($sdk in $script:Sdks) {
            [string] $where = $sdk.Directory.FullName.Replace($script:Root, '').TrimStart('\', '/')
            [string] $config = Join-Path $sdk.Directory.FullName 'nuget.config'

            if (-not (Test-Path -LiteralPath $config)) {
                $wrong += "$where has no nuget.config"
                continue
            }

            [xml] $read = Get-Content -LiteralPath $config -Raw
            $sources = $read.configuration.packageSources

            if ($null -eq $sources.clear) {
                $wrong += "$where does not clear the inherited sources"
            }

            foreach ($source in @($sources.add)) {
                if ($source.minPublishAgeHours -ne $age) {
                    [string] $set = $source.minPublishAgeHours
                    $wrong += "$where names $($source.key) at '$set', expected '$age'"
                }
            }
        }

        $wrong.Count | Should -Be 0 -Because ($wrong -join "`n")
    }
}
