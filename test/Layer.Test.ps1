#requires -PSEdition Core
#requires -Version 7.7.0

<#
    Every dependency between the estate's repositories points down its
    layers, and none comes back round (ADR-0058, amendment 2026-11-13).

    The records said the direction and nothing held it. ADR-0058 clause 3,
    2026-09-19: a Foundation crate depends on Foundation crates and on
    third-party crates, and on nothing else in the estate, *a ratchet on ten
    crates that already satisfy it*. Within a week `xmip-core-event` took
    the audit, authorize, observe and resilience crates, and nothing said
    so, because nothing looked. The owner agreed on 2026-11-07, moving
    `xmip-core-cluster` from Foundation to Platform, that a test checks the
    layer direction and that the graph is acyclic.

    What a dependency is: for a mounted repository what its build uses
    (`Get-XmipEstateRepository`, `Uses`: its Cargo.toml `[dependencies]` and
    its non-test .NET project references); for one not mounted, what the
    manifest declares. A Technology repository is in its parent's layer, so
    a Library's technologies are Library and a Capability's are that
    Capability's. The rules, each from a record:

      - The graph is acyclic (repository-model.md section 4,
        architecture.toml `[policy] acyclic`).
      - Library depends only on Library: it is what everything else is
        built out of.
      - Foundation depends only on Foundation and Library (ADR-0058 clause
        3; a Library is read as the clause's third-party crates, the
        estate's own, holding no noun of Xmip's — the amendment of
        2026-11-13).
      - A Capability does not depend on its own Technology children, and a
        Platform repository on no Technology but a Library's
        (repository-model.md section 4).

    The breaches the test found the day it was written are listed below, each
    with the record that says why it stands and what ends it. The list may
    shrink and never grow: a new breach fails, and so does an entry for one
    that is gone.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    [PSCustomObject[]] $script:Repository = @(Get-XmipEstateRepository -Root $script:Root)
    [hashtable] $script:Named = @{}

    # Never $repository: names are case-insensitive, and at this scope it
    # would be $script:Repository itself.
    foreach ($declared in $script:Repository) {
        $script:Named[$declared.Name] = $declared
    }

    # Each breach of a rule standing on 2026-11-13, and why. Remove an entry
    # in the change that ends it; never add one. None stands: the last four,
    # xmip-core-event's, ended with Event delivery's move into
    # xmip-core-cluster (ADR-0058, amendment 2026-11-13).
    [hashtable] $script:Breach = @{}

    <#
        .SYNOPSIS
        The layer a repository is in: its domain, or its parent's for a
        Technology.

        .PARAMETER Name
        The repository.
    #>
    function Get-XmipTestLayer {
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [Parameter(Mandatory = $true)]
            [string] $Name
        )

        [PSCustomObject] $held = $script:Named[$Name]

        if ($held.Domain -eq 'Technology') {
            return [string] $script:Named[$held.Parent].Domain
        }

        return [string] $held.Domain
    }

    <#
        .SYNOPSIS
        Every repository's dependencies on the estate: what a mounted one's
        build uses, what the manifest declares for the rest.
    #>
    function Get-XmipTestEdge {
        [CmdletBinding()]
        [OutputType([PSCustomObject])]
        param()

        foreach ($each in $script:Repository) {
            [string[]] $on = if ($each.Mounted) {
                @($each.Uses)
            }
            else {
                @($each.Declared)
            }

            [string[]] $estate = @(
                $on | Where-Object {
                    -not [string]::IsNullOrEmpty($_) -and $script:Named.ContainsKey($_)
                }
            )

            foreach ($target in $estate) {
                [PSCustomObject] @{
                    From = [string] $each.Name
                    To   = [string] $target
                }
            }
        }
    }

    <#
        .SYNOPSIS
        The rule a dependency breaks, or nothing.

        .PARAMETER From
        The repository that depends.

        .PARAMETER To
        The repository depended on.
    #>
    function Get-XmipTestLayerBreach {
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [Parameter(Mandatory = $true)]
            [string] $From,

            [Parameter(Mandatory = $true)]
            [string] $To
        )

        [string] $above = Get-XmipTestLayer -Name $From
        [string] $below = Get-XmipTestLayer -Name $To
        [PSCustomObject] $depending = $script:Named[$From]
        [PSCustomObject] $depended = $script:Named[$To]

        if ($above -eq 'Library' -and $below -ne 'Library') {
            return "Library depends on $below"
        }

        if ($above -eq 'Foundation' -and $below -notin @('Foundation', 'Library')) {
            return "Foundation depends on $below"
        }

        if ($depending.Domain -eq 'Capability' -and $depended.Parent -eq $From) {
            return 'a Capability depends on its own Technology'
        }

        if ($depending.Domain -eq 'Platform' -and $depended.Domain -eq 'Technology' -and
            $below -ne 'Library') {
            return "Platform depends on a $below Technology"
        }

        return ''
    }

    [PSCustomObject[]] $script:Edge = @(Get-XmipTestEdge)
    [PSCustomObject[]] $script:Found = @(
        foreach ($dependency in $script:Edge) {
            [string] $rule = Get-XmipTestLayerBreach -From $dependency.From -To $dependency.To

            if (-not [string]::IsNullOrEmpty($rule)) {
                [PSCustomObject] @{
                    Pair = "$($dependency.From) -> $($dependency.To)"
                    Rule = $rule
                }
            }
        }
    )
}

