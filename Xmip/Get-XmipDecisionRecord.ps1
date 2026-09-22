#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    Reading the decision records: status, brief, and what supersedes what.

.DESCRIPTION
    Apart from New-XmipDecisionIndex.ps1 since 2026-09-22, when that file was 618 lines against the
    400 the estate allows a file and the owner asked for the estate to be
    consolidated. One subject per file.

    Style: doc/governance/powershell-style.md
#>


function Get-XmipDecisionStatus {
    <#
        .SYNOPSIS
            The status an ADR declares about itself.

        .DESCRIPTION
            Two shapes are in use and both are read: a `- Status: Accepted` line
            in the header block, which the records from ADR-0016 onward use, and
            a `## Status` section with the sentence below it, which the earlier
            ones use. Returns the sentence with its trailing stop removed, or an
            empty string when neither shape matches.

        .PARAMETER Text
            The whole record.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Text
    )

    [string] $status = ''

    if ($Text -match '(?m)^-\s*Status:\s*(.+?)\s*$') {
        $status = $Matches[1]
    }
    elseif ($Text -match '(?ms)^##\s*Status\s*$\s*(.+?)\s*$') {
        $status = $Matches[1]
    }

    return $status.TrimEnd('.')
}


function Get-XmipDecisionBrief {
    <#
        .SYNOPSIS
            The declared fields and the summary prose of one record.

        .DESCRIPTION
            Returns a hashtable of the `## In brief` fields plus a `Prose` key
            holding everything between the last field and the next `##` heading.
            Returns $null when the record has no `## In brief` section, which is
            the one thing a caller must handle.

        .PARAMETER Text
            The whole record.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Text
    )

    if ($Text -notmatch '(?ms)^## In brief\s*$(.+?)(?=^## )') {
        return $null
    }

    [string[]] $line = $Matches[1] -split '\r?\n'
    [hashtable] $brief = @{ Prose = '' }
    [string[]] $prose = @()

    foreach ($entry in $line) {
        if ($entry -match '^-\s*(\w+):\s*(.+?)\s*$' -and
            $Matches[1] -in $script:XmipBriefField) {
            $brief[$Matches[1]] = $Matches[2]
            continue
        }

        $prose += $entry
    }

    $brief.Prose = ($prose -join "`n").Trim()

    return $brief
}


function Get-XmipDecisionRecord {
    <#
        .SYNOPSIS
            Every decision record, with what it declares about itself.

        .DESCRIPTION
            One object per `ADR-*.md`, ordered by number. Objects out rather
            than text, so `Get-XmipDecisionRecord | Where-Object Status -like
            'Superseded*'` answers a question without parsing anything.

            A record with no `## In brief` section comes back with $null in
            every declared field. That is a finding for the test rather than an
            error here: refusing to read the estate because one record is
            incomplete tells the caller less than showing which one is.

        .PARAMETER DecisionRoot
            The folder holding the records. Defaults to the one beside this
            module.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.DecisionRecord')]
    param(
        [Parameter(Mandatory = $false)]
        [string] $DecisionRoot
    )

    if ([string]::IsNullOrWhiteSpace($DecisionRoot)) {
        $DecisionRoot = Join-Path (Get-XmipRepositoryRoot) 'doc/decision'
    }

    [System.IO.FileInfo[]] $file = @(
        Get-ChildItem -Path $DecisionRoot -File -Filter 'ADR-*.md' |
            Sort-Object -Property Name
    )

    foreach ($record in $file) {
        [string] $text = Get-Content -LiteralPath $record.FullName -Raw
        [hashtable] $brief = Get-XmipDecisionBrief -Text $text

        if ($null -eq $brief) {
            $brief = @{ Prose = '' }
        }

        [string[]] $concept = @()

        if ($brief.ContainsKey('Concepts')) {
            $concept = @($brief.Concepts -split ';\s*' | Where-Object { $_ })
        }

        [PSCustomObject] @{
            PSTypeName = 'Xmip.DecisionRecord'
            Number     = ($record.BaseName -replace '^ADR-(\d{4}).*$', '$1')
            File       = $record.Name
            Title      = ((Get-Content -LiteralPath $record.FullName -TotalCount 1) -replace
                          '^#\s*ADR-\d{4}:\s*', '')
            Status     = Get-XmipDecisionStatus -Text $text
            Theme      = $brief['Theme']
            Subject    = $brief['Subject']
            Name       = $brief['Name']
            Order      = [int] ($brief['Order'] ?? 0)
            Concepts   = $concept
            Note       = $brief['Note']
            Prose      = $brief.Prose
        }
    }
}


function Get-XmipSupersedingRecord {
    <#
        .SYNOPSIS
            The record that superseded this one, or $null.

        .DESCRIPTION
            Read out of the status rather than declared twice. A status of
            'Superseded by ADR-0024' names its successor, and the successor's
            filename is what a link needs.

        .PARAMETER Record
            The record to look at.

        .PARAMETER All
            Every record, so the successor's filename can be found.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $Record,

        [Parameter(Mandatory = $true)]
        [PSCustomObject[]] $All
    )

    if ($Record.Status -notmatch 'Superseded by ADR-(\d{4})') {
        return $null
    }

    [string] $number = $Matches[1]

    return ($All | Where-Object { $_.Number -eq $number } | Select-Object -First 1)
}
