#requires -PSEdition Core
#requires -Version 7.6
<#
.SYNOPSIS
    Reads the Xmip manifest and flattens the estate.

.DESCRIPTION
    Shared by Xmip-Estate.ps1 and Xmip-Git.ps1. Both need to know what the
    estate is, and two copies of that knowledge would drift the way
    architecture.toml and architecture.json already have.

    The tree is the data. xmip.core.transport.ftp is xmip-core-transport-ftp:
    dots become hyphens and nothing else happens.
#>

# One version for the whole module. The reader enforces minimumScriptVersion,
# so the reader has to own the number; a copy inside Xmip-Estate's body was
# invisible from here and the check silently had nothing to compare against.
$script:XmipVersion = [version]'1.6.0'

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

function Convert-CommonRepository($Item, $Defaults) {
    if ($Item -is [System.Array]) {
        return [pscustomobject]@{
            name = [string]$Item[0]
            description = [string]$Item[1]
            architecturalDomain = [string]$Item[2]
            repositoryRole = [string]$Item[3]
            maturity = [string](Get-PropertyValue $Defaults 'maturity' 'reserved')
            dependencies = @($Item[4])
        }
    }
    return [pscustomobject]@{
        name = [string](Get-PropertyValue $Item 'name')
        description = [string](Get-PropertyValue $Item 'description')
        architecturalDomain = [string](Get-PropertyValue $Item 'architecturalDomain')
        repositoryRole = [string](Get-PropertyValue $Item 'repositoryRole')
        maturity = [string](Get-PropertyValue $Item 'maturity' (Get-PropertyValue $Defaults 'maturity' 'reserved'))
        dependencies = @(Get-PropertyValue $Item 'dependencies' @())
    }
}

function Convert-TechnologyGroup($Group) {
    if ($Group -is [System.Array]) {
        return [pscustomobject]@{
            parent = [string]$Group[0]
            dependencies = @($Group[1])
            technologies = @($Group[2])
        }
    }
    return [pscustomobject]@{
        parent = [string](Get-PropertyValue $Group 'parent')
        dependencies = @(Get-PropertyValue $Group 'dependencies' @())
        technologies = @(Get-PropertyValue $Group 'technologies' @())
    }
}

