#requires -PSEdition Core
#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Test-XmipEstate {
    <#
        .SYNOPSIS
            Tests one invariant or prerequisite of the Xmip estate.

        .EXAMPLE
            Test-XmipEstate -Target Manifest

        .EXAMPLE
            Test-XmipEstate -Target Prerequisite -Role developer
    #>
    [CmdletBinding()]
    [OutputType([PSObject])]
    param(
        [Parameter(Position = 0)]
        [ValidateSet('Manifest', 'Prerequisite')]
        [string] $Target = 'Manifest',

        [Parameter()]
        [string] $Path,

        [Parameter()]
        [ValidateSet('operator', 'developer', 'build')]
        [string] $Role = 'developer',

        [Parameter()]
        [switch] $IncludeOptional
    )

    $ErrorActionPreference = 'Stop'

    if ($Target -eq 'Prerequisite') {
        $prerequisite = @{
            Role = $Role
            IncludeOptional = $IncludeOptional
            PassThru = $true
        }

        if (-not [string]::IsNullOrWhiteSpace($Path)) {
            $prerequisite.ManifestPath = $Path
        }

        return Install-XmipPrerequisite @prerequisite
    }

    [string] $manifestPath = $Path ?? (Join-Path (Get-XmipRepositoryRoot) 'architecture.toml')
    $manifest = Get-XmipManifest -Path $manifestPath
    Test-XmipManifest -Manifest $manifest
}
