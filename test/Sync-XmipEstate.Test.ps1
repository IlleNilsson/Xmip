#requires -PSEdition Core
#requires -Version 7.7.0

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')
    $script:ModuleRoot = Join-Path $script:Root 'Xmip'

    # Every file that can be dot-sourced or invoked directly, and so must carry
    # its own #requires. Named once because three tests walk the same list.
    [string[]] $script:EntryPoints = @(
        'Xmip.psm1'
        'Sync-XmipEstate.ps1'
        'Sync-XmipRepository.ps1'
        'Install-XmipPrerequisite.ps1'
        'Install-XmipModule.ps1'
        'Publish-XmipChange.ps1'
    )

    # Read once: every test below asks the same manifest.
    $script:Manifest = Get-XmipManifest -Path (Join-Path $script:Root 'architecture.toml')

    # What the estate actually checks out, from .gitmodules rather than from
    # the manifest: the tests that compare the two would pass comparing the
    # manifest with itself while a clone disagreed.
    $script:Submodule = @(
        InModuleScope Xmip -Parameters @{ Root = $script:Root } {
            param($Root)
            Get-XmipSubmodule -Root $Root
        }
    )
}

Describe 'The manifest' {
    It 'is TOML, and the estate expands from it' {
        @($script:Manifest.repositories).Count | Should -BeGreaterThan 200
    }

    It 'names every repository from its position in the tree' {
        # The path is the name: dots become hyphens and nothing else happens.
        @($script:Manifest.repositories | Where-Object { $_.name -notlike 'xmip-*' }).Count |
            Should -Be 0
    }

    It 'gives every repository a domain, a role and a maturity' {
        foreach ($property in 'architecturalDomain', 'repositoryRole', 'maturity') {
            @($script:Manifest.repositories | Where-Object { -not $_.$property }).Count |
                Should -Be 0 -Because "every repository needs $property"
        }
    }

    It 'has no duplicate repository names' {
        $names = @($script:Manifest.repositories.name)
        $names.Count | Should -Be (@($names | Sort-Object -Unique).Count)
    }

    It 'refuses a repository that states no maturity rather than inheriting one' {
        # `reserved` was the [default] until 2026-09-19, so a repository that
        # declared nothing read as deliberately reserved. 156 read that way and
        # 79 of them were composed and holding source — the manifest filed
        # built work as un-started. The reader refuses a silent one now, so
        # reading the manifest above is the check. ADR-0060, amendment
        # 2026-09-19.
        [string] $path = Join-Path $TestDrive 'silent.toml'
        Set-Content -LiteralPath $path -Encoding utf8 -Value @(
            'schemaVersion = "2.0.0"'
            '[xmip.core]'
            'maturity = "scaffolded"'
            '[xmip.core.transport]'
            'description = "Says nothing of how far it is."'
        )

        { Get-XmipManifest -Path $path } | Should -Throw '*xmip-core-transport states no maturity*'
    }
}

Describe 'Sync-XmipEstate' {
    It 'has no -Apply: an operation switch means do it, -WhatIf means do not' {
        $script = Get-Content (Join-Path $script:ModuleRoot 'Sync-XmipEstate.ps1') -Raw
        $script | Should -Not -Match '\$Apply'
        $script | Should -Match '\[switch\] \$Create'
        $script | Should -Match '\[switch\] \$Configure'
    }

    It 'supports ShouldProcess, which is what -WhatIf rides on' {
        $script = Get-Content (Join-Path $script:ModuleRoot 'Sync-XmipEstate.ps1') -Raw
        $script | Should -Match 'SupportsShouldProcess'
    }

    It 'can create one named repository instead of the whole estate' {
        # -Create without -Only makes every missing repository the manifest
        # declares - 200+ with the technology children. Added 2026-08-31 so
        # xmip-core-transport-file could be created without its 200 siblings.
        # -Only, not -Name: the loop-variable gate refused -Name on sight.
        (Get-Command -Name Sync-XmipEstate).Parameters.Keys |
            Should -Contain 'Only' -Because 'creating one repository must not require creating all'
    }

    It 'never issues a DELETE, however the estate drifts' {
        $script = Get-Content (Join-Path $script:ModuleRoot 'Sync-XmipEstate.ps1') -Raw
        # The call site, not the ValidateSet. Invoke-XmipGitHubApi declares DELETE as
        # a legal verb so the helper stays general; what must never appear is
        # anything actually invoking it. Matching the declaration was the first
        # version of this test and it failed on its own scaffolding.
        [string] $never = 'Sync-XmipEstate reconciles; it does not remove repositories'

        $script | Should -Not -Match 'Invoke-XmipGitHubApi\s+DELETE' -Because $never
        $script | Should -Not -Match 'Method\s*=\s*.DELETE.' -Because 'nor by hand'
    }

    It 'does not use remote-tracking submodule updates' {
        # The call site, not the prose. 'submodule.+--remote' matched a comment
        # saying the code never does this, which is the same false positive the
        # DELETE test above was written to avoid. A real use passes --remote as
        # a quoted git argument.
        [string] $because = 'ADR-0016: parents pin commits, they do not track a branch'

        foreach ($file in 'Sync-XmipEstate.ps1', 'Sync-XmipRepository.ps1') {
            $script = Get-Content (Join-Path $script:ModuleRoot $file) -Raw

            $script | Should -Not -Match "'--remote'" -Because $because
            $script | Should -Not -Match '"--remote"' -Because $because
        }
    }
}

