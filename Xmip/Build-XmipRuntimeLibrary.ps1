#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    The runtime library the estate's tooling reads its rules through, found
    where the estate builds it and built there where it is not.

.DESCRIPTION
    Every rule this module reads through Xmip.Surface is the runtime's, in
    xmip-core-operate's library, which Xmip.Operate copies beside the
    operator module when it is built (Import-XmipOperatorModule). A landing
    builds that library before anything is tested; a machine no landing had
    built it on gave the operator module none, and every such rule failed:
    Read-XmipConfiguration, Get-XmipNodeRoleWord, the System Tests' authority
    and the rest, which is how the estate's Pester suite first ran on Linux
    (2026-11-20).

    Style: doc/governance/powershell-style.md
#>


function Build-XmipRuntimeLibrary {
    <#
        .SYNOPSIS
            The runtime library where cargo builds, by its full path: built
            there first, from the working tree, where it is not there yet.

        .DESCRIPTION
            Where cargo builds is Get-XmipEstateLayout's Build, and
            Xmip.Operate reads the same place, so it copies what was built
            here. One already there is used as it is: a landing builds a
            fresh one before it tests, and this is for a machine that has
            none.

        .PARAMETER Root
            The estate's root.

        .PARAMETER Fresh
            Built even where one is there, cargo deciding whether anything
            changed: for a copy whose sources changed since its last build,
            as a test computer's does with every send (open problem 208).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter()]
        [switch] $Fresh
    )

    $library = Get-XmipPackageProgram | Where-Object -Property Kind -EQ 'Library'
    [string] $target = (Get-XmipEstateLayout -Root $Root).Build
    [string] $path = Join-Path -Path $target -ChildPath "debug/$($library.File)"

    if ($Fresh -or -not [System.IO.File]::Exists($path)) {
        [hashtable] $building = @{
            Root            = $Root
            Folder          = $library.Folder
            TargetDirectory = $target
            Argument        = @('build', '--lib')
        }
        Invoke-XmipCrateBuild @building
    }

    return $path
}
