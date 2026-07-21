#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string] $ManifestPath = (Join-Path $PSScriptRoot 'xmip-architecture.json'),
    [string] $WorkingDirectory = (Join-Path $PSScriptRoot '.xmip-work'),
    [switch] $Apply,
    [switch] $CreateRepositories,
    [switch] $ConfigureRepositories,
    [switch] $SynchronizeSubmodules,
    [switch] $GenerateMetadata,
    [switch] $CommitChanges,
    [switch] $PushChanges,
    [switch] $IncludeReserved,
    [switch] $ReportDeprecated = $true,
    [string] $ReportPath,
    [switch] $PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step([string] $Message) {
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Assert-Command([string] $Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found."
    }
}

function Invoke-Native {
    param([string] $FilePath, [string[]] $Arguments = @(), [string] $At = '')
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

function Expand-XmipManifest($Source) {
    if ($Source.repositories) { return $Source }

    $repositories = [Collections.Generic.List[object]]::new()

    foreach ($item in @($Source.commonRepositories)) {
        $repositories.Add([pscustomobject]@{
            name = $item.name
            description = $item.description
            architecturalDomain = $item.architecturalDomain
            repositoryRole = $item.repositoryRole
            maturity = $(if ($item.maturity) { $item.maturity } else { $Source.defaults.maturity })
            dependencies = @($item.dependencies)
            github = [pscustomobject]@{
                visibility = $Source.defaults.visibility
                autoInitialize = $Source.defaults.autoInitialize
                hasIssues = $Source.defaults.hasIssues
                hasProjects = $Source.defaults.hasProjects
                hasWiki = $Source.defaults.hasWiki
                topics = @('xmip', $item.architecturalDomain.ToLowerInvariant())
            }
            submodule = [pscustomobject]@{ enabled = $false }
        })
    }

    foreach ($group in @($Source.technologyGroups)) {
        $capability = $group.parent -replace '^xmip-', ''
        foreach ($technology in @($group.technologies)) {
            $technologyName = $(if ($technology.name) { $technology.name } else { [string] $technology })
            $description = $(if ($technology.description) { $technology.description } else { "$technologyName implementation of $($group.parent)." })
            $maturity = $(if ($technology.maturity) { $technology.maturity } else { $Source.defaults.maturity })
            $name = "$($group.parent)-$technologyName"

            $repositories.Add([pscustomobject]@{
                name = $name
                description = $description
                architecturalDomain = 'Technology'
                repositoryRole = 'technology-implementation'
                maturity = $maturity
                capability = $capability
                technology = $technologyName
                parent = $group.parent
                dependencies = @($group.dependencies)
                github = [pscustomobject]@{
                    visibility = $Source.defaults.visibility
                    autoInitialize = $Source.defaults.autoInitialize
                    hasIssues = $Source.defaults.hasIssues
                    hasProjects = $Source.defaults.hasProjects
                    hasWiki = $Source.defaults.hasWiki
                    topics = @('xmip', 'technology', $capability, $technologyName)
                }
                submodule = [pscustomobject]@{
                    enabled = $true
                    parentRepository = $group.parent
                    path = "modules/$technologyName"
                    revision = $technology.revision
                    branch = $technology.branch
                }
            })
        }
    }

    $Source | Add-Member -NotePropertyName repositories -NotePropertyValue @($repositories) -Force
    $Source
}

function Get-XmipManifest([string] $Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Manifest not found: $Path"
    }
    $source = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 100
    Expand-XmipManifest $source
}

