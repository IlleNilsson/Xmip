#requires -PSEdition Core
#requires -Version 7.7.0

<#
    The estate page is what the owner reads the estate on, and it was a hand-
    written copy that went eleven days stale (2026-09-21). It is generated now,
    and its edges come from what each repository's build uses rather than from
    what the manifest declares. These assert the reading of the build, which is
    the part that decides whether an edge on the page is true.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')


    <#
        .SYNOPSIS
        What a mount uses, asked inside the module, where the reader and the
        TOML helpers it calls are private.
    #>
    function Get-FixtureUse {
        param([string] $Mount)

        [hashtable] $asked = @{ Root = $script:Fixture; Mount = $Mount; Owner = $script:Owner }

        InModuleScope Xmip -Parameters @{ Asked = $asked } {
            param($Asked)

            Get-XmipRepositoryUse @Asked
        }
    }

    <#
        .SYNOPSIS
        Writes one file under the fixture, making its directory.
    #>
    function New-FixtureFile {
        param([string] $Path, [string] $Text)

        [string] $full = Join-Path $script:Fixture $Path
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $full) | Out-Null
        Set-Content -LiteralPath $full -Value $Text -Encoding utf8
    }
}

Describe 'What a repository uses is read from its build' {
    BeforeAll {
        $script:Fixture = [string] $TestDrive

        # Each estate crate taken from the root's [workspace.dependencies],
        # which names its package (ADR-0005, amendment 2026-11-28).
        New-FixtureFile -Path 'Cargo.toml' -Text @'
[workspace.dependencies]
two = { package = "xmip-core-two", path = "module/two" }
xmip-core-three = { path = "module/three" }
four = { package = "xmip-core-four", path = "module/four" }
five = { package = "xmip-core-five", path = "module/five" }
six = { package = "xmip-core-six", path = "module/six" }
'@

        New-FixtureFile -Path 'module/one/Cargo.toml' -Text @'
[package]
name = "xmip-core-one"

[dependencies]
two = { workspace = true }
xmip-core-three = { workspace = true }
serde = "1"

[dev-dependencies]
four = { workspace = true }

[target.'cfg(windows)'.dependencies]
five = { workspace = true, optional = true }
two = { workspace = true }

[target.'cfg(unix)'.dev-dependencies]
six = { workspace = true }
'@

        New-FixtureFile -Path 'module/surface/src/Surface/Surface.csproj' -Text @'
<Project Sdk="Microsoft.NET.Sdk">
  <ItemGroup>
    <ProjectReference Include="..\..\..\abi\dotnet\Binding\Binding.csproj" />
  </ItemGroup>
</Project>
'@

        New-FixtureFile -Path 'module/surface/src/Surface.Test/Surface.Test.csproj' -Text @'
<Project Sdk="Microsoft.NET.Sdk">
  <ItemGroup>
    <ProjectReference Include="..\..\..\one\Nothing.csproj" />
  </ItemGroup>
</Project>
'@

        New-FixtureFile -Path 'module/abi/dotnet/Binding/Binding.csproj' -Text '<Project />'

        # A table, not an array of pairs: @( @('a', 'b') @('c', 'd') ) flattens
        # to four strings, and the first version of this read the letter m as a
        # mount (2026-09-21).
        [hashtable] $mounts = @{
            'module/one'     = 'xmip-core-one'
            'module/surface' = 'xmip-core-surface'
            'module/abi'     = 'xmip-core-abi'
        }

        [hashtable] $script:Owner = @{}

        foreach ($mount in $mounts.Keys) {
            [string] $full = [IO.Path]::GetFullPath((Join-Path $script:Fixture $mount))
            $script:Owner[$full.TrimEnd([char] 92, [char] 47)] = $mounts[$mount]
        }
    }

    It 'names the estate crates under [dependencies], by the package the root names' {
        [string[]] $uses = @(Get-FixtureUse -Mount 'module/one')

        $uses | Should -Contain 'xmip-core-two' -Because 'renamed, it is the root entry''s package'
        $uses | Should -Contain 'xmip-core-three' -Because 'unrenamed, it is its key'
        $uses | Should -Not -Contain 'xmip-core-four' -Because 'a dev-dependency tests it'
        $uses | Should -Not -Contain 'serde' -Because 'only the estate is drawn'
    }

    It "names the estate crates a platform's own [dependencies] name, once each" {
        [string[]] $uses = @(Get-FixtureUse -Mount 'module/one')

        $uses | Should -Contain 'xmip-core-five' -Because 'a build on Windows is made of it'
        @($uses | Where-Object { $_ -eq 'xmip-core-two' }).Count | Should -Be 1
        $uses | Should -Not -Contain 'xmip-core-six' -Because "a platform's dev-dependency tests it"
    }

    It 'resolves a .NET project reference to the repository holding the project' {
        [string[]] $uses = @(Get-FixtureUse -Mount 'module/surface')

        $uses | Should -Be @('xmip-core-abi')
        $uses | Should -Not -Contain 'xmip-core-one' -Because 'a test project is not the build'
    }
}

Describe 'The page is generated, and the template can receive it' {
    It 'has exactly one place for the data, so a page cannot be published empty' {
        [string] $page = Join-Path $script:Root 'Xmip/estate-page.html'
        [string] $template = Get-Content -Raw -LiteralPath $page

        ([regex]::Matches($template, [regex]::Escape('/*ESTATE*/null'))).Count | Should -Be 1
    }

    It 'says it is generated and names the command that generates it' {
        [string] $page = Join-Path $script:Root 'Xmip/estate-page.html'
        [string] $template = Get-Content -Raw -LiteralPath $page

        $template | Should -Match 'New-XmipEstateMap -Format Html'
        $template | Should -Match 'never edited'
    }
}
