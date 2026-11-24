#requires -PSEdition Core
#requires -Version 7.7.0

<#
    RocksDB's C++ is compiled once per version and linked from
    .local-work/native/rocksdb/<version> (.cargo/config.toml), never once per
    build. A version bump with the old library still named would link the
    wrong RocksDB silently; this test makes it a failed gate instead.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')
}

Describe 'RocksDB is linked from the one library kept for its version' {
    It 'names the version every lock resolves, and the library is there' {
        # Read as Install-XmipPrerequisite reads it, which compiles it once.
        $native = & (Get-Module -Name Xmip) {
            param([string] $Root)
            Get-XmipNativeLibrary -Root $Root
        } $script:Root
        [string] $version = $native.Version

        # The workspace's lock, the one cargo resolves every crate by (ADR-0016,
        # amendment 2026-11-20). A submodule's own lock, which no build has read
        # since, is neither held by Git nor sent to a test computer, which this
        # read until 2026-11-24 (open problem 145).
        [string] $lock = Join-Path -Path $script:Root -ChildPath 'Cargo.lock'
        $lock | Should -Exist -Because 'cargo writes the workspace''s lock at its first build'
        [string] $entry = 'name = "librocksdb-sys"\s*\r?\nversion = "[^+"]+\+([^"]+)"'
        [string[]] $resolved = @(
            [regex]::Matches((Get-Content -Raw -LiteralPath $lock), $entry) |
                ForEach-Object { $_.Groups[1].Value } |
                Sort-Object -Unique
        )

        [string] $why = "cargo resolves RocksDB $($resolved -join ', ') and " +
            ".cargo/config.toml links ${version}: name the new version there, then " +
            'Install-XmipPrerequisite -Install compiles it once'

        $resolved | Should -Be @($version) -Because $why
        $native.Library | Should -Exist
    }
}
