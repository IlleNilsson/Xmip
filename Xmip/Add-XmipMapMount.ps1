#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    Builds the estate map's tree from the mounts, and weighs each one.

.DESCRIPTION
    Separated from `New-XmipMapTree.ps1`, which draws it. This is where a
    repository lands and what it is found to hold; that is where it is turned
    into characters. Neither knows the other's business, and keeping them
    apart is also what keeps both files inside the length rule.

    Style: doc/governance/powershell-style.md
#>


function Get-XmipMapWeight {
    <#
        .SYNOPSIS
            Lines of production source per mount, each file charged once.

        .DESCRIPTION
            A file belongs to the deepest mount that contains it, so
            `module/core/capability/transport` is its own source and not the eighty
            technologies beneath it. Without that rule a parent's count is
            every child's count added again, and the tree would say the estate
            is several times its own size.

            A mount with no source of its own is absent from the result rather
            than present as zero: the caller tells a repository that holds
            nothing from one it never asked about.

            The value is a count per language rather than one total, because
            one total hides what a repository is written in: `abi` read 8060
            and is 7225 lines of C# (the owner, 2026-09-21, whose own drawing
            of the map carried the split and whose assistant's did not).

        .PARAMETER Mount
            Every mounted repository's path, root-relative, forward slashes.

        .PARAMETER Source
            Every source file, from `Get-XmipSourceFile`.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $Mount,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [PSCustomObject[]] $Source
    )

    [hashtable] $known = @{}

    foreach ($path in $Mount) {
        $known[$path] = $true
    }

    [hashtable] $weight = @{}

    foreach ($file in $Source) {
        [string[]] $part = $file.Path -split '/'

        # Up from the file, not down from the root: the first mount met going
        # up is the deepest one holding it.
        for ([int] $depth = $part.Count - 1; $depth -gt 0; $depth--) {
            [string] $within = ($part[0..($depth - 1)]) -join '/'

            if (-not $known.ContainsKey($within)) {
                continue
            }

            if (-not $weight.ContainsKey($within)) {
                $weight[$within] = @{}
            }

            if (-not $weight[$within].ContainsKey($file.Language)) {
                $weight[$within][$file.Language] = 0
            }

            $weight[$within][$file.Language] += $file.Code
            break
        }
    }

    return $weight
}


function New-XmipMapNode {
    <#
        .SYNOPSIS
            An empty node of the tree.

        .PARAMETER Name
            What the node is called at its own level. Empty for the root,
            which is the estate and is drawn as nothing.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Name
    )

    return [PSCustomObject]@{
        Name     = $Name
        Code     = $null
        Language = $null
        Child    = [ordered] @{}
        Absent   = [string[]] @()
    }
}


function Add-XmipMapMount {
    <#
        .SYNOPSIS
            Puts one mount into the tree, making the levels above it as needed.

        .DESCRIPTION
            A level that is only a directory — `module`, `capability` — gets a
            node with no count, because no repository mounts there and a count
            would be a sum of its children rather than anything anyone wrote.

        .PARAMETER Root
            The tree's root node.

        .PARAMETER Mount
            The path to add, root-relative, forward slashes.

        .PARAMETER Code
            The lines the mount holds, per language, or $null when it holds
            none.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $Root,

        [Parameter(Mandatory = $true)]
        [string] $Mount,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [hashtable] $Code
    )

    [PSCustomObject] $at = $Root

    foreach ($step in ($Mount -split '/')) {
        if (-not $at.Child.Contains($step)) {
            $at.Child[$step] = New-XmipMapNode -Name $step
        }

        $at = $at.Child[$step]
    }

    if ($null -ne $Code) {
        [int] $sum = 0

        foreach ($count in $Code.Values) {
            $sum += $count
        }

        $at.Code = $sum
        $at.Language = $Code
    }

    return $at
}
