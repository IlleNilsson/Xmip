#requires -PSEdition Core
#requires -Version 7.6.5

<#
    docs/decisions/README.md reads every decision record as one
    document, grouped by subject, because nobody remembers what a number means.

    An index nobody maintains is worse than no index: it is believed. These
    tests fail when an ADR exists that the index does not mention, when the
    index links to something that does not exist, or when a status in the index
    disagrees with the status in the record itself.
#>

# How many decision records state their provenance. A floor, not a target: it
# may rise and may not fall. At file scope because Pester discovers test names
# before it runs BeforeAll.
[int] $script:ProvenanceFloor = 1

BeforeAll {
    [int] $script:ProvenanceFloor = 1
    $script:Root = Join-Path $PSScriptRoot '..'
    $script:DecisionRoot = Join-Path $script:Root 'docs/decisions'
    $script:IndexPath = Join-Path $script:DecisionRoot 'README.md'
    $script:Index = Get-Content -LiteralPath $script:IndexPath -Raw

    [System.IO.FileInfo[]] $script:Records = @(
        Get-ChildItem -Path $script:DecisionRoot -File -Filter 'ADR-*.md' |
            Sort-Object Name
    )

    <#
        .SYNOPSIS
        The status an ADR declares about itself.

        .DESCRIPTION
        Two formats are in use: a '- Status: Accepted' line in the header block,
        and a '## Status' section with the word on a following line. Returns the
        first word found, or '' when neither shape matches.
    #>
    function Get-DecisionStatus {
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [Parameter(Mandatory = $true)]
            [System.IO.FileInfo] $Record
        )

        [string] $text = Get-Content -LiteralPath $Record.FullName -Raw

        if ($text -match '(?m)^-\s*Status:\s*(\w+)') {
            return $Matches[1]
        }

        if ($text -match '(?ms)^##\s*Status\s*$.*?(\w+)') {
            return $Matches[1]
        }

        return ''
    }

    <#
        .SYNOPSIS
        Whether any term in a concept label appears in the given text.

        .DESCRIPTION
        A label may hold several ways of saying one thing, comma separated, and
        any one of them counts. Backticks are stripped and a trailing plural
        's' is tried as well.

        Terms shorter than three characters are ignored, because 'a' and 'of'
        match everything. Three is the floor rather than four: DMQ, ABI, CLI,
        SSH, MSI, OCI and GUI are all real concepts, and the first run of this
        test reported DMQ missing from a record that names it twice.
    #>
    function Test-ConceptPresent {
        [CmdletBinding()]
        [OutputType([bool])]
        param(
            [Parameter(Mandatory = $true)]
            [string] $Concept,

            [Parameter(Mandatory = $true)]
            [AllowEmptyString()]
            [string] $Corpus
        )

        foreach ($part in ($Concept -split ',')) {
            [string] $term = $part.Replace('`', '').Trim()

            if ($term.Length -lt 3) {
                continue
            }

            if ($Corpus -like "*$term*") {
                return $true
            }

            if ($term.EndsWith('s') -and $Corpus -like "*$($term.TrimEnd('s'))*") {
                return $true
            }
        }

        return $false
    }

    <#
        .SYNOPSIS
        The row for one ADR in the index's 'By number' table, or '' if absent.
    #>
    function Get-IndexRow {
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [Parameter(Mandatory = $true)]
            [string] $Number
        )

        [string] $pattern = '(?m)^\|\s*\[' + [regex]::Escape($Number) + '\].*$'

        if ($script:Index -match $pattern) {
            return $Matches[0]
        }

        return ''
    }
}

Describe 'The index covers every decision' {
    It 'mentions every ADR file that exists' {
        [string[]] $unmentioned = @()

        foreach ($record in $script:Records) {
            if (-not $script:Index.Contains($record.Name)) {
                $unmentioned += $record.Name
            }
        }

        [string] $detail = $unmentioned -join "`n"

        $unmentioned.Count | Should -Be 0 -Because "not in the index:`n$detail"
    }

    It 'gives every ADR a row in the by-number table' {
        foreach ($record in $script:Records) {
            [string] $number = $record.BaseName.Substring(4, 4)
            [string] $because = "ADR-$number has no row in the by-number table"

            Get-IndexRow -Number $number | Should -Not -BeNullOrEmpty -Because $because
        }
    }

    It 'has at least twenty decisions to index' {
        # A guard against the glob silently matching nothing and every test
        # above passing over an empty set.
        $script:Records.Count | Should -BeGreaterThan 19
    }
}

