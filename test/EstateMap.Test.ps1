#requires -PSEdition Core
#requires -Version 7.6.5

<#
    doc/architecture/estate-map.md is every repository the estate declares and
    whether it is composed here. It is generated, for the reason ADR-0020
    clause 5 gives: a hand-written list of repositories is a second source of
    truth and will be wrong within a week.

    It had been wrong for exactly that reason before it was generated. The
    two-level tree in repository-model.md section 7 said eighteen capability
    entries when there were nineteen, and carried `migrate`, `diagnose` and
    `schedule` for as long as it took someone to notice they had gone.

    These tests fail when the committed map differs from what the generator
    produces, when a count in it disagrees with the manifest, and when the
    generator is not deterministic — a map that differs run to run fails its
    own first test on the next machine.
#>

BeforeAll {
    $script:Root = Join-Path $PSScriptRoot '..'
    $script:MapPath = Join-Path $script:Root 'doc/architecture/estate-map.md'

    Import-Module (Join-Path $script:Root 'Xmip/Xmip.psd1') -Force

    $script:Map = Get-Content -LiteralPath $script:MapPath -Raw

    [PSCustomObject[]] $script:Repository = @(
        Get-XmipEstateRepository -Root $script:Root
    )

    <#
        .SYNOPSIS
        The count a row of one of the map's two tables states.

        .DESCRIPTION
        Returns the declared, mounted and not-mounted cells of the row whose
        first cell is $Label, or $null when the map has no such row. The
        label may carry markdown, so it is matched inside the cell rather
        than against the whole of it.
    #>
    function Get-MapCount {
        [CmdletBinding()]
        [OutputType([PSCustomObject])]
        param(
            [Parameter(Mandatory = $true)]
            [string] $Label
        )

        [string] $escaped = [regex]::Escape($Label)
        [string] $pattern = '(?m)^\|[^|]*\b' + $escaped +
                            '\b[^|]*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|'

        if ($script:Map -notmatch $pattern) {
            return $null
        }

        return [PSCustomObject] @{
            Declared   = [int] $Matches[1]
            Mounted    = [int] $Matches[2]
            NotMounted = [int] $Matches[3]
        }
    }

    <#
        .SYNOPSIS
        How many technology names one host's block actually lists.

        .DESCRIPTION
        A bullet opens with `- **maturity**, N — ` and its names run on over
        indented continuation lines. Everything after the dash is joined and
        split on commas, so the answer is the names that are there rather
        than the number the bullet claims.
    #>
    function Measure-MapName {
        [CmdletBinding()]
        [OutputType([int])]
        param(
            [Parameter(Mandatory = $true)]
            [string] $Block
        )

        [string[]] $named = @()

        foreach ($line in ($Block -split '\r?\n')) {
            if ($line -match '^- \*\*\w+\*\*, \d+ — (.+)$') {
                $named += ($Matches[1] -split ',\s*')
                continue
            }

            if ($named.Count -gt 0 -and $line -match '^  (\S.*)$') {
                $named += ($Matches[1] -split ',\s*')
            }
        }

        return @($named | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
    }
}

Describe 'The map is generated, not written' {
    It 'matches what New-XmipEstateMap produces' {
        # The whole point of the generator, and the same guarantee
        # Decision.Test.ps1 gives the decision index. A hand edit fails here.
        #
        # It also fails on a clone whose submodules are not initialized,
        # because the map reports what is composed and an uncomposed clone
        # composes nothing. Initialize the submodules recursively before
        # reading a failure here as a stale map.
        [string] $generated = New-XmipEstateMap -Root $script:Root
        [string] $committed = Get-Content -LiteralPath $script:MapPath -Raw

        [string] $because = 'run: New-XmipEstateMap -Save'

        $generated | Should -Be $committed -Because $because
    }

    It 'produces the same text twice' {
        # A generator reading a hashtable's keys in whatever order they come
        # back is stable within one run and not across two. Every ordering in
        # this one is sorted; this is what says so.
        [string] $first = New-XmipEstateMap -Root $script:Root
        [string] $second = New-XmipEstateMap -Root $script:Root

        $first | Should -Be $second -Because 'the map must not depend on run order'
    }

    It 'wraps every line inside a hundred columns' {
        # The style rules gate the module and the tests at a hundred columns.
        # A generated document is written by the module and is held to the
        # same width, which means the generator has to wrap.
        [string[]] $long = @(
            Get-Content -LiteralPath $script:MapPath |
                Where-Object { $_.Length -gt 100 }
        )

        [string] $detail = $long -join "`n"

        $long.Count | Should -Be 0 -Because "these lines are too long:`n$detail"
    }
}

Describe 'The map counts what the manifest declares' {
    It 'states the same total the manifest does' {
        $counted = Get-MapCount -Label 'Total'

        $null -ne $counted | Should -BeTrue -Because 'the map needs a total row'
        $counted.Declared | Should -Be $script:Repository.Count
    }

    It 'states the same count for every domain' {
        [string[]] $domain = @(
            $script:Repository | ForEach-Object { $_.Domain } | Sort-Object -Unique
        )

        $domain.Count | Should -BeGreaterThan 3

        foreach ($name in $domain) {
            [int] $declared = @(
                $script:Repository | Where-Object { $_.Domain -eq $name }
            ).Count

            $counted = Get-MapCount -Label $name

            $null -ne $counted | Should -BeTrue -Because "$name needs a row"
            $counted.Declared | Should -Be $declared -Because "$name declares $declared"
        }
    }

    It 'states the same count for every maturity' {
        [string[]] $maturity = @(
            $script:Repository | ForEach-Object { $_.Maturity } | Sort-Object -Unique
        )

        $maturity.Count | Should -BeGreaterThan 0

        foreach ($word in $maturity) {
            [int] $declared = @(
                $script:Repository | Where-Object { $_.Maturity -eq $word }
            ).Count

            $counted = Get-MapCount -Label $word

            $null -ne $counted | Should -BeTrue -Because "$word needs a row"
            $counted.Declared | Should -Be $declared -Because "$word declares $declared"
        }
    }

    It 'adds declared and not mounted back to mounted in every row' {
        # The arithmetic of the tables, checked rather than trusted: a row
        # whose three numbers do not add up is a generator counting two
        # different sets.
        [regex] $row = [regex]::new('(?m)^\|[^|]+\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|')

        [object[]] $wrong = @(
            $row.Matches($script:Map) | Where-Object {
                [int] $_.Groups[1].Value -ne
                ([int] $_.Groups[2].Value + [int] $_.Groups[3].Value)
            }
        )

        [string] $detail = ($wrong | ForEach-Object { $_.Value }) -join "`n"

        $wrong.Count | Should -Be 0 -Because "these rows do not add up:`n$detail"
    }
}

Describe 'The map names every repository' {
    It 'mentions every declared module by its full name' {
        # The forty that are not technologies. A technology appears under its
        # parent by its last segment, which the test below counts instead —
        # asserting that `c` appears somewhere in a document of this size
        # would assert nothing.
        [string[]] $missing = @(
            $script:Repository |
                Where-Object { $_.Domain -ne 'Technology' } |
                Where-Object { -not $script:Map.Contains($_.Name) } |
                ForEach-Object { $_.Name }
        )

        [string] $detail = $missing -join "`n"

        $missing.Count | Should -Be 0 -Because "not on the map:`n$detail"
    }

    It 'names every retired repository with its date' {
        # So that a reader who remembers a name and cannot find it above is
        # told what happened to it rather than left looking. Three of these
        # were unmounted on 2026-09-19 and the section 7 tree kept drawing
        # them.
        Import-Module PSToml -ErrorAction Stop

        [string] $path = Join-Path $script:Root 'architecture.toml'
        $manifest = ConvertFrom-Toml -InputObject (Get-Content -LiteralPath $path -Raw)

        [object[]] $retired = @($manifest.retired)

        $retired.Count | Should -BeGreaterThan 0

        foreach ($entry in $retired) {
            $script:Map | Should -Match ([regex]::Escape([string] $entry.name))
            $script:Map | Should -Match ([regex]::Escape([string] $entry.on))
        }
    }

    It 'puts every technology under the repository that hosts it' {
        # 290 of the 330 are technologies, and a technology on no parent's
        # list is a repository nobody can find. The heading is the parent's
        # name; the count beside it is how many it hosts.
        [PSCustomObject[]] $parent = @(
            $script:Repository |
                Where-Object { $_.Domain -ne 'Technology' } |
                Where-Object { $_.Name -in $script:Repository.Parent }
        )

        $parent.Count | Should -BeGreaterThan 10

        foreach ($entry in $parent) {
            [int] $hosted = @(
                $script:Repository | Where-Object { $_.Parent -eq $entry.Name }
            ).Count

            [string] $heading = '(?m)^### `' + [regex]::Escape($entry.Name) + '`, '

            $script:Map | Should -Match $heading -Because "$($entry.Name) hosts $hosted"
        }
    }

    It 'names as many technologies under a host as it declares' {
        # Not the count in the bullet, which comes from the same place the
        # names do and would agree with itself. The names, counted. A
        # technology dropped from a wrapped line is invisible in a document
        # this long, and this is what sees it.
        [string] $block = '(?ms)^### `([^`]+)`, .+?(?=^### |^---)'

        [object[]] $wrong = @(
            [regex]::Matches($script:Map, $block) | ForEach-Object {
                [string] $name = $_.Groups[1].Value

                [int] $declared = @(
                    $script:Repository | Where-Object { $_.Parent -eq $name }
                ).Count

                [int] $named = Measure-MapName -Block $_.Value

                if ($named -ne $declared) {
                    "$name names $named of $declared"
                }
            }
        )

        [string] $detail = $wrong -join "`n"

        $wrong.Count | Should -Be 0 -Because "a host is missing technologies:`n$detail"
    }
}

Describe 'The map says what the manifest cannot' {
    It 'reports a mount for every composed repository' {
        # The fact the manifest does not hold. Composition lives in the
        # .gitmodules files, at two levels, and a repository composed here
        # shows the path it is composed at.
        [PSCustomObject[]] $mounted = @(
            $script:Repository | Where-Object { $_.Mounted }
        )

        $mounted.Count | Should -BeGreaterThan 40

        foreach ($entry in ($mounted | Where-Object { $_.Domain -ne 'Technology' })) {
            $script:Map | Should -Match ([regex]::Escape($entry.Mount))
        }
    }

    It 'says in its own words that maturity is declared rather than observed' {
        # The manifest's maturity is known unreliable — repositories marked
        # `planned` hold six figures of Rust. The map makes that visible and
        # must not be read as endorsing it.
        $script:Map | Should -Match 'declared, not observed'
    }

    It 'links to the section that draws where the modules mount' {
        $script:Map | Should -Match 'repository-model\.md'
    }
}

Describe 'The section 7 tree points at the map' {
    It 'names the map in repository-model.md' {
        # The two are a pair: the tree is where things mount, the map is the
        # whole estate. A reader who finds one must be told about the other,
        # or the tree goes on looking complete.
        [string] $path = Join-Path $script:Root 'doc/architecture/repository-model.md'
        [string] $model = Get-Content -LiteralPath $path -Raw

        $model | Should -Match 'estate-map\.md'
    }
}
