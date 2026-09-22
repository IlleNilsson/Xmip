#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    One record's line in the decision index, its concepts and its citations.

.DESCRIPTION
    Apart from New-XmipDecisionIndex.ps1 since 2026-09-22, when that file was 618 lines against the
    400 the estate allows a file and the owner asked for the estate to be
    consolidated. One subject per file.

    Style: doc/governance/powershell-style.md
#>


function New-XmipIndexEntry {
    <#
        .SYNOPSIS
            One record's section of the index.

        .DESCRIPTION
            The heading, the summary prose the record declares, and the link
            back to it. A Proposed or superseded record says so on the link,
            derived from its status so the two cannot disagree.

        .PARAMETER Record
            The record to render.

        .PARAMETER All
            Every record, for resolving a superseding link.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $Record,

        [Parameter(Mandatory = $true)]
        [PSCustomObject[]] $All
    )

    [string] $note = ''
    [PSCustomObject] $superseding = Get-XmipSupersedingRecord -Record $Record -All $All

    if ($Record.Status -match '^Proposed') {
        $note = ' — **still Proposed**'
    }
    elseif ($null -ne $superseding) {
        [string] $target = "[ADR-$($superseding.Number)]($($superseding.File))"
        $note = " — **superseded by $target**"
    }

    return @(
        "### $($Record.Subject)"
        ''
        $Record.Prose
        ''
        "→ [$($Record.Name), in full]($($Record.File))$note"
        ''
    )
}


function New-XmipIndexConcept {
    <#
        .SYNOPSIS
            The concept index table.

        .DESCRIPTION
            One row per concept, alphabetical, naming every record that claims
            it. A concept marked `(retired)` by a record renders as retired,
            because a word that no longer means anything still has to be
            findable by whoever reads it in an old comment.

        .PARAMETER Record
            Every record.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]] $Record
    )

    $claim = [ordered] @{ }

    foreach ($entry in $Record) {
        foreach ($word in $entry.Concepts) {
            [bool] $retired = $word -match '\s*\(retired\)$'
            [string] $key = ($word -replace '\s*\(retired\)$', '')
            [string] $link = "[$($entry.Name)]($($entry.File))"

            if ($retired) {
                $link = "retired — $link"
            }

            if (-not $claim.Contains($key)) {
                $claim[$key] = @()
            }

            $claim[$key] += $link
        }
    }

    [string[]] $row = @('| Concept | Decided by |', '| --- | --- |')

    foreach ($key in ($claim.Keys | Sort-Object)) {
        $row += "| $key | $($claim[$key] -join ', ') |"
    }

    return $row
}


function New-XmipIndexCitation {
    <#
        .SYNOPSIS
            The table that turns a number back into a subject.

        .DESCRIPTION
            The only place in the index where a number is the thing you look at,
            which is why it is the only place a number appears. The note column
            is the record's status where the status says something, plus
            whatever the record declares that a status cannot imply.

        .PARAMETER Record
            Every record.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]] $Record
    )

    [string[]] $row = @('| | Subject | |', '| --- | --- | --- |')

    foreach ($entry in $Record) {
        [string[]] $note = @()

        if ($entry.Status -match '^Proposed') {
            $note += '**Proposed**'
        }

        if ($entry.Status -match 'Superseded by ADR-(\d{4})') {
            $note += "superseded by $($Matches[1])"
        }

        if (-not [string]::IsNullOrWhiteSpace($entry.Note)) {
            $note += $entry.Note
        }

        [string] $link = "[$($entry.Number)]($($entry.File))"
        [string] $said = ($note -join '; ')

        if ([string]::IsNullOrWhiteSpace($said)) {
            $row += "| $link | $($entry.Name) | |"
            continue
        }

        $row += "| $link | $($entry.Name) | $said |"
    }

    return $row
}
