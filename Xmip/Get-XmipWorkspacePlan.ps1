#requires -PSEdition Core
#requires -Version 7.7.0

using namespace System.Collections.Generic

<#
.SYNOPSIS
    What the estate's one Cargo workspace should be, read from its crates on
    disk: the root manifest's members and [workspace.dependencies], and each
    member's estate dependency in the workspace's form (ADR-0016, amendment
    2026-11-20; ADR-0005, amendment 2026-11-28).

.DESCRIPTION
    Every crate under the root is a member, the Rust template's too, since a
    module made from it builds only inside the estate (ADR-0016, amendment
    2026-11-27). An estate crate depends on another by path, through the
    root: the root's [workspace.dependencies] holds one entry for each key a
    member names an estate crate by, its package and its mount, and the
    member says `key = { workspace = true }`, with features and optional of
    its own.

    A member may name an estate crate by its repository's git URL, as every
    one did until 2026-11-28: the plan turns that into the workspace's form,
    and the key into the root at the crate's mount. So a new dependency is
    written either way, and Update-XmipWorkspace writes the plan; a second
    run finds nothing to write. test/Sync-XmipEstate.Test.ps1 holds the root
    and the members to the plan.

    Style: doc/governance/powershell-style.md
#>


# What an estate dependency may say beside its source; the rest is the
# workspace's.
[string[]] $script:XmipMemberPair = @('features', 'optional', 'default-features')


function Get-XmipWorkspacePlan {
    <#
        .SYNOPSIS
            The workspace the root manifest should hold: Member, each
            member's folder, relative and `/`-separated, sorted ordinally;
            Mount, each estate crate's path by package; Dependency, each key
            members name an estate crate by, its Package and Path; and Edge,
            each member's line that is not yet the workspace's form: Manifest,
            Index, Text, and Git, whether it names its crate by git URL.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot
    )

    # Resolved by PowerShell: .NET would resolve a relative root against its
    # own current directory, which is not this session's.
    [string] $full = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($RepositoryRoot)
    [string] $root = $full.TrimEnd('\', '/')
    [pscustomobject[]] $crates = @(Get-XmipWorkspaceMember -Root $root)
    [hashtable] $mount = Get-XmipWorkspaceMount -Root $root -Crate $crates
    [string[]] $folders = @($crates | ForEach-Object { $_.Folder })
    [hashtable] $current = Get-XmipWorkspaceEntry -Root $root -Mount $mount

    [string[]] $manifests = @(Join-Path $root 'Cargo.toml') +
        @($folders | ForEach-Object { Join-Path (Join-Path $root $_) 'Cargo.toml' })
    [hashtable] $read = @{ Mount = $mount; Current = $current }
    [pscustomobject[]] $edges = @(
        foreach ($manifest in $manifests) {
            Get-XmipEstateEdge @read -Manifest $manifest
        }
    )

    [pscustomobject]@{
        Member     = $folders
        Mount      = $mount
        Dependency = @(Get-XmipWorkspaceKey -Edge $edges -Mount $mount -Current $current)
        Edge       = @($edges | ForEach-Object { ConvertTo-XmipWorkspaceEdge -Edge $_ })
    }
}


function Get-XmipWorkspaceMember {
    <#
        .SYNOPSIS
            Every member of the workspace, each estate crate on disk but the
            root's: Name, its package, and Folder, relative and
            `/`-separated, sorted ordinally. The plan's members without the
            rest of the plan, for what needs no more.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Root
    )

    [List[pscustomobject]] $crates = [List[pscustomobject]]::new()

    foreach ($crate in @(Get-XmipEstateCrate -RepositoryRoot $Root)) {
        [string] $folder = [IO.Path]::GetRelativePath($Root, $crate.Directory).Replace('\', '/')

        if ($folder -ne '.') {
            $crates.Add([pscustomobject]@{ Name = $crate.Name; Folder = $folder })
        }
    }

    $crates.Sort([Comparison[pscustomobject]] {
            param([pscustomobject] $Left, [pscustomobject] $Right)
            [string]::CompareOrdinal($Left.Folder, $Right.Folder)
        })

    return $crates.ToArray()
}


