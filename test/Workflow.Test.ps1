#requires -PSEdition Core
#requires -Version 7.7.0

<#
    ADR-0016, amendment 2026-11-27: a module builds only inside the estate
    and takes what every crate shares from the root, so the one file of the
    estate's own each module repository keeps is its workflow,
    .github/workflows/verify.yml: GitHub runs a workflow only from the
    repository's own folder. Each is its template's, byte for byte, as
    Sync-XmipEstate -Workflow writes it (Write-XmipWorkflow); the two that
    verify a second language beside the crate are their own, and call the
    template's shared workflow for the crate as it does.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    $script:Plan = @(
        InModuleScope Xmip -Parameters @{ Root = $script:Root } {
            param($Root)
            Get-XmipWorkflowPlan -RepositoryRoot $Root
        }
    )
}

Describe 'A module''s workflow is its template''s' {
    It 'holds every module''s workflow identical to its template' {
        [string[]] $differing = @(
            $script:Plan |
                Where-Object {
                    [byte[]] $held = [IO.File]::ReadAllBytes((Join-Path $script:Root $_.Path))
                    [byte[]] $made = [IO.File]::ReadAllBytes((Join-Path $script:Root $_.Template))
                    -not [System.Linq.Enumerable]::SequenceEqual($held, $made)
                } |
                ForEach-Object { $_.Path }
        )

        Write-Host "  $($script:Plan.Count) module workflows, each its template's."
        $script:Plan.Count | Should -BeGreaterThan 200
        $differing | Should -BeNullOrEmpty -Because (
            'Sync-XmipEstate -Workflow writes each from its template; run it')
    }

    It 'verifies the crate of a workflow of its own through the template''s shared workflow' {
        [string] $template = Join-Path $script:Root 'template/rust/.github/workflows/verify.yml'
        [string] $shared = @(Get-Content -LiteralPath $template | Where-Object {
                $_ -match '^\s*uses:'
            })[0].Trim()
        [string[]] $own = @(
            InModuleScope Xmip -Parameters @{ Root = $script:Root } {
                param($Root)
                [string[]] $named = $script:XmipWorkflowOwn
                Get-XmipSubmodule -Root $Root -Recurse |
                    Where-Object -Property Repository -In -Value $named |
                    ForEach-Object { "$($_.Path)/$script:XmipWorkflowPath" }
            }
        )

        $own.Count | Should -Be 2
        foreach ($path in $own) {
            $script:Plan.Path | Should -Not -Contain $path
            Get-Content -LiteralPath (Join-Path $script:Root $path) -Raw |
                Should -Match ([regex]::Escape($shared)) -Because $path
        }
    }

    It 'writes a workflow that differs from its template, and leaves an equal one' {
        # A template and two modules: a's changed by hand, b's its template's.
        [string] $estate = Join-Path $TestDrive 'estate'
        [string] $from = Join-Path $estate 'template/rust/.github/workflows/verify.yml'
        [string] $a = Join-Path $estate 'module/a/.github/workflows/verify.yml'
        [string] $b = Join-Path $estate 'module/b/.github/workflows/verify.yml'

        foreach ($path in $from, $a, $b) {
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
        }

        Set-Content -LiteralPath $from -Value 'name: Verify' -NoNewline
        Set-Content -LiteralPath $a -Value 'name: Mine' -NoNewline
        Copy-Item -LiteralPath $from -Destination $b

        InModuleScope Xmip -Parameters @{ Root = $estate } {
            param($Root)
            Mock Write-XmipStep { }
            Mock Get-XmipWorkflowPlan {
                foreach ($one in 'a', 'b') {
                    [pscustomobject]@{
                        Path     = "module/$one/.github/workflows/verify.yml"
                        Template = 'template/rust/.github/workflows/verify.yml'
                    }
                }
            }

            Write-XmipWorkflow -RepositoryRoot $Root

            # One written, a's; b already was its template's.
            Should -Invoke Write-XmipStep -Times 1 -Exactly
        }

        foreach ($path in $a, $b) {
            Get-Content -LiteralPath $path -Raw | Should -Be 'name: Verify'
        }
    }
}