function Test-DependencyGraph($Manifest) {
    $map = @{}
    foreach ($repository in $Manifest.repositories) {
        $map[$repository.name] = @($repository.dependencies)
    }

    $state = @{}
    $stack = [Collections.Generic.List[string]]::new()

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

function Test-XmipManifest($Manifest) {
    Write-Step 'Validating architecture manifest'

    if (-not $Manifest.owner) { throw 'Manifest owner is missing.' }
    if (-not $Manifest.repositories) { throw 'Manifest contains no repositories.' }

    $names = @($Manifest.repositories.name)
    $duplicates = $names | Group-Object | Where-Object Count -gt 1
    if ($duplicates) { throw "Duplicate repositories: $($duplicates.Name -join ', ')" }

    $nameSet = [Collections.Generic.HashSet[string]]::new([string[]] $names, [StringComparer]::OrdinalIgnoreCase)

    foreach ($repository in $Manifest.repositories) {
        if ($repository.name -notmatch '^xmip-[a-z0-9]+(?:-[a-z0-9]+)*$') {
            throw "Invalid repository name: $($repository.name)"
        }
        if (-not $repository.description) { throw "Description missing: $($repository.name)" }
        if ($repository.maturity -notin @('reserved','scaffolded','implemented','verified','supported','deprecated','retired')) {
            throw "Invalid maturity '$($repository.maturity)' for '$($repository.name)'"
        }
        if ($repository.submodule.enabled) {
            if (-not $repository.parent) { throw "Submodule '$($repository.name)' has no parent." }
            if (-not $nameSet.Contains([string] $repository.parent)) {
                throw "Unknown parent '$($repository.parent)' for '$($repository.name)'"
            }
            if (-not $repository.submodule.path) { throw "Submodule path missing: $($repository.name)" }
        }
        foreach ($dependency in @($repository.dependencies)) {
            if (-not $nameSet.Contains([string] $dependency)) {
                throw "Unknown dependency '$dependency' for '$($repository.name)'"
            }
            if ($dependency -eq $repository.name) { throw "Self dependency: $($repository.name)" }
        }
    }

    Test-DependencyGraph $Manifest
}

function Get-SelectedRepositories($Manifest) {
    @($Manifest.repositories | Where-Object {
        ($IncludeReserved -or $_.maturity -ne 'reserved') -and
        $_.maturity -notin @('deprecated', 'retired')
    })
}

function Get-ActualGitHubRepositories([string] $Owner) {
    $json = & gh repo list $Owner --limit 1000 --json name,description,visibility,isArchived 2>$null
    if ($LASTEXITCODE -ne 0) { throw "Unable to list repositories for '$Owner'." }
    @($json | ConvertFrom-Json)
}

function Get-ArchitectureDrift($Manifest, [array] $ActualRepositories) {
    $desired = @{}
    foreach ($repository in $Manifest.repositories) { $desired[$repository.name] = $repository }

    $actual = @{}
    foreach ($repository in $ActualRepositories) { $actual[$repository.name] = $repository }

    $deprecated = @($Manifest.repositories | Where-Object maturity -eq 'deprecated' | Sort-Object name)
    $retired = @($Manifest.repositories | Where-Object maturity -eq 'retired' | Sort-Object name)
    $deprecatedNames = @{}
    foreach ($repository in @($deprecated + $retired)) { $deprecatedNames[$repository.name] = $repository.maturity }

    $references = @()
    foreach ($repository in $Manifest.repositories | Where-Object maturity -notin @('deprecated','retired')) {
        foreach ($dependency in @($repository.dependencies)) {
            if ($deprecatedNames.ContainsKey([string] $dependency)) {
                $references += [pscustomobject]@{
                    repository = $repository.name
                    dependency = $dependency
                    maturity = $deprecatedNames[$dependency]
                }
            }
        }
    }

    [pscustomobject]@{
        generatedAtUtc = [DateTime]::UtcNow.ToString('o')
        owner = $Manifest.owner
        desiredCount = $desired.Count
        actualCount = $actual.Count
        missing = @($desired.Keys | Where-Object { -not $actual.ContainsKey($_) } | Sort-Object)
        unexpected = @($actual.Keys | Where-Object { $_ -like 'xmip-*' -and -not $desired.ContainsKey($_) } | Sort-Object)
        deprecated = $deprecated
        retired = $retired
        activeDeprecatedReferences = $references
    }
}

function Show-ArchitectureDrift($Drift) {
    Write-Step "Drift: $($Drift.missing.Count) missing, $($Drift.unexpected.Count) unexpected, $($Drift.deprecated.Count) deprecated, $($Drift.retired.Count) retired"
    foreach ($name in $Drift.missing) { Write-Warning "MISSING: $name" }
    foreach ($name in $Drift.unexpected) { Write-Warning "UNEXPECTED: $name" }
    foreach ($item in $Drift.deprecated) { Write-Warning "DEPRECATED: $($item.name)" }
    foreach ($item in $Drift.retired) { Write-Warning "RETIRED: $($item.name)" }
    foreach ($reference in $Drift.activeDeprecatedReferences) {
        Write-Warning "$($reference.repository) depends on $($reference.maturity) repository $($reference.dependency)"
    }
}

function Test-RepositoryExists([string] $Owner, [string] $Name) {
    & gh repo view "$Owner/$Name" --json name *> $null
    $LASTEXITCODE -eq 0
}

function New-XmipRepository($Manifest, $Repository) {
    $fullName = "$($Manifest.owner)/$($Repository.name)"
    if (Test-RepositoryExists $Manifest.owner $Repository.name) { return }

    $arguments = @('repo','create',$fullName,'--description',[string]$Repository.description,"--$($Repository.github.visibility)")
    if ($Repository.github.autoInitialize) { $arguments += '--add-readme' }

    if ($Apply -and $PSCmdlet.ShouldProcess($fullName, 'Create repository')) {
        Invoke-Native gh $arguments
    }
    else {
        Write-Host "PLAN create repository: $fullName"
    }
}

function Set-XmipRepositorySettings($Manifest, $Repository) {
    $fullName = "$($Manifest.owner)/$($Repository.name)"
    if (-not (Test-RepositoryExists $Manifest.owner $Repository.name)) {
        Write-Warning "Cannot configure missing repository: $fullName"
        return
    }

    $arguments = @(
        'repo','edit',$fullName,
        '--description',[string]$Repository.description,
        '--visibility',[string]$Repository.github.visibility,
        '--enable-issues',([string]$Repository.github.hasIssues).ToLowerInvariant(),
        '--enable-projects',([string]$Repository.github.hasProjects).ToLowerInvariant(),
        '--enable-wiki',([string]$Repository.github.hasWiki).ToLowerInvariant()
    )

    if ($Apply -and $PSCmdlet.ShouldProcess($fullName, 'Configure repository')) {
        Invoke-Native gh $arguments
    }
    else {
        Write-Host "PLAN configure repository: $fullName"
    }
}

function Get-RepositoryClone($Manifest, $Repository) {
    if (-not $Apply) { throw 'Repository cloning is an Apply-mode operation.' }

    $path = Join-Path $WorkingDirectory $Repository.name
    $url = "https://github.com/$($Manifest.owner)/$($Repository.name).git"

    if (Test-Path (Join-Path $path '.git')) {
        Invoke-Native git @('fetch','--all','--prune') $path
        Invoke-Native git @('checkout',$Manifest.defaults.defaultBranch) $path
        Invoke-Native git @('pull','--ff-only') $path
    }
    else {
        New-Item -ItemType Directory -Force -Path $WorkingDirectory | Out-Null
        Invoke-Native git @('clone',$url,$path)
    }
    $path
}

function Get-ConfiguredSubmodulePaths([string] $RepositoryPath) {
    if (-not (Test-Path (Join-Path $RepositoryPath '.gitmodules'))) { return @() }
    $lines = & git -C $RepositoryPath config --file .gitmodules --get-regexp path 2>$null
    if ($LASTEXITCODE -ne 0) { return @() }
    @($lines | ForEach-Object { ($_ -split '\s+', 2)[1] })
}

function Set-ParentSubmodules($Manifest, $Parent) {
    $children = @($Manifest.repositories | Where-Object {
        $_.submodule.enabled -and $_.parent -eq $Parent.name -and $_.maturity -notin @('deprecated','retired')
    })

    if (-not $Apply) {
        foreach ($child in $children) {
            Write-Host "PLAN ensure submodule $($Parent.name)/$($child.submodule.path) -> $($child.name)"
        }
        return
    }

    $path = Get-RepositoryClone $Manifest $Parent
    $configuredPaths = @(Get-ConfiguredSubmodulePaths $path)
    $desiredPaths = @($children.submodule.path)

    foreach ($unexpectedPath in $configuredPaths | Where-Object { $_ -notin $desiredPaths }) {
        Write-Warning "UNEXPECTED SUBMODULE: $($Parent.name)/$unexpectedPath. No automatic removal is performed."
    }

    foreach ($child in $children) {
        $remote = "https://github.com/$($Manifest.owner)/$($child.name).git"
        $submodulePath = [string] $child.submodule.path

        if ($submodulePath -notin $configuredPaths -and $PSCmdlet.ShouldProcess("$($Parent.name)/$submodulePath", "Add submodule $($child.name)")) {
            Invoke-Native git @('submodule','add',$remote,$submodulePath) $path
        }

        if ($child.submodule.revision) {
            Invoke-Native git @('submodule','update','--init','--',$submodulePath) $path
            Invoke-Native git @('checkout',[string]$child.submodule.revision) (Join-Path $path $submodulePath)
            Invoke-Native git @('add','--',$submodulePath) $path
        }
    }

    if ($GenerateMetadata) {
        [ordered]@{
            name = $Parent.name
            architecturalDomain = $Parent.architecturalDomain
            repositoryRole = $Parent.repositoryRole
            maturity = $Parent.maturity
            dependencies = @($Parent.dependencies)
            technologySubmodules = @($children | ForEach-Object {
                [ordered]@{ name=$_.name; path=$_.submodule.path; revision=$_.submodule.revision }
            })
        } | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $path 'xmip.repository.json') -Encoding utf8NoBOM
    }

    if ($CommitChanges) {
        Invoke-Native git @('add','--all') $path
        & git -C $path diff --cached --quiet
        if ($LASTEXITCODE -ne 0 -and $PSCmdlet.ShouldProcess($Parent.name, 'Commit architecture reconciliation')) {
            Invoke-Native git @('commit','-m','Reconcile Xmip architecture') $path
            if ($PushChanges) { Invoke-Native git @('push','origin',$Manifest.defaults.defaultBranch) $path }
        }
    }
}

