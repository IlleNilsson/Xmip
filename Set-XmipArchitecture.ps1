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
$ScriptVersion = [version]'1.1.4'

function Write-Step([string] $Message) { Write-Host "==> $Message" -ForegroundColor Cyan }

function Get-PropertyValue {
    param([AllowNull()] $Object, [Parameter(Mandatory)] [string] $Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return $Default }
    return $property.Value
}

function ConvertTo-Array($Value) {
    if ($null -eq $Value) { return ,@() }
    return ,@($Value)
}

function Assert-Command([string] $Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) { throw "Required command '$Name' was not found." }
}

function Invoke-Native {
    param([Parameter(Mandatory)] [string] $FilePath, [string[]] $Arguments = @(), [string] $At = '')
    $previous = $PWD
    try {
        if ($At) { Set-Location $At }
        & $FilePath @Arguments
        if ($LASTEXITCODE -ne 0) { throw "Command failed: $FilePath $($Arguments -join ' ')" }
    }
    finally { Set-Location $previous }
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
    $uri = if ($Path -match '^https?://') { $Path } else { "$($GitHubApiBaseUri.TrimEnd('/'))/$($Path.TrimStart('/'))" }
    $parameters = @{ Method=$Method; Uri=$uri; Headers=(Get-GitHubHeaders); ErrorAction='Stop' }
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
        $response = Invoke-GitHubApi GET "$Path${separator}per_page=100&page=$page"
        $batch = @(ConvertTo-Array $response)
        foreach ($item in $batch) {
            if ($null -ne $item) { $results.Add($item) }
        }
        $page++
    } while ($batch.Count -eq 100)
    return ,@($results.ToArray())
}

function Convert-CommonRepository($Item, $Defaults) {
    if ($Item -is [System.Array]) {
        return [pscustomobject]@{
            name=[string]$Item[0]; description=[string]$Item[1]; architecturalDomain=[string]$Item[2]
            repositoryRole=[string]$Item[3]; maturity=[string](Get-PropertyValue $Defaults 'maturity' 'reserved')
            dependencies=@($Item[4])
        }
    }
    return [pscustomobject]@{
        name=[string](Get-PropertyValue $Item 'name'); description=[string](Get-PropertyValue $Item 'description')
        architecturalDomain=[string](Get-PropertyValue $Item 'architecturalDomain'); repositoryRole=[string](Get-PropertyValue $Item 'repositoryRole')
        maturity=[string](Get-PropertyValue $Item 'maturity' (Get-PropertyValue $Defaults 'maturity' 'reserved'))
        dependencies=@(Get-PropertyValue $Item 'dependencies' @())
    }
}

function Convert-TechnologyGroup($Group) {
    if ($Group -is [System.Array]) {
        return [pscustomobject]@{ parent=[string]$Group[0]; dependencies=@($Group[1]); technologies=@($Group[2]) }
    }
    return [pscustomobject]@{
        parent=[string](Get-PropertyValue $Group 'parent'); dependencies=@(Get-PropertyValue $Group 'dependencies' @())
        technologies=@(Get-PropertyValue $Group 'technologies' @())
    }
}

