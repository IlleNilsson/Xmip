BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'Modules' 'Xmip.Manifest.psm1') -Force
}

Describe 'Xmip manifest compatibility' {
    It 'accepts a compatible manifest' {
        $manifest = [pscustomobject]@{
            schemaVersion = '1.2.0'
            architectureVersion = '1.0.0'
            minimumScriptVersion = '1.0.0'
        }

        (Test-XmipManifestCompatibility $manifest).compatible | Should -BeTrue
    }

    It 'rejects a newer schema major version' {
        $manifest = [pscustomobject]@{ schemaVersion = '2.0.0' }
        { Test-XmipManifestCompatibility $manifest } | Should -Throw
    }

    It 'rejects a newer required script version' {
        $manifest = [pscustomobject]@{
            schemaVersion = '1.2.0'
            minimumScriptVersion = '9.0.0'
        }
        { Test-XmipManifestCompatibility $manifest } | Should -Throw
    }
}
