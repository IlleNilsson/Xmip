#requires -PSEdition Core
#requires -Version 7.6.7

<#
    The estate's two length rules, held for C# as Rust.Style.Test.ps1 holds
    them for Rust and Xmip.Style.Test.ps1 for PowerShell: a file is at most 400
    lines, a line at most 100 columns (CONTRIBUTING, *Read before writing*).
    C# had no gate until 2026-10-13, and eight files over 400 and fifty-four
    lines over 100 were found then. The owner, the same day: *I have clearly
    stated we do not want wide or long files! Make the small, usefull and
    includable!*

    The count is the estate's one, Get-XmipSourceFile's: a C# file's every
    line, a test file's included.
#>

[int] $script:MaximumFileLines = 400
[int] $script:MaximumColumns = 100

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')
    [int] $script:MaximumFileLines = 400
    [int] $script:MaximumColumns = 100
    $script:Files = @(Get-XmipSourceFile -Root $script:Root -Language 'C#')
}

Describe 'C# style: a file is small and its lines are short' {
    It "has some C# to read" {
        $script:Files.Count | Should -BeGreaterThan 0
    }

    It "gates every file at or under $script:MaximumFileLines lines" {
        $over = @($script:Files | Where-Object { $_.Code -gt $script:MaximumFileLines })

        [string] $detail = ($over | ForEach-Object { "$($_.Path) is $($_.Code)" }) -join "`n"

        $over.Count | Should -Be 0 -Because "these are over the gate:`n$detail"
    }

    It "keeps every line at or under $script:MaximumColumns columns" {
        [string[]] $wide = @(
            foreach ($file in $script:Files) {
                [string] $path = Join-Path -Path $script:Root -ChildPath $file.Path
                [string[]] $lines = [IO.File]::ReadAllLines($path)

                for ([int] $index = 0; $index -lt $lines.Count; $index++) {
                    if ($lines[$index].Length -gt $script:MaximumColumns) {
                        "$($file.Path):$($index + 1) is $($lines[$index].Length)"
                    }
                }
            }
        )

        $wide.Count | Should -Be 0 -Because "these are too wide:`n$($wide -join "`n")"
    }
}
