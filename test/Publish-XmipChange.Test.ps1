#requires -PSEdition Core
#requires -Version 7.7.0

<#
    The file that lands the estate had no tests, and it is the one that keeps
    breaking. Three of its failures reached the operator's console before
    anything caught them:

      2026-08-27  Publish-XmipPin was added and never exported. The command
                  documented as the repair path did not exist.
      2026-08-27  Sort-XmipModuleDependency emitted one module out of three.

    Neither needed a running estate to catch. The first is the manifest and the
    module disagreeing with each other, and a test can read both. The second is
    a pure function over a fixture. The version has one home, Xmip.psd1, which
    the module reads from its own module object, so there is nothing to hold
    equal.

    That is what this file is: the cheap checks that would have caught what was
    actually shipped, rather than a thorough suite that would not have.
#>

BeforeAll {
    # What these commands audit while they are tested goes to this run's own
    # drive, never to .local-work/audit or the operating system's log
    # (ADR-0062): stated over whatever the session had, and given back after.
    $script:AuditBefore = $env:XMIP_AUDIT_DIRECTORY
    $env:XMIP_AUDIT_DIRECTORY = Join-Path -Path $TestDrive -ChildPath 'audit'

    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')
    $script:ModuleRoot = Join-Path $script:Root 'Xmip'

    <#
        .SYNOPSIS
        The module's source, every file of it, so a test that asks what the
        landing's code says does not care which file a line is in.
    #>
    function Get-XmipLandingSource {
        return ((Get-ChildItem -LiteralPath $script:ModuleRoot -Filter '*.ps1' |
                    ForEach-Object { Get-Content -Raw -LiteralPath $_.FullName }) -join "`n")
    }

    $script:ManifestPath = Join-Path $script:ModuleRoot 'Xmip.psd1'
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
    It 'catches what a compiler produced, below a repository''s root too' {
        # On 2026-08-27 a hand-run loop pushed 105 files of target/ to
        # xmip-core. It asked whether a module was dirty and never what was.
        # On 2026-11-19 a landing committed 483 files of .NET build output
        # below a module's root, src/Xmip.Cli/bin and obj, which a rule
        # anchored at the root did not see.
        [string] $built = Join-Path -Path $TestDrive -ChildPath 'built'
        [string] $tagged = Join-Path -Path $built -ChildPath 'sdk/target'
        $null = New-Item -ItemType Directory -Path $tagged -Force
        Set-Content -LiteralPath (Join-Path $tagged 'CACHEDIR.TAG') -Value 'Signature: cargo'

        InModuleScope Xmip -Parameters @{ At = $built } {
            param([string] $At)

            foreach ($path in @(
                    'target/debug/build/x.rs'
                    'bin/Debug/net11.0/x.dll'
                    'obj/project.assets.json'
                    'Cargo.lock'
                    'packages.lock.json'
                    'src/Xmip.Cli/bin/Debug/net11.0/Xmip.Cli.deps.json'
                    'src/Xmip.Cli.Test/bin/Release/net11.0/x.json'
                    'src/Xmip.Cli/obj/project.assets.json'
                    'sdk/target/debug/x.d'
                    'sdk/target/'
                    'tool/x.exe', 'lib/x.so', 'lib/x.dylib', 'x.rlib', 'x.pdb', 'x.nupkg'
                )) {
                Test-XmipBuildOutput -At $At -Path $path -State '??' |
                    Should -BeTrue -Because "$path is build output"
            }
        }
    }

    It 'leaves source alone, a folder named target that cargo did not make among it' {
        # deploy/profile/target holds a deployment target's profiles: what
        # makes a folder cargo's is the CACHEDIR.TAG cargo writes in it.
        [string] $source = Join-Path -Path $TestDrive -ChildPath 'source'
        $null = New-Item -ItemType Directory -Path "$source/deploy/profile/target" -Force

        InModuleScope Xmip -Parameters @{ At = $source } {
            param([string] $At)

            foreach ($path in @(
                    'src/lib.rs'
                    'Cargo.toml'
                    'doc/decision/ADR-0019.md'
                    'README.md'
                    'src/bin/main.rs'
                    'src/bin/release/main.rs'
                    'deploy/profile/target/server.toml'
                )) {
                Test-XmipBuildOutput -At $At -Path $path -State ' M' |
                    Should -BeFalse -Because "$path is source"
            }
        }
    }

    It 'lets build output leave: a deletion commits none' {
        InModuleScope Xmip -Parameters @{ At = $TestDrive } {
            param([string] $At)

            foreach ($state in ' D', 'D ', 'MD') {
                Test-XmipBuildOutput -At $At -Path 'bin/Debug/x.dll' -State $state |
                    Should -BeFalse -Because "'$state' deletes it"
            }
        }
    }
}

