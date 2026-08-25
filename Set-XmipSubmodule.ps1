#Requires -Version 7.2

<#
.SYNOPSIS
    Brings a repository's submodules into agreement with architecture.toml.

.DESCRIPTION
    The manifest tree is the data. A repository name is derived from its
    position in that tree, so the submodule layout is derived from it too:

        provider.core.module.transport                 -> xmip-core-transport
        provider.core.module.transport.implementation.http
                                                       -> xmip-core-transport-http

    The tree is two levels deep and so is the wiring. A .gitmodules file
    belongs to the repository that pins, never to the repository pinned, so
    this script does one level at a time and works out which level it is
    standing in:

        Xmip                  root, pins the modules      -> modules/transport
        xmip-core-transport   module, pins its standards  -> modules/http

    Run it at any time. Missing submodules are added, moved submodules are
    moved, submodules the manifest no longer names are reported and removed
    only when -Remove is given. Nothing is written without -WhatIf telling
    you first.

    A module is wired when its repository exists. Maturity gates repository
    creation, not composition: you cannot pin what has not been created, and
    a repository that exists is a repository worth pinning. Use -Strict to
    turn an absent repository into an error rather than a note.

.PARAMETER ManifestPath
    architecture.toml. Defaults to the file beside this script, then to the
    one at the root of the repository being operated on.

.PARAMETER RepositoryPath
    The working tree to wire. Defaults to the current directory.

.PARAMETER Level
    module        pin the modules of a provider (root repository)
    implementation pin the standards of one module (module repository)
    auto          decide from the repository's own name. Default.

.PARAMETER Provider
    Which provider subtree to read. Defaults to core.

.PARAMETER Protocol
    https or ssh. Defaults to https, which is what a fresh clone of a public
    repository already uses.

.PARAMETER Remove
    Remove submodules the manifest no longer names. Warns for each and
    refuses to touch one that has uncommitted work inside it.

.PARAMETER Update
    After wiring, fetch each submodule's tracked branch.

.PARAMETER Strict
    Treat a manifest module with no repository as an error.

.EXAMPLE
    ./Set-XmipSubmodule.ps1 -WhatIf
    Say what would happen to the current repository and change nothing.

.EXAMPLE
    ./Set-XmipSubmodule.ps1 -Remove
    Wire the tree and drop submodules the manifest has forgotten.

.EXAMPLE
    ./Set-XmipSubmodule.ps1 -RepositoryPath ../xmip-core-transport
    Wire the standards of the transport module from inside its own repository.
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [string] $ManifestPath,

    [string] $RepositoryPath = (Get-Location).Path,

    [ValidateSet('module', 'implementation', 'auto')]
    [string] $Level = 'auto',

    [string] $Provider = 'core',

    [ValidateSet('https', 'ssh')]
    [string] $Protocol = 'https',

    [switch] $Remove,

    [switch] $Update,

    [switch] $Strict
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------

function Test-XmipCommand {
    param([Parameter(Mandatory)] [string] $Name)
    [bool] (Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue)
}

function Assert-XmipEnvironment {
    if (-not (Test-XmipCommand -Name 'git')) {
        $hint = if ($IsWindows) {
            'winget install --id Git.Git'
        }
        elseif ($IsMacOS) {
            'brew install git'
        }
        else {
            'apt install git, dnf install git, zypper install git or pacman -S git'
        }
        throw "git is not on PATH. Install it with: $hint"
    }

    if (-not (Get-Module -ListAvailable -Name PSToml)) {
        throw 'PSToml is not installed. Run Install-XmipPrerequisite.ps1 -Role developer, or Install-Module PSToml -Scope CurrentUser.'
    }

    Import-Module PSToml -ErrorAction Stop
}

# ---------------------------------------------------------------------------
# git, with its exit code respected
# ---------------------------------------------------------------------------

