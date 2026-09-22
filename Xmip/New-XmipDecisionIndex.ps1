#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    Generates doc/decision/README.md from the decision records.

.DESCRIPTION
    The index used to be written by hand, and it admitted so in a closing
    section: every summary in it was a copy of a record, which ADR-0020 forbids,
    in the document that indexes ADR-0020. Markdown has no transclusion, so the
    copies could not be turned into views. They can be turned into output.

    Each record declares what the index needs, in an `## In brief` section:

        - Theme      which of the six groups it reads under
        - Subject    the heading it appears under, a sentence
        - Name       its short name, used in the link and the citation table
        - Order      where it reads within its theme
        - Concepts   the words the concept index should point here
        - Note       anything the status cannot imply

    followed by the summary prose. The record is the source and this is a view
    of it. `test/Decision.Test.ps1` regenerates and fails when the committed
    index differs, so the copy cannot drift the way the handwritten one did.

    Three counts disagreed on 2026-09-03 — the index said twenty-three, the test
    said twenty-two, and there were twenty-five — and two records had no entry at
    all. All four numbers came from the same cause.

    Style: doc/governance/powershell-style.md
#>

# The six themes, in reading order. This is the index's own shape rather than
# any record's, which is why it lives here and not in a record. A record naming
# a theme that is not one of these fails Decision.Test.ps1.
[string[]] $script:XmipDecisionTheme = @(
    'What Xmip is at runtime'
    'Identity and security'
    'Modules and the boundary'
    'The shape of the estate'
    'Operating Xmip'
    'How the work is done'
)

# The fields an `## In brief` block may declare. Theme, Subject, Name and Order
# are required; a record missing one cannot be placed.
[string[]] $script:XmipBriefField = @(
    'Theme'
    'Subject'
    'Name'
    'Order'
    'Concepts'
    'Note'
)

function ConvertTo-XmipNumberWord {
    <#
        .SYNOPSIS
            A number under one hundred, spelled.

        .DESCRIPTION
            The index opens by saying how many decisions it holds, and the
            estate spells small numbers in prose. Returns the digits unchanged
            for anything this does not cover, which is better than refusing to
            generate a document over a word.

        .PARAMETER Number
            The number to spell.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [int] $Number
    )

    [string[]] $unit = @(
        'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight',
        'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen',
        'sixteen', 'seventeen', 'eighteen', 'nineteen'
    )

    [string[]] $ten = @(
        '', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy',
        'eighty', 'ninety'
    )

    if ($Number -lt 0 -or $Number -ge 100) {
        return [string] $Number
    }

    if ($Number -lt 20) {
        return $unit[$Number]
    }

    [string] $tens = $ten[[math]::Floor($Number / 10)]

    if (($Number % 10) -eq 0) {
        return $tens
    }

    return "$tens-$($unit[$Number % 10])"
}


function New-XmipIndexPreamble {
    <#
        .SYNOPSIS
            The index's opening, down to the first theme.

        .DESCRIPTION
            The one part of this document that belongs to no record, because it
            is about the collection rather than about any decision in it. It
            lives in the generator for the same reason the theme list does.

        .PARAMETER Count
            How many records there are. Spelled, and therefore right.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [int] $Count
    )

    [string] $word = (ConvertTo-XmipNumberWord -Number $Count)
    [string] $spelled = $word.Substring(0, 1).ToUpperInvariant() + $word.Substring(1)

    return @(
        '# What Xmip has decided'
        ''
        "$spelled decisions, read as one document."
        ''
        '**Generated from the records by `New-XmipDecisionIndex`.** Every summary'
        'below is the `## In brief` section of the record it links to, so the two'
        'cannot disagree. Edit a record and regenerate; an edit made here is lost.'
        '`test/Decision.Test.ps1` regenerates and fails when this file differs.'
        ''
        'Every decision has a number. The number is an identifier for machines, for'
        'citations in code comments, and for filenames — it is not how anyone'
        'understands anything, so it does not appear in this document until the last'
        'section, which exists only to turn a citation back into a subject.'
        ''
        'Read this front to back to know what Xmip has decided. Use the'
        '[concept index](#concept-index) when you have a word and want the decision'
        'that governs it.'
        ''
        'Each entry states the decision, not the reasoning behind it — the reasoning'
        'is in the record, one link away.'
        ''
        '**Where the rest lives.** These are decisions. The five architecture'
        'documents in [`../architecture/`](../architecture) describe the system as it'
        'currently stands, and [`../terminology.md`](../terminology.md) defines every'
        'Xmip word. A decision says *what was chosen and why*; an architecture'
        'document says *what is true now*.'
        ''
        '---'
        ''
    )
}


