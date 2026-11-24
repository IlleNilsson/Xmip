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
    the landing's and Core.Internal's, is asked here.

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
        [string] $at = $_.DirectoryName
        [bool] $own = $true

        while ($own -and $at.Length -gt $top.Length) {
            $own = -not (Test-Path -LiteralPath (Join-Path -Path $at -ChildPath '.git'))
            $at = Split-Path -Parent -Path $at
        }

        $own
    }
}
