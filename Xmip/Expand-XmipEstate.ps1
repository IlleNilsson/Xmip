#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    Turning the manifest's tree into repositories: where each is, what it is, what it depends on.

.DESCRIPTION
    Apart from Xmip.psm1 since 2026-09-22, when that file was 977 lines against the
    400 the estate allows a file and the owner asked for the estate to be
    consolidated. One subject per file.

    Style: doc/governance/powershell-style.md
#>


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
        $resolvedLanguage = [string](
            Get-TomlValue -Node $Crate -Name 'primaryLanguage' -Default 'rust'
        )
    }

    [string] $fallbackLicense = [string](
        Get-TomlValue -Node $Default -Name 'license' -Default 'NOASSERTION'
    )

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

    [string[]] $declared = @(
        Get-TomlValue -Node $Default -Name 'repositoryTopics' -Default @('xmip')
    )

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
        $domain = [string](
            Get-TomlValue -Node $Node -Name 'architecturalDomain' -Default 'Capabilities'
        )
        $role = [string](
            Get-TomlValue -Node $Node -Name 'repositoryRole' -Default 'common-capability'
        )
        $fallbackDescription = "Xmip $($Path[-1]) module."
        $topics = @($domain.ToLowerInvariant())
    }

    return [pscustomobject]@{
        Name         = $name
        Description  = [string](
            Get-TomlValue -Node $Node -Name 'description' -Default $fallbackDescription
        )
        Domain       = $domain
        Role         = $role
        Maturity     = [string](
            Get-TomlValue -Node $Node -Name 'maturity' -Default $FallbackMaturity
        )
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

        throw ("'$key' is a metadata key and cannot also name a child of xmip.$where. " +
            'Rename the child.')
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
