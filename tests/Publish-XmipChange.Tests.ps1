#requires -PSEdition Core
#requires -Version 7.6.5

<#
    The file that lands the estate had no tests, and it is the one that keeps
    breaking. Three of its failures reached the operator's console before
    anything caught them:

      2026-08-27  Publish-XmipPin was added and never exported. The command
                  documented as the repair path did not exist.
      2026-08-27  ModuleVersion went to 1.8.0 in the manifest and stayed 1.7.0
                  in the module, which is the number the manifest gate reads.
      2026-08-27  Sort-XmipModuleDependency emitted one module out of three.

    None of those needed a running estate to catch. Two are the manifest and the
    module disagreeing with each other, and a test can read both. The third is a
    pure function over a fixture.

    That is what this file is: the cheap checks that would have caught what was
    actually shipped, rather than a thorough suite that would not have.
#>

BeforeAll {
    $script:Root = Join-Path $PSScriptRoot '..'
    $script:ModuleRoot = Join-Path $script:Root 'Xmip'
    $script:ManifestPath = Join-Path $script:ModuleRoot 'Xmip.psd1'

    # Every copy first, then one import.
    #
    # Pester runs the whole tests/ directory in one session and several files
    # import this module. Two loaded copies make InModuleScope throw "Multiple
    # script or manifest modules named 'Xmip' are currently loaded" — which
    # reads as a broken test and is a dirty session.
    Get-Module -Name Xmip -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:ManifestPath -Force

    $script:Manifest = Import-PowerShellDataFile -Path $script:ManifestPath
    $script:Module = Get-Module -Name Xmip
}

Describe 'What the module says it exports' {
    It 'exports every function the manifest names' {
        # The Publish-XmipPin bug, exactly. The manifest listed it; the module
        # did not export it; the command was documented and unreachable.
        foreach ($name in $script:Manifest.FunctionsToExport) {
            $script:Module.ExportedFunctions.Keys |
                Should -Contain $name -Because "$name is in FunctionsToExport"
        }
    }

    It 'names every function it exports in the manifest' {
        # The other direction. An exported function the manifest does not list
        # works when the module is imported by path and vanishes when it is
        # imported by name from PSModulePath.
        foreach ($name in $script:Module.ExportedFunctions.Keys) {
            $script:Manifest.FunctionsToExport |
                Should -Contain $name -Because "$name is exported and unlisted"
        }
    }

    It 'exports every alias the manifest names, and each resolves' {
        foreach ($name in $script:Manifest.AliasesToExport) {
            $script:Module.ExportedAliases.Keys |
                Should -Contain $name -Because "$name is in AliasesToExport"

            # Definition, not ResolvedCommandName. The latter is empty for an
            # alias exported from a module: resolution happens against the
            # caller's session state, and the alias object carries only the
            # name it was defined with.
            $target = $script:Module.ExportedAliases[$name].Definition
            $script:Module.ExportedFunctions.Keys |
                Should -Contain $target -Because "$name points at $target"
        }
    }

    It 'uses an approved verb for every exported function' {
        # An unapproved verb warns on import and disappears from
        # `Get-Command -Verb`. This is why xmip-git is an alias and not a
        # function.
        $approved = @((Get-Verb).Verb)

        foreach ($name in $script:Module.ExportedFunctions.Keys) {
            $verb = ($name -split '-', 2)[0]
            $approved | Should -Contain $verb -Because "$name would warn on import"
        }
    }
}

Describe 'The version' {
    It 'is the same in the manifest and in the module' {
        # $script:XmipVersion is what Assert-XmipManifestVersion compares
        # minimumScriptVersion against. When the two drift, the manifest gate
        # reads a number nobody bumped.
        $psm1 = Get-Content (Join-Path $script:ModuleRoot 'Xmip.psm1') -Raw
        $psm1 | Should -Match "XmipVersion = \[version\]::Parse\('$([regex]::Escape($script:Manifest.ModuleVersion))'\)"
    }
}

Describe 'Every exported command' {
    It 'has a synopsis' {
        foreach ($name in $script:Module.ExportedFunctions.Keys) {
            $help = Get-Help -Name $name -ErrorAction SilentlyContinue

            $help.Synopsis |
                Should -Not -BeNullOrEmpty -Because "$name needs one line saying what it does"
        }
    }

    It 'supports -WhatIf where it changes something' {
        # Named rather than inferred: a command that pushes to origin and does
        # not support -WhatIf cannot be rehearsed, and the estate is 42 remote
        # repositories.
        foreach ($name in 'Publish-XmipChange', 'Publish-XmipPin') {
            (Get-Command -Name $name).Parameters.Keys |
                Should -Contain 'WhatIf' -Because "$name writes to origin"
        }
    }
}