Describe 'The module is the entry point' {
    It 'exports both commands and the reader' {
        $exported = (Get-Module Xmip).ExportedFunctions.Keys

        [string[]] $required = @(
            'Sync-XmipEstate'
            'Sync-XmipRepository'
            'Install-XmipPrerequisite'
            'Get-XmipManifest'
        )

        foreach ($name in $required) {
            $exported | Should -Contain $name
        }
    }

    It 'declares Core and the floor on every entry point' {
        foreach ($file in $script:EntryPoints) {
            $head = (Get-Content (Join-Path $script:ModuleRoot $file) -TotalCount 3) -join "`n"
            $head | Should -Match '#requires -PSEdition Core'
            $head | Should -Match '#requires -Version \d+\.\d+\.\d+'
        }
    }
}

Describe 'ADR-0021: current platforms only, enforced' {
    BeforeAll {
        $script:Prereq = InModuleScope Xmip {
            Read-XmipToml -Path (Join-Path (Get-XmipRepositoryRoot) 'prerequisite.toml')
        }
    }

    It 'declares a minimum for every platform the ADR names' {
        foreach ($name in 'powershell', 'dotnet', 'pester', 'git') {
            [string]$script:Prereq.prerequisite.$name.minimum |
                Should -Not -BeNullOrEmpty -Because "ADR-0021 makes $name a floor, not a preference"
        }
    }

    It 'keeps every language toolchain but Rust''s optional' {
        # The owner, 2026-10-20: "every language except Rust is optional" for
        # Xmip itself; Java and Python build only the Event bindings,
        # TypeScript's native compiler only the VS Code extension's shell,
        # and each is verified where it is here and said SKIPPED where it is
        # not. Node.js is no prerequisite at all (2026-10-22). C and C++
        # build with the compiler Rust already requires, the linker entry
        # (ADR-0065, amendment 2026-11-09), so they have no entry of their own.
        foreach ($name in 'java', 'python') {
            [string] $because = "$name builds only what uses it, never the core"

            $script:Prereq.prerequisite.$name.optional | Should -BeTrue -Because $because
        }

        $script:Prereq.prerequisite.Contains('c') | Should -BeFalse -Because (
            'C and C++ build with the compiler Rust requires, prerequisite.linker')

        $script:Prereq.archive.typescript.optional | Should -BeTrue -Because (
            'TypeScript builds only the extension''s shell')
        $script:Prereq.prerequisite.Contains('node') | Should -BeFalse -Because (
            'Node.js is never installed on a developer''s machine; it lives in the CI')
    }

    It 'keeps the manifest floor and the #requires floor in step' {
        # The one that drifts silently: prerequisite.toml says 7.6.7 while an
        # entry point still says 7.6, and nothing notices. On 2026-08-27 three
        # documents said 7.6, one said 7.6.3, and an example printed 7.6.5.
        $declared = [string]$script:Prereq.prerequisite.powershell.minimum

        foreach ($file in $script:EntryPoints) {
            $head = (Get-Content (Join-Path $script:ModuleRoot $file) -TotalCount 3) -join "`n"
            [string] $because = "$file must state the same floor as prerequisite.toml"

            $head | Should -Match ([regex]::Escape("#requires -Version $declared")) -Because $because
        }
    }

    It 'gives every script in the estate that floor, never an older one' {
        # The entry points alone missed nine desired-state scripts that said
        # 7.6 until 2026-11-07, while prerequisite.toml said 7.7.0.
        [string] $declared = [string]$script:Prereq.prerequisite.powershell.minimum
        [string[]] $older = @(
            InModuleScope Xmip -Parameters @{ Root = $script:Root } {
                param($Root)
                foreach ($filter in '*.ps1', '*.psm1') {
                    Find-XmipFile -Path $Root -Filter $filter
                }
            } |
                Select-String -Pattern '^#requires -Version (\S+)' |
                Where-Object { $_.Matches[0].Groups[1].Value -ne $declared } |
                ForEach-Object {
                    "$($_.Path):$($_.LineNumber) says $($_.Matches[0].Groups[1].Value)"
                }
        )

        $older.Count | Should -Be 0 -Because ($older -join "`n")
    }

    It 'tracks the stable channel in the root''s toolchain file, the estate''s one' {
        # Until 2026-09-22 this read only the root's file, while the Rust
        # template pinned 1.94.1 and 210 repositories generated from it
        # carried that pin: rustup takes the nearest file, so each of them
        # built on March's compiler however far stable had moved. Since
        # 2026-11-27 a module builds only inside the estate and carries none
        # (ADR-0016, amendment 2026-11-27), so the nearest is the root's.
        [string[]] $folders = @('module', 'template', 'test', 'sdk') |
            ForEach-Object { Join-Path $script:Root $_ }
        [string[]] $other = @(
            InModuleScope Xmip -Parameters @{ Folders = $folders } {
                param($Folders)
                Find-XmipFile -Path $Folders -Filter 'rust-toolchain.toml'
            } |
                ForEach-Object { [IO.Path]::GetRelativePath($script:Root, $_.FullName) }
        )
        [string] $toolchain = Join-Path -Path $script:Root -ChildPath 'rust-toolchain.toml'

        [string] $root = Get-Content -LiteralPath $toolchain -Raw

        $root | Should -Match '(?m)^channel\s*=\s*"stable"' -Because (
            'ADR-0021 forbids a pinned toolchain')
        $other | Should -BeNullOrEmpty -Because 'the root''s toolchain file is the estate''s one'
    }

    It 'declares the Core edition on every entry point' {
        # Core is the edition PowerShell 7 reports. The requirement is positive
        # — this edition — rather than a statement about any other product.
        # ADR-0021 covers what it consequently rules out.
        foreach ($file in $script:EntryPoints) {
            $head = (Get-Content (Join-Path $script:ModuleRoot $file) -TotalCount 3) -join "`n"
            $head | Should -Match '#requires -PSEdition Core'
        }
    }

    It 'reads whether the channel a toolchain file names is current' {
        # The other half of ADR-0021, and the half nothing looked at: the file
        # says `stable` and rustup resolves it to whatever stable it last
        # installed. On 2026-09-22 that was March's 1.94.1 against 1.98.1.
        InModuleScope Xmip {
            [string] $toolchain = 'stable-x86_64-pc-windows-msvc'
            # One string: a `+` at the end of a line inside an array literal
            # starts another element rather than continuing this one.
            [string] $available = "$toolchain - update available: " +
                '1.94.1 (e408947bf 2026-03-25) -> 1.98.1 (48a229cea 2026-09-01)'
            [string[]] $behind = @('rustup - up to date : 1.29.1', $available)

            $old = Read-XmipRustCheck -Said $behind -Toolchain $toolchain
            $current = Read-XmipRustCheck -Toolchain $toolchain -Said @(
                "$toolchain - up to date: 1.98.1 (48a229cea 2026-09-01)"
            )
            $quiet = @('rustup - up to date : 1.29.1')
            $silent = Read-XmipRustCheck -Said $quiet -Toolchain $toolchain

            $old.Current | Should -Be '1.94.1'
            $old.Latest | Should -Be '1.98.1'
            $old.Unverifiable | Should -BeFalse
            $current.Current | Should -Be '1.98.1'
            $current.Latest | Should -BeNullOrEmpty
            $silent.Unverifiable | Should -BeTrue
        }
    }

    It 'holds a preview floor by its preview, a release above every preview of it' {
        # Previews are adopted until the first Linear release (CONTRIBUTING),
        # and DSC's floor is 3.4.0-preview.3: [version] reads none of it.
        [hashtable] $judged = InModuleScope Xmip {
            [hashtable] $said = @{}
            foreach ($found in 'dsc 3.4.0-preview.2', 'dsc 3.4.0-preview.3',
                'dsc 3.4.0-preview.10', 'dsc 3.4.0', 'dsc 3.3.0') {
                $said[$found] = Test-XmipFloor -Name 'dsc' -Found $found -Minimum '3.4.0-preview.3'
            }
            $said
        }

        $judged['dsc 3.4.0-preview.2'] | Should -BeFalse
        $judged['dsc 3.4.0-preview.3'] | Should -BeTrue
        $judged['dsc 3.4.0-preview.10'] | Should -BeTrue
        $judged['dsc 3.4.0'] | Should -BeTrue
        $judged['dsc 3.3.0'] | Should -BeFalse
    }

    It 'holds a release floor above every preview of that release' {
        # .NET's floor became 11.0.100 on 2026-11-12, and its release
        # candidate reads 11.0.100 in numbers alone.
        [hashtable] $judged = InModuleScope Xmip {
            [hashtable] $said = @{}
            foreach ($found in '11.0.100-rc.3.26522.148', '11.0.100', '11.0.101', '11.0.99') {
                $said[$found] = Test-XmipFloor -Name 'dotnet' -Found $found -Minimum '11.0.100'
            }
            [string] $git = 'git version 2.56.0.windows.1'
            $said[$git] = Test-XmipFloor -Name 'git' -Found $git -Minimum '2.56.0'
            $said
        }

        $judged['11.0.100-rc.3.26522.148'] | Should -BeFalse
        $judged['11.0.100'] | Should -BeTrue
        $judged['11.0.101'] | Should -BeTrue
        $judged['11.0.99'] | Should -BeFalse
        $judged['git version 2.56.0.windows.1'] | Should -BeTrue
    }

    It 'fails rather than reports when a floor is not met' {
        $script = Get-Content (Join-Path $script:ModuleRoot 'Install-XmipPrerequisite.ps1') -Raw
        $script | Should -Match 'Write-Error' -Because 'an unmet floor must be an error, not a warning'
        $script | Should -Match "'outdated'" -Because 'a version below the floor needs its own status'
    }
}

