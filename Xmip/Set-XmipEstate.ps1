#requires -PSEdition Core
#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Set-XmipEstate {
    <#
        .SYNOPSIS
            Defines a named, machine-local slice of the Xmip repository estate.

        .DESCRIPTION
            Include names repositories from architecture.toml. Their dependencies
            are resolved automatically and recorded with the slice. This command
            declares local intent; Sync-XmipEstate materializes it.

        .EXAMPLE
            Set-XmipEstate -Slice Runtime -Path D:\Repos\Xmip-Runtime -Include
            xmip-core-runtime, xmip-core-powershell
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType('Xmip.EstateSlice')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidatePattern('^[A-Za-z][A-Za-z0-9._-]*$')]
        [string] $Slice,

        [Parameter(Mandatory)]
        [Alias('Destination', 'Directory')]
        [string] $Path,

        [Parameter(Mandatory)]
        [Alias('Feature', 'Features', 'Repository')]
        [string[]] $Include,

        [Parameter()]
        [string] $ManifestPath = (Join-Path (Get-XmipRepositoryRoot) 'architecture.toml'),

        [Parameter()]
        [string] $SliceRoot = (Join-Path (Get-XmipRepositoryRoot) '.local-work/estate'),

        [Parameter()]
        [switch] $PassThru
    )

    $ErrorActionPreference = 'Stop'
    $manifest = Get-XmipManifest -Path $ManifestPath
    [string[]] $repository = Resolve-XmipEstateSlice -Manifest $manifest -Include $Include
    [string] $definition = Join-Path $SliceRoot "$Slice.toml"

    if (-not $PSCmdlet.ShouldProcess($definition, "Define estate slice $Slice")) { return }

    Import-Module PSToml -ErrorAction Stop
    New-Item -ItemType Directory -Path $SliceRoot -Force | Out-Null

    [System.Collections.Specialized.OrderedDictionary] $document = [ordered]@{
        slice = $Slice
        path = [IO.Path]::GetFullPath($Path)
        include = @($Include)
        repository = @($repository)
    }

    ConvertTo-Toml -InputObject $document |
        Set-Content -LiteralPath $definition -Encoding utf8

    if ($PassThru) { return Get-XmipEstateSlice -Slice $Slice -SliceRoot $SliceRoot }
}