function Invoke-XmipGit {
    <#
        git writes progress to stderr on a good day, so stderr alone is not a
        failure. The exit code is.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $WorkingDirectory,
        [Parameter(Mandatory, ValueFromRemainingArguments)] [string[]] $Argument,
        [switch] $AllowFailure
    )

    # A repository that does not exist must come back as a failure, not as a
    # credential prompt sitting there waiting for someone to notice.
    $previousPrompt = $env:GIT_TERMINAL_PROMPT
    $env:GIT_TERMINAL_PROMPT = '0'
    try {
        $output = & git -C $WorkingDirectory @Argument 2>&1
        $code = $LASTEXITCODE
    }
    finally {
        $env:GIT_TERMINAL_PROMPT = $previousPrompt
    }

    if ($code -ne 0 -and -not $AllowFailure) {
        throw "git $($Argument -join ' ') failed with exit code $code`n$($output -join [Environment]::NewLine)"
    }

    [pscustomobject]@{
        ExitCode = $code
        Output   = @($output | ForEach-Object { "$_" })
        Failed   = ($code -ne 0)
    }
}

function Assert-XmipWorkingTree {
    param([Parameter(Mandatory)] [string] $Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "No such directory: $Path"
    }

    $top = Invoke-XmipGit -WorkingDirectory $Path -Argument 'rev-parse', '--show-toplevel' -AllowFailure
    if ($top.Failed) {
        throw "$Path is not inside a git working tree."
    }

    (Resolve-Path -LiteralPath $top.Output[0]).Path
}

# ---------------------------------------------------------------------------
# Manifest
#
# ConvertFrom-Toml has been known to hand back a dictionary in one version and
# an object in the next. Which one it is should not be a thing this script has
# an opinion about, so it never asks directly.
# ---------------------------------------------------------------------------

function Get-XmipKey {
    param($Node)

    if ($null -eq $Node) { return @() }
    if ($Node -is [System.Collections.IDictionary]) { return @($Node.Keys) }
    @($Node.PSObject.Properties.Name)
}

function Get-XmipValue {
    param($Node, [Parameter(Mandatory)] [string] $Name)

    if ($null -eq $Node) { return $null }

    if ($Node -is [System.Collections.IDictionary]) {
        if ($Node.Contains($Name)) { return $Node[$Name] }
        return $null
    }

    $property = $Node.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    $null
}

function Test-XmipKey {
    param($Node, [Parameter(Mandatory)] [string] $Name)
    (Get-XmipKey -Node $Node) -contains $Name
}

function Resolve-XmipManifest {
    param(
        [string] $Explicit,
        [Parameter(Mandatory)] [string] $RepositoryRoot
    )

    $candidate = @()
    if ($Explicit) { $candidate += $Explicit }
    if ($PSScriptRoot) { $candidate += (Join-Path $PSScriptRoot 'architecture.toml') }
    $candidate += (Join-Path $RepositoryRoot 'architecture.toml')
    $candidate += (Join-Path (Split-Path -Parent $RepositoryRoot) 'Xmip/architecture.toml')

    foreach ($path in $candidate) {
        if ($path -and (Test-Path -LiteralPath $path -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $path).Path
        }
    }

    throw "architecture.toml not found. Looked in: $($candidate -join '; ')"
}

function Read-XmipManifest {
    param([Parameter(Mandatory)] [string] $Path)

    $manifest = Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Toml

    foreach ($required in 'owner', 'provider') {
        if (-not (Test-XmipKey -Node $manifest -Name $required)) {
            throw "$Path has no '$required'. Is it schema 2.0?"
        }
    }

    $manifest
}

function Get-XmipSetting {
    param(
        [Parameter(Mandatory)] $Manifest,
        [Parameter(Mandatory)] [string] $Name,
        $Fallback
    )

    $defaults = Get-XmipValue -Node $Manifest -Name 'default'
    if ($defaults -and (Test-XmipKey -Node $defaults -Name $Name)) {
        return (Get-XmipValue -Node $defaults -Name $Name)
    }

    $Fallback
}

# ---------------------------------------------------------------------------
# What the manifest says this repository should pin
# ---------------------------------------------------------------------------

