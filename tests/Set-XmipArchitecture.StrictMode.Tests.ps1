Describe 'Set-XmipArchitecture optional manifest properties' {
    It 'does not require minimumScriptVersion' {
        $manifest = [pscustomobject]@{
            schemaVersion = '1.2.0'
            owner = 'IlleNilsson'
            defaults = [pscustomobject]@{ maturity = 'reserved' }
            commonRepositories = @()
            technologyGroups = @()
        }

        { $manifest.PSObject.Properties['minimumScriptVersion'] } | Should -Not -Throw
        $manifest.PSObject.Properties['minimumScriptVersion'] | Should -BeNullOrEmpty
    }

    It 'reads minimumScriptVersion safely when present' {
        $manifest = [pscustomobject]@{ minimumScriptVersion = '1.1.0' }
        $manifest.PSObject.Properties['minimumScriptVersion'].Value | Should -Be '1.1.0'
    }

    It 'does not require architectureVersion' {
        $manifest = [pscustomobject]@{ schemaVersion = '1.2.0' }
        $manifest.PSObject.Properties['architectureVersion'] | Should -BeNullOrEmpty
    }
}