Describe 'The estate depends down its layers' {
    It 'has no dependency against the direction but those listed' {
        [string[]] $new = @(
            $script:Found |
                Where-Object { -not $script:Breach.ContainsKey($_.Pair) } |
                ForEach-Object { "$($_.Pair): $($_.Rule)" }
        )

        $new | Should -BeNullOrEmpty -Because (
            "a dependency points up a layer (ADR-0058, amendment 2026-11-13):`n" +
            ($new -join "`n")
        )
    }

    It 'lists no breach that is gone, so the list only shrinks' {
        [string[]] $pairs = @($script:Found | ForEach-Object { $_.Pair })
        [string[]] $gone = @($script:Breach.Keys | Where-Object { $_ -notin $pairs } | Sort-Object)

        $gone | Should -BeNullOrEmpty -Because (
            "remove these from the list in Layer.Test.ps1:`n" + ($gone -join "`n")
        )
    }

    It 'reads a layer for every repository it judges' {
        [string[]] $unplaced = @(
            $script:Repository |
                Where-Object { [string]::IsNullOrEmpty((Get-XmipTestLayer -Name $_.Name)) } |
                ForEach-Object { $_.Name }
        )

        $unplaced | Should -BeNullOrEmpty
        $script:Edge.Count | Should -BeGreaterThan $script:Repository.Count
    }
}

Describe 'The dependency graph is acyclic' {
    It 'has no repository that depends on itself, however far round' {
        [hashtable] $on = @{}

        foreach ($dependency in $script:Edge) {
            if (-not $on.ContainsKey($dependency.From)) {
                $on[$dependency.From] = [Collections.Generic.List[string]]::new()
            }

            $on[$dependency.From].Add($dependency.To)
        }

        # 0 unvisited, 1 on the path walked now, 2 done. A name met again
        # while still on the path closes a cycle, said from where it began.
        [hashtable] $state = @{}
        [Collections.Generic.List[string]] $path = [Collections.Generic.List[string]]::new()
        [Collections.Generic.List[string]] $cycles = [Collections.Generic.List[string]]::new()

        [scriptblock] $walk = {
            param([string] $Name)

            $state[$Name] = 1
            $path.Add($Name)

            foreach ($next in @($on[$Name] | Where-Object { $null -ne $_ })) {
                [int] $seen = [int] $state[$next]

                if ($seen -eq 1) {
                    [int] $from = $path.IndexOf($next)
                    [string[]] $round = @($path.GetRange($from, $path.Count - $from)) + $next
                    $cycles.Add($round -join ' -> ')
                }
                elseif ($seen -eq 0) {
                    & $walk $next
                }
            }

            $path.RemoveAt($path.Count - 1)
            $state[$Name] = 2
        }

        foreach ($declared in $script:Repository) {
            if ([int] $state[$declared.Name] -eq 0) {
                & $walk $declared.Name
            }
        }

        $cycles | Should -BeNullOrEmpty -Because ($cycles -join "`n")
    }
}
