#requires -PSEdition Core
#requires -Version 7.6

<#
    docs/governance/powershell-style.md states the rules. This file is what
    makes them rules rather than preferences.

    Everything here is measured with the PowerShell parser or with PowerShell's
    own file objects — never by counting characters in text. That matters:
    Get-XmipStyleFinding returns findings you can pipe, group and sort when a
    test fails, instead of a wall of output you have to read.

        Get-XmipStyleFinding | Group-Object Rule
        Get-XmipStyleFinding | Where-Object Rule -eq 'LineLength' | Format-Table

    Scope is the module and these tests. scripts/, tools/ and install/ are
    superseded and awaiting deletion; they are deliberately not measured,
    because a rule that fails on code nobody maintains gets switched off.
#>

# Declared at file scope, not in BeforeAll: Pester discovers test names before
# it runs BeforeAll, and a name that interpolates a variable set in BeforeAll
# reads as 'at or under  characters' in the output.
[int] $script:MaximumLineLength = 120
[int] $script:MaximumFunctionLines = 35

BeforeAll {
    $script:Root = Join-Path $PSScriptRoot '..'
    [int] $script:MaximumLineLength = 120
    [int] $script:MaximumFunctionLines = 35

    # Named once: both the file walk and the nesting calculation ask the same
    # question of the AST, and a predicate defined twice drifts.
    [scriptblock] $script:IsFunctionAst = {
        param($node)
        return $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
    }

    <#
        .SYNOPSIS
        Every style violation in the measured files, as objects.

        .DESCRIPTION
        Returns one object per finding with Rule, Path, Line, Value and
        Detail. Returns nothing when the tree is clean, so an empty result is
        the pass condition.
    #>
    function Get-XmipStyleFinding {
        [CmdletBinding()]
        [OutputType([pscustomobject])]
        param(
            [Parameter(Mandatory = $false)]
            [string] $At = $script:Root
        )

        foreach ($file in (Get-MeasuredFile -At $At)) {
            Measure-Line -File $file
            Measure-FunctionLength -File $file
        }
    }

    <#
        .SYNOPSIS
        The files the style rules apply to.

        .DESCRIPTION
        The module and these tests. scripts/, tools/ and install/ are omitted
        on purpose: they are superseded and awaiting deletion.
    #>
    function Get-MeasuredFile {
        [CmdletBinding()]
        [OutputType([System.IO.FileInfo])]
        param(
            [Parameter(Mandatory = $true)]
            [string] $At
        )

        [string] $module = Join-Path $At 'Xmip'
        [string] $tests = Join-Path $At 'tests'

        return @(
            Get-ChildItem -Path $module -File -Include '*.ps1', '*.psm1' -Recurse
            Get-ChildItem -Path $tests -File -Filter '*.ps1' -Recurse
        )
    }

    <#
        .SYNOPSIS
        Line-level findings: length, and backtick continuation.
    #>
    function Measure-Line {
        [CmdletBinding()]
        [OutputType([pscustomobject])]
        param(
            [Parameter(Mandatory = $true)]
            [System.IO.FileInfo] $File
        )

        [string[]] $lines = @(Get-Content -LiteralPath $File.FullName)

        for ([int] $index = 0; $index -lt $lines.Count; $index++) {
            [string] $line = $lines[$index]

            [hashtable] $where = @{
                File   = $File
                Line   = $index + 1
                Detail = $line.Trim()
            }

            if ($line.Length -gt $script:MaximumLineLength) {
                New-Finding @where -Rule 'LineLength' -Value $line.Length
            }

            if ($line -match '`\s*$') {
                New-Finding @where -Rule 'BacktickContinuation' -Value 1
            }
        }
    }

    function New-Finding {
        [CmdletBinding()]
        [OutputType([pscustomobject])]
        param(
            [Parameter(Mandatory = $true)]
            [string] $Rule,

            [Parameter(Mandatory = $true)]
            [System.IO.FileInfo] $File,

            [Parameter(Mandatory = $true)]
            [int] $Line,

            [Parameter(Mandatory = $true)]
            [int] $Value,

            [Parameter(Mandatory = $true)]
            [AllowEmptyString()]
            [string] $Detail
        )

        return [pscustomobject]@{
            Rule   = $Rule
            Path   = $File.Name
            Line   = $Line
            Value  = $Value
            Detail = $Detail
        }
    }

    <#
        .SYNOPSIS
        A finding for the first parse error in a file.
    #>
    function New-ParseFinding {
        [CmdletBinding()]
        [OutputType([pscustomobject])]
        param(
            [Parameter(Mandatory = $true)]
            [System.IO.FileInfo] $File,

            [Parameter(Mandatory = $true)]
            [System.Management.Automation.Language.ParseError[]] $Errors
        )

        [hashtable] $finding = @{
            Rule   = 'ParseError'
            File   = $File
            Line   = $Errors[0].Extent.StartLineNumber
            Value  = $Errors.Count
            Detail = $Errors[0].Message
        }

        return New-Finding @finding
    }

    <#
        .SYNOPSIS
        The parsed AST of a file. Parse errors are returned through $Errors.
    #>
    function Get-ParsedFile {
        [CmdletBinding()]
        [OutputType([System.Management.Automation.Language.ScriptBlockAst])]
        param(
            [Parameter(Mandatory = $true)]
            [System.IO.FileInfo] $File,

            [Parameter(Mandatory = $true)]
            [ref] $Errors
        )

        [System.Management.Automation.Language.Token[]] $tokens = @()

        return [System.Management.Automation.Language.Parser]::ParseFile(
            $File.FullName, [ref] $tokens, $Errors
        )
    }

    <#
        .SYNOPSIS
        Function bodies longer than the declared maximum, found by the parser.

        .DESCRIPTION
        Uses the PowerShell AST rather than brace counting, so a brace inside a
        string or a comment cannot skew the result. Nested functions are
        measured on their own, and a parent that only contains them is not
        blamed for their length.
    #>
    function Measure-FunctionLength {
        [CmdletBinding()]
        [OutputType([pscustomobject])]
        param(
            [Parameter(Mandatory = $true)]
            [System.IO.FileInfo] $File
        )

        [System.Management.Automation.Language.ParseError[]] $errors = @()
        $ast = Get-ParsedFile -File $File -Errors ([ref] $errors)

        if (0 -ne $errors.Count) {
            New-ParseFinding -File $File -Errors $errors
            return
        }

        foreach ($function in $ast.FindAll($script:IsFunctionAst, $true)) {
            [int] $own = Measure-OwnLine -Function $function

            if ($own -le $script:MaximumFunctionLines) {
                continue
            }

            [hashtable] $lengthFinding = @{
                Rule   = 'FunctionLength'
                File   = $File
                Line   = $function.Extent.StartLineNumber
                Value  = $own
                Detail = $function.Name
            }

            New-Finding @lengthFinding
        }
    }

    <#
        .SYNOPSIS
        The nearest function that encloses a node, or $null at file level.
    #>
    function Get-EnclosingFunction {
        [CmdletBinding()]
        [OutputType([System.Management.Automation.Language.FunctionDefinitionAst])]
        param(
            [Parameter(Mandatory = $true)]
            [System.Management.Automation.Language.Ast] $Node
        )

        $current = $Node.Parent

        while ($null -ne $current) {
            if ($current -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
                return $current
            }

            $current = $current.Parent
        }

        return $null
    }

    <#
        .SYNOPSIS
        How many lines an AST node spans, inclusive of both ends.
    #>
    function Measure-Extent {
        [CmdletBinding()]
        [OutputType([int])]
        param(
            [Parameter(Mandatory = $true)]
            [System.Management.Automation.Language.Ast] $Ast
        )

        return $Ast.Extent.EndLineNumber - $Ast.Extent.StartLineNumber + 1
    }

    <#
        .SYNOPSIS
        A function's own line count, excluding functions nested inside it.

        .DESCRIPTION
        Sync-XmipRepository is 450 lines of which most are its nested helpers.
        Charging the parent for its children would report one enormous number
        and hide which helper is actually too long.
    #>
    function Measure-OwnLine {
        [CmdletBinding()]
        [OutputType([int])]
        param(
            [Parameter(Mandatory = $true)]
            [System.Management.Automation.Language.FunctionDefinitionAst] $Function
        )

        [int] $total = Measure-Extent -Ast $Function
        [int] $nested = 0

        # The declaration is not the function. powershell-style.md section 2
        # requires one parameter per line, a blank line between, a type on each
        # and [Parameter()] on its own line — four lines per parameter before
        # any code exists. Counting that against a 35-line limit meant the two
        # rules fought, and the param() rule always won.
        if ($null -ne $Function.Body.ParamBlock) {
            $total -= Measure-Extent -Ast $Function.Body.ParamBlock
        }

        foreach ($child in $Function.FindAll($script:IsFunctionAst, $true)) {
            # Only direct children. Walking the parent chain to the first
            # enclosing function is exact; a fixed number of .Parent hops is a
            # guess about how the parser nests blocks. A grandchild is already
            # inside its own parent's extent, so subtracting both double-counts.
            if ($child -eq $Function -or (Get-EnclosingFunction -Node $child) -ne $Function) {
                continue
            }

            $nested += Measure-Extent -Ast $child
        }

        return [Math]::Max(0, $total - $nested)
    }
}

