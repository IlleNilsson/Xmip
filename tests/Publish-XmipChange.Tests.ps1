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
    # The owner's call, 2026-09-05: a superproject log full of "Pin 1 module" is
    # not correct. One land carries one message; it belongs on the superproject
    # commit as much as the module commit, so the estate's log reads what
    # changed. The message wins whenever there is one — a pin that changes only
    # gitlinks says the same thing the module said. "Pin N module" survives only
    # as the fallback for a pin with no message, the shape outside a land.
    #
    # This reverses the 2026-08-29 rule, which used the message only when the
    # commit also touched a platform-repository file. That rule left a
    # module-only land — the common case — under a generic "Pin 1 module".

    It 'keeps the message when the platform repository changed too' {
        InModuleScope Xmip {
            $staged = @(
                '.gitmodules'
                'docs/decisions/ADR-0024-resource-claim-replaces-exclusiveness.md'
                'modules/platform/exclusiveness'
                'tests/Sync-XmipEstate.Tests.ps1'
            )

            Resolve-XmipCommitSubject -Staged $staged -Message 'Unmount exclusiveness' |
                Should -Be 'Unmount exclusiveness'
        }
    }

    It 'keeps the message even when gitlinks are all there is' {
        InModuleScope Xmip {
            $staged = @('modules/foundation/core', 'modules/capabilities/route')

            Resolve-XmipCommitSubject -Staged $staged -Message 'Arrivals and departures' |
                Should -Be 'Arrivals and departures' -Because 'the land carried a message'
        }
    }

    It 'keeps the message for a single-module land' {
        InModuleScope Xmip {
            Resolve-XmipCommitSubject -Staged @('modules/foundation/core') -Message 'Record the departure' |
                Should -Be 'Record the departure'
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
            Resolve-XmipCommitSubject -Staged @('modules/foundation/core') -Message '' |
                Should -Be 'Pin 1 module'
        }
    }

    It 'names the count in the fallback when there is no message' {
        InModuleScope Xmip {
            Resolve-XmipCommitSubject -Staged @('modules/foundation/core', 'modules/capabilities/route') -Message '' |
                Should -Be 'Pin 2 modules'
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
                $features =
                    Get-XmipBuildableFeature -ManifestPath $Manifest -Module 'modules/nowhere'

                $features | Should -Not -Contain 'tls'
                $features |
                    Should -Contain 'server' -Because 'one broken feature must not stop the rest'
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

    It 'has an empty exception list, which is the intended state' {
        # The list began with tls and dynamic-loading on 2026-08-29, the day
        # declared features were first built, and both came off on 2026-08-30 —
        # tls by enabling rustls's ring feature, dynamic-loading by ADR-0025
        # clause 5 giving xmip-core-abi the surface its header always defined.
        #
        # This asserts the emptiness deliberately. A new entry fails here, and
        # it should: the entry needs the owner's agreement and a written reason,
        # and editing this test alongside it is where the second half is proven.
        InModuleScope Xmip {
            [string] $because = 'an unbuildable feature needs the owner''s agreement, recorded'

            @($script:XmipUnbuildableFeature.Keys).Count | Should -Be 0 -Because $because
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

Describe 'A module the estate is about to pin is on origin first' {
    BeforeAll {
        [string] $script:Source = Get-Content -Raw -LiteralPath (
            Join-Path $script:ModuleRoot 'Publish-XmipChange.ps1'
        )

        [System.Management.Automation.Language.Ast] $script:Ast =
            [System.Management.Automation.Language.Parser]::ParseInput(
                $script:Source, [ref] $null, [ref] $null
            )
    }

    It 'acts on the unpushed set rather than only warning about it' {
        # 2026-09-03. Eight modules were committed with nothing uncommitted,
        # the run warned about all eight, and Publish-XmipPin staged every
        # moved gitlink with `git add -A` and pinned them. The superproject
        # went to origin naming eight commits origin did not have, so a fresh
        # clone could not check the estate out.
        #
        # The warning was right and nothing acted on it. powershell-style.md
        # section 5: a rule that reports and returns success is not a rule.
        $script:Source | Should -Match 'Publish-XmipUnpushed -RepositoryRoot'
    }

    It 'pushes them before the first call that can pin' {
        # Order is the whole fix. Pushing after a pin leaves the same broken
        # commit on origin for as long as it takes the push to finish, and
        # leaves it forever if the push fails.
        [int] $push = $script:Source.IndexOf('Publish-XmipUnpushed -RepositoryRoot')
        [int] $pin = $script:Source.IndexOf('Publish-XmipPin -RepositoryRoot')

        $push | Should -BeGreaterThan 0 -Because 'the unpushed set must be pushed somewhere'
        $pin | Should -BeGreaterThan 0 -Because 'the pin must still happen'
        $push | Should -BeLessThan $pin -Because 'pushing after pinning fixes nothing'
    }

    It 'refuses to continue when such a push fails' {
        # Throwing, not warning. A failed push here is the one condition that
        # produces the unclonable estate this whole Describe is about.
        [System.Management.Automation.Language.FunctionDefinitionAst] $function =
            $script:Ast.Find({
                param($node)

                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'Publish-XmipUnpushed'
            }, $true)

        $function | Should -Not -BeNullOrEmpty -Because 'the function has to exist'

        [bool] $throws = $null -ne $function.Find({
            param($node)

            $node -is [System.Management.Automation.Language.ThrowStatementAst]
        }, $true)

        $throws | Should -BeTrue
    }

    It 'completes a commit rather than making one' {
        # It completes a commit the operator already made. Making one here
        # would land untested work under a message nobody wrote.
        [System.Management.Automation.Language.FunctionDefinitionAst] $function =
            $script:Ast.Find({
                param($node)

                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'Publish-XmipUnpushed'
            }, $true)

        $function.Extent.Text | Should -Not -Match 'git -C \$path commit'
    }
}
