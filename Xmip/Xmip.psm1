#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    The Xmip estate's tooling module.

.DESCRIPTION
    The module's root: the helpers every command file dot-sourced below
    shares. All of the commands need to know what the estate is, and copies
    of that knowledge drift.

    The tree is the data. xmip.core.transport.ftp is xmip-core-transport-ftp:
    dots become hyphens and nothing else happens.

    Style: doc/governance/powershell-style.md
#>

Set-StrictMode -Version Latest

# The manifest schema this module understands. Major is the compatibility
# boundary: 2.x is the tree-is-the-name schema, and a 3.0 manifest will mean
# something this reader does not know. Refusing it is the whole point of the
# field — declaring a version nothing checks is worse than declaring none,
# because it looks like a guarantee.
[int] $script:XmipSchemaMajor = 2

# The names every System Process Xmip owns answers to: xmip, the command a
# person types, and xmip-<what> (ADR-0053, amendment 2026-10-22). Asked of
# the operating system as they stand, and held to by Test-XmipProcessName.
[string[]] $script:XmipProcessName = @('xmip', 'xmip-*')

# Keys that describe a repository. A child of the estate tree may not share a
# name with one of these, because TOML cannot hold a scalar and a table at one
# key. See Assert-XmipNoMetadataCollision.
[string[]] $script:XmipMetadataKey = @(
    'description'
    'architecturalDomain'
    'repositoryRole'
    'maturity'
    'dependency'
    'primaryLanguage'
)

[string[]] $script:XmipMaturity = @(
    'planned'
    'reserved'
    'created'
    'configured'
    'submodule'
    'workspace'
    'scaffolded'
    'implemented'
    'verified'
    'supported'
)


function Get-XmipRepositoryRoot {
    <#
        Finds the Xmip repository by walking up from the current location until
        architecture.toml appears.

        $PSScriptRoot cannot answer this. Once the module is linked onto
        PSModulePath it lives outside the repository, and when it is loaded by
        path it lives two levels inside it. Neither is a reliable anchor, and
        the manifest is the thing actually being looked for.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [string] $StartAt = ((Get-Location).Path)
    )

    [string] $found = Find-XmipRepositoryRoot -StartAt $StartAt

    if (-not [string]::IsNullOrEmpty($found)) {
        return $found
    }

    # The module knows where it came from. Install-XmipModule links it onto
    # PSModulePath by a junction or symbolic link whose target is inside the
    # repository, so a cmdlet answers from any directory — the owner's shell
    # at home included (2026-09-12) — and a copy elsewhere still says no.
    $here = Get-Item -LiteralPath $PSScriptRoot -ErrorAction SilentlyContinue
    [string] $origin = $PSScriptRoot

    if ($null -ne $here -and -not [string]::IsNullOrEmpty($here.LinkTarget)) {
        $origin = $here.LinkTarget
    }

    $found = Find-XmipRepositoryRoot -StartAt $origin

    if (-not [string]::IsNullOrEmpty($found)) {
        return $found
    }

    throw ("No $script:XmipManifestName found at or above '$StartAt' or where this " +
        "module lives ($origin).")
}


function Find-XmipRepositoryRoot {
    <#
        Walks up from one directory until the estate's manifest appears; empty
        when it never does. The search Get-XmipRepositoryRoot runs twice.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $StartAt
    )

    [System.IO.DirectoryInfo] $directory = [System.IO.DirectoryInfo]::new($StartAt)

    while ($null -ne $directory) {
        [string] $candidate = Join-Path $directory.FullName $script:XmipManifestName

        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $directory.FullName
        }

        $directory = $directory.Parent
    }

    return ''
}


function Write-XmipStep {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    Write-Host "==> $Message" -ForegroundColor Cyan
}


function Get-XmipPropertyValue {
    <#
        Reads a property from a PSObject, returning $Default when the object,
        the property or its value is absent.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Object,

        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $false)]
        $Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    $property = $Object.PSObject.Properties[$Name]

    if ($null -eq $property) {
        return $Default
    }

    if ($null -eq $property.Value) {
        return $Default
    }

    return $property.Value
}


function ConvertTo-XmipArray {
    <#
        Wraps a value as an array, turning $null into an empty array rather than
        an array containing $null.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Value
    )

    if ($null -eq $Value) {
        return @()
    }

    return @($Value)
}


# When this session read the module's files. A console keeps the module it
# imported, and the programs it starts are built from the source as it is now:
# on 2026-09-29 a console two days old told a roll where to publish in words
# the roll no longer read, and the roll published to the temp directory while
# the web host waited for it in .local-work.
[datetime] $script:XmipImportedAt = [datetime]::Now

function Assert-XmipModuleCurrent {
    <#
    .SYNOPSIS
        Refuses when this session's Xmip module is older than its files.
    .DESCRIPTION
        What starts a program built from source calls this first, so a
        console holding yesterday's module says so instead of starting
        today's program with yesterday's words.
    #>
    [CmdletBinding()]
    param()

    [string[]] $kinds = '*.ps1', '*.psm1', '*.psd1'
    $newest = Get-ChildItem -LiteralPath $PSScriptRoot -File -Include $kinds -Recurse |
        Sort-Object -Property LastWriteTime -Descending |
        Select-Object -First 1

    if ($newest -and $newest.LastWriteTime -gt $script:XmipImportedAt) {
        [string] $imported = $script:XmipImportedAt.ToString('yyyy-MM-dd HH:mm')
        [string] $changed = $newest.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
        throw ("REFUSED. This session's Xmip module was imported at $imported and " +
            "$($newest.Name) changed at $changed. Close this Xmip PowerShell Console and " +
            'open a new one: Import-Module -Force reloads the scripts but not the ' +
            'assemblies .NET already holds.')
    }
}

# The commands. Dot-sourced rather than duplicated, so they see the helpers
# above and the module is the single thing anyone imports. The TOML reader
# comes first: every other file reads through it.
#
# Install-XmipPrerequisite is here despite the bootstrap look of it: this module loads
# without PSToml, because Get-XmipManifest imports PSToml when called rather than
# at import time. So a bare machine can import the module and ask what it is
# missing. PowerShell itself is the only prerequisite Xmip cannot install, and
# #requires states that floor.
# The module's files, each loaded once: the layout and the TOML reader first,
# since other files use them as they load, then every other file of the
# folder in name order. A new file is loaded by being here; nothing lists it.
[string[]] $first = @('Get-XmipEstateLayout.ps1', 'Read-XmipToml.ps1')

foreach ($name in $first) {
    . (Join-Path -Path $PSScriptRoot -ChildPath $name)
}

foreach ($file in @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' |
        Where-Object { $_.Name -notin $first } | Sort-Object -Property Name)) {
    . $file.FullName
}

# Xmip.psd1 is the one home of the version and of what is exported: the
# manifest filters what this exports down to FunctionsToExport and
# AliasesToExport, and a function reads the version from its module object.
Export-ModuleMember -Function '*' -Alias '*'