function Get-XmipWorkspaceMount {
    <#
        .SYNOPSIS
            Each estate crate's path, by package: where .gitmodules mounts
            the repository the package is (Get-XmipMountedPath), or, for a
            crate a repository holds without being one, its folder. Throws
            when a crate is not where its repository is mounted.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $Root,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [pscustomobject[]] $Crate
    )

    [hashtable] $mounted = Get-XmipMountedPath -Root $Root -Recurse
    [hashtable] $path = @{}

    foreach ($each in $Crate) {
        [string] $at = if ($mounted.ContainsKey($each.Name)) { $mounted[$each.Name] }
        else { $each.Folder }

        if ($at -cne $each.Folder) {
            throw ("REFUSED. $($each.Name) is at $($each.Folder), and .gitmodules mounts " +
                "its repository at $at; mount it where its crate is.")
        }

        $path[$each.Name] = $at
    }

    return $path
}


function Get-XmipWorkspaceEntry {
    <#
        .SYNOPSIS
            The root's [workspace.dependencies] as it stands: each key to its
            Package, Estate, whether that is an estate crate, and
            DefaultFeatures, false where the entry turns them off, as a member
            that says nothing of them then takes it.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $Root,

        [Parameter(Mandatory)]
        [hashtable] $Mount
    )

    [hashtable] $entries = @{}
    [hashtable] $none = @{}
    [string] $manifest = Join-Path -Path $Root -ChildPath 'Cargo.toml'

    foreach ($entry in @(Read-XmipCargoDependency -Path $manifest)) {
        if ($entry.Table -ne 'workspace.dependencies') {
            continue
        }

        [hashtable] $named = @{ Key = $entry.Key; Pair = $entry.Pair; Workspace = $none }
        [string] $package = Resolve-XmipCargoPackage @named
        [string] $defaults = Get-XmipCargoValue -Pair $entry.Pair -Name 'default-features'

        $entries[$entry.Key] = [pscustomobject]@{
            Package = $package; Estate = $Mount.ContainsKey($package)
            DefaultFeatures = $defaults -ne 'false'
        }
    }

    return $entries
}


function Get-XmipEstateEdge {
    <#
        .SYNOPSIS
            Each estate dependency one manifest names, by git URL or from the
            workspace: Manifest, Entry, Key, Package, Git, and Wants, whether
            it takes the crate's default features.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Manifest,

        [Parameter(Mandatory)]
        [hashtable] $Mount,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [hashtable] $Current
    )

    [hashtable] $none = @{}

    foreach ($entry in @(Read-XmipCargoDependency -Path $Manifest)) {
        if ($entry.Table -eq 'workspace.dependencies') {
            continue
        }

        [bool] $git = $entry.Pair.Contains('git')
        [bool] $inherited = (Get-XmipCargoValue -Pair $entry.Pair -Name 'workspace') -eq 'true'
        [hashtable] $named = @{ Key = $entry.Key; Pair = $entry.Pair; Workspace = $none }
        [string] $package = if ($inherited -and $Current.ContainsKey($entry.Key)) {
            $Current[$entry.Key].Package
        }
        else { Resolve-XmipCargoPackage @named }

        if (-not $Mount.ContainsKey($package) -or -not ($git -or $inherited)) {
            continue
        }

        [string] $defaults = Get-XmipCargoValue -Pair $entry.Pair -Name 'default-features'
        [bool] $wants = if ($defaults.Length -gt 0) { $defaults -ne 'false' }
        elseif ($inherited) { $Current[$entry.Key].DefaultFeatures }
        else { $true }

        Assert-XmipEstateEdgePair -Manifest $Manifest -Entry $entry

        [pscustomobject]@{
            Manifest = $Manifest; Entry = $entry; Key = $entry.Key; Package = $package
            Git = $git; Wants = $wants
        }
    }
}


