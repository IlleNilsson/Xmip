#requires -PSEdition Core
#requires -Version 7.6.7

using namespace System.Collections.Generic

<#
.SYNOPSIS
    The modules architecture.toml declares whose crate is on disk and which
    are not submodules yet.

.DESCRIPTION
    A crate written where the manifest mounts a new repository is a folder
    with no .git of its own, inside the module that will mount it. git status
    reported it as untracked files of that module, and the landing listed no
    module by its name: it was verified only when named with -Module, and
    would have been committed into the module around it (2026-10-27).
    Get-XmipDeclaredModule adds these to the estate's modules, so every
    caller sees them.

    Style: doc/governance/powershell-style.md
#>


function Get-XmipNewModule {
    <#
        .SYNOPSIS
            Every folder holding a Cargo.toml, without a .git of its own and
            not a submodule, where architecture.toml mounts the repository
            its package names; each as its path from the estate root.

        .DESCRIPTION
            Looked for beside the submodules, where a capability's technology
            mounts, and two and three levels under module/, where a module
            mounts (ADR-0016). Only a folder whose package is the name its
            place gives is a candidate, so the manifest is read only when one
            is found: none, the ordinary case, costs a directory listing.
            Then the candidate is new when the manifest declares its package
            and mounts it exactly there. Nothing without architecture.toml.

        .PARAMETER RepositoryRoot
            The Xmip working tree.

        .PARAMETER Submodule
            What the working tree mounts, from Get-XmipSubmodule -Recurse.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Submodule
    )

    [string] $architecture = Join-Path -Path $RepositoryRoot -ChildPath 'architecture.toml'
    [hashtable] $found = @{
        RepositoryRoot = $RepositoryRoot
        Submodule      = $Submodule
    }
    [object[]] $candidate = @(Find-XmipNewModuleCandidate @found)

    if ($candidate.Count -eq 0 -or -not (Test-Path -LiteralPath $architecture)) {
        return
    }

    [object[]] $repository = @((Get-XmipManifest -Path $architecture).repositories)
    [string[]] $declared = @($repository | ForEach-Object { [string] $_.name })
    [hashtable] $mounted = @{}

    foreach ($entry in $Submodule) {
        $mounted[$entry.Repository] = $entry.Path
    }

    foreach ($folder in $candidate) {
        [object] $named = $repository | Where-Object { $_.name -eq $folder.Package }

        if ($null -eq $named) {
            continue
        }

        [pscustomobject] $mount = Get-XmipMountPath -Repository $named -Declared $declared
        [string] $full = $mount.Mount

        if ('' -ne $mount.Owner) {
            $full = "$($mounted[$mount.Owner])/$($mount.Mount)"
        }

        if ($full -eq $folder.Path) {
            Write-Output $folder.Path
        }
    }
}


function Find-XmipNewModuleCandidate {
    <#
        .SYNOPSIS
            Get-XmipNewModule's walk: each folder that could be a new module,
            as Path and Package.

        .DESCRIPTION
            Beside a submodule, a folder whose package is the submodule's
            repository name and the folder's own (xmip-core-path and edi make
            xmip-core-path-edi). Under module/, outside every submodule, a
            folder two or three levels down with an xmip package.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Submodule
    )

    [HashSet[string]] $taken = [HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    [string] $root = [System.IO.Path]::GetFullPath($RepositoryRoot)

    # Each folder looked in, with the package its technology gets: the
    # submodule's repository name and a hyphen, or empty for any xmip package.
    [List[string[]]] $parent = [List[string[]]]::new()

    foreach ($entry in $Submodule) {
        [void] $taken.Add($entry.Path)
        $parent.Add(@($entry.Path, "$($entry.Repository)-"))
    }

    # module/<domain>/<leaf> for what starts a node, and
    # module/<provider>/<domain>/<leaf> for the rest, outside every submodule.
    foreach ($first in @(Get-XmipChildFolder -Root $root -Path 'module')) {
        $parent.Add(@($first, ''))

        foreach ($second in @(Get-XmipChildFolder -Root $root -Path $first)) {
            if (-not $taken.Contains($second)) {
                $parent.Add(@($second, ''))
            }
        }
    }

    # One listing per folder of the Cargo.toml directly in its children: the
    # walk stays a few milliseconds over three hundred submodules.
    [System.IO.EnumerationOptions] $children = [System.IO.EnumerationOptions]::new()
    $children.RecurseSubdirectories = $true
    $children.MaxRecursionDepth = 1

    foreach ($pair in $parent) {
        [string] $at = [System.IO.Path]::Join($root, $pair[0])

        if (-not [System.IO.Directory]::Exists($at)) {
            continue
        }

        foreach ($manifest in [System.IO.Directory]::GetFiles($at, 'Cargo.toml', $children)) {
            [string] $folder = [System.IO.Path]::GetDirectoryName($manifest)
            [string] $leaf = [System.IO.Path]::GetFileName($folder)
            [string] $path = "$($pair[0])/$leaf"

            # Its own crate, a submodule or a repository: nothing read.
            if ($folder.Length -le $at.Length -or $taken.Contains($path) -or
                [System.IO.Path]::Exists([System.IO.Path]::Join($folder, '.git'))) {
                continue
            }

            [hashtable] $read = @{ RepositoryRoot = $root; Module = $path }
            [string] $package = (Read-XmipModuleManifest @read).Package
            [bool] $placed = if ('' -eq $pair[1]) {
                $package -like 'xmip-*'
            }
            else {
                $package -eq "$($pair[1])$leaf"
            }

            if ($placed) {
                [pscustomobject] @{ Path = $path; Package = $package }
            }
        }
    }
}


function Get-XmipChildFolder {
    <#
        .SYNOPSIS
            Each folder directly in one, as its path from the root; none when
            it is absent.

        .PARAMETER Root
            The estate root, in full.

        .PARAMETER Path
            The folder, from the root, with forward slashes.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    [string] $at = [System.IO.Path]::Join($Root, $Path)

    if (-not [System.IO.Directory]::Exists($at)) {
        return [string[]] @()
    }

    [List[string]] $folder = [List[string]]::new()

    foreach ($full in [System.IO.Directory]::GetDirectories($at)) {
        $folder.Add("$Path/$([System.IO.Path]::GetFileName($full))")
    }

    return $folder.ToArray()
}