function Expand-XmipManifest($Source) {
    $existing = @(Get-PropertyValue $Source 'repositories' @())
    if ($existing.Count -gt 0) { return $Source }
    $defaults = Get-PropertyValue $Source 'defaults' ([pscustomobject]@{})
    $repositories = [Collections.Generic.List[object]]::new()

    foreach ($raw in @(Get-PropertyValue $Source 'commonRepositories' @())) {
        $item = Convert-CommonRepository $raw $defaults
        $domain = [string]$item.architecturalDomain
        $repositories.Add([pscustomobject]@{
            name=$item.name; description=$item.description; architecturalDomain=$domain; repositoryRole=$item.repositoryRole
            maturity=$item.maturity; dependencies=@($item.dependencies)
            github=[pscustomobject]@{
                visibility=[string](Get-PropertyValue $defaults 'visibility' 'public')
                autoInitialize=[bool](Get-PropertyValue $defaults 'autoInitialize' $true)
                hasIssues=[bool](Get-PropertyValue $defaults 'hasIssues' $true)
                hasProjects=[bool](Get-PropertyValue $defaults 'hasProjects' $false)
                hasWiki=[bool](Get-PropertyValue $defaults 'hasWiki' $false)
                topics=@('xmip', $domain.ToLowerInvariant())
            }
            submodule=[pscustomobject]@{ enabled=$false }
        })
    }

    foreach ($rawGroup in @(Get-PropertyValue $Source 'technologyGroups' @())) {
        $group = Convert-TechnologyGroup $rawGroup
        $capability = $group.parent -replace '^xmip-',''
        foreach ($rawTechnology in @($group.technologies)) {
            $technology = if ($rawTechnology -is [string]) { [pscustomobject]@{ name=$rawTechnology } } else { $rawTechnology }
            $technologyName = [string](Get-PropertyValue $technology 'name')
            $repositories.Add([pscustomobject]@{
                name="$($group.parent)-$technologyName"
                description=[string](Get-PropertyValue $technology 'description' "$technologyName implementation of $($group.parent).")
                architecturalDomain='Technology'; repositoryRole='technology-implementation'
                maturity=[string](Get-PropertyValue $technology 'maturity' (Get-PropertyValue $defaults 'maturity' 'reserved'))
                capability=$capability; technology=$technologyName; parent=$group.parent; dependencies=@($group.dependencies)
                github=[pscustomobject]@{
                    visibility=[string](Get-PropertyValue $defaults 'visibility' 'public')
                    autoInitialize=[bool](Get-PropertyValue $defaults 'autoInitialize' $true)
                    hasIssues=[bool](Get-PropertyValue $defaults 'hasIssues' $true)
                    hasProjects=[bool](Get-PropertyValue $defaults 'hasProjects' $false)
                    hasWiki=[bool](Get-PropertyValue $defaults 'hasWiki' $false)
                    topics=@('xmip','technology',$capability,$technologyName)
                }
                submodule=[pscustomobject]@{ enabled=$true; parentRepository=$group.parent; path="modules/$technologyName"; revision=(Get-PropertyValue $technology 'revision') }
            })
        }
    }

    $Source | Add-Member -NotePropertyName repositories -NotePropertyValue @($repositories.ToArray()) -Force
    return $Source
}

function Get-XmipManifest([string] $Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Manifest not found: $Path" }
    $source = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 100
    $minimumScriptVersion = Get-PropertyValue $source 'minimumScriptVersion'
    if ($minimumScriptVersion -and $ScriptVersion -lt [version]$minimumScriptVersion) {
        throw "Manifest requires script version $minimumScriptVersion; current version is $ScriptVersion."
    }
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
    if ($duplicates.Count -gt 0) { throw "Duplicate repositories: $($duplicates.Name -join ', ')" }

    $nameSet = [Collections.Generic.HashSet[string]]::new([string[]]$names,[StringComparer]::OrdinalIgnoreCase)
    foreach ($repository in $repositories) {
        $name = [string](Get-PropertyValue $repository 'name')
        $description = [string](Get-PropertyValue $repository 'description')
        $maturity = [string](Get-PropertyValue $repository 'maturity' 'reserved')
        $submodule = Get-PropertyValue $repository 'submodule' ([pscustomobject]@{ enabled=$false })
        $parent = [string](Get-PropertyValue $repository 'parent')
        if ($name -notmatch '^xmip-[a-z0-9]+(?:-[a-z0-9]+)*$') { throw "Invalid repository name: $name" }
        if (-not $description) { throw "Description missing: $name" }
        if ($maturity -notin @('planned','reserved','created','configured','submodule','workspace','scaffolded','implemented','verified','supported','deprecated','retired')) { throw "Invalid maturity '$maturity' for '$name'" }
        if ([bool](Get-PropertyValue $submodule 'enabled' $false) -and -not $nameSet.Contains($parent)) { throw "Unknown parent '$parent' for '$name'" }
        foreach ($dependency in @(Get-PropertyValue $repository 'dependencies' @())) {
            if (-not $nameSet.Contains([string]$dependency)) { throw "Unknown dependency '$dependency' for '$name'" }
            if ($dependency -eq $name) { throw "Self dependency: $name" }
        }
    }
}

