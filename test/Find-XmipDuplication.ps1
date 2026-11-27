#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    What the estate says, codes or configures in more than one place: the
    finder test/Duplication.Test.ps1 reports from.

.DESCRIPTION
    test/Duplication.Test.ps1's header holds the rules: what each kind reads,
    what counts as the same and what is exempt. This file is their one
    implementation. Find-XmipDuplication returns one object per group, so the
    list can be sorted and grouped rather than read:

        . ./test/Find-XmipDuplication.ps1
        (Find-XmipDuplication -Root .).Group | Where-Object -Property Kind -EQ -Value Code

    Each tracked file is read once. A sentence, a window of code lines or a
    value line becomes one key, and only where a key was found is kept: a key
    two files share is a finding. The work is the regular expression
    engine's wherever it can be, over a whole file or a whole array at once;
    a PowerShell loop runs only where there is no other way, reads locals
    through operators and indexers, and writes into arrays made before it.
    Measured on 2026-11-27 over the estate's half a million Rust lines: a
    step of a PowerShell loop costs a microsecond or more, a script variable
    read in it doubles that, a method call such as List.Add costs twenty
    times an indexer, and eight runspaces side by side took as long as one
    doing all their work.

    Not a test file: Pester is told its extension, .Test.ps1, and this is not
    one.

    Style: doc/governance/powershell-style.md
#>

function New-XmipDuplicationPattern {
    <#
        .SYNOPSIS
        A pattern made once. As an operator's operand it runs faster than the
        same pattern as a string, which the operator looks up in PowerShell's
        cache at every use.
    #>
    [CmdletBinding()]
    [OutputType([regex])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Pattern
    )

    return [regex]::new($Pattern, [System.Text.RegularExpressions.RegexOptions]::Compiled)
}

# Below these a repeat is an idiom or a phrase rather than a copy: a sentence
# of this many words, a block of this many code lines.
[int] $script:XmipDuplicationWords = 12
[int] $script:XmipDuplicationLines = 6

# Written by a tool and kept by nobody: New-XmipEstateMap, New-XmipDecisionIndex,
# and process::generate for the two Work Processes built from a BPMN design.
[string[]] $script:XmipDuplicationGenerated = @(
    'doc/architecture/estate-map.md'
    'doc/decision/README.md'
    'module/platform/runtime/examples/approval_unit.rs'
    'test/core/system-test/examples/order_approval.rs'
)

# A run of spaces and tabs, and the space a line is left with at either end.
[hashtable] $script:XmipDuplicationSpace = @{
    Run  = New-XmipDuplicationPattern -Pattern '[ \t]+'
    Edge = New-XmipDuplicationPattern -Pattern '(?m)^ | $'
}

