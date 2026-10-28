#requires -PSEdition Core
#requires -Version 7.6.7

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

    The packages are the ones `cargo metadata` resolves, offline, with every
    estate crate patched to its working tree as a landing builds them
    (New-XmipLocalPatch).
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    [string] $manifest = Join-Path $script:Root 'module/core/capability/unit/Cargo.toml'
    [string] $patch = & (Get-Module -Name Xmip) {
        param([string] $Root)
        New-XmipLocalPatch -RepositoryRoot $Root
    } $script:Root

    [string[]] $arguments = @(
        'metadata', '--offline', '--format-version', '1', '--manifest-path', $manifest,
        '--config', $patch
    )
    $metadata = & cargo @arguments 2>$null | ConvertFrom-Json -Depth 64
    $script:Resolved = $LASTEXITCODE -eq 0 -and $null -ne $metadata

    # The packages the module's own build compiles: its normal dependencies,
    # followed from the module down, never a test's or a build script's.
    $script:Packages = @()
    if ($script:Resolved) {
        [hashtable] $byId = @{}
        foreach ($package in $metadata.packages) { $byId[$package.id] = $package }
        [hashtable] $nodes = @{}
        foreach ($node in $metadata.resolve.nodes) { $nodes[$node.id] = $node }
        [HashSet[string]] $seen = [HashSet[string]]::new()
        [Queue[string]] $next = [Queue[string]]::new()
        $next.Enqueue($metadata.resolve.root)
        while ($next.Count -gt 0) {
            [string] $id = $next.Dequeue()
            if (-not $seen.Add($id)) { continue }
            foreach ($dependency in $nodes[$id].deps) {
                [bool] $normal = @(
                    $dependency.dep_kinds | Where-Object { $null -eq $_.kind }
                ).Count -gt 0
                if ($normal) { $next.Enqueue($dependency.pkg) }
            }
        }
        $script:Packages = @($seen | ForEach-Object { $byId[$_] })
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
