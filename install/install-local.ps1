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
    "$InstallRoot\data\persistence",
    "$InstallRoot\data\management",
    "$InstallRoot\logs"
)

foreach ($path in $paths) {
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Path $path | Out-Null
    }
}

$nodeConfig = @"
[node]
name = "local-xmip-node"
cluster = "local-xmip-cluster"

[storage]
persistence_path = "$InstallRoot\data\persistence"
management_path = "$InstallRoot\data\management"

[modules]
load_from = "$InstallRoot\modules"
"@

$configPath = "$InstallRoot\config\xmip-node.toml"
if (-not (Test-Path $configPath)) {
    Set-Content -Path $configPath -Value $nodeConfig -Encoding UTF8
}

Write-Host "Xmip local layout initialized at $InstallRoot"
Write-Host "Persistence store: $InstallRoot\data\persistence"
Write-Host "Management store:   $InstallRoot\data\management"
