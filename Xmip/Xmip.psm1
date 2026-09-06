#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    Reads the Xmip manifest and flattens the estate.

.DESCRIPTION
    Shared by the three command files. All of them need to know what the estate
    is, and copies of that knowledge drift — which is exactly what
    architecture.toml and architecture.json did before the JSON one was deleted.

    The tree is the data. xmip.core.transport.ftp is xmip-core-transport-ftp:
    dots become hyphens and nothing else happens.

    Style: docs/governance/powershell-style.md
#>

Set-StrictMode -Version Latest

# One version for the whole module. The reader enforces minimumScriptVersion, so
# the reader owns the number; a copy inside Sync-XmipEstate's body was invisible
# from here and the check silently had nothing to compare against.
[version] $script:XmipVersion = [version]::Parse('1.20.0')

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
    'deprecated'
    'retired'
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

    [System.IO.DirectoryInfo] $directory = [System.IO.DirectoryInfo]::new($StartAt)

    while ($null -ne $directory) {
        [string] $candidate = Join-Path $directory.FullName 'architecture.toml'

        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $directory.FullName
        }

        $directory = $directory.Parent
    }

    throw "No architecture.toml found at or above '$StartAt'. Run this from inside the Xmip repository."
}


function Write-Step {
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    Write-Host "==> $Message" -ForegroundColor Cyan
}


function Get-PropertyValue {
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


function ConvertTo-Array {
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


function Get-TomlKey {
    <#
        Lists the keys of a TOML node. ConvertFrom-Toml has returned a dictionary
        in one version of PSToml and a PSObject in the next, so nothing here asks
        which it is.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Node
    )

    if ($null -eq $Node) {
        return @()
    }

    if ($Node -is [System.Collections.IDictionary]) {
        return @($Node.Keys)
    }

    return @($Node.PSObject.Properties.Name)
}


function Get-TomlValue {
    <#
        Reads one key from a TOML node, dictionary-shaped or object-shaped,
        returning $Default when absent or null.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Node,

        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $false)]
        $Default = $null
    )

    if ($null -eq $Node) {
        return $Default
    }

    if ($Node -is [System.Collections.IDictionary]) {
        if ($Node.Contains($Name) -and $null -ne $Node[$Name]) {
            return $Node[$Name]
        }

        return $Default
    }

    return (Get-PropertyValue -Object $Node -Name $Name -Default $Default)
}


function Test-XmipTable {
    <#
        True when a value is a child node of the estate tree. A child is a table;
        metadata is a scalar or an array.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Value
    )

    if ($null -eq $Value) {
        return $false
    }

    if ($Value -is [System.Collections.IDictionary]) {
        return $true
    }

    if ($Value -is [string] -or $Value -is [bool] -or $Value -is [array]) {
        return $false
    }

    return ($Value.PSObject.Properties.Count -gt 0)
}


function New-XmipCrateDescriptor {
    <#
        The primary Rust crate for a repository. A module carrying its own
        language is not a Rust crate: powershell and gui are the two, per
        ADR-0014 clause 14.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Language,

        [Parameter(Mandatory = $true)]
        $Crate,

        [Parameter(Mandatory = $true)]
        $Default
    )

    [string] $resolvedLanguage = $Language

    if ([string]::IsNullOrWhiteSpace($resolvedLanguage)) {
        $resolvedLanguage = [string](Get-TomlValue -Node $Crate -Name 'primaryLanguage' -Default 'rust')
    }

    [string] $fallbackLicense = [string](Get-TomlValue -Node $Default -Name 'license' -Default 'NOASSERTION')

    return [pscustomobject]@{
        name     = $Name
        language = $resolvedLanguage
        edition  = [string](Get-TomlValue -Node $Crate -Name 'edition' -Default '2021')
        license  = [string](Get-TomlValue -Node $Crate -Name 'license' -Default $fallbackLicense)
    }
}


