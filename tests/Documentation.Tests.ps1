#requires -PSEdition Core
#requires -Version 7.6

<#
    README.md is the front door. It was stale for weeks — pointing at a deleted
    specification, at scripts that had moved, and at four parameters that no
    longer existed — and nothing noticed, because nothing was watching.

    These tests watch. If Xmip is hard to use, no one will use it, and the
    fastest way to make it hard is documentation that lies.
#>

BeforeAll {
    $script:Root = Join-Path $PSScriptRoot '..'
    $script:ModuleRoot = Join-Path $script:Root 'Xmip'
    $script:Readme = Get-Content (Join-Path $script:Root 'README.md') -Raw

    Import-Module (Join-Path $script:ModuleRoot 'Xmip.psd1') -Force
}

Describe 'README names only commands that exist' {
    It 'mentions no Xmip command the module does not export' {
        [string[]] $exported = @((Get-Module Xmip).ExportedFunctions.Keys)

        [string[]] $mentioned = @(
            [regex]::Matches($script:Readme, '\b(?:Install|Sync|Get|Test|Expand|New|Remove|Set)-Xmip\w*') |
                ForEach-Object { $_.Value } |
                Select-Object -Unique
        )

        $mentioned.Count | Should -BeGreaterThan 5 -Because 'the README should show the commands'

        foreach ($name in $mentioned) {
            $exported | Should -Contain $name -Because "README shows $name, so the module must export it"
        }
    }

    It 'passes no parameter a command does not have' {
        # The failure this catches by name: -Apply, -CreateRepositories,
        # -ConfigureRepositories and -SynchronizeSubmodules survived in the
        # README for weeks after they were removed from the code.
        [regex] $pattern = [regex]::new('\b((?:Install|Sync|Get|Test|Expand)-Xmip\w*)((?:\s+-\w+)+)')

        foreach ($match in $pattern.Matches($script:Readme)) {
            [string] $command = $match.Groups[1].Value
            $definition = Get-Command $command -ErrorAction SilentlyContinue

            if ($null -eq $definition) {
                continue
            }

            foreach ($argument in [regex]::Matches($match.Groups[2].Value, '-(\w+)')) {
                [string] $parameter = $argument.Groups[1].Value

                # Common parameters are real but not in the function's own list.
                if ($parameter -in 'WhatIf', 'Confirm', 'Verbose', 'Debug', 'ErrorAction') {
                    continue
                }

                $definition.Parameters.Keys |
                    Should -Contain $parameter -Because "README passes -$parameter to $command"
            }
        }
    }
}

Describe 'README links resolve' {
    It 'links to no file that does not exist' {
        [string[]] $links = @(
            [regex]::Matches($script:Readme, '\]\(([^)#:]+)\)') |
                ForEach-Object { $_.Groups[1].Value } |
                Where-Object { -not $_.StartsWith('http') } |
                Select-Object -Unique
        )

        $links.Count | Should -BeGreaterThan 5

        foreach ($link in $links) {
            [string] $path = Join-Path $script:Root $link
            Test-Path -LiteralPath $path |
                Should -BeTrue -Because "README links to $link"
        }
    }
}

Describe 'README lists every document that exists' {
    It 'links to every document under docs/architecture' {
        # The reverse direction, and the one that was missing. Checking that
        # every link resolves catches a deleted file; it says nothing about a
        # file nobody linked. docs/architecture/ reached 31 documents against
        # ADR-0020's six that way, and the README looked correct throughout.
        [string] $directory = Join-Path $script:Root 'docs/architecture'
        [string[]] $present = @(
            Get-ChildItem -Path $directory -Filter '*.md' -File |
                ForEach-Object { $_.Name } |
                Sort-Object
        )

        $present.Count | Should -BeGreaterThan 0

        [string[]] $unlisted = @(
            $present | Where-Object { $script:Readme -notmatch [regex]::Escape($_) }
        )

        [string] $detail = $unlisted -join ', '

        # A ratchet, not a target. Twenty-three of these are pre-consolidation
        # documents that allocation.toml section 3b is merging into the six,
        # and the README is right not to list them — they are leaving. Asserting
        # zero here fails on work that is already planned and tracked, and a
        # test that is always red is a test nobody reads.
        #
        # Lower it as section 3b empties. It may fall and may not rise, so a
        # new unlisted document is still caught immediately, which is the case
        # this test was written for.
        $unlisted.Count |
            Should -BeLessOrEqual 16 -Because "ADR-0020 is one document per subject; unlisted: $detail"
    }
}

Describe 'The setup procedure is present' {
    It 'shows how to load the module and put it on PSModulePath' {
        $script:Readme | Should -Match 'Import-Module\s+\.\\Xmip'
        $script:Readme | Should -Match 'Install-XmipModule'
        $script:Readme | Should -Match 'Import-Module Xmip'
    }

    It 'states the PowerShell floor that prerequisite.toml declares' {
        Import-Module PSToml -ErrorAction Stop

        [string] $prerequisitePath = Join-Path $script:Root 'prerequisite.toml'
        $prerequisite = ConvertFrom-Toml -InputObject (Get-Content $prerequisitePath -Raw -Encoding utf8)
        [string] $floor = [string] $prerequisite.prerequisite.powershell.minimum

        [string] $because = 'a reader must be told the same floor the tooling enforces'

        $script:Readme | Should -Match ([regex]::Escape($floor)) -Because $because
    }

    It 'covers both roles a person can set up' {
        $script:Readme | Should -Match '-Role operator'
        $script:Readme | Should -Match '-Role developer'
    }
}
