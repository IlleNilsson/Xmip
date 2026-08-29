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

Describe 'Resolve-XmipCommitSubject' {
    # 2026-08-29. Two commits landed under "Pin 1 module" while carrying an ADR,
    # a test file and a documentation change. Two defects, one symptom:
    #
    #   the subject rule used $Message only when NO gitlink was staged, so any
    #   commit that also moved a gitlink discarded it;
    #
    #   and both call sites invoked Publish-XmipPin with no -Message at all, so
    #   on the ordinary path there was nothing to discard in the first place.
    #
    # The second is why fixing only the first would have changed nothing.

    It 'keeps the message when the platform repository changed too' {
        InModuleScope Xmip {
            $staged = @(
                '.gitmodules'
                'docs/decisions/ADR-0024-resource-claim-replaces-exclusiveness.md'
                'modules/platform/exclusiveness'
                'tests/Sync-XmipEstate.Tests.ps1'
            )

            Resolve-XmipCommitSubject -Staged $staged -Message 'Unmount exclusiveness' |
                Should -Be 'Unmount exclusiveness' -Because 'three of the four are not gitlinks'
        }
    }

    It 'calls it a pin when gitlinks are all there is' {
        InModuleScope Xmip {
            $staged = @('modules/foundation/core', 'modules/capabilities/route')

            Resolve-XmipCommitSubject -Staged $staged -Message 'Arrivals and departures' |
                Should -Be 'Pin 2 modules' -Because 'no author intent is recorded by a gitlink move'
        }
    }

    It 'agrees on the noun for one' {
        InModuleScope Xmip {
            Resolve-XmipCommitSubject -Staged @('modules/foundation/core') -Message 'x' |
                Should -Be 'Pin 1 module'
        }
    }

    It 'uses the message when nothing under modules/ is staged' {
        InModuleScope Xmip {
            Resolve-XmipCommitSubject -Staged @('src/lib.rs') -Message 'Record the departure' |
                Should -Be 'Record the departure'
        }
    }

    It 'falls back to the pin subject when there is no message' {
        InModuleScope Xmip {
            Resolve-XmipCommitSubject -Staged @('src/lib.rs') -Message '' |
                Should -Be 'Pin 0 modules'
        }
    }
}

Describe 'Get-XmipBuildableFeature' {
    BeforeAll {
        $script:Fixture = Join-Path ([IO.Path]::GetTempPath()) "xmip-feat-$([guid]::NewGuid())"
        New-Item -Path $script:Fixture -ItemType Directory -Force | Out-Null

        $script:Manifest = Join-Path $script:Fixture 'Cargo.toml'
        Set-Content -LiteralPath $script:Manifest -Value @'
[package]
name = "xmip-core-example"

[features]
default = ["server"]
server = []
tls = ["dep:rustls"]
uuid-v7 = ["dep:uuid"]

[dependencies]
rustls = { version = "0.23", optional = true }
'@
    }

    AfterAll {
        Remove-Item -LiteralPath $script:Fixture -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'names every declared feature except default' {
        # default is what cargo build already does.
        InModuleScope Xmip -Parameters @{ Manifest = $script:Manifest } {
            $features = Get-XmipBuildableFeature -ManifestPath $Manifest -Module 'modules/nowhere'

            $features | Should -Contain 'server'
            $features | Should -Contain 'tls'
            $features | Should -Contain 'uuid-v7' -Because 'a hyphenated feature is still a feature'
            $features | Should -Not -Contain 'default'
        }
    }

    It 'leaves out a feature known not to build' {
        # The list is shrink-only. An entry here is why a feature is unchecked,
        # and removing it is what fixing the feature looks like.
        InModuleScope Xmip -Parameters @{ Manifest = $script:Manifest } {
            $script:XmipUnbuildableFeature['modules/nowhere'] = @('tls')

            try {
                $features = Get-XmipBuildableFeature -ManifestPath $Manifest -Module 'modules/nowhere'

                $features | Should -Not -Contain 'tls'
                $features | Should -Contain 'server' -Because 'one broken feature must not stop the rest'
            }
            finally {
                $script:XmipUnbuildableFeature.Remove('modules/nowhere')
            }
        }
    }

    It 'says nothing for a manifest with no features table' {
        InModuleScope Xmip -Parameters @{ Fixture = $script:Fixture } {
            $bare = Join-Path $Fixture 'bare.toml'
            Set-Content -LiteralPath $bare -Value "[package]`nname = `"x`"`n"

            @(Get-XmipBuildableFeature -ManifestPath $bare -Module 'modules/nowhere').Count |
                Should -Be 0
        }
    }

    It 'excuses only what is written down, and writes down why' {
        # Both entries are real and dated. An undocumented exception is a waiver
        # list wearing a ratchet's clothes.
        InModuleScope Xmip {
            $script:XmipUnbuildableFeature.Keys | Should -Contain 'modules/capabilities/transport'
            $script:XmipUnbuildableFeature.Keys | Should -Contain 'modules/platform/runtime'

            $script:XmipUnbuildableFeature['modules/platform/runtime'] |
                Should -Contain 'dynamic-loading'
        }

        $source = Get-Content (Join-Path $script:ModuleRoot 'Publish-XmipChange.ps1') -Raw

        foreach ($feature in 'tls', 'dynamic-loading') {
            $source | Should -Match "$([regex]::Escape($feature))\s" -Because "$feature needs its reason in the source"
        }
    }
}

Describe 'Publish-XmipPin is given what it needs' {
    It 'is passed -Message everywhere it is called' {
        # The half of the defect a fixture cannot see. Resolve-XmipCommitSubject
        # can be correct and the message still never arrive.
        $source = Get-Content (Join-Path $script:ModuleRoot 'Publish-XmipChange.ps1') -Raw

        [string[]] $calls = @(
            [regex]::Matches($source, 'Publish-XmipPin\s+-RepositoryRoot[^\r\n]*') |
                ForEach-Object { $_.Value }
        )

        $calls.Count | Should -BeGreaterThan 0 -Because 'the pin is called from somewhere'

        foreach ($call in $calls) {
            $call | Should -Match '-Message' -Because "this call drops the operator's message: $call"
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