function New-XmipIndexClosing {
    <#
        .SYNOPSIS
            The concept index and the citation table.

        .DESCRIPTION
            Both are views of the records. The paragraph between them is not: it
            names concepts that no record governs, which is the one thing no
            record can declare about itself.

        .PARAMETER Record
            Every record.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]] $Record
    )

    return @(
        '## Concept index'
        ''
        'You have a word. This gives you the decision that governs it.'
        ''
    ) + (New-XmipIndexConcept -Record $Record) + @(
        ''
        'Concepts with **no decision recorded yet**, and where they live instead:'
        'Event and Schedule'
        '([`runtime-model.md`](../architecture/runtime-model.md) section 17),'
        'delivery semantics'
        '([`runtime-model.md`](../architecture/runtime-model.md) section 15), and the'
        'node configuration format'
        '([`open-problems.md`](../planning/open-problems.md) problem 14).'
        ''
        'The Xmip URI left this list on 2026-09-03: ADR-0027 clause 3 makes it the'
        'addressing form of the operator boundary, which is the record it never had.'
        ''
        '---'
        ''
        '## Resolving a citation'
        ''
        'Code comments, commit messages and the records themselves cite each other by'
        'number. This turns one back into a subject. It is the only place in this'
        'document where a number is the thing you look at, and it is here so that it'
        'is nowhere else.'
        ''
    ) + (New-XmipIndexCitation -Record $Record)
}


function New-XmipDecisionIndex {
    <#
        .SYNOPSIS
            Builds doc/decision/README.md from the records.

        .DESCRIPTION
            Returns the index as text. Reporting is the default and needs no
            ceremony to reach; `-Save` writes it to the index file, and
            `-WhatIf` says what it would write.

        .PARAMETER DecisionRoot
            The folder holding the records. Defaults to the one in the
            repository this module was imported from.

        .PARAMETER Save
            Write the result to README.md in that folder.

        .EXAMPLE
            New-XmipDecisionIndex

        .EXAMPLE
            New-XmipDecisionIndex -Save
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [string] $DecisionRoot,

        [Parameter(Mandatory = $false)]
        [switch] $Save
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    if ([string]::IsNullOrWhiteSpace($DecisionRoot)) {
        $DecisionRoot = Join-Path (Get-XmipRepositoryRoot) 'doc/decision'
    }

    [PSCustomObject[]] $record = @(Get-XmipDecisionRecord -DecisionRoot $DecisionRoot)
    [string[]] $line = @(New-XmipIndexPreamble -Count $record.Count)

    for ([int] $i = 0; $i -lt $script:XmipDecisionTheme.Count; $i++) {
        [string] $theme = $script:XmipDecisionTheme[$i]

        [PSCustomObject[]] $inTheme = @(
            $record | Where-Object { $_.Theme -eq $theme } | Sort-Object -Property Order
        )

        $line += @("## $($i + 1). $theme", '')

        foreach ($entry in $inTheme) {
            $line += New-XmipIndexEntry -Record $entry -All $record
        }

        $line += @('---', '')
    }

    $line += New-XmipIndexClosing -Record $record

    [string] $text = ($line -join "`n").TrimEnd() + "`n"

    if (-not $Save) {
        return $text
    }

    [string] $path = Join-Path $DecisionRoot 'README.md'

    if ($PSCmdlet.ShouldProcess($path, 'Write the generated decision index')) {
        Set-Content -LiteralPath $path -Value $text -NoNewline -Encoding utf8
        Write-Host "OK       wrote $path, $($record.Count) records"
    }

    return $text
}