function New-XmipGitHubDescriptor {
    <#
        The GitHub settings for a repository, all of them defaulted from
        [default] in the manifest.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        $Default,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $Topics
    )

    [string[]] $declared = @(Get-TomlValue -Node $Default -Name 'repositoryTopics' -Default @('xmip'))

    [string[]] $topicList = @(
        @($declared + $Topics) |
            ForEach-Object { [string] $_ } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique
    )

    return [pscustomobject]@{
        visibility     = [string](Get-TomlValue -Node $Default -Name 'visibility' -Default 'public')
        autoInitialize = [bool](Get-TomlValue -Node $Default -Name 'autoInitialize' -Default $true)
        hasIssues      = [bool](Get-TomlValue -Node $Default -Name 'hasIssues' -Default $true)
        hasProjects    = [bool](Get-TomlValue -Node $Default -Name 'hasProjects' -Default $false)
        hasWiki        = [bool](Get-TomlValue -Node $Default -Name 'hasWiki' -Default $false)
        topics         = $topicList
    }
}


function New-XmipRepositoryEntry {
    <#
        One flattened repository. Composition is Sync-XmipRepository's job per ADR-0016, so
        submodule.enabled is always false here.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [string] $Description,

        [Parameter(Mandatory = $true)]
        [string] $Domain,

        [Parameter(Mandatory = $true)]
        [string] $Role,

        [Parameter(Mandatory = $true)]
        [string] $Maturity,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $Dependencies,

        [Parameter(Mandatory = $true)]
        $Default,

        [Parameter(Mandatory = $true)]
        $Crate,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Language,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $Topics,

        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Mount = '',

        [Parameter(Mandatory = $false)]
        [bool] $Optional = $false
    )

    [hashtable] $crateArguments = @{
        Name     = $Name
        Language = $Language
        Crate    = $Crate
        Default  = $Default
    }

    return [pscustomobject]@{
        name                = $Name
        description         = $Description
        architecturalDomain = $Domain
        repositoryRole      = $Role
        maturity            = $Maturity
        dependencies        = @($Dependencies)
        mount               = $Mount
        optional            = $Optional
        primaryCrate        = New-XmipCrateDescriptor @crateArguments
        github              = New-XmipGitHubDescriptor -Default $Default -Topics $Topics
        submodule           = [pscustomobject]@{ enabled = $false }
    }
}


function Resolve-XmipNodeFacts {
    <#
        Everything about one node of the estate tree that is derived from its
        position rather than declared. Depth is the classification: one segment
        is a provider root, two a module, three an implementation.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        $Node,

        [Parameter(Mandatory = $true)]
        [string[]] $Path,

        [Parameter(Mandatory = $true)]
        [string] $FallbackMaturity
    )

    [string] $name = 'xmip-' + ($Path -join '-')
    [bool] $isImplementation = ($Path.Count -ge 3)
    [string] $parent = ''

    if ($isImplementation) {
        $parent = 'xmip-' + (($Path[0..($Path.Count - 2)]) -join '-')
    }

    [string[]] $dependency = @(Get-TomlValue -Node $Node -Name 'dependency' -Default @())

    if ($isImplementation) {
        $dependency = @($parent) + $dependency
    }

    [string] $domain = ''
    [string] $role = ''
    [string] $fallbackDescription = ''
    [string[]] $topics = @()

    # Branch rather than default-then-override. $Path[-2] only exists at depth
    # three, so assigning the implementation case as a default evaluates it for
    # the provider root as well and throws IndexOutOfRange on xmip.core.
    if ($isImplementation) {
        $domain = 'Technology'
        $role = 'technology-implementation'
        $fallbackDescription = "$($Path[-1]) implementation of $parent."
        $topics = @('technology', $Path[-2], $Path[-1])
    }
    else {
        $domain = [string](Get-TomlValue -Node $Node -Name 'architecturalDomain' -Default 'Capabilities')
        $role = [string](Get-TomlValue -Node $Node -Name 'repositoryRole' -Default 'common-capability')
        $fallbackDescription = "Xmip $($Path[-1]) module."
        $topics = @($domain.ToLowerInvariant())
    }

    return [pscustomobject]@{
        Name         = $name
        Description  = [string](Get-TomlValue -Node $Node -Name 'description' -Default $fallbackDescription)
        Domain       = $domain
        Role         = $role
        Maturity     = [string](Get-TomlValue -Node $Node -Name 'maturity' -Default $FallbackMaturity)
        Dependencies = $dependency
        Language     = [string](Get-TomlValue -Node $Node -Name 'primaryLanguage' -Default '')
        Topics       = $topics
        # Declared, not derived: an explicit mount overrides the computed path,
        # and optional marks a repository the estate builds without. ADR-0036.
        Mount        = [string](Get-TomlValue -Node $Node -Name 'mount' -Default '')
        Optional     = [bool](Get-TomlValue -Node $Node -Name 'optional' -Default $false)
    }
}