Describe 'The index links nowhere that does not exist' {
    It 'resolves every relative link' {
        [string[]] $links = @(
            [regex]::Matches($script:Index, '\]\(([^)#:]+)\)') |
                ForEach-Object { $_.Groups[1].Value } |
                Where-Object { -not $_.StartsWith('http') } |
                Select-Object -Unique
        )

        $links.Count | Should -BeGreaterThan 20

        foreach ($link in $links) {
            [string] $path = Join-Path $script:DecisionRoot $link

            Test-Path -LiteralPath $path |
                Should -BeTrue -Because "the index links to $link"
        }
    }
}

Describe 'The concept index still matches the records' {
    It 'finds every indexed concept in the record it points at' {
        <#
            The summaries in the index are hand-written, and markdown has no
            transclusion — CommonMark leaves it to third parties and GitHub
            implements none of it — so there is no way to make the index a view
            over the records rather than a copy of them.

            This is the check that is possible instead. The concept index
            already declares which words each record governs, so those words
            must appear in it. It cannot tell whether a summary is still
            accurate; it catches the likelier failure, which is a term being
            renamed or removed while the index goes on claiming it.

            At least one term per row must match, because a row like
            'Claim, claimable artefact' is one idea written several ways.
        #>
        [string[]] $stale = @()

        [regex] $row = [regex]::new('(?m)^\|\s*([^|]+?)\s*\|\s*(\[[^|]+)\|')

        foreach ($match in $row.Matches($script:Index)) {
            [string] $concept = $match.Groups[1].Value
            [string] $targets = $match.Groups[2].Value

            # Skip the header and separator rows, and the citation table, whose
            # first column is a link rather than a concept.
            if ($concept -match '^(Concept|-+|\s*)$' -or $concept.StartsWith('[')) {
                continue
            }

            [string[]] $files = @(
                [regex]::Matches($targets, '\(([^)]+\.md)\)') |
                    ForEach-Object { $_.Groups[1].Value }
            )

            if (0 -eq $files.Count) {
                continue
            }

            [string] $corpus = ''

            foreach ($file in $files) {
                [string] $path = Join-Path $script:DecisionRoot $file

                if (Test-Path -LiteralPath $path) {
                    $corpus += Get-Content -LiteralPath $path -Raw
                }
            }

            if (Test-ConceptPresent -Concept $concept -Corpus $corpus) {
                continue
            }

            $stale += "$concept -> $($files -join ', ')"
        }

        [string] $detail = $stale -join "`n"

        $stale.Count | Should -Be 0 -Because "the index claims these and the records do not say them:`n$detail"
    }
}

Describe 'Decisions say where they came from' {
    It "carries a Provenance section on at least $script:ProvenanceFloor records" {
        <#
            An inverse ratchet: this number may rise and may not fall.

            Generated text has no tell. It is fluent and authoritative whether
            it transcribes a ruling or fills a gap, so a reader cannot recover
            the difference from the prose — and that is how four documents each
            called a version of the specification turned out to be four
            different documents.

            A Provenance section names which clauses are the owner's. It is
            what makes the rest of a record safe to consolidate, because a
            later reader knows which lines may not be quietly rewritten to
            resolve a conflict.

            One record has one today. governance/architectural-change-permission.md
            says every record should. Raise the floor as they are written.
        #>
        [string[]] $with = @()

        foreach ($record in $script:Records) {
            [string] $text = Get-Content -LiteralPath $record.FullName -Raw

            if ($text -match '(?m)^##\s*Provenance\s*$') {
                $with += $record.Name
            }
        }

        Write-Host "  $($with.Count) of $($script:Records.Count) records state their provenance"

        $with.Count | Should -BeGreaterOrEqual $script:ProvenanceFloor
    }
}

