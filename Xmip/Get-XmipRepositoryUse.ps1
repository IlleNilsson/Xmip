#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    Which estate repositories one repository actually uses, read from its code.

.DESCRIPTION
    The manifest declares a `dependency` for every repository, and a declaration
    is a promise. The estate map was drawn as a published page on 2026-09-10
    with its edges typed in by hand, and the owner read it for eleven days
    after it stopped being true, down to a retired module drawn with no
    dependencies (2026-09-21). An edge the map draws is read from the build, so
    it cannot be wrong for longer than one landing.

    Rust is read from the repository's own `Cargo.toml`: `[dependencies]` and
    every platform's own, `[target.'cfg(...)'.dependencies]`, since a
    dependency a build takes on one platform alone is still what it is made
    of there — until 2026-11-15 the second were not read, and a serial port's
    use of `net` on Windows went undeclared. A dev-dependency is how a
    repository is tested, not what it is made of, on any platform.
    .NET is read from every project file the repository holds that is not a
    test project, each `ProjectReference` resolved to the repository that
    contains the project it names.

    Style: doc/governance/powershell-style.md
#>


function Get-XmipRepositoryUse {
    <#
        .SYNOPSIS
            The estate repositories one mounted repository uses.

        .PARAMETER Root
            The estate root.

        .PARAMETER Mount
            The repository's mount, root-relative, forward slashes.

        .PARAMETER Owner
            Every mount's full path, normalized, to the repository at it — for
            resolving a project reference to the repository that holds it.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        [string] $Mount,

        [Parameter(Mandatory = $true)]
        [hashtable] $Owner
    )

    [string] $here = [IO.Path]::GetFullPath((Join-Path $Root $Mount))
    $here = $here.TrimEnd([char] 92, [char] 47)

    $uses = [System.Collections.Generic.SortedSet[string]]::new()

    [hashtable] $workspace = Get-XmipWorkspaceDependency -RepositoryRoot $Root

    foreach ($name in @(Get-XmipCargoUse -Directory $here -Workspace $workspace)) {
        [void] $uses.Add($name)
    }

    foreach ($name in @(Get-XmipProjectUse -Directory $here -Owner $Owner)) {
        [void] $uses.Add($name)
    }

    [string] $self = [string] $Owner[$here]
    [void] $uses.Remove($self)

    return [string[]] @($uses)
}


function Get-XmipCargoUse {
    <#
        .SYNOPSIS
            The estate crates a Cargo manifest names under `[dependencies]`,
            and under the dependencies of each `[target.'cfg(...)']` table.

        .DESCRIPTION
            By the package each entry names (Resolve-XmipCargoPackage): its
            `package`, the root's entry under its key where it takes the
            crate from the workspace, its key otherwise. A crate empty off
            its own platform is a dependency of that platform alone, since
            cargo refuses one a build does not use (unused_dependencies,
            Cargo 1.100; ADR-0062, amendment 2026-11-19), so what a crate
            links is read from both. Nothing where there is no manifest,
            which is a .NET repository or an empty one.

        .PARAMETER Directory
            The repository's full path.

        .PARAMETER Workspace
            The root's [workspace.dependencies], each key to its package
            (Get-XmipWorkspaceDependency).
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Directory,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [hashtable] $Workspace
    )

    [string] $cargo = Join-Path $Directory 'Cargo.toml'

    if (-not (Test-Path -LiteralPath $cargo -PathType Leaf)) {
        return [string[]] @()
    }

    [string[]] $named = @(
        foreach ($entry in @(Read-XmipCargoDependency -Path $cargo)) {
            if ($entry.Table -notmatch '^(target\..+\.)?dependencies$') {
                continue
            }

            [hashtable] $asked = @{ Key = $entry.Key; Pair = $entry.Pair; Workspace = $Workspace }
            [string] $package = Resolve-XmipCargoPackage @asked

            if ($package -like 'xmip-*') {
                $package
            }
        }
    )

    return [string[]] @($named | Sort-Object -Unique)
}


function Get-XmipProjectUse {
    <#
        .SYNOPSIS
            The estate repositories a repository's .NET projects reference.

        .DESCRIPTION
            Every project file inside the repository and not inside a
            repository nested in it, test projects left out, and not under
            build output. A reference that resolves outside every mount is
            not the estate's and is not an edge.

        .PARAMETER Directory
            The repository's full path.

        .PARAMETER Owner
            Every mount's full path, normalized, to the repository at it.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Directory,

        [Parameter(Mandatory = $true)]
        [hashtable] $Owner
    )

    [string] $self = [string] $Owner[$Directory]

    [System.IO.FileInfo[]] $projects = @(
        Find-XmipFile -Path $Directory -Filter '*.csproj' |
            Where-Object { $_.BaseName -notmatch '\.Test$' } |
            Where-Object { (Resolve-XmipOwner -Path $_.DirectoryName -Owner $Owner) -eq $self }
    )

    [string[]] $used = @(
        foreach ($project in $projects) {
            [xml] $document = Get-Content -Raw -LiteralPath $project.FullName

            foreach ($reference in @($document.SelectNodes('//ProjectReference'))) {
                [string] $include = [string] $reference.Include -replace '\\', '/'
                [string] $named = Join-Path $project.DirectoryName $include
                [string] $target = [IO.Path]::GetFullPath($named)
                [string] $folder = [IO.Path]::GetDirectoryName($target)
                [string] $holder = Resolve-XmipOwner -Path $folder -Owner $Owner

                if (-not [string]::IsNullOrEmpty($holder)) {
                    $holder
                }
            }
        }
    )

    return $used
}


function Resolve-XmipOwner {
    <#
        .SYNOPSIS
            The repository whose mount is the deepest one containing a path.

        .PARAMETER Path
            A full path.

        .PARAMETER Owner
            Every mount's full path, normalized, to the repository at it.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [hashtable] $Owner
    )

    [string] $at = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')

    while (-not [string]::IsNullOrEmpty($at)) {
        if ($Owner.ContainsKey($at)) {
            return [string] $Owner[$at]
        }

        [string] $up = [IO.Path]::GetDirectoryName($at)

        if ($up -eq $at) {
            break
        }

        $at = $up
    }

    return ''
}
