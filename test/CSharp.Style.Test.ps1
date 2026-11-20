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
    a test's temporary folder is TestFolder's (Xmip.Surface.Test/TestFolder.cs,
    linked into every .NET test project that makes one), as a Rust test's is
    file::temporary::Folder's. It makes the folder with
    Directory.CreateTempSubdirectory, under the temporary path with a name
    nobody can guess, and disposing it removes it with everything in it, also
    when the test fails. A call to CreateTempSubdirectory, Path.GetTempPath()
    or Path.GetTempFileName() anywhere else is refused, except where the
    reason is written beside the file's name below. On 2026-11-19 twenty files
    made their folders by hand (ADR-0021, amendment 2026-11-19); on 2026-11-20
    the GUI's tests had left about 1,267 folders per label under this
    machine's temporary directory, and every other site made its own folder
    and removed it its own way (ADR-0021, amendment 2026-11-20).
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

Describe 'C# style: a test''s temporary folder is TestFolder' {
    BeforeAll {
        <#
            Each entry is a file's count of calls to CreateTempSubdirectory,
            GetTempPath or GetTempFileName, or reads of a variable that names
            the temporary path, and why it makes them. A file not listed makes
            none, and a listed file makes exactly its count.
        #>
        [string] $script:Helper = 'module/core/operation/operate/dotnet/Xmip.Surface.Test'
        $script:TemporaryPathAllowed = @{
            # The helper: its folder is made there.
            "$script:Helper/TestFolder.cs"                                       = 1
            # The helper's test, which asserts where the folder is made.
            "$script:Helper/TestFolderTest.cs"                                   = 1
            # The runtime library's copies, in the one folder every process
            # loading the library shares: each load sweeps the copies no
            # process holds any more, which a folder of its own per process
            # would leave behind.
            'module/core/operation/operate/dotnet/Xmip.Operate/NativeRuntime.cs' = 1
        }

        # A call, not a word in a comment; and the variables that name the
        # temporary path.
        [string] $script:TemporaryPath = (
            '\b(CreateTempSubdirectory|GetTempPath|GetTempFileName)\s*\(|' +
            '"(TEMP|TMP|TMPDIR)"'
        )
    }

    It 'makes a temporary path nowhere but where it is allowed' {
        [object[]] $calls = @(
            foreach ($file in $script:Files) {
                [string] $full = Join-Path -Path $script:Root -ChildPath $file.Path
                [string[]] $line = @([IO.File]::ReadAllLines($full))

                for ([int] $index = 0; $index -lt $line.Count; $index++) {
                    [string] $code = $line[$index]

                    if (-not $code.TrimStart().StartsWith('//') -and
                        $code -match $script:TemporaryPath) {
                        [PSCustomObject]@{ Path = $file.Path; Line = $index + 1 }
                    }
                }
            }
        )

        [string[]] $named = @(
            @($calls.Path) + @($script:TemporaryPathAllowed.Keys) | Sort-Object -Unique
        )

        [string[]] $wrong = @(
            foreach ($name in $named) {
                [object[]] $made = @($calls | Where-Object { $_.Path -eq $name })
                [int] $allowed = 0

                if ($script:TemporaryPathAllowed.ContainsKey($name)) {
                    $allowed = $script:TemporaryPathAllowed[$name]
                }

                if ($made.Count -ne $allowed) {
                    "$name makes $($made.Count) where $allowed is allowed, at " +
                        ($made.Line -join ', ')
                }
            }
        )

        $wrong.Count | Should -Be 0 -Because (
            "TestFolder instead, from $script:Helper/TestFolder.cs:`n" + ($wrong -join "`n")
        )
    }
}
