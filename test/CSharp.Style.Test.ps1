#requires -PSEdition Core
#requires -Version 7.7.0

<#
    The estate's two length rules, held for C# as Rust.Style.Test.ps1 holds
    them for Rust and Xmip.Style.Test.ps1 for PowerShell: a file is at most 400
    lines, a line at most 100 columns (CONTRIBUTING, *Read before writing*).
    C# had no gate until 2026-10-13, and eight files over 400 and fifty-four
    lines over 100 were found then. The owner, the same day: *I have clearly
    stated we do not want wide or long files! Make them small, useful and
    includable!*

    The count is the estate's one, Get-XmipSourceFile's: a C# file's every
    line, a test file's included.

    And one rule of C#'s own, stated here because C# has no style document:
    a temporary folder is Directory.CreateTempSubdirectory's, which makes it
    under the temporary path with a name nobody can guess, in one call. A
    file that builds a name from Path.GetTempPath() and calls
    Directory.CreateDirectory is refused, except where a stable folder is the
    point and the reason is written beside its name below. On 2026-11-19
    twenty files made their folders by hand, and a run that stopped early
    left each one behind (ADR-0021, amendment 2026-11-19).
#>

. (Join-Path $PSScriptRoot 'Initialize-XmipStyleLimit.ps1')
[int] $script:MaximumColumns = 100

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')
    . (Join-Path $PSScriptRoot 'Initialize-XmipStyleLimit.ps1')
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

Describe 'C# style: a temporary folder is the platform''s' {
    BeforeAll {
        $script:TemporaryFolderAllowed = @(
            # The runtime library's copies, in the one folder every process
            # loading the library shares: each load sweeps the copies no
            # process holds any more, which a folder of its own per process
            # would leave behind.
            'module/core/operation/operate/dotnet/Xmip.Operate/NativeRuntime.cs'
        )
    }

    It 'makes no folder from a name built on Path.GetTempPath()' {
        [string[]] $made = @(
            foreach ($file in $script:Files) {
                if ($file.Path -in $script:TemporaryFolderAllowed) {
                    continue
                }

                [string] $path = Join-Path -Path $script:Root -ChildPath $file.Path
                [string] $text = [IO.File]::ReadAllText($path)

                if ($text.Contains('Path.GetTempPath()') -and
                    $text.Contains('Directory.CreateDirectory(')) {
                    $file.Path
                }
            }
        )

        $made.Count | Should -Be 0 -Because (
            "Directory.CreateTempSubdirectory instead:`n" + ($made -join "`n")
        )
    }
}