function Resolve-XmipLevel {
    param(
        [Parameter(Mandatory)] [string] $RepositoryRoot,
        [Parameter(Mandatory)] [string] $Requested,
        [Parameter(Mandatory)] $Manifest,
        [Parameter(Mandatory)] [string] $ProviderName
    )

    if ($Requested -ne 'auto') {
        return [pscustomobject]@{ Level = $Requested; Module = $null }
    }

    $name = Split-Path -Leaf $RepositoryRoot

    # xmip-<provider>-<module> is a module repository and pins its standards.
    $pattern = "^xmip-$([regex]::Escape($ProviderName))-([a-z][a-z0-9-]*)$"
    $found = [regex]::Match($name, $pattern)

    if ($found.Success) {
        $provider = Get-XmipValue -Node (Get-XmipValue -Node $Manifest -Name 'provider') -Name $ProviderName
        $modules = Get-XmipValue -Node $provider -Name 'module'

        if (Test-XmipKey -Node $modules -Name $found.Groups[1].Value) {
            return [pscustomobject]@{ Level = 'implementation'; Module = $found.Groups[1].Value }
        }
    }

    # Anything else holding the manifest is the root and pins the modules.
    [pscustomobject]@{ Level = 'module'; Module = $null }
}

function Get-XmipDesired {
    param(
        [Parameter(Mandatory)] $Manifest,
        [Parameter(Mandatory)] [string] $ProviderName,
        [Parameter(Mandatory)] [string] $LevelName,
        [string] $ModuleName,
        [Parameter(Mandatory)] [string] $Root,
        [Parameter(Mandatory)] [string] $Owner,
        [Parameter(Mandatory)] [string] $UrlProtocol
    )

    $providers = Get-XmipValue -Node $Manifest -Name 'provider'
    if (-not (Test-XmipKey -Node $providers -Name $ProviderName)) {
        throw "The manifest has no provider '$ProviderName'."
    }

    $modules = Get-XmipValue -Node (Get-XmipValue -Node $providers -Name $ProviderName) -Name 'module'
    $defaultMaturity = Get-XmipSetting -Manifest $Manifest -Name 'maturity' -Fallback 'reserved'

    $entries = switch ($LevelName) {
        'module' {
            foreach ($key in ((Get-XmipKey -Node $modules) | Sort-Object)) {
                [pscustomobject]@{
                    Key        = $key
                    Repository = "xmip-$ProviderName-$key"
                    Node       = (Get-XmipValue -Node $modules -Name $key)
                }
            }
        }
        'implementation' {
            if (-not $ModuleName) { throw 'Level implementation needs -Module or a module repository to stand in.' }
            if (-not (Test-XmipKey -Node $modules -Name $ModuleName)) {
                throw "The manifest has no module '$ModuleName' under provider '$ProviderName'."
            }

            $node = Get-XmipValue -Node $modules -Name $ModuleName
            $implementations = Get-XmipValue -Node $node -Name 'implementation'

            foreach ($key in ((Get-XmipKey -Node $implementations) | Sort-Object)) {
                [pscustomobject]@{
                    Key        = $key
                    Repository = "xmip-$ProviderName-$ModuleName-$key"
                    Node       = (Get-XmipValue -Node $implementations -Name $key)
                }
            }
        }
    }

    foreach ($entry in $entries) {
        $maturity = $defaultMaturity
        if (Test-XmipKey -Node $entry.Node -Name 'maturity') {
            $maturity = Get-XmipValue -Node $entry.Node -Name 'maturity'
        }

        $url = if ($UrlProtocol -eq 'ssh') {
            "git@github.com:$Owner/$($entry.Repository).git"
        }
        else {
            "https://github.com/$Owner/$($entry.Repository).git"
        }

        [pscustomobject]@{
            Name       = $entry.Repository
            Key        = $entry.Key
            Path       = "$Root/$($entry.Key)"
            Url        = $url
            Maturity   = $maturity
        }
    }
}

# ---------------------------------------------------------------------------
# What this repository pins today
# ---------------------------------------------------------------------------

