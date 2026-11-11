#requires -PSEdition Core
#requires -Version 7.7.0

<#
    `Get-XmipSourceFile` is what the estate map weighs its tree with and what
    `test/Rust.Style.Test.ps1` gates file length with. Both read the same
    number, so a wrong counting rule is wrong in two places at once and
    consistent with itself in both — the map would draw a false shape and the
    gate would let a long file through, and neither would disagree with the
    other loudly enough to be noticed.

    So the rules are asserted here against a fixture small enough to count by
    hand, rather than against the estate, where nobody can say what the right
    answer is.

    `Get-XmipMapWeight` is tested beside it: the rule that a file is charged to
    the deepest repository containing it is the whole reason a parent's count
    is not its children's added again.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')
    . (Join-Path $PSScriptRoot 'Initialize-XmipStyleLimit.ps1')


    # `Get-XmipMapWeight` is the map generator's, not the module's: it is not
    # exported, so it is reached the only way an unexported function can be.
    . (Join-Path $script:Root 'Xmip/Add-XmipMapMount.ps1')

    <#
        .SYNOPSIS
        Writes one file under the fixture, making its directory.

        .PARAMETER Path
        Where it goes, relative to the fixture root.

        .PARAMETER Text
        Its lines.
    #>
    function New-FixtureFile {
        [CmdletBinding()]
        [OutputType([void])]
        param(
            [Parameter(Mandatory = $true)]
            [string] $Path,

            [Parameter(Mandatory = $true)]
            [AllowEmptyCollection()]
            [AllowEmptyString()]
            [string[]] $Text
        )

        [string] $full = Join-Path $script:Fixture $Path

        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $full) | Out-Null
        Set-Content -LiteralPath $full -Value $Text -Encoding utf8
    }
}

Describe 'Get-XmipSourceFile counts what a file holds' {
    BeforeAll {
        $script:Fixture = Join-Path -Path $TestDrive -ChildPath 'source'

        New-FixtureFile -Path 'module/one/src/lib.rs' -Text @(
            'pub fn one() {}'
            'pub fn two() {}'
            ''
            '#[cfg(test)]'
            'mod tests {'
            '    #[test]'
            '    fn it() {}'
            '}'
        )

        New-FixtureFile -Path 'module/one/src/plain.rs' -Text @('a', 'b', 'c')

        New-FixtureFile -Path 'module/one/target/generated.rs' -Text @(
            'this', 'was', 'not', 'written', 'by', 'anyone'
        )

        # A crate's further program, one line over the gate. Until 2026-11-11
        # every directory called bin was skipped as .NET's output, and the
        # Essentials' roll and node grew past the gate unread.
        [string[]] $long = @(1..($script:MaximumFileLines + 1) | ForEach-Object { "// $_" })
        New-FixtureFile -Path 'module/one/src/bin/program.rs' -Text $long

        # The root crate's own source, one line over the gate. Until
        # 2026-11-11 the root's .src was no tree the gate read, and
        # xmip-service's run.rs had reached 407 lines unmeasured.
        New-FixtureFile -Path '.src/service/run.rs' -Text $long

        New-FixtureFile -Path 'module/two/Two.csproj' -Text @('<Project />')
        New-FixtureFile -Path 'module/two/Two.cs' -Text @('class Two {}')
        New-FixtureFile -Path 'module/two/bin/Debug/Built.cs' -Text @('class Built {}')

        New-FixtureFile -Path 'test/two/Thing.ps1' -Text @('one', 'two')
        New-FixtureFile -Path 'test/two/Thing.Test.ps1' -Text @('one', 'two', 'three')

        $script:Found = @(Get-XmipSourceFile -Root $script:Fixture)
    }

    It 'ends a Rust file''s production code at its first #[cfg(test)]' {
        $file = $script:Found | Where-Object Path -eq 'module/one/src/lib.rs'

        $file.Code | Should -Be 3
        $file.Tests | Should -Be 5
        $file.Total | Should -Be 8
    }

    It 'counts every line of a Rust file that has no test module' {
        $file = $script:Found | Where-Object Path -eq 'module/one/src/plain.rs'

        $file.Code | Should -Be 3
        $file.Tests | Should -Be 0
    }

    It 'counts a *.Test.ps1 as no production code at all' {
        $file = $script:Found | Where-Object Path -eq 'test/two/Thing.Test.ps1'

        $file.Code | Should -Be 0
        $file.Tests | Should -Be 3
    }

    It 'counts a PowerShell file that is not a test in full' {
        ($script:Found | Where-Object Path -eq 'test/two/Thing.ps1').Code | Should -Be 2
    }

    It 'reads nothing out of target, which nobody wrote' {
        @($script:Found | Where-Object Path -match 'target') | Should -BeNullOrEmpty
    }

    It 'reads a Rust crate''s src/bin, so a program over the gate is reported' {
        [string[]] $over = @(
            $script:Found |
                Where-Object { $_.Code -gt $script:MaximumFileLines } |
                ForEach-Object { $_.Path }
        )

        $over | Should -Contain 'module/one/src/bin/program.rs' -Because (
            'test/Rust.Style.Test.ps1 gates what Get-XmipSourceFile counts')
    }

    It 'reads the root''s .src, so the root service over the gate is reported' {
        [string[]] $over = @(
            $script:Found |
                Where-Object { $_.Code -gt $script:MaximumFileLines } |
                ForEach-Object { $_.Path }
        )

        $over | Should -Contain '.src/service/run.rs' -Because (
            'the root crate is Rust the estate ships, gated like every module (ADR-0049)')
    }

    It 'reads nothing out of the bin beside a .NET project, which its build wrote' {
        @($script:Found | Where-Object Path -match '^module/two/bin/') | Should -BeNullOrEmpty
        ($script:Found | Where-Object Path -eq 'module/two/Two.cs').Code | Should -Be 1
    }

    It 'names a file with forward slashes, relative to the root' {
        foreach ($file in $script:Found) {
            $file.Path | Should -Not -Match '\\' -Because 'a path reads the same on every platform'
            $file.Path | Should -Not -Match '^[A-Za-z]:' -Because 'it is relative to the root'
        }
    }

    It 'answers for one language when asked for one' {
        @(Get-XmipSourceFile -Root $script:Fixture -Language Rust).Language |
            Sort-Object -Unique |
            Should -Be 'Rust'
    }
}

