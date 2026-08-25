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
            [hashtable] $parseFinding = @{
                Rule   = 'ParseError'
                File   = $File
                Line   = $errors[0].Extent.StartLineNumber
                Value  = $errors.Count
                Detail = $errors[0].Message
            }

            New-Finding @parseFinding
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

        [int] $total = $Function.Extent.EndLineNumber - $Function.Extent.StartLineNumber + 1
        [int] $nested = 0

        foreach ($child in $Function.FindAll($script:IsFunctionAst, $true)) {
            if ($child -eq $Function) {
                continue
            }

            # Only direct children. Walking the parent chain to the first
            # enclosing function is exact; a fixed number of .Parent hops is a
            # guess about how the parser nests blocks and breaks when it is
            # wrong. A grandchild is already inside its own parent's extent,
            # and subtracting both would count it twice.
            if ((Get-EnclosingFunction -Node $child) -ne $Function) {
                continue
            }

            $nested += $child.Extent.EndLineNumber - $child.Extent.StartLineNumber + 1
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
        # The debt, named. These four predate the style document and each is a
        # cmdlet body that should become named steps.
        #
        # The ceilings are deliberately loose on this first pass, because they
        # were written without running the measurement, and a waiver guessed
        # too low fails the build for being right. The test prints what it
        # measured; tighten each number to the measured value once seen. From
        # then on it is a ratchet: a number may fall, never rise.
        $script:Waived = @{
            'Install-XmipPrerequisite' = 400
            'Sync-XmipEstate'          = 500
            'Sync-XmipRepository'      = 500
            'Invoke-Distribute'        = 300
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
