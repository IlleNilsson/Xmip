#requires -PSEdition Core
#requires -Version 7.7.0

<#
    Every surface shows the Xmip mark, and shows the one asset/brand holds.

    The owner, 2026-11-04: *Why dont we use the brand, the assets, the
    Icons. For the VS Code extension and executables and what not?*
    asset/brand/brand.toml names each surface: what it shows, the copy it
    keeps where it is a repository of its own, and the file that names it.
    Held here: the icon and the resource made from the mark are what
    Write-XmipBrand makes of it now, each copy is the source byte for byte,
    and each surface's file names what it shows. Sync-XmipEstate -Brand
    writes what differs.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')
    $script:Brand = Join-Path $script:Root 'asset/brand'
    $script:Surface = @(InModuleScope Xmip { Get-XmipBrandSurface })

    function Test-XmipSameByte([string] $Path, [byte[]] $Content) {
        if (-not (Test-Path -LiteralPath $Path)) { return $false }
        [byte[]] $held = [System.IO.File]::ReadAllBytes($Path)
        [System.Linq.Enumerable]::SequenceEqual($held, $Content)
    }
}

Describe 'The brand' {
    It 'names surfaces' {
        $script:Surface.Count | Should -BeGreaterThan 0
    }

    It 'holds the icon and resource made from the mark as they are made now' {
        [byte[]] $icon = InModuleScope Xmip -Parameters @{ Brand = $script:Brand } {
            param($Brand) ConvertTo-XmipIcon -Brand $Brand
        }
        [byte[]] $resource = InModuleScope Xmip -Parameters @{ Brand = $script:Brand } {
            param($Brand) ConvertTo-XmipIconResource -Brand $Brand
        }
        Test-XmipSameByte -Path (Join-Path $script:Brand 'xmip-x.ico') -Content $icon |
            Should -BeTrue -Because 'Sync-XmipEstate -Brand writes it'
        Test-XmipSameByte -Path (Join-Path $script:Brand 'xmip-x.res') -Content $resource |
            Should -BeTrue -Because 'Sync-XmipEstate -Brand writes it'
    }

    It 'holds every copy byte for byte as asset/brand holds its source' {
        foreach ($surface in @($script:Surface | Where-Object Copy)) {
            [string] $from = Join-Path $script:Brand $surface.From
            [byte[]] $source = [System.IO.File]::ReadAllBytes($from)
            [string] $because = "$($surface.Name) keeps $($surface.Copy); Sync-XmipEstate -Brand"
            Test-XmipSameByte -Path (Join-Path $script:Root $surface.Copy) -Content $source |
                Should -BeTrue -Because $because
        }
    }

    It 'carries the extension icon into the VSIX VS Code reads' {
        [string] $extension = Join-Path $script:Root 'module/core/operation/gui/vscode/extension'
        $package = Get-Content -Raw -LiteralPath (Join-Path $extension 'package.json') |
            ConvertFrom-Json
        [string] $manifest = InModuleScope Xmip -Parameters @{ Package = $package } {
            param($Package) Get-XmipExtensionManifest -Package $Package
        }
        $manifest | Should -Match '<Icon>extension/media/xmip-x\.png</Icon>'
        $manifest | Should -Match 'Icons\.Default" Path="extension/media/xmip-x\.png"'
    }

    It 'has each surface name what it shows' {
        foreach ($surface in $script:Surface) {
            Join-Path $script:Brand $surface.From | Should -Exist
            [string] $text = Get-Content -Raw -LiteralPath (Join-Path $script:Root $surface.In)
            $text.Contains($surface.Names) |
                Should -BeTrue -Because "$($surface.Name): $($surface.In) names $($surface.Names)"
        }
    }
}
