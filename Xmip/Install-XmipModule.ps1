#requires -PSEdition Core
#requires -Version 7.6

<#
    Dot-sourced by Xmip.psm1. Style: docs/governance/powershell-style.md
#>

function Get-XmipUserModulePath {
    <#
        The per-user module directory PowerShell searches, taken from
        PSModulePath rather than assumed. On Windows that is normally
        Documents\PowerShell\Modules; on Linux and macOS it is
        ~/.local/share/powershell/Modules. Neither is hard-coded here, because
        OneDrive redirection moves the Windows one and a hard-coded path would
        link into a directory nothing searches.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    [string] $home = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    [string[]] $candidates = $env:PSModulePath -split [IO.Path]::PathSeparator

    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        if ($candidate.StartsWith($home, [StringComparison]::OrdinalIgnoreCase)) {
            return $candidate
        }
    }

    throw 'No per-user directory found on PSModulePath. Xmip cannot decide where to link itself.'
}


function Install-XmipModule {
    <#
    .SYNOPSIS
        Links this module into your per-user module directory so that
        Import-Module Xmip works from anywhere.

    .DESCRIPTION
        Creates a directory link from the per-user module directory to the copy
        in this repository. A link rather than a copy, deliberately: edits in the
        repository are live in the next session, and there is never a second
        version of the module to wonder about.

        On Windows a junction is used rather than a symbolic link, because a
        junction needs no elevation and no Developer Mode. On Linux and macOS a
        symbolic link is used.

        Run once, by path. Everything after that is Import-Module Xmip.

    .EXAMPLE
        Import-Module ./module/Xmip
        Install-XmipModule

    .EXAMPLE
        Install-XmipModule -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param(
        # Replace an existing link or directory of the same name.
        [Parameter(Mandatory = $false)]
        [switch] $Force
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    [string] $source = $PSScriptRoot
    [string] $modulePath = Get-XmipUserModulePath
    [string] $target = Join-Path $modulePath 'Xmip'

    Write-Step -Message "Linking $target to $source"

    if (Test-Path -LiteralPath $target) {
        [System.IO.DirectoryInfo] $existing = [System.IO.DirectoryInfo]::new($target)
        [bool] $isLink = ($null -ne $existing.LinkTarget)

        if (-not $isLink -and -not $Force) {
            throw "$target exists and is a real directory, not a link. Move it, or pass -Force."
        }

        if (-not $PSCmdlet.ShouldProcess($target, 'Remove the existing module directory')) {
            return
        }

        Remove-Item -LiteralPath $target -Recurse -Force
    }

    if (-not (Test-Path -LiteralPath $modulePath)) {
        if ($PSCmdlet.ShouldProcess($modulePath, 'Create the per-user module directory')) {
            New-Item -ItemType Directory -Path $modulePath -Force | Out-Null
        }
    }

    # Junction on Windows: no elevation, no Developer Mode. SymbolicLink
    # elsewhere, where it needs neither.
    [string] $linkType = 'SymbolicLink'

    if ($IsWindows) {
        $linkType = 'Junction'
    }

    if (-not $PSCmdlet.ShouldProcess($target, "Create $linkType to $source")) {
        return
    }

    [hashtable] $link = @{
        ItemType = $linkType
        Path     = $target
        Value    = $source
    }

    New-Item @link | Out-Null

    Write-Step -Message 'Linked. Import-Module Xmip now works from any location.'
}
