#requires -PSEdition Core
#requires -Version 7.6.5

using namespace System.Collections.Generic

<#
.SYNOPSIS
    Which modules a landing takes, and the order their dependencies put them in.

.DESCRIPTION
    Apart from Publish-XmipChange.ps1 since 2026-09-22, when that file had grown
    to 1,586 lines against the 400 the estate allows a file, and the owner asked
    for the estate to be consolidated. The landing is one command made of several
    subjects; each subject is a file.

    Style: doc/governance/powershell-style.md
#>


function Get-XmipDeclaredModule {
    <#
        .SYNOPSIS
            Every submodule path in .gitmodules, in file order, nested included.

        .DESCRIPTION
            A Technology repository (repository-model.md) is a submodule of its
            parent Capability, so its path lives in *that* repository's
            .gitmodules, not the estate root's. Reading only the root left every
            such module — a content contract, a transport, an archive target —
            outside the pipeline: not tested, not landed, not pinned.

            So this recurses (Get-XmipSubmodule -Recurse): a Technology reads as
            its full path from the estate root. Pre-order: a parent precedes its
            children, which keeps the root order and appends the nested after
            each.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot
    )

    # A submodule with no submodules of its own is the ordinary case; only the
    # estate root is required to have one.
    if (-not (Test-Path -LiteralPath (Join-Path -Path $RepositoryRoot -ChildPath '.gitmodules'))) {
        throw "No .gitmodules under $RepositoryRoot. Is that the Xmip working tree?"
    }

    Get-XmipSubmodule -Root $RepositoryRoot -Recurse | ForEach-Object { $_.Path }
}


function Get-XmipNestedParent {
    <#
        .SYNOPSIS
            Declared submodules that themselves mount submodules, deepest first.

        .DESCRIPTION
            A Technology lands in its own repository, but the gitlink to it lives
            in its parent Capability's repository, not the superproject. The
            parent has to record and push that gitlink before the superproject can
            pin the parent. These are those parents, ordered deepest first so a
            chain of nesting pins from the bottom up.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot
    )

    [string[]] $declared = @(Get-XmipDeclaredModule -RepositoryRoot $RepositoryRoot)

    [string[]] $parents = @(
        $declared | Where-Object {
            [string] $candidate = $_
            @($declared | Where-Object { $_ -like "$candidate/*" }).Count -gt 0
        }
    )

    $parents |
        Sort-Object -Property @{ Expression = { ($_ -split '/').Count }; Descending = $true }
}


function Read-XmipModuleManifest {
    <#
        .SYNOPSIS
            A module's package name and the estate packages it depends on, read
            once from its Cargo.toml for every caller.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [string] $Module
    )

    [string] $manifest = Join-Path -Path $RepositoryRoot -ChildPath "$Module/Cargo.toml"

    # No manifest, no declared dependencies.
    if (-not (Test-Path -LiteralPath $manifest)) {
        return [pscustomobject]@{ Package = ''; Needs = @() }
    }

    [string] $text = Get-Content -LiteralPath $manifest -Raw
    [string] $name = ''

    if ($text -match '(?m)^name\s*=\s*"(?<name>[^"]+)"') {
        $name = $Matches['name']
    }

    # Any alias: a technology names its sibling `ethernet` or `iso_tp`, not
    # `xmip-...`. Matching only aliases that start with xmip landed ethercat
    # before ethernet on 2026-09-11. What decides is the package.
    [string[]] $needs = @(
        [regex]::Matches($text, '(?m)^\s*(?<alias>[A-Za-z0-9_-]+)\s*=\s*\{(?<body>[^}]*)\}') |
            ForEach-Object {
                [string] $body = $_.Groups['body'].Value

                if ($body -match 'package\s*=\s*"(?<package>[^"]+)"') {
                    $Matches['package']
                }
                else {
                    $_.Groups['alias'].Value
                }
            } |
            Where-Object { $_ -like 'xmip*' }
    )

    [pscustomobject]@{ Package = $name; Needs = $needs }
}

function Get-XmipModuleConsumer {
    <#
        .SYNOPSIS
            Every module of the estate that depends, directly or through
            others, on one of the given modules, and is not one of them.

        .DESCRIPTION
            A change to a leaf can pass its own tests and break a consumer
            nobody touched; the landing checks these too (an external review,
            2026-10-05).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Module
    )

    [hashtable] $read = @{}
    foreach ($name in @(Get-XmipDeclaredModule -RepositoryRoot $RepositoryRoot)) {
        $read[$name] = Read-XmipModuleManifest -RepositoryRoot $RepositoryRoot -Module $name
    }

    [HashSet[string]] $reached = [HashSet[string]]::new()
    foreach ($name in $Module) {
        if ($read.ContainsKey($name) -and $read[$name].Package) {
            [void] $reached.Add($read[$name].Package)
        }
    }

    [List[string]] $consumers = [List[string]]::new()
    do {
        [bool] $grew = $false

        foreach ($name in $read.Keys) {
            [pscustomobject] $entry = $read[$name]

            if ($Module -contains $name -or $consumers.Contains($name) -or -not $entry.Package) {
                continue
            }

            if (@($entry.Needs | Where-Object { $reached.Contains($_) }).Count -gt 0) {
                $consumers.Add($name)
                [void] $reached.Add($entry.Package)
                $grew = $true
            }
        }
    } while ($grew)

    $consumers
}

function Sort-XmipModuleDependency {
    <#
        .SYNOPSIS
            Orders modules so that nothing is landed before what it depends on.

        .DESCRIPTION
            Reads each manifest's package name and its Xmip dependencies, then
            repeatedly takes every module whose dependencies are already placed.

            Iterative rather than a recursive walk. The recursive version
            depended on a nested function seeing the parent's collections
            through PowerShell's scope rules, and silently emitted one module
            out of three — the kind of failure that looks like a smaller change
            set rather than like a bug.

            A cycle is reported rather than quietly broken. Cargo would refuse
            it anyway, and an arbitrary order here would turn a manifest error
            into a mysterious build failure.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Module
    )

    [hashtable] $package = @{}
    [hashtable] $needs = @{}

    foreach ($name in $Module) {
        [pscustomobject] $read =
            Read-XmipModuleManifest -RepositoryRoot $RepositoryRoot -Module $name

        if ($read.Package) {
            $package[$read.Package] = $name
        }

        $needs[$name] = $read.Needs
    }

    [List[string]] $placed = [List[string]]::new()
    [List[string]] $waiting = [List[string]]::new()
    $Module | ForEach-Object { $waiting.Add($_) }

    while ($waiting.Count -gt 0) {
        [string[]] $ready = @(
            $waiting | Where-Object {
                # Named, not $PSItem. Each nested pipeline rebinds $_ *and*
                # $PSItem — they are the same variable — so the inner
                # Where-Object's $PSItem is the resolved dependency, never the
                # module being tested. Written as `$_ -ne $PSItem` it compared a
                # value with itself, filtered out every blocker, and made every
                # module look ready. The sort then emitted its input order,
                # which is alphabetical, and authenticate was tested before the
                # identify and context it depends on.
                [string] $candidate = $_

                [string[]] $blockers = @(
                    $needs[$candidate] |
                        ForEach-Object { $package[$_] } |
                        Where-Object { $_ -and $_ -ne $candidate -and $waiting.Contains($_) }
                )

                $blockers.Count -eq 0
            }
        )

        if ($ready.Count -eq 0) {
            throw "The manifests declare a dependency cycle among: $($waiting -join ', ')"
        }

        foreach ($name in $ready) {
            $placed.Add($name)
            [void] $waiting.Remove($name)
        }
    }

    $placed
}
