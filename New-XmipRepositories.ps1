#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string] $ManifestPath = (Join-Path $PSScriptRoot 'xmip-architecture.json'),
    [string] $GitHubToken = $env:GITHUB_TOKEN,
    [string] $GitHubApiBaseUri = 'https://api.github.com',
    [switch] $IncludeReserved
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PropertyValue {
    param([AllowNull()] $Object, [Parameter(Mandatory)] [string] $Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return $Default }
    return $property.Value
}

function Get-GitHubHeaders {
    $headers = @{
        Accept = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
        'User-Agent' = 'Xmip-Repository-Creator'
        Authorization = "Bearer $GitHubToken"
    }
    return $headers
}

function Invoke-GitHubRequest {
    param(
        [Parameter(Mandatory)] [ValidateSet('GET','POST')] [string] $Method,
        [Parameter(Mandatory)] [string] $Path,
        $Body
    )

    $uri = if ($Path -match '^https?://') { $Path } else { "$($GitHubApiBaseUri.TrimEnd('/'))/$($Path.TrimStart('/'))" }
    $parameters = @{
        Method = $Method
        Uri = $uri
        Headers = Get-GitHubHeaders
        ErrorAction = 'Stop'
        SkipHttpErrorCheck = $true
        StatusCodeVariable = 'statusCode'
    }
    if ($PSBoundParameters.ContainsKey('Body')) {
        $parameters.ContentType = 'application/json'
        $parameters.Body = $Body | ConvertTo-Json -Depth 50
    }

    $value = Invoke-RestMethod @parameters
    return [pscustomobject]@{ StatusCode = [int]$statusCode; Value = $value }
}

function Expand-XmipRepositories {
    param([Parameter(Mandatory)] $Source)

    $existing = @(Get-PropertyValue $Source 'repositories' @())
    if ($existing.Count -gt 0) { return ,$existing }

    $defaults = Get-PropertyValue $Source 'defaults' ([pscustomobject]@{})
    $repositories = [Collections.Generic.List[object]]::new()

    foreach ($item in @(Get-PropertyValue $Source 'commonRepositories' @())) {
        $repositories.Add([pscustomobject]@{
            name = [string]$item[0]
            description = [string]$item[1]
            maturity = [string](Get-PropertyValue $defaults 'maturity' 'reserved')
            github = [pscustomobject]@{
                visibility = [string](Get-PropertyValue $defaults 'visibility' 'public')
                autoInitialize = [bool](Get-PropertyValue $defaults 'autoInitialize' $true)
                hasIssues = [bool](Get-PropertyValue $defaults 'hasIssues' $true)
                hasProjects = [bool](Get-PropertyValue $defaults 'hasProjects' $false)
                hasWiki = [bool](Get-PropertyValue $defaults 'hasWiki' $false)
            }
        })
    }

    foreach ($group in @(Get-PropertyValue $Source 'technologyGroups' @())) {
        $parent = [string]$group[0]
        foreach ($technology in @($group[2])) {
            $technologyName = if ($technology -is [string]) { $technology } else { [string](Get-PropertyValue $technology 'name') }
            $description = if ($technology -is [string]) { "$technologyName implementation of $parent." } else { [string](Get-PropertyValue $technology 'description' "$technologyName implementation of $parent.") }
            $maturity = if ($technology -is [string]) { [string](Get-PropertyValue $defaults 'maturity' 'reserved') } else { [string](Get-PropertyValue $technology 'maturity' (Get-PropertyValue $defaults 'maturity' 'reserved')) }
            $repositories.Add([pscustomobject]@{
                name = "$parent-$technologyName"
                description = $description
                maturity = $maturity
                github = [pscustomobject]@{
                    visibility = [string](Get-PropertyValue $defaults 'visibility' 'public')
                    autoInitialize = [bool](Get-PropertyValue $defaults 'autoInitialize' $true)
                    hasIssues = [bool](Get-PropertyValue $defaults 'hasIssues' $true)
                    hasProjects = [bool](Get-PropertyValue $defaults 'hasProjects' $false)
                    hasWiki = [bool](Get-PropertyValue $defaults 'hasWiki' $false)
                }
            })
        }
    }

    return ,@($repositories.ToArray())
}