Describe 'The estate is more than its modules' {
    BeforeAll {
        $script:Template = $script:Manifest.crate.template
        $script:Mounted = @($script:Submodule | ForEach-Object { $_.Repository })
    }

    It 'declares a template for every language a module can be written in' {
        # The defect this catches, on 2026-08-27: crate.template was one string
        # naming xmip-template, which had been renamed to xmip-template-rust
        # that morning. Repository creation posted to a URL that 404s, and the
        # drift check exempted a name nothing has while reporting both real
        # templates as unexpected.
        $templates = $script:Template

        $templates | Should -Not -BeNullOrEmpty
        $templates.Keys | Should -Contain 'rust'
        $templates.Keys | Should -Contain 'dotnet'
    }

    It 'names every template as owner/name' {
        foreach ($language in $script:Template.Keys) {
            [string] $name = $script:Template.$language

            $name | Should -Match '^[^/]+/[^/]+$' -Because "$language must be owner/name"
        }
    }

    It 'gives every repository a mount point of its own' {
        # Raised on 2026-08-29: mount names are the last segment of the
        # repository name, and the estate declares `file` four times, `sql` four
        # times and `party` four times. It looks like a collision waiting for
        # the protocol and contract modules to arrive.
        #
        # It is not, because a depth-three module mounts inside its parent
        # capability's repository rather than inside Xmip — `module/file` in
        # xmip-core-transport and `module/file` in xmip-core-audit are two
        # paths in two repositories. The leaf namespace is per-parent.
        #
        # Nothing guaranteed that. It held for 334 repositories by construction
        # and by luck in equal measure, and the construction is invisible in the
        # tree, which is why it was reported as a bug by someone reading the
        # tree. This is the guarantee.
        $manifest = $script:Manifest

        $mounts = & (Get-Module Xmip) {
            param($Repositories, $Declared)

            foreach ($repository in $Repositories) {
                $path = Get-XmipMountPath -Repository $repository -Declared $Declared

                [pscustomobject]@{
                    Name = $repository.name
                    At   = "$($path.Owner)/$($path.Mount)"
                }
            }
        } $manifest.repositories @($manifest.repositories.name)

        $shared = @($mounts | Group-Object At | Where-Object Count -gt 1)

        [string] $detail = (
            $shared | ForEach-Object { "$($_.Name): $($_.Group.Name -join ', ')" }
        ) -join "`n"

        $shared.Count | Should -Be 0 -Because "two repositories cannot share one mount:`n$detail"
    }

    It 'leaves a provider other than core a subtree of its own' {
        # The owner, 2026-09-23: the System Tests had taken test/system-test and
        # left nowhere for anyone else's; what starts a node carries no
        # provider, everything else does, provider before purpose. Read as one
        # rule, foundation went under core; the owner, 2026-09-24: *Do you think
        # core is not needed to start Xmip?* Both halves are held here.
        $mount = & (Get-Module Xmip) {
            param($Repositories)

            [string[]] $declared = @('xmip-example-transport')

            foreach ($repository in $Repositories) {
                $path = Get-XmipMountPath -Repository $repository -Declared $declared

                [pscustomobject]@{ Name = $repository.name; At = $path.Mount; In = $path.Owner }
            }
        } @(
            [pscustomobject]@{ name = 'xmip-core-transport'; architecturalDomain = 'Capability' }
            [pscustomobject]@{ name = 'xmip-example-transport'; architecturalDomain = 'Capability' }
            [pscustomobject]@{
                name                = 'xmip-example-transport-kafka'
                architecturalDomain = 'Capability'
            }
            [pscustomobject]@{ name = 'xmip-core-node'; architecturalDomain = 'Foundation' }
            [pscustomobject]@{ name = 'xmip-core-runtime'; architecturalDomain = 'Platform' }
        )

        $mount[0].At | Should -Be 'module/core/capability/transport'
        $mount[1].At | Should -Be 'module/example/capability/transport'
        $mount[2].In | Should -Be 'xmip-example-transport'
        $mount[2].At | Should -Be 'kafka'
        $mount[3].At | Should -Be 'module/foundation/node'
        $mount[4].At | Should -Be 'module/platform/runtime'
    }

    It 'mounts an Example at example/<leaf> by its domain, owned by no module it names' {
        # ADR-0016, amendment 2026-11-28: an example is no part of Xmip and no
        # module, so its name beginning with xmip-core-contract makes it no
        # technology of the contract capability.
        $mount = & (Get-Module Xmip) {
            param($Repositories)

            [string[]] $declared = @('xmip-core-contract', 'xmip-core-contract-c_cpp')

            foreach ($repository in $Repositories) {
                Get-XmipMountPath -Repository $repository -Declared $declared
            }
        } @(
            [pscustomobject]@{ name = 'xmip-core-contract-c_cpp'; architecturalDomain = 'Example' }
            [pscustomobject]@{ name = 'xmip-core-contract-csv'; architecturalDomain = 'Technology' }
        )

        $mount[0].Owner | Should -BeNullOrEmpty
        $mount[0].Mount | Should -Be 'example/contract-c_cpp'
        $mount[1].Owner | Should -Be 'xmip-core-contract'
        $mount[1].Mount | Should -Be 'csv'
    }

    It 'admits an underscore joining two words in a name''s segment, and no other new mark' {
        # The owner named xmip-core-contract-c_cpp, one segment for C and C++
        # (ADR-0016, amendment 2026-11-28).
        InModuleScope Xmip {
            [string[]] $declared = @('xmip-core')
            $known = [Collections.Generic.HashSet[string]]::new($declared)

            foreach ($name in 'xmip-core-contract-c_cpp', 'xmip-core-c__cpp', 'xmip-core-_c',
                'xmip-core-c_') {
                [hashtable] $asked = @{
                    Repository               = [pscustomobject]@{
                        name         = $name
                        description  = 'Named for the test.'
                        maturity     = 'reserved'
                        primaryCrate = [pscustomobject]@{ name = $name }
                    }
                    KnownNames               = $known
                    CrateMustMatchRepository = $true
                }
                [scriptblock] $judged = { Assert-XmipRepositoryEntry @asked }

                if ($name -eq 'xmip-core-contract-c_cpp') {
                    $judged | Should -Not -Throw
                }
                else {
                    $judged | Should -Throw "Invalid repository name: $name"
                }
            }
        }
    }

    It 'mounts what starts a node without a provider and everything else with one' {
        # Checked against the tree rather than the function: a hand-declared
        # mount could still break the rule. What starts a node is
        # module/foundation/ and module/platform/; every other module is
        # module/<provider>/<domain>/; what exercises a provider's work is
        # test/<provider>/; a template belongs to no provider and stays at
        # template/<language>, and an example, no module, at example/<leaf>
        # (ADR-0016, amendment 2026-11-28).
        foreach ($at in @($script:Submodule | ForEach-Object { $_.Path })) {
            [string] $shape = '^(module/(foundation|platform)/[a-z0-9-]+|' +
                'module/(?!foundation/|platform/)[a-z0-9]+/[a-z]+/[a-z0-9-]+|' +
                'test/[a-z0-9]+/[a-z0-9-]+|template/[a-z]+|example/[a-z0-9_-]+|sdk)$'
            $at | Should -Match $shape -Because "$at is where a submodule mounts"
        }
    }

    It 'mounts nothing the manifest does not declare' {
        # The other direction, and the reason the first was survivable for two
        # days: a submodule is only visible to somebody who lists them, and the
        # estate is dozens of them.
        [string[]] $declared = @($script:Manifest.repositories.name) + @(
            $script:Template.Values |
                ForEach-Object { ($_ -split '/')[-1] }
        )

        foreach ($name in $script:Mounted) {
            $declared | Should -Contain $name -Because "$name is checked out and nothing declares it"
        }
    }
}

