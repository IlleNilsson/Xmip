#requires -PSEdition Core
#requires -Version 7.6.5

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

    It 'declares Core and 7.6.5 on every entry point' {
        foreach ($file in $script:EntryPoints) {
            $head = (Get-Content (Join-Path $script:ModuleRoot $file) -TotalCount 3) -join "`n"
            $head | Should -Match '#requires -PSEdition Core'
            $head | Should -Match '#requires -Version 7\.6\.5'
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

    It 'keeps the manifest floor and the #requires floor in step' {
        # The one that drifts silently: prerequisite.toml says 7.6.5 while an
        # entry point still says 7.6, and nothing notices. On 2026-08-27 three
        # documents said 7.6, one said 7.6.3, and an example printed 7.6.5.
        $declared = [string]$script:Prereq.prerequisite.powershell.minimum

        foreach ($file in $script:EntryPoints) {
            $head = (Get-Content (Join-Path $script:ModuleRoot $file) -TotalCount 3) -join "`n"
            [string] $because = "$file must state the same floor as prerequisite.toml"

            $head | Should -Match ([regex]::Escape("#requires -Version $declared")) -Because $because
        }
    }

    It 'tracks channels rather than pinning versions, in every repository' {
        # Every repository, not the root alone. Until 2026-09-22 this read
        # only the root's file, while the Rust template pinned 1.94.1 and 210
        # repositories generated from it carried that pin: rustup takes the
        # nearest file, so each of them built on March's compiler however far
        # stable had moved.
        [string[]] $folders = @('module', 'template', 'test') |
            ForEach-Object { Join-Path $script:Root $_ }
        [object[]] $files = @(
            Get-Item -LiteralPath (Join-Path $script:Root 'rust-toolchain.toml')
            InModuleScope Xmip -Parameters @{ Folders = $folders } {
                param($Folders)
                Find-XmipFile -Path $Folders -Filter 'rust-toolchain.toml'
            }
        )

        [string[]] $pinned = @(
            $files |
                Where-Object {
                    (Get-Content -LiteralPath $_.FullName -Raw) -notmatch 'channel\s*=\s*"stable"'
                } |
                ForEach-Object { [IO.Path]::GetRelativePath($script:Root, $_.FullName) }
        )

        $pinned | Should -BeNullOrEmpty -Because (
            "ADR-0021 forbids a pinned toolchain: $($pinned -join ', ')"
        )
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
        # The owner, 2026-09-23: the Playground had taken test/playground and
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

    It 'mounts what starts a node without a provider and everything else with one' {
        # Checked against the tree rather than the function: a hand-declared
        # mount could still break the rule. What starts a node is
        # module/foundation/ and module/platform/; every other module is
        # module/<provider>/<domain>/; a Playground is test/<provider>/; a
        # template belongs to no provider and stays at template/<language>.
        foreach ($at in @($script:Submodule | ForEach-Object { $_.Path })) {
            [string] $shape = '^(module/(foundation|platform)/[a-z0-9-]+|' +
                'module/(?!foundation/|platform/)[a-z0-9]+/[a-z]+/[a-z0-9-]+|' +
                'test/[a-z0-9]+/playground|template/[a-z]+|sdk)$'
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
