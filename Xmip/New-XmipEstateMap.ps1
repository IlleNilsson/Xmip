#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    Generates doc/architecture/estate-map.md from architecture.toml.

.DESCRIPTION
    `repository-model.md` section 7 draws where the modules mount. It is
    hand-drawn, it covers the forty-one submodules, and it stops there — the
    manifest declares 330 repositories, and the 290 technologies appeared on
    no map at all. Being hand-drawn is also why it was wrong: it carried three
    unmounted modules and an off-by-one count until 2026-09-19.

    ADR-0020 clause 5 is why this is generated rather than written: a document
    that lists repositories is a second source of truth and will be wrong
    within a week. A view is not a second source: test/EstateMap.Test.ps1
    regenerates and fails when the committed map differs, the way
    test/Decision.Test.ps1 holds the decision index. ADR-0060.

    `Get-XmipEstateRepository.ps1` reads the estate; this renders it.

    Style: doc/governance/powershell-style.md
#>

# The domains, in reading order, and the order the map's sections take. This is
# the map's own shape rather than the manifest's, which is why it lives here.
# Technology is deliberately absent: a technology is drawn under the repository
# that hosts it, never in a list of its own.
[string[]] $script:XmipMapDomain = @(
    'Foundation'
    'Capability'
    'Operation'
    'Platform'
)

# The column the generated prose wraps at. Under the hundred the style rules
# gate, so the map passes the same line-length rule as everything else.
[int] $script:XmipMapWidth = 78


function Format-XmipMapLine {
    <#
        .SYNOPSIS
            One long line of words, wrapped to the map's width.

        .DESCRIPTION
            Greedy, on spaces, every line after the first carrying $Indent.
            The technology lists are the only thing here long enough to need
            it, and the style rules gate the generated file like any other.

        .PARAMETER Text
            The whole line, already joined.

        .PARAMETER Indent
            What a continuation line begins with.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Text,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Indent
    )

    [string[]] $line = @()
    [string] $current = ''

    foreach ($word in ($Text -split ' ')) {
        if ([string]::IsNullOrEmpty($current)) {
            $current = $word
            continue
        }

        if (($current.Length + 1 + $word.Length) -le $script:XmipMapWidth) {
            $current = "$current $word"
            continue
        }

        $line += $current
        $current = "$Indent$word"
    }

    if (-not [string]::IsNullOrEmpty($current)) {
        $line += $current
    }

    return $line
}


function New-XmipMapCountRow {
    <#
        .SYNOPSIS
            One row of a count table: declared, mounted, not mounted.

        .PARAMETER Label
            The row's first cell, already formatted.

        .PARAMETER Row
            The repositories the row counts.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Label,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [PSCustomObject[]] $Row
    )

    [int] $mounted = @($Row | Where-Object { $_.Mounted }).Count

    return "| $Label | $($Row.Count) | $mounted | $($Row.Count - $mounted) |"
}


function New-XmipMapCount {
    <#
        .SYNOPSIS
            The count per domain and the count per maturity.

        .DESCRIPTION
            The two tables the map exists for. Declared against mounted is the
            gap no document in the estate stated before.

        .PARAMETER Repository
            Every declared repository.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]] $Repository
    )

    [string[]] $line = @(
        '| Domain | Declared | Mounted | Not mounted |'
        '| --- | ---: | ---: | ---: |'
    )

    foreach ($name in ($script:XmipMapDomain + 'Technology')) {
        $line += New-XmipMapCountRow -Label $name -Row @(
            $Repository | Where-Object { $_.Domain -eq $name }
        )
    }

    $line += (New-XmipMapCountRow -Label '**Total**' -Row $Repository)

    $line += @(
        ''
        '| Maturity | Declared | Mounted | Not mounted |'
        '| --- | ---: | ---: | ---: |'
    )

    foreach ($word in ($Repository.Maturity | Sort-Object -Unique)) {
        $line += New-XmipMapCountRow -Label $word -Row @(
            $Repository | Where-Object { $_.Maturity -eq $word }
        )
    }

    return $line
}


function New-XmipMapRow {
    <#
        .SYNOPSIS
            One repository's row in its domain's table.

        .DESCRIPTION
            A repository that is not composed here says so in words rather
            than leaving the cell blank, because a blank cell in a generated
            table reads as a generator that failed.

        .PARAMETER Entry
            The repository.

        .PARAMETER Repository
            Every declared repository, for counting what this one hosts.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $Entry,

        [Parameter(Mandatory = $true)]
        [PSCustomObject[]] $Repository
    )

    [string] $mount = 'not mounted'

    if ($Entry.Mounted) {
        $mount = "``$($Entry.Mount)``"
    }

    [int] $hosted = @(
        $Repository | Where-Object { $_.Parent -eq $Entry.Name }
    ).Count

    [string] $count = '—'

    if ($hosted -gt 0) {
        $count = [string] $hosted
    }

    return "| ``$($Entry.Name)`` | $($Entry.Maturity) | $mount | $count |"
}


