#requires -Version 7.2
[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [string]$ManifestPath = (Join-Path $PSScriptRoot 'xmip-architecture.json'),
  [string]$WorkingDirectory = (Join-Path $PSScriptRoot '.xmip-work'),
  [switch]$Apply,
  [switch]$CreateRepositories,
  [switch]$ConfigureRepositories,
  [switch]$SynchronizeSubmodules,
  [switch]$GenerateMetadata,
  [switch]$GenerateCargoWorkspaces,
  [switch]$CommitChanges,
  [switch]$PushChanges,
  [switch]$IncludeReserved,
  [switch]$ReportDeprecated = $true,
  [string]$DeprecatedReportPath = (Join-Path $WorkingDirectory 'xmip-deprecated-items.json'),
  [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }
function Assert-Command([string]$Name) { if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) { throw "Required command '$Name' not found." } }
function Invoke-Native([string]$File,[string[]]$Arguments,[string]$At='') {
  $previous = $PWD
  try {
    if ($At) { Set-Location $At }
    & $File @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Command failed: $File $($Arguments -join ' ')" }
  } finally { Set-Location $previous }
}

function Expand-XmipManifest($Source) {
  if ($Source.repositories) { return $Source }

  $repositories = [Collections.Generic.List[object]]::new()
  foreach ($row in @($Source.commonRepositories)) {
    $name,$description,$domain,$role,$dependencies = $row
    $repositories.Add([pscustomobject]@{
      name = $name
      description = $description
      architecturalDomain = $domain
      repositoryRole = $role
      maturity = $Source.defaults.maturity
      github = [pscustomobject]@{
        visibility = $Source.defaults.visibility
        autoInitialize = $Source.defaults.autoInitialize
        hasIssues = $Source.defaults.hasIssues
        hasProjects = $Source.defaults.hasProjects
        hasWiki = $Source.defaults.hasWiki
        topics = @('xmip',$domain.ToLowerInvariant())
      }
      generation = [pscustomobject]@{ readme=$true; license=$false; codeowners=$true; security=$true; ci=$true; issueTemplates=$true }
      dependencies = @($dependencies)
      submodule = [pscustomobject]@{ enabled=$false }
      cargo = [pscustomobject]@{ enabled=$true; crate=$name.Replace('-','_'); workspaceMember=$false }
    })
  }

  foreach ($group in @($Source.technologyGroups)) {
    $parent,$dependencies,$technologies = $group
    $capability = $parent -replace '^xmip-',''
    foreach ($technology in @($technologies)) {
      $name = "$parent-$technology"
      $repositories.Add([pscustomobject]@{
        name = $name
        description = "$technology implementation of $parent."
        architecturalDomain = 'Technology'
        repositoryRole = 'technology-implementation'
        maturity = $Source.defaults.maturity
        capability = $capability
        technology = $technology
        parent = $parent
        github = [pscustomobject]@{
          visibility = $Source.defaults.visibility
          autoInitialize = $Source.defaults.autoInitialize
          hasIssues = $Source.defaults.hasIssues
          hasProjects = $Source.defaults.hasProjects
          hasWiki = $Source.defaults.hasWiki
          topics = @('xmip','technology',$capability,$technology)
        }
        generation = [pscustomobject]@{ readme=$true; license=$false; codeowners=$true; security=$true; ci=$true; issueTemplates=$true }
        dependencies = @($dependencies)
        submodule = [pscustomobject]@{ enabled=$true; parentRepository=$parent; path="modules/$technology" }
        cargo = [pscustomobject]@{ enabled=$true; crate=$name.Replace('-','_'); workspaceMember=$true }
      })
    }
  }

  $Source | Add-Member -NotePropertyName repositories -NotePropertyValue @($repositories) -Force
  return $Source
}

