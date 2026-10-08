#requires -PSEdition Core
#requires -Version 7.6.5
<#
.SYNOPSIS
Uses the estate's prerequisite manifest for the lab development machine.
.DESCRIPTION
The host stages the current Xmip tooling and prerequisite manifest here. Set
requires internet access and winget, which LabGuest.ps1 registers for Administrator.
Get reports the real prerequisite state; no completion marker substitutes for it.
#>
[CmdletBinding()]
[OutputType([void])]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Get', 'Set')]
    [string] $Operation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[string] $root = Join-Path -Path $PSScriptRoot -ChildPath 'Estate'
Import-Module -Name (Join-Path -Path $root -ChildPath 'Xmip/Xmip.psd1') -Force
[hashtable] $prerequisite = @{
    Role = 'developer'
    ManifestPath = Join-Path -Path $root -ChildPath 'prerequisite.toml'
    PassThru = $true
    Confirm = $false
}
if ($Operation -eq 'Set') {
    if ($null -eq (Get-Command -Name winget -ErrorAction SilentlyContinue)) {
        throw 'winget is not registered for Administrator; LabGuest.ps1 registers it on Set.'
    }
    Install-XmipPrerequisite @prerequisite -Install | Out-Null
}
[object[]] $results = @(Install-XmipPrerequisite @prerequisite)
if ($results.Count -eq 0 -or @($results | Where-Object {
    $_.Status -notin @('present', 'installed', 'not-applicable')
}).Count -gt 0) {
    throw 'Xmip developer prerequisites are not all satisfied; inspect the report above.'
}
