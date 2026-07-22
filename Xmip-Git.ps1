#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Clone')]
param(
    [Parameter(ParameterSetName = 'Clone')]
    [switch] $Clone,

    [Parameter(Mandatory, ParameterSetName = 'Pull')]
    [switch] $Pull,

    [string] $ManifestPath = (Join-Path $PSScriptRoot 'xmip-architecture.json'),
    [string] $DestinationPath = (Join-Path (Get-Location) 'xmip-repositories'),

    [ValidateSet('Https', 'Ssh')]
    [string] $Transport = 'Https',

    [switch] $PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PropertyValue {
    param(
        [AllowNull()] $Object,
        [Parameter(Mandatory)] [string] $Name,
        $Default = $null
    )

    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) { return $Default }
    return $property.Value
}

function Assert-Command {
    param([Parameter(Mandatory)] [string] $Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found."
    }
}

function Invoke-Git {
    param(
        [Parameter(Mandatory)] [string[]] $Arguments,
        [string] $At = ''
    )

    $previousLocation = $PWD
    try {
        if ($At) { Set-Location -LiteralPath $At }
        & git @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "Git command failed: git $($Arguments -join ' ')"
        }
    }
    finally {
        Set-Location $previousLocation
    }
}

function Expand-XmipRepositoryNames {
    param([Parameter(Mandatory)] $Manifest)

    $names = [Collections.Generic.List[string]]::new()
    $explicitRepositories = @(Get-PropertyValue $Manifest 'repositories' @())

    if ($explicitRepositories.Count -gt 0) {
        foreach ($repository in $explicitRepositories) {
            $name = [string](Get-PropertyValue $repository 'name')
            if ($name) { $names.Add($name) }
        }
    }
    else {
        foreach ($repository in @(Get-PropertyValue $Manifest 'commonRepositories' @())) {
            $name = if ($repository -is [System.Array]) {
                [string]$repository[0]
            }
            else {
                [string](Get-PropertyValue $repository 'name')
            }
            if ($name) { $names.Add($name) }
        }

        foreach ($group in @(Get-PropertyValue $Manifest 'technologyGroups' @())) {
            $parent = if ($group -is [System.Array]) {
                [string]$group[0]
            }
            else {
                [string](Get-PropertyValue $group 'parent')
            }

            $technologies = if ($group -is [System.Array]) {
                @($group[2])
            }
            else {
                @(Get-PropertyValue $group 'technologies' @())
            }

            foreach ($technology in $technologies) {
                $technologyName = if ($technology -is [string]) {
                    $technology
                }
                else {
                    [string](Get-PropertyValue $technology 'name')
                }

                if ($parent -and $technologyName) {
                    $names.Add("$parent-$technologyName")
                }
            }
        }
    }

    return @($names | Sort-Object -Unique)
}

function Get-CloneUrl {
    param(
        [Parameter(Mandatory)] [string] $Owner,
        [Parameter(Mandatory)] [string] $RepositoryName,
        [Parameter(Mandatory)] [ValidateSet('Https', 'Ssh')] [string] $Transport
    )

    if ($Transport -eq 'Ssh') {
        return "git@github.com:$Owner/$RepositoryName.git"
    }

    return "https://github.com/$Owner/$RepositoryName.git"
}

function Test-GitRepository {
    param([Parameter(Mandatory)] [string] $Path)

    return Test-Path -LiteralPath (Join-Path $Path '.git') -PathType Container
}

Assert-Command -Name 'git'

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Manifest not found: $ManifestPath"
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json -Depth 100
$owner = [string](Get-PropertyValue $manifest 'owner')
if (-not $owner) { throw 'Manifest owner is missing.' }

$repositoryNames = @(Expand-XmipRepositoryNames -Manifest $manifest)
if ($repositoryNames.Count -eq 0) { throw 'Manifest contains no repositories.' }

$operation = if ($Pull) { 'Pull' } else { 'Clone' }
$resolvedDestination = [IO.Path]::GetFullPath($DestinationPath)

if ($operation -eq 'Clone' -and -not (Test-Path -LiteralPath $resolvedDestination)) {
    if ($PSCmdlet.ShouldProcess($resolvedDestination, 'Create destination directory')) {
        New-Item -ItemType Directory -Path $resolvedDestination -Force | Out-Null
    }
}
elseif ($operation -eq 'Pull' -and -not (Test-Path -LiteralPath $resolvedDestination -PathType Container)) {
    throw "Destination directory does not exist: $resolvedDestination"
}

$results = [Collections.Generic.List[object]]::new()

foreach ($repositoryName in $repositoryNames) {
    $repositoryPath = Join-Path $resolvedDestination $repositoryName
    $cloneUrl = Get-CloneUrl -Owner $owner -RepositoryName $repositoryName -Transport $Transport
    $status = $null

    if ($operation -eq 'Clone') {
        if (Test-Path -LiteralPath $repositoryPath) {
            if (-not (Test-GitRepository -Path $repositoryPath)) {
                throw "Destination path exists but is not a Git repository: $repositoryPath"
            }

            Write-Host "EXISTS: $repositoryName"
            $status = 'existing'
        }
        elseif ($PSCmdlet.ShouldProcess($repositoryPath, "Clone $cloneUrl")) {
            Invoke-Git -Arguments @('clone', $cloneUrl, $repositoryPath)
            Write-Host "CLONED: $repositoryName"
            $status = 'cloned'
        }
        else {
            $status = 'skipped'
        }
    }
    else {
        if (-not (Test-Path -LiteralPath $repositoryPath)) {
            Write-Warning "MISSING: $repositoryName"
            $status = 'missing'
        }
        elseif (-not (Test-GitRepository -Path $repositoryPath)) {
            throw "Destination path exists but is not a Git repository: $repositoryPath"
        }
        elseif ($PSCmdlet.ShouldProcess($repositoryPath, 'Fetch, prune and fast-forward')) {
            Invoke-Git -At $repositoryPath -Arguments @('fetch', '--all', '--prune')
            Invoke-Git -At $repositoryPath -Arguments @('pull', '--ff-only')
            Write-Host "PULLED: $repositoryName"
            $status = 'pulled'
        }
        else {
            $status = 'skipped'
        }
    }

    $results.Add([pscustomobject]@{
        repository = $repositoryName
        path = $repositoryPath
        url = $cloneUrl
        operation = $operation.ToLowerInvariant()
        status = $status
    })
}

$summary = [pscustomobject]@{
    operation = $operation.ToLowerInvariant()
    owner = $owner
    manifestPath = [IO.Path]::GetFullPath($ManifestPath)
    destinationPath = $resolvedDestination
    transport = $Transport
    repositoryCount = $repositoryNames.Count
    cloned = @($results | Where-Object status -eq 'cloned').Count
    pulled = @($results | Where-Object status -eq 'pulled').Count
    existing = @($results | Where-Object status -eq 'existing').Count
    missing = @($results | Where-Object status -eq 'missing').Count
    skipped = @($results | Where-Object status -eq 'skipped').Count
    repositories = @($results)
}

Write-Host "$operation completed. Total: $($summary.repositoryCount); Cloned: $($summary.cloned); Pulled: $($summary.pulled); Existing: $($summary.existing); Missing: $($summary.missing); Skipped: $($summary.skipped)."

if ($PassThru) {
    return $summary
}
