#requires -PSEdition Core
#requires -Version 7.7.0

using namespace System.Collections.Generic

<#
.SYNOPSIS
    Writes the estate's one Cargo workspace from its plan
    (Get-XmipWorkspacePlan): the root's members and [workspace.dependencies],
    each member's estate dependencies in the workspace's form, and no [patch]
    of an estate crate.

.DESCRIPTION
    Sync-XmipEstate -Cargo runs it, and -Compose after it mounts. A line is
    rewritten where the plan says, and nothing else of a manifest: its
    comments, its order and its line endings stay.

    Style: doc/governance/powershell-style.md
#>


# The root's comment over [workspace.dependencies], written with the table
# where the root has none.
[string[]] $script:XmipWorkspaceDependencyNote = @(
    '# Every estate crate a member depends on, under the key the member names it'
    '# by: its package and its mount, the path its submodule is mounted at'
    '# (ADR-0005, amendment 2026-11-28). A member takes one with'
    '# `key = { workspace = true }` and says what is its own: features,'
    '# optional, and default-features = false. One key names one package.'
    '# Written from the members by Sync-XmipEstate -Cargo (Update-XmipWorkspace).'
)


function Update-XmipWorkspace {
    <#
        .SYNOPSIS
            Writes the workspace the crates on disk make, and says what it
            wrote; safe to run twice.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot
    )

    $plan = Get-XmipWorkspacePlan -RepositoryRoot $RepositoryRoot
    [string] $full = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($RepositoryRoot)
    [string] $root = Join-Path -Path $full.TrimEnd('\', '/') -ChildPath 'Cargo.toml'
    [hashtable] $changed = @{}

    foreach ($edge in $plan.Edge) {
        if (-not $changed.ContainsKey($edge.Manifest)) {
            $changed[$edge.Manifest] = @{}
        }

        $changed[$edge.Manifest][$edge.Index] = $edge.Text
    }

    foreach ($manifest in @($changed.Keys | Where-Object { $_ -ne $root } | Sort-Object)) {
        [pscustomobject] $text = Read-XmipManifestText -Path $manifest
        $changed[$manifest].GetEnumerator() | ForEach-Object { $text.Line[$_.Key] = $_.Value }
        Write-XmipManifestText -Path $manifest -Text $text
    }

    [pscustomobject] $own = Read-XmipManifestText -Path $root

    if ($changed.ContainsKey($root)) {
        $changed[$root].GetEnumerator() | ForEach-Object { $own.Line[$_.Key] = $_.Value }
    }

    [hashtable] $written = @{ Line = Set-XmipWorkspaceMember -Line $own.Line -Member $plan.Member }
    [pscustomobject] $section = Set-XmipWorkspaceDependency @written -Plan $plan
    $own.Line = $section.Line
    Write-XmipManifestText -Path $root -Text $own

    [int] $git = @($plan.Edge | Where-Object { $_.Git }).Count
    Write-Host ("  WORKSPACE: $($plan.Member.Count) members, $($plan.Dependency.Count) estate " +
        "keys, $git dependencies by git URL and $($plan.Edge.Count - $git) others rewritten " +
        "in $($changed.Count) manifests, $($section.Removed) [patch] tables removed")
}


function Read-XmipManifestText {
    <#
        .SYNOPSIS
            A manifest's lines and the line ending it uses, for writing back
            what it was but the lines changed.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    [string] $text = [IO.File]::ReadAllText($Path)
    [string] $ending = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    [string[]] $lines = $text.Replace("`r`n", "`n").TrimEnd("`n").Split("`n")

    return [pscustomobject]@{ Path = $Path; Line = [string[]] $lines; Ending = $ending }
}


function Write-XmipManifestText {
    <#
        .SYNOPSIS
            Writes a manifest's lines back where they differ from the file,
            with its own line ending and a final one.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [pscustomobject] $Text
    )

    [string] $whole = ($Text.Line -join $Text.Ending) + $Text.Ending
    [byte[]] $bytes = [Text.UTF8Encoding]::new($false).GetBytes($whole)

    Write-XmipChangedFile -Path $Path -Content $bytes -What 'Cargo manifest'
}