Describe 'What the manifest tells GitHub' {
    # GitHub refuses a description over 350 characters; three were written
    # longer on 2026-09-24 and found only when -Configure stopped on one.
    It 'gives every repository a description GitHub takes' {
        [string[]] $long = @($script:Manifest.repositories |
                Where-Object { "$($_.description)".Length -gt 350 } |
                ForEach-Object { "$($_.name) ($("$($_.description)".Length))" })

        $long | Should -BeNullOrEmpty
    }
}

Describe 'Whether GitHub has a repository' {
    # A renamed repository keeps its old name as a redirect, and the request
    # follows it: xmip-core-transport-mysql answered as xmip-core-transport-mariadb
    # after the rename of 2026-10-12, and -Create would have skipped a name that
    # was free (found 2026-10-14).
    It 'reads a name that only redirects to another repository as free' {
        InModuleScope Xmip {
            Mock Invoke-XmipGitHubApi { [pscustomobject]@{ name = 'xmip-renamed' } }
            [hashtable] $asked = @{ Owner = 'example'; GitHub = @{ Token = 'token' } }

            (Test-XmipGitHubRepository @asked -Name 'xmip-old').Exists | Should -BeFalse
            (Test-XmipGitHubRepository @asked -Name 'xmip-renamed').Exists | Should -BeTrue
        }
    }
}

