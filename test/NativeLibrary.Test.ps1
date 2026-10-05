#requires -PSEdition Core
#requires -Version 7.6.5

<#
    RocksDB's C++ is compiled once per version and linked from
    .local-work/native/rocksdb/<version> (.cargo/config.toml), never once per
    build. A version bump with the old library still named would link the
    wrong RocksDB silently; this test makes it a failed gate instead.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')
    [string] $configuration = Join-Path -Path $script:Root -ChildPath '.cargo/config.toml'
    [string] $script:Config = Get-Content -Raw -LiteralPath $configuration
}

Describe 'RocksDB is linked from the one library kept for its version' {
    It 'names the version every lock resolves, and the library is there' {
        [string] $named = 'ROCKSDB_LIB_DIR\s*=\s*\{\s*value\s*=\s*"([^"]+)"'
        $script:Config -match $named | Should -BeTrue
        [string] $kept = $Matches[1]
        [string] $version = Split-Path -Leaf $kept

        [hashtable] $locks = @{
            Path    = Join-Path -Path $script:Root -ChildPath 'module/platform'
            Filter  = 'Cargo.lock'
            Recurse = $true
            Depth   = 2
        }
        [string] $entry = 'name = "librocksdb-sys"\s*\r?\nversion = "[^+"]+\+([^"]+)"'
        [string[]] $resolved = @(
            Get-ChildItem @locks |
                ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName } |
                ForEach-Object {
                    [regex]::Matches($_, $entry) | ForEach-Object { $_.Groups[1].Value }
                } |
                Sort-Object -Unique
        )

        [string] $why = "cargo resolves RocksDB $($resolved -join ', ') and " +
            ".cargo/config.toml links ${version}: build the new one once " +
            '(ROCKSDB_COMPILE=1 cargo build in module/platform/persist/rocksdb), ' +
            'copy rocksdb.lib from its build out directory to ' +
            '.local-work/native/rocksdb/<version>, and name it there'

        $resolved | Should -Be @($version) -Because $why
        Join-Path -Path $script:Root -ChildPath "$kept/rocksdb.lib" | Should -Exist
    }
}
