#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    The estate map as a page: the tree, who uses whom, and where the manifest
    and the build disagree.

.DESCRIPTION
    The owner read the estate as a published page, and the page was written by
    hand on 2026-09-10 — every count and every dependency edge typed in. It
    was eleven days stale and still drew `diagnose`, retired two days before,
    as a module with no dependencies (the owner, 2026-09-21). ADR-0020 clause 5
    is the whole lesson: a second copy of the estate is wrong within a week.
    So the page is generated from what `estate-map.md` is generated from, and
    it says which commit it was built from, so a reader can tell a stale page
    at a glance instead of by arithmetic.

    The edges are what each repository's build uses (`Get-XmipRepositoryUse`),
    not what the manifest declares, and where the two differ the page says so.

    Style: doc/governance/powershell-style.md
#>


function ConvertTo-XmipEstateShortName {
    <#
        .SYNOPSIS
            A repository's name as the page prints it: `xmip-core-route` is
            `route`, and `xmip-core` itself is `core`.

        .PARAMETER Name
            The repository's full name.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    if ($Name -eq 'xmip-core') {
        return 'core'
    }

    return ($Name -replace '^xmip-core-', '' -replace '^xmip-', '')
}


function New-XmipEstatePageModule {
    <#
        .SYNOPSIS
            One module as the page draws it: its weight, its languages, what it
            uses and declares, and the technologies beneath it.

        .PARAMETER Entry
            The module, from Get-XmipEstateRepository.

        .PARAMETER Repository
            Every declared repository.

        .PARAMETER Weight
            Lines per mount, per language, from Get-XmipMapWeight.

        .PARAMETER Module
            The full names of every module the graph draws.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $Entry,

        [Parameter(Mandatory = $true)]
        [PSCustomObject[]] $Repository,

        [Parameter(Mandatory = $true)]
        [hashtable] $Weight,

        [Parameter(Mandatory = $true)]
        [string[]] $Module
    )

    [hashtable] $spoken = @{}
    [int] $lines = 0

    if ($Weight.ContainsKey($Entry.Mount)) {
        foreach ($language in $Weight[$Entry.Mount].Keys) {
            $spoken[$language] = $Weight[$Entry.Mount][$language]
            $lines += $Weight[$Entry.Mount][$language]
        }
    }

    [PSCustomObject[]] $beneath = @($Repository | Where-Object { $_.Parent -eq $Entry.Name })
    [string[]] $uses = @($Entry.Uses)
    [string[]] $declared = @($Entry.Declared | Where-Object { "$_" -ne '' })

    return @{
        name       = ConvertTo-XmipEstateShortName -Name $Entry.Name
        domain     = $Entry.Domain.ToLowerInvariant()
        lines      = $lines
        languages  = $spoken
        uses       = @($uses | Where-Object { $_ -in $Module } |
            ForEach-Object { ConvertTo-XmipEstateShortName -Name $_ })
        technology = @($uses | Where-Object { $_ -notin $Module }).Count
        nested     = @($beneath | Where-Object { $_.Mounted }).Count
        notBuilt   = @($beneath | Where-Object { -not $_.Mounted }).Count
        undeclared = @($uses | Where-Object { $_ -notin $declared } |
            ForEach-Object { ConvertTo-XmipEstateShortName -Name $_ })
        unused     = @($declared | Where-Object { $_ -notin $uses } |
            ForEach-Object { ConvertTo-XmipEstateShortName -Name $_ })
    }
}


function New-XmipEstatePage {
    <#
        .SYNOPSIS
            The page, as one self-contained HTML string.

        .DESCRIPTION
            The data is embedded in the page rather than fetched beside it, so
            one file is the whole of it and a published copy cannot lose half
            of itself. The template is `estate-page.html` beside this file.

        .PARAMETER Root
            The estate root, for the commit the page names.

        .PARAMETER Repository
            Every declared repository, with `Uses` and `Declared`.

        .PARAMETER Source
            Every source file, from Get-XmipSourceFile.

        .PARAMETER Map
            The generated estate-map.md, whose tree the page shows as it is.

        .PARAMETER Retired
            The manifest's `[[retired]]` entries.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        [PSCustomObject[]] $Repository,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [PSCustomObject[]] $Source,

        [Parameter(Mandatory = $true)]
        [string] $Map,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Retired
    )

    [PSCustomObject[]] $mounted = @($Repository | Where-Object { $_.Mounted })
    [hashtable] $weight = Get-XmipMapWeight -Source $Source -Mount @($mounted.Mount)

    # A module is a repository mounted under module/. The Playground declares
    # itself an Operation and mounts under test/; drawn as a module it put a
    # hundred edges on the page and hid every other one.
    [PSCustomObject[]] $modules = @(
        $mounted |
            Where-Object { $_.Domain -in $script:XmipMapDomain } |
            Where-Object { $_.Mount -like 'module/*' }
    )
    [string[]] $names = @($modules.Name)

    [hashtable[]] $drawn = @(
        foreach ($entry in $modules) {
            [hashtable] $one = @{
                Entry      = $entry
                Repository = $Repository
                Weight     = $weight
                Module     = $names
            }

            New-XmipEstatePageModule @one
        }
    )

    # What the graph leaves out, said in numbers rather than hidden: the
    # Playground links every technology and would bury the drawing.
    [hashtable[]] $outside = @(
        $mounted |
            Where-Object { $_.Domain -ne 'Technology' } |
            Where-Object { $_.Name -notin $names } |
            ForEach-Object {
                @{
                    name     = ConvertTo-XmipEstateShortName -Name $_.Name
                    uses     = @($_.Uses).Count
                    declared = @($_.Declared).Count
                }
            }
    )

    # The tree exactly as estate-map.md draws it, so the page and the document
    # cannot disagree about a single count.
    [string[]] $tree = @(
        ($Map -split "`n") |
            ForEach-Object -Begin { $inside = $false } -Process {
                if ($_ -eq '```text') { $inside = $true; return }
                if ($inside -and $_ -eq '```') { $inside = $false; return }
                if ($inside) { $_ }
            }
    )

    [int] $total = 0

    foreach ($spoken in $weight.Values) {
        foreach ($count in $spoken.Values) {
            $total += $count
        }
    }

    [hashtable] $data = @{
        commit    = ((& git -C $Root rev-parse --short HEAD) -join '').Trim()
        built     = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm') + ' UTC'
        declared  = $Repository.Count
        mounted   = $mounted.Count
        lines     = $total
        notBuilt  = @($Repository | Where-Object { -not $_.Mounted }).Count
        tree      = $tree
        modules   = $drawn
        outside   = $outside
        retired   = @(
            foreach ($gone in $Retired) {
                [string] $name = [string](Get-TomlValue -Node $gone -Name 'name' -Default '')

                @{
                    name   = ConvertTo-XmipEstateShortName -Name $name
                    on     = [string](Get-TomlValue -Node $gone -Name 'on' -Default '')
                    reason = [string](Get-TomlValue -Node $gone -Name 'reason' -Default '')
                }
            }
        )
    }

    # Inside a <script>, `</` would end it. JSON allows the escaped slash.
    [string] $json = ($data | ConvertTo-Json -Depth 8 -Compress) -replace '</', '<\/'
    [string] $template = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'estate-page.html')

    return $template.Replace('/*ESTATE*/null', $json)
}
