#requires -PSEdition Core
#requires -Version 7.6.5

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
    $script:Root = Join-Path $PSScriptRoot '..'

    Import-Module (Join-Path $script:Root 'Xmip/Xmip.psd1') -Force

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
        $script:Fixture = Join-Path ([IO.Path]::GetTempPath()) "xmip-source-$(New-Guid)"

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

        New-FixtureFile -Path 'test/two/Thing.ps1' -Text @('one', 'two')
        New-FixtureFile -Path 'test/two/Thing.Test.ps1' -Text @('one', 'two', 'three')

        $script:Found = @(Get-XmipSourceFile -Root $script:Fixture)
    }

    AfterAll {
        Remove-Item -LiteralPath $script:Fixture -Recurse -Force -ErrorAction SilentlyContinue
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
            [PSCustomObject]@{ Path = 'module/capability/transport/.src/lib.rs'; Code = 100 }
            [PSCustomObject]@{ Path = 'module/capability/transport/http/src/lib.rs'; Code = 40 }
            [PSCustomObject]@{ Path = 'module/capability/transport/http/src/more.rs'; Code = 2 }
            [PSCustomObject]@{ Path = 'module/nowhere/src/lib.rs'; Code = 9 }
        )

        $script:Mount = @(
            'module/capability/transport'
            'module/capability/transport/http'
        )

        $script:Weight = Get-XmipMapWeight -Mount $script:Mount -Source $script:Source
    }

    It 'gives a parent its own source and not its children''s' {
        $script:Weight['module/capability/transport'] | Should -Be 100
    }

    It 'adds a child''s files together under the child' {
        $script:Weight['module/capability/transport/http'] | Should -Be 42
    }

    It 'charges nothing to a mount nobody declared' {
        $script:Weight.ContainsKey('module/nowhere') | Should -BeFalse
    }

    It 'charges every line exactly once' {
        [int] $sum = 0

        foreach ($count in $script:Weight.Values) {
            $sum += $count
        }

        $sum | Should -Be 142 -Because 'the file under no mount is the only one not counted'
    }
}