# Prose. A paragraph is a run of lines between a blank line, a fence, a help
# keyword, a heading, a list item or a table row, and a heading or a table row
# stands alone; Marker is a line's list or heading mark; Fence a fenced block,
# which Blank leaves only the line breaks of. Each paragraph is tagged with
# the line it starts on, and Spread carries the tag to every sentence in it,
# where a sentence ends at . ! or ? before a capital, a figure or a mark, and
# at every table cell. Enough is a sentence of enough words; Link, Mark and
# Edge what of it is not its words. Quoted is the owner's words, quoted across
# the records on purpose: an italic span in a paragraph that names him.
[hashtable] $script:XmipDuplicationProse = & {
    [string] $keyword = '\.(?:SYNOPSIS|DESCRIPTION|PARAMETER|EXAMPLE|INPUTS|OUTPUTS|NOTES|LINK)\b'
    [string] $ends = '(?:$|```|~~~|<!--|' + $keyword + ')'
    [string] $starts = '(?:#{1,6}[ \t]|[-*+][ \t]|\d+[.)][ \t]|\|)'
    [string] $enough = '(?:(?>\S+)\s+){' + ($script:XmipDuplicationWords - 1) + '}\S'
    [string] $owner = '(?i:\bthe owner\b)'

    return @{
        Paragraph = New-XmipDuplicationPattern -Pattern (
            '(?m)^[ \t]*(?:#{1,6}[ \t]|\|)[^\n]*|^(?![ \t]*' + $ends + ')[^\n]+' +
            '(?:\n(?![ \t]*(?:' + $ends + '|' + $starts + '))[^\n]+)*')
        Marker    = New-XmipDuplicationPattern -Pattern (
            '(?m)^[ \t]*(?:#{1,6}|[-*+]|\d+[.)]|>)[ \t]+')
        Fenced    = New-XmipDuplicationPattern -Pattern '```|~~~'
        Fence     = New-XmipDuplicationPattern -Pattern (
            '(?ms)^[ \t]*(```|~~~).*?(?:^[ \t]*\1[ \t]*$|\z)')
        Blank     = [System.Text.RegularExpressions.MatchEvaluator] {
            param([System.Text.RegularExpressions.Match] $Span)

            return $Span.Value -replace '[^\n]', ''
        }
        Quoted    = New-XmipDuplicationPattern -Pattern (
            '(?<![*\w])\*(?![\s*])[^*]+?(?<![\s*])\*(?![*\w])' +
            '(?:(?<=' + $owner + '[\s\S]*)|(?=[\s\S]*' + $owner + '))')
        Spread    = New-XmipDuplicationPattern -Pattern (
            '(?:(?<=[.!?])\s+(?=[A-Z0-9"''(\[*_`])|\s*\|\s*)(?<=^(?<tag>\d+)\t[\s\S]*)')
        Sentence  = [string] [char] 1
        Enough    = New-XmipDuplicationPattern -Pattern ('^\s*' + $enough)
        Long      = New-XmipDuplicationPattern -Pattern ('^\d+\t\s*' + $enough)
        Tag       = New-XmipDuplicationPattern -Pattern '^\d+\t'
        Untag     = New-XmipDuplicationPattern -Pattern '\t[\s\S]*$'
        Link      = New-XmipDuplicationPattern -Pattern '\[([^\]]*)\]\([^)]*\)'
        Mark      = New-XmipDuplicationPattern -Pattern '[\[\]*_`]'
        Edge      = New-XmipDuplicationPattern -Pattern '^[\s.,;:!?]+|[\s.,;:!?]+$'
        Space     = New-XmipDuplicationPattern -Pattern '\s+'
    }
}