function Format-XmipMapName {
    <#
        .SYNOPSIS
            One technology's name in a list, marked when it stands out.

        .DESCRIPTION
            Bare where the parent composes all of its technologies or none of
            them. A trailing asterisk on the ones missing from a parent that
            composes some, which is the only case where the mark informs.

        .PARAMETER Entry
            The technology.

        .PARAMETER Mounted
            How many of its parent's technologies are composed.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $Entry,

        [Parameter(Mandatory = $true)]
        [int] $Mounted
    )

    if ($Mounted -eq 0 -or $Entry.Mounted) {
        return $Entry.Leaf
    }

    return "$($Entry.Leaf)*"
}


function New-XmipMapTechnologyState {
    <#
        .SYNOPSIS
            The sentence above a technology list: what is composed, and where.

        .PARAMETER Parent
            The hosting repository.

        .PARAMETER Hosted
            Its technologies.

        .PARAMETER Mounted
            How many of them are composed here.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $Parent,

        [Parameter(Mandatory = $true)]
        [PSCustomObject[]] $Hosted,

        [Parameter(Mandatory = $true)]
        [int] $Mounted
    )

    [string] $said = ''

    if (-not $Parent.Mounted) {
        $said = 'The parent is not composed here, so what it composes cannot ' +
                'be read; every technology below is declared only.'
    }
    elseif ($Mounted -eq 0) {
        $said = "Declared, and none composed: ``$($Parent.Mount)`` has no " +
                '`.gitmodules`.'
    }
    elseif ($Mounted -eq $Hosted.Count -and $Mounted -eq 1) {
        $said = "Composed in ``$($Parent.Mount)``."
    }
    elseif ($Mounted -eq $Hosted.Count) {
        $said = "All $Mounted composed in ``$($Parent.Mount)``."
    }
    else {
        $said = "$Mounted of $($Hosted.Count) composed in " +
                "``$($Parent.Mount)``; " + 'a name marked `*` is one the ' +
                'parent does not compose.'
    }

    return @(Format-XmipMapLine -Text $said -Indent '') + ''
}


function New-XmipMapTechnology {
    <#
        .SYNOPSIS
            The technologies one repository hosts, several per line.

        .DESCRIPTION
            Nothing at all for a repository that hosts none, which is most of
            them. Otherwise a sentence saying how many are composed and one
            bullet per maturity, the names being the last segment of the
            repository name — `http` is `xmip-core-transport-http`.

        .PARAMETER Parent
            The hosting repository.

        .PARAMETER Repository
            Every declared repository.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $Parent,

        [Parameter(Mandatory = $true)]
        [PSCustomObject[]] $Repository
    )

    [PSCustomObject[]] $hosted = @(
        $Repository |
            Where-Object { $_.Parent -eq $Parent.Name } |
            Sort-Object -Property Leaf
    )

    if ($hosted.Count -eq 0) {
        return @()
    }

    [int] $mounted = @($hosted | Where-Object { $_.Mounted }).Count
    [string] $said = "$($hosted.Count) technologies"

    if ($hosted.Count -eq 1) {
        $said = 'one technology'
    }

    [string[]] $line = @(
        "### ``$($Parent.Name)``, $said"
        ''
    ) + (New-XmipMapTechnologyState -Parent $Parent -Hosted $hosted -Mounted $mounted)

    foreach ($word in ($hosted.Maturity | Sort-Object -Unique)) {
        [PSCustomObject[]] $group = @($hosted | Where-Object { $_.Maturity -eq $word })

        [string[]] $named = @(
            $group | ForEach-Object { Format-XmipMapName -Entry $_ -Mounted $mounted }
        )

        [string] $lead = "- **$word**, $($group.Count) — " + ($named -join ', ')

        $line += Format-XmipMapLine -Text $lead -Indent '  '
    }

    return ($line + '')
}


function New-XmipMapDomain {
    <#
        .SYNOPSIS
            One domain's section: its repositories, then what each hosts.

        .DESCRIPTION
            The table is the domain's own repositories. The blocks below it
            are the technologies each of them hosts, which is where the 290
            live — a technology is drawn under its parent and nowhere else,
            because that is where it is mounted.

        .PARAMETER Domain
            The domain to render.

        .PARAMETER Repository
            Every declared repository.

        .PARAMETER Description
            What the manifest's [classification] table says this domain is.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Domain,

        [Parameter(Mandatory = $true)]
        [PSCustomObject[]] $Repository,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Description
    )

    [PSCustomObject[]] $own = @($Repository | Where-Object { $_.Domain -eq $Domain })

    [string[]] $line = @(
        "## $Domain"
        ''
        $Description
        ''
        '| Repository | Maturity | Mount | Technologies |'
        '| --- | --- | --- | ---: |'
    )

    foreach ($entry in $own) {
        $line += New-XmipMapRow -Entry $entry -Repository $Repository
    }

    $line += ''

    foreach ($entry in $own) {
        $line += New-XmipMapTechnology -Parent $entry -Repository $Repository
    }

    return $line
}


