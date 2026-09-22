#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    The estate map's opening, its note on composition, and its list of the retired.

.DESCRIPTION
    Apart from New-XmipEstateMap.ps1 since 2026-09-22, when that file was 795 lines against the
    400 the estate allows a file and the owner asked for the estate to be
    consolidated. One subject per file.

    Style: doc/governance/powershell-style.md
#>


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
        'it above should be told what happened to it. Each says whether its'
        'GitHub repository was kept or deleted.'
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
