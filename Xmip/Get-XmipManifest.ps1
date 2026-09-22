#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    Reading architecture.toml, checking its version, and validating what it declares.

.DESCRIPTION
    Apart from Xmip.psm1 since 2026-09-22, when that file was 977 lines against the
    400 the estate allows a file and the owner asked for the estate to be
    consolidated. One subject per file.

    Style: doc/governance/powershell-style.md
#>


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
        FallbackMaturity = [string](
            Get-TomlValue -Node $default -Name 'maturity' -Default 'reserved'
        )
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

    [hashtable] $member = @{
        NotePropertyName  = 'repositories'
        NotePropertyValue = @($repositories.ToArray())
        Force             = $true
    }

    $result | Add-Member @member

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

    [string] $required = [string](
        Get-TomlValue -Node $Source -Name 'minimumScriptVersion' -Default ''
    )

    if (-not [string]::IsNullOrWhiteSpace($required)) {
        if ($script:XmipVersion -lt [version]::Parse($required)) {
            throw "Manifest requires script version $required; this module is $script:XmipVersion."
        }
    }

    [string] $schemaVersion = [string](
        Get-TomlValue -Node $Source -Name 'schemaVersion' -Default ''
    )

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

    throw ("The manifest is schema $schemaVersion; this module reads " +
        "$($script:XmipSchemaMajor).x. $remedy")
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
        throw ('Reading a TOML manifest needs PSToml. ' +
            'Run Install-XmipPrerequisite -Role developer -Install.')
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
    [string] $maturity = [string](
        Get-PropertyValue -Object $Repository -Name 'maturity' -Default 'reserved'
    )

    $primaryCrate = (
        Get-PropertyValue -Object $Repository -Name 'primaryCrate' -Default ([pscustomobject]@{})
    )
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

    [object[]] $dependencies = @(
        Get-PropertyValue -Object $Repository -Name 'dependencies' -Default @()
    )

    foreach ($dependency in $dependencies) {
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
    [object[]] $repositories = @(
        Get-PropertyValue -Object $Manifest -Name 'repositories' -Default @()
    )

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

    # `[crate]`, where the manifest keeps it. This read schema 1's
    # `cratePolicy` until 2026-09-21, a table the manifest had not had for
    # weeks, so the default of false answered for it and the rule was never
    # checked; found while deleting the reader of the old shape.
    $crate = Get-TomlValue -Node $Manifest -Name 'crate' -Default $null

    [bool] $crateMustMatch = [bool](
        Get-TomlValue -Node $crate -Name 'primaryCrateMatchesRepository' -Default $false
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