function Expand-XmipManifest($Source) {
    $existing = @(Get-PropertyValue $Source 'repositories' @())
    if ($existing.Count -gt 0) { return $Source }

    $defaults = Get-PropertyValue $Source 'defaults' ([pscustomobject]@{})
    $cratePolicy = Get-PropertyValue $Source 'cratePolicy' ([pscustomobject]@{})
    $repositories = [Collections.Generic.List[object]]::new()

    foreach ($raw in @(Get-PropertyValue $Source 'commonRepositories' @())) {
        $item = Convert-CommonRepository $raw $defaults
        $domain = [string]$item.architecturalDomain
        $repositories.Add([pscustomobject]@{
            name = $item.name
            description = $item.description
            architecturalDomain = $domain
            repositoryRole = $item.repositoryRole
            maturity = $item.maturity
            dependencies = @($item.dependencies)
            primaryCrate = [pscustomobject]@{
                name = $item.name
                language = [string](Get-PropertyValue $cratePolicy 'language' 'rust')
                edition = [string](Get-PropertyValue $cratePolicy 'edition' '2024')
                license = [string](Get-PropertyValue $cratePolicy 'license' (Get-PropertyValue $defaults 'license' 'NOASSERTION'))
            }
            github = [pscustomobject]@{
                visibility = [string](Get-PropertyValue $defaults 'visibility' 'public')
                autoInitialize = [bool](Get-PropertyValue $defaults 'autoInitialize' $true)
                hasIssues = [bool](Get-PropertyValue $defaults 'hasIssues' $true)
                hasProjects = [bool](Get-PropertyValue $defaults 'hasProjects' $false)
                hasWiki = [bool](Get-PropertyValue $defaults 'hasWiki' $false)
                topics = @('xmip', $domain.ToLowerInvariant())
            }
            submodule = [pscustomobject]@{ enabled = $false }
        })
    }

    foreach ($rawGroup in @(Get-PropertyValue $Source 'technologyGroups' @())) {
        $group = Convert-TechnologyGroup $rawGroup
        $capability = $group.parent -replace '^xmip-',''
        foreach ($rawTechnology in @($group.technologies)) {
            $technology = if ($rawTechnology -is [string]) {
                [pscustomobject]@{ name = $rawTechnology }
            }
            else {
                $rawTechnology
            }
            $technologyName = [string](Get-PropertyValue $technology 'name')
            $repositoryName = "$($group.parent)-$technologyName"
            $technologyDependencies = @($group.dependencies) + @(Get-PropertyValue $technology 'dependencies' @())
            $technologyDependencies = @(
                $technologyDependencies |
                    ForEach-Object { [string]$_ } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                    Select-Object -Unique
            )
            $repositories.Add([pscustomobject]@{
                name = $repositoryName
                description = [string](Get-PropertyValue $technology 'description' "$technologyName implementation of $($group.parent).")
                architecturalDomain = 'Technology'
                repositoryRole = 'technology-implementation'
                maturity = [string](Get-PropertyValue $technology 'maturity' (Get-PropertyValue $defaults 'maturity' 'reserved'))
                capability = $capability
                technology = $technologyName
                parent = $group.parent
                dependencies = @($technologyDependencies)
                primaryCrate = [pscustomobject]@{
                    name = [string](Get-PropertyValue $technology 'crateName' $repositoryName)
                    language = [string](Get-PropertyValue $cratePolicy 'language' 'rust')
                    edition = [string](Get-PropertyValue $technology 'crateEdition' (Get-PropertyValue $cratePolicy 'edition' '2024'))
                    license = [string](Get-PropertyValue $cratePolicy 'license' (Get-PropertyValue $defaults 'license' 'NOASSERTION'))
                }
                github = [pscustomobject]@{
                    visibility = [string](Get-PropertyValue $defaults 'visibility' 'public')
                    autoInitialize = [bool](Get-PropertyValue $defaults 'autoInitialize' $true)
                    hasIssues = [bool](Get-PropertyValue $defaults 'hasIssues' $true)
                    hasProjects = [bool](Get-PropertyValue $defaults 'hasProjects' $false)
                    hasWiki = [bool](Get-PropertyValue $defaults 'hasWiki' $false)
                    topics = @('xmip','technology',$capability,$technologyName)
                }
                submodule = [pscustomobject]@{
                    enabled = $true
                    parentRepository = $group.parent
                    path = [string](Get-PropertyValue $technology 'submodulePath' "modules/$technologyName")
                    revision = Get-PropertyValue $technology 'revision'
                }
            })
        }
    }

    $Source | Add-Member -NotePropertyName repositories -NotePropertyValue @($repositories.ToArray()) -Force
    return $Source
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

    $isToml = [IO.Path]::GetExtension($Path) -ieq '.toml'

    if ($isToml) {
        if (-not (Get-Module -ListAvailable -Name PSToml)) {
            throw 'Reading a TOML manifest needs PSToml. Run Install-XmipPrerequisite.ps1 -Role developer, or Install-Module PSToml -Scope CurrentUser.'
        }
        Import-Module PSToml -ErrorAction Stop
        $source = Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Toml
    }
    else {
        $source = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 100
    }

    $minimumScriptVersion = Get-TomlValue $source 'minimumScriptVersion' $null
    if ($minimumScriptVersion -and $script:XmipVersion -lt [version]$minimumScriptVersion) {
        throw "Manifest requires script version $minimumScriptVersion; current version is $script:XmipVersion."
    }

    if ($isToml) { return Expand-XmipManifestFromTree $source }
    return Expand-XmipManifest $source
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
