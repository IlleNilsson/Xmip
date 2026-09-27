#requires -PSEdition Core
#requires -Version 7.6.5

<#
    The module ran git five ways until 2026-09-23, and the written-out calls
    checked the exit code where someone remembered to. Publish-XmipPin did not
    after a commit, so a failed commit followed by an empty push reported the
    estate pinned (open-problems.md, problem 25, row l). These hold the one
    way to its promise, and hold every other file to the one way.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    [string] $script:Repository = Join-Path $TestDrive 'repository'
    New-Item -ItemType Directory -Path $script:Repository | Out-Null

    & (Get-Module Xmip) {
        param($At)

        Invoke-XmipGit -At $At -Arguments @('init', '--quiet') | Out-Null
    } $script:Repository
}

Describe 'Invoke-XmipGit' {
    It 'returns what git wrote to standard output' {
        $said = & (Get-Module Xmip) {
            param($At)

            Invoke-XmipGit -At $At -Arguments @('rev-parse', '--is-inside-work-tree')
        } $script:Repository

        $said | Should -Be 'true'
    }

    It 'throws on a failure, naming the command and where it ran' {
        {
            & (Get-Module Xmip) {
                param($At)

                Invoke-XmipGit -At $At -Arguments @('rev-parse', '--verify', 'no-such-ref')
            } $script:Repository
        } | Should -Throw -ExpectedMessage "*git rev-parse --verify no-such-ref in*failed*"
    }

    It 'answers a question with -Test and throws nothing' {
        $answers = & (Get-Module Xmip) {
            param($At)

            Invoke-XmipGit -At $At -Arguments @('rev-parse', '--verify', 'no-such-ref') -Test
            Invoke-XmipGit -At $At -Arguments @('rev-parse', '--is-inside-work-tree') -Test
        } $script:Repository

        $answers | Should -Be @($false, $true)
    }

    It 'is the only place the module runs git' {
        [string] $module = Join-Path $script:Root 'Xmip'
        [string[]] $callers = @(
            Get-ChildItem -Path $module -Recurse -Include '*.ps1', '*.psm1' |
                Where-Object Name -ne 'Invoke-XmipGit.ps1' |
                ForEach-Object {
                    [string] $file = $_.Name
                    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                        $_.FullName, [ref] $null, [ref] $null)

                    $ast.FindAll({
                            param($node)

                            $node -is [System.Management.Automation.Language.CommandAst] -and
                                $node.GetCommandName() -eq 'git'
                        }, $true) |
                        ForEach-Object { "${file}:$($_.Extent.StartLineNumber)" }
                }
        )

        $callers | Should -BeNullOrEmpty -Because 'git runs through Invoke-XmipGit'
    }
}

Describe 'What git says of a repository, read once' {
    BeforeAll {
        # An origin of its own, bare, in this run's drive: nothing here ever
        # reaches a real remote.
        [string] $script:Origin = Join-Path $TestDrive 'origin.git'
        [string] $script:Clone = Join-Path $TestDrive 'clone'

        & (Get-Module Xmip) {
            param($Origin, $Clone)

            Invoke-XmipGit -Arguments @('init', '--bare', '--quiet', '-b', 'main', $Origin) |
                Out-Null
            Invoke-XmipGit -Arguments @('clone', '--quiet', $Origin, $Clone) 2>$null | Out-Null

            foreach ($setting in @(
                    @('config', 'user.name', 'Xmip test'),
                    @('config', 'user.email', 'test@example.invalid'),
                    @('checkout', '--quiet', '-b', 'main'),
                    @('config', 'branch.main.remote', 'origin'),
                    @('config', 'branch.main.merge', 'refs/heads/main'))) {
                Invoke-XmipGit -At $Clone -Arguments $setting | Out-Null
            }
        } $script:Origin $script:Clone
    }

    It 'commits and pushes what is staged, and does nothing when nothing is' {
        Set-Content -LiteralPath (Join-Path $script:Clone 'first.txt') -Value 'first'

        $landed = & (Get-Module Xmip) {
            param($At)

            @(Submit-XmipRepositoryChange -At $At -Message 'First' 6>$null)
            @(Submit-XmipRepositoryChange -At $At -Message 'Nothing' 6>$null).Count
        } $script:Clone

        $landed[0] | Should -Be 'first.txt'
        $landed[-1] | Should -Be 0

        & (Get-Module Xmip) {
            param($Origin)

            Invoke-XmipGit -At $Origin -Arguments @('log', '-1', '--format=%s', 'main')
        } $script:Origin | Should -Be 'First'
    }

    It 'reads the branch, its upstream, how far ahead and every changed path' {
        Set-Content -LiteralPath (Join-Path $script:Clone 'first.txt') -Value 'changed'
        Set-Content -LiteralPath (Join-Path $script:Clone 'new file.txt') -Value 'new'

        $status = & (Get-Module Xmip) {
            param($At)

            Invoke-XmipGit -At $At -Arguments @('commit', '--quiet', '-am', 'Ahead') | Out-Null
            Set-Content -LiteralPath (Join-Path $At 'first.txt') -Value 'again'
            Get-XmipRepositoryStatus -At $At
        } $script:Clone

        $status.Branch | Should -Be 'main'
        $status.Detached | Should -BeFalse
        $status.HasUpstream | Should -BeTrue
        $status.AheadBy | Should -Be 1
        $status.BehindBy | Should -Be 0
        $status.Changed | Should -Be 1
        $status.Untracked | Should -Be 1
        @($status.Entry | ForEach-Object { "$($_.State)|$($_.Path)" }) |
            Should -Be @(' M|first.txt', '??|new file.txt')
    }
}

Describe 'What a working tree mounts, read once' {
    It 'reads .gitmodules through git, nested submodules joined to their parent' {
        [string] $tree = Join-Path $TestDrive 'mounts'
        New-Item -ItemType Directory -Path (Join-Path $tree 'module/core/transport') -Force |
            Out-Null

        Set-Content -LiteralPath (Join-Path $tree '.gitmodules') -Value @(
            '[submodule "modules/transport"]'
            '    path = module/core/transport'
            '    url = https://github.com/example/xmip-core-transport.git'
        )
        Set-Content -LiteralPath (Join-Path $tree 'module/core/transport/.gitmodules') -Value @(
            '[submodule "file"]'
            '    path = file'
            '    url = https://github.com/example/xmip-core-transport-file'
        )

        $mounted = & (Get-Module Xmip) {
            param($Root)

            @(Get-XmipSubmodule -Root $Root -Recurse)
        } $tree

        @($mounted.Path) | Should -Be @('module/core/transport', 'module/core/transport/file')
        @($mounted.Repository) | Should -Be @('xmip-core-transport', 'xmip-core-transport-file')
        $mounted[0].Name | Should -Be 'modules/transport'
    }
}
