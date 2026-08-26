#requires -PSEdition Core
#requires -Version 7.6

BeforeAll {
    $script:Root = Join-Path $PSScriptRoot '..'
    $script:ModuleRoot = Join-Path $script:Root 'Xmip'

    # Every file that can be dot-sourced or invoked directly, and so must carry
    # its own #requires. Named once because three tests walk the same list.
    [string[]] $script:EntryPoints = @(
        'Xmip.psm1'
        'Sync-XmipEstate.ps1'
        'Sync-XmipRepository.ps1'
        'Install-XmipPrerequisite.ps1'
        'Install-XmipModule.ps1'
    )

    Import-Module (Join-Path $script:ModuleRoot 'Xmip.psd1') -Force
}

Describe 'The manifest' {
    It 'is TOML, and the estate expands from it' {
        $manifest = Get-XmipManifest -Path (Join-Path $script:Root 'architecture.toml')
        @($manifest.repositories).Count | Should -BeGreaterThan 200
    }

    It 'names every repository from its position in the tree' {
        $manifest = Get-XmipManifest -Path (Join-Path $script:Root 'architecture.toml')
        # The path is the name: dots become hyphens and nothing else happens.
        @($manifest.repositories | Where-Object { $_.name -notlike 'xmip-*' }).Count |
            Should -Be 0
    }

    It 'gives every repository a domain, a role and a maturity' {
        $manifest = Get-XmipManifest -Path (Join-Path $script:Root 'architecture.toml')
        foreach ($property in 'architecturalDomain', 'repositoryRole', 'maturity') {
            @($manifest.repositories | Where-Object { -not $_.$property }).Count |
                Should -Be 0 -Because "every repository needs $property"
        }
    }

    It 'has no duplicate repository names' {
        $manifest = Get-XmipManifest -Path (Join-Path $script:Root 'architecture.toml')
        $names = @($manifest.repositories.name)
        $names.Count | Should -Be (@($names | Sort-Object -Unique).Count)
    }
}

Describe 'Sync-XmipEstate' {
    It 'has no -Apply: an operation switch means do it, -WhatIf means do not' {
        $script = Get-Content (Join-Path $script:ModuleRoot 'Sync-XmipEstate.ps1') -Raw
        $script | Should -Not -Match '\$Apply'
        $script | Should -Match '\[switch\] \$Create'
        $script | Should -Match '\[switch\] \$Configure'
    }

    It 'supports ShouldProcess, which is what -WhatIf rides on' {
        $script = Get-Content (Join-Path $script:ModuleRoot 'Sync-XmipEstate.ps1') -Raw
        $script | Should -Match 'SupportsShouldProcess'
    }

    It 'never issues a DELETE, however the estate drifts' {
        $script = Get-Content (Join-Path $script:ModuleRoot 'Sync-XmipEstate.ps1') -Raw
        # The call site, not the ValidateSet. Invoke-GitHubApi declares DELETE as
        # a legal verb so the helper stays general; what must never appear is
        # anything actually invoking it. Matching the declaration was the first
        # version of this test and it failed on its own scaffolding.
        [string] $never = 'Sync-XmipEstate reconciles; it does not remove repositories'

        $script | Should -Not -Match 'Invoke-GitHubApi\s+DELETE' -Because $never
        $script | Should -Not -Match 'Method\s*=\s*.DELETE.' -Because 'nor by hand'
    }

    It 'does not use remote-tracking submodule updates' {
        # The call site, not the prose. 'submodule.+--remote' matched a comment
        # saying the code never does this, which is the same false positive the
        # DELETE test above was written to avoid. A real use passes --remote as
        # a quoted git argument.
        [string] $because = 'ADR-0016: parents pin commits, they do not track a branch'

        foreach ($file in 'Sync-XmipEstate.ps1', 'Sync-XmipRepository.ps1') {
            $script = Get-Content (Join-Path $script:ModuleRoot $file) -Raw

            $script | Should -Not -Match "'--remote'" -Because $because
            $script | Should -Not -Match '"--remote"' -Because $because
        }
    }
}

Describe 'The module is the entry point' {
    It 'exports both commands and the reader' {
        $exported = (Get-Module Xmip).ExportedFunctions.Keys

        [string[]] $required = @(
            'Sync-XmipEstate'
            'Sync-XmipRepository'
            'Install-XmipPrerequisite'
            'Get-XmipManifest'
        )

        foreach ($name in $required) {
            $exported | Should -Contain $name
        }
    }

    It 'declares Core and 7.6 on every entry point' {
        foreach ($file in $script:EntryPoints) {
            $head = (Get-Content (Join-Path $script:ModuleRoot $file) -TotalCount 3) -join "`n"
            $head | Should -Match '#requires -PSEdition Core'
            $head | Should -Match '#requires -Version 7\.6'
        }
    }
}

Describe 'ADR-0021: current platforms only, enforced' {
    BeforeAll {
        Import-Module PSToml -ErrorAction Stop
        [string] $prerequisitePath = Join-Path $script:Root 'prerequisite.toml'
        [string] $prerequisiteText = Get-Content $prerequisitePath -Raw -Encoding utf8

        $script:Prereq = ConvertFrom-Toml -InputObject $prerequisiteText
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

        foreach ($file in $script:EntryPoints) {
            $head = (Get-Content (Join-Path $script:ModuleRoot $file) -TotalCount 3) -join "`n"
            [string] $because = "$file must state the same floor as prerequisite.toml"

            $head | Should -Match ([regex]::Escape("#requires -Version $declared")) -Because $because
        }
    }

    It 'tracks channels rather than pinning versions' {
        $toolchain = Get-Content (Join-Path $script:Root 'rust-toolchain.toml') -Raw
        $toolchain | Should -Match 'channel\s*=\s*"stable"'
        $toolchain | Should -Not -Match 'channel\s*=\s*"1\.' -Because 'ADR-0021 forbids a pinned toolchain'
    }

    It 'requires the Core edition, which excludes Windows PowerShell 5.1' {
        foreach ($file in $script:EntryPoints) {
            $head = (Get-Content (Join-Path $script:ModuleRoot $file) -TotalCount 3) -join "`n"
            $head | Should -Match '#requires -PSEdition Core'
        }
    }

    It 'fails rather than reports when a floor is not met' {
        $script = Get-Content (Join-Path $script:ModuleRoot 'Install-XmipPrerequisite.ps1') -Raw
        $script | Should -Match 'Write-Error' -Because 'an unmet floor must be an error, not a warning'
        $script | Should -Match "'outdated'" -Because 'a version below the floor needs its own status'
    }
}
