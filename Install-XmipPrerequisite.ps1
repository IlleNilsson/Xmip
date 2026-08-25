#requires -PSEdition Core
#requires -Version 7.0

<#
.SYNOPSIS
    Reports and installs what a machine needs to run or build Xmip.

.DESCRIPTION
    The prerequisites live in xmip-prerequisite.toml. This script applies them.

    PowerShell runs on Windows, Linux and macOS, and the package manager differs
    on each, so nothing here assumes winget. The manifest declares a prerequisite
    per operating system and per manager, and this script picks the one that is
    actually present.

    It never elevates. Where a prerequisite needs administrative rights it says
    so and prints the command, because a setup script that silently runs elevated
    installers is the thing an estate blocks.

.EXAMPLE
    ./Install-XmipPrerequisite.ps1 -Role developer -WhatIf
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [ValidateSet('operator', 'developer', 'build')]
    [string] $Role = 'developer',

    [string] $ManifestPath = (Join-Path $PSScriptRoot 'xmip-prerequisite.toml'),

    [switch] $IncludeOptional,

    [switch] $PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-XmipOperatingSystem {
    if ($IsWindows) { return 'windows' }
    if ($IsMacOS)   { return 'macos' }
    if ($IsLinux)   { return 'linux' }
    throw "Unrecognised operating system. Xmip tooling supports Windows, Linux and macOS."
}

function Get-XmipPackageManager {
    # The first manager actually on PATH wins. Order is deliberate: a machine with
    # both apt and dnf is unusual, and apt is the likelier intent on such a box.
    param([string] $OperatingSystem)
    $candidates = switch ($OperatingSystem) {
        'windows' { @('winget') }
        'macos'   { @('brew') }
        'linux'   { @('apt', 'dnf', 'zypper', 'pacman') }
    }
    foreach ($candidate in $candidates) {
        if (Get-Command $candidate -ErrorAction SilentlyContinue) { return $candidate }
    }
    return $null
}

function Test-XmipCommand {
    param([string] $Probe)
    if (-not $Probe) { return $null }
    $name = ($Probe -split '\s+')[0]
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { return $null }
    try { return (& $name --version 2>$null | Select-Object -First 1) } catch { return 'present' }
}

function Resolve-XmipRole {
    # Roles are cumulative and declared in the manifest, not here.
    param($RoleTable, [string] $Name)
    $seen = [System.Collections.Generic.List[string]]::new()
    function Walk([string] $current) {
        if ($seen.Contains($current)) { return }
        $seen.Add($current)
        foreach ($parent in @($RoleTable.$current.include)) { if ($parent) { Walk $parent } }
    }
    Walk $Name
    return $seen
}

# --- bootstrap -------------------------------------------------------------
#
# The prerequisite list is TOML and reading TOML needs PSToml, so PSToml is the
# one prerequisite this script knows about without reading the file.

if (-not (Get-Module -ListAvailable -Name PSToml)) {
    if ($PSCmdlet.ShouldProcess('PSToml', 'Install from the PowerShell Gallery')) {
        Write-Host 'INSTALL: PSToml (required to read the manifest)'
        Install-Module -Name PSToml -Scope CurrentUser -Force -AcceptLicense
    }
    else {
        Write-Warning 'PSToml is missing. Nothing further can be read without it.'
        return
    }
}
Import-Module PSToml -ErrorAction Stop

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Prerequisite manifest not found: $ManifestPath"
}

$manifest = ConvertFrom-Toml -InputObject (Get-Content -LiteralPath $ManifestPath -Raw)
$os = Get-XmipOperatingSystem
$manager = Get-XmipPackageManager -OperatingSystem $os
$roles = Resolve-XmipRole -RoleTable $manifest.role -Name $Role

Write-Host "Operating system : $os"
Write-Host "Package manager  : $(if ($manager) { $manager } else { 'none found' })"
Write-Host "Roles            : $($roles -join ', ')"
Write-Host ''

$results = [System.Collections.Generic.List[object]]::new()

