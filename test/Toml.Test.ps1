#Requires -Version 7.6.5

# ConvertFrom-Toml has returned a dictionary in one version of PSToml and an
# object in the next. The module reads TOML through one pair, Get-TomlKey and
# Get-TomlValue in Xmip.psm1, and every reader of a TOML file goes through it,
# so which shape the installed PSToml returns is nobody's business. This holds
# the pair on both shapes, and the readers that once asked for one of them.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'Xmip' 'Xmip.psd1') -Force

    # The same document in both shapes PSToml has returned.
    function New-TomlShape {
        param([Parameter(Mandatory)] [string] $Shape, [Parameter(Mandatory)] [hashtable] $Value)

        $ordered = [ordered]@{}
        foreach ($key in $Value.Keys) {
            $ordered[$key] = $Value[$key]
        }

        if ($Shape -eq 'dictionary') {
            return $ordered
        }

        return [pscustomobject] $ordered
    }
}

Describe 'Reading a TOML node, whichever shape PSToml returned' -ForEach @(
    @{ Shape = 'dictionary' }
    @{ Shape = 'object' }
) {
    It 'reads a key, lists the keys and defaults an absent one (<Shape>)' {
        InModuleScope Xmip -Parameters @{ Shape = $Shape } {
            param($Shape)
            $ordered = [ordered]@{ name = 'Nightly'; count = 3; empty = $null }
            $node = if ($Shape -eq 'dictionary') { $ordered } else { [pscustomobject] $ordered }

            Set-StrictMode -Version Latest
            Get-TomlValue -Node $node -Name 'name' | Should -Be 'Nightly'
            Get-TomlValue -Node $node -Name 'count' | Should -Be 3
            Get-TomlValue -Node $node -Name 'missing' -Default 'none' | Should -Be 'none'
            Get-TomlValue -Node $node -Name 'empty' -Default 'none' | Should -Be 'none'
            Get-TomlKey -Node $node | Should -Be @('name', 'count', 'empty')
        }
    }

    It 'reads a suite declaration (<Shape>)' {
        $declared = New-TomlShape -Shape $Shape -Value @{
            provider = 'example'; name = 'Nightly'; command = 'run.ps1'
        }
        Mock ConvertFrom-Toml -ModuleName Xmip { $declared }.GetNewClosure()
        [string] $path = Join-Path $TestDrive 'suite.toml'
        Set-Content -LiteralPath $path -Value '# read through the mock'

        $suite = InModuleScope Xmip -Parameters @{ Path = $path } {
            param($Path)
            Read-XmipTestSuiteDeclaration -Path $Path
        }

        $suite.Provider | Should -Be 'example'
        $suite.Name | Should -Be 'example.Nightly'
        $suite.Command | Should -Be 'run.ps1'
    }

    It 'refuses a suite declaration that leaves a key out, in words (<Shape>)' {
        $declared = New-TomlShape -Shape $Shape -Value @{ provider = 'example'; name = 'Nightly' }
        Mock ConvertFrom-Toml -ModuleName Xmip { $declared }.GetNewClosure()
        [string] $path = Join-Path $TestDrive 'half.toml'
        Set-Content -LiteralPath $path -Value '# read through the mock'

        {
            InModuleScope Xmip -Parameters @{ Path = $path } {
                param($Path)
                Read-XmipTestSuiteDeclaration -Path $Path
            }
        } | Should -Throw '*declares no command*'
    }

    It 'reads a process declaration and drops one whose process is gone (<Shape>)' {
        $mine = New-TomlShape -Shape $Shape -Value @{ pid = $PID; purpose = 'test' }
        Mock ConvertFrom-Toml -ModuleName Xmip { $mine }.GetNewClosure()
        Mock Get-Process -ModuleName Xmip {
            [pscustomobject] @{ ProcessName = 'xmip-test'; Id = $Id }
        }
        [string] $directory = Join-Path $TestDrive "process-$Shape"
        New-Item -ItemType Directory -Path $directory | Out-Null
        Set-Content -LiteralPath (Join-Path $directory 'xmip-test.toml') -Value '# mock'

        $byId = InModuleScope Xmip -Parameters @{ Path = $directory } {
            param($Path)
            Read-XmipProcessDeclaration -Path $Path
        }

        $byId.Keys | Should -Be @($PID)
        InModuleScope Xmip -Parameters @{ Said = $byId[$PID] } {
            param($Said)
            Get-TomlValue -Node $Said -Name 'purpose' | Should -Be 'test'
        }
    }
}

Describe 'Where TOML is read' {
    It 'is through Get-TomlValue, and no reader asks a document for its shape' {
        # A reader that calls .Contains( or .Keys on what ConvertFrom-Toml
        # returned works with one shape of PSToml and breaks on the other.
        [string] $module = Join-Path $PSScriptRoot '..' 'Xmip'
        [string[]] $asking = @(
            Get-ChildItem -LiteralPath $module -Filter '*.ps1' -File |
                Where-Object {
                    (Get-Content -LiteralPath $_.FullName -Raw) -match 'ConvertFrom-Toml'
                } |
                Where-Object {
                    (Get-Content -LiteralPath $_.FullName -Raw) -match
                    '\$(document|said|declared|record|manifest|map|toml)\.(Contains\(|Keys\b)'
                } |
                ForEach-Object Name
        )

        $asking | Should -BeNullOrEmpty
    }
}
