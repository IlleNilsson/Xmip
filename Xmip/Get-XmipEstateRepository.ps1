#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    Every declared repository, with where it sits and whether it is composed.

.DESCRIPTION
    What `New-XmipEstateMap` renders, as objects. Two facts are joined here:
    `architecture.toml` says what the estate is, and the `.gitmodules` files
    say what this working tree has composed of it.

    Composition is read at two levels, because that is where it is written
    (ADR-0016, amended 2026-09-07). The root `.gitmodules` composes the
    modules; a depth-three technology is composed by its own parent capability,
    in that repository's `.gitmodules`. A reader looking only at the root would
    report 290 technologies as absent when 214 of them are on disk.

    Style: doc/governance/powershell-style.md
#>

function Get-XmipEstateRepository {
    <#
        .SYNOPSIS
            Every declared repository, ordered by name.

        .DESCRIPTION
            Objects out rather than text, so a pipeline into Where-Object on
            Mounted answers what is declared and not composed here without
            parsing a document.

            Parent is the hosting repository for a technology and empty for
            everything else. It is read from the dependency the manifest
            derives rather than from the name, because a technology key may
            itself hold hyphens — `iec-60870-5-104` is one segment. Leaf is
            the name with that parent's prefix removed.

            Mount is the path from the repository root, and empty when the
            repository is not composed in this tree.

        .PARAMETER Root
            The repository root. Defaults to the one this module was imported
            from.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.EstateRepository')]
    param(
        [Parameter(Mandatory = $false)]
        [string] $Root
    )

    if ([string]::IsNullOrWhiteSpace($Root)) {
        $Root = Get-XmipRepositoryRoot
    }

    $manifest = Get-XmipManifest -Path (Join-Path $Root 'architecture.toml')
    [hashtable] $composed = Get-XmipMountedPath -Root $Root -Recurse

    # Every mount's full path to the repository at it, so a .NET project
    # reference resolves to the repository that holds the project it names.
    [hashtable] $owner = @{}

    foreach ($name in $composed.Keys) {
        [string] $full = [IO.Path]::GetFullPath((Join-Path $Root $composed[$name]))
        $owner[$full.TrimEnd([char] 92, [char] 47)] = $name
    }

    foreach ($entry in ($manifest.repositories | Sort-Object -Property name)) {
        [string] $parent = ''

        if ($entry.architecturalDomain -eq 'Technology') {
            $parent = [string] $entry.dependencies[0]
        }

        [string] $leaf = [string] $entry.name

        if (-not [string]::IsNullOrEmpty($parent)) {
            $leaf = $entry.name.Substring($parent.Length + 1)
        }

        [string] $mount = ''

        if ($composed.ContainsKey($entry.name)) {
            $mount = [string] $composed[$entry.name]
        }

        [PSCustomObject] @{
            PSTypeName = 'Xmip.EstateRepository'
            Name       = [string] $entry.name
            Leaf       = $leaf
            Domain     = [string] $entry.architecturalDomain
            Maturity   = [string] $entry.maturity
            Parent     = $parent
            Mount      = $mount
            Mounted    = (-not [string]::IsNullOrEmpty($mount))
            Declared   = [string[]] @($entry.dependencies)
            Uses       = [string[]] @(
                if (-not [string]::IsNullOrEmpty($mount)) {
                    Get-XmipRepositoryUse -Root $Root -Mount $mount -Owner $owner
                }
            )
        }
    }
}