Assert-Command gh
Assert-Command git

$manifest = Get-XmipManifest $ManifestPath
Test-XmipManifest $manifest
$selectedRepositories = @(Get-SelectedRepositories $manifest)
$actualRepositories = @(Get-ActualGitHubRepositories $manifest.owner)
$drift = Get-ArchitectureDrift $manifest $actualRepositories
Show-ArchitectureDrift $drift

if (-not $ReportPath) { $ReportPath = Join-Path $WorkingDirectory 'xmip-architecture-drift.json' }
if ($ReportDeprecated -and $Apply) {
    $directory = Split-Path -Parent $ReportPath
    if ($directory) { New-Item -ItemType Directory -Force -Path $directory | Out-Null }
    $drift | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $ReportPath -Encoding utf8NoBOM
    Write-Host "Report written: $ReportPath"
}
elseif ($ReportDeprecated) {
    Write-Host "PLAN report path: $ReportPath"
}

if (-not ($CreateRepositories -or $ConfigureRepositories -or $SynchronizeSubmodules -or $GenerateMetadata)) {
    Write-Step 'No reconciliation operation selected; reporting only.'
}

if ($CreateRepositories) {
    Write-Step 'Reconciling missing repositories'
    foreach ($repository in $selectedRepositories) { New-XmipRepository $manifest $repository }
}