function New-XmipMapRetired {
    <#
        .SYNOPSIS
            The repositories that were retired, with the date and the reason.

        .DESCRIPTION
            Here so that a reader who remembers a name and cannot find it on
            the map is told what happened to it rather than left looking. The
            reasons are long and are wrapped rather than put in a table, where
            a cell cannot break a line.

        .PARAMETER Retired
            The manifest's `[[retired]]` entries.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Retired
    )

    [string[]] $line = @(
        '## Retired'
        ''
        'Named here because a reader who remembers one of these and cannot find'
        'it above should be told what happened to it. The GitHub repository is'
        'archived rather than deleted in every case.'
        ''
    )

    foreach ($entry in $Retired) {
        [string] $name = [string](Get-TomlValue -Node $entry -Name 'name' -Default '')
        [string] $on = [string](Get-TomlValue -Node $entry -Name 'on' -Default '')
        [string] $why = [string](Get-TomlValue -Node $entry -Name 'reason' -Default '')

        $line += Format-XmipMapLine -Text "- **``$name``**, $on — $why" -Indent '  '
        $line += ''
    }

    return $line
}


function New-XmipMapPreamble {
    <#
        .SYNOPSIS
            The map's opening, down to the first count.

        .DESCRIPTION
            The part of the document that belongs to no repository, because it
            is about the collection. It lives in the generator for the same
            reason the domain order does.

        .PARAMETER Repository
            Every declared repository.

        .PARAMETER Extra
            Submodules mounted here that the estate tree does not declare.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]] $Repository,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $Extra
    )

    [int] $mounted = @($Repository | Where-Object { $_.Mounted }).Count

    [string[]] $line = @(
        '# The Xmip estate'
        ''
        "$($Repository.Count) repositories are declared and $mounted of them are"
        'mounted in this working tree.'
        ''
        '**Generated from `architecture.toml` and from the `.gitmodules` files'
        'of the estate, by `New-XmipEstateMap`.** ADR-0020 clause 5 rules that'
        'a document listing repositories is a second source of truth and will'
        'be wrong within a week; a view of the manifest is not a second source'
        'of it.'
        '`test/EstateMap.Test.ps1` regenerates this file and fails when the'
        'committed one differs. Edit the manifest and regenerate — an edit made'
        'here is lost.'
        ''
        '**Maturity is declared, not observed.** It is what the manifest says'
        'about a repository, never what the repository contains, and the two are'
        'known to disagree.'
        ''
        '[`repository-model.md`](repository-model.md) section 7 draws where the'
        'modules mount and says why. This is the whole estate, including every'
        'technology, and whether each one is composed here.'
        ''
    )

    if ($Extra.Count -gt 0) {
        [string] $said = 'Mounted here and not repositories of the estate: ' +
                         (($Extra | ForEach-Object { "``$_``" }) -join ', ') +
                         '. They are declared under `crate.template` rather' +
                         ' than in the estate tree, and are counted nowhere' +
                         ' below.'

        $line += @(Format-XmipMapLine -Text $said -Indent '') + ''
    }

    return ($line + @('---', ''))
}


function New-XmipMapComposition {
    <#
        .SYNOPSIS
            The paragraph that says what "mounted" means on this map.

        .DESCRIPTION
            Two levels, and a reader who does not know that reads a hundred
            technologies as missing. It is the one thing about the map that
            neither the manifest nor a count can state.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    return @(
        '**Mounted means composed as a submodule, and composition happens at two'
        'levels** (ADR-0016, amended 2026-09-07). The root `.gitmodules` composes'
        'the modules under `module/`, `test/` and `template/`. A technology is'
        'composed by its own parent capability, inside that repository, so the'
        'root cannot see it and this map reads each parent as well. A technology'
        'reported as not mounted is one its parent does not compose — not one'
        'the root forgot.'
        ''
    )
}