function Assert-XmipNoMetadataCollision {
    <#
        A child sharing a name with a metadata key cannot exist: TOML would have
        to hold a scalar and a table at one key. It silently lost
        xmip-core-authorize-role once. Never again quietly.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        $Node,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $Path
    )

    foreach ($key in (Get-TomlKey -Node $Node)) {
        if ($script:XmipMetadataKey -notcontains $key) {
            continue
        }

        if (-not (Test-XmipTable -Value (Get-TomlValue -Node $Node -Name $key))) {
            continue
        }

        [string] $where = $Path -join '.'

        throw "'$key' is a metadata key and cannot also name a child of xmip.$where. Rename the child."
    }
}


function Expand-XmipEstate {
    <#
        Walks xmip.<provider>[.<module>[.<standard>]] and flattens it into $Into.
        The path is the name: dots become hyphens and nothing else happens.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        $Node,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]] $Path = @(),

        [Parameter(Mandatory = $true)]
        $Default,

        [Parameter(Mandatory = $true)]
        $Crate,

        [Parameter(Mandatory = $true)]
        [string] $FallbackMaturity,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [Collections.Generic.List[object]] $Into
    )

    if ($Path.Count -ge 1) {
        $facts = Resolve-XmipNodeFacts -Node $Node -Path $Path -FallbackMaturity $FallbackMaturity

        [hashtable] $entry = @{
            Name         = $facts.Name
            Description  = $facts.Description
            Domain       = $facts.Domain
            Role         = $facts.Role
            Maturity     = $facts.Maturity
            Dependencies = $facts.Dependencies
            Language     = $facts.Language
            Topics       = $facts.Topics
            Mount        = $facts.Mount
            Optional     = $facts.Optional
            Default      = $Default
            Crate        = $Crate
        }

        $Into.Add((New-XmipRepositoryEntry @entry))
    }

    Assert-XmipNoMetadataCollision -Node $Node -Path $Path

    foreach ($key in ((Get-TomlKey -Node $Node) | Sort-Object)) {
        $child = Get-TomlValue -Node $Node -Name $key

        if (-not (Test-XmipTable -Value $child)) {
            continue
        }

        [hashtable] $recursion = @{
            Node             = $child
            Path             = ($Path + $key)
            Default          = $Default
            Crate            = $Crate
            FallbackMaturity = $FallbackMaturity
            Into             = $Into
        }

        Expand-XmipEstate @recursion
    }
}


function Expand-XmipManifestFromTree {
    <#
        Turns the parsed TOML into a manifest object carrying a flat
        repositories array alongside its original top-level keys.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        $Source
    )

    $default = Get-TomlValue -Node $Source -Name 'default' -Default ([pscustomobject]@{})
    $crate = Get-TomlValue -Node $Source -Name 'crate' -Default ([pscustomobject]@{})
    $estate = Get-TomlValue -Node $Source -Name 'xmip' -Default $null

    if ($null -eq $estate) {
        throw 'The manifest has no [xmip] estate. Is it schema 2.0?'
    }

    $repositories = [Collections.Generic.List[object]]::new()

    [hashtable] $walk = @{
        Node             = $estate
        Default          = $default
        Crate            = $crate
        FallbackMaturity = [string](Get-TomlValue -Node $default -Name 'maturity' -Default 'reserved')
        Into             = $repositories
    }

    Expand-XmipEstate @walk

    if ($repositories.Count -eq 0) {
        throw 'The manifest tree produced no repositories. Is it schema 2.0?'
    }

    $result = [pscustomobject]@{}

    foreach ($key in (Get-TomlKey -Node $Source)) {
        [hashtable] $member = @{
            NotePropertyName  = $key
            NotePropertyValue = (Get-TomlValue -Node $Source -Name $key)
            Force             = $true
        }

        $result | Add-Member @member
    }

    $result | Add-Member -NotePropertyName 'repositories' -NotePropertyValue @($repositories.ToArray()) -Force

    return $result
}