# How a file is read, by its extension. Block is a comment over lines, which
# Inline turns into line comments, so a line is a comment or not by itself;
# Other matches a line that is no comment and Marker a comment's opening;
# Plain matches a code line that is no line of a block, and a file without
# Plain holds no code; Trail is a comment after code; Token finds a string
# literal long enough to hold a sentence, skipping whole every token before
# it; Setting marks a file of configuration.
[hashtable] $script:XmipDuplicationLanguage = & {
    [string] $short = '{0,' + ($script:XmipDuplicationWords * 3 - 1) + '}'
    [string] $long = '{' + ($script:XmipDuplicationWords * 3) + ',}'
    [string] $character = '''(?:\\.[^''\n]{0,9}|[^''\\\n])'''
    [string] $plain = '^(?:(?:pub(?:\([\w:]+\))? )?(?:use|mod|extern crate) |' +
        '(?:global )?using |@(?:using|inject|namespace|page) |namespace |' +
        '#(?:requires|region|endregion|nullable|pragma)\b)|^[^A-Za-z0-9]*$|' +
        '^#!?\[.*\]$|^\[[\w.]+(?:\(.*\))?\]$'
    [hashtable] $slash = @{
        Block  = New-XmipDuplicationPattern -Pattern '(?m)^[ \t]*/\*[\s\S]*?\*/'
        Inline = [System.Text.RegularExpressions.MatchEvaluator] {
            param([System.Text.RegularExpressions.Match] $Comment)

            return '//' + ($Comment.Value -replace '^[ \t]*/\*+|\*+/$', '' -replace '\n', "`n//")
        }
        Other  = New-XmipDuplicationPattern -Pattern '(?m)^(?![ \t]*//).*$'
        Marker = New-XmipDuplicationPattern -Pattern '(?m)^[ \t]*//[/!]?[ \t]?'
        Plain  = New-XmipDuplicationPattern -Pattern ($plain + '|^//')
        Trail  = New-XmipDuplicationPattern -Pattern ' //.*$'
    }
    [hashtable] $rust = $slash + @{
        Token = New-XmipDuplicationPattern -Pattern (
            '\G(?>"(?:[^"\\]|\\[\s\S])' + $short + '"|//[^\n]*|r(#*)"[\s\S]*?"\1|b?' +
            $character + '|[^"''/r]+|[''/r])*?(?<long>"(?:[^"\\]|\\[\s\S])' + $long + '")')
    }
    [hashtable] $csharp = $slash + @{
        Token = New-XmipDuplicationPattern -Pattern (
            '\G(?>@"(?:[^"]|"")' + $short + '"|"(?:[^"\\\n]|\\.)' + $short + '"|' +
            '//[^\n]*|' + $character + '|[^"''/@]+|[''/@])*?' +
            '(?<long>@"(?:[^"]|"")' + $long + '"|"(?:[^"\\\n]|\\.)' + $long + '")')
    }
    [hashtable] $shell = @{
        Block  = New-XmipDuplicationPattern -Pattern '(?m)^[ \t]*<#[\s\S]*?#>'
        Inline = [System.Text.RegularExpressions.MatchEvaluator] {
            param([System.Text.RegularExpressions.Match] $Comment)

            return '#' + ($Comment.Value -replace '^[ \t]*<#|#>$', '' -replace '\n', "`n#")
        }
        Other  = New-XmipDuplicationPattern -Pattern '(?m)^(?![ \t]*#(?!requires\b|!)).*$'
        Marker = New-XmipDuplicationPattern -Pattern '(?m)^[ \t]*#[ \t]?'
        Plain  = New-XmipDuplicationPattern -Pattern ($plain + '|^#')
        Token  = New-XmipDuplicationPattern -Pattern (
            '\G(?>''(?:[^'']|'''')' + $short + '''|"(?:[^"`]|`[\s\S]|"")' + $short +
            '"|@''\n[\s\S]*?\n''@|@"\n[\s\S]*?\n"@|#[^\n]*|[^''"#@]+|[#@])*?' +
            '(?<long>''(?:[^'']|'''')' + $long + '''|"(?:[^"`]|`[\s\S]|"")' + $long + '")')
    }
    [hashtable] $setting = @{
        Other   = New-XmipDuplicationPattern -Pattern '(?m)^(?![ \t]*#).*$'
        Marker  = New-XmipDuplicationPattern -Pattern '(?m)^[ \t]*#[ \t]?'
        Setting = $true
        Token   = New-XmipDuplicationPattern -Pattern (
            '\G(?>"""[\s\S]*?"""|''''''[\s\S]*?''''''|"(?:[^"\\\n]|\\.)' + $short +
            '"|''[^''\n]' + $short + '''|#[^\n]*|[^"''#]+|["''#])*?' +
            '(?<long>"(?:[^"\\\n]|\\.)' + $long + '"|''[^''\n]' + $long + ''')')
    }

    return @{
        '.md'    = @{}
        '.rs'    = $rust
        '.cs'    = $csharp
        '.razor' = $csharp
        '.ps1'   = $shell
        '.psm1'  = $shell
        '.toml'  = $setting
        '.xmip'  = $setting
        '.yml'   = $setting
        '.yaml'  = $setting
    }
}

# What makes a line configuration: a value, not a comment, a table header, a
# key that opens a block, a document marker or punctuation alone, and not a
# line deferring to the workspace, which names the one home rather than
# copying it.
[regex] $script:XmipDuplicationValue = New-XmipDuplicationPattern -Pattern (
    '^(?!#|\[\[?[^\]]*\]\]?$|-? ?[\w."-]+:$|---$|.*\bworkspace = true\b).*[A-Za-z0-9]')

function Get-XmipDuplicationSource {
    <#
        .SYNOPSIS
        Every file git tracks in the estate and its submodules that a kind
        reads, as a path from the root, but the generated.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root
    )

    [string[]] $read = @($script:XmipDuplicationLanguage.Keys)
    [string[]] $tracked = @(git -C $Root -c core.quotePath=off ls-files --recurse-submodules)

    return @(
        foreach ($path in $tracked) {
            if ($path -in $script:XmipDuplicationGenerated) {
                continue
            }

            if ([System.IO.Path]::GetExtension($path) -in $read) {
                $path
            }
        }
    )
}

function Read-XmipDuplicationParagraph {
    <#
        .SYNOPSIS
        One file's paragraphs of prose, each tagged with the line it starts
        on: its Markdown outside the fences, or the words of its comments.

        .DESCRIPTION
        The file's prose view keeps every line where it is: a line that is no
        comment is blank in it, and a comment line is its words.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Content,

        [Parameter(Mandatory = $true)]
        [hashtable] $Language
    )

    [hashtable] $prose = $script:XmipDuplicationProse
    [string] $view = $Content

    if ($Language.ContainsKey('Other')) {
        $view = $Content -replace $Language.Other, '' -replace $Language.Marker, ''
    }

    if ($view -match $prose.Fenced) {
        $view = $prose.Fence.Replace($view, $prose.Blank)
    }

    $paragraphs = $prose.Paragraph.Matches($view)
    [regex] $marker = $prose.Marker
    [string[]] $tagged = [string[]]::new($paragraphs.Count)
    [int] $count = 0
    [int] $number = 1
    [int] $last = 0

    foreach ($paragraph in $paragraphs) {
        [string] $before = $view.Substring($last, $paragraph.Index - $last)
        $number += ($before -split "`n", 0, 'SimpleMatch').Count - 1
        $last = $paragraph.Index
        $tagged[$count] = [string] $number + "`t" + ($paragraph.Value -replace $marker, '')
        $count++
    }

    # Whole, so an empty one arrives as an empty array rather than as nothing.
    return , $tagged
}

function Read-XmipDuplicationString {
    <#
        .SYNOPSIS
        One file's string literals long enough to hold a sentence, each a
        paragraph of its own tagged with the line it starts on: the messages
        a user reads.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Content,

        [Parameter(Mandatory = $true)]
        [regex] $Token
    )

    $literals = $Token.Matches($Content)
    [string[]] $tagged = [string[]]::new($literals.Count)
    [int] $count = 0
    [int] $line = 1
    [int] $last = 0

    foreach ($literal in $literals) {
        $found = $literal.Groups['long']
        [string] $before = $Content.Substring($last, $found.Index - $last)
        $line += ($before -split "`n", 0, 'SimpleMatch').Count - 1
        $last = $found.Index
        $tagged[$count] = [string] $line + "`t" + $found.Value
        $count++
    }

    [string[]] $text = $tagged -replace '\\\n\s*', '' -replace '\\[ntr]|`[ntr]', ' ' -replace
        '(?<=^\d+\t)@?["'']|["'']$', ''

    return , $text
}

function Read-XmipDuplicationSentence {
    <#
        .SYNOPSIS
        One file's sentences: its tagged paragraphs split where a sentence
        ends, the owner's quoted words taken out, and a sentence of enough
        words kept as its words alone, lower case, without emphasis, code
        marks, link targets or line breaks; with how it reads, and the line
        its paragraph starts on as its place.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $Tagged
    )

    [hashtable] $prose = $script:XmipDuplicationProse
    [string] $spread = $prose.Sentence + '${tag}' + "`t"
    [string[]] $long = @(
        $Tagged -replace $prose.Quoted, '' -replace $prose.Spread, $spread -split
            $prose.Sentence, 0, 'SimpleMatch'
    ) -match $prose.Long

    if ($long.Count -eq 0) {
        return @{ Key = @(); Start = @(); End = @(); Said = @() }
    }

    [regex] $enough = $prose.Enough
    [string[]] $sentence = $long -replace $prose.Tag, ''
    [string[]] $clean = @(
        $sentence -replace $prose.Link, '$1' -replace $prose.Mark, '' -replace $prose.Space,
            ' ' -replace $prose.Edge, ''
    ).ToLowerInvariant()
    [string[]] $said = $sentence -replace $prose.Space, ' ' -replace $prose.Edge, ''
    [int[]] $line = $long -replace $prose.Untag, ''
    [string[]] $key = [string[]]::new($long.Count)
    [int[]] $at = [int[]]::new($long.Count)
    [string[]] $as = [string[]]::new($long.Count)
    [int] $count = 0

    for ([int] $index = 0; $index -lt $long.Count; $index++) {
        if ($clean[$index] -match $enough) {
            $key[$count] = $clean[$index]
            $at[$count] = $line[$index]
            $as[$count] = $said[$index]
            $count++
        }
    }

    [int[]] $numbers = [System.ArraySegment[int]]::new($at, 0, $count).ToArray()

    return @{
        Key   = [System.ArraySegment[string]]::new($key, 0, $count).ToArray()
        Start = $numbers
        End   = $numbers
        Said  = [System.ArraySegment[string]]::new($as, 0, $count).ToArray()
    }
}

function ConvertTo-XmipDuplicationLine {
    <#
        .SYNOPSIS
        A file's lines, every run of spaces and tabs one space and none at
        either end.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Content
    )

    [hashtable] $space = $script:XmipDuplicationSpace

    return , ($Content -replace $space.Run, ' ' -replace $space.Edge, '').Split("`n")
}

function Read-XmipDuplicationSetting {
    <#
        .SYNOPSIS
        One file's value lines, whitespace normalized, each with its number.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]] $Line
    )

    [regex] $pattern = $script:XmipDuplicationValue
    [string[]] $key = [string[]]::new($Line.Count)
    [int[]] $at = [int[]]::new($Line.Count)
    [int] $count = 0

    for ([int] $index = 0; $index -lt $Line.Count; $index++) {
        if ($Line[$index] -match $pattern) {
            $key[$count] = $Line[$index]
            $at[$count] = $index + 1
            $count++
        }
    }

    [int[]] $numbers = [System.ArraySegment[int]]::new($at, 0, $count).ToArray()

    return @{
        Key   = [System.ArraySegment[string]]::new($key, 0, $count).ToArray()
        Start = $numbers
        End   = $numbers
    }
}

function Read-XmipDuplicationFile {
    <#
        .SYNOPSIS
        One file read under every kind that reads its extension: its
        sentences, its lines as code with the meaningful ones among them, and
        its value lines. Nothing for a file git lists and the working tree
        has deleted.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [int] $File
    )

    [string] $full = [System.IO.Path]::Combine($Root, $Path)

    if (-not [System.IO.File]::Exists($full)) {
        return
    }

    [hashtable] $language = $script:XmipDuplicationLanguage[[System.IO.Path]::GetExtension($Path)]
    [string] $content = [System.IO.File]::ReadAllText($full).Replace("`r`n", "`n")

    if ($language.ContainsKey('Block') -and $content -match $language.Block) {
        $content = $language.Block.Replace($content, $language.Inline)
    }

    [string[]] $tagged = Read-XmipDuplicationParagraph -Content $content -Language $language
    [hashtable] $read = @{ File = $File; Code = @(); Kept = @(); Setting = $null }

    if ($language.ContainsKey('Token')) {
        $tagged = $tagged + (Read-XmipDuplicationString -Content $content -Token $language.Token)
    }

    if ($language.ContainsKey('Plain') -or $language.ContainsKey('Setting')) {
        [string[]] $lines = ConvertTo-XmipDuplicationLine -Content $content

        if ($language.ContainsKey('Trail')) {
            $lines = $lines -replace $language.Trail, ''
        }

        if ($language.ContainsKey('Plain')) {
            $read.Code = $lines
            $read.Kept = [string[]] @($lines -notmatch $language.Plain)
        }
        else {
            $read.Setting = Read-XmipDuplicationSetting -Line $lines
        }
    }

    $read.Prose = Read-XmipDuplicationSentence -Tagged $tagged

    return $read
}

function Add-XmipDuplicationUnit {
    <#
        .SYNOPSIS
        Records where each key of one file was found: the first place of a
        key, or one more place of a key found before.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Found,

        [Parameter(Mandatory = $true)]
        [int] $File,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $Key,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [int[]] $Start,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [int[]] $End,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]] $Said = @()
    )

    $first = $Found.First
    $more = $Found.More
    $as = $Found.Said
    [string] $prefix = [string] $File + ' '

    for ([int] $index = 0; $index -lt $Key.Count; $index++) {
        [string] $one = $Key[$index]
        [string] $place = $prefix + $Start[$index] + ' ' + $End[$index]
        [string] $seen = $first[$one]

        if ($seen.Length -gt 0) {
            $more[$one] = $more[$one] + "`n" + $place
            continue
        }

        $first[$one] = $place

        if ($Said.Count -gt 0) {
            $as[$one] = $Said[$index]
        }
    }
}

function Get-XmipDuplicationKeptLine {
    <#
        .SYNOPSIS
        The number of each meaningful line in its file. A line equal to a
        meaningful one is meaningful too, so the first equal line after the
        last one found is the next one's.
    #>
    [CmdletBinding()]
    [OutputType([int[]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]] $Code,

        [Parameter(Mandatory = $true)]
        [string[]] $Kept
    )

    [int[]] $at = [int[]]::new($Kept.Count)
    [int] $next = 0

    for ([int] $index = 0; $index -lt $Code.Count -and $next -lt $Kept.Count; $index++) {
        if ($Code[$index] -ceq $Kept[$next]) {
            $at[$next] = $index + 1
            $next++
        }
    }

    return $at
}

function Add-XmipDuplicationWindow {
    <#
        .SYNOPSIS
        Records one file's windows of code, each from the meaningful line it
        starts on, with the lines it spans in the file.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Found,

        [Parameter(Mandatory = $true)]
        [hashtable] $Read,

        [Parameter(Mandatory = $true)]
        [int[]] $First,

        [Parameter(Mandatory = $true)]
        [int] $Count
    )

    [int] $size = $script:XmipDuplicationLines
    [string[]] $kept = $Read.Kept
    [int[]] $at = Get-XmipDuplicationKeptLine -Code $Read.Code -Kept $kept
    [string[]] $key = [string[]]::new($Count)
    [int[]] $from = [int[]]::new($Count)
    [int[]] $to = [int[]]::new($Count)
    [string[]] $said = [string[]]::new($Count)

    for ([int] $index = 0; $index -lt $Count; $index++) {
        [int] $begins = $First[$index]
        $key[$index] = [string]::Join("`n", $kept, $begins, $size)
        $from[$index] = $at[$begins]
        $to[$index] = $at[$begins + $size - 1]
        $said[$index] = $kept[$begins]
    }

    [hashtable] $unit = @{
        Found = $Found
        File  = $Read.File
        Key   = $key
        Start = $from
        End   = $to
        Said  = $said
    }

    Add-XmipDuplicationUnit @unit
}

function Add-XmipDuplicationCode {
    <#
        .SYNOPSIS
        Records the estate's code: every window of consecutive meaningful
        lines each of which another file has too, the only windows two files
        can share.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Found,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [hashtable[]] $Read
    )

    [int] $size = $script:XmipDuplicationLines
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    $again = [System.Collections.Generic.HashSet[string]]::new()
    $shared = [System.Collections.Generic.Dictionary[string, bool]]::new()

    foreach ($one in $Read) {
        if ($one.Kept.Count -ge $size) {
            $mine = [System.Collections.Generic.HashSet[string]]::new([string[]] $one.Kept)
            $both = [System.Collections.Generic.HashSet[string]]::new($mine)
            $both.IntersectWith($seen)
            $again.UnionWith($both)
            $seen.UnionWith($mine)
        }
    }

    foreach ($line in $again) {
        $shared[$line] = $true
    }

    foreach ($one in $Read) {
        [string[]] $kept = $one.Kept

        if ($kept.Count -lt $size) {
            continue
        }

        $mine = [System.Collections.Generic.HashSet[string]]::new($kept)
        $mine.IntersectWith($again)

        if ($mine.Count -eq 0) {
            continue
        }

        # Where each window whose every line another file has starts.
        [int[]] $first = [int[]]::new($kept.Count)
        [int] $count = 0
        [int] $run = 0

        for ([int] $index = 0; $index -lt $kept.Count; $index++) {
            $run = if ($shared[$kept[$index]]) { $run + 1 } else { 0 }

            if ($run -ge $size) {
                $first[$count] = $index - $size + 1
                $count++
            }
        }

        if ($count -gt 0) {
            Add-XmipDuplicationWindow -Found $Found -Read $one -First $first -Count $count
        }
    }
}

function Merge-XmipDuplicationPlace {
    <#
        .SYNOPSIS
        Places as path:line or path:first-last, in the order git lists the
        files, the spans in one file that touch or overlap taken as one.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Place,

        [Parameter(Mandatory = $true)]
        [string[]] $Path
    )

    [long] $scale = 1000000000
    [long[]] $order = [long[]]::new($Place.Count)
    [int[]] $last = [int[]]::new($Place.Count)

    for ([int] $index = 0; $index -lt $Place.Count; $index++) {
        [string[]] $part = $Place[$index] -split ' ', 0, 'SimpleMatch'
        $order[$index] = [long] $part[0] * $scale + [long] $part[1]
        $last[$index] = [int] $part[2]
    }

    [System.Array]::Sort($order, $last)
    $merged = [System.Collections.Generic.List[string]]::new()
    [long] $file = -1
    [long] $from = 0
    [long] $to = 0

    # One step past the last place, which ends the last span.
    for ([int] $index = 0; $index -le $order.Count; $index++) {
        [long] $here = -2
        [long] $begins = 0

        if ($index -lt $order.Count) {
            $begins = $order[$index] % $scale
            $here = ($order[$index] - $begins) / $scale
        }

        if ($here -eq $file -and $begins -le $to + 1) {
            $to = [System.Math]::Max($to, $last[$index])
            continue
        }

        if ($file -ge 0) {
            [string] $span = if ($to -gt $from) { "$from-$to" } else { "$from" }
            $merged.Add($Path[$file] + ':' + $span)
        }

        $file = $here
        $from = $begins

        if ($index -lt $order.Count) {
            $to = $last[$index]
        }
    }

    return $merged.ToArray()
}

function Group-XmipDuplication {
    <#
        .SYNOPSIS
        One kind's groups: its keys found in two files or more, those found in
        exactly the same files taken as one group, whose places are the spans
        they cover in each.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Found,

        [Parameter(Mandatory = $true)]
        [string] $Kind,

        [Parameter(Mandatory = $true)]
        [string[]] $Path
    )

    $bySet = [System.Collections.Generic.Dictionary[string, object]]::new()

    foreach ($one in $Found.More.Keys) {
        [string[]] $places = ($Found.First[$one] + $Found.More[$one]) -split "`n", 0, 'SimpleMatch'
        $distinct = [System.Collections.Generic.HashSet[string]]::new(
            [string[]] ($places -replace ' .*$', ''))

        if ($distinct.Count -lt 2) {
            continue
        }

        [string[]] $files = $distinct
        [System.Array]::Sort($files)
        [string] $signature = $files -join ','
        $keys = $bySet[$signature]

        if ($null -eq $keys) {
            $keys = [System.Collections.Generic.List[string]]::new()
            $bySet[$signature] = $keys
        }

        $keys.Add($one)
    }

    foreach ($signature in $bySet.Keys) {
        [string[]] $keys = $bySet[$signature].ToArray()
        [string[]] $places = foreach ($one in $keys) {
            ($Found.First[$one] + $Found.More[$one]) -split "`n", 0, 'SimpleMatch'
        }
        [string] $text = $Found.Said[$keys[0]]

        [pscustomobject] @{
            Kind   = $Kind
            Text   = if ($text.Length -gt 0) { $text } else { $keys[0] }
            Units  = $keys.Count
            Files  = ($signature -split ',').Count
            Places = Merge-XmipDuplicationPlace -Place $places -Path $Path
        }
    }
}

function Find-XmipDuplication {
    <#
        .SYNOPSIS
        Every group of prose, code and configuration the estate holds in two
        files or more, the group touching most places first; with the number
        of files read and the milliseconds reading and grouping took.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root
    )

    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    [string] $base = (Resolve-Path -LiteralPath $Root).ProviderPath
    [string[]] $path = Get-XmipDuplicationSource -Root $base
    [hashtable[]] $read = @(
        for ([int] $file = 0; $file -lt $path.Count; $file++) {
            Read-XmipDuplicationFile -Root $base -Path $path[$file] -File $file
        }
    )
    [hashtable] $found = @{}

    foreach ($kind in 'Prose', 'Code', 'Configuration') {
        $found[$kind] = @{
            First = [System.Collections.Generic.Dictionary[string, string]]::new()
            More  = [System.Collections.Generic.Dictionary[string, string]]::new()
            Said  = [System.Collections.Generic.Dictionary[string, string]]::new()
        }
    }

    foreach ($one in $read) {
        [hashtable] $prose = $one.Prose
        Add-XmipDuplicationUnit -Found $found.Prose -File $one.File @prose

        if ($null -ne $one.Setting) {
            [hashtable] $setting = $one.Setting
            Add-XmipDuplicationUnit -Found $found.Configuration -File $one.File @setting
        }
    }

    Add-XmipDuplicationCode -Found $found.Code -Read $read
    [object[]] $group = @(
        foreach ($kind in 'Prose', 'Code', 'Configuration') {
            Group-XmipDuplication -Found $found[$kind] -Kind $kind -Path $path
        }
    )
    [hashtable] $most = @{ Expression = { $_.Places.Count }; Descending = $true }
    [hashtable] $widest = @{ Expression = { $_.Units }; Descending = $true }

    return [pscustomobject] @{
        Read         = $read.Count
        Group        = @($group | Sort-Object -Property $most, $widest)
        Milliseconds = $watch.ElapsedMilliseconds
    }
}
