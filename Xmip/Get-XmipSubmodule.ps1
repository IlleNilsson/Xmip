#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    What a working tree mounts: the estate's one reader of .gitmodules.

.DESCRIPTION
    Every question about what is mounted where is answered from here: which
    modules a landing takes (Get-XmipDeclaredModule), where a repository sits
    (Get-XmipMountedPath, for composing, distributing and the estate map) and
    which section a moved submodule is written under (Move-XmipSubmodule).
    git reads the file, through Invoke-XmipGit, so a quoted path, a comment or
    a name that is not its path reads the way git itself reads it.

    Style: doc/governance/powershell-style.md
#>


function Get-XmipSubmodule {
    <#
        .SYNOPSIS
            Every submodule a .gitmodules declares, in file order.

        .DESCRIPTION
            One object per submodule: Name, the section it is written under;
            Path, from the root asked about; Url; Repository, the last
            segment of the URL without .git. With -Recurse, a submodule that
            mounts submodules of its own is followed by them, their paths
            joined to its own, at any depth: a technology is mounted by its
            capability, not by the estate (ADR-0016). Nothing when there is no
            .gitmodules.

        .PARAMETER Root
            The working tree whose .gitmodules is read.

        .PARAMETER Recurse
            Follow every mounted submodule's own .gitmodules.

        .PARAMETER Prefix
            Joined before each path. Set by the recursion.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $false)]
        [switch] $Recurse,

        [Parameter(Mandatory = $false)]
        [string] $Prefix = ''
    )

    [string] $relative = if ($Prefix -ne '') { "$Prefix/.gitmodules" } else { '.gitmodules' }
    [string] $file = Join-Path -Path $Root -ChildPath $relative

    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        return
    }

    [string[]] $asked = @('config', '--file', $file, '--list')
    [System.Collections.Specialized.OrderedDictionary] $section = [ordered] @{}

    foreach ($line in @(Invoke-XmipGit -Arguments $asked)) {
        if ($line -notmatch '^submodule\.(?<name>.+)\.(?<key>path|url)=(?<value>.*)$') {
            continue
        }

        if (-not $section.Contains($Matches['name'])) {
            $section[$Matches['name']] = @{}
        }

        $section[$Matches['name']][$Matches['key']] = $Matches['value']
    }

    foreach ($name in $section.Keys) {
        [string] $path = [string] $section[$name]['path']
        [string] $url = [string] $section[$name]['url']
        [string] $full = if ($Prefix -ne '') { "$Prefix/$path" } else { $path }

        [pscustomobject] @{
            Name       = $name
            Path       = $full
            Url        = $url
            Repository = ($url.TrimEnd('/') -split '/')[-1] -replace '\.git$', ''
        }

        if ($Recurse) {
            Get-XmipSubmodule -Root $Root -Recurse -Prefix $full
        }
    }
}


function Get-XmipMountedPath {
    <#
        .SYNOPSIS
            Where each repository is mounted, by repository name.

        .DESCRIPTION
            A repository whose architecturalDomain changes gets a new
            computed mount path, and without this the old mount is invisible:
            -Compose only ever added, so a moved module stayed where it was
            until someone ran git mv by hand. With -Recurse every level is
            read, and each value is one path from the root.

        .PARAMETER Root
            The working tree.

        .PARAMETER Recurse
            Include what the mounted submodules mount.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $false)]
        [switch] $Recurse
    )

    [hashtable] $mounted = @{}

    foreach ($entry in @(Get-XmipSubmodule -Root $Root -Recurse:$Recurse)) {
        $mounted[$entry.Repository] = $entry.Path
    }

    return $mounted
}
