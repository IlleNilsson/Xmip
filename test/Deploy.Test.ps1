#Requires -Version 7.6.5

# The deploy lists are the manifest's. deploy/dsc/xmip-node.dsc.yaml and
# deploy/ansible/roles/xmip_node/defaults/main.yml each name every technology a
# node carries and which start, and the owner's rule (2026-09-08) is that every
# technology landed goes into both. They were hand-edited three times on
# 2026-09-09 and then held equal to architecture.toml by this file; now
# Sync-XmipEstate -Deploy writes them (Update-XmipDeployList), and this fails
# when a file is not what it would write.

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    $script:Manifest = Get-XmipManifest -Path (Join-Path $script:Root 'architecture.toml')

    $script:Written = InModuleScope Xmip -Parameters @{
        Root     = $script:Root
        Manifest = $script:Manifest
    } {
        param($Root, $Manifest)
        New-XmipDeployList -Root $Root -Manifest $Manifest
    }

    $script:Technology = @(
        InModuleScope Xmip -Parameters @{ Manifest = $script:Manifest } {
            param($Manifest)
            Get-XmipDeployedTechnology -Manifest $Manifest
        }
    )
}

Describe 'The deploy lists are generated from the manifest' {
    It 'carries something to deploy, and starts part of it' {
        $script:Technology.Count | Should -BeGreaterThan 50
        @($script:Technology | Where-Object Start).Count | Should -BeGreaterThan 0
    }

    It 'has <_> as Sync-XmipEstate -Deploy writes it' -ForEach @(
        'deploy/dsc/xmip-node.dsc.yaml'
        'deploy/ansible/roles/xmip_node/defaults/main.yml'
    ) {
        [string] $now = Get-Content -LiteralPath (Join-Path $script:Root $_) -Raw

        $now | Should -BeExactly $script:Written[$_] -Because (
            "architecture.toml changed and $_ did not; run Sync-XmipEstate -Deploy"
        )
    }
}
