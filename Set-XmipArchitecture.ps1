#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string] $ManifestPath = (Join-Path $PSScriptRoot 'xmip-architecture.json'),
    [string] $WorkingDirectory = (Join-Path $PSScriptRoot '.xmip-work'),
    [string] $GitHubToken = $env:GITHUB_TOKEN,
    [string] $GitHubApiBaseUri = 'https://api.github.com',
    [switch] $Apply,
    [switch] $CreateRepositories,
    [switch] $ConfigureRepositories,
    [switch] $SynchronizeSubmodules,
    [switch] $GenerateMetadata,
    [switch] $CommitChanges,
    [switch] $PushChanges,
    [switch] $IncludeReserved,
    [switch] $WriteReport,
    [string] $ReportPath = (Join-Path $WorkingDirectory 'xmip-architecture-report.json'),
    [switch] $PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ScriptVersion = [version]'1.1.1'

function Write-Step([string] $Message) {
    Write-Host "==> $Message" -ForegroundColor Cyan
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
        [string] $At = ''
    )

    $previous = $PWD
    try {
        if ($At) { Set-Location $At }
        & $FilePath @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed: $FilePath $($Arguments -join ' ')"
        }
    }
    finally {
        Set-Location $previous
    }
}

function Get-PropertyValue {
    param(
        [Parameter(Mandatory)] $Object,
        [Parameter(Mandatory)] [string] $Name,
        $Default = $null
    )

    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return $Default }
    return $property.Value
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
        $parameters.Body = ($Body | ConvertTo-Json -Depth 50)
    }

    return Invoke-RestMethod @parameters
}

