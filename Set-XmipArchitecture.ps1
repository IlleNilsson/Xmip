#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string] $ManifestPath = (Join-Path $PSScriptRoot 'architecture.toml'),
    [string] $WorkingDirectory = (Join-Path $PSScriptRoot '.xmip-work'),
    [string] $GitHubToken = $env:GITHUB_TOKEN,
    [string] $GitHubApiBaseUri = 'https://api.github.com',
    [switch] $Apply,
    [switch] $CreateRepositories,
    [switch] $ConfigureRepositories,
    [switch] $GenerateMetadata,
    [switch] $CommitChanges,
    [switch] $PushChanges,
    [switch] $IncludeReserved,
    [switch] $WriteReport,
    [string] $ReportPath = (Join-Path $WorkingDirectory 'architecture-report.json'),
    [switch] $PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ScriptVersion = [version]'1.5.0'

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

function Assert-Command([string] $Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found."
    }
}

function Invoke-Native {
    param(
        [Parameter(Mandatory)] [string] $FilePath,
        [string[]] $Arguments = @(),
        [string] $At = '',
        [switch] $CaptureOutput
    )

    $previous = $PWD
    try {
        if ($At) { Set-Location $At }
        if ($CaptureOutput) {
            $output = & $FilePath @Arguments 2>&1
        }
        else {
            & $FilePath @Arguments
        }
        if ($LASTEXITCODE -ne 0) {
            $details = if ($CaptureOutput) { "`n$($output -join "`n")" } else { '' }
            throw "Command failed: $FilePath $($Arguments -join ' ')$details"
        }
        if ($CaptureOutput) { return @($output) }
    }
    finally {
        Set-Location $previous
    }
}

function Get-GitHubHeaders {
    $headers = @{
        Accept = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
        'User-Agent' = 'Xmip-Architecture-Reconciler'
    }
    if ($GitHubToken) { $headers.Authorization = "Bearer $GitHubToken" }
    return $headers
}

function Invoke-GitHubApi {
    param(
        [Parameter(Mandatory)] [ValidateSet('GET','POST','PATCH','PUT','DELETE')] [string] $Method,
        [Parameter(Mandatory)] [string] $Path,
        $Body
    )

    $uri = if ($Path -match '^https?://') {
        $Path
    }
    else {
        "$($GitHubApiBaseUri.TrimEnd('/'))/$($Path.TrimStart('/'))"
    }

    $parameters = @{
        Method = $Method
        Uri = $uri
        Headers = Get-GitHubHeaders
        ErrorAction = 'Stop'
    }
    if ($PSBoundParameters.ContainsKey('Body')) {
        $parameters.ContentType = 'application/json'
        $parameters.Body = $Body | ConvertTo-Json -Depth 50
    }
    return Invoke-RestMethod @parameters
}

function Test-GitHubRepositoryExists {
    param(
        [Parameter(Mandatory)] [string] $Owner,
        [Parameter(Mandatory)] [string] $Name
    )

    try {
        $repository = Invoke-GitHubApi GET "/repos/$Owner/$Name"
        return [pscustomobject]@{ Exists = $true; Repository = $repository }
    }
    catch {
        $statusCode = $null
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }
        if ($statusCode -eq 404) {
            return [pscustomobject]@{ Exists = $false; Repository = $null }
        }
        throw
    }
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

# ---------------------------------------------------------------------------
# Schema 2.0. The tree is the data: a repository name is derived from its
# position, so a name cannot drift from the structure that owns it.
#
#   platform.xmip-core                                    -> xmip-core
#   provider.core.module.transport                        -> xmip-core-transport
#   provider.core.module.transport.implementation.kafka   -> xmip-core-transport-kafka
#
# The tree is flattened into the same repository shape schema 1 produced, so
# everything downstream is untouched by which file it came from.
#
# ConvertFrom-Toml has returned a dictionary in one version and an object in
# the next. Which one it is should not be a thing this script has an opinion
# about, so it never asks directly.
# ---------------------------------------------------------------------------

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
            language = if ($Language) { $Language } else { [string](Get-TomlValue $Crate 'language' 'rust') }
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
        # Composition is Set-XmipSubmodule.ps1's job now, ADR-0016. This script
        # creates and configures repositories and says nothing about how they
        # are mounted.
        submodule = [pscustomobject]@{ enabled = $false }
    }
}

function Expand-XmipManifestFromTree($Source) {
    $default = Get-TomlValue $Source 'default' ([pscustomobject]@{})
    $crate = Get-TomlValue $Source 'crate' ([pscustomobject]@{})
    $fallbackMaturity = [string](Get-TomlValue $default 'maturity' 'reserved')
    $repositories = [Collections.Generic.List[object]]::new()

    foreach ($name in (Get-TomlKey (Get-TomlValue $Source 'platform' $null) | Sort-Object)) {
        $node = Get-TomlValue (Get-TomlValue $Source 'platform' $null) $name
        $repositories.Add((New-XmipRepositoryEntry `
            -Name $name `
            -Description ([string](Get-TomlValue $node 'description' "Xmip platform repository $name.")) `
            -Domain ([string](Get-TomlValue $node 'domain' 'Foundation')) `
            -Role ([string](Get-TomlValue $node 'role' 'common-architecture')) `
            -Maturity ([string](Get-TomlValue $node 'maturity' $fallbackMaturity)) `
            -Dependencies @(Get-TomlValue $node 'dependency' @()) `
            -Default $default -Crate $crate `
            -Language ([string](Get-TomlValue $node 'language' '')) `
            -Topics @('foundation')))
    }

    $providers = Get-TomlValue $Source 'provider' $null
    foreach ($providerName in (Get-TomlKey $providers | Sort-Object)) {
        $modules = Get-TomlValue (Get-TomlValue $providers $providerName) 'module' $null

        foreach ($moduleName in (Get-TomlKey $modules | Sort-Object)) {
            $module = Get-TomlValue $modules $moduleName
            $moduleRepository = "xmip-$providerName-$moduleName"
            $domain = [string](Get-TomlValue $module 'domain' 'Capabilities')

            $repositories.Add((New-XmipRepositoryEntry `
                -Name $moduleRepository `
                -Description ([string](Get-TomlValue $module 'description' "Xmip $moduleName module.")) `
                -Domain $domain `
                -Role ([string](Get-TomlValue $module 'role' 'common-capability')) `
                -Maturity ([string](Get-TomlValue $module 'maturity' $fallbackMaturity)) `
                -Dependencies @(Get-TomlValue $module 'dependency' @()) `
                -Default $default -Crate $crate `
                -Language ([string](Get-TomlValue $module 'language' '')) `
                -Topics @($domain.ToLowerInvariant())))

            $implementations = Get-TomlValue $module 'implementation' $null
            foreach ($standard in (Get-TomlKey $implementations | Sort-Object)) {
                $implementation = Get-TomlValue $implementations $standard
                $implementationRepository = "$moduleRepository-$standard"

                $repositories.Add((New-XmipRepositoryEntry `
                    -Name $implementationRepository `
                    -Description ([string](Get-TomlValue $implementation 'description' "$standard implementation of $moduleRepository.")) `
                    -Domain 'Technology' `
                    -Role 'technology-implementation' `
                    -Maturity ([string](Get-TomlValue $implementation 'maturity' $fallbackMaturity)) `
                    -Dependencies (@($moduleRepository) + @(Get-TomlValue $implementation 'dependency' @())) `
                    -Default $default -Crate $crate `
                    -Language ([string](Get-TomlValue $implementation 'language' '')) `
                    -Topics @('technology', $moduleName, $standard)))
            }
        }
    }

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
    if ($minimumScriptVersion -and $ScriptVersion -lt [version]$minimumScriptVersion) {
        throw "Manifest requires script version $minimumScriptVersion; current version is $ScriptVersion."
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

function Get-ActualRepositories {
    param([Parameter(Mandatory)] $Manifest)

    $owner = [string](Get-PropertyValue $Manifest 'owner')
    $actual = [Collections.Generic.List[object]]::new()
    foreach ($repository in @(Get-PropertyValue $Manifest 'repositories' @())) {
        $name = [string](Get-PropertyValue $repository 'name')
        $result = Test-GitHubRepositoryExists -Owner $owner -Name $name
        if ($result.Exists) {
            $actual.Add($result.Repository)
        }
    }
    return @($actual.ToArray())
}

function New-TransactionReport($Manifest, $Actual) {
    $desired = @{}
    foreach ($repository in @(Get-PropertyValue $Manifest 'repositories' @())) {
        $desired[[string](Get-PropertyValue $repository 'name')] = $repository
    }

    $actualMap = @{}
    foreach ($repository in @(ConvertTo-Array $Actual)) {
        if ($null -ne $repository) {
            $actualMap[[string](Get-PropertyValue $repository 'name')] = $repository
        }
    }

    return [ordered]@{
        generatedAtUtc = [DateTime]::UtcNow.ToString('o')
        scriptVersion = $ScriptVersion.ToString()
        schemaVersion = [string](Get-PropertyValue $Manifest 'schemaVersion' 'unversioned')
        architectureVersion = [string](Get-PropertyValue $Manifest 'architectureVersion' 'unversioned')
        owner = [string](Get-PropertyValue $Manifest 'owner')
        desiredCount = $desired.Count
        actualCount = $actualMap.Count
        missing = @($desired.Keys | Where-Object { -not $actualMap.ContainsKey($_) } | Sort-Object)
        unexpected = @()
        deprecated = @()
        retired = @()
        operations = [ordered]@{
            created = 0
            configured = 0
            metadataWritten = 0
            commits = 0
            pushes = 0
            skipped = 0
        }
    }
}

function New-XmipGitHubRepository {
    param(
        [Parameter(Mandatory)] $Repository,
        [Parameter(Mandatory)] [string] $Owner,
        [Parameter(Mandatory)] [ValidateSet('User','Organization')] [string] $OwnerType,
        [string] $Template
    )

    $name = [string](Get-PropertyValue $Repository 'name')
    $description = [string](Get-PropertyValue $Repository 'description')
    $github = Get-PropertyValue $Repository 'github' ([pscustomobject]@{})
    $visibility = [string](Get-PropertyValue $github 'visibility' 'public')
    if ($visibility -notin @('public','private','internal')) {
        throw "Unsupported GitHub visibility '$visibility' for '$name'."
    }
    if ($OwnerType -eq 'User' -and $visibility -eq 'internal') {
        throw "Visibility 'internal' is not valid for user-owned repository '$name'."
    }

    $settings = [ordered]@{
        has_issues = [bool](Get-PropertyValue $github 'hasIssues' $true)
        has_projects = [bool](Get-PropertyValue $github 'hasProjects' $false)
        has_wiki = [bool](Get-PropertyValue $github 'hasWiki' $false)
    }

    # The template is a Rust crate: Cargo.toml, src/lib.rs and a Rust workflow.
    # A module that is not a Rust crate must not be generated from it, or a
    # PowerShell module arrives holding a Cargo.toml. ADR-0014 clause 14.
    $primaryCrate = Get-PropertyValue $Repository 'primaryCrate' ([pscustomobject]@{})
    $language = [string](Get-PropertyValue $primaryCrate 'language' 'rust')
    if ($Template -and $language -ine 'rust') {
        Write-Warning "$name is language '$language', not rust. Creating it empty rather than from the Rust template; it needs its own scaffolding."
        $Template = ''
    }

    # A repository generated from the template starts with the licence, the
    # workflow and the layout every Xmip repository is supposed to have. A
    # blank one starts with nothing and someone has to remember to add them.
    if ($Template) {
        if ($Template -notmatch '^[^/]+/[^/]+$') {
            throw "Template must be owner/name, not '$Template'."
        }

        $body = [ordered]@{
            owner = $Owner
            name = $name
            description = $description
            include_all_branches = $false
            private = ($visibility -eq 'private')
        }

        $created = Invoke-GitHubApi POST "/repos/$Template/generate" $body

        # generate takes none of the feature switches, so they follow.
        $null = Invoke-GitHubApi PATCH "/repos/$Owner/$name" $settings
        return $created
    }

    $body = [ordered]@{
        name = $name
        description = $description
        private = ($visibility -eq 'private')
        auto_init = [bool](Get-PropertyValue $github 'autoInitialize' $true)
    }
    foreach ($key in $settings.Keys) { $body[$key] = $settings[$key] }
    if ($OwnerType -eq 'Organization') { $body.visibility = $visibility }

    $path = if ($OwnerType -eq 'Organization') { "/orgs/$Owner/repos" } else { '/user/repos' }
    return Invoke-GitHubApi POST $path $body
}

function Invoke-CreateRepositories {
    param(
        [Parameter(Mandatory)] $Manifest,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Report
    )

    if (-not $GitHubToken) {
        throw '-CreateRepositories requires -GitHubToken or GITHUB_TOKEN.'
    }

    $owner = [string](Get-PropertyValue $Manifest 'owner')
    $ownerInfo = Invoke-GitHubApi GET "/users/$owner"
    $ownerType = [string](Get-PropertyValue $ownerInfo 'type')
    if ($ownerType -notin @('User','Organization')) {
        throw "Unsupported GitHub owner type '$ownerType' for '$owner'."
    }

    if ($ownerType -eq 'User') {
        $currentUser = Invoke-GitHubApi GET '/user'
        $currentLogin = [string](Get-PropertyValue $currentUser 'login')
        if ($currentLogin -ine $owner) {
            throw "Authenticated GitHub user '$currentLogin' cannot create repositories for '$owner'."
        }
    }

    # crate.template in schema 2.0, cratePolicy.template in schema 1.
    $template = [string](Get-TomlValue (Get-TomlValue $Manifest 'crate' $null) 'template' `
        ([string](Get-PropertyValue (Get-PropertyValue $Manifest 'cratePolicy') 'template' '')))

    if ($template) {
        $templateInfo = Invoke-GitHubApi GET "/repos/$template"
        if (-not [bool](Get-PropertyValue $templateInfo 'is_template' $false)) {
            throw "'$template' is not marked as a template repository. Enable Settings, Template repository on it, or clear crate.template to create blank repositories."
        }
        Write-Step "Creating from template $template"
    }
    else {
        Write-Warning 'No crate.template in the manifest. Repositories will be created blank, with no licence, workflow or layout.'
    }

    $desired = @{}
    foreach ($repository in @(Get-PropertyValue $Manifest 'repositories' @())) {
        $desired[[string](Get-PropertyValue $repository 'name')] = $repository
    }

    foreach ($name in @($Report.missing)) {
        $repository = $desired[$name]
        if ($null -eq $repository) { throw "Missing repository definition for '$name'." }

        $maturity = [string](Get-PropertyValue $repository 'maturity' 'reserved')
        if ($maturity -eq 'reserved' -and -not $IncludeReserved) {
            Write-Warning "SKIPPED RESERVED: $name"
            $Report.operations.skipped++
            continue
        }

        $existing = Test-GitHubRepositoryExists -Owner $owner -Name $name
        if ($existing.Exists) {
            Write-Step "Repository already exists: $owner/$name"
            $Report.actualCount++
            $Report.missing = @($Report.missing | Where-Object { $_ -ine $name })
            $Report.operations.skipped++
            continue
        }

        if (-not $PSCmdlet.ShouldProcess("$owner/$name", 'Create GitHub repository')) {
            $Report.operations.skipped++
            continue
        }

        Write-Step "Creating repository $owner/$name"
        $created = New-XmipGitHubRepository -Repository $repository -Owner $owner -OwnerType $ownerType -Template $template
        $createdName = [string](Get-PropertyValue $created 'name')
        if ($createdName -ine $name) {
            throw "GitHub returned repository '$createdName' while creating '$name'."
        }

        $verification = Test-GitHubRepositoryExists -Owner $owner -Name $name
        if (-not $verification.Exists) {
            throw "Repository '$owner/$name' was not visible after creation."
        }

        $Report.operations.created++
        $Report.actualCount++
        $Report.missing = @($Report.missing | Where-Object { $_ -ine $name })
    }
}

if ($Apply -and -not ($CreateRepositories -or $ConfigureRepositories -or $GenerateMetadata)) {
    throw '-Apply requires at least one reconciliation operation switch.'
}
if (-not $Apply -and ($CreateRepositories -or $ConfigureRepositories -or $GenerateMetadata -or $CommitChanges -or $PushChanges)) {
    throw 'Reconciliation operation switches require -Apply.'
}
if ($PushChanges -and -not $CommitChanges) { throw '-PushChanges requires -CommitChanges.' }
if ($CommitChanges -or $PushChanges) { Assert-Command git }

$manifest = Get-XmipManifest $ManifestPath
Test-XmipManifest $manifest
$actual = @(Get-ActualRepositories -Manifest $manifest)
$report = New-TransactionReport $manifest $actual

Write-Step "Drift: $($report.missing.Count) missing, $($report.unexpected.Count) unexpected"
foreach ($name in $report.missing) { Write-Warning "MISSING: $name" }
foreach ($name in $report.unexpected) { Write-Warning "UNEXPECTED: $name" }

if ($Apply) {
    if ($CreateRepositories) {
        Invoke-CreateRepositories -Manifest $manifest -Report $report
    }
    if ($ConfigureRepositories -or $GenerateMetadata) {
        throw 'Configure and metadata operations remain blocked in this stabilization build.'
    }
}
else {
    Write-Step 'Reporting only; no reconciliation operation selected.'
}

if ($WriteReport) {
    $directory = Split-Path -Parent $ReportPath
    if ($directory) { New-Item -ItemType Directory -Force -Path $directory | Out-Null }
    $report | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $ReportPath -Encoding utf8NoBOM
    Write-Host "Report written: $ReportPath"
}

Write-Step "Architecture reconciliation completed in $(if ($Apply) { 'Apply' } else { 'Plan' }) mode"
if ($PassThru) { [pscustomobject]$report }
