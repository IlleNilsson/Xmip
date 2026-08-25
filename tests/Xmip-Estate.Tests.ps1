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

    It 'never issues a DELETE, however the estate drifts' {
        $script = Get-Content (Join-Path $script:Root 'Xmip-Estate.ps1') -Raw
        # The call site, not the ValidateSet. Invoke-GitHubApi declares DELETE as
        # a legal verb so the helper stays general; what must never appear is
        # anything actually invoking it. Matching the declaration was the first
        # version of this test and it failed on its own scaffolding.
        $script | Should -Not -Match 'Invoke-GitHubApi\s+DELETE' `
            -Because 'Xmip-Estate reconciles; it does not remove repositories'
        $script | Should -Not -Match 'Method\s*=\s*.DELETE.' `
            -Because 'nor by building the request by hand'
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
        foreach ($name in 'Xmip-Estate', 'Xmip-Git', 'Xmip-Prerequisite', 'Get-XmipManifest') {
            $exported | Should -Contain $name
        }
    }

    It 'declares Core and 7.6 on every entry point' {
        foreach ($file in 'Xmip.psm1', 'Xmip-Estate.ps1', 'Xmip-Git.ps1', 'Xmip-Prerequisite.ps1') {
            $head = (Get-Content (Join-Path $script:Root $file) -TotalCount 3) -join "`n"
            $head | Should -Match '#requires -PSEdition Core'
            $head | Should -Match '#requires -Version 7\.6'
        }
    }
}

Describe 'ADR-0021: current platforms only, enforced' {
    BeforeAll {
        Import-Module PSToml -ErrorAction Stop
        $script:Prereq = ConvertFrom-Toml -InputObject (Get-Content (Join-Path $script:Root 'prerequisite.toml') -Raw -Encoding utf8)
    }

    It 'declares a minimum for every platform the ADR names' {
        foreach ($name in 'powershell', 'dotnet', 'pester', 'git') {
            [string]$script:Prereq.prerequisite.$name.minimum |
                Should -Not -BeNullOrEmpty -Because "ADR-0021 makes $name a floor, not a preference"
        }
    }

    It 'keeps the manifest floor and the #requires floor in step' {
        # The one that drifts silently: prerequisite.toml says 7.6 while an
        # entry point still says 7.2, and nothing notices.
        $declared = [string]$script:Prereq.prerequisite.powershell.minimum
        foreach ($file in 'Xmip.psm1', 'Xmip-Estate.ps1', 'Xmip-Git.ps1', 'Xmip-Prerequisite.ps1') {
            $head = (Get-Content (Join-Path $script:Root $file) -TotalCount 3) -join "`n"
            $head | Should -Match ([regex]::Escape("#requires -Version $declared")) `
                -Because "$file must state the same floor as prerequisite.toml"
        }
    }

    It 'tracks channels rather than pinning versions' {
        $toolchain = Get-Content (Join-Path $script:Root 'rust-toolchain.toml') -Raw
        $toolchain | Should -Match 'channel\s*=\s*"stable"'
        $toolchain | Should -Not -Match 'channel\s*=\s*"1\.' -Because 'ADR-0021 forbids a pinned toolchain'
    }

    It 'requires the Core edition, which excludes Windows PowerShell 5.1' {
        foreach ($file in 'Xmip.psm1', 'Xmip-Estate.ps1', 'Xmip-Git.ps1', 'Xmip-Prerequisite.ps1') {
            $head = (Get-Content (Join-Path $script:Root $file) -TotalCount 3) -join "`n"
            $head | Should -Match '#requires -PSEdition Core'
        }
    }

    It 'fails rather than reports when a floor is not met' {
        $script = Get-Content (Join-Path $script:Root 'Xmip-Prerequisite.ps1') -Raw
        $script | Should -Match 'Write-Error' -Because 'an unmet floor must be an error, not a warning'
        $script | Should -Match "'outdated'" -Because 'a version below the floor needs its own status'
    }
}
