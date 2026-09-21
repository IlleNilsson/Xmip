#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    The estate map's tree: every repository where it mounts, and what it weighs.

.DESCRIPTION
    The map had tables, which say what exists and not how much of it there is.
    The owner, 2026-09-20, drew the shape he wanted instead — a tree, with a
    count of lines beside each name and the repositories that hold no source
    gathered under the parent that declares them.

    A tree of mounts is the one drawing the manifest can make on its own: the
    mount path is the nesting, so nothing here decides where a repository
    goes. What it adds is weight, which no record in the estate stated before.

    `Add-XmipMapMount.ps1` builds the tree and weighs it; this draws what that
    produced.

    Style: doc/governance/powershell-style.md
#>

# The column a name's count is right-aligned to end at. Wide enough for the
# deepest mount the estate has, and inside the map's own width.
[int] $script:XmipTreeColumn = 52


function New-XmipMapBranch {
    <#
        .SYNOPSIS
            One name in the tree, its count aligned, and everything under it.

        .DESCRIPTION
            Recursive, depth first, children heaviest first — the tree exists
            to show weight, and alphabetical order hides it. The per-domain
            tables below the tree are alphabetical for looking a name up.

        .PARAMETER Node
            The node to draw: Name, Code, Child and Absent.

        .PARAMETER Indent
            What every line of this subtree begins with, drawn by the caller.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $Node,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Indent
    )

    [PSCustomObject[]] $child = @(
        $Node.Child.Values | Sort-Object -Property @{ Expression = 'Code'; Descending = $true },
                                                   @{ Expression = 'Name'; Descending = $false }
    )

    [string[]] $line = @()

    for ([int] $index = 0; $index -lt $child.Count; $index++) {
        [bool] $last = ($index -eq $child.Count - 1) -and ($Node.Absent.Count -eq 0)
        [string] $elbow = if ($last) { '└── ' } else { '├── ' }
        [string] $under = $Indent + $(if ($last) { '    ' } else { '│   ' })

        # A directory of the working tree carries no count and says so with a
        # trailing slash, the way the owner drew it: `platform/` is a place,
        # `runtime` is a repository.
        [string] $said = $child[$index].Name

        if ($null -eq $child[$index].Code) {
            $said = "$said/"
        }

        [hashtable] $drawn = @{
            Name     = $Indent + $elbow + $said
            Code     = $child[$index].Code
            Language = $child[$index].Language
        }

        $line += Format-XmipTreeName @drawn

        $line += New-XmipMapBranch -Node $child[$index] -Indent $under
    }

    return ($line + (New-XmipMapAbsent -Absent $Node.Absent -Indent $Indent))
}


function Format-XmipTreeName {
    <#
        .SYNOPSIS
            A drawn name with its count, right-aligned into one column.

        .DESCRIPTION
            Nothing at all where the count is unknown, which is a repository
            the manifest declares and this tree does not mount. A zero would
            claim the repository is empty; it is not here to be measured.

        .PARAMETER Name
            The name, already carrying its tree drawing.

        .PARAMETER Code
            The lines it holds, or $null when it holds none.

        .PARAMETER Language
            Those lines per language. A repository written in one language
            says nothing about it — the estate is Rust and the exception is
            what a reader needs told. Where there are two or more, every
            language but the largest is named after the count, so `abi` reads
            8060 and says 7225 of them are C#.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object] $Code,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [hashtable] $Language
    )

    if ($null -eq $Code) {
        return $Name
    }

    [int] $pad = $script:XmipTreeColumn - $Name.Length - ([string] $Code).Length

    if ($pad -lt 1) {
        $pad = 1
    }

    return $Name + (' ' * $pad) + [string] $Code +
        (Format-XmipTreeLanguage -Language $Language)
}


function Format-XmipTreeLanguage {
    <#
        .SYNOPSIS
            What a repository is written in, where that is not one thing.

        .DESCRIPTION
            Nothing for a repository of one language, which is nearly all of
            them and is the estate's Rust default. Otherwise every language
            it holds, largest first, as `C# 7225 · Rust 835`.

            Every one of them, not just the ones that are not the largest: a
            lone `+835 Rust` beside a total of 8060 reads as eight thousand
            and eight hundred, because a plus sign means addition wherever
            else it is written. The count in the column is the whole of the
            repository and these say what it is made of.

        .PARAMETER Language
            Lines per language, or $null.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [hashtable] $Language
    )

    if ($null -eq $Language -or $Language.Count -lt 2) {
        return ''
    }

    [PSCustomObject[]] $spoken = @(
        $Language.Keys | ForEach-Object {
            [PSCustomObject]@{ Name = $_; Code = $Language[$_] }
        } | Sort-Object -Property Code -Descending
    )

    [string[]] $said = @(
        $spoken | ForEach-Object { "$($_.Name) $($_.Code)" }
    )

    return '  ' + ($said -join ' · ')
}