function Assert-XmipManifestVersion {
    <#
        Two gates, failing in opposite directions.

            minimumScriptVersion  the manifest needs a newer reader than this
            schemaVersion         the manifest is shaped in a way this reader
                                  does not understand

        A newer minor schema is accepted deliberately: 2.1 may add keys, and a
        reader that ignores unknown keys still reads the estate correctly. A
        newer major is refused, because it may have moved something this reader
        would then silently misread.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        $Source,

        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    [string] $required = [string](Get-TomlValue -Node $Source -Name 'minimumScriptVersion' -Default '')

    if (-not [string]::IsNullOrWhiteSpace($required)) {
        if ($script:XmipVersion -lt [version]::Parse($required)) {
            throw "Manifest requires script version $required; this module is $script:XmipVersion."
        }
    }

    [string] $schemaVersion = [string](Get-TomlValue -Node $Source -Name 'schemaVersion' -Default '')

    if ([string]::IsNullOrWhiteSpace($schemaVersion)) {
        throw "The manifest declares no schemaVersion: $Path"
    }

    [int] $schemaMajor = [int]::Parse(($schemaVersion -split '\.')[0])

    if ($schemaMajor -eq $script:XmipSchemaMajor) {
        return
    }

    [string] $remedy = 'The manifest predates the tree schema and must be migrated.'

    if ($schemaMajor -gt $script:XmipSchemaMajor) {
        $remedy = 'Update the module.'
    }

    throw "The manifest is schema $schemaVersion; this module reads $($script:XmipSchemaMajor).x. $remedy"
}


function Get-XmipManifest {
    <#
        Reads architecture.toml and returns it with the estate flattened.

        TOML only. architecture.json was schema 1 and is deleted; keeping a
        fallback would keep a second reader alive for a file that no longer
        exists, which is how the two drifted in the first place.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Manifest not found: $Path"
    }

    if ([IO.Path]::GetExtension($Path) -ine '.toml') {
        throw "The manifest must be TOML: $Path"
    }

    if (-not (Get-Module -ListAvailable -Name PSToml)) {
        throw 'Reading a TOML manifest needs PSToml. Run Install-XmipPrerequisite -Role developer -Install.'
    }

    Import-Module PSToml -ErrorAction Stop

    [string] $text = Get-Content -LiteralPath $Path -Raw -Encoding utf8
    $source = ConvertFrom-Toml -InputObject $text

    Assert-XmipManifestVersion -Source $source -Path $Path

    return (Expand-XmipManifestFromTree -Source $source)
}


function Assert-XmipRepositoryEntry {
    <#
        Validates one flattened repository against the naming, crate and
        maturity rules. Throws on the first violation, naming the repository.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        $Repository,

        [Parameter(Mandatory = $true)]
        [Collections.Generic.HashSet[string]] $KnownNames,

        [Parameter(Mandatory = $true)]
        [bool] $CrateMustMatchRepository
    )

    [string] $name = [string](Get-PropertyValue -Object $Repository -Name 'name')
    [string] $description = [string](Get-PropertyValue -Object $Repository -Name 'description')
    [string] $maturity = [string](Get-PropertyValue -Object $Repository -Name 'maturity' -Default 'reserved')

    $primaryCrate = Get-PropertyValue -Object $Repository -Name 'primaryCrate' -Default ([pscustomobject]@{})
    [string] $crateName = [string](Get-PropertyValue -Object $primaryCrate -Name 'name')

    if ($name -notmatch '^xmip-[a-z0-9]+(?:-[a-z0-9]+)*$') {
        throw "Invalid repository name: $name"
    }

    if ([string]::IsNullOrWhiteSpace($description)) {
        throw "Description missing: $name"
    }

    if ([string]::IsNullOrWhiteSpace($crateName)) {
        throw "Primary crate missing: $name"
    }

    if ($crateName -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') {
        throw "Invalid primary crate name '$crateName' for '$name'"
    }

    if ($CrateMustMatchRepository -and $crateName -cne $name) {
        throw "Primary crate '$crateName' must match repository '$name'."
    }

    if ($script:XmipMaturity -notcontains $maturity) {
        throw "Invalid maturity '$maturity' for '$name'"
    }

    foreach ($dependency in @(Get-PropertyValue -Object $Repository -Name 'dependencies' -Default @())) {
        if (-not $KnownNames.Contains([string] $dependency)) {
            throw "Unknown dependency '$dependency' for '$name'"
        }

        if ($dependency -eq $name) {
            throw "Self dependency: $name"
        }
    }
}