if ($ConfigureRepositories) {
    Write-Step 'Reconciling repository settings'
    foreach ($repository in $selectedRepositories) { Set-XmipRepositorySettings $manifest $repository }
}

if ($SynchronizeSubmodules -or $GenerateMetadata) {
    Write-Step 'Reconciling capability submodules'
    foreach ($parent in $selectedRepositories | Where-Object { -not $_.submodule.enabled }) {
        if ($manifest.repositories | Where-Object { $_.submodule.enabled -and $_.parent -eq $parent.name }) {
            Set-ParentSubmodules $manifest $parent
        }
    }
}

$result = [pscustomobject]@{
    Manifest = (Resolve-Path $ManifestPath).Path
    Owner = $manifest.owner
    SelectedRepositoryCount = $selectedRepositories.Count
    DesiredRepositoryCount = $manifest.repositories.Count
    ActualRepositoryCount = $actualRepositories.Count
    MissingCount = $drift.missing.Count
    UnexpectedCount = $drift.unexpected.Count
    DeprecatedCount = $drift.deprecated.Count
    RetiredCount = $drift.retired.Count
    Mode = $(if ($Apply) { 'Apply' } else { 'Plan' })
    ReportPath = $ReportPath
}

Write-Step "Architecture reconciliation completed in $($result.Mode) mode"
if ($PassThru) { $result }
