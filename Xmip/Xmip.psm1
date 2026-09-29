#requires -PSEdition Core
#requires -Version 7.6.5

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

    throw "No architecture.toml found at or above '$StartAt' or where this module lives ($origin)."
}


function Find-XmipRepositoryRoot {
    <#
        Walks up from one directory until architecture.toml appears; empty
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
        [string] $candidate = Join-Path $directory.FullName 'architecture.toml'

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
. (Join-Path $PSScriptRoot 'Read-XmipToml.ps1')
. (Join-Path $PSScriptRoot 'Expand-XmipEstate.ps1')
. (Join-Path $PSScriptRoot 'Get-XmipManifest.ps1')
. (Join-Path $PSScriptRoot 'Install-XmipModule.ps1')
. (Join-Path $PSScriptRoot 'Test-XmipFloor.ps1')
. (Join-Path $PSScriptRoot 'Install-XmipPrerequisite.ps1')
. (Join-Path $PSScriptRoot 'Install-XmipEventSource.ps1')
. (Join-Path $PSScriptRoot 'New-XmipPrerequisiteResult.ps1')
. (Join-Path $PSScriptRoot 'Get-XmipComposePlan.ps1')
. (Join-Path $PSScriptRoot 'Get-XmipUnexpectedName.ps1')
. (Join-Path $PSScriptRoot 'Get-XmipCrateFinding.ps1')
. (Join-Path $PSScriptRoot 'Invoke-XmipGitHubApi.ps1')
. (Join-Path $PSScriptRoot 'New-XmipTransactionReport.ps1')
. (Join-Path $PSScriptRoot 'New-XmipRepository.ps1')
. (Join-Path $PSScriptRoot 'Invoke-XmipGit.ps1')
. (Join-Path $PSScriptRoot 'Move-XmipSubmodule.ps1')
. (Join-Path $PSScriptRoot 'Invoke-XmipCompose.ps1')
. (Join-Path $PSScriptRoot 'Update-XmipDeployList.ps1')
. (Join-Path $PSScriptRoot 'Sync-XmipEstate.ps1')
. (Join-Path $PSScriptRoot 'Invoke-XmipDistribution.ps1')
. (Join-Path $PSScriptRoot 'Sync-XmipRepository.ps1')
. (Join-Path $PSScriptRoot 'Publish-XmipChange.ps1')
. (Join-Path $PSScriptRoot 'Get-XmipStatus.ps1')
. (Join-Path $PSScriptRoot 'Get-XmipSubmodule.ps1')
. (Join-Path $PSScriptRoot 'Get-XmipDeclaredModule.ps1')
. (Join-Path $PSScriptRoot 'Test-XmipModule.ps1')
. (Join-Path $PSScriptRoot 'Test-XmipDotnetModule.ps1')
. (Join-Path $PSScriptRoot 'Submit-XmipModule.ps1')
. (Join-Path $PSScriptRoot 'Publish-XmipPin.ps1')
. (Join-Path $PSScriptRoot 'Get-XmipDecisionRecord.ps1')
. (Join-Path $PSScriptRoot 'New-XmipIndexEntry.ps1')
. (Join-Path $PSScriptRoot 'New-XmipDecisionIndex.ps1')
. (Join-Path $PSScriptRoot 'Get-XmipRepositoryUse.ps1')
. (Join-Path $PSScriptRoot 'Get-XmipEstateRepository.ps1')
. (Join-Path $PSScriptRoot 'Get-XmipSourceFile.ps1')
. (Join-Path $PSScriptRoot 'Add-XmipMapMount.ps1')
. (Join-Path $PSScriptRoot 'New-XmipMapTree.ps1')
. (Join-Path $PSScriptRoot 'New-XmipEstatePage.ps1')
. (Join-Path $PSScriptRoot 'New-XmipMapDomain.ps1')
. (Join-Path $PSScriptRoot 'New-XmipMapPreamble.ps1')
. (Join-Path $PSScriptRoot 'New-XmipEstateMap.ps1')
. (Join-Path $PSScriptRoot 'Get-XmipHistory.ps1')

# Xmip's test suites — the Playground is the first — and the web monitor on
# this machine: Start, Get and Stop for
# each of the roll, the emulated nodes and the web host, and Get for what a run
# says. Nothing in the estate starts any of them on its own (owner, 2026-09-12).
. (Join-Path $PSScriptRoot 'Read-XmipTestSuiteDeclaration.ps1')
. (Join-Path $PSScriptRoot 'Get-XmipTestSuite.ps1')
. (Join-Path $PSScriptRoot 'Get-XmipPlaygroundLayout.ps1')
. (Join-Path $PSScriptRoot 'New-XmipPlaygroundImage.ps1')
. (Join-Path $PSScriptRoot 'Get-XmipPlaygroundProcess.ps1')
. (Join-Path $PSScriptRoot 'Resolve-XmipClusterFile.ps1')
. (Join-Path $PSScriptRoot 'Import-XmipOperatorModule.ps1')
. (Join-Path $PSScriptRoot 'Write-XmipAudit.ps1')
. (Join-Path $PSScriptRoot 'Get-XmipNodeCapability.ps1')
. (Join-Path $PSScriptRoot 'Get-XmipNodeComplement.ps1')
. (Join-Path $PSScriptRoot 'New-XmipPlaygroundEnvironment.ps1')
. (Join-Path $PSScriptRoot 'Get-XmipRollRecord.ps1')
. (Join-Path $PSScriptRoot 'New-XmipTestStatus.ps1')
. (Join-Path $PSScriptRoot 'Start-XmipTestSuiteGroup.ps1')
. (Join-Path $PSScriptRoot 'Start-XmipEstateSuite.ps1')
. (Join-Path $PSScriptRoot 'Complete-XmipEstateRun.ps1')
. (Join-Path $PSScriptRoot 'Resolve-XmipPlaygroundChoice.ps1')
. (Join-Path $PSScriptRoot 'Start-XmipPlaygroundRoll.ps1')
. (Join-Path $PSScriptRoot 'Start-XmipTest.ps1')
. (Join-Path $PSScriptRoot 'Get-XmipTestStatus.ps1')
. (Join-Path $PSScriptRoot 'Get-XmipEstateRun.ps1')
. (Join-Path $PSScriptRoot 'Select-XmipTestRoll.ps1')
. (Join-Path $PSScriptRoot 'Stop-XmipTest.ps1')
. (Join-Path $PSScriptRoot 'Stop-XmipTestCluster.ps1')
. (Join-Path $PSScriptRoot 'Start-XmipTestNode.ps1')
. (Join-Path $PSScriptRoot 'Get-XmipTestNode.ps1')
. (Join-Path $PSScriptRoot 'Stop-XmipTestNode.ps1')
. (Join-Path $PSScriptRoot 'Get-XmipTestResult.ps1')
. (Join-Path $PSScriptRoot 'Wait-XmipSnapshot.ps1')
. (Join-Path $PSScriptRoot 'Start-XmipOperationWeb.ps1')
. (Join-Path $PSScriptRoot 'Get-XmipOperationWeb.ps1')
. (Join-Path $PSScriptRoot 'Stop-XmipOperationWeb.ps1')
. (Join-Path $PSScriptRoot 'Get-XmipProcess.ps1')

# Xmip.psd1 is the one home of the version and of what is exported: the
# manifest filters what this exports down to FunctionsToExport and
# AliasesToExport, and a function reads the version from its module object.
Export-ModuleMember -Function '*' -Alias '*'
