#requires -PSEdition Core
#requires -Version 7.6.3

$script:XmipGitDefaultManifestPath = Join-Path $PSScriptRoot 'xmip-architecture.json'

function Xmip-Git {
    [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Clone')]
    param(
        [Parameter(ParameterSetName = 'Clone')]
        [switch] $Clone,

        [Parameter(Mandatory, ParameterSetName = 'Pull')]
        [switch] $Pull,

        [Parameter(Mandatory, ParameterSetName = 'Status')]
        [switch] $Status,

        [Parameter(Mandatory, ParameterSetName = 'Branch')]
        [Parameter(Mandatory, ParameterSetName = 'BranchCreate')]
        [switch] $Branch,

        [Parameter(Mandatory, ParameterSetName = 'BranchCreate')]
        [ValidateNotNullOrEmpty()]
        [string] $Create,

        [Parameter(Mandatory, ParameterSetName = 'Push')]
        [ValidateNotNullOrEmpty()]
        [string] $Push,

        [string] $ManifestPath = $script:XmipGitDefaultManifestPath,
        [string] $DestinationPath = (Join-Path (Get-Location) 'xmip-repositories'),

        [ValidateSet('Https', 'Ssh')]
        [string] $Transport = 'Https',

        [switch] $PassThru
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    function Get-PropertyValue {
        param([AllowNull()] $Object, [Parameter(Mandatory)] [string] $Name, $Default = $null)
        if ($null -eq $Object) { return $Default }
        $property = $Object.PSObject.Properties[$Name]
        if ($null -eq $property -or $null -eq $property.Value) { return $Default }
        $property.Value
    }

    function Invoke-Git {
        param([Parameter(Mandatory)] [string[]] $Arguments, [string] $At = '')
        $previousLocation = $PWD
        try {
            if ($At) { Set-Location -LiteralPath $At }
            $output = @(& git @Arguments 2>&1)
            if ($LASTEXITCODE -ne 0) {
                throw "Git command failed: git $($Arguments -join ' ')$([Environment]::NewLine)$($output -join [Environment]::NewLine)"
            }
            $output
        }
        finally {
            Set-Location $previousLocation
        }
    }

    function Test-GitCommand {
        param([Parameter(Mandatory)] [string[]] $Arguments, [Parameter(Mandatory)] [string] $At)
        $previousLocation = $PWD
        try {
            Set-Location -LiteralPath $At
            & git @Arguments *> $null
            $LASTEXITCODE -eq 0
        }
        finally {
            Set-Location $previousLocation
        }
    }

    function Get-RepositoryNames {
        param([Parameter(Mandatory)] $Manifest)
        $names = [Collections.Generic.List[string]]::new()
        $explicit = @(Get-PropertyValue $Manifest 'repositories' @())

        if ($explicit.Count -gt 0) {
            foreach ($repository in $explicit) {
                $name = [string](Get-PropertyValue $repository 'name')
                if ($name) { $names.Add($name) }
            }
        }
        else {
            foreach ($repository in @(Get-PropertyValue $Manifest 'commonRepositories' @())) {
                $name = if ($repository -is [System.Array]) { [string]$repository[0] } else { [string](Get-PropertyValue $repository 'name') }
                if ($name) { $names.Add($name) }
            }

            foreach ($group in @(Get-PropertyValue $Manifest 'technologyGroups' @())) {
                $parent = if ($group -is [System.Array]) { [string]$group[0] } else { [string](Get-PropertyValue $group 'parent') }
                $technologies = if ($group -is [System.Array]) { @($group[2]) } else { @(Get-PropertyValue $group 'technologies' @()) }
                foreach ($technology in $technologies) {
                    $technologyName = if ($technology -is [string]) { $technology } else { [string](Get-PropertyValue $technology 'name') }
                    if ($parent -and $technologyName) { $names.Add("$parent-$technologyName") }
                }
            }
        }

        @($names | Sort-Object -Unique)
    }

    function Get-RepositoryStatus {
        param([Parameter(Mandatory)] [string] $At)

        $porcelain = @(Invoke-Git -At $At -Arguments @('status', '--porcelain=v1'))
        $branch = [string](@(Invoke-Git -At $At -Arguments @('symbolic-ref', '--quiet', '--short', 'HEAD')) | Select-Object -First 1)
        $detached = -not $branch
        if ($detached) {
            $branch = [string](@(Invoke-Git -At $At -Arguments @('rev-parse', '--short', 'HEAD')) | Select-Object -First 1)
        }

        $ahead = 0
        $behind = 0
        $hasUpstream = Test-GitCommand -At $At -Arguments @('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{upstream}')
        if ($hasUpstream) {
            $counts = [string](@(Invoke-Git -At $At -Arguments @('rev-list', '--left-right', '--count', 'HEAD...@{upstream}')) | Select-Object -First 1)
            if ($counts -match '^(\d+)\s+(\d+)$') {
                $ahead = [int]$Matches[1]
                $behind = [int]$Matches[2]
            }
        }

        [pscustomobject]@{
            branch = $branch
            detached = $detached
            clean = $porcelain.Count -eq 0
            changed = @($porcelain | Where-Object { $_ -notmatch '^\?\?' }).Count
            untracked = @($porcelain | Where-Object { $_ -match '^\?\?' }).Count
            hasUpstream = $hasUpstream
            ahead = $ahead
            behind = $behind
        }
    }

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "Required command 'git' was not found." }
    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { throw "Manifest not found: $ManifestPath" }

    $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json -Depth 100
    $owner = [string](Get-PropertyValue $manifest 'owner')
    if (-not $owner) { throw 'Manifest owner is missing.' }

    $repositoryNames = @(Get-RepositoryNames -Manifest $manifest)
    if ($repositoryNames.Count -eq 0) { throw 'Manifest contains no repositories.' }

    $operation = switch ($PSCmdlet.ParameterSetName) {
        'Pull' { 'Pull' }
        'Status' { 'Status' }
        'Branch' { 'Branch' }
        'BranchCreate' { 'BranchCreate' }
        'Push' { 'Push' }
        default { 'Clone' }
    }

    $resolvedDestination = [IO.Path]::GetFullPath($DestinationPath)
    if ($operation -eq 'Clone' -and -not (Test-Path -LiteralPath $resolvedDestination)) {
        if ($PSCmdlet.ShouldProcess($resolvedDestination, 'Create destination directory')) {
            New-Item -ItemType Directory -Path $resolvedDestination -Force | Out-Null
        }
    }
    elseif ($operation -ne 'Clone' -and -not (Test-Path -LiteralPath $resolvedDestination -PathType Container)) {
        throw "Destination directory does not exist: $resolvedDestination"
    }

    $results = [Collections.Generic.List[object]]::new()

    foreach ($repositoryName in $repositoryNames) {
        $repositoryPath = Join-Path $resolvedDestination $repositoryName
        $cloneUrl = if ($Transport -eq 'Ssh') { "git@github.com:$owner/$repositoryName.git" } else { "https://github.com/$owner/$repositoryName.git" }
        $statusValue = $null
        $branches = @()
        $branchName = $null
        $repositoryStatus = $null

        if ($operation -eq 'Clone') {
            if (Test-Path -LiteralPath $repositoryPath) {
                if (-not (Test-Path -LiteralPath (Join-Path $repositoryPath '.git') -PathType Container)) { throw "Destination path exists but is not a Git repository: $repositoryPath" }
                Write-Host "EXISTS: $repositoryName"
                $statusValue = 'existing'
            }
            elseif ($PSCmdlet.ShouldProcess($repositoryPath, "Clone $cloneUrl")) {
                Invoke-Git -Arguments @('clone', $cloneUrl, $repositoryPath) | Out-Host
                Write-Host "CLONED: $repositoryName"
                $statusValue = 'cloned'
            }
            else { $statusValue = 'skipped' }
        }
        elseif (-not (Test-Path -LiteralPath $repositoryPath)) {
            Write-Warning "MISSING: $repositoryName"
            $statusValue = 'missing'
        }
        elseif (-not (Test-Path -LiteralPath (Join-Path $repositoryPath '.git') -PathType Container)) {
            throw "Destination path exists but is not a Git repository: $repositoryPath"
        }
        elseif ($operation -eq 'Status') {
            $repositoryStatus = Get-RepositoryStatus -At $repositoryPath
            $branchName = $repositoryStatus.branch
            $statusValue = if ($repositoryStatus.clean) { 'clean' } else { 'dirty' }
            $position = if ($repositoryStatus.hasUpstream) { "ahead $($repositoryStatus.ahead), behind $($repositoryStatus.behind)" } else { 'no upstream' }
            $head = if ($repositoryStatus.detached) { "detached $branchName" } else { $branchName }
            Write-Host "STATUS: $repositoryName [$head] $statusValue; $position; changed $($repositoryStatus.changed); untracked $($repositoryStatus.untracked)"
        }
        elseif ($operation -eq 'Pull') {
            if ($PSCmdlet.ShouldProcess($repositoryPath, 'Fetch, prune and fast-forward')) {
                Invoke-Git -At $repositoryPath -Arguments @('fetch', '--all', '--prune') | Out-Host
                Invoke-Git -At $repositoryPath -Arguments @('pull', '--ff-only') | Out-Host
                Write-Host "PULLED: $repositoryName"
                $statusValue = 'pulled'
            }
            else { $statusValue = 'skipped' }
        }
        elseif ($operation -eq 'Branch') {
            $branches = @(Invoke-Git -At $repositoryPath -Arguments @('branch', '--all', '--no-color'))
            Write-Host "BRANCHES: $repositoryName"
            $branches | ForEach-Object { Write-Host "  $_" }
            $statusValue = 'listed'
        }
        elseif ($operation -eq 'BranchCreate') {
            $branchName = $Create
            if (Test-GitCommand -At $repositoryPath -Arguments @('show-ref', '--verify', '--quiet', "refs/heads/$Create")) {
                Write-Host "BRANCH EXISTS: $repositoryName/$Create"
                $statusValue = 'branch-existing'
            }
            elseif ($PSCmdlet.ShouldProcess($repositoryPath, "Create local branch '$Create' at HEAD")) {
                Invoke-Git -At $repositoryPath -Arguments @('branch', $Create) | Out-Host
                Write-Host "BRANCH CREATED: $repositoryName/$Create"
                $statusValue = 'branch-created'
            }
            else { $statusValue = 'skipped' }
        }
        else {
            $branchName = $Push
            if (-not (Test-GitCommand -At $repositoryPath -Arguments @('show-ref', '--verify', '--quiet', "refs/heads/$Push"))) {
                Write-Warning "BRANCH MISSING: $repositoryName/$Push"
                $statusValue = 'branch-missing'
            }
            elseif ($PSCmdlet.ShouldProcess($repositoryPath, "Push branch '$Push' to origin")) {
                Invoke-Git -At $repositoryPath -Arguments @('push', 'origin', $Push) | Out-Host
                Write-Host "PUSHED: $repositoryName/$Push"
                $statusValue = 'pushed'
            }
            else { $statusValue = 'skipped' }
        }

        $results.Add([pscustomobject]@{
            repository = $repositoryName
            path = $repositoryPath
            url = $cloneUrl
            operation = $operation.ToLowerInvariant()
            branch = $branchName
            branches = $branches
            status = $statusValue
            clean = if ($repositoryStatus) { $repositoryStatus.clean } else { $null }
            detached = if ($repositoryStatus) { $repositoryStatus.detached } else { $null }
            changed = if ($repositoryStatus) { $repositoryStatus.changed } else { $null }
            untracked = if ($repositoryStatus) { $repositoryStatus.untracked } else { $null }
            hasUpstream = if ($repositoryStatus) { $repositoryStatus.hasUpstream } else { $null }
            ahead = if ($repositoryStatus) { $repositoryStatus.ahead } else { $null }
            behind = if ($repositoryStatus) { $repositoryStatus.behind } else { $null }
        })
    }

    $summary = [pscustomobject]@{
        operation = $operation.ToLowerInvariant()
        owner = $owner
        manifestPath = [IO.Path]::GetFullPath($ManifestPath)
        destinationPath = $resolvedDestination
        transport = $Transport
        branch = if ($operation -eq 'Push') { $Push } elseif ($operation -eq 'BranchCreate') { $Create } else { $null }
        repositoryCount = $repositoryNames.Count
        clean = @($results | Where-Object status -eq 'clean').Count
        dirty = @($results | Where-Object status -eq 'dirty').Count
        detached = @($results | Where-Object detached -eq $true).Count
        withoutUpstream = @($results | Where-Object { $_.operation -eq 'status' -and $_.hasUpstream -eq $false }).Count
        ahead = @($results | Where-Object { $_.operation -eq 'status' -and $_.ahead -gt 0 }).Count
        behind = @($results | Where-Object { $_.operation -eq 'status' -and $_.behind -gt 0 }).Count
        cloned = @($results | Where-Object status -eq 'cloned').Count
        pulled = @($results | Where-Object status -eq 'pulled').Count
        listed = @($results | Where-Object status -eq 'listed').Count
        branchCreated = @($results | Where-Object status -eq 'branch-created').Count
        branchExisting = @($results | Where-Object status -eq 'branch-existing').Count
        pushed = @($results | Where-Object status -eq 'pushed').Count
        existing = @($results | Where-Object status -eq 'existing').Count
        missing = @($results | Where-Object status -eq 'missing').Count
        branchMissing = @($results | Where-Object status -eq 'branch-missing').Count
        skipped = @($results | Where-Object status -eq 'skipped').Count
        repositories = @($results)
    }

    if ($operation -eq 'Status') {
        Write-Host "Status completed. Total: $($summary.repositoryCount); Clean: $($summary.clean); Dirty: $($summary.dirty); Detached: $($summary.detached); Ahead: $($summary.ahead); Behind: $($summary.behind); No upstream: $($summary.withoutUpstream); Missing: $($summary.missing)."
    }
    else {
        Write-Host "$operation completed. Total: $($summary.repositoryCount); Cloned: $($summary.cloned); Pulled: $($summary.pulled); Listed: $($summary.listed); Branch created: $($summary.branchCreated); Branch existing: $($summary.branchExisting); Pushed: $($summary.pushed); Existing: $($summary.existing); Missing: $($summary.missing); Branch missing: $($summary.branchMissing); Skipped: $($summary.skipped)."
    }

    if ($PassThru) { $summary }
}
