#requires -PSEdition Core
#requires -Version 7.6

Describe 'Xmip-Estate manifest compatibility' {
    It 'accepts the current compact manifest structure' {
        $manifest = Get-Content (Join-Path $PSScriptRoot '..' 'architecture.json') -Raw | ConvertFrom-Json -Depth 100
        @($manifest.commonRepositories).Count | Should -BeGreaterThan 0
        @($manifest.commonRepositories[0]).Count | Should -BeGreaterOrEqual 5
        @($manifest.technologyGroups).Count | Should -BeGreaterThan 0
        @($manifest.technologyGroups[0]).Count | Should -BeGreaterOrEqual 3
    }

    It 'keeps Plan mode separate from Apply mode' {
        $script = Get-Content (Join-Path $PSScriptRoot '..' 'Xmip-Estate.ps1') -Raw
        $script | Should -Match '\[switch\] \$Apply'
        $script | Should -Match "if\(-not \$Apply\)"
    }

    It 'does not use remote-tracking submodule updates' {
        $script = Get-Content (Join-Path $PSScriptRoot '..' 'Xmip-Estate.ps1') -Raw
        $script | Should -Not -Match 'submodule.+--remote'
    }
}