Describe 'The index agrees with the records about status' {
    It 'marks as Proposed exactly what calls itself Proposed' {
        # The one that drifts: an ADR is accepted, its status line is updated,
        # and the index still shows it as open. Or the reverse, which is worse.
        foreach ($record in $script:Records) {
            [string] $number = $record.BaseName.Substring(4, 4)
            [string] $status = Get-DecisionStatus -Record $record
            [string] $row = Get-IndexRow -Number $number

            if ([string]::IsNullOrWhiteSpace($row)) {
                continue
            }

            [bool] $recordSaysProposed = $status -eq 'Proposed'
            [bool] $indexSaysProposed = $row -match 'Proposed'

            [string] $because = "ADR-$number says '$status'; the index row says: $row"

            $indexSaysProposed | Should -Be $recordSaysProposed -Because $because
        }
    }

    It 'marks as superseded exactly what calls itself superseded' {
        foreach ($record in $script:Records) {
            [string] $number = $record.BaseName.Substring(4, 4)
            [string] $status = Get-DecisionStatus -Record $record
            [string] $row = Get-IndexRow -Number $number

            if ([string]::IsNullOrWhiteSpace($row)) {
                continue
            }

            [bool] $recordSaysSuperseded = $status -eq 'Superseded'
            [bool] $indexSaysSuperseded = $row -match 'superseded'

            [string] $because = "ADR-$number says '$status'; the index row says: $row"

            $indexSaysSuperseded | Should -Be $recordSaysSuperseded -Because $because
        }
    }
}

Describe 'The index is generated, not written' {
    BeforeAll {
        Import-Module (Join-Path $script:Root 'Xmip/Xmip.psd1') -Force

        [PSCustomObject[]] $script:Declared = @(
            Get-XmipDecisionRecord -DecisionRoot $script:DecisionRoot
        )

        [string[]] $script:Theme = @(
            'What Xmip is at runtime'
            'Identity and security'
            'Modules and the boundary'
            'The shape of the estate'
            'Operating Xmip'
            'How the work is done'
        )
    }

    It 'matches what New-XmipDecisionIndex produces' {
        # The whole point of the generator. A hand edit to README.md fails
        # here, which is the only way to stop the copies drifting again —
        # the previous index carried a section admitting they had.
        [string] $generated = New-XmipDecisionIndex -DecisionRoot $script:DecisionRoot
        [string] $committed = Get-Content -LiteralPath $script:IndexPath -Raw

        [string] $because = 'run: New-XmipDecisionIndex -Save'

        $generated | Should -Be $committed -Because $because
    }

    It 'reads a complete In brief from every record' {
        foreach ($entry in $script:Declared) {
            [string] $because = "ADR-$($entry.Number) is missing part of its In brief"

            [string]::IsNullOrWhiteSpace($entry.Theme) | Should -BeFalse -Because $because
            [string]::IsNullOrWhiteSpace($entry.Subject) | Should -BeFalse -Because $because
            [string]::IsNullOrWhiteSpace($entry.Name) | Should -BeFalse -Because $because
            $entry.Order | Should -BeGreaterThan 0 -Because $because
            [string]::IsNullOrWhiteSpace($entry.Prose) | Should -BeFalse -Because $because
        }
    }

    It 'places every record in one of the six themes' {
        # A theme the generator does not know is a record that renders
        # nowhere, and a silently absent entry is what this file exists to
        # prevent.
        foreach ($entry in $script:Declared) {
            [string] $because = "ADR-$($entry.Number) declares theme '$($entry.Theme)'"

            $script:Theme | Should -Contain $entry.Theme -Because $because
        }
    }

    It 'gives each record its own place in its theme' {
        foreach ($name in $script:Theme) {
            [PSCustomObject[]] $inTheme = @(
                $script:Declared | Where-Object { $_.Theme -eq $name }
            )

            [int[]] $order = @($inTheme | ForEach-Object { $_.Order })
            [int] $distinct = @($order | Sort-Object -Unique).Count

            [string] $because = "'$name' has $($order.Count) records at $distinct positions"

            $distinct | Should -Be $order.Count -Because $because
        }
    }
}
