param(
    [string]$InstallRoot = "$env:ProgramData\Xmip"
)

$ErrorActionPreference = "Stop"

$paths = @(
    $InstallRoot,
    "$InstallRoot\bin",
    "$InstallRoot\config",
    "$InstallRoot\modules",
    "$InstallRoot\data",
    "$InstallRoot\data\persistence-rocksdb",
    "$InstallRoot\logs"
)

foreach ($path in $paths) {
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Path $path | Out-Null
    }
}

$managementDb = "$InstallRoot\data\management.sqlite"
if (-not (Test-Path $managementDb)) {
    New-Item -ItemType File -Path $managementDb | Out-Null
}

$nodeConfig = @"
[node]
name = "local-xmip-node"
cluster = "local-xmip-cluster"

[storage]
persistence_engine = "rocksdb"
persistence_path = "$InstallRoot\data\persistence-rocksdb"
management_engine = "sqlite"
management_path = "$InstallRoot\data\management.sqlite"

[modules]
load_from = "$InstallRoot\modules"
"@

$configPath = "$InstallRoot\config\xmip-node.toml"
if (-not (Test-Path $configPath)) {
    Set-Content -Path $configPath -Value $nodeConfig -Encoding UTF8
}

Write-Host "Xmip local layout initialized at $InstallRoot"
Write-Host "Persistence store: $InstallRoot\data\persistence-rocksdb"
Write-Host "Management store:   $InstallRoot\data\management.sqlite"
