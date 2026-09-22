#requires -PSEdition Core
#requires -Version 7.6.5

<#
    The manifest says what each repository depends on, and until 2026-09-22 it
    said something else from what the builds did: generated side by side, the
    two disagreed for most modules — `runtime` used sixteen estate crates and
    declared six, `receive` used three it never declared, the Playground used
    a hundred and twenty-three and declared five. A declaration nobody checks
    is a guess that was right once. The owner asked for the estate to be
    consolidated; the first thing consolidated was the record of what uses
    what.

    For every mounted repository the manifest's `dependency` list, with the
    parent a technology's place in the tree implies set aside, is exactly what
    its build uses: its `Cargo.toml` `[dependencies]` and its non-test .NET
    project references (`Get-XmipEstateRepository`, `Uses`). An unmounted
    repository has no build to compare, and its list stays the plan.

    When this fails, the build changed and the manifest did not. Put the
    repositories it names into `architecture.toml` as it says — the build is
    what is true.
#>

BeforeAll {
    $script:Root = Join-Path $PSScriptRoot '..'

    Import-Module (Join-Path $script:Root 'Xmip/Xmip.psd1') -Force

    $script:Mounted = @(Get-XmipEstateRepository -Root $script:Root | Where-Object Mounted)
}

Describe 'The manifest says what each build uses' {
    It 'lists, for every mounted repository, exactly the estate crates its build uses' {
        [string[]] $drift = @(
            foreach ($repository in $script:Mounted) {
                [string] $parent = $repository.Parent
                [string[]] $said = @($repository.Declared | Where-Object { $_ -and $_ -ne $parent })
                [string[]] $real = @($repository.Uses | Where-Object { $_ -ne $parent })

                [string[]] $add = @($real | Where-Object { $_ -notin $said } | Sort-Object)
                [string[]] $drop = @($said | Where-Object { $_ -notin $real } | Sort-Object)

                if ($add.Count -gt 0 -or $drop.Count -gt 0) {
                    [string] $plus = if ($add.Count) { " add $($add -join ', ');" } else { '' }
                    [string] $minus = if ($drop.Count) { " drop $($drop -join ', ');" } else { '' }
                    "$($repository.Name):$plus$minus"
                }
            }
        )

        $drift | Should -BeNullOrEmpty -Because (
            "the build is what is true, so architecture.toml follows it:`n" + ($drift -join "`n")
        )
    }

    It 'reads a build for most of the estate, so the check is not passing on nothing' {
        # A reader that found no Cargo.toml would pass the test above for every
        # repository at once. Most mounted repositories use at least one other.
        @($script:Mounted | Where-Object { @($_.Uses).Count -gt 0 }).Count |
            Should -BeGreaterThan ($script:Mounted.Count / 2)
    }
}