function Test-XmipManifest {
    <#
        Validates the whole manifest. Throws on the first problem rather than
        collecting them, because a manifest with one bad entry is not a manifest
        anything should act on.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        $Manifest
    )

    Write-Step -Message 'Validating architecture manifest'

    [string] $owner = [string](Get-PropertyValue -Object $Manifest -Name 'owner')
    [object[]] $repositories = @(Get-PropertyValue -Object $Manifest -Name 'repositories' -Default @())

    if ([string]::IsNullOrWhiteSpace($owner)) {
        throw 'Manifest owner is missing.'
    }

    if ($repositories.Count -eq 0) {
        throw 'Manifest contains no repositories.'
    }

    [string[]] $names = @(
        $repositories | ForEach-Object { [string](Get-PropertyValue -Object $_ -Name 'name') }
    )

    [object[]] $duplicates = @($names | Group-Object | Where-Object { $_.Count -gt 1 })

    if ($duplicates.Count -gt 0) {
        throw "Duplicate repositories: $($duplicates.Name -join ', ')"
    }

    $knownNames = [Collections.Generic.HashSet[string]]::new(
        [string[]] $names,
        [StringComparer]::OrdinalIgnoreCase
    )

    $cratePolicy = Get-PropertyValue -Object $Manifest -Name 'cratePolicy' -Default ([pscustomobject]@{})

    [bool] $crateMustMatch = [bool](
        Get-PropertyValue -Object $cratePolicy -Name 'primaryCrateMatchesRepository' -Default $false
    )

    foreach ($repository in $repositories) {
        [hashtable] $check = @{
            Repository               = $repository
            KnownNames               = $knownNames
            CrateMustMatchRepository = $crateMustMatch
        }

        Assert-XmipRepositoryEntry @check
    }
}


# The commands. Dot-sourced rather than duplicated, so they see the manifest
# reader above and the module is the single thing anyone imports.
#
# Install-XmipPrerequisite is here despite the bootstrap look of it: this module loads
# without PSToml, because Get-XmipManifest imports PSToml when called rather than
# at import time. So a bare machine can import the module and ask what it is
# missing. PowerShell itself is the only prerequisite Xmip cannot install, and
# #requires states that floor.
. (Join-Path $PSScriptRoot 'Install-XmipModule.ps1')
. (Join-Path $PSScriptRoot 'Install-XmipPrerequisite.ps1')
. (Join-Path $PSScriptRoot 'Sync-XmipEstate.ps1')
. (Join-Path $PSScriptRoot 'Sync-XmipRepository.ps1')
. (Join-Path $PSScriptRoot 'Publish-XmipChange.ps1')
. (Join-Path $PSScriptRoot 'New-XmipDecisionIndex.ps1')
. (Join-Path $PSScriptRoot 'Get-XmipHistory.ps1')
. (Join-Path $PSScriptRoot 'Start-XmipWeb.ps1')

[string[]] $script:XmipExport = @(
    'Install-XmipPrerequisite'
    'Sync-XmipEstate'
    'Sync-XmipRepository'
    'Get-XmipManifest'
    'Test-XmipManifest'
    'Expand-XmipEstate'
    'Get-XmipRepositoryRoot'
    'Install-XmipModule'
    'Publish-XmipChange'
    'Publish-XmipPin'
    'Get-XmipStatus'
    'Get-XmipDecisionRecord'
    'New-XmipDecisionIndex'
    'Get-XmipHistory'
    'Start-XmipWeb'
)

Export-ModuleMember -Function $script:XmipExport -Alias @('xmip-git', 'xgit')