function New-XmipMapAbsent {
    <#
        .SYNOPSIS
            The declared-and-not-built line under a parent, and the names.

        .DESCRIPTION
            The owner asked for the count and the names both. The count alone
            is a number nobody can act on; the names alone hide how many there
            are when the list wraps over four lines.

        .PARAMETER Absent
            The names declared under this parent and mounted nowhere.

        .PARAMETER Indent
            The subtree's indent, which these lines share with its children.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $Absent,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Indent
    )

    if ($Absent.Count -eq 0) {
        return @()
    }

    [string] $lead = "$Indent    declared, not built $($Absent.Count)"
    [string] $said = "$Indent    " + (($Absent | Sort-Object) -join '  ')

    # Two spaces between names, so a wrap can fall on the first of the pair and
    # leave the line ending in a space. The style rules gate that, and rightly.
    [string[]] $line = @(
        Format-XmipMapLine -Text $said -Indent "$Indent    " |
            ForEach-Object { $_.TrimEnd() }
    )

    return @($lead) + $line
}




function New-XmipMapTree {
    <#
        .SYNOPSIS
            The map's tree section, from the manifest and the composed tree.

        .DESCRIPTION
            Mounted repositories are the tree. Declared ones that mount nowhere
            are named under the parent that declares them, because that is the
            only place the manifest puts them and a list of three hundred names
            at the end would say nothing about which capability is unbuilt.

        .PARAMETER Repository
            Every declared repository.

        .PARAMETER Source
            Every source file, from `Get-XmipSourceFile`.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]] $Repository,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [PSCustomObject[]] $Source
    )

    [PSCustomObject[]] $mounted = @($Repository | Where-Object { $_.Mounted })

    [hashtable] $weight = Get-XmipMapWeight -Source $Source -Mount @(
        $mounted | ForEach-Object { $_.Mount }
    )

    [PSCustomObject] $root = New-XmipMapNode -Name ''
    [hashtable] $placed = @{}

    foreach ($entry in ($mounted | Sort-Object -Property Mount)) {
        [hashtable] $code = $null

        if ($weight.ContainsKey($entry.Mount)) {
            $code = $weight[$entry.Mount]
        }

        $placed[$entry.Name] = Add-XmipMapMount -Root $root -Mount $entry.Mount -Code $code
    }

    foreach ($entry in ($Repository | Where-Object { -not $_.Mounted })) {
        if ([string]::IsNullOrEmpty($entry.Parent) -or -not $placed.ContainsKey($entry.Parent)) {
            continue
        }

        $placed[$entry.Parent].Absent += $entry.Leaf
    }

    [int] $sum = 0

    foreach ($spoken in $weight.Values) {
        foreach ($count in $spoken.Values) {
            $sum += $count
        }
    }

    return @(
        '## The tree'
        ''
    ) + (New-XmipMapTreeWords -Repository $Repository -Sum $sum) + @(
        '```text'
    ) + (New-XmipMapBranch -Node $root -Indent '') + @(
        '```'
        ''
    )
}


function New-XmipMapTreeWords {
    <#
        .SYNOPSIS
            What the tree's numbers mean, said before the tree rather than
            after it.

        .PARAMETER Repository
            Every declared repository.

        .PARAMETER Sum
            Every counted line, added up.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject[]] $Repository,

        [Parameter(Mandatory = $true)]
        [int] $Sum
    )

    [int] $absent = @($Repository | Where-Object { -not $_.Mounted }).Count

    [string[]] $said = @(
        "Where each repository mounts and what it holds: $Sum lines of " +
        'production source, every file charged to the deepest repository ' +
        'containing it, so a parent is its own code and never its children ' +
        'added again. Counted by `Get-XmipSourceFile`, which is also what ' +
        '`test/Rust.Style.Test.ps1` gates file length with; a Rust file ends ' +
        'at its first `#[cfg(test)]` and a `*.Test.ps1` or `*.Test.cs` counts ' +
        'as nothing.'

        'Heaviest first at every level, because that is what a tree of counts ' +
        'is for. The tables below are alphabetical, for looking a name up. ' +
        'A name ending in `/` is a directory of the working tree; every other ' +
        'name is a repository.'

        'A repository written in more than one language says what it is made ' +
        'of, largest first, and one written in a single language says nothing ' +
        '— the estate is Rust and the exception is what a reader needs told. ' +
        'One total hid that the largest repository in the estate is almost ' +
        'all C# (the owner, 2026-09-21).'

        'A name under `declared, not built` is declared by the manifest and ' +
        'mounted nowhere — work not begun, not work unmounted. There are ' +
        [string] $absent + ' of them and they hold no source to count.'
    )

    [string[]] $line = @()

    foreach ($text in $said) {
        $line += (Format-XmipMapLine -Text $text -Indent '') + ''
    }

    return $line
}