function Get-ActualRepositories([string] $Owner) {
    $ownerInfo = Invoke-GitHubApi GET "/users/$Owner"
    if ((Get-PropertyValue $ownerInfo 'type') -eq 'Organization') {
        return ,@(Get-GitHubPagedCollection "/orgs/$Owner/repos?type=all")
    }

    if ($GitHubToken) {
        $currentUser = Invoke-GitHubApi GET '/user'
        if ((Get-PropertyValue $currentUser 'login') -ieq $Owner) {
            $filtered = [Collections.Generic.List[object]]::new()
            foreach ($repository in @(Get-GitHubPagedCollection '/user/repos?affiliation=owner')) {
                if ($null -eq $repository) { continue }
                $repoOwner = Get-PropertyValue $repository 'owner'
                if ((Get-PropertyValue $repoOwner 'login') -ieq $Owner) {
                    $filtered.Add($repository)
                }
            }
            return ,@($filtered.ToArray())
        }
    }

    return ,@(Get-GitHubPagedCollection "/users/$Owner/repos?type=owner")
}

function New-TransactionReport($Manifest, $Actual) {
    $desired=@{}; foreach($repository in @(Get-PropertyValue $Manifest 'repositories' @())){$desired[[string](Get-PropertyValue $repository 'name')]=$repository}
    $actualMap=@{}; foreach($repository in @(ConvertTo-Array $Actual)){if($null -ne $repository){$actualMap[[string](Get-PropertyValue $repository 'name')]=$repository}}
    return [ordered]@{
        generatedAtUtc=[DateTime]::UtcNow.ToString('o'); scriptVersion=$ScriptVersion.ToString()
        schemaVersion=[string](Get-PropertyValue $Manifest 'schemaVersion' 'unversioned')
        architectureVersion=[string](Get-PropertyValue $Manifest 'architectureVersion' 'unversioned')
        owner=[string](Get-PropertyValue $Manifest 'owner'); desiredCount=$desired.Count; actualCount=$actualMap.Count
        missing=@($desired.Keys|Where-Object{-not $actualMap.ContainsKey($_)}|Sort-Object)
        unexpected=@($actualMap.Keys|Where-Object{$_ -like 'xmip-*' -and -not $desired.ContainsKey($_)}|Sort-Object)
        deprecated=@(); retired=@(); operations=[ordered]@{created=0;configured=0;submodulesAdded=0;metadataWritten=0;commits=0;pushes=0;skipped=0}
    }
}

if ($Apply -and -not ($CreateRepositories -or $ConfigureRepositories -or $SynchronizeSubmodules -or $GenerateMetadata)) { throw '-Apply requires at least one reconciliation operation switch.' }
if ($SynchronizeSubmodules -or $GenerateMetadata -or $CommitChanges -or $PushChanges) { Assert-Command git }

$manifest = Get-XmipManifest $ManifestPath
Test-XmipManifest $manifest
$actual = @(Get-ActualRepositories ([string](Get-PropertyValue $manifest 'owner')))
$report = New-TransactionReport $manifest $actual
Write-Step "Drift: $($report.missing.Count) missing, $($report.unexpected.Count) unexpected"
foreach ($name in $report.missing) { Write-Warning "MISSING: $name" }
foreach ($name in $report.unexpected) { Write-Warning "UNEXPECTED: $name" }

if ($CreateRepositories -or $ConfigureRepositories -or $SynchronizeSubmodules -or $GenerateMetadata) {
    throw 'Apply operations are temporarily blocked in this stabilization build. Run Plan mode only.'
}
else { Write-Step 'Reporting only; no reconciliation operation selected.' }

if ($WriteReport) {
    $directory = Split-Path -Parent $ReportPath
    if ($directory) { New-Item -ItemType Directory -Force -Path $directory | Out-Null }
    $report | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $ReportPath -Encoding utf8NoBOM
    Write-Host "Report written: $ReportPath"
}

Write-Step "Architecture reconciliation completed in $(if($Apply){'Apply'}else{'Plan'}) mode"
if ($PassThru) { [pscustomobject]$report }
