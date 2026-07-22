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
$ScriptVersion = [version]'1.3.0'

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
                    topics = @('xmip','technology',$capability,$technologyName)
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

    $Source | Add-Member -NotePropertyName repositories -NotePropertyValue @($repositories.ToArray()) -Force
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
            submodulesAdded = 0
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
        [Parameter(Mandatory)] [ValidateSet('User','Organization')] [string] $OwnerType
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

    $body = [ordered]@{
        name = $name
        description = $description
        private = ($visibility -eq 'private')
        auto_init = [bool](Get-PropertyValue $github 'autoInitialize' $true)
        has_issues = [bool](Get-PropertyValue $github 'hasIssues' $true)
        has_projects = [bool](Get-PropertyValue $github 'hasProjects' $false)
        has_wiki = [bool](Get-PropertyValue $github 'hasWiki' $false)
    }
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
        $created = New-XmipGitHubRepository -Repository $repository -Owner $owner -OwnerType $ownerType
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

function Get-RepositoryCloneUrl {
    param([Parameter(Mandatory)] [string] $Owner, [Parameter(Mandatory)] [string] $Name)
    return "https://github.com/$Owner/$Name.git"
}

function Ensure-ParentRepositoryCheckout {
    param(
        [Parameter(Mandatory)] [string] $Owner,
        [Parameter(Mandatory)] [string] $ParentName
    )

    $path = Join-Path $WorkingDirectory $ParentName
    if (Test-Path -LiteralPath (Join-Path $path '.git')) {
        Invoke-Native git @('fetch','--all','--prune') $path
        Invoke-Native git @('checkout','main') $path
        Invoke-Native git @('pull','--ff-only') $path
    }
    elseif (Test-Path -LiteralPath $path) {
        throw "Working path exists but is not a Git repository: $path"
    }
    else {
        New-Item -ItemType Directory -Force -Path $WorkingDirectory | Out-Null
        Invoke-Native git @('clone',(Get-RepositoryCloneUrl $Owner $ParentName),$path)
    }
    return $path
}

function Invoke-SynchronizeSubmodules {
    param(
        [Parameter(Mandatory)] $Manifest,
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Report
    )

    $owner = [string](Get-PropertyValue $Manifest 'owner')
    $repositories = @(Get-PropertyValue $Manifest 'repositories' @())
    $groups = @{}

    foreach ($repository in $repositories) {
        $submodule = Get-PropertyValue $repository 'submodule' ([pscustomobject]@{ enabled = $false })
        if (-not [bool](Get-PropertyValue $submodule 'enabled' $false)) { continue }

        $name = [string](Get-PropertyValue $repository 'name')
        $parent = [string](Get-PropertyValue $submodule 'parentRepository' (Get-PropertyValue $repository 'parent'))
        $path = [string](Get-PropertyValue $submodule 'path')
        if (-not $parent) { throw "Submodule parent is missing for '$name'." }
        if (-not $path) { throw "Submodule path is missing for '$name'." }

        $parentExists = Test-GitHubRepositoryExists -Owner $owner -Name $parent
        if (-not $parentExists.Exists) { throw "Parent repository '$owner/$parent' does not exist." }
        $childExists = Test-GitHubRepositoryExists -Owner $owner -Name $name
        if (-not $childExists.Exists) { throw "Child repository '$owner/$name' does not exist." }

        if (-not $groups.ContainsKey($parent)) {
            $groups[$parent] = [Collections.Generic.List[object]]::new()
        }
        $groups[$parent].Add([pscustomobject]@{ Name = $name; Path = $path })
    }

    foreach ($parent in @($groups.Keys | Sort-Object)) {
        $checkout = Ensure-ParentRepositoryCheckout -Owner $owner -ParentName $parent
        $changed = $false

        foreach ($entry in @($groups[$parent].ToArray() | Sort-Object Path)) {
            $relativePath = [string]$entry.Path
            $name = [string]$entry.Name
            $expectedUrl = Get-RepositoryCloneUrl -Owner $owner -Name $name
            $occupiedPath = Join-Path $checkout $relativePath
            $moduleName = $relativePath -replace '\\','/'
            $registeredUrl = ''

            $configOutput = & git -C $checkout config --file .gitmodules --get "submodule.$moduleName.url" 2>$null
            if ($LASTEXITCODE -eq 0) { $registeredUrl = [string]($configOutput | Select-Object -First 1) }

            if ($registeredUrl) {
                if ($registeredUrl -ne $expectedUrl) {
                    if (-not $PSCmdlet.ShouldProcess("$parent:$relativePath", "Correct submodule URL to $expectedUrl")) {
                        $Report.operations.skipped++
                        continue
                    }
                    Invoke-Native git @('config','--file','.gitmodules',"submodule.$moduleName.url",$expectedUrl) $checkout
                    Invoke-Native git @('submodule','sync','--',$relativePath) $checkout
                    $changed = $true
                }
                Invoke-Native git @('submodule','update','--init','--recursive','--',$relativePath) $checkout
                continue
            }

            if (Test-Path -LiteralPath $occupiedPath) {
                $items = @(Get-ChildItem -LiteralPath $occupiedPath -Force -ErrorAction SilentlyContinue)
                if ($items.Count -gt 0) {
                    throw "Submodule path '$parent/$relativePath' is occupied by ordinary files."
                }
            }

            if (-not $PSCmdlet.ShouldProcess("$parent:$relativePath", "Add submodule $owner/$name")) {
                $Report.operations.skipped++
                continue
            }

            Invoke-Native git @('submodule','add',$expectedUrl,$relativePath) $checkout
            $Report.operations.submodulesAdded++
            $changed = $true
        }

        if ($changed) {
            Invoke-Native git @('add','.gitmodules','modules') $checkout
            if ($CommitChanges) {
                $status = @(Invoke-Native git @('status','--porcelain') $checkout -CaptureOutput)
                if ($status.Count -gt 0) {
                    Invoke-Native git @('commit','-m','Synchronize Xmip technology submodules') $checkout
                    $Report.operations.commits++
                }
            }
            if ($PushChanges) {
                if (-not $CommitChanges) { throw '-PushChanges requires -CommitChanges.' }
                Invoke-Native git @('push','origin','main') $checkout
                $Report.operations.pushes++
            }
        }
    }
}

if ($Apply -and -not ($CreateRepositories -or $ConfigureRepositories -or $SynchronizeSubmodules -or $GenerateMetadata)) {
    throw '-Apply requires at least one reconciliation operation switch.'
}
if (-not $Apply -and ($CreateRepositories -or $ConfigureRepositories -or $SynchronizeSubmodules -or $GenerateMetadata -or $CommitChanges -or $PushChanges)) {
    throw 'Reconciliation operation switches require -Apply.'
}
if ($PushChanges -and -not $CommitChanges) { throw '-PushChanges requires -CommitChanges.' }
if ($SynchronizeSubmodules -or $CommitChanges -or $PushChanges) { Assert-Command git }

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
    if ($SynchronizeSubmodules) {
        Invoke-SynchronizeSubmodules -Manifest $manifest -Report $report
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
