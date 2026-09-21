#requires -PSEdition Core
#requires -Version 7.6.5

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

    Rust is read from the repository's own `Cargo.toml`, `[dependencies]` only:
    a dev-dependency is how a repository is tested, not what it is made of.
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

    foreach ($name in @(Get-XmipCargoUse -Directory $here)) {
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
            The estate crates a Cargo manifest names under `[dependencies]`.

        .DESCRIPTION
            By package name where the entry renames it — `transport = { package
            = "xmip-core-transport" }` — and by key otherwise. Nothing where
            there is no manifest, which is a .NET repository or an empty one.

        .PARAMETER Directory
            The repository's full path.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Directory
    )

    [string] $cargo = Join-Path $Directory 'Cargo.toml'

    if (-not (Test-Path -LiteralPath $cargo -PathType Leaf)) {
        return [string[]] @()
    }

    $toml = Get-Content -Raw -LiteralPath $cargo | ConvertFrom-Toml
    $table = Get-TomlValue -Node $toml -Name 'dependencies' -Default $null

    [string[]] $named = @(
        foreach ($key in @(Get-TomlKey -Node $table)) {
            $entry = Get-TomlValue -Node $table -Name $key
            [string] $package = [string](Get-TomlValue -Node $entry -Name 'package' -Default $key)

            if ($package -like 'xmip-*') {
                $package
            }
        }
    )

    return $named
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
        Get-ChildItem -LiteralPath $Directory -Recurse -Filter '*.csproj' -File |
            Where-Object { $_.FullName -notmatch '[\\/](bin|obj|target)[\\/]' } |
            Where-Object { $_.BaseName -notmatch '\.Tests?$' } |
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
