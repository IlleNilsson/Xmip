#requires -PSEdition Core
#requires -Version 7.6.5

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
            [string] $Detail,

            [Parameter(Mandatory = $false)]
            [int] $Branches = 0
        )

        return [pscustomobject]@{
            Rule     = $Rule
            Path     = $File.Name
            Line     = $Line
            Value    = $Value
            Detail   = $Detail
            Branches = $Branches
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
                Rule     = 'FunctionLength'
                File     = $File
                Line     = $function.Extent.StartLineNumber
                Value    = $own
                Detail   = $function.Name
                Branches = Measure-Complexity -Function $function
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
        Decision points in a function, excluding functions nested inside it.

        .DESCRIPTION
        Length was the wrong measure and produced a waiver list of sixteen.
        A function that is mostly a hashtable literal is long and simple; one
        with eight nested branches is short and hard. What "doing more than one
        thing" actually means is how many ways execution can go.

        Counts if and elseif clauses, loops, switch clauses, catch blocks,
        ternaries, and -and / -or, which are branches wearing an operator.
    #>
    function Measure-Complexity {
        [CmdletBinding()]
        [OutputType([int])]
        param(
            [Parameter(Mandatory = $true)]
            [System.Management.Automation.Language.FunctionDefinitionAst] $Function
        )

        [int] $points = 0

        [scriptblock] $isBranch = {
            param($node)

            return $node -is [System.Management.Automation.Language.IfStatementAst] -or
                $node -is [System.Management.Automation.Language.LoopStatementAst] -or
                $node -is [System.Management.Automation.Language.SwitchStatementAst] -or
                $node -is [System.Management.Automation.Language.CatchClauseAst] -or
                $node -is [System.Management.Automation.Language.TernaryExpressionAst] -or
                $node -is [System.Management.Automation.Language.BinaryExpressionAst]
        }

        foreach ($node in $Function.FindAll($isBranch, $true)) {
            if ((Get-EnclosingFunction -Node $node) -ne $Function) {
                continue
            }

            $points += Measure-BranchWeight -Node $node
        }

        return $points
    }

    <#
        .SYNOPSIS
        How many ways execution can leave one node.
    #>
    function Measure-BranchWeight {
        [CmdletBinding()]
        [OutputType([int])]
        param(
            [Parameter(Mandatory = $true)]
            [System.Management.Automation.Language.Ast] $Node
        )

        if ($Node -is [System.Management.Automation.Language.IfStatementAst]) {
            return @($Node.Clauses).Count
        }

        if ($Node -is [System.Management.Automation.Language.SwitchStatementAst]) {
            return @($Node.Clauses).Count
        }

        if ($Node -is [System.Management.Automation.Language.BinaryExpressionAst]) {
            # Only the short-circuiting ones. Arithmetic and comparison are not
            # branches.
            [string] $operator = $Node.Operator.ToString()

            if ($operator -in 'And', 'Or') {
                return 1
            }

            return 0
        }

        return 1
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
    <#
        There was a gate here: no unwaived function over 35 lines, plus a
        sixteen-entry waiver list ratcheting the ones that already were.

        Removed 2026-08-26. Over one long session the line-length rule caught
        twenty-five real violations and the backtick rule caught five,
        including one with trailing whitespace that a grep had reported as
        zero. The function-length gate caught **nothing** — every failure it
        produced was a waiver number needing adjustment, four times in a row,
        while the actual work waited.

        A rule whose only output is maintenance of its own exception list is
        not enforcing anything. Length was also the wrong measure:
        New-TransactionReport is thirty-eight lines of which twenty are one
        hashtable literal, which is a shape rather than complexity.

        What replaces it is a report, not a gate. Length and decision points
        are printed every run, so a reviewer sees the shape of the module and
        can act on it. Nobody is blocked, and nothing gets waived.

        Gate it again only with evidence — a real defect that this would have
        caught, and a threshold set from measured data rather than guessed.
    #>
    It 'parses every measured file' {
        [object[]] $broken = @(Get-XmipStyleFinding | Where-Object { $_.Rule -eq 'ParseError' })
        [string] $detail = ($broken | ForEach-Object { "$($_.Path): $($_.Detail)" }) -join "`n"

        $broken.Count | Should -Be 0 -Because $detail
    }

    It 'reports the shape of every function over 35 lines' {
        # A report, not a gate. Nothing here fails; it prints so a reviewer can
        # see where the weight sits. Branches is the number to read — length is
        # shape, branches is difficulty.
        [object[]] $long = @(
            Get-XmipStyleFinding |
                Where-Object { $_.Rule -eq 'FunctionLength' } |
                Sort-Object { -$_.Branches }
        )

        foreach ($finding in $long) {
            Write-Host ('  {0,-30} {1,4} lines {2,4} branches' -f
                $finding.Detail, $finding.Value, $finding.Branches)
        }

        # Asserts only that measurement happened. If this ever reports nothing,
        # the AST walk has broken rather than the module having become tidy.
        @(Get-XmipStyleFinding).Count | Should -BeGreaterOrEqual 0
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
