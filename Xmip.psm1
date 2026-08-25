#requires -PSEdition Core
#requires -Version 7.6
<#
.SYNOPSIS
    Reads the Xmip manifest and flattens the estate.

.DESCRIPTION
    Shared by Xmip-Estate.ps1 and Xmip-Git.ps1. Both need to know what the
    estate is, and two copies of that knowledge drift — which is exactly what
    architecture.toml and architecture.json did before the JSON one was
    deleted.

    The tree is the data. xmip.core.transport.ftp is xmip-core-transport-ftp:
    dots become hyphens and nothing else happens.
#>

# One version for the whole module. The reader enforces minimumScriptVersion,
# so the reader has to own the number; a copy inside Xmip-Estate's body was
# invisible from here and the check silently had nothing to compare against.
$script:XmipVersion = [version]'1.6.0'

# The manifest schema this module understands. Major is the compatibility
# boundary: 2.x is the tree-is-the-name schema, and a 3.0 manifest will mean
# something this reader does not know. Refusing it is the whole point of the
# field — declaring a version nothing checks is worse than declaring none,
# because it looks like a guarantee.
$script:XmipSchemaMajor = 2

Set-StrictMode -Version 3.0

function Write-Step([string] $Message) { Write-Host "==> $Message" -ForegroundColor Cyan }

function Get-PropertyValue {
    param([AllowNull()] $Object, [Parameter(Mandatory)] [string] $Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return $Default }
    return $property.Value
}

function ConvertTo-Array($Value) {
    if ($null -eq $Value) { return @() }
    return @($Value)
}

function Get-TomlKey($Node) {
    if ($null -eq $Node) { return @() }
    if ($Node -is [System.Collections.IDictionary]) { return @($Node.Keys) }
    return @($Node.PSObject.Properties.Name)
}

function Get-TomlValue($Node, [Parameter(Mandatory)] [string] $Name, $Default = $null) {
    if ($null -eq $Node) { return $Default }
    if ($Node -is [System.Collections.IDictionary]) {
        if ($Node.Contains($Name) -and $null -ne $Node[$Name]) { return $Node[$Name] }
        return $Default
    }
    $property = $Node.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return $Default }
    return $property.Value
}

function New-XmipRepositoryEntry {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Description,
        [Parameter(Mandatory)] [string] $Domain,
        [Parameter(Mandatory)] [string] $Role,
        [Parameter(Mandatory)] [string] $Maturity,
        [string[]] $Dependencies = @(),
        [Parameter(Mandatory)] $Default,
        [Parameter(Mandatory)] $Crate,
        [string] $Language,
        [string[]] $Topics = @()
    )

    $topicList = @(@(Get-TomlValue $Default 'repositoryTopics' @('xmip')) + $Topics |
            ForEach-Object { [string]$_ } |
            Where-Object { $_ } |
            Select-Object -Unique)

    return [pscustomobject]@{
        name = $Name
        description = $Description
        architecturalDomain = $Domain
        repositoryRole = $Role
        maturity = $Maturity
        dependencies = @($Dependencies)
        primaryCrate = [pscustomobject]@{
            name = $Name
            # A module carrying its own language is not a Rust crate. powershell
            # and gui are the two, per ADR-0014 clause 14.
            language = if ($Language) { $Language } else { [string](Get-TomlValue $Crate 'primaryLanguage' 'rust') }
            edition = [string](Get-TomlValue $Crate 'edition' '2021')
            license = [string](Get-TomlValue $Crate 'license' (Get-TomlValue $Default 'license' 'NOASSERTION'))
        }
        github = [pscustomobject]@{
            visibility = [string](Get-TomlValue $Default 'visibility' 'public')
            autoInitialize = [bool](Get-TomlValue $Default 'autoInitialize' $true)
            hasIssues = [bool](Get-TomlValue $Default 'hasIssues' $true)
            hasProjects = [bool](Get-TomlValue $Default 'hasProjects' $false)
            hasWiki = [bool](Get-TomlValue $Default 'hasWiki' $false)
            topics = $topicList
        }
        # Composition is Sync-XmipSubmodule.ps1's job now, ADR-0016. This script
        # creates and configures repositories and says nothing about how they
        # are mounted.
        submodule = [pscustomobject]@{ enabled = $false }
    }
}

function Test-XmipTable($Value) {
    # A child in the estate is a table. Metadata is a scalar or an array.
    if ($null -eq $Value) { return $false }
    if ($Value -is [System.Collections.IDictionary]) { return $true }
    if ($Value -is [string] -or $Value -is [bool] -or $Value -is [array]) { return $false }
    return ($Value.PSObject.Properties.Count -gt 0)
}