Describe 'A landing commits no build output, and refuses before anything lands' {
    # 2026-11-19: round 12's landing, 38e46a4 in module/core/operation/cli,
    # committed 483 files of .NET build output, src/Xmip.Cli/bin and obj, left
    # on disk after the C# command line was deleted. Get-XmipStatus read an
    # untracked folder as one path, the rule was anchored at the root, and the
    # platform repository was never asked.
    BeforeAll {
        [string[]] $script:Who = @('-c', 'user.name=x', '-c', 'user.email=x@example.com')

        <#
            .SYNOPSIS
            An estate of one module, module/a, in the platform repository,
            each a git repository on main with one commit.
        #>
        function New-XmipLandingFixture {
            param(
                [Parameter(Mandatory = $true)]
                [string] $Name,

                [Parameter()]
                [string[]] $Committed = @()
            )

            [string] $root = Join-Path -Path $TestDrive -ChildPath $Name
            [string] $module = Join-Path -Path $root -ChildPath 'module/a'
            $null = New-Item -ItemType Directory -Path "$module/src" -Force
            Set-Content -LiteralPath "$root/.gitignore" -Value 'module/'
            Set-Content -LiteralPath "$module/src/lib.rs" -Value 'pub fn one() {}'

            foreach ($file in $Committed) {
                $null = New-Item -ItemType File -Path "$module/$file" -Value 'built' -Force
            }

            foreach ($repository in $root, $module) {
                git init -q -b main $repository
                git -C $repository add -A
                git -C $repository @script:Who commit -q -m one
            }

            return $root
        }

        # Everything past the refusal is the landing's own business and is
        # mocked: what is asked here is whether the landing reaches it.
        Mock -ModuleName Xmip Update-XmipGeneratedDocument { }
        Mock -ModuleName Xmip Get-XmipDeclaredModule { @('module/a') }
        Mock -ModuleName Xmip Test-XmipCodeChange { $true }
        Mock -ModuleName Xmip Get-XmipModuleConsumer { }
        Mock -ModuleName Xmip Sort-XmipModuleDependency { $Module }
        Mock -ModuleName Xmip Test-XmipChangeTree {
            [pscustomobject] @{ Failed = $true; Skipped = @(); Verified = @() }
        }
    }

    It 'refuses an added bin/Debug/x.dll, naming the repository and the file' {
        [string] $root = New-XmipLandingFixture -Name 'added'
        $null = New-Item -ItemType File -Path "$root/module/a/bin/Debug/x.dll" -Force

        { Publish-XmipChange -RepositoryRoot $root -Message 'land' 6>$null } |
            Should -Throw -ExpectedMessage '*REFUSED.*module/a*bin/Debug/x.dll*'

        Should -Invoke -ModuleName Xmip Test-XmipChangeTree -Times 0 -Exactly
        git -C "$root/module/a" rev-list --count HEAD | Should -Be '1'
    }

    It 'refuses build output in a folder below the root, in every repository, first files named' {
        [string] $root = New-XmipLandingFixture -Name 'below'
        foreach ($index in 1..7) {
            [string] $file = "$root/module/a/src/Xmip.Cli/bin/Debug/net11.0/x$index.dll"
            $null = New-Item -ItemType File -Path $file -Force
        }
        $null = New-Item -ItemType File -Path "$root/tool/obj/project.assets.json" -Force

        [string] $said = ''
        try {
            Publish-XmipChange -RepositoryRoot $root -Message 'land' 6>$null
        }
        catch {
            $said = $_.Exception.Message
        }

        $said | Should -Match 'REFUSED\.'
        $said | Should -Match 'module/a, 7 file'
        $said | Should -Match 'src/Xmip\.Cli/bin/Debug/net11\.0/x1\.dll'
        $said | Should -Match 'and 2 more'
        $said | Should -Match 'the platform repository, 1 file'
        $said | Should -Match 'tool/obj/project\.assets\.json'
        Should -Invoke -ModuleName Xmip Test-XmipChangeTree -Times 0 -Exactly
    }

    It 'lets a deleted bin/Debug/x.dll land' {
        [string] $root = New-XmipLandingFixture -Name 'deleted' -Committed 'bin/Debug/x.dll'
        Remove-Item -LiteralPath "$root/module/a/bin/Debug/x.dll"

        { Publish-XmipChange -RepositoryRoot $root -Message 'land' 6>$null } | Should -Not -Throw

        Should -Invoke -ModuleName Xmip Test-XmipChangeTree -Times 1 -Exactly
    }

    It 'lets a source change land' {
        [string] $root = New-XmipLandingFixture -Name 'source'
        Set-Content -LiteralPath "$root/module/a/src/lib.rs" -Value 'pub fn two() {}'

        { Publish-XmipChange -RepositoryRoot $root -Message 'land' 6>$null } | Should -Not -Throw

        Should -Invoke -ModuleName Xmip Test-XmipChangeTree -Times 1 -Exactly
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
                'doc/decision/ADR-0024-resource-claim-replaces-exclusiveness.md'
                'module/platform/exclusiveness'
                'test/Sync-XmipEstate.Test.ps1'
            )

            Resolve-XmipCommitSubject -Staged $staged -Message 'Unmount exclusiveness' |
                Should -Be 'Unmount exclusiveness'
        }
    }

    It 'keeps the message even when gitlinks are all there is' {
        InModuleScope Xmip {
            $staged = @('module/foundation/core', 'module/core/capability/route')

            Resolve-XmipCommitSubject -Staged $staged -Message 'Arrivals and departures' |
                Should -Be 'Arrivals and departures' -Because 'the land carried a message'
        }
    }

    It 'keeps the message for a single-module land' {
        InModuleScope Xmip {
            $staged = @('module/foundation/core')

            Resolve-XmipCommitSubject -Staged $staged -Message 'Record the departure' |
                Should -Be 'Record the departure'
        }
    }

    It 'uses the message when nothing under module/ is staged' {
        InModuleScope Xmip {
            Resolve-XmipCommitSubject -Staged @('src/lib.rs') -Message 'Record the departure' |
                Should -Be 'Record the departure'
        }
    }

    It 'falls back to the pin subject when there is no message' {
        InModuleScope Xmip {
            Resolve-XmipCommitSubject -Staged @('module/foundation/core') -Message '' |
                Should -Be 'Pin 1 module'
        }
    }

    It 'names the count in the fallback when there is no message' {
        InModuleScope Xmip {
            $staged = @('module/foundation/core', 'module/core/capability/route')

            Resolve-XmipCommitSubject -Staged $staged -Message '' |
                Should -Be 'Pin 2 modules'
        }
    }
}