function Get-XmipManifest([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Manifest not found: $Path" }
  $source = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 100
  Expand-XmipManifest $source
}

function Test-DependencyGraph($Manifest) {
  $map = @{}
  foreach ($repository in $Manifest.repositories) { $map[$repository.name] = @($repository.dependencies) }
  $state = @{}
  $stack = [Collections.Generic.List[string]]::new()
  function Visit([string]$Name) {
    if ($state[$Name] -eq 1) {
      $index = $stack.IndexOf($Name)
      $cycle = @($stack[$index..($stack.Count-1)]) + $Name
      throw "Dependency cycle: $($cycle -join ' -> ')"
    }
    if ($state[$Name] -eq 2) { return }
    $state[$Name] = 1
    $stack.Add($Name)
    foreach ($dependency in $map[$Name]) { Visit $dependency }
    $stack.RemoveAt($stack.Count-1)
    $state[$Name] = 2
  }
  foreach ($name in $map.Keys) { Visit $name }
}

function Test-XmipManifest($Manifest) {
  Write-Step 'Validating manifest'
  if (-not $Manifest.owner) { throw 'Manifest owner missing.' }
  $names = @($Manifest.repositories.name)
  $duplicates = $names | Group-Object | Where-Object Count -gt 1
  if ($duplicates) { throw "Duplicate repositories: $($duplicates.Name -join ', ')" }
  $set = [Collections.Generic.HashSet[string]]::new([string[]]$names,[StringComparer]::OrdinalIgnoreCase)
  foreach ($repository in $Manifest.repositories) {
    if ($repository.name -notmatch '^xmip-[a-z0-9]+(?:-[a-z0-9]+)*$') { throw "Invalid name: $($repository.name)" }
    if ($repository.maturity -notin @('reserved','scaffolded','implemented','verified','supported','deprecated','retired')) { throw "Invalid maturity: $($repository.name)" }
    if ($repository.submodule.enabled -and -not $set.Contains([string]$repository.parent)) { throw "Unknown parent '$($repository.parent)' for '$($repository.name)'" }
    foreach ($dependency in @($repository.dependencies)) {
      if (-not $set.Contains([string]$dependency)) { throw "Unknown dependency '$dependency' for '$($repository.name)'" }
      if ($dependency -eq $repository.name) { throw "Self dependency: $($repository.name)" }
    }
  }
  Test-DependencyGraph $Manifest
}

function Get-DeprecatedItems($Manifest) { @($Manifest.repositories | Where-Object maturity -in @('deprecated','retired') | Sort-Object maturity,name) }
function Write-DeprecatedReport($Manifest,[string]$Path) {
  $items = @(Get-DeprecatedItems $Manifest)
  $references = @()
  $deprecatedNames = @{}; foreach ($item in $items) { $deprecatedNames[$item.name] = $item.maturity }
  foreach ($repository in $Manifest.repositories) {
    foreach ($dependency in @($repository.dependencies)) {
      if ($deprecatedNames.ContainsKey([string]$dependency)) { $references += [pscustomobject]@{ repository=$repository.name; dependency=$dependency; maturity=$deprecatedNames[$dependency] } }
    }
  }
  $report = [ordered]@{
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    deprecatedCount = @($items | Where-Object maturity -eq 'deprecated').Count
    retiredCount = @($items | Where-Object maturity -eq 'retired').Count
    items = $items
    activeReferences = $references
  }
  $directory = Split-Path -Parent $Path
  if ($directory) { New-Item -ItemType Directory -Force -Path $directory | Out-Null }
  $report | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $Path -Encoding utf8NoBOM
  Write-Step "Deprecated report: $($report.deprecatedCount) deprecated, $($report.retiredCount) retired, $($references.Count) active references"
  foreach ($item in $items) { Write-Warning "$($item.maturity.ToUpperInvariant()): $($item.name)" }
  foreach ($reference in $references) { Write-Warning "$($reference.repository) depends on $($reference.maturity) repository $($reference.dependency)" }
  $report
}

function Test-RepositoryExists([string]$Owner,[string]$Name) { & gh repo view "$Owner/$Name" --json name *> $null; $LASTEXITCODE -eq 0 }
function Set-GitHubRepository($Manifest,$Repository) {
  $fullName = "$($Manifest.owner)/$($Repository.name)"
  if (-not (Test-RepositoryExists $Manifest.owner $Repository.name)) {
    $arguments = @('repo','create',$fullName,'--description',[string]$Repository.description,"--$($Repository.github.visibility)")
    if ($Repository.github.autoInitialize) { $arguments += '--add-readme' }
    if ($Apply -and $PSCmdlet.ShouldProcess($fullName,'Create repository')) { Invoke-Native gh $arguments }
    else { Write-Host "PLAN gh $($arguments -join ' ')" }
    return
  }
  if ($ConfigureRepositories) {
    $arguments = @('repo','edit',$fullName,'--description',[string]$Repository.description,'--visibility',[string]$Repository.github.visibility,
      '--enable-issues',([string]$Repository.github.hasIssues).ToLowerInvariant(),
      '--enable-projects',([string]$Repository.github.hasProjects).ToLowerInvariant(),
      '--enable-wiki',([string]$Repository.github.hasWiki).ToLowerInvariant())
    if ($Apply -and $PSCmdlet.ShouldProcess($fullName,'Configure repository')) { Invoke-Native gh $arguments }
    else { Write-Host "PLAN gh $($arguments -join ' ')" }
  }
}

function Get-RepositoryClone($Manifest,$Repository) {
  $path = Join-Path $WorkingDirectory $Repository.name
  $url = "https://github.com/$($Manifest.owner)/$($Repository.name).git"
  if (Test-Path (Join-Path $path '.git')) {
    Invoke-Native git @('fetch','--all','--prune') $path
    Invoke-Native git @('checkout',$Manifest.defaults.defaultBranch) $path
    Invoke-Native git @('pull','--ff-only') $path
  } else {
    New-Item -ItemType Directory -Force -Path $WorkingDirectory | Out-Null
    Invoke-Native git @('clone',$url,$path)
  }
  $path
}

function Set-ParentSubmodules($Manifest,$Parent) {
  $path = Get-RepositoryClone $Manifest $Parent
  $children = @($Manifest.repositories | Where-Object { $_.submodule.enabled -and $_.parent -eq $Parent.name -and $_.maturity -notin @('deprecated','retired') })
  foreach ($child in $children) {
    $remote = "https://github.com/$($Manifest.owner)/$($child.name).git"
    $configured = $false
    if (Test-Path (Join-Path $path '.gitmodules')) { $configured = [bool]((& git -C $path config --file .gitmodules --get-regexp path 2>$null) | Select-String -SimpleMatch $child.submodule.path) }
    if ($configured) { Invoke-Native git @('submodule','update','--init','--remote','--',$child.submodule.path) $path }
    elseif ($Apply -and $PSCmdlet.ShouldProcess("$($Parent.name)/$($child.submodule.path)","Add submodule $($child.name)")) { Invoke-Native git @('submodule','add',$remote,$child.submodule.path) $path }
    else { Write-Host "PLAN git -C '$path' submodule add '$remote' '$($child.submodule.path)'" }
  }
  if ($GenerateCargoWorkspaces) {
    $lines = @('[workspace]','resolver = "2"','members = [')
    foreach ($child in $children | Where-Object { $_.cargo.enabled -and $_.cargo.workspaceMember }) { $lines += "  `"$($child.submodule.path)`"," }
    $lines += ']'
    $lines -join [Environment]::NewLine | Set-Content -LiteralPath (Join-Path $path 'Cargo.toml') -Encoding utf8NoBOM
  }
  if ($GenerateMetadata) {
    [ordered]@{ name=$Parent.name; architecturalDomain=$Parent.architecturalDomain; repositoryRole=$Parent.repositoryRole; maturity=$Parent.maturity; dependencies=@($Parent.dependencies) } |
      ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $path 'xmip.repository.json') -Encoding utf8NoBOM
  }
  if ($CommitChanges) {
    Invoke-Native git @('add','--all') $path
    & git -C $path diff --cached --quiet
    if ($LASTEXITCODE -ne 0 -and $Apply -and $PSCmdlet.ShouldProcess($Parent.name,'Commit synchronized architecture')) {
      Invoke-Native git @('commit','-m','Synchronize Xmip architecture') $path
      if ($PushChanges) { Invoke-Native git @('push','origin',$Manifest.defaults.defaultBranch) $path }
    }
  }
}

Assert-Command git
Assert-Command gh
$manifest = Get-XmipManifest $ManifestPath
Test-XmipManifest $manifest
$deprecatedReport = $null
if ($ReportDeprecated) { $deprecatedReport = Write-DeprecatedReport $manifest $DeprecatedReportPath }
$repositories = @($manifest.repositories | Where-Object { ($IncludeReserved -or $_.maturity -ne 'reserved') -and $_.maturity -notin @('deprecated','retired') })
if (-not ($CreateRepositories -or $ConfigureRepositories -or $SynchronizeSubmodules -or $GenerateMetadata -or $GenerateCargoWorkspaces)) {
  $CreateRepositories = $ConfigureRepositories = $SynchronizeSubmodules = $GenerateMetadata = $GenerateCargoWorkspaces = $true
}
Write-Step "Selected repositories: $($repositories.Count)"
if ($CreateRepositories -or $ConfigureRepositories) { foreach ($repository in $repositories) { Set-GitHubRepository $manifest $repository } }
if ($SynchronizeSubmodules -or $GenerateCargoWorkspaces -or $GenerateMetadata) {
  foreach ($parent in $repositories | Where-Object { -not $_.submodule.enabled }) {
    if ($manifest.repositories | Where-Object { $_.submodule.enabled -and $_.parent -eq $parent.name }) { Set-ParentSubmodules $manifest $parent }
  }
}
$result = [pscustomobject]@{ Manifest=(Resolve-Path $ManifestPath).Path; Owner=$manifest.owner; RepositoryCount=$repositories.Count; Mode=$(if($Apply){'Apply'}else{'Plan'}); DeprecatedReport=$DeprecatedReportPath }
Write-Step "Architecture set completed in $($result.Mode) mode"
if ($PassThru) { $result }