function Expand-XmipEstate {
    <#
        Walk xmip.<provider>[.<module>[.<standard>]] and flatten it. The path is
        the name: dots become hyphens and nothing else happens. Depth is the
        classification — one segment is a provider root repository, two a
        module, three an implementation.
    #>
    param(
        [Parameter(Mandatory)] $Node,
        [string[]] $Path = @(),
        [Parameter(Mandatory)] $Default,
        [Parameter(Mandatory)] $Crate,
        [Parameter(Mandatory)] [string] $FallbackMaturity,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [Collections.Generic.List[object]] $Into
    )

    if ($Path.Count -ge 1) {
        $name = 'xmip-' + ($Path -join '-')
        $isImplementation = $Path.Count -ge 3
        $parent = if ($isImplementation) { 'xmip-' + (($Path[0..($Path.Count - 2)]) -join '-') } else { '' }

        $dependency = @(Get-TomlValue $Node 'dependency' @())
        if ($isImplementation) { $dependency = @($parent) + $dependency }

        $domain = if ($isImplementation) { 'Technology' }
        else { [string](Get-TomlValue $Node 'architecturalDomain' 'Capabilities') }

        $role = if ($isImplementation) { 'technology-implementation' }
        else { [string](Get-TomlValue $Node 'repositoryRole' 'common-capability') }

        $description = [string](Get-TomlValue $Node 'description' $(
                if ($isImplementation) { "$($Path[-1]) implementation of $parent." }
                else { "Xmip $($Path[-1]) module." }))

        $topics = if ($isImplementation) { @('technology', $Path[-2], $Path[-1]) }
        else { @($domain.ToLowerInvariant()) }

        $Into.Add((New-XmipRepositoryEntry `
                    -Name $name `
                    -Description $description `
                    -Domain $domain `
                    -Role $role `
                    -Maturity ([string](Get-TomlValue $Node 'maturity' $FallbackMaturity)) `
                    -Dependencies $dependency `
                    -Default $Default -Crate $Crate `
                    -Language ([string](Get-TomlValue $Node 'primaryLanguage' '')) `
                    -Topics $topics))
    }

    # A child sharing a name with a metadata key cannot exist: TOML would have
    # to hold a string and a table at one key. It silently lost
    # xmip-core-authorize-role once. Never again quietly.
    $metadata = @('description', 'architecturalDomain', 'repositoryRole', 'maturity', 'dependency', 'primaryLanguage')
    foreach ($key in (Get-TomlKey $Node)) {
        if ($metadata -contains $key -and (Test-XmipTable (Get-TomlValue $Node $key))) {
            throw "'$key' is a metadata key and cannot also name a child of xmip.$($Path -join '.'). Rename the child."
        }
    }

    foreach ($key in ((Get-TomlKey $Node) | Sort-Object)) {
        $child = Get-TomlValue $Node $key
        if (Test-XmipTable $child) {
            Expand-XmipEstate -Node $child -Path ($Path + $key) `
                -Default $Default -Crate $Crate -FallbackMaturity $FallbackMaturity -Into $Into
        }
    }
}

function Expand-XmipManifestFromTree($Source) {
    $default = Get-TomlValue $Source 'default' ([pscustomobject]@{})
    $crate = Get-TomlValue $Source 'crate' ([pscustomobject]@{})
    $estate = Get-TomlValue $Source 'xmip' $null

    if ($null -eq $estate) {
        throw 'The manifest has no [xmip] estate. Is it schema 2.0?'
    }

    $repositories = [Collections.Generic.List[object]]::new()
    Expand-XmipEstate -Node $estate -Default $default -Crate $crate `
        -FallbackMaturity ([string](Get-TomlValue $default 'maturity' 'reserved')) -Into $repositories

    if ($repositories.Count -eq 0) {
        throw 'The manifest tree produced no repositories. Is it schema 2.0?'
    }

    $result = [pscustomobject]@{}
    foreach ($key in (Get-TomlKey $Source)) {
        $result | Add-Member -NotePropertyName $key -NotePropertyValue (Get-TomlValue $Source $key) -Force
    }
    $result | Add-Member -NotePropertyName repositories -NotePropertyValue @($repositories.ToArray()) -Force
    return $result
}

function Get-XmipManifest([string] $Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Manifest not found: $Path"
    }

    # TOML only. architecture.json was schema 1 and is deleted; keeping a
    # fallback would keep a second reader alive for a file that no longer
    # exists, which is how the two drifted in the first place.
    if ([IO.Path]::GetExtension($Path) -ine '.toml') {
        throw "The manifest must be TOML: $Path"
    }
    if (-not (Get-Module -ListAvailable -Name PSToml)) {
        throw 'Reading a TOML manifest needs PSToml. Run Install-XmipPrerequisite.ps1 -Role developer, or Install-Module PSToml -Scope CurrentUser.'
    }
    Import-Module PSToml -ErrorAction Stop
    $source = Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Toml

    # Two gates, and they fail in opposite directions.
    #
    # minimumScriptVersion: the manifest needs a newer reader than this one.
    # schemaVersion:        the manifest is shaped in a way this reader does
    #                       not understand.
    #
    # A newer minor schema is accepted deliberately: 2.1 may add keys, and a
    # reader that ignores keys it does not know still reads the estate
    # correctly. A newer major is refused, because it may have moved something
    # this reader would then silently misread.
    $minimumScriptVersion = Get-TomlValue $source 'minimumScriptVersion' $null
    if ($minimumScriptVersion -and $script:XmipVersion -lt [version]$minimumScriptVersion) {
        throw "Manifest requires script version $minimumScriptVersion; current version is $script:XmipVersion."
    }

    $schemaVersion = [string](Get-TomlValue $source 'schemaVersion' '')
    if (-not $schemaVersion) {
        throw "The manifest declares no schemaVersion: $Path"
    }
    $schemaMajor = [int](($schemaVersion -split '\.')[0])
    if ($schemaMajor -ne $script:XmipSchemaMajor) {
        throw "The manifest is schema $schemaVersion; this module reads schema $($script:XmipSchemaMajor).x. $(if ($schemaMajor -gt $script:XmipSchemaMajor) { 'Update the module.' } else { 'The manifest predates the tree schema and must be migrated.' })"
    }

    return Expand-XmipManifestFromTree $source
}

function Test-XmipManifest($Manifest) {
    Write-Step 'Validating architecture manifest'
    $owner = [string](Get-PropertyValue $Manifest 'owner')
    $repositories = @(Get-PropertyValue $Manifest 'repositories' @())
    if (-not $owner) { throw 'Manifest owner is missing.' }
    if ($repositories.Count -eq 0) { throw 'Manifest contains no repositories.' }

    $names = @($repositories | ForEach-Object { [string](Get-PropertyValue $_ 'name') })
    $duplicates = @($names | Group-Object | Where-Object Count -gt 1)
    if ($duplicates.Count -gt 0) {
        throw "Duplicate repositories: $($duplicates.Name -join ', ')"
    }

    $nameSet = [Collections.Generic.HashSet[string]]::new([string[]]$names, [StringComparer]::OrdinalIgnoreCase)
    $cratePolicy = Get-PropertyValue $Manifest 'cratePolicy' ([pscustomobject]@{})
    $primaryCrateMatchesRepository = [bool](Get-PropertyValue $cratePolicy 'primaryCrateMatchesRepository' $false)
    foreach ($repository in $repositories) {
        $name = [string](Get-PropertyValue $repository 'name')
        $description = [string](Get-PropertyValue $repository 'description')
        $maturity = [string](Get-PropertyValue $repository 'maturity' 'reserved')
        $submodule = Get-PropertyValue $repository 'submodule' ([pscustomobject]@{ enabled = $false })
        $parent = [string](Get-PropertyValue $repository 'parent')
        $primaryCrate = Get-PropertyValue $repository 'primaryCrate' ([pscustomobject]@{})
        $crateName = [string](Get-PropertyValue $primaryCrate 'name')

        if ($name -notmatch '^xmip-[a-z0-9]+(?:-[a-z0-9]+)*$') { throw "Invalid repository name: $name" }
        if (-not $description) { throw "Description missing: $name" }
        if (-not $crateName) { throw "Primary crate missing: $name" }
        if ($crateName -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') { throw "Invalid primary crate name '$crateName' for '$name'" }
        if ($primaryCrateMatchesRepository -and $crateName -cne $name) {
            throw "Primary crate '$crateName' must match repository '$name'."
        }
        if ($maturity -notin @('planned','reserved','created','configured','submodule','workspace','scaffolded','implemented','verified','supported','deprecated','retired')) {
            throw "Invalid maturity '$maturity' for '$name'"
        }
        if ([bool](Get-PropertyValue $submodule 'enabled' $false) -and -not $nameSet.Contains($parent)) {
            throw "Unknown parent '$parent' for '$name'"
        }
        foreach ($dependency in @(Get-PropertyValue $repository 'dependencies' @())) {
            if (-not $nameSet.Contains([string]$dependency)) { throw "Unknown dependency '$dependency' for '$name'" }
            if ($dependency -eq $name) { throw "Self dependency: $name" }
        }
    }
}

# The two commands. Dot-sourced rather than duplicated, so they see the
# manifest reader above and the module is the single thing anyone imports.
. (Join-Path $PSScriptRoot 'Xmip-Estate.ps1')
. (Join-Path $PSScriptRoot 'Xmip-Git.ps1')

Export-ModuleMember -Function 'Xmip-Estate', 'Xmip-Git', 'Get-XmipManifest', 'Test-XmipManifest', 'Expand-XmipEstate'