Describe 'A module''s timing program runs last, alone' {
    # rust-style.md section 5c: landings failed at random on timing tests run
    # inside a module's parallel suite (2026-11-01).
    BeforeAll {
        $script:Fixture = Join-Path -Path $TestDrive -ChildPath 'measured'
        New-Item -Path $script:Fixture -ItemType Directory -Force | Out-Null

        $script:Declared = Join-Path $script:Fixture 'declared.toml'
        Set-Content -LiteralPath $script:Declared -Value @'
[package]
name = "xmip-core-example"

[[test]]
name = "ledger"
path = "tests/ledger/main.rs"

# The module's timing program.
[[test]]
name = "measured"
path = "tests/measured/main.rs"
test = false
required-features = ["test-support"]

[dev-dependencies]
'@
        $script:Tested = Join-Path $script:Fixture 'tested.toml'
        Set-Content -LiteralPath $script:Tested -Value @'
[package]
name = "xmip-core-example"

[[test]]
name = "measured"
path = "tests/measured/main.rs"
'@
    }

    It 'finds the program named measured, and nothing where none is declared' {
        InModuleScope Xmip -Parameters @{ Declared = $script:Declared; Fixture = $script:Fixture } {
            Get-XmipMeasuredDeclaration -ManifestPath $Declared | Should -Match 'test = false'

            $bare = Join-Path $Fixture 'bare.toml'
            Set-Content -LiteralPath $bare -Value "[package]`nname = `"x`"`n"
            Get-XmipMeasuredDeclaration -ManifestPath $bare | Should -BeNullOrEmpty
        }
    }

    It 'fails a program cargo would run among the module''s other tests' {
        InModuleScope Xmip -Parameters @{ Tested = $script:Tested } {
            Mock Write-Host { }

            Test-XmipMeasuredProgram -ManifestPath $Tested | Should -BeFalse
        }
    }

    It 'runs it in the measured build, one test at a time' {
        # ADR-0018, amendment 2026-11-20: the millisecond rule is measured on
        # the optimized build, `measured`; every other build is at opt-level 1.
        InModuleScope Xmip -Parameters @{ Declared = $script:Declared } {
            Mock Write-Host { }
            Mock Invoke-XmipTool { [pscustomobject]@{ Passed = $true; Said = @() } }

            Test-XmipMeasuredProgram -ManifestPath $Declared | Should -BeTrue
            Should -Invoke Invoke-XmipTool -Times 1 -Exactly -ParameterFilter {
                ($Argument -join ' ') -eq
                'test --profile measured --all-features --test measured -- --test-threads=1'
            }
        }
    }

    It 'is run by the landing after every part has passed, and linted in the workspace' {
        [string] $tree = Get-Content -Raw -LiteralPath (
            Join-Path $script:ModuleRoot 'Test-XmipChangeTree.ps1')
        [string] $rust = Get-Content -Raw -LiteralPath (
            Join-Path $script:ModuleRoot 'Test-XmipRustChange.ps1')

        [int] $parts = $tree.IndexOf('Invoke-XmipLandingPart -RepositoryRoot')
        [int] $measured = $tree.IndexOf('Test-XmipMeasuredProgram -ManifestPath')

        $parts | Should -BeGreaterThan 0
        $measured | Should -BeGreaterThan $parts
        $rust | Should -Match "'--test', 'measured'"
    }
}

Describe 'The landing''s Rust part verifies in the one workspace' {
    # ADR-0016, amendment 2026-11-20: one workspace; every consumer is linted
    # at once against a change, each changed crate alone with its defaults.
    BeforeAll {
        $script:Both = Join-Path -Path $TestDrive -ChildPath 'both'
        New-Item -ItemType Directory -Force -Path (Join-Path $script:Both 'm/dotnet/X') | Out-Null
        foreach ($crate in '.', 'm', 'r') {
            New-Item -ItemType Directory -Force -Path (Join-Path $script:Both $crate) | Out-Null
            [string] $manifest = Join-Path $script:Both "$crate/Cargo.toml"
            [string] $name = if ($crate -eq '.') { 'xmip' } else { "xmip-$crate" }
            Set-Content -LiteralPath $manifest -Value "[package]`nname = `"$name`"`n"
        }
        Set-Content -LiteralPath (Join-Path $script:Both 'm/dotnet/X/X.csproj') -Value '<Project />'
    }

    It 'lints every member against a change with consumers, each crate alone with its defaults' {
        InModuleScope Xmip -Parameters @{ Root = $script:Both } {
            Mock Write-Host { }
            Mock Invoke-XmipTool { [pscustomobject]@{ Passed = $true; Said = @() } }

            Test-XmipRustChange -RepositoryRoot $Root -Module @('m') -Consumer |
                Should -BeNullOrEmpty
            Should -Invoke Invoke-XmipTool -Times 1 -Exactly -ParameterFilter {
                ($Argument -join ' ') -eq 'clippy --all-targets --all-features --workspace'
            }
            Should -Invoke Invoke-XmipTool -Times 2 -Exactly -ParameterFilter {
                ($Argument -join ' ') -eq 'test'
            }
            Should -Invoke Invoke-XmipTool -Times 1 -Exactly -ParameterFilter {
                ($Argument -join ' ') -eq 'fmt --check -p xmip-m -p xmip'
            }
        }
    }

    It 'names the step that failed' {
        InModuleScope Xmip -Parameters @{ Root = $script:Both } {
            Mock Write-Host { }
            Mock Invoke-XmipTool {
                [bool] $passed = ($Argument -join ' ') -ne 'clippy --all-targets'
                [pscustomobject]@{ Passed = $passed; Said = @() }
            }

            Test-XmipRustChange -RepositoryRoot $Root -Module @('r') |
                Should -Be 'r, its lints'
            # A crate declaring no feature was tested whole by its default run.
            Should -Invoke Invoke-XmipTool -Times 0 -Exactly -ParameterFilter {
                ($Argument -join ' ') -eq 'test --all-features'
            }
        }
    }

    It 'verifies a changed crate the workspace''s plan does not hold through its own manifest' {
        # 2026-11-20: a landing stopped at its first step, `cargo fmt --check
        # -p xmip-template-rust`, a crate the workspace leaves out. Here `r` is
        # left out by the plan alone, never by its folder's name.
        InModuleScope Xmip -Parameters @{ Root = $script:Both } {
            Mock Write-Host { }
            Mock Invoke-XmipTool { [pscustomobject]@{ Passed = $true; Said = @() } }
            Mock Get-XmipWorkspacePlan { [pscustomobject]@{ Member = @('m'); Patched = @() } }

            Test-XmipRustChange -RepositoryRoot $Root -Module @('m', 'r') |
                Should -BeNullOrEmpty

            [string] $own = '--manifest-path ' + (Join-Path (Join-Path $Root 'r') 'Cargo.toml')
            [string[]] $once = @(
                'fmt --check -p xmip-m -p xmip'
                'clippy --all-targets --all-features -p xmip-m -p xmip'
                "fmt --check $own"
                "clippy --all-targets --all-features $own"
                "test $own"
                "clippy --all-targets $own"
            )

            foreach ($command in $once) {
                Should -Invoke Invoke-XmipTool -Times 1 -Exactly -ParameterFilter {
                    ($Argument -join ' ') -eq $command
                }
            }
            Should -Invoke Invoke-XmipTool -Times 0 -Exactly -ParameterFilter {
                $Argument -contains 'xmip-r'
            }
        }
    }

    It 'verifies a Rust module''s .NET projects in the .NET part, failing the module with them' {
        # 2026-11-16: operate's Xmip.Surface and Xmip.Operate, and abi's Xmip.Abi,
        # sit beside a Cargo.toml, and only cargo ran for them.
        InModuleScope Xmip -Parameters @{ Root = $script:Both } {
            Mock Write-Host { }
            Mock Test-XmipDotnetModule { $false }

            Test-XmipDotnetChange -RepositoryRoot $Root -Module @('m', 'r') | Should -Be 'm'
            Should -Invoke Test-XmipDotnetModule -Times 1 -Exactly
        }
    }
}

