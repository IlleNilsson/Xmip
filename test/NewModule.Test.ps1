#requires -PSEdition Core
#requires -Version 7.6.7

<#
    A crate written where architecture.toml mounts a repository that is not a
    submodule yet is a module of the estate, listed by its own name. Until
    2026-10-27 it was untracked files of the module around it: Get-XmipStatus
    and the landing's verification named it nowhere, and it was verified only
    when named with -Module.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    <#
        .SYNOPSIS
        Writes a Cargo.toml naming one package.
    #>
    function New-XmipTestCrate {
        param(
            [string] $At,

            [string] $Package
        )

        $null = New-Item -ItemType Directory -Path $At -Force
        Set-Content -LiteralPath (Join-Path $At 'Cargo.toml') -Value @(
            '[package]', "name = `"$Package`"", 'version = "0.1.0"'
        )
    }

    <#
        .SYNOPSIS
        A git repository in one folder.
    #>
    function Initialize-XmipTestRepository {
        param(
            [string] $At
        )

        InModuleScope Xmip -Parameters @{ At = $At } {
            param([string] $At)

            $null = Invoke-XmipGit -At $At -Arguments @('init', '--quiet')
        }
    }

    # An estate whose root mounts the path capability. In it, edi is declared
    # and new; rust is the capability's own crate in a folder; other is
    # undeclared. The unit capability is declared and new at the root's level.
    $script:Estate = Join-Path -Path $TestDrive -ChildPath 'estate'
    $script:Path = Join-Path -Path $script:Estate -ChildPath 'module/core/capability/path'
    $null = New-Item -ItemType Directory -Path $script:Path -Force

    Set-Content -LiteralPath (Join-Path $script:Estate '.gitmodules') -Value @(
        '[submodule "module/core/capability/path"]'
        "`tpath = module/core/capability/path"
        "`turl = https://example.invalid/xmip-core-path.git"
    )
    Set-Content -LiteralPath (Join-Path $script:Estate 'architecture.toml') -Value @(
        'schemaVersion = "2.0.0"'
        '[xmip.core]'
        'description = "Core."'
        'architecturalDomain = "Foundation"'
        'repositoryRole = "common-architecture"'
        'maturity = "scaffolded"'
        '[xmip.core.path]'
        'description = "Path."'
        'architecturalDomain = "Capability"'
        'repositoryRole = "common-capability"'
        'maturity = "scaffolded"'
        '[xmip.core.path.edi]'
        'description = "EDI path."'
        'maturity = "scaffolded"'
        '[xmip.core.unit]'
        'description = "Unit."'
        'architecturalDomain = "Capability"'
        'repositoryRole = "common-capability"'
        'maturity = "scaffolded"'
    )

    New-XmipTestCrate -At $script:Path -Package 'xmip-core-path'
    New-XmipTestCrate -At (Join-Path $script:Path 'rust') -Package 'xmip-core-path'
    New-XmipTestCrate -At (Join-Path $script:Path 'other') -Package 'xmip-core-path-other'
    Initialize-XmipTestRepository -At $script:Estate
    Initialize-XmipTestRepository -At $script:Path

    $script:Edi = Join-Path -Path $script:Path -ChildPath 'edi'
    New-XmipTestCrate -At $script:Edi -Package 'xmip-core-path-edi'
    $null = New-Item -ItemType Directory -Path (Join-Path $script:Edi 'src') -Force
    Set-Content -LiteralPath (Join-Path $script:Edi 'src/lib.rs') -Value '//! EDI path.'

    [string] $unit = Join-Path -Path $script:Estate -ChildPath 'module/core/capability/unit'
    New-XmipTestCrate -At $unit -Package 'xmip-core-unit'
}

Describe 'A declared crate that is no submodule yet' {
    It 'is a module of the estate, the declared and the placed alone' {
        InModuleScope Xmip -Parameters @{ Root = $script:Estate } {
            param($Root)

            [string[]] $declared = @(Get-XmipDeclaredModule -RepositoryRoot $Root)

            $declared | Should -Be @(
                'module/core/capability/path'
                'module/core/capability/path/edi'
                'module/core/capability/unit'
            )
        }
    }

    It 'is listed by Get-XmipStatus as new, by its own path' {
        [object[]] $short = @(Get-XmipStatus -RepositoryRoot $script:Estate -Short)
        [object] $edi = $short | Where-Object Module -EQ 'module/core/capability/path/edi'

        $edi.New | Should -BeTrue
        $edi.Branch | Should -Be 'new'
        $edi.Changed | Should -Be 2
        ($short | Where-Object Module -EQ 'module/core/capability/unit').New | Should -BeTrue
    }

    It 'leaves the status of the repository around it' {
        # Its files were the capability's untracked edi/, and the landing
        # would have committed them into xmip-core-path.
        # Nothing is committed: git writes its objects read-only, and the test
        # drive could not be removed.
        [string[]] $around = @(
            Get-XmipStatus -RepositoryRoot $script:Estate |
                Where-Object Module -EQ 'module/core/capability/path' |
                ForEach-Object -MemberName Path
        )

        $around | Should -Be @('Cargo.toml', 'other/', 'rust/')
    }

    It 'is verified with the rest and refused before anything lands' {
        [string] $source = Get-Content -Raw -LiteralPath (
            Join-Path $script:Root 'Xmip/Publish-XmipChange.ps1')
        [int] $verify = $source.IndexOf('Test-XmipChangeTree @tree')
        [int] $refuse = $source.IndexOf('Where-Object -Property New')
        [int] $land = $source.LastIndexOf('Publish-XmipUnpushed -RepositoryRoot')

        $refuse | Should -BeGreaterThan $verify
        $refuse | Should -BeLessThan $land
    }
}
