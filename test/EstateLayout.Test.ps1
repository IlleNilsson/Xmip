#requires -PSEdition Core
#requires -Version 7.7.0

<#
    The estate's files and its working area's folders are named in one place,
    Get-XmipEstateLayout, so a renamed file or a moved folder is one edit.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')
    $script:ModuleFolder = Join-Path $script:Root 'Xmip'
}

Describe 'The estate layout' {
    # Where cargo builds follows CARGO_TARGET_DIR, which this run may have
    # inherited from the landing running it (its copy of the runtime
    # library): saved, cleared and given back.
    BeforeAll {
        $script:TargetWas = $env:CARGO_TARGET_DIR
        Remove-Item -Path 'env:CARGO_TARGET_DIR' -ErrorAction SilentlyContinue
    }

    AfterAll {
        $env:CARGO_TARGET_DIR = $script:TargetWas
    }

    It 'answers cargo''s build directory by cargo''s rule' {
        InModuleScope Xmip -Parameters @{ Estate = (Join-Path $TestDrive 'estate') } {
            param([string] $Estate)
            [string] $elsewhere = Join-Path $TestDrive 'built'

            try {
                (Get-XmipEstateLayout -Root $Estate).Build | Should -Be (Join-Path $Estate 'target')
                $env:CARGO_TARGET_DIR = $elsewhere
                (Get-XmipEstateLayout -Root $Estate).Build | Should -Be $elsewhere
            }
            finally {
                Remove-Item -Path 'env:CARGO_TARGET_DIR' -ErrorAction SilentlyContinue
            }
        }
    }

    It 'answers every path under the root it is given' {
        InModuleScope Xmip -Parameters @{ Estate = (Join-Path $TestDrive 'estate') } {
            param([string] $Estate)

            [pscustomobject] $layout = Get-XmipEstateLayout -Root $Estate

            foreach ($property in $layout.PSObject.Properties) {
                $property.Value | Should -BeLike "$Estate*"
            }

            $layout.Manifest | Should -Be (Join-Path $Estate $script:XmipManifestName)
            $layout.Essentials | Should -BeLike "$($layout.Work)*"
        }
    }

    It 'is the only module code that names the working area or the estate''s files' {
        # Read as tokens, so a comment or help text may say where something
        # is; a string in code asks the layout.
        [string] $named = '\.local-work|architecture\.toml|prerequisite\.toml'
        [string[]] $spelled = @(Get-ChildItem -LiteralPath $script:ModuleFolder -Filter '*.ps1' |
            Where-Object { $_.Name -ne 'Get-XmipEstateLayout.ps1' } |
            ForEach-Object {
                [System.Management.Automation.Language.Token[]] $tokens = $null
                $null = [System.Management.Automation.Language.Parser]::ParseFile(
                    $_.FullName, [ref] $tokens, [ref] $null)
                [string] $file = $_.Name
                $tokens | Where-Object {
                    $_.Kind -in 'StringLiteral', 'StringExpandable', 'HereStringLiteral',
                        'HereStringExpandable' -and $_.Text -match $named
                } | ForEach-Object { "${file}:$($_.Extent.StartLineNumber)" }
            })

        $spelled | Should -BeNullOrEmpty
    }
}