function Get-GitHubPagedCollection {
    param([Parameter(Mandatory)] [string] $Path)

    $results = [Collections.Generic.List[object]]::new()
    $page = 1
    do {
        $separator = if ($Path.Contains('?')) { '&' } else { '?' }
        $batch = @(Invoke-GitHubApi GET "$Path${separator}per_page=100&page=$page")
        foreach ($item in $batch) { $results.Add($item) }
        $page++
    } while ($batch.Count -eq 100)

    return @($results)
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
    $existingRepositories = Get-PropertyValue $Source 'repositories'
    if ($existingRepositories) { return $Source }

    $defaults = Get-PropertyValue $Source 'defaults' ([pscustomobject]@{})
    $repositories = [Collections.Generic.List[object]]::new()

    foreach ($raw in @(Get-PropertyValue $Source 'commonRepositories' @())) {
        $item = Convert-CommonRepository $raw $defaults
        $domain = $item.architecturalDomain
        $repositories.Add([pscustomobject]@{
            name = $item.name
            description = $item.description
            architecturalDomain = $domain
            repositoryRole = $item.repositoryRole
            maturity = $item.maturity
            dependencies = @($item.dependencies)
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
        $capability = $group.parent -replace '^xmip-', ''
        foreach ($rawTechnology in @($group.technologies)) {
            $technology = if ($rawTechnology -is [string]) {
                [pscustomobject]@{ name = $rawTechnology }
            }
            else {
                $rawTechnology
            }

            $technologyName = [string](Get-PropertyValue $technology 'name')
            $repositories.Add([pscustomobject]@{
                name = "$($group.parent)-$technologyName"
                description = [string](Get-PropertyValue $technology 'description' "$technologyName implementation of $($group.parent).")
                architecturalDomain = 'Technology'
                repositoryRole = 'technology-implementation'
                maturity = [string](Get-PropertyValue $technology 'maturity' (Get-PropertyValue $defaults 'maturity' 'reserved'))
                capability = $capability
                technology = $technologyName
                parent = $group.parent
                dependencies = @($group.dependencies)
                github = [pscustomobject]@{
                    visibility = [string](Get-PropertyValue $defaults 'visibility' 'public')
                    autoInitialize = [bool](Get-PropertyValue $defaults 'autoInitialize' $true)
                    hasIssues = [bool](Get-PropertyValue $defaults 'hasIssues' $true)
                    hasProjects = [bool](Get-PropertyValue $defaults 'hasProjects' $false)
                    hasWiki = [bool](Get-PropertyValue $defaults 'hasWiki' $false)
                    topics = @('xmip', 'technology', $capability, $technologyName)
                }
                submodule = [pscustomobject]@{
                    enabled = $true
                    parentRepository = $group.parent
                    path = "modules/$technologyName"
                    revision = Get-PropertyValue $technology 'revision'
                }
            })
        }
    }

    $Source | Add-Member -NotePropertyName repositories -NotePropertyValue @($repositories) -Force
    return $Source
}

function Get-XmipManifest([string] $Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Manifest not found: $Path"
    }

    $source = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 100
    $minimumScriptVersion = Get-PropertyValue $source 'minimumScriptVersion'
    if ($minimumScriptVersion -and $ScriptVersion -lt [version]$minimumScriptVersion) {
        throw "Manifest requires script version $minimumScriptVersion; current version is $ScriptVersion."
    }

    return Expand-XmipManifest $source
}

function Test-XmipManifest($Manifest) {
    Write-Step 'Validating architecture manifest'

    $owner = Get-PropertyValue $Manifest 'owner'
    $repositories = @(Get-PropertyValue $Manifest 'repositories' @())
    if (-not $owner) { throw 'Manifest owner is missing.' }
    if ($repositories.Count -eq 0) { throw 'Manifest contains no repositories.' }

    $names = @($repositories | ForEach-Object { Get-PropertyValue $_ 'name' })
    $duplicates = $names | Group-Object | Where-Object Count -gt 1
    if ($duplicates) { throw "Duplicate repositories: $($duplicates.Name -join ', ')" }

    $nameSet = [Collections.Generic.HashSet[string]]::new([string[]]$names, [StringComparer]::OrdinalIgnoreCase)
    foreach ($repository in $repositories) {
        $name = [string](Get-PropertyValue $repository 'name')
        $description = [string](Get-PropertyValue $repository 'description')
        $maturity = [string](Get-PropertyValue $repository 'maturity' 'reserved')
        $submodule = Get-PropertyValue $repository 'submodule' ([pscustomobject]@{ enabled = $false })
        $parent = [string](Get-PropertyValue $repository 'parent')

        if ($name -notmatch '^xmip-[a-z0-9]+(?:-[a-z0-9]+)*$') { throw "Invalid repository name: $name" }
        if (-not $description) { throw "Description missing: $name" }
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

    $state = @{}
    $stack = [Collections.Generic.List[string]]::new()
    $map = @{}
    foreach ($repository in $repositories) {
        $map[[string](Get-PropertyValue $repository 'name')] = @(Get-PropertyValue $repository 'dependencies' @())
    }

    function Visit([string] $Name) {
        if ($state[$Name] -eq 1) {
            $index = $stack.IndexOf($Name)
            $cycle = @($stack[$index..($stack.Count - 1)]) + $Name
            throw "Dependency cycle: $($cycle -join ' -> ')"
        }
        if ($state[$Name] -eq 2) { return }
        $state[$Name] = 1
        $stack.Add($Name)
        foreach ($dependency in $map[$Name]) { Visit $dependency }
        $stack.RemoveAt($stack.Count - 1)
        $state[$Name] = 2
    }

    foreach ($name in $map.Keys) { Visit $name }
}

function Get-GitHubOwner([string] $Owner) {
    return Invoke-GitHubApi GET "/users/$Owner"
}

function Get-ActualRepositories([string] $Owner) {
    $ownerInfo = Get-GitHubOwner $Owner
    if ((Get-PropertyValue $ownerInfo 'type') -eq 'Organization') {
        return Get-GitHubPagedCollection "/orgs/$Owner/repos?type=all"
    }

    if ($GitHubToken) {
        $currentUser = Invoke-GitHubApi GET '/user'
        if ((Get-PropertyValue $currentUser 'login') -ieq $Owner) {
            return @(Get-GitHubPagedCollection '/user/repos?affiliation=owner' | Where-Object {
                (Get-PropertyValue (Get-PropertyValue $_ 'owner') 'login') -ieq $Owner
            })
        }
    }

    return Get-GitHubPagedCollection "/users/$Owner/repos?type=owner"
}

function Test-RepositoryExists([string] $Owner, [string] $Name) {
    try {
        $null = Invoke-GitHubApi GET "/repos/$Owner/$Name"
        return $true
    }
    catch {
        $statusCode = Get-PropertyValue (Get-PropertyValue $_.Exception 'Response') 'StatusCode'
        $numericStatusCode = Get-PropertyValue $statusCode 'value__' $statusCode
        if ($numericStatusCode -eq 404) { return $false }
        throw
    }
}

function New-TransactionReport($Manifest, $Actual) {
    $desired = @{}
    foreach ($repository in $Manifest.repositories) { $desired[$repository.name] = $repository }
    $actualMap = @{}
    foreach ($repository in $Actual) { $actualMap[$repository.name] = $repository }

    return [ordered]@{
        generatedAtUtc = [DateTime]::UtcNow.ToString('o')
        scriptVersion = $ScriptVersion.ToString()
        schemaVersion = [string](Get-PropertyValue $Manifest 'schemaVersion' 'unversioned')
        architectureVersion = [string](Get-PropertyValue $Manifest 'architectureVersion' 'unversioned')
        owner = $Manifest.owner
        desiredCount = $desired.Count
        actualCount = $actualMap.Count
        missing = @($desired.Keys | Where-Object { -not $actualMap.ContainsKey($_) } | Sort-Object)
        unexpected = @($actualMap.Keys | Where-Object { $_ -like 'xmip-*' -and -not $desired.ContainsKey($_) } | Sort-Object)
        deprecated = @($Manifest.repositories | Where-Object maturity -eq 'deprecated' | Select-Object name, description | Sort-Object name)
        retired = @($Manifest.repositories | Where-Object maturity -eq 'retired' | Select-Object name, description | Sort-Object name)
        operations = [ordered]@{ created = 0; configured = 0; submodulesAdded = 0; metadataWritten = 0; commits = 0; pushes = 0; skipped = 0 }
    }
}

function New-Repository($Manifest, $Repository, $Report) {
    $fullName = "$($Manifest.owner)/$($Repository.name)"
    if (Test-RepositoryExists $Manifest.owner $Repository.name) { $Report.operations.skipped++; return }
    if (-not $Apply) { Write-Host "PLAN create repository: $fullName"; return }
    if (-not $GitHubToken) { throw 'GITHUB_TOKEN or -GitHubToken is required for repository creation.' }
    if (-not $PSCmdlet.ShouldProcess($fullName, 'Create repository')) { return }

    $ownerInfo = Get-GitHubOwner $Manifest.owner
    $body = [ordered]@{
        name = $Repository.name
        description = [string]$Repository.description
        private = ([string]$Repository.github.visibility -eq 'private')
        auto_init = [bool]$Repository.github.autoInitialize
        has_issues = [bool]$Repository.github.hasIssues
        has_projects = [bool]$Repository.github.hasProjects
        has_wiki = [bool]$Repository.github.hasWiki
    }

    if ((Get-PropertyValue $ownerInfo 'type') -eq 'Organization') {
        $null = Invoke-GitHubApi POST "/orgs/$($Manifest.owner)/repos" $body
    }
    else {
        $currentUser = Invoke-GitHubApi GET '/user'
        if ((Get-PropertyValue $currentUser 'login') -ine $Manifest.owner) {
            throw "Authenticated GitHub user '$((Get-PropertyValue $currentUser 'login'))' cannot create repositories for '$($Manifest.owner)'."
        }
        $null = Invoke-GitHubApi POST '/user/repos' $body
    }

    $topics = @(Get-PropertyValue $Repository.github 'topics' @())
    if ($topics.Count -gt 0) { $null = Invoke-GitHubApi PUT "/repos/$fullName/topics" @{ names = $topics } }
    $Report.operations.created++
}

function Set-Repository($Manifest, $Repository, $Report) {
    $fullName = "$($Manifest.owner)/$($Repository.name)"
    if (-not (Test-RepositoryExists $Manifest.owner $Repository.name)) { Write-Warning "Cannot configure missing repository: $fullName"; return }
    if (-not $Apply) { Write-Host "PLAN configure repository: $fullName"; return }
    if (-not $GitHubToken) { throw 'GITHUB_TOKEN or -GitHubToken is required for repository configuration.' }
    if (-not $PSCmdlet.ShouldProcess($fullName, 'Configure repository')) { return }

    $body = [ordered]@{
        description = [string]$Repository.description
        visibility = [string]$Repository.github.visibility
        has_issues = [bool]$Repository.github.hasIssues
        has_projects = [bool]$Repository.github.hasProjects
        has_wiki = [bool]$Repository.github.hasWiki
    }
    $null = Invoke-GitHubApi PATCH "/repos/$fullName" $body
    $null = Invoke-GitHubApi PUT "/repos/$fullName/topics" @{ names = @(Get-PropertyValue $Repository.github 'topics' @()) }
    $Report.operations.configured++
}

function Sync-Parent($Manifest, $Parent, $Report) {
    $children = @($Manifest.repositories | Where-Object {
        $_.submodule.enabled -and $_.parent -eq $Parent.name -and $_.maturity -notin @('deprecated','retired')
    })

    foreach ($child in $children) { Write-Host "PLAN ensure submodule $($Parent.name)/$($child.submodule.path) -> $($child.name)" }
    if (-not $Apply) { return }

    $path = Join-Path $WorkingDirectory $Parent.name
    if (Test-Path (Join-Path $path '.git')) {
        Invoke-Native git @('fetch','--all','--prune') $path
        Invoke-Native git @('checkout',$Manifest.defaults.defaultBranch) $path
        Invoke-Native git @('pull','--ff-only') $path
    }
    else {
        New-Item -ItemType Directory -Force -Path $WorkingDirectory | Out-Null
        Invoke-Native git @('clone',"https://github.com/$($Manifest.owner)/$($Parent.name).git",$path)
    }

    $configured = @()
    if (Test-Path (Join-Path $path '.gitmodules')) {
        $configured = @((& git -C $path config --file .gitmodules --get-regexp path 2>$null) | ForEach-Object { ($_ -split '\s+',2)[1] })
    }

    foreach ($child in $children) {
        if ($child.submodule.path -notin $configured -and $PSCmdlet.ShouldProcess("$($Parent.name)/$($child.submodule.path)", "Add submodule $($child.name)")) {
            Invoke-Native git @('submodule','add',"https://github.com/$($Manifest.owner)/$($child.name).git",$child.submodule.path) $path
            $Report.operations.submodulesAdded++
        }
        $revision = Get-PropertyValue $child.submodule 'revision'
        if ($revision) {
            Invoke-Native git @('submodule','update','--init','--',$child.submodule.path) $path
            Invoke-Native git @('checkout',[string]$revision) (Join-Path $path $child.submodule.path)
            Invoke-Native git @('add','--',$child.submodule.path) $path
        }
    }

    if ($GenerateMetadata) {
        [ordered]@{
            name = $Parent.name
            domain = $Parent.architecturalDomain
            role = $Parent.repositoryRole
            maturity = $Parent.maturity
            dependencies = @($Parent.dependencies)
            technologySubmodules = @($children | ForEach-Object {
                [ordered]@{ name = $_.name; path = $_.submodule.path; revision = Get-PropertyValue $_.submodule 'revision' }
            })
        } | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $path 'xmip.repository.json') -Encoding utf8NoBOM
        $Report.operations.metadataWritten++
    }

    if ($CommitChanges) {
        Invoke-Native git @('add','--all') $path
        & git -C $path diff --cached --quiet
        if ($LASTEXITCODE -ne 0 -and $PSCmdlet.ShouldProcess($Parent.name, 'Commit architecture reconciliation')) {
            Invoke-Native git @('commit','-m','Reconcile Xmip architecture') $path
            $Report.operations.commits++
            if ($PushChanges) {
                Invoke-Native git @('push','origin',$Manifest.defaults.defaultBranch) $path
                $Report.operations.pushes++
            }
        }
    }
}

if ($Apply -and -not ($CreateRepositories -or $ConfigureRepositories -or $SynchronizeSubmodules -or $GenerateMetadata)) {
    throw '-Apply requires at least one reconciliation operation switch.'
}
if (($CreateRepositories -or $ConfigureRepositories) -and $Apply -and -not $GitHubToken) {
    throw 'GITHUB_TOKEN or -GitHubToken is required for GitHub write operations.'
}
if ($SynchronizeSubmodules -or $GenerateMetadata -or $CommitChanges -or $PushChanges) {
    Assert-Command git
}

$manifest = Get-XmipManifest $ManifestPath
Test-XmipManifest $manifest
$actual = @(Get-ActualRepositories $manifest.owner)
$report = New-TransactionReport $manifest $actual

Write-Step "Drift: $($report.missing.Count) missing, $($report.unexpected.Count) unexpected, $($report.deprecated.Count) deprecated, $($report.retired.Count) retired"
foreach ($name in $report.missing) { Write-Warning "MISSING: $name" }
foreach ($name in $report.unexpected) { Write-Warning "UNEXPECTED: $name" }

$selected = @($manifest.repositories | Where-Object {
    ($IncludeReserved -or $_.maturity -ne 'reserved') -and $_.maturity -notin @('deprecated','retired')
})

if ($CreateRepositories) { foreach ($repository in $selected) { New-Repository $manifest $repository $report } }
if ($ConfigureRepositories) { foreach ($repository in $selected) { Set-Repository $manifest $repository $report } }
if ($SynchronizeSubmodules -or $GenerateMetadata) {
    foreach ($parent in $selected | Where-Object { -not $_.submodule.enabled }) {
        if ($manifest.repositories | Where-Object { $_.submodule.enabled -and $_.parent -eq $parent.name }) {
            Sync-Parent $manifest $parent $report
        }
    }
}
if (-not ($CreateRepositories -or $ConfigureRepositories -or $SynchronizeSubmodules -or $GenerateMetadata)) {
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
