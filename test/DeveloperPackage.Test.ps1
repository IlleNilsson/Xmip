#requires -PSEdition Core
#requires -Version 7.7.0

<#
    ADR-0075: the packages a developer installs, Xmip.Module and
    Xmip.Templates, live in one repository and take one version, and the
    module `dotnet new xmip-module` gives names Xmip.Module at that version,
    written in as the template is packed — never a copy kept by hand.
#>

Describe 'ADR-0075: the developer packages share one version' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

        $script:Dotnet = Join-Path -Path $script:Root -ChildPath 'module/foundation/abi/dotnet'

        <#
            .SYNOPSIS
            A project file of the abi repository's .NET folder, as text.
        #>
        function Get-ProjectText {
            [CmdletBinding()]
            [OutputType([string])]
            param(
                [Parameter(Mandatory = $true)]
                [string] $Relative
            )

            Get-Content -LiteralPath (Join-Path $script:Dotnet $Relative) -Raw
        }
    }

    It 'declares the one version once, and each package takes it' {
        Get-ProjectText -Relative 'Directory.Build.props' |
            Should -Match '<XmipPackageVersion>\d+\.\d+\.\d+[^<]*</XmipPackageVersion>'

        [string[]] $packages = @(
            'Xmip.Module/Xmip.Module.csproj', 'Xmip.Templates/Xmip.Templates.csproj'
        )
        foreach ($package in $packages) {
            Get-ProjectText -Relative $package |
                Should -Match '<Version>\$\(XmipPackageVersion\)</Version>' -Because $package
        }
    }

    It 'names Xmip.Module in the template at the version the template is packed with' {
        [string] $module = 'Xmip.Templates/content/xmip-module/XmipModule1/XmipModule1.csproj'

        [string] $reference =
            '<PackageReference Include="Xmip\.Module" Version="XMIP_MODULE_VERSION" />'
        Get-ProjectText -Relative $module | Should -Match $reference
        Get-ProjectText -Relative 'Xmip.Templates/Xmip.Templates.csproj' |
            Should -Match "Replace\('XMIP_MODULE_VERSION', '\`$\(Version\)'\)"
    }
}