Describe 'Configuring repositories' {
    # -Only was ignored here, so creating two repositories reconfigured all of
    # them, and GitHub's 350-character limit refused a description after the
    # ones before it had changed (found 2026-09-24).
    It 'configures only what -Only names, and judges every description first' {
        InModuleScope Xmip {
            Mock Invoke-XmipGitHubApi { }
            Mock Write-XmipStep { }
            $manifest = [pscustomobject]@{
                owner        = 'example'
                repositories = @(
                    [pscustomobject]@{ name = 'xmip-a'; description = 'short' }
                    [pscustomobject]@{ name = 'xmip-b'; description = 'short' }
                    [pscustomobject]@{ name = 'xmip-long'; description = 'x' * 351 }
                )
            }
            $github = @{ Token = 'token' }
            $report = [ordered]@{ missing = @(); operations = @{ configured = 0; skipped = 0 } }
            [hashtable] $estate = @{ Manifest = $manifest; Report = $report; GitHub = $github }

            Set-XmipRepository @estate -Only 'xmip-b'
            Should -Invoke Invoke-XmipGitHubApi -Times 1 -Exactly
            $report.operations.configured | Should -Be 1

            { Set-XmipRepository @estate -Only 'xmip-z' } | Should -Throw '*not declared*'
            { Set-XmipRepository @estate } | Should -Throw '*350 characters*xmip-long*'
        }
    }
}

