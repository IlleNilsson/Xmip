$ErrorActionPreference = 'Stop'

$commit = $env:GITHUB_SHA
if ([string]::IsNullOrWhiteSpace($commit)) {
    $commit = (git rev-parse HEAD).Trim()
}

$shortSha = $commit.Substring(0, 7)
$date = (Get-Date).ToUniversalTime().ToString('yyyyMMdd')
$timestamp = (Get-Date).ToUniversalTime().ToString('o')
$version = "0.0.2-canary.$date.$shortSha"

$manifest = [ordered]@{
    product = 'Xmip Linear'
    channel = 'canary'
    version = $version
    commit = $commit
    shortCommit = $shortSha
    builtAtUtc = $timestamp
    runtimeContract = 'protobuf/grpc-compatible'
    deploymentProfile = 'prototype'
    moduleSet = @(
        'xmip-kernel'
    )
    architectureSnapshot = @(
        'docs/architecture/modularity.md'
        'docs/architecture/kernel-boundary.md'
        'docs/architecture/feature-folder-convention.md'
        'docs/architecture/deployment-profiles.md'
    )
}

$manifest | ConvertTo-Json -Depth 10 | Set-Content -Path 'canary-manifest.json' -Encoding UTF8

Write-Host "Created canary-manifest.json"
Write-Host "Version: $version"