function Get-XmipMapDescription {
    <#
        .SYNOPSIS
            What the manifest's [classification] table says a domain is.

        .DESCRIPTION
            The table's keys are plural for two of the five, Capabilities
            and Operations, where the domain a repository declares is
            singular. Every spelling is tried rather than any of them being
            corrected, because the manifest is not this generator's to edit.
            An empty string when none is there.

        .PARAMETER Classification
            The manifest's `[classification]` table, or $null.

        .PARAMETER Domain
            The domain to describe.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        $Classification,

        [Parameter(Mandatory = $true)]
        [string] $Domain
    )

    if ($null -eq $Classification) {
        return ''
    }

    [string[]] $spelling = @(
        $Domain
        "${Domain}s"
        ($Domain -replace 'y$', 'ies')
    )

    foreach ($key in $spelling) {
        [string] $said = [string](Get-TomlValue -Node $Classification -Name $key -Default '')

        if (-not [string]::IsNullOrWhiteSpace($said)) {
            return $said
        }
    }

    return ''
}


function New-XmipMapText {
    <#
        .SYNOPSIS
            The whole map, as one string.

        .DESCRIPTION
            Split from `New-XmipEstateMap` so that the cmdlet is about what a
            caller asked for — report or write — and this is about what the
            document is.

        .PARAMETER Manifest
            The parsed manifest, for its classifications and its retirements.

        .PARAMETER Repository
            Every declared repository.

        .PARAMETER Extra
            Submodules mounted here that the estate tree does not declare.

        .PARAMETER Source
            Every source file, for the tree's counts.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        $Manifest,

        [Parameter(Mandatory = $true)]
        [PSCustomObject[]] $Repository,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $Extra,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [PSCustomObject[]] $Source
    )

    $classification = Get-TomlValue -Node $Manifest -Name 'classification' -Default $null

    [string[]] $line = @(New-XmipMapPreamble -Repository $Repository -Extra $Extra) + @(
        '## The count'
        ''
    ) + (New-XmipMapCount -Repository $Repository) + @('') +
        (New-XmipMapComposition) + @('---', '') +
        (New-XmipMapTree -Repository $Repository -Source $Source) + @('---', '')

    foreach ($name in $script:XmipMapDomain) {
        [hashtable] $section = @{
            Domain      = $name
            Repository  = $Repository
            Description = (Get-XmipMapDescription -Classification $classification -Domain $name)
        }

        $line += (New-XmipMapDomain @section) + @('---', '')
    }

    $line += New-XmipMapRetired -Retired @(
        Get-TomlValue -Node $Manifest -Name 'retired' -Default @()
    )

    return (($line -join "`n").TrimEnd() + "`n")
}


function New-XmipEstateMap {
    <#
        .SYNOPSIS
            Builds doc/architecture/estate-map.md from the manifest and the
            composed tree.

        .DESCRIPTION
            Returns the map as text. Reporting is the default and needs no
            ceremony to reach; `-Save` writes it to the map file, and
            `-WhatIf` says what it would write.

            Reading composition means reading the mounted modules, so a clone
            whose submodules are not initialized produces a map reporting every
            technology as uncomposed. That is true of that clone and false of
            the estate, which is why `test/EstateMap.Test.ps1` says to compose
            before reading its failure as a stale map.

        .PARAMETER Root
            The repository root. Defaults to the one this module was imported
            from.

        .PARAMETER Save
            Write the result to doc/architecture/estate-map.md.

        .EXAMPLE
            New-XmipEstateMap

        .EXAMPLE
            New-XmipEstateMap -Save
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [string] $Root,

        [Parameter(Mandatory = $false)]
        [switch] $Save
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if ([string]::IsNullOrWhiteSpace($Root)) {
        $Root = Get-XmipRepositoryRoot
    }

    $manifest = Get-XmipManifest -Path (Join-Path $Root 'architecture.toml')
    [PSCustomObject[]] $repository = @(Get-XmipEstateRepository -Root $Root)
    [hashtable] $composed = Get-XmipEstateComposition -Root $Root

    [string[]] $declared = @($repository | ForEach-Object { $_.Name })
    [string[]] $extra = @($composed.Keys | Where-Object { $_ -notin $declared } | Sort-Object)

    [PSCustomObject[]] $source = @(Get-XmipSourceFile -Root $Root)

    [hashtable] $whole = @{
        Manifest   = $manifest
        Repository = $repository
        Extra      = $extra
        Source     = $source
    }

    [string] $text = (New-XmipMapText @whole)

    if (-not $Save) {
        return $text
    }

    [string] $path = Join-Path $Root 'doc/architecture/estate-map.md'

    if ($PSCmdlet.ShouldProcess($path, 'Write the generated estate map')) {
        Set-Content -LiteralPath $path -Value $text -NoNewline -Encoding utf8

        [int] $mounted = @($repository | Where-Object { $_.Mounted }).Count

        Write-Host "OK       wrote $path, $($repository.Count) declared, $mounted mounted"
    }

    return $text
}