Describe 'The estate is one Cargo workspace, its root holding every crate' {
    # ADR-0016, amendment 2026-11-20: a crate on disk the root does not list
    # builds in no workspace. ADR-0005, amendment 2026-11-28: an estate crate
    # depends on another by path, through the root's [workspace.dependencies];
    # one named by its git URL made cargo read that crate's manifest from
    # GitHub wherever the lock did not already hold the edge, and that
    # manifest, inheriting from a root it is not under, did not resolve.
    BeforeAll {
        $script:Plan = InModuleScope Xmip -Parameters @{ Root = $script:Root } {
            param($Root)
            Get-XmipWorkspacePlan -RepositoryRoot $Root
        }
        [string] $script:Manifest = Join-Path $script:Root 'Cargo.toml'
        [string] $text = Get-Content -LiteralPath $script:Manifest -Raw
        [string] $members = [regex]::Match($text, '(?ms)^members = \[\s*$(.*?)^\]').Groups[1].Value
        $script:Members = @([regex]::Matches($members, '"([^"]+)"') | ForEach-Object {
                $_.Groups[1].Value
            })
        $script:Entry = @(
            InModuleScope Xmip -Parameters @{ Manifest = $script:Manifest } {
                param($Manifest)
                Read-XmipCargoDependency -Path $Manifest |
                    Where-Object { $_.Table -eq 'workspace.dependencies' }
            }
        )
        $script:Mounted = InModuleScope Xmip -Parameters @{ Root = $script:Root } {
            param($Root)
            Get-XmipMountedPath -Root $Root -Recurse
        }
        [string] $script:Run = 'Sync-XmipEstate -Cargo writes them (Update-XmipWorkspace); run it'
    }

    It 'lists every crate on disk as a member, and nothing else' {
        $script:Plan.Member.Count | Should -BeGreaterThan 200
        $script:Members | Should -Be @($script:Plan.Member) -Because $script:Run
    }

    It 'names no estate crate by a git source in any member, and patches none' {
        [string] $source = 'git\s*=\s*"https://github\.com/IlleNilsson/'
        [string[]] $named = @(
            foreach ($folder in @('.') + @($script:Plan.Member)) {
                [string] $path = Join-Path (Join-Path $script:Root $folder) 'Cargo.toml'
                Select-String -LiteralPath $path -Pattern $source |
                    Where-Object { -not $_.Line.TrimStart().StartsWith('#') } |
                    ForEach-Object { "${folder}/Cargo.toml:$($_.LineNumber)" }
            }
        )

        $named | Should -BeNullOrEmpty -Because (
            "an estate crate is taken from the root's [workspace.dependencies]; $script:Run")
        Get-Content -LiteralPath $script:Manifest -Raw |
            Should -Not -Match '(?m)^\[patch\."https://github\.com/IlleNilsson/'
        @($script:Plan.Edge).Count | Should -Be 0 -Because $script:Run
    }

    It 'holds one entry for each key members name an estate crate by, at its mount' {
        [string[]] $planned = @($script:Plan.Dependency | ForEach-Object {
                "$($_.Key)=$($_.Package)@$($_.Path)"
            })
        [string[]] $held = @(
            InModuleScope Xmip -Parameters @{ Entry = $script:Entry; Mount = $script:Plan.Mount } {
                param($Entry, $Mount)
                [hashtable] $none = @{}

                foreach ($each in $Entry) {
                    [hashtable] $named = @{ Key = $each.Key; Pair = $each.Pair; Workspace = $none }
                    [string] $package = Resolve-XmipCargoPackage @named
                    [string] $path = Get-XmipCargoValue -Pair $each.Pair -Name 'path'

                    if ($Mount.ContainsKey($package)) {
                        "$($each.Key)=$package@$path"
                    }
                }
            }
        )

        $planned.Count | Should -BeGreaterThan 300
        $held | Should -Be $planned -Because $script:Run
    }

    It 'gives each estate entry the path its package is mounted at, and one package a key' {
        [string[]] $wrong = @(
            foreach ($key in $script:Plan.Dependency) {
                [string] $manifest = Join-Path (Join-Path $script:Root $key.Path) 'Cargo.toml'
                [string] $name = [regex]::Match(
                    (Get-Content -LiteralPath $manifest -Raw),
                    '(?ms)^\[package\][^\[]*?^name\s*=\s*"([^"]+)"').Groups[1].Value

                if ($name -cne $key.Package) {
                    "$($key.Key): $($key.Path) holds $name, not $($key.Package)"
                }

                if ($script:Mounted.ContainsKey($key.Package) -and
                    $script:Mounted[$key.Package] -cne $key.Path) {
                    "$($key.Key): $($key.Path), and .gitmodules mounts it at " +
                        $script:Mounted[$key.Package]
                }
            }
        )
        [string[]] $keys = @($script:Plan.Dependency | ForEach-Object { $_.Key })

        $wrong | Should -BeNullOrEmpty
        $keys.Count | Should -Be @($keys | Sort-Object -Unique -CaseSensitive).Count
    }
}

