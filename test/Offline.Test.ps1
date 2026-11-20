#requires -PSEdition Core
#requires -Version 7.7.0

using namespace System.Collections.Generic

<#
    The standard units work offline, and say so (ADR-0045, amendment
    2026-10-22). The owner, that day: *We can only use standards, code and
    compiled units that explicitly work offline!* A unit's manifest saying
    `offline = true` is a promise; this is what holds it. Every package the
    standard module's build compiles — the estate's crates and every third
    party's — is read for code that reaches a network: a socket of the
    standard library's, a crate of sockets, an HTTP client. One found is a
    failed gate, never a setting to turn off: a crate that can reach a
    network is out even where a setting could disable it.

    The packages are the ones `cargo metadata` resolves, offline, in the
    estate's one workspace, every estate crate its working tree (ADR-0016,
    amendment 2026-11-20).
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    [string] $manifest = Join-Path $script:Root 'module/core/capability/unit/Cargo.toml'
    [string[]] $arguments = @(
        'metadata', '--offline', '--format-version', '1', '--manifest-path', $manifest
    )
    # As a hashtable: the workspace's metadata holds a crate whose features
    # differ by case alone (`Default` and `default`).
    $metadata = & cargo @arguments 2>$null | ConvertFrom-Json -Depth 64 -AsHashtable
    $script:Resolved = $LASTEXITCODE -eq 0 -and $null -ne $metadata

    # The packages the module's own build compiles: its normal dependencies,
    # followed from the module down, never a test's or a build script's, with
    # the features the module alone turns on. The workspace's metadata
    # resolves every member at once, so the module's own tree says which.
    $script:Packages = @()
    if ($script:Resolved) {
        [string[]] $asked = @(
            'tree', '--offline', '--manifest-path', $manifest, '-p', 'xmip-core-unit',
            '-e', 'normal', '--prefix', 'none', '--format', '{p}'
        )
        [string[]] $tree = @(& cargo @asked 2>$null)
        [HashSet[string]] $built = [HashSet[string]]::new()
        foreach ($line in $tree) {
            if ($line -match '^(\S+) v(\S+)') {
                $null = $built.Add("$($Matches[1]) $($Matches[2])")
            }
        }
        $script:Packages = @(
            $metadata.packages | Where-Object { $built.Contains("$($_.name) $($_.version)") }
        )
    }

    # What reaches a network: the standard library's sockets, and the crates
    # that are sockets or clients over them.
    $script:Reaching = 'std::net::(TcpStream|TcpListener|UdpSocket)|\bToSocketAddrs\b|' +
        '\bsocket2::|\bmio::net\b|\btokio::net\b|\breqwest::|\bureq::|\bhyper::|\bcurl::'
    $script:Clients = @(
        'reqwest', 'ureq', 'hyper', 'curl', 'isahc', 'attohttpc', 'surf', 'h2', 'h3',
        'socket2', 'mio', 'tokio', 'rustls', 'native-tls', 'openssl', 'hickory-resolver',
        'trust-dns-resolver', 'xmip-core-library-net', 'xmip-core-library-tls',
        'xmip-core-transport'
    )
}

Describe 'The standard units reach no network' {
    It 'resolves the module offline, so the check reads a build' {
        $script:Resolved | Should -BeTrue -Because (
            'cargo metadata --offline resolves xmip-core-unit once its dependencies are ' +
            'fetched; fetch them once with a build'
        )
        $script:Packages.Count | Should -BeGreaterThan 20
    }

    It 'compiles no crate that is a network client or a socket' {
        [string[]] $found = @(
            $script:Packages | Where-Object { $_.name -in $script:Clients } |
                ForEach-Object { "$($_.name) $($_.version)" }
        )
        $found | Should -BeNullOrEmpty -Because 'a crate that can reach a network is not admitted'
    }

    It 'compiles no source that opens a socket' {
        [string[]] $found = @(
            foreach ($package in $script:Packages) {
                [string] $folder = Split-Path -Parent $package.manifest_path
                [string] $sources = Join-Path $folder 'src'
                if (-not (Test-Path -LiteralPath $sources)) { $sources = Join-Path $folder '.src' }
                if (-not (Test-Path -LiteralPath $sources)) { continue }
                Get-ChildItem -LiteralPath $sources -Recurse -Filter *.rs |
                    Select-String -Pattern $script:Reaching |
                    Where-Object { $_.Line -notmatch '^\s*(//|\*)' } |
                    ForEach-Object {
                        "$($package.name) $($package.version): $($_.Filename):$($_.LineNumber)"
                    }
            }
        )
        $found | Should -BeNullOrEmpty -Because (
            "these lines reach a network, and the standard units work offline:`n" +
            ($found -join "`n")
        )
    }
}
