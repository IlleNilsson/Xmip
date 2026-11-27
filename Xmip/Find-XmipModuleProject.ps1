#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    The .NET projects a module holds itself, never those of a module nested
    in it.

.DESCRIPTION
    The estate's one walk (Find-XmipFile) enters a submodule as any folder,
    so the root's walk for projects found every project of every module,
    and Core.Internal's whole suite built and tested each twice, once for
    its module and once for the root, which holds none (the review of
    2026-11-24, finding M8). Every question of what projects a module holds,
    the landing's and Core.Internal's, is asked here, and whether a folder is
    a module's own (Test-XmipOwnFolder), which the landing also asks of the
    modules whose builds read the runtime's remote builds.

    Style: doc/governance/powershell-style.md
#>


function Find-XmipModuleProject {
    <#
        .SYNOPSIS
            Every *.csproj under -Path outside a repository nested in it: a
            folder below -Path holding a .git, a submodule's file or a
            repository's folder, is a module of its own and verified as
            itself.

        .PARAMETER Path
            The module's working tree.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    [string] $top = [System.IO.Path]::GetFullPath($Path).TrimEnd('\', '/')

    Find-XmipFile -Path $top -Filter '*.csproj' | Where-Object {
        Test-XmipOwnFolder -Top $top -Folder $_.DirectoryName
    }
}


function Test-XmipOwnFolder {
    <#
        .SYNOPSIS
            Whether a folder is a module's own: true where it is the module's
            working tree, or below it with no .git in it or in a folder
            between, a submodule's file or a repository's folder making a
            module of its own; false where it is not below the module.

        .DESCRIPTION
            A test computer's copy holds no submodule's .git, so there the
            root holds every module's folders as its own.

        .PARAMETER Top
            The module's working tree.

        .PARAMETER Folder
            The folder asked about.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string] $Top,

        [Parameter(Mandatory)]
        [string] $Folder
    )

    [string] $module = [System.IO.Path]::GetFullPath($Top).TrimEnd('\', '/')
    [string] $at = [System.IO.Path]::GetFullPath($Folder).TrimEnd('\', '/')
    [string] $relative = [System.IO.Path]::GetRelativePath($module, $at)
    [string] $up = '..' + [System.IO.Path]::DirectorySeparatorChar

    if ($relative -eq '..' -or $relative.StartsWith($up) -or
        [System.IO.Path]::IsPathRooted($relative)) {
        return $false
    }

    [bool] $own = $true

    while ($own -and $at.Length -gt $module.Length) {
        $own = -not (Test-Path -LiteralPath (Join-Path -Path $at -ChildPath '.git'))
        $at = Split-Path -Parent -Path $at
    }

    return $own
}