Describe 'PowerShell style, section 1: layout' {
    It "keeps every line at or under $script:MaximumLineLength characters" {
        [object[]] $long = @(Get-XmipStyleFinding | Where-Object { $_.Rule -eq 'LineLength' })
        [string] $detail = ($long | ForEach-Object { "$($_.Path):$($_.Line) is $($_.Value)" }) -join "`n"

        $long.Count | Should -Be 0 -Because "these lines are too long:`n$detail"
    }
}

Describe 'PowerShell style, section 3: calls' {
    It 'uses no backtick line continuation' {
        # Invisible, and one trailing space after it silently breaks the
        # statement. A splat, a pipeline or parentheses instead.
        [object[]] $ticks = @(
            Get-XmipStyleFinding | Where-Object { $_.Rule -eq 'BacktickContinuation' }
        )

        [string] $detail = ($ticks | ForEach-Object { "$($_.Path):$($_.Line)" }) -join ', '

        $ticks.Count | Should -Be 0 -Because "backtick continuation at: $detail"
    }
}

Describe 'PowerShell style, section 2: functions' {
    BeforeAll {
        <#
            The debt, measured rather than guessed.

            The first version of this list named four functions on the
            assumption that the long cmdlet bodies were the whole problem. The
            AST found twenty-one, because 'function' and 'cmdlet' are not the
            same thing and most of these are helpers that grew quietly.

            Every number here is what the function measured on 2026-08-26, so
            each is a ratchet from today: it may fall, it may not rise, and a
            new function over thirty-five lines fails immediately because it is
            not on this list.

            **A number may be raised for exactly two reasons, in the same
            change, with the reason stated here.**

            One: the function gained functionality. A ratchet that forbids
            growth forever forbids adding features, and the point is that
            growth is deliberate and visible rather than silent.

            Two: a nested helper was extracted from it. Splitting one costs the
            parent the blank line that separates it, so extracting a helper
            makes the parent measure one line longer. Refusing that would make
            this list punish the exact refactor the limit exists to encourage.

            Re-baselining because a test is inconvenient is the failure this
            list exists to prevent, and it is only distinguishable from the two
            above by the reason being written down.

            Roughly in the order they are worth splitting:

              Sync-XmipRepository       318   seven operations in one body
              Install-XmipPrerequisite  250   one branch per package manager
              Invoke-CreateRepositories 108   creation, verification, reporting
              Sync-XmipEstate            97   dispatch that grew arms
              Invoke-Distribute          92   plan, move, stage, commit
              Install-XmipModule         85   probe, link, verify

            The rest are between 36 and 73 and mostly want one helper each.
        #>
        # Re-baselined 2026-08-26 to measured body lines, after Measure-OwnLine
        # stopped counting the param() block. Every previous number was loose by
        # the size of its own declaration. Six functions left the list entirely
        # once their signatures stopped counting against them.
        #
        # Sync-XmipEstate is the one genuine growth: 97 to 101, for -Compose and
        # for the drift report learning that a reserved repository which does
        # not exist is not drift.
        $script:Waived = @{
            'Assert-XmipManifestVersion'   = 44
            'Assert-XmipRepositoryEntry'   = 49
            'Expand-XmipEstate'            = 48
            'Expand-XmipManifestFromTree'  = 48
            'Get-RepositoryStatus'         = 42
            'Install-XmipModule'           = 80
            'Install-XmipPrerequisite'     = 237
            'Invoke-ConfigureRepositories' = 56
            'Invoke-CreateRepositories'    = 104
            'Invoke-Distribute'            = 87
            'New-XmipGitHubRepository'     = 67
            'Resolve-XmipNodeFacts'        = 55
            # 101 to 102: Get-RepositoryPage extracted from
            # Get-ActualRepositories, which costs the parent the blank line
            # between the two nested functions.
            'Sync-XmipEstate'              = 102
            'Sync-XmipRepository'          = 270
            'Test-XmipManifest'            = 53
        }
    }

    It 'parses every measured file' {
        [object[]] $broken = @(Get-XmipStyleFinding | Where-Object { $_.Rule -eq 'ParseError' })
        [string] $detail = ($broken | ForEach-Object { "$($_.Path): $($_.Detail)" }) -join "`n"

        $broken.Count | Should -Be 0 -Because $detail
    }

    It "keeps every unwaived function at or under $script:MaximumFunctionLines lines" {
        [object[]] $long = @(
            Get-XmipStyleFinding |
                Where-Object { $_.Rule -eq 'FunctionLength' } |
                Where-Object { -not $script:Waived.ContainsKey($_.Detail) }
        )

        [string] $detail = ($long | ForEach-Object { "$($_.Detail) is $($_.Value)" }) -join "`n"

        $long.Count | Should -Be 0 -Because "half a page, about 35 lines:`n$detail"
    }

    It 'holds every waived function at or below the length it was waived at' {
        # A ratchet, not an exemption. The waiver records what the function was
        # when the rule arrived; it may shrink, and this fails if it grows.
        [hashtable] $actual = @{}

        Get-XmipStyleFinding |
            Where-Object { $_.Rule -eq 'FunctionLength' } |
            ForEach-Object { $actual[$_.Detail] = $_.Value }

        foreach ($name in ($actual.Keys | Sort-Object)) {
            Write-Host ('  measured {0,-28} {1,4} lines' -f $name, $actual[$name])
        }

        foreach ($name in $script:Waived.Keys) {
            if (-not $actual.ContainsKey($name)) {
                continue
            }

            [int] $ceiling = $script:Waived[$name]
            [string] $because = "$name was waived at $ceiling lines and may not grow"

            $actual[$name] | Should -BeLessOrEqual $ceiling -Because $because
        }
    }
}

Describe 'The style document describes what is enforced' {
    It 'names this file as the thing that enforces it' {
        [string] $path = Join-Path $script:Root 'docs/governance/powershell-style.md'
        [string] $style = Get-Content -LiteralPath $path -Raw

        # The failure that prompted this test: section 6 named a file that did
        # not exist, in a document about not letting rules decay.
        $style | Should -Match 'Xmip\.Style\.Tests\.ps1'
    }

    It 'states the same line length this file enforces' {
        [string] $path = Join-Path $script:Root 'docs/governance/powershell-style.md'
        [string] $style = Get-Content -LiteralPath $path -Raw

        $style | Should -Match ([string] $script:MaximumLineLength)
    }
}