function Get-XmipCurrent {
    param([Parameter(Mandatory)] [string] $RepositoryRoot)

    $file = Join-Path $RepositoryRoot '.gitmodules'
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return @() }

    $listing = Invoke-XmipGit -WorkingDirectory $RepositoryRoot `
        -Argument 'config', '--file', '.gitmodules', '--list' -AllowFailure

    if ($listing.Failed) { return @() }

    $byName = @{}
    foreach ($line in $listing.Output) {
        if ($line -match '^submodule\.(?<name>.+?)\.(?<key>path|url|branch)=(?<value>.*)$') {
            $name = $Matches.name
            if (-not $byName.ContainsKey($name)) { $byName[$name] = @{} }
            $byName[$name][$Matches.key] = $Matches.value
        }
    }

    foreach ($name in ($byName.Keys | Sort-Object)) {
        [pscustomobject]@{
            Name   = $name
            Path   = $byName[$name]['path']
            Url    = if ($byName[$name].ContainsKey('url')) { $byName[$name]['url'] } else { $null }
            Branch = if ($byName[$name].ContainsKey('branch')) { $byName[$name]['branch'] } else { $null }
        }
    }
}

function Test-XmipRemote {
    param([Parameter(Mandatory)] [string] $Url, [Parameter(Mandatory)] [string] $WorkingDirectory)

    $probe = Invoke-XmipGit -WorkingDirectory $WorkingDirectory `
        -Argument 'ls-remote', '--exit-code', '--heads', $Url, 'main' -AllowFailure

    -not $probe.Failed
}

function Test-XmipSubmoduleClean {
    param([Parameter(Mandatory)] [string] $RepositoryRoot, [Parameter(Mandatory)] [string] $Path)

    $full = Join-Path $RepositoryRoot $Path
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { return $true }

    $status = Invoke-XmipGit -WorkingDirectory $full -Argument 'status', '--porcelain' -AllowFailure
    if ($status.Failed) { return $true }

    -not ($status.Output | Where-Object { $_ -and $_.Trim() })
}

# ---------------------------------------------------------------------------
# Reconcile
# ---------------------------------------------------------------------------

Assert-XmipEnvironment

$repositoryRoot = Assert-XmipWorkingTree -Path $RepositoryPath
$manifestFile = Resolve-XmipManifest -Explicit $ManifestPath -RepositoryRoot $repositoryRoot
$manifest = Read-XmipManifest -Path $manifestFile

$owner = Get-XmipValue -Node $manifest -Name 'owner'
$root = Get-XmipSetting -Manifest $manifest -Name 'submoduleRoot' -Fallback 'modules'
$resolved = Resolve-XmipLevel -RepositoryRoot $repositoryRoot -Requested $Level -Manifest $manifest -ProviderName $Provider

$desired = @(Get-XmipDesired -Manifest $manifest -ProviderName $Provider `
        -LevelName $resolved.Level -ModuleName $resolved.Module `
        -Root $root -Owner $owner -UrlProtocol $Protocol)

$current = @(Get-XmipCurrent -RepositoryRoot $repositoryRoot)

# The submodule root has to be empty of ordinary files. A submodule is a
# mount point, and you cannot mount onto something already standing there.
$tracked = Invoke-XmipGit -WorkingDirectory $repositoryRoot `
    -Argument 'ls-files', '--', $root -AllowFailure

$squatting = @($tracked.Output | Where-Object { $_ -and ($current.Path -notcontains $_) })

if ($squatting.Count) {
    Write-Warning "$root/ holds $($squatting.Count) tracked file(s) that are not submodules. Nothing can be mounted over them."
    $squatting | Select-Object -First 10 | ForEach-Object { Write-Warning "  $_" }
    if ($squatting.Count -gt 10) { Write-Warning "  ... and $($squatting.Count - 10) more" }
    Write-Warning "Clear it first:  git rm -r $root"
    Write-Host ''
}

Write-Host ''
Write-Host "Repository  $repositoryRoot"
Write-Host "Manifest    $manifestFile  (architecture $(Get-XmipValue -Node $manifest -Name 'architectureVersion'))"
Write-Host "Level       $($resolved.Level)$(if ($resolved.Module) { " of $($resolved.Module)" })"
Write-Host "Manifest says $($desired.Count), .gitmodules holds $($current.Count)."
Write-Host ''

$added = 0
$absent = [System.Collections.Generic.List[string]]::new()
$moved = 0
$removed = 0

foreach ($want in $desired) {
    $have = $current | Where-Object { $_.Name -eq $want.Name -or $_.Path -eq $want.Path } | Select-Object -First 1

    if ($have) {
        if ($have.Path -ne $want.Path) {
            if ($PSCmdlet.ShouldProcess("$($want.Name): $($have.Path) -> $($want.Path)", 'Move submodule')) {
                Invoke-XmipGit -WorkingDirectory $repositoryRoot -Argument 'mv', $have.Path, $want.Path | Out-Null
                Write-Host "  moved    $($want.Name)  $($have.Path) -> $($want.Path)"
            }
            $moved++
        }
        else {
            Write-Verbose "  present  $($want.Name)"
        }
        continue
    }

    if (-not (Test-XmipRemote -Url $want.Url -WorkingDirectory $repositoryRoot)) {
        $absent.Add("$($want.Name)  [maturity $($want.Maturity)]")
        continue
    }

    if ($PSCmdlet.ShouldProcess("$($want.Name) at $($want.Path)", 'Add submodule')) {
        Invoke-XmipGit -WorkingDirectory $repositoryRoot `
            -Argument 'submodule', 'add', '-b', 'main', '--name', $want.Name, $want.Url, $want.Path | Out-Null
        Write-Host "  added    $($want.Name)  ->  $($want.Path)"
    }
    else {
        Write-Host "  would add  $($want.Name)  ->  $($want.Path)"
    }
    $added++
}

