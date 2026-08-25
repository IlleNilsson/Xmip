#requires -PSEdition Core
#requires -Version 7.6

BeforeAll {
    $script:Root = Join-Path $PSScriptRoot '..'
    Import-Module (Join-Path $script:Root 'Xmip.psm1') -Force -DisableNameChecking
}

Describe 'The manifest' {
    It 'is TOML, and the estate expands from it' {
        $manifest = Get-XmipManifest (Join-Path $script:Root 'architecture.toml')
        @($manifest.repositories).Count | Should -BeGreaterThan 200
    }

    It 'names every repository from its position in the tree' {
        $manifest = Get-XmipManifest (Join-Path $script:Root 'architecture.toml')
        # The path is the name: dots become hyphens and nothing else happens.
        @($manifest.repositories | Where-Object { $_.name -notlike 'xmip-*' }).Count |
            Should -Be 0
    }

    It 'gives every repository a domain, a role and a maturity' {
        $manifest = Get-XmipManifest (Join-Path $script:Root 'architecture.toml')
        foreach ($property in 'architecturalDomain', 'repositoryRole', 'maturity') {
            @($manifest.repositories | Where-Object { -not $_.$property }).Count |
                Should -Be 0 -Because "every repository needs $property"
        }
    }

    It 'has no duplicate repository names' {
        $manifest = Get-XmipManifest (Join-Path $script:Root 'architecture.toml')
        $names = @($manifest.repositories.name)
        $names.Count | Should -Be (@($names | Sort-Object -Unique).Count)
    }
}

Describe 'Xmip-Estate' {
    It 'has no -Apply: an operation switch means do it, -WhatIf means do not' {
        $script = Get-Content (Join-Path $script:Root 'Xmip-Estate.ps1') -Raw
        $script | Should -Not -Match '\$Apply'
        $script | Should -Match '\[switch\] \$Create'
        $script | Should -Match '\[switch\] \$Configure'
    }

    It 'supports ShouldProcess, which is what -WhatIf rides on' {
        $script = Get-Content (Join-Path $script:Root 'Xmip-Estate.ps1') -Raw
        $script | Should -Match 'SupportsShouldProcess'
    }

    It 'never deletes a repository' {
        $script = Get-Content (Join-Path $script:Root 'Xmip-Estate.ps1') -Raw
        $script | Should -Not -Match "Method\s+DELETE|'DELETE'"
    }

    It 'does not use remote-tracking submodule updates' {
        foreach ($file in 'Xmip-Estate.ps1', 'Xmip-Git.ps1') {
            $script = Get-Content (Join-Path $script:Root $file) -Raw
            $script | Should -Not -Match 'submodule.+--remote'
        }
    }
}

Describe 'The module is the entry point' {
    It 'exports both commands and the reader' {
        $exported = (Get-Module Xmip).ExportedFunctions.Keys
        foreach ($name in 'Xmip-Estate', 'Xmip-Git', 'Get-XmipManifest') {
            $exported | Should -Contain $name
        }
    }

    It 'declares Core and 7.6 on every entry point' {
        # Install-XmipPrerequisite.ps1 is deliberately excluded: a bootstrap
        # script that refuses to run on the version it upgrades is no use.
        foreach ($file in 'Xmip.psm1', 'Xmip-Estate.ps1', 'Xmip-Git.ps1') {
            $head = (Get-Content (Join-Path $script:Root $file) -TotalCount 3) -join "`n"
            $head | Should -Match '#requires -PSEdition Core'
            $head | Should -Match '#requires -Version 7\.6'
        }
    }
}
