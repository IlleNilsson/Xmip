#requires -PSEdition Core
#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Get-XmipEstate {
    <#
        .SYNOPSIS
            Reads one view of the Xmip development estate.

        .DESCRIPTION
            Estate is the repositories, submodules, manifest and architectural
            decisions used to build Xmip. This command only reads. Use
            Sync-XmipEstate or Publish-XmipEstate when the estate must change.

        .EXAMPLE
            Get-XmipEstate -View Status -Short

        .EXAMPLE
            Get-XmipEstate -View Decision | Where-Object Status -Like 'Proposed*'
    #>
    [CmdletBinding()]
    [OutputType([PSObject])]
    param(
        [Parameter(Position = 0)]
        [ValidateSet('Status', 'Root', 'Manifest', 'Decision', 'DecisionIndex', 'Slice')]
        [string] $View = 'Status',

        [Parameter()]
        [string] $Path,

        [Parameter()]
        [switch] $Short,

        [Parameter()]
        [string] $Slice
    )

    $ErrorActionPreference = 'Stop'

    switch ($View) {
        'Root' { return Get-XmipRepositoryRoot -StartAt ($Path ?? (Get-Location).Path) }
        'Manifest' {
            [string] $manifest = $Path ?? (Join-Path (Get-XmipRepositoryRoot) 'architecture.toml')
            return Get-XmipManifest -Path $manifest
        }
        'Decision' { return Get-XmipDecisionRecord -DecisionRoot $Path }
        'DecisionIndex' { return New-XmipDecisionIndex -DecisionRoot $Path }
        'Slice' {
            if ([string]::IsNullOrWhiteSpace($Path)) { return Get-XmipEstateSlice -Slice $Slice }
            return Get-XmipEstateSlice -Slice $Slice -SliceRoot $Path
        }
        default {
            [string] $root = $Path ?? (Get-XmipRepositoryRoot)
            return Get-XmipStatus -RepositoryRoot $root -Short:$Short
        }
    }
}