Describe 'A test that never ends fails the landing in a minute' {
    # 2026-11-04: a landing waited two hours on seven TLS tests that waited on
    # each other; libtest only said each had run over 60 seconds.

    It 'stops the run at libtest''s first word of a test running a minute, and names it' {
        InModuleScope Xmip {
            Mock Write-Host { }
            Mock Stop-XmipToolRun { }
            Mock cargo {
                'test a::passes ... ok'
                'test b::waits has been running for over 60 seconds'
                'test c::waits has been running for over 60 seconds'
                $global:LASTEXITCODE = 0
            }

            (Invoke-XmipTool -Tool cargo -Argument @('test')).Passed | Should -BeFalse
            Should -Invoke Stop-XmipToolRun -Times 1 -Exactly
            Should -Invoke Write-Host -ParameterFilter {
                "$Object" -like '*FAILED. b::waits ran a minute*'
            }
        }
    }

    It 'passes a run whose tests all end, and stops nothing' {
        InModuleScope Xmip {
            Mock Write-Host { }
            Mock Stop-XmipToolRun { }
            Mock cargo {
                'test a::passes ... ok'
                $global:LASTEXITCODE = 0
            }

            (Invoke-XmipTool -Tool cargo -Argument @('test')).Passed | Should -BeTrue
            Should -Invoke Stop-XmipToolRun -Times 0 -Exactly
        }
    }
}

Describe 'Every cargo and dotnet the module runs takes twelve of the machine, set in one place' {
    # The owner, 2026-11-02: cargo -j 12, test threads 12, dotnet -m:12.
    # A landing's part is given its share in XMIP_TOOL_SHARE, which this
    # run may have inherited from the landing running it: saved, cleared and
    # given back.
    BeforeAll {
        $script:ShareWas = $env:XMIP_TOOL_SHARE
        Remove-Item -Path 'env:XMIP_TOOL_SHARE' -ErrorAction SilentlyContinue
    }

    AfterAll {
        $env:XMIP_TOOL_SHARE = $script:ShareWas
    }

    It 'takes the share a landing''s part is given, at most twelve' {
        InModuleScope Xmip {
            try {
                $env:XMIP_TOOL_SHARE = '2'
                Get-XmipToolParallel | Should -Be 2
                $env:XMIP_TOOL_SHARE = '40'
                Get-XmipToolParallel | Should -Be 12
            }
            finally {
                Remove-Item -Path 'env:XMIP_TOOL_SHARE' -ErrorAction SilentlyContinue
            }
        }
    }

    It 'gives cargo twelve jobs and twelve test threads for the call, and puts them back after' {
        InModuleScope Xmip {
            Mock Write-Host { }
            $env:CARGO_BUILD_JOBS = $null
            $env:RUST_TEST_THREADS = $null
            Mock cargo {
                "jobs=$env:CARGO_BUILD_JOBS threads=$env:RUST_TEST_THREADS"
                $global:LASTEXITCODE = 0
            }

            (Invoke-XmipTool -Tool cargo -Argument @('build') -Output Keep).Said |
                Should -Be 'jobs=12 threads=12'
            $env:CARGO_BUILD_JOBS | Should -BeNullOrEmpty
            $env:RUST_TEST_THREADS | Should -BeNullOrEmpty
        }
    }

    It 'gives a dotnet build or test twelve nodes, and leaves other subcommands alone' {
        InModuleScope Xmip {
            Mock dotnet {
                $args -join ' '
                $global:LASTEXITCODE = 0
            }

            (Invoke-XmipTool -Tool dotnet -Argument @('test', 'x.csproj') -Output Keep).Said |
                Should -Be 'test x.csproj -m:12'
            (Invoke-XmipTool -Tool dotnet -Argument @('--version') -Output Keep).Said |
                Should -Be '--version'
        }
    }

    It 'says a failed call failed' {
        InModuleScope Xmip {
            Mock cargo { $global:LASTEXITCODE = 101 }

            (Invoke-XmipTool -Tool cargo -Argument @('build') -Output None).Passed | Should -BeFalse
        }
    }

    It 'is the only place in the module that runs cargo or dotnet' {
        [string[]] $calling = @(Get-ChildItem -LiteralPath $script:ModuleRoot -Filter '*.ps1' |
            Where-Object { $_.Name -ne 'Invoke-XmipTool.ps1' } |
            Select-String -Pattern '^\s*[^#]*&\s*(cargo|dotnet)\b' |
            ForEach-Object { "$($_.Filename):$($_.LineNumber)" })

        $calling | Should -BeNullOrEmpty
    }
}