function Assert-XmipEstateEdgePair {
    <#
        .SYNOPSIS
            Throws on an estate dependency saying what the workspace's form
            cannot carry, a rev, a tag, a version, a path of its own, or
            written across lines, which its rewriting does not keep.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $Manifest,

        [Parameter(Mandatory)]
        [pscustomobject] $Entry
    )

    [string[]] $source = @('package', 'git', 'branch', 'workspace')
    [string[]] $other = @(
        $Entry.Pair.Keys | Where-Object { $_ -notin $source -and $_ -notin $script:XmipMemberPair }
    )

    if ($other.Count -gt 0) {
        throw ("REFUSED. ${Manifest}:$($Entry.Index + 1) says $($other -join ', ') of the " +
            "estate crate $($Entry.Key); a member names one with features, optional and " +
            'default-features alone, the workspace the rest.')
    }

    if ($Entry.Last -ne $Entry.Index) {
        throw ("REFUSED. ${Manifest}:$($Entry.Index + 1) names the estate crate " +
            "$($Entry.Key) across lines; write it on one line.")
    }
}


function Get-XmipWorkspaceKey {
    <#
        .SYNOPSIS
            Each key the members name an estate crate by, sorted ordinally:
            Key, Package and Path, its mount. Throws when one key names two
            packages, or names a crate a key of the root's names beside a
            third party.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [pscustomobject[]] $Edge,

        [Parameter(Mandatory)]
        [hashtable] $Mount,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [hashtable] $Current
    )

    [SortedDictionary[string, object]] $keys =
        [SortedDictionary[string, object]]::new([StringComparer]::Ordinal)

    foreach ($group in @($Edge | Group-Object -Property Key -CaseSensitive)) {
        [string[]] $packages = @($group.Group | ForEach-Object { $_.Package } | Sort-Object -Unique)
        [bool] $third = $Current.ContainsKey($group.Name) -and -not $Current[$group.Name].Estate

        if ($packages.Count -gt 1 -or $third) {
            Write-XmipWorkspaceClash -Key $group.Name -Edge $group.Group -Third $third
        }

        $keys[$group.Name] = [pscustomobject]@{
            Key = $group.Name; Package = $packages[0]; Path = $Mount[$packages[0]]
        }
    }

    return @($keys.Values)
}


function Write-XmipWorkspaceClash {
    <#
        .SYNOPSIS
            Throws, naming each manifest a clashing key is in and what it
            names there.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $Key,

        [Parameter(Mandatory)]
        [pscustomobject[]] $Edge,

        [Parameter(Mandatory)]
        [bool] $Third
    )

    [string[]] $where = @(
        $Edge | ForEach-Object { "$($_.Package) in $($_.Manifest)" } | Sort-Object -Unique
    )
    [string] $also = if ($Third) { ', and the root''s entry a third party' } else { '' }

    throw ("REFUSED. The key $Key names $($where -join '; ')$also. One key of the root's " +
        '[workspace.dependencies] names one package: rename it where it means another.')
}


function ConvertTo-XmipWorkspaceEdge {
    <#
        .SYNOPSIS
            An estate dependency in the workspace's form, where its line is
            not already that: Manifest, Index, Text, and Git, whether it named
            its crate by git URL. Nothing when the line stays.

        .DESCRIPTION
            A member that turns the crate's default features off says so
            itself, and the root's entry says nothing of them: cargo 1.100
            takes a member's `default-features = false` beside `workspace =
            true` as it took it beside the git URL (measured 2026-11-28).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Edge
    )

    [pscustomobject] $entry = $Edge.Entry
    [List[string]] $pairs = [List[string]]::new()
    $pairs.Add('workspace = true')

    if (-not $Edge.Wants) {
        $pairs.Add('default-features = false')
    }

    foreach ($name in @($entry.Pair.Keys | Where-Object { $_ -in @('features', 'optional') })) {
        $pairs.Add("$name = $($entry.Pair[$name])")
    }

    [string] $text = "$($entry.Indent)$($entry.Key) = { $($pairs -join ', ') }$($entry.Tail)"

    if ($text -ceq $entry.Line) {
        return
    }

    [pscustomobject]@{
        Manifest = $Edge.Manifest; Index = $entry.Index; Text = $text; Git = $Edge.Git
    }
}
