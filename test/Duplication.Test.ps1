#requires -PSEdition Core
#requires -Version 7.7.0

<#
    One subject, one place. CONTRIBUTING.md says code is placed once and
    everything else uses it, and ADR-0020 clause 1 that a subject has exactly
    one document, but nothing looked at text, configuration or code for
    copies until the owner, 2026-11-27: *Being a digital transformation
    person, I really do not like the same information, instructions,
    configuration and code in multiple places.*

    What is read is every file git tracks in the estate and its submodules
    (git ls-files --recurse-submodules), each once, by the one finder,
    test/Find-XmipDuplication.ps1, as three kinds:

    - Prose: a sentence of twelve words or more that two files or more hold,
      compared as its words alone: lower case, without Markdown emphasis, code
      marks, link targets and line breaks. Read in Markdown outside its
      fences; in the comments, doc comments and comment-based help of Rust,
      C#, PowerShell, TOML, YAML and .xmip; and in string literals long enough
      to hold one, the messages a user reads. A sentence's place is the line
      its paragraph starts on.
    - Code: six meaningful lines in a row that two files or more hold, in
      Rust, C# (.cs, .razor) and PowerShell (.ps1, .psm1), spaces normalized.
      A meaningful line holds a letter or a figure and is no comment, import
      (use, using, mod, extern crate), #requires or attribute alone.
    - Configuration: a value line that two files or more hold, in TOML, YAML
      and .xmip: key = value, key: value, a list item, a command. Not a
      comment, a table header, a key that opens a block, or a line deferring
      to the workspace (workspace = true), which names the one home rather
      than copying it.

    What files share is grouped by the files: the units found in exactly the
    same files are one group, whose places are the spans they cover in each.
    The group touching most places comes first.

    Exempt, and nothing else:
    - the owner's quoted words: an italic span in a paragraph that names the
      owner, as the records quote him on purpose;
    - what a tool writes: doc/architecture/estate-map.md (New-XmipEstateMap),
      doc/decision/README.md (New-XmipDecisionIndex), and the two Work
      Processes process::generate builds from a BPMN design,
      module/platform/runtime/examples/approval_unit.rs and
      test/core/system-test/examples/order_approval.rs;
    - license texts (LICENSE, NOTICE), lock files (packages.lock.json,
      package-lock.json) and the database scripts xmip-core-persist writes
      (deploy/database), none of which has an extension the finder reads.

    It fails nothing yet: it says what it found, the groups and places of each
    kind and every place, and passes. A kind is gated once its list is
    cleared: add 'Prose', 'Code' or 'Configuration' to $script:Gated in
    BeforeAll, and from then on any group of that kind fails the test.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')
    . (Join-Path $PSScriptRoot 'Find-XmipDuplication.ps1')

    # The kinds whose list is cleared, which fail on any group from then on.
    # None yet: the owner asked for the list first (2026-11-27).
    [string[]] $script:Gated = @()

    $script:Found = Find-XmipDuplication -Root $script:Root

    function Write-XmipDuplicationReport {
        <#
            .SYNOPSIS
            One kind's groups in words: how many, over how many places, and
            each group's places with what it repeats.
        #>
        [CmdletBinding()]
        [OutputType([void])]
        param(
            [Parameter(Mandatory = $true)]
            [string] $Kind,

            [Parameter(Mandatory = $true)]
            [AllowEmptyCollection()]
            [object[]] $Group
        )

        [int] $places = ($Group | ForEach-Object { $_.Places.Count } | Measure-Object -Sum).Sum
        Write-Host ("  {0}: {1} groups over {2} places" -f $Kind, $Group.Count, $places)

        foreach ($one in $Group) {
            [string] $text = $one.Text

            if ($text.Length -gt 90) {
                $text = $text.Substring(0, 90) + '...'
            }

            Write-Host ("    {0} places, {1} units in {2} files: {3}" -f $one.Places.Count,
                $one.Units, $one.Files, $text)
            Write-Host ('      ' + ($one.Places -join ', '))
        }
    }
}

Describe 'Duplication: one subject, one place' {
    It 'reads the estate, and every file it exempts as generated is there' {
        Write-Host ("  Read {0} files in {1} ms." -f $script:Found.Read, $script:Found.Milliseconds)

        [string[]] $missing = @(
            $script:XmipDuplicationGenerated |
                Where-Object { -not (Test-Path -LiteralPath (Join-Path $script:Root $_)) }
        )

        $script:Found.Read | Should -BeGreaterThan 1000 -Because 'the estate tracks thousands'
        $missing | Should -BeNullOrEmpty -Because 'an exemption names a file that is there'
    }

    It 'finds each kind, and nothing the owner said, in files made to repeat' {
        # The instrument held to a small estate of its own: a sentence, a
        # block of code and a value line in two files, and one sentence they
        # share only inside the owner's quoted words.
        [string] $estate = Join-Path $TestDrive 'estate'
        New-Item -ItemType Directory -Path $estate | Out-Null
        [string] $said = 'A sentence long enough to count says one thing in two places at once.'
        [string] $quoted = 'The owner, 2026-11-27: *Every word of this quote stays where he said ' +
            'it, in each record.*'
        [string[]] $code = @(
            'fn twice(value: u32) -> u32 {', '    let doubled = value * 2;',
            '    let checked = doubled.max(1);', '    let kept = checked.min(100);',
            '    let shown = kept + 0;', '    let done = shown;', '    done', '}'
        )

        foreach ($name in 'one', 'two') {
            Set-Content -LiteralPath (Join-Path $estate "$name.md") -Value @($said, '', $quoted)
            Set-Content -LiteralPath (Join-Path $estate "$name.rs") -Value $code
            Set-Content -LiteralPath (Join-Path $estate "$name.toml") -Value 'timeout = 30'
        }

        git -C $estate init --quiet
        git -C $estate add --all
        $found = Find-XmipDuplication -Root $estate

        @($found.Group | ForEach-Object { $_.Kind } | Sort-Object) |
            Should -Be @('Code', 'Configuration', 'Prose')
        ($found.Group | Where-Object -Property Kind -EQ -Value 'Prose').Text |
            Should -Be $said.TrimEnd('.')
    }

    It 'reports repeated <Kind>' -ForEach @(
        @{ Kind = 'Prose' }
        @{ Kind = 'Code' }
        @{ Kind = 'Configuration' }
    ) {
        [object[]] $group = @(
            $script:Found.Group | Where-Object -Property Kind -EQ -Value $Kind
        )
        Write-XmipDuplicationReport -Kind $Kind -Group $group

        if ($Kind -in $script:Gated) {
            $group.Count | Should -Be 0 -Because "$Kind is gated: each group has one home"
        }
    }
}