function Set-XmipWorkspaceMember {
    <#
        .SYNOPSIS
            The root's lines with its `members = [ ... ]` written from the
            plan.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string[]] $Line,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Member
    )

    [int] $start = [Array]::IndexOf($Line, 'members = [')
    [int] $end = if ($start -ge 0) { [Array]::IndexOf($Line, ']', $start) } else { -1 }

    if ($end -lt 0) {
        throw 'FAILED: the root Cargo.toml holds no `members = [`; the estate is one workspace.'
    }

    [List[string]] $written = [List[string]]::new()
    $written.AddRange([string[]] $Line[0..$start])
    $Member | ForEach-Object { $written.Add("    `"$_`",") }
    $written.AddRange([string[]] $Line[$end..($Line.Count - 1)])

    return $written.ToArray()
}


function Set-XmipWorkspaceDependency {
    <#
        .SYNOPSIS
            The root's lines with [workspace.dependencies] written from the
            plan, a third party's entries in it kept, and every [patch]
            table of an estate crate deleted with the comment above it:
            Line, and Removed, how many were. Where the root has no
            [workspace.dependencies], it is written where the first such
            [patch] was, or at the end.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string[]] $Line,

        [Parameter(Mandatory)]
        [pscustomobject] $Plan
    )

    [string[]] $entries = @($Plan.Dependency | ForEach-Object { Format-XmipWorkspaceKey -Key $_ })
    [List[string]] $out = [List[string]]::new()
    [int] $removed = 0
    [int] $insert = -1
    [bool] $found = $false

    [int] $index = 0

    while ($index -lt $Line.Count) {
        [hashtable] $read = @{ Line = $Line; Index = $index; Estate = $Plan.Mount }
        [pscustomobject] $table = Read-XmipManifestTable @read

        if ($table.Name -like 'patch.*' -and $table.Estate) {
            [int] $own = Remove-XmipTrailingComment -Line $out

            if ($insert -lt 0) {
                $insert = $own
            }

            $removed++
        }
        elseif ($table.Name -eq 'workspace.dependencies') {
            $out.Add($Line[$index])
            $table.Kept | ForEach-Object { $out.Add($_) }
            $entries | ForEach-Object { $out.Add($_) }
            $found = $true
        }
        else {
            $Line[$index..($table.Next - 1)] | ForEach-Object { $out.Add($_) }
        }

        $index = $table.Next
    }

    if (-not $found) {
        Add-XmipWorkspaceDependencyTable -Line $out -At $insert -Entry $entries
    }

    return [pscustomobject]@{ Line = $out.ToArray(); Removed = $removed }
}


function Read-XmipManifestTable {
    <#
        .SYNOPSIS
            The part of a manifest's lines from -Index to the next table's
            header: Name, the table's, empty before the first; Next, where
            the next begins, after any blank line and comment that open it;
            Estate, whether an entry in it names an estate crate; Kept, its
            lines but those entries, with no blank line at the end.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string[]] $Line,

        [Parameter(Mandatory)]
        [int] $Index,

        [Parameter(Mandatory)]
        [hashtable] $Estate
    )

    [Text.RegularExpressions.Match] $header = $script:XmipCargoHeader.Match($Line[$Index])
    [string] $name = if ($header.Success) { $header.Groups['table'].Value } else { '' }
    [int] $next = $Index + 1
    [int] $last = $Index

    while ($next -lt $Line.Count -and -not $script:XmipCargoHeader.IsMatch($Line[$next])) {
        [string] $bare = $Line[$next].Trim()

        if ($bare.Length -gt 0 -and -not $bare.StartsWith('#')) {
            $last = $next
        }

        $next++
    }

    [List[string]] $kept = [List[string]]::new()
    [bool] $estateNamed = $false
    [hashtable] $none = @{}

    for ([int] $at = $Index + 1; $at -le $last; $at++) {
        [Text.RegularExpressions.Match] $entry = $script:XmipCargoEntry.Match($Line[$at])
        [string] $package = ''

        if ($entry.Success) {
            [hashtable] $pair = @{}
            $script:XmipCargoPair.Matches($entry.Groups['body'].Value) | ForEach-Object {
                $pair[$_.Groups['key'].Value] = $_.Groups['value'].Value
            }
            [hashtable] $named = @{ Key = $entry.Groups['key'].Value; Pair = $pair }
            $package = Resolve-XmipCargoPackage @named -Workspace $none
        }

        if ($Estate.ContainsKey($package)) {
            $estateNamed = $true
        }
        else {
            $kept.Add($Line[$at])
        }
    }

    return [pscustomobject]@{
        Name = $name; Next = if ($header.Success) { $last + 1 } else { $next }
        Estate = $estateNamed; Kept = $kept.ToArray()
    }
}


function Remove-XmipTrailingComment {
    <#
        .SYNOPSIS
            Takes the comment lines at the end of -Line, which open the table
            being deleted, and returns where they began.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [List[string]] $Line
    )

    while ($Line.Count -gt 0 -and $Line[$Line.Count - 1].TrimStart().StartsWith('#')) {
        $Line.RemoveAt($Line.Count - 1)
    }

    return $Line.Count
}


function Add-XmipWorkspaceDependencyTable {
    <#
        .SYNOPSIS
            Writes [workspace.dependencies] with its comment into -Line, at
            -At, or at the end where -At is below 0, a blank line on either
            side.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [List[string]] $Line,

        [Parameter(Mandatory)]
        [int] $At,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Entry
    )

    [int] $place = if ($At -ge 0) { $At } else { $Line.Count }
    [List[string]] $block = [List[string]]::new()

    if ($place -gt 0 -and $Line[$place - 1].Trim().Length -gt 0) {
        $block.Add('')
    }

    $block.AddRange($script:XmipWorkspaceDependencyNote)
    $block.Add('[workspace.dependencies]')
    $block.AddRange($Entry)

    if ($place -lt $Line.Count -and $Line[$place].Trim().Length -gt 0) {
        $block.Add('')
    }

    $Line.InsertRange($place, $block)

    while ($Line.Count -gt 0 -and $Line[$Line.Count - 1].Trim().Length -eq 0) {
        $Line.RemoveAt($Line.Count - 1)
    }
}


function Format-XmipWorkspaceKey {
    <#
        .SYNOPSIS
            One key's line in the root's [workspace.dependencies]: its
            package where the key is another name, and its path.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Key
    )

    [List[string]] $pairs = [List[string]]::new()

    if ($Key.Package -cne $Key.Key) {
        $pairs.Add("package = `"$($Key.Package)`"")
    }

    $pairs.Add("path = `"$($Key.Path)`"")

    return "$($Key.Key) = { $($pairs -join ', ') }"
}
