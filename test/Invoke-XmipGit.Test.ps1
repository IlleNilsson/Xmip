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
    $script:Root = Join-Path $PSScriptRoot '..'
    Import-Module (Join-Path $script:Root 'Xmip/Xmip.psd1') -Force

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