Describe 'Get-XmipMapWeight charges a file to the deepest repository holding it' {
    BeforeAll {
        $script:Source = @(
            [PSCustomObject]@{
                Path = 'module/core/capability/transport/.src/lib.rs'; Code = 100; Language = 'Rust'
            }
            [PSCustomObject]@{
                Path     = 'module/core/capability/transport/http/src/lib.rs'
                Code     = 40
                Language = 'Rust'
            }
            [PSCustomObject]@{
                Path     = 'module/core/capability/transport/http/src/more.rs'
                Code     = 2
                Language = 'Rust'
            }
            [PSCustomObject]@{
                Path     = 'module/core/capability/transport/http/src/Thing.cs'
                Code     = 7
                Language = 'C#'
            }
            [PSCustomObject]@{
                Path = 'module/nowhere/src/lib.rs'; Code = 9; Language = 'Rust'
            }
        )

        $script:Mount = @(
            'module/core/capability/transport'
            'module/core/capability/transport/http'
        )

        $script:Weight = Get-XmipMapWeight -Mount $script:Mount -Source $script:Source
    }

    It 'gives a parent its own source and not its children''s' {
        $script:Weight['module/core/capability/transport']['Rust'] | Should -Be 100
    }

    It 'adds a child''s files together under the child' {
        $script:Weight['module/core/capability/transport/http']['Rust'] | Should -Be 42
    }

    It 'keeps each language of a mount apart, so the tree can say what it is' {
        # One total hid that the estate's largest repository is almost all C#
        # (the owner, 2026-09-21).
        $script:Weight['module/core/capability/transport/http']['C#'] | Should -Be 7
        $script:Weight['module/core/capability/transport'].ContainsKey('C#') |
            Should -BeFalse -Because 'the parent holds no C# of its own'
    }

    It 'charges nothing to a mount nobody declared' {
        $script:Weight.ContainsKey('module/nowhere') | Should -BeFalse
    }

    It 'charges every line exactly once' {
        [int] $sum = 0

        foreach ($spoken in $script:Weight.Values) {
            foreach ($count in $spoken.Values) {
                $sum += $count
            }
        }

        $sum | Should -Be 149 -Because 'the file under no mount is the only one not counted'
    }
}