Describe 'A detached submodule lands on a main put at its commit' {
    It 'puts main here rather than checking out a stale main' {
        # 2026-09-12, twice in one landing: after `git submodule update` the
        # local main sat behind origin, `checkout main` was refused over the
        # changed files, HEAD stayed detached, and the push of that stale main
        # failed with the commit already made. `checkout -B main` puts main at
        # the commit the superproject pinned, which is where it belongs.
        $source = Get-XmipLandingSource

        $source | Should -Match ([regex]::Escape("@('checkout', '-B', 'main'"))
        $source | Should -Not -Match ([regex]::Escape("@('checkout', 'main'"))
    }
}

Describe 'Publish-XmipPin is given what it needs' {
    It 'is passed -Message everywhere it is called' {
        # The half of the defect a fixture cannot see. Resolve-XmipCommitSubject
        # can be correct and the message still never arrive.
        $source = Get-XmipLandingSource

        [string[]] $calls = @(
            [regex]::Matches($source, 'Publish-XmipPin\s+-RepositoryRoot[^\r\n]*') |
                ForEach-Object { $_.Value }
        )

        $calls.Count | Should -BeGreaterThan 0 -Because 'the pin is called from somewhere'

        foreach ($call in $calls) {
            [string] $because = "this call drops the operator's message: $call"
            $call | Should -Match '-Message' -Because $because
        }
    }
}

