#requires -PSEdition Core
#requires -Version 7.6.5

<#
    Where unsafe code may live (ADR-0050, amendment 2026-09-25): a crate that
    must call a C interface allows it in one named file, every block in that
    file says where its pointers come from, how long they live and who frees
    them, and every other file forbids it.

    The runtime keeps its whole C boundary in one folder, src/ffi/ (ADR-0050,
    refined 2026-09-25); every other crate gets one file. The folder and the
    list below are the whole of the estate's unsafe. A new file on the list is
    a change a reviewer sees here, with its reason; a file that lowers the lint
    anywhere else fails.
#>

BeforeAll {
    $script:Root = Join-Path $PSScriptRoot '..'
    Import-Module (Join-Path $script:Root 'Xmip/Xmip.psd1') -Force

    # The runtime keeps its whole C boundary in one folder (ADR-0050, refined
    # 2026-09-25): the operator's table and exports (ADR-0027) and the loader
    # (ADR-0057). Only the runtime has a folder.
    $script:Folder = 'module/platform/runtime/src/ffi/'

    # Every other crate: exactly one file, and why it crosses a C interface.
    $script:Allowed = [ordered]@{
        # The far side of xmip_module.h: the conforming module a loader probes.
        'module/foundation/abi/examples/conforming.rs'          = 'ADR-0012, the probe fixture'
        # A contract's export table (ADR-0061).
        'module/core/capability/contract/.src/export.rs'        = 'ADR-0061 clause 8'
        # The language server loads the runtime's library.
        'module/core/operation/gui/vscode/.src/runtime.rs'      = 'ADR-0014, amendment 2026-09-10'
        # The Windows Event Log and the registry (ADR-0062).
        'module/core/operation/audit/src/windows_event_log.rs' = 'ADR-0050, amendment 2026-09-25'
        # CryptProtectData and CryptUnprotectData: the key home on Windows.
        'module/core/capability/secret/dpapi/src/crypt_protect.rs' = 'ADR-0063 clause 4'
    }

    # The crate a file belongs to: the nearest directory above it with a
    # Cargo.toml.
    function Get-UnsafeCrate([string] $Path) {
        [string] $at = Split-Path -Parent (Join-Path $script:Root $Path)

        while ($at -and -not (Test-Path -LiteralPath (Join-Path $at 'Cargo.toml'))) {
            $at = Split-Path -Parent $at
        }

        return [System.IO.Path]::GetFullPath($at)
    }

    function Test-UnsafePlace([string] $Path) {
        return $Path.StartsWith($script:Folder) -or $script:Allowed.Contains($Path)
    }

    $script:Rust = @(Get-XmipSourceFile -Language Rust)

    # `#![allow(unsafe_code)]`, `#[allow(unsafe_code)]`, and the multi-line
    # form with a reason.
    $script:Lowering = '#!?\[\s*allow\(\s*unsafe_code'
}

Describe 'Unsafe code lives only in the files the estate lists' {
    It 'finds no file allowing unsafe code that is not on the list' {
        [string[]] $found = @(
            $script:Rust | Where-Object {
                (Get-Content -LiteralPath (Join-Path $script:Root $_.Path) -Raw) -match
                    $script:Lowering
            } | ForEach-Object { $_.Path -replace '\\', '/' }
        )
        [string[]] $stranger = @($found | Where-Object { -not (Test-UnsafePlace $_) })

        $stranger | Should -BeNullOrEmpty -Because (
            'unsafe lives in the runtime''s ffi folder or one named file per crate (ADR-0050)')
    }

    It 'lists exactly one file for each crate' {
        [string[]] $twice = @(
            $script:Allowed.Keys | ForEach-Object { Get-UnsafeCrate $_ } |
                Group-Object | Where-Object Count -gt 1 | ForEach-Object Name
        )

        $twice | Should -BeNullOrEmpty -Because 'one file per crate; only the runtime has a folder'
    }

    It 'lists no file that is gone or no longer allows it' {
        [string[]] $stale = @(
            $script:Allowed.Keys | Where-Object {
                $path = Join-Path $script:Root $_
                -not (Test-Path -LiteralPath $path) -or
                    (Get-Content -LiteralPath $path -Raw) -notmatch $script:Lowering
            }
        )

        $stale | Should -BeNullOrEmpty -Because 'the list says what is true'
    }

    It 'says of every unsafe block in a listed file or the folder why it is sound' {
        [string[]] $held = @($script:Allowed.Keys) + @(
            $script:Rust | ForEach-Object { $_.Path -replace '\\', '/' } |
                Where-Object { $_.StartsWith($script:Folder) }
        )
        [string[]] $bare = @(
            foreach ($file in $held) {
                [string[]] $lines = @(Get-Content -LiteralPath (Join-Path $script:Root $file))

                for ($at = 0; $at -lt $lines.Count; $at++) {
                    if ($lines[$at] -notmatch '\bunsafe\s*\{') {
                        continue
                    }

                    [int] $from = [Math]::Max(0, $at - 8)
                    [string] $before = $lines[$from..$at] -join "`n"

                    if ($before -notmatch 'SAFETY') {
                        "${file}:$($at + 1)"
                    }
                }
            }
        )

        $bare | Should -BeNullOrEmpty -Because (
            'every block names its pointers, their lifetime and who frees them')
    }

    It 'lowers the lint only in a crate that holds a listed file or the folder' {
        [string[]] $crates = @(
            @($script:Allowed.Keys) + @($script:Folder + 'operate.rs') |
                ForEach-Object { Get-UnsafeCrate $_ }
        )
        [string[]] $lowered = @(
            $script:Rust | ForEach-Object { Get-UnsafeCrate $_.Path } | Sort-Object -Unique |
                Where-Object {
                    (Get-Content -LiteralPath (Join-Path $_ 'Cargo.toml') -Raw) -match
                        'unsafe_code\s*=\s*"(deny|warn|allow)"'
                } | Where-Object { $_ -notin $crates }
        )

        $lowered | Should -BeNullOrEmpty -Because (
            'a crate with no listed file forbids unsafe code outright')
    }
}