foreach ($name in $manifest.prerequisite.Keys) {
    $item = $manifest.prerequisite.$name
    if (-not $roles.Contains([string]$item.role)) { continue }

    $optional = $false
    if ($item.PSObject.Properties.Name -contains 'optional') { $optional = [bool]$item.optional }
    if ($optional -and -not $IncludeOptional) {
        Write-Host "SKIPPED OPTIONAL: $name"
        continue
    }

    $probe = if ($item.PSObject.Properties.Name -contains 'probe') { [string]$item.probe } else { $null }
    $found = Test-XmipCommand -Probe $probe

    if ($found) {
        Write-Host "PRESENT: $name  ($found)"
        $results.Add([pscustomobject]@{ name = $name; status = 'present'; detail = $found })
        continue
    }

    # PSToml is the bootstrap and has no per-system table.
    if ($item.PSObject.Properties.Name -contains 'source' -and $item.source -eq 'psgallery') {
        Write-Host "PRESENT: $name (installed during bootstrap)"
        $results.Add([pscustomobject]@{ name = $name; status = 'present'; detail = 'psgallery' })
        continue
    }

    if ($item.PSObject.Properties.Name -notcontains $os) {
        Write-Host "NOT APPLICABLE: $name on $os"
        $results.Add([pscustomobject]@{ name = $name; status = 'not-applicable'; detail = $os })
        continue
    }

    $spec = $item.$os
    $needsElevation = ($spec.PSObject.Properties.Name -contains 'elevation') -and [bool]$spec.elevation

    if ($spec.PSObject.Properties.Name -contains 'command') {
        Write-Warning "MANUAL: $name -> $($spec.command)"
        $results.Add([pscustomobject]@{ name = $name; status = 'manual'; detail = [string]$spec.command })
        continue
    }

    if (-not $manager -or ($spec.PSObject.Properties.Name -notcontains $manager)) {
        $fallback = if ($spec.PSObject.Properties.Name -contains 'fallback') { [string]$spec.fallback } else { $null }
        if ($fallback) {
            Write-Warning "MANUAL: $name is not packaged for $manager on $os. See $fallback"
            $results.Add([pscustomobject]@{ name = $name; status = 'manual'; detail = $fallback })
        }
        else {
            Write-Warning "UNAVAILABLE: $name has no entry for $manager on $os"
            $results.Add([pscustomobject]@{ name = $name; status = 'unavailable'; detail = $manager })
        }
        continue
    }

    $package = [string]$spec.$manager
    $arguments = switch ($manager) {
        'winget'  { @('install', '--id', $package, '--exact', '--accept-package-agreements', '--accept-source-agreements') }
        'brew'    { @('install', $package) }
        'apt'     { @('install', '-y', $package) }
        'dnf'     { @('install', '-y', $package) }
        'zypper'  { @('install', '-y', $package) }
        'pacman'  { @('-S', '--noconfirm', $package) }
    }
    if ($spec.PSObject.Properties.Name -contains 'override') {
        $arguments += @('--override', [string]$spec.override)
    }

    $line = "$manager $($arguments -join ' ')"
    if ($needsElevation -or ($os -eq 'linux' -and $manager -ne 'brew')) {
        Write-Warning "NEEDS ELEVATION: $name"
        Write-Host "    $line"
        $results.Add([pscustomobject]@{ name = $name; status = 'needs-elevation'; detail = $line })
        continue
    }

    if ($PSCmdlet.ShouldProcess($name, $line)) {
        Write-Host "INSTALL: $name"
        & $manager @arguments
        $results.Add([pscustomobject]@{ name = $name; status = 'installed'; detail = $line })
    }
    else {
        $results.Add([pscustomobject]@{ name = $name; status = 'would-install'; detail = $line })
    }
}

# Rust components are a second step: rustup installs the toolchain, the
# components come from rustup itself rather than from any package manager.
$rust = $manifest.prerequisite.rust
if ($roles.Contains([string]$rust.role) -and (Get-Command rustup -ErrorAction SilentlyContinue)) {
    foreach ($component in @($rust.component)) {
        if ($PSCmdlet.ShouldProcess("rustup component $component", 'rustup component add')) {
            Write-Host "COMPONENT: $component"
            rustup component add $component | Out-Host
        }
    }
}

Write-Host ''
$summary = $results | Group-Object status | ForEach-Object { "$($_.Name)=$($_.Count)" }
Write-Host "Summary: $($summary -join '  ')"

if ($PassThru) { $results }