Describe 'Test-XmipBuildOutput' {
    It 'catches what a compiler produced' {
        # On 2026-08-27 a hand-run loop pushed 105 files of target/ to
        # xmip-core. It asked whether a module was dirty and never what was.
        InModuleScope Xmip {
            foreach ($path in @(
                    'target/debug/build/x.rs'
                    'bin/Debug/net11.0/x.dll'
                    'obj/project.assets.json'
                    'Cargo.lock'
                    'packages.lock.json'
                )) {
                Test-XmipBuildOutput -Path $path |
                    Should -BeTrue -Because "$path is build output"
            }
        }
    }

    It 'leaves source alone' {
        InModuleScope Xmip {
            foreach ($path in @(
                    'src/lib.rs'
                    'Cargo.toml'
                    'docs/decisions/ADR-0019.md'
                    'README.md'
                    'src/bin/main.rs'
                )) {
                Test-XmipBuildOutput -Path $path |
                    Should -BeFalse -Because "$path is source"
            }
        }
    }
}

Describe 'Sort-XmipModuleDependency' {
    BeforeAll {
        # A three-module estate on disk: c depends on b, b depends on a. The
        # manifests are real Cargo.toml files because the sort reads them with
        # a regex, and a mock would test the mock.
        $script:Fixture = Join-Path ([IO.Path]::GetTempPath()) "xmip-sort-$([guid]::NewGuid())"

        $modules = @{
            'modules/foundation/a' = @'
[package]
name = "xmip-core-a"

[dependencies]
'@
            'modules/foundation/b' = @'
[package]
name = "xmip-core-b"

[dependencies]
xmip-a = { package = "xmip-core-a", git = "https://example.invalid/a", branch = "main" }
'@
            'modules/foundation/c' = @'
[package]
name = "xmip-core-c"

[dependencies]
xmip-b = { package = "xmip-core-b", git = "https://example.invalid/b", branch = "main" }
'@
        }

        foreach ($module in $modules.Keys) {
            $directory = Join-Path $script:Fixture $module
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $directory 'Cargo.toml') -Value $modules[$module]
        }

        $script:Given = @(
            'modules/foundation/c'
            'modules/foundation/a'
            'modules/foundation/b'
        )
    }

    AfterAll {
        Remove-Item -LiteralPath $script:Fixture -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'returns every module it was given' {
        # The recursion bug: it emitted one of three, which reads as a smaller
        # change set rather than as a failure. This is the assertion that would
        # have caught it, and it is one line.
        InModuleScope Xmip -Parameters @{ Root = $script:Fixture; Given = $script:Given } {
            param($Root, $Given)

            $ordered = @(Sort-XmipModuleDependency -RepositoryRoot $Root -Module $Given)

            $ordered.Count | Should -Be 3
            foreach ($module in $Given) {
                $ordered | Should -Contain $module
            }
        }
    }

    It 'puts a dependency before what depends on it' {
        InModuleScope Xmip -Parameters @{ Root = $script:Fixture; Given = $script:Given } {
            param($Root, $Given)

            $ordered = @(Sort-XmipModuleDependency -RepositoryRoot $Root -Module $Given)

            $ordered.IndexOf('modules/foundation/a') |
                Should -BeLessThan $ordered.IndexOf('modules/foundation/b')
            $ordered.IndexOf('modules/foundation/b') |
                Should -BeLessThan $ordered.IndexOf('modules/foundation/c')
        }
    }

    It 'places a module whose dependency is not in this change set' {
        # Landing only c is ordinary: a and b are already on origin. A sort that
        # waited for them would report a cycle and land nothing.
        InModuleScope Xmip -Parameters @{ Root = $script:Fixture } {
            param($Root)

            $ordered = @(
                Sort-XmipModuleDependency -RepositoryRoot $Root -Module @('modules/foundation/c')
            )

            $ordered | Should -Be @('modules/foundation/c')
        }
    }

    It 'accepts an empty change set without throwing' {
        InModuleScope Xmip -Parameters @{ Root = $script:Fixture } {
            param($Root)

            @(Sort-XmipModuleDependency -RepositoryRoot $Root -Module @()).Count |
                Should -Be 0
        }
    }
}

Describe 'Publish-XmipPin' {
    It 'counts what it is pinning rather than being told' {
        # Being told "nothing landed" is what made it skip, leaving 18 stale
        # gitlinks. It has no -Count parameter now, on purpose.
        (Get-Command -Name Publish-XmipPin).Parameters.Keys |
            Should -Not -Contain 'Count'
    }

    It 'is reachable as Publish-XmipChange -Pin' {
        (Get-Command -Name Publish-XmipChange).Parameters.Keys |
            Should -Contain 'Pin'
    }
}

Describe 'Publish-XmipChange' {
    It 'has no -Commit or -Push' {
        # Dependencies track branch = "main" under ADR-0005, so a module that is
        # committed and not pushed is one the next in the order tests against
        # the previous published version. The pair is one operation here.
        $parameters = (Get-Command -Name Publish-XmipChange).Parameters.Keys

        $parameters | Should -Not -Contain 'Commit'
        $parameters | Should -Not -Contain 'Push'
    }

    It 'takes -m, like git' {
        (Get-Command -Name Publish-XmipChange).Parameters['Message'].Aliases |
            Should -Contain 'm'
    }
}
