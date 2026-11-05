#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    Where everything of the estate is: its own files and every folder of its
    working area. The one place the module names them.

.DESCRIPTION
    A function that needs one of these asks Get-XmipEstateLayout for it and
    writes no name or path of its own, so a renamed file or a moved folder is
    one edit here.

    The working area, `.local-work`, is git-ignored and holds what belongs to
    this machine: what a run, a build or a landing writes.

    Style: doc/governance/powershell-style.md
#>


# The estate's own files, at its root.
[string] $script:XmipManifestName = 'architecture.xmip'
[string] $script:XmipPrerequisiteName = 'prerequisite.xmip'

# The working area's folder name, at the estate's root.
[string] $script:XmipWorkName = '.local-work'


function Get-XmipEstateLayout {
    <#
        .SYNOPSIS
            Every path of the estate at -Root: its files and its working
            area's folders. Nothing is created; who writes a folder makes it.

        .PARAMETER Root
            The estate's root. The repository this session is in, unless said.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [string] $Root = (Get-XmipRepositoryRoot)
    )

    [string] $work = Join-Path -Path $Root -ChildPath $script:XmipWorkName

    [pscustomobject]@{
        Root         = $Root
        Manifest     = Join-Path -Path $Root -ChildPath $script:XmipManifestName
        Prerequisite = Join-Path -Path $Root -ChildPath $script:XmipPrerequisiteName
        Work         = $work
        Essentials   = Join-Path -Path $work -ChildPath 'essentials'
        Estate       = Join-Path -Path $work -ChildPath 'estate'
        Landing      = Join-Path -Path $work -ChildPath 'landing'
        Package      = Join-Path -Path $work -ChildPath 'package'
        Operator     = Join-Path -Path $work -ChildPath 'operator'
        Tool         = Join-Path -Path $work -ChildPath 'tool'
        Deploy       = Join-Path -Path $work -ChildPath 'deploy'
        Web          = Join-Path -Path $work -ChildPath 'web'
        Audit        = Join-Path -Path $work -ChildPath 'audit'
        VerifyTime   = Join-Path -Path $work -ChildPath 'verify-time.json'
        EstateMap    = Join-Path -Path $work -ChildPath 'estate-map.html'
    }
}
