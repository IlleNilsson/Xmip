#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string] $ManifestPath = (Join-Path $PSScriptRoot 'xmip-architecture.json'),
    [string] $DestinationPath = (Join-Path (Get-Location) 'xmip-repositories'),
    [ValidateSet('Https', 'Ssh')]
    [string] $Transport = 'Https',
    [switch] $UpdateExisting,
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

Assert-Command -Name 'git'

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Manifest not found: $ManifestPath"
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json -Depth 100
$owner = [string](Get-PropertyValue $manifest 'owner')
if (-not $owner) { throw 'Manifest owner is missing.' }

$repositoryNames = @(Expand-XmipRepositoryNames -Manifest $manifest)
if ($repositoryNames.Count -eq 0) { throw 'Manifest contains no repositories to clone.' }

$resolvedDestination = [IO.Path]::GetFullPath($DestinationPath)
if (-not (Test-Path -LiteralPath $resolvedDestination)) {
    if ($PSCmdlet.ShouldProcess($resolvedDestination, 'Create destination directory')) {
        New-Item -ItemType Directory -Path $resolvedDestination -Force | Out-Null
    }
}

$results = [Collections.Generic.List[object]]::new()

foreach ($repositoryName in $repositoryNames) {
    $repositoryPath = Join-Path $resolvedDestination $repositoryName
    $cloneUrl = if ($Transport -eq 'Ssh') {
        "git@github.com:$owner/$repositoryName.git"
    }
    else {
        "https://github.com/$owner/$repositoryName.git"
    }

    if (Test-Path -LiteralPath $repositoryPath) {
        $gitDirectory = Join-Path $repositoryPath '.git'
        if (-not (Test-Path -LiteralPath $gitDirectory)) {
            throw "Destination path exists but is not a Git repository: $repositoryPath"
        }

        if ($UpdateExisting) {
            if ($PSCmdlet.ShouldProcess($repositoryPath, 'Fetch and fast-forward existing repository')) {
                Invoke-Git -At $repositoryPath -Arguments @('fetch', '--all', '--prune')
                Invoke-Git -At $repositoryPath -Arguments @('pull', '--ff-only')
                Write-Host "UPDATED: $repositoryName"
                $status = 'updated'
            }
            else {
                $status = 'skipped'
            }
        }
        else {
            Write-Host "EXISTS: $repositoryName"
            $status = 'existing'
        }
    }
    else {
        if ($PSCmdlet.ShouldProcess($repositoryPath, "Clone $cloneUrl")) {
            Invoke-Git -Arguments @('clone', $cloneUrl, $repositoryPath)
            Write-Host "CLONED: $repositoryName"
            $status = 'cloned'
        }
        else {
            $status = 'skipped'
        }
    }

    $results.Add([pscustomobject]@{
        repository = $repositoryName
        path = $repositoryPath
        url = $cloneUrl
        status = $status
    })
}

$summary = [pscustomobject]@{
    owner = $owner
    manifestPath = [IO.Path]::GetFullPath($ManifestPath)
    destinationPath = $resolvedDestination
    transport = $Transport
    repositoryCount = $repositoryNames.Count
    cloned = @($results | Where-Object status -eq 'cloned').Count
    updated = @($results | Where-Object status -eq 'updated').Count
    existing = @($results | Where-Object status -eq 'existing').Count
    skipped = @($results | Where-Object status -eq 'skipped').Count
    repositories = @($results)
}

Write-Host "Clone completed. Total: $($summary.repositoryCount); Cloned: $($summary.cloned); Updated: $($summary.updated); Existing: $($summary.existing); Skipped: $($summary.skipped)."

if ($PassThru) {
    return $summary
}