$stale = $current | Where-Object { $n = $_.Name; $p = $_.Path; -not ($desired | Where-Object { $_.Name -eq $n -or $_.Path -eq $p }) }

foreach ($extra in $stale) {
    if (-not $Remove) {
        Write-Warning "The manifest does not name '$($extra.Name)' at $($extra.Path). Re-run with -Remove to drop it."
        continue
    }

    if (-not (Test-XmipSubmoduleClean -RepositoryRoot $repositoryRoot -Path $extra.Path)) {
        Write-Warning "Refusing to remove '$($extra.Name)': it has uncommitted work. Commit or discard it first."
        continue
    }

    if ($PSCmdlet.ShouldProcess("$($extra.Name) at $($extra.Path)", 'Remove submodule')) {
        Invoke-XmipGit -WorkingDirectory $repositoryRoot -Argument 'submodule', 'deinit', '-f', '--', $extra.Path -AllowFailure | Out-Null
        Invoke-XmipGit -WorkingDirectory $repositoryRoot -Argument 'rm', '-f', '--', $extra.Path -AllowFailure | Out-Null
        $gitDir = Join-Path $repositoryRoot ".git/modules/$($extra.Name)"
        if (Test-Path -LiteralPath $gitDir) { Remove-Item -LiteralPath $gitDir -Recurse -Force }
        Write-Host "  removed  $($extra.Name)"
    }
    else {
        Write-Host "  would remove  $($extra.Name)  at  $($extra.Path)"
    }
    $removed++
}

if ($Update -and -not $WhatIfPreference) {
    if ($PSCmdlet.ShouldProcess($repositoryRoot, 'Fetch each submodule''s tracked branch')) {
        Invoke-XmipGit -WorkingDirectory $repositoryRoot -Argument 'submodule', 'update', '--init', '--remote' | Out-Null
        Write-Host '  updated  every submodule to the tip of its tracked branch'
    }
}

Write-Host ''
Write-Host "added $added, moved $moved, removed $removed, absent $($absent.Count)"

if ($absent.Count) {
    Write-Host ''
    Write-Host 'No repository yet, so nothing to pin:'
    $absent | ForEach-Object { Write-Host "  $_" }
    Write-Host ''
    Write-Host 'Create them with Set-XmipArchitecture.ps1 -CreateRepositories, then run this again.'

    if ($Strict) {
        throw "$($absent.Count) module(s) named by the manifest have no repository."
    }
}

if (-not $WhatIfPreference -and ($added -or $moved -or $removed)) {
    Write-Host ''
    Write-Host '.gitmodules and the index have changed. Review, then:'
    Write-Host '  git add .gitmodules ' -NoNewline
    Write-Host "$root"
    Write-Host '  git commit -m "submodules: wire the tree from architecture.toml"'
}
