#requires -PSEdition Core
#requires -Version 7.7.0

using namespace System.Collections.Generic

<#
.SYNOPSIS
    The estate's one Cargo workspace kept in step with its crates: the root
    manifest's members and its [patch] (ADR-0016, amendment 2026-11-20).

.DESCRIPTION
    Every crate under the root but the template's is a member; every estate
    crate a manifest names by its git URL is patched to its folder, by
    relative path. Sync-XmipEstate -Compose calls it whenever it mounts a
    crate, and test/Publish-XmipChange.Test.ps1 holds the plan to the crates on disk.

    Style: doc/governance/powershell-style.md
#>


# Where an estate crate's repository is, and what a manifest names it by.
[string] $script:XmipCrateSource = 'https://github.com/IlleNilsson/'


function Get-XmipWorkspacePlan {
    <#
        .SYNOPSIS
            The members and the patched crates the root manifest should hold:
            each member's folder, relative and `/`-separated, sorted
            ordinally, and each patched crate's name and folder.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot
    )

    [string] $root = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\', '/')
    [List[pscustomobject]] $members = [List[pscustomobject]]::new()

    foreach ($crate in @(Get-XmipEstateCrate -RepositoryRoot $root)) {
        [string] $folder = [IO.Path]::GetRelativePath($root, $crate.Directory).Replace('\', '/')

        if ($folder -eq '.' -or $folder -eq 'template' -or $folder.StartsWith('template/')) {
            continue
        }

        $members.Add([pscustomobject]@{ Name = $crate.Name; Folder = $folder })
    }

    $members.Sort([Comparison[pscustomobject]] {
            param($left, $right) [string]::CompareOrdinal($left.Folder, $right.Folder)
        })

    # Every estate crate a manifest names by its git URL; a commented line
    # names nothing.
    [string] $source = [regex]::Escape($script:XmipCrateSource)
    [string] $named = 'git\s*=\s*"' + $source + '([^"/]+?)(?:\.git)?"'
    [SortedSet[string]] $used = [SortedSet[string]]::new([StringComparer]::Ordinal)
    [string[]] $manifests = @(Join-Path $root 'Cargo.toml') +
        @($members | ForEach-Object { Join-Path (Join-Path $root $_.Folder) 'Cargo.toml' })

    foreach ($manifest in $manifests) {
        foreach ($line in [IO.File]::ReadAllLines($manifest)) {
            if ($line.TrimStart().StartsWith('#')) {
                continue
            }

            foreach ($match in [regex]::Matches($line, $named)) {
                $null = $used.Add($match.Groups[1].Value)
            }
        }
    }

    [hashtable] $folderOf = @{}
    $members | ForEach-Object { $folderOf[$_.Name] = $_.Folder }

    [pscustomobject]@{
        Member  = @($members | ForEach-Object { $_.Folder })
        Patched = @($used | Where-Object { $folderOf.ContainsKey($_) } |
                ForEach-Object { [pscustomobject]@{ Name = $_; Folder = $folderOf[$_] } })
    }
}


function Update-XmipWorkspace {
    <#
        .SYNOPSIS
            Writes the root manifest's members and [patch] from the crates on
            disk, and nothing else of it.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot
    )

    [string] $path = Join-Path -Path $RepositoryRoot -ChildPath 'Cargo.toml'
    [string] $text = [IO.File]::ReadAllText($path)
    $plan = Get-XmipWorkspacePlan -RepositoryRoot $RepositoryRoot

    [string] $members = "members = [`n" +
        (($plan.Member | ForEach-Object { "    `"$_`",`n" }) -join '') + ']'
    [string] $after = [regex]::Replace($text, '(?ms)^members = \[\s*$.*?^\]', { $members })

    [string] $patch = ($plan.Patched | ForEach-Object {
            [string] $url = "$($script:XmipCrateSource)$($_.Name)"
            "[patch.`"$url`"]`n$($_.Name) = { path = `"$($_.Folder)`" }`n"
        }) -join ''
    [string] $first = '[patch."' + $script:XmipCrateSource
    [int] $at = $after.IndexOf($first)

    if ($at -lt 0) {
        throw ("FAILED: $path holds no [patch] of the estate's crates; the estate is one " +
            'workspace (ADR-0016).')
    }

    $after = $after.Substring(0, $at) + $patch

    [string] $act = 'Write the workspace''s members and [patch]'

    if ($after -ne $text -and $PSCmdlet.ShouldProcess($path, $act)) {
        [IO.File]::WriteAllText($path, $after, [Text.UTF8Encoding]::new($false))
        [int] $patched = $plan.Patched.Count
        Write-Host "  WORKSPACE: $($plan.Member.Count) members, $patched patched crates"
    }
}
