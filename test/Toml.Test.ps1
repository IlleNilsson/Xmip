#Requires -Version 7.6.5

# ConvertFrom-Toml has returned a dictionary in one version of PSToml and an
# object in the next. The module reads a TOML file in one place, Read-XmipToml
# in Xmip/Read-XmipToml.ps1, and writes one in one place, Write-XmipToml; what it read is
# read through one pair, Get-TomlKey and Get-TomlValue, so which shape the
# installed PSToml returns is nobody's business. This holds the pair on both
# shapes, the readers that once asked for one of them, and the one place.

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    # The same document in both shapes PSToml has returned.
    function New-TomlShape {
        param(
            [Parameter(Mandatory = $true)]
            [string] $Shape,

            [Parameter(Mandatory = $true)]
            [hashtable] $Value
        )

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
}

Describe 'Where TOML is read' {
    It 'is in Read-XmipToml.ps1 alone: one reader and one writer' {
        # About twenty-five copies of `Import-Module PSToml; Get-Content -Raw |
        # ConvertFrom-Toml` and a regular expression reading one key stood
        # where Read-XmipToml does now (2026-09-27).
        [string] $module = Join-Path $script:Root 'Xmip'
        [string] $parse = 'ConvertFrom-Toml|ConvertTo-Toml|Import-Module (-Name )?PSToml'
        [string[]] $parsing = @(
            Get-ChildItem -LiteralPath $module -Filter '*.ps1' -File |
                Where-Object { $_.Name -ne 'Read-XmipToml.ps1' } |
                Where-Object {
                    [string[]] $code = @(
                        Get-Content -LiteralPath $_.FullName |
                            Where-Object { $_ -notmatch '^\s*#' }
                    )

                    ($code -join "`n") -match $parse
                } |
                ForEach-Object Name
        )

        [string] $because = 'Read-XmipToml and Write-XmipToml are the one place'
        $parsing | Should -BeNullOrEmpty -Because $because
    }

    It 'is through Get-TomlValue, and no reader asks a document for its shape' {
        # A reader that calls .Contains( or .Keys on what Read-XmipToml
        # returned works with one shape of PSToml and breaks on the other.
        [string] $module = Join-Path $script:Root 'Xmip'
        [string[]] $asking = @(
            Get-ChildItem -LiteralPath $module -Filter '*.ps1' -File |
                Where-Object {
                    (Get-Content -LiteralPath $_.FullName -Raw) -match 'Read-XmipToml'
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