if (-not $GitHubToken) { throw 'GITHUB_TOKEN or -GitHubToken is required.' }
if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw "Manifest not found: $ManifestPath" }

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json -Depth 100
$owner = [string](Get-PropertyValue $manifest 'owner')
if (-not $owner) { throw 'Manifest owner is missing.' }

$ownerResponse = Invoke-GitHubRequest GET "/users/$owner"
if ($ownerResponse.StatusCode -ne 200) { throw "Unable to resolve owner '$owner': HTTP $($ownerResponse.StatusCode)." }
$ownerType = [string](Get-PropertyValue $ownerResponse.Value 'type')
if ($ownerType -notin @('User','Organization')) { throw "Unsupported owner type '$ownerType'." }

if ($ownerType -eq 'User') {
    $currentUser = Invoke-GitHubRequest GET '/user'
    if ($currentUser.StatusCode -ne 200) { throw "Unable to resolve authenticated user: HTTP $($currentUser.StatusCode)." }
    $currentLogin = [string](Get-PropertyValue $currentUser.Value 'login')
    if ($currentLogin -ine $owner) { throw "Authenticated GitHub user '$currentLogin' cannot create repositories for '$owner'." }
}

$created = 0
$existing = 0
$skipped = 0

foreach ($repository in @(Expand-XmipRepositories $manifest)) {
    $name = [string](Get-PropertyValue $repository 'name')
    $maturity = [string](Get-PropertyValue $repository 'maturity' 'reserved')

    if ($maturity -eq 'reserved' -and -not $IncludeReserved) {
        Write-Warning "SKIPPED RESERVED: $name"
        $skipped++
        continue
    }

    $exact = Invoke-GitHubRequest GET "/repos/$owner/$name"
    if ($exact.StatusCode -eq 200) {
        Write-Host "EXISTS: $owner/$name"
        $existing++
        continue
    }
    if ($exact.StatusCode -ne 404) {
        throw "Repository existence check failed for '$owner/$name': HTTP $($exact.StatusCode)."
    }

    if (-not $PSCmdlet.ShouldProcess("$owner/$name", 'Create GitHub repository')) {
        $skipped++
        continue
    }

    $github = Get-PropertyValue $repository 'github' ([pscustomobject]@{})
    $visibility = [string](Get-PropertyValue $github 'visibility' 'public')
    $body = [ordered]@{
        name = $name
        description = [string](Get-PropertyValue $repository 'description')
        private = ($visibility -eq 'private')
        auto_init = [bool](Get-PropertyValue $github 'autoInitialize' $true)
        has_issues = [bool](Get-PropertyValue $github 'hasIssues' $true)
        has_projects = [bool](Get-PropertyValue $github 'hasProjects' $false)
        has_wiki = [bool](Get-PropertyValue $github 'hasWiki' $false)
    }
    if ($ownerType -eq 'Organization') { $body.visibility = $visibility }

    Write-Host "CREATE: $owner/$name"
    $path = if ($ownerType -eq 'Organization') { "/orgs/$owner/repos" } else { '/user/repos' }
    $creation = Invoke-GitHubRequest POST $path $body

    if ($creation.StatusCode -eq 201) {
        $created++
        continue
    }

    if ($creation.StatusCode -eq 422) {
        $verification = Invoke-GitHubRequest GET "/repos/$owner/$name"
        if ($verification.StatusCode -eq 200) {
            Write-Host "EXISTS AFTER 422: $owner/$name"
            $existing++
            continue
        }
    }

    $message = [string](Get-PropertyValue $creation.Value 'message' 'Unknown GitHub error')
    throw "Repository creation failed for '$owner/$name': HTTP $($creation.StatusCode): $message"
}

Write-Host "Repository creation completed. Created: $created; Existing: $existing; Skipped: $skipped."