Describe 'Update-XmipWorkspace turns an estate crate named by its git URL into the workspace''s' {
    # ADR-0005, amendment 2026-11-28: it is run again over a merged tree, so
    # it converts whatever git-form edge it finds, keeps optional, features
    # and a member's default features turned off, deletes the [patch], and a
    # second run writes nothing.
    BeforeAll {
        [string] $script:Estate = Join-Path $TestDrive 'converted'
        [string] $source = 'git = "https://github.com/IlleNilsson/xmip-core-'
        [hashtable] $files = @{
            'Cargo.toml'                     = @(
                '[workspace]', 'members = [', ']', '', '[package]', 'name = "xmip"', '',
                '[dependencies]'
                ('a = { package = "xmip-core-a", ' + $source + 'a", branch = "main", ' +
                    'default-features = false, features = ["x"] }')
                'serde = "1"', '', '# The estate crates, patched.'
                '[patch."https://github.com/IlleNilsson/xmip-core-a"]'
                'xmip-core-a = { path = "module/foundation/a" }'
                '[patch."https://github.com/IlleNilsson/xmip-core-b"]'
                'xmip-core-b = { path = "module/foundation/b" }'
            )
            'module/foundation/a/Cargo.toml' = @('[package]', 'name = "xmip-core-a"')
            'module/foundation/b/Cargo.toml' = @(
                '[package]', 'name = "xmip-core-b"', '', '[dependencies]'
                ('a = { package = "xmip-core-a", ' + $source + 'a", branch = "main", ' +
                    'optional = true }  # kept')
            )
            'module/foundation/c/Cargo.toml' = @(
                '[package]', 'name = "xmip-core-c"', '', '[dependencies]'
                ('xmip-core-b = { ' + $source + 'b", branch = "main" }'), '',
                '[dev-dependencies]'
                ('a = { package = "xmip-core-a", ' + $source + 'a", features = ["test-support"] }')
            )
        }

        foreach ($file in $files.Keys) {
            [string] $path = Join-Path $script:Estate $file
            $null = New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force
            Set-Content -LiteralPath $path -Value $files[$file]
        }

        InModuleScope Xmip -Parameters @{ Root = $script:Estate } {
            param($Root)
            Mock Write-Host { }
            Mock Write-XmipStep { }
            Update-XmipWorkspace -RepositoryRoot $Root
        }

        [scriptblock] $script:Read = {
            param([string] $Path)
            Get-Content -LiteralPath (Join-Path $script:Estate $Path)
        }
    }

    It 'writes the root''s members and one entry a key, at its folder, and no [patch]' {
        [string[]] $root = @(& $script:Read 'Cargo.toml')

        $root | Should -Contain '    "module/foundation/c",'
        $root | Should -Contain 'a = { package = "xmip-core-a", path = "module/foundation/a" }'
        $root | Should -Contain 'xmip-core-b = { path = "module/foundation/b" }'
        [string] $off = 'default-features = false'
        $root | Should -Contain "a = { workspace = true, $off, features = [`"x`"] }"
        $root | Should -Contain 'serde = "1"'
        ($root -join "`n") | Should -Not -Match '\[patch|patched'
    }

    It 'keeps each member''s optional, features, default features and comment' {
        & $script:Read 'module/foundation/b/Cargo.toml' |
            Should -Contain 'a = { workspace = true, optional = true }  # kept'
        [string[]] $c = @(& $script:Read 'module/foundation/c/Cargo.toml')
        $c | Should -Contain 'xmip-core-b = { workspace = true }'
        $c | Should -Contain 'a = { workspace = true, features = ["test-support"] }'
    }

    It 'writes nothing on a second run' {
        [scriptblock] $hashed = {
            Get-ChildItem -LiteralPath $script:Estate -Recurse -File |
                ForEach-Object { "$($_.FullName)=$((Get-FileHash -LiteralPath $_.FullName).Hash)" }
        }
        [string[]] $before = @(& $hashed)

        InModuleScope Xmip -Parameters @{ Root = $script:Estate } {
            param($Root)
            Mock Write-Host { }
            Mock Write-XmipStep { }
            Update-XmipWorkspace -RepositoryRoot $Root
            Should -Invoke Write-XmipStep -Times 0 -Exactly
        }

        @(& $hashed) | Should -Be $before
    }

    It 'refuses a key that names two packages, naming where' {
        [string] $clash = Join-Path $TestDrive 'clash'
        foreach ($leaf in 'a', 'b', 'c') {
            [string] $at = Join-Path $clash "module/foundation/$leaf"
            $null = New-Item -ItemType Directory -Path $at -Force
            [string[]] $text = @('[package]', "name = `"xmip-core-$leaf`"", '[dependencies]')
            if ($leaf -ne 'a') {
                [string] $other = if ($leaf -eq 'b') { 'a' } else { 'b' }
                $text += "shape = { package = `"xmip-core-$other`", git = `"x`" }"
            }
            Set-Content -LiteralPath (Join-Path $at 'Cargo.toml') -Value $text
        }
        Set-Content -LiteralPath (Join-Path $clash 'Cargo.toml') -Value '[package]', 'name = "xmip"'

        InModuleScope Xmip -Parameters @{ Root = $clash } {
            param($Root)
            { Get-XmipWorkspacePlan -RepositoryRoot $Root } |
                Should -Throw -ExpectedMessage '*key shape names xmip-core-a in*xmip-core-b in*'
        }
    }
}