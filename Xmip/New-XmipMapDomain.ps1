#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    The estate map's counts and its per-domain sections, with the technologies each hosts.

.DESCRIPTION
    Apart from New-XmipEstateMap.ps1 since 2026-09-22, when that file was 795 lines against the
    400 the estate allows a file and the owner asked for the estate to be
    consolidated. One subject per file.

    Style: doc/governance/powershell-style.md
#>


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