Describe 'Sort-XmipModuleDependency' {
    BeforeAll {
        # A three-module estate on disk: c depends on b, b depends on a. The
        # manifests are real Cargo.toml files because the sort reads them with
        # a regex, and a mock would test the mock. c aliases b as `b`, the way
        # a technology names a sibling; the sort read only `xmip` aliases and
        # landed ethercat before ethernet on 2026-09-11.
        $script:Fixture = Join-Path -Path $TestDrive -ChildPath 'sort'

        $modules = @{
            'module/foundation/a' = @'
[package]
name = "xmip-core-a"

[dependencies]
'@
            'module/foundation/b' = @'
[package]
name = "xmip-core-b"

[dependencies]
xmip-a = { package = "xmip-core-a", git = "https://example.invalid/a", branch = "main" }
'@
            'module/foundation/c' = @'
[package]
name = "xmip-core-c"

[dependencies]
b = { package = "xmip-core-b", git = "https://example.invalid/b", branch = "main" }
'@
        }

        foreach ($module in $modules.Keys) {
            $directory = Join-Path $script:Fixture $module
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $directory 'Cargo.toml') -Value $modules[$module]
        }

        $script:Given = @(
            'module/foundation/c'
            'module/foundation/a'
            'module/foundation/b'
        )
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

            $ordered.IndexOf('module/foundation/a') |
                Should -BeLessThan $ordered.IndexOf('module/foundation/b')
            $ordered.IndexOf('module/foundation/b') |
                Should -BeLessThan $ordered.IndexOf('module/foundation/c')
        }
    }

    It 'places a module whose dependency is not in this change set' {
        # Landing only c is ordinary: a and b are already on origin. A sort that
        # waited for them would report a cycle and land nothing.
        InModuleScope Xmip -Parameters @{ Root = $script:Fixture } {
            param($Root)

            [hashtable] $sort = @{ RepositoryRoot = $Root; Module = @('module/foundation/c') }
            $ordered = @(Sort-XmipModuleDependency @sort)

            $ordered | Should -Be @('module/foundation/c')
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

Describe 'Get-XmipDeclaredModule sees nested submodules' {
    BeforeAll {
        # A depth-three estate on disk: the root mounts a capability and a
        # foundation module; the capability mounts a technology of its own. The
        # .gitmodules files are real because the discovery reads them with a
        # regex, and a mock would test the mock. This is the shape that was
        # invisible before — a Technology's path lives in its parent's
        # .gitmodules, never the root's.
        $script:Nest = Join-Path -Path $TestDrive -ChildPath 'nest'

        $files = @{
            '.gitmodules' = @'
[submodule "module/core/capability/contract"]
	path = module/core/capability/contract
	url = https://example.invalid/contract
[submodule "module/foundation/core"]
	path = module/foundation/core
	url = https://example.invalid/core
'@
            'module/core/capability/contract/.gitmodules' = @'
[submodule "xmip-core-contract-csv"]
	path = csv
	url = https://example.invalid/contract-csv
'@
        }

        foreach ($relative in $files.Keys) {
            $target = Join-Path $script:Nest $relative
            New-Item -Path (Split-Path $target) -ItemType Directory -Force | Out-Null
            Set-Content -LiteralPath $target -Value $files[$relative]
        }
    }

    It 'emits the nested module as its full path from the estate root' {
        InModuleScope Xmip -Parameters @{ Root = $script:Nest } {
            param($Root)

            $declared = @(Get-XmipDeclaredModule -RepositoryRoot $Root)

            $declared | Should -Contain 'module/core/capability/contract'
            $declared | Should -Contain 'module/core/capability/contract/csv'
            $declared | Should -Contain 'module/foundation/core'
        }
    }

    It 'places a parent before its child' {
        InModuleScope Xmip -Parameters @{ Root = $script:Nest } {
            param($Root)

            $declared = @(Get-XmipDeclaredModule -RepositoryRoot $Root)

            $declared.IndexOf('module/core/capability/contract') |
                Should -BeLessThan $declared.IndexOf('module/core/capability/contract/csv')
        }
    }

    It 'does not throw over a submodule that mounts nothing' {
        InModuleScope Xmip -Parameters @{ Root = $script:Nest } {
            param($Root)

            # module/foundation/core has no .gitmodules of its own; the ordinary
            # case must be silent, not an error.
            { Get-XmipDeclaredModule -RepositoryRoot $Root } | Should -Not -Throw
        }
    }

    It 'names the nesting parent, and only the parent' {
        InModuleScope Xmip -Parameters @{ Root = $script:Nest } {
            param($Root)

            $parents = @(Get-XmipNestedParent -RepositoryRoot $Root)

            $parents | Should -Be @('module/core/capability/contract')
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
        [string] $script:Source = Get-XmipLandingSource

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
        # produces the unclonable estate this whole Describe is about. Since
        # Push-XmipMain throws when the push fails or origin's main is not the
        # commit, so what is held is that the push goes through it.
        [System.Management.Automation.Language.FunctionDefinitionAst] $function =
            $script:Ast.Find({
                param($node)

                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'Publish-XmipUnpushed'
            }, $true)

        $function | Should -Not -BeNullOrEmpty -Because 'the function has to exist'

        [string] $push = [string] $function.Find({
            param($node)

            $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -eq 'Push-XmipMain'
        }, $true)

        $push | Should -Not -BeNullOrEmpty -Because 'the push runs through Push-XmipMain'
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

AfterAll {
    $env:XMIP_AUDIT_DIRECTORY = $script:AuditBefore
}

Describe 'The dependency tree verifies whole before anything lands' {
    BeforeAll {
        [string] $script:Source = Get-XmipLandingSource

        # An estate of two crates, one with a copy of its manifest in build
        # output that must not be patched in.
        $script:Estate = Join-Path -Path $TestDrive -ChildPath 'estate'
        foreach ($leaf in 'a', 'b') {
            $crate = Join-Path -Path $script:Estate -ChildPath "module/foundation/$leaf"
            $null = New-Item -ItemType Directory -Path $crate -Force
            Set-Content -LiteralPath (Join-Path $crate 'Cargo.toml') -Value @(
                '[package]', "name = `"xmip-core-$leaf`"", 'version = "0.1.0"'
            )
        }

        $copy = Join-Path -Path $script:Estate -ChildPath 'module/foundation/a/target/package/x'
        $null = New-Item -ItemType Directory -Path $copy -Force
        Set-Content -LiteralPath (Join-Path $copy 'Cargo.toml') -Value @(
            '[package]', 'name = "xmip-core-copy"', 'version = "0.1.0"'
        )
    }

    It 'makes every estate crate a member, patched by its folder, and nothing in build output' {
        # ADR-0016, amendment 2026-11-20: one workspace, its [patch] committed.
        [string] $b = Join-Path $script:Estate 'module/foundation/b/Cargo.toml'
        Set-Content -LiteralPath $b -Value @(
            '[package]', 'name = "xmip-core-b"', 'version = "0.1.0"', '[dependencies]',
            ('a = { package = "xmip-core-a", ' +
                'git = "https://github.com/IlleNilsson/xmip-core-a", branch = "main" }'),
            '# x = { git = "https://github.com/IlleNilsson/xmip-core-copy" }'
        )
        Set-Content -LiteralPath (Join-Path $script:Estate 'Cargo.toml') -Value @(
            '[package]', 'name = "xmip"'
        )

        InModuleScope Xmip -Parameters @{ Root = $script:Estate } {
            param($Root)

            $plan = Get-XmipWorkspacePlan -RepositoryRoot $Root

            $plan.Member | Should -Be @('module/foundation/a', 'module/foundation/b')
            @($plan.Patched | ForEach-Object { "$($_.Name)=$($_.Folder)" }) |
                Should -Be @('xmip-core-a=module/foundation/a')
        }
    }

    It 'finds the crates of an estate cloned under another one''s .local-work' {
        # 2026-10-23: the skip matched \.local-work\ anywhere in the path, so a
        # clone under .local-work found no crate of its own and patched none.
        $clone = Join-Path -Path $TestDrive -ChildPath 'outer/.local-work/clone'
        $crate = Join-Path -Path $clone -ChildPath 'module/foundation/c'
        $null = New-Item -ItemType Directory -Path $crate -Force
        Set-Content -LiteralPath (Join-Path $crate 'Cargo.toml') -Value @(
            '[package]', 'name = "xmip-core-c"', 'version = "0.1.0"'
        )
        $run = Join-Path -Path $clone -ChildPath '.local-work/run'
        $null = New-Item -ItemType Directory -Path $run -Force
        Set-Content -LiteralPath (Join-Path $run 'Cargo.toml') -Value @(
            '[package]', 'name = "xmip-core-run"', 'version = "0.1.0"'
        )

        InModuleScope Xmip -Parameters @{ Root = $clone } {
            param($Root)

            [string[]] $names = @(Get-XmipEstateCrate -RepositoryRoot $Root |
                    ForEach-Object -MemberName Name)
            $names | Should -Be @('xmip-core-c')
        }
    }

    It 'walks an estate cloned under another one''s .local-work like any other' {
        # The estate's one walk prunes a working area by the name of a folder
        # it enters, never by the path above where it starts (2026-10-27).
        $clone = Join-Path -Path $TestDrive -ChildPath 'walked/.local-work/clone'
        $crate = Join-Path -Path $clone -ChildPath 'module/foundation/d'
        $null = New-Item -ItemType Directory -Path $crate -Force
        Set-Content -LiteralPath (Join-Path $crate 'Cargo.toml') -Value '[package]'
        $run = Join-Path -Path $clone -ChildPath 'module/foundation/d/.local-work'
        $null = New-Item -ItemType Directory -Path $run -Force
        Set-Content -LiteralPath (Join-Path $run 'Cargo.toml') -Value '[package]'

        InModuleScope Xmip -Parameters @{ Root = $clone } {
            param($Root)

            [string[]] $found = @(
                Find-XmipFile -Path (Join-Path $Root 'module') -Filter 'Cargo.toml' |
                    ForEach-Object { [System.IO.Path]::GetRelativePath($Root, $_.FullName) }
            )
            ($found -replace '\\', '/') | Should -Be @('module/foundation/d/Cargo.toml')
        }
    }

    It 'patches every crate one way: its folder relative to the root, slashes forward' {
        # One committed manifest serves every machine.
        InModuleScope Xmip -Parameters @{ Root = $script:Estate } {
            param($Root)

            foreach ($patched in @((Get-XmipWorkspacePlan -RepositoryRoot $Root).Patched)) {
                [System.IO.Path]::IsPathFullyQualified($patched.Folder) | Should -BeFalse
                $patched.Folder | Should -Not -Match '\\'
            }
        }
    }
    It 'lands only after the verification loop, so a failure pushes nothing' {
        # 2026-10-05, the owner: *Do dependency tree build and stop when a leaf
        # fails*. Before, each module was pushed as soon as it verified, and a
        # failure halfway left the estate half landed.
        [int] $verify = $script:Source.IndexOf('Test-XmipChangeTree @tree')
        [int] $land = $script:Source.IndexOf('Submit-XmipModule -RepositoryRoot')

        $verify | Should -BeGreaterThan 0
        $land | Should -BeGreaterThan $verify
        $script:Source | Should -Match 'Nothing landed this run'
        ([regex]::Matches($script:Source, 'Submit-XmipModule -RepositoryRoot')).Count | Should -Be 1
    }

    It 'builds in the estate''s one shared build directory' {
        [string] $read = '\$sharedTarget = \(Get-XmipEstateLayout -Root \$RepositoryRoot\)\.Build'
        $script:Source | Should -Match $read
        $script:Source | Should -Match '\$env:CARGO_TARGET_DIR = \$sharedTarget'
    }
}

Describe 'A change is checked against what consumes it, and nothing is pushed first' {
    BeforeAll {
        [string] $script:Source = Get-XmipLandingSource
    }

    It 'finds every consumer of a changed module, directly or through others' {
        # a <- b <- c, and d on its own: a change to a reaches b and c.
        $estate = Join-Path -Path $TestDrive -ChildPath 'consumers'
        $manifests = @{
            'module/foundation/a' = @('[package]', 'name = "xmip-core-a"')
            'module/foundation/b' = @('[package]', 'name = "xmip-core-b"', '[dependencies]',
                'xmip-core-a = { git = "x", branch = "main" }')
            'module/foundation/c' = @('[package]', 'name = "xmip-core-c"', '[dependencies]',
                'b = { package = "xmip-core-b", git = "x", branch = "main" }')
            'module/foundation/d' = @('[package]', 'name = "xmip-core-d"')
        }
        foreach ($at in $manifests.Keys) {
            $null = New-Item -ItemType Directory -Path (Join-Path $estate $at) -Force
            Set-Content -LiteralPath (Join-Path $estate "$at/Cargo.toml") -Value $manifests[$at]
        }

        InModuleScope Xmip -Parameters @{ Root = $estate; Every = @($manifests.Keys) } {
            param($Root, $Every)

            Mock Get-XmipDeclaredModule { $Every }

            $found = @(Get-XmipModuleConsumer -RepositoryRoot $Root -Module 'module/foundation/a')
            $found | Sort-Object | Should -Be @('module/foundation/b', 'module/foundation/c')

            @(Get-XmipModuleConsumer -RepositoryRoot $Root -Module 'module/foundation/c').Count |
                Should -Be 0
        }
    }

    It 'spares the consumers of a change that is comments and prose alone' {
        $remote = Join-Path -Path $TestDrive -ChildPath 'commented.git'
        $estate = Join-Path -Path $TestDrive -ChildPath 'commented'
        $module = Join-Path -Path $estate -ChildPath 'module/foundation/a'
        $null = & git init --quiet --bare $remote
        $null = & git clone --quiet $remote $module 2>&1
        $null = New-Item -ItemType Directory -Path (Join-Path $module 'src')
        Set-Content -LiteralPath (Join-Path $module 'src/lib.rs') -Value @(
            '// What it does.', 'pub fn one() -> u8 {', '    1', '}')
        $null = & git -C $module add -A
        $null = & git -C $module -c user.name=x -c user.email=x@example.com commit --quiet -m one
        $null = & git -C $module push --quiet -u origin HEAD 2>&1

        InModuleScope Xmip -Parameters @{ Root = $estate; Path = $module } {
            param($Root, $Path)

            [hashtable] $at = @{ RepositoryRoot = $Root; Module = 'module/foundation/a' }
            [string] $lib = Join-Path $Path 'src/lib.rs'

            Set-Content -LiteralPath $lib -Value @(
                '// What it does, said better.', 'pub fn one() -> u8 {', '    1', '}')
            Set-Content -LiteralPath (Join-Path $Path 'README.md') -Value 'Prose.'
            Test-XmipCodeChange @at | Should -BeFalse

            Set-Content -LiteralPath $lib -Value @(
                '// What it does.', 'pub fn one() -> u8 {', '    2', '}')
            Test-XmipCodeChange @at | Should -BeTrue

            & git -C $Path checkout --quiet -- src/lib.rs
            Set-Content -LiteralPath (Join-Path $Path 'src/two.rs') -Value '// New.'
            Test-XmipCodeChange @at | Should -BeTrue

            Remove-Item -LiteralPath (Join-Path $Path 'src/two.rs')
            [string[]] $who = @('-c', 'user.name=x', '-c', 'user.email=x@example.com')
            $null = & git -C $Path add -A
            $null = & git -C $Path @who commit --quiet -m prose
            Test-XmipCodeChange @at | Should -BeTrue
        }

        [string] $spared = 'Get-XmipModuleConsumer -RepositoryRoot \$RepositoryRoot -Module \$coded'
        $script:Source | Should -Match $spared
    }

    It 'pushes what an interrupted run left only after the tree verified' {
        # The repair path (-Pin) pushes first; a landing pushes after
        # verification, so a failure pushes nothing.
        [int] $verify = $script:Source.IndexOf('Test-XmipChangeTree @tree')
        [int] $late = $script:Source.LastIndexOf('Publish-XmipUnpushed -RepositoryRoot')

        $late | Should -BeGreaterThan $verify
    }

    It 'fails the module whose runtime build failed rather than testing a stale library' {
        [string] $library = 'Build-XmipTestLibrary -RepositoryRoot \$RepositoryRoot ' +
            '-Module \$library\.Folder\)\) \{\s+return \$library\.Folder'
        $script:Source | Should -Match $library
    }

    It 'verifies the platform repository before it pins, a root-only change too' {
        # A root-only change goes through the same verification as any
        # landing, so its test/ runs against the runtime built from the
        # working tree: until 2026-10-13 it called Test-XmipPlatform alone and
        # tested against whatever library a module's target still held.
        [int] $branch = $script:Source.IndexOf('Only the platform repository has changes.')
        [int] $rootOnly = $script:Source.IndexOf('Test-XmipChangeTree @rootOnly', $branch)
        [int] $pin = $script:Source.IndexOf('Publish-XmipPin -RepositoryRoot', $branch)

        $branch | Should -BeGreaterThan 0
        $rootOnly | Should -BeGreaterThan $branch
        $rootOnly | Should -BeLessThan $pin
        $script:Source | Should -Match "Name        = 'Pester'\s+Command     = 'Test-XmipPlatform'"
    }
}

Describe 'A landing says how long it has left' {
    # The owner, 2026-10-13, during a landing that took over an hour: *A
    # timer, letting one know how long it is going to take.*

    It 'records each duration and reads it back for the next landing' {
        InModuleScope Xmip -Parameters @{ Root = $TestDrive } {
            param($Root)

            (Get-XmipVerifyTime -RepositoryRoot $Root).Count | Should -Be 0
            Set-XmipVerifyTime -RepositoryRoot $Root -Name 'Rust' -Duration '00:01:30'
            Set-XmipVerifyTime -RepositoryRoot $Root -Name 'measured' -Duration '00:04:00'

            [hashtable] $read = Get-XmipVerifyTime -RepositoryRoot $Root
            $read['Rust'] | Should -Be ([timespan]::FromSeconds(90))
            $read['measured'] | Should -Be ([timespan]::FromMinutes(4))
        }
    }

    It 'says before the parts how long they and the timing programs took last time' {
        [string] $tree = Get-Content -Raw -LiteralPath (
            Join-Path $script:ModuleRoot 'Test-XmipChangeTree.ps1')

        [int] $read = $tree.IndexOf('Get-XmipVerifyTime -RepositoryRoot $RepositoryRoot')
        [int] $parts = $tree.IndexOf('Invoke-XmipLandingPart -RepositoryRoot')

        $read | Should -BeGreaterThan 0
        $read | Should -BeLessThan $parts
        $tree | Should -Match 'time left unknown: not yet timed'
        $tree | Should -Match "Name = 'measured'; Duration = \`$clock\.Elapsed"
    }
}
Describe 'A landing regenerates the generated documents before it verifies' {
    BeforeAll {
        [string] $script:Change = Get-Content -Raw -LiteralPath (
            Join-Path $script:ModuleRoot 'Publish-XmipChange.ps1')
    }

    It 'saves the estate map and the decision index' {
        [string] $update = Get-Content -Raw -LiteralPath (
            Join-Path $script:ModuleRoot 'Update-XmipGeneratedDocument.ps1')

        $update | Should -Match 'New-XmipEstateMap -Root \$RepositoryRoot -Save'
        $update | Should -Match 'New-XmipDecisionIndex -DecisionRoot \$decision -Save'
    }

    It 'does it before the estate is read and before any verification' {
        # EstateMap.Test.ps1 stopped four landings on 2026-10-13: the map was
        # saved at the pin, after test/ had compared it with the tree.
        [int] $update = $script:Change.IndexOf('Update-XmipGeneratedDocument -RepositoryRoot')
        [int] $read = $script:Change.IndexOf('Get-XmipStatus -RepositoryRoot')

        $update | Should -BeGreaterThan 0
        $update | Should -BeLessThan $read
        $update | Should -BeLessThan $script:Change.IndexOf('Test-XmipChangeTree @')
    }

    It 'does it in one place, not at the pin as well' {
        [string] $source = Get-XmipLandingSource

        ([regex]::Matches($source, 'New-XmipEstateMap -Root')).Count | Should -Be 1
        ([regex]::Matches($source, 'Update-XmipGeneratedDocument -RepositoryRoot')).Count |
            Should -Be 1
    }
}

Describe 'A landing lands on main, and says so only once origin''s main is its commit' {
    It 'refuses a repository on another branch, and takes main or a detached head' {
        [string] $repository = Join-Path $TestDrive 'branched'
        git init -q -b feature $repository
        [string[]] $commit = @(
            '-c', 'user.name=x', '-c', 'user.email=x@example.com',
            'commit', '-q', '--allow-empty', '-m', 'one'
        )
        git -C $repository @commit

        InModuleScope Xmip -Parameters @{ At = $repository } {
            param([string] $At)

            { Assert-XmipLandable -At $At } |
                Should -Throw -ExpectedMessage '*on the branch feature*'
            git -C $At checkout -q -b main
            { Assert-XmipLandable -At $At } | Should -Not -Throw
            git -C $At checkout -q --detach
            { Assert-XmipLandable -At $At } | Should -Not -Throw
        }
    }

    It 'fails a push after which origin''s main is not the commit' {
        InModuleScope Xmip {
            Mock Invoke-XmipGit {
                switch ($Arguments[0]) {
                    'rev-parse' { 'aaaa' }
                    'ls-remote' { "bbbb`trefs/heads/main" }
                }
            }

            { Push-XmipMain -At 'X' } |
                Should -Throw -ExpectedMessage "FAILED:*'bbbb', not this commit, aaaa*"
            Should -Invoke Invoke-XmipGit -ParameterFilter {
                $Arguments[0] -eq 'push' -and $Arguments[2] -eq 'HEAD:refs/heads/main'
            }
        }
    }

    It 'passes a push after which origin''s main is the commit' {
        InModuleScope Xmip {
            Mock Invoke-XmipGit {
                switch ($Arguments[0]) {
                    'rev-parse' { 'aaaa' }
                    'ls-remote' { "aaaa`trefs/heads/main" }
                }
            }

            { Push-XmipMain -At 'X' } | Should -Not -Throw
        }
    }
}
