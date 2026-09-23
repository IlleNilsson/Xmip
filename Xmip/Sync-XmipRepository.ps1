#requires -PSEdition Core
#requires -Version 7.6.5

# Resolved per call rather than at load: the repository is found by looking
# for architecture.toml, and the module may be loaded from outside it.

<#
    .SYNOPSIS
    Whether a file is untouched scaffolding from the repository template.

    .DESCRIPTION
    The template's src/lib.rs says, in as many words, to replace it once the
    repository's responsibility is accepted. A file saying that is not content
    and must not stop a distribution.

    Deliberately narrow. It matches the template's own sentence rather than
    guessing from length or emptiness, so a real file can never be mistaken for
    a stub and overwritten.
#>
function Test-XmipTemplateStub {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }

    [string] $text = Get-Content -LiteralPath $Path -Raw

    return $text -match 'Replace this template documentation'
}

function Sync-XmipRepository {
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

        # Executes doc/planning/allocation.toml: puts every document and every
        # source file in the repository that owns it. Local only. It stages and
        # commits in each working copy and pushes nothing, so the whole estate
        # can be read before any of it leaves the machine.
        [Parameter(Mandatory, ParameterSetName = 'Distribute')]
        [switch] $Distribute,

        [Parameter(ParameterSetName = 'Distribute')]
        [string] $AllocationPath = (
            Join-Path (Get-XmipRepositoryRoot) 'doc/planning/allocation.toml'
        ),

        [Parameter(ParameterSetName = 'Distribute')]
        [string] $SourcePath = ((Get-XmipRepositoryRoot)),

        [string] $ManifestPath = (Join-Path (Get-XmipRepositoryRoot) 'architecture.toml'),
        # Beside the script's repository, not inside it. The natural place to run
        # this from is the repository that holds it, and cloning thirty siblings
        # into your own working tree is not what anyone means by -Clone.
        [string] $DestinationPath = (
            Join-Path (Split-Path -Parent (Get-XmipRepositoryRoot)) 'xmip-repositories'
        ),

        [ValidateSet('Https', 'Ssh')]
        [string] $Transport = 'Https',

        [switch] $ModulesOnly,

        [switch] $PassThru
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    # Get-PropertyValue is the module's, from Xmip.psm1 — this script is dot-sourced
    # into that scope, so the local copy that used to shadow it was pure redundancy
    # (removed 2026-09-06).

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "Required command 'git' was not found."
    }

    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "Manifest not found: $ManifestPath"
    }

    if ($PSCmdlet.ParameterSetName -eq 'Distribute') {
        [hashtable] $distribution = @{
            Allocation  = $AllocationPath
            Source      = $SourcePath
            Destination = [IO.Path]::GetFullPath($DestinationPath)
        }

        $distributed = Invoke-Distribute @distribution
        if ($PassThru) { $distributed }
        return
    }

    $manifest = Get-XmipManifest $ManifestPath
    $owner = [string](Get-PropertyValue $manifest 'owner')
    if (-not $owner) { throw 'Manifest owner is missing.' }

    $repositoryNames = @(Get-RepositoryNames -Manifest $manifest -ModulesOnly:$ModulesOnly)
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
    elseif ($operation -ne 'Clone' -and
        -not (Test-Path -LiteralPath $resolvedDestination -PathType Container)) {
        throw "Destination directory does not exist: $resolvedDestination"
    }

    $results = [Collections.Generic.List[object]]::new()

    foreach ($repositoryName in $repositoryNames) {
        $repositoryPath = Join-Path $resolvedDestination $repositoryName
        [string] $gitDirectory = Join-Path $repositoryPath '.git'
        [string] $cloneUrl = "https://github.com/$owner/$repositoryName.git"

        if ($Transport -eq 'Ssh') {
            $cloneUrl = "git@github.com:$owner/$repositoryName.git"
        }

        $statusValue = $null
        $branches = @()
        $branchName = $null
        $repositoryStatus = $null

        if ($operation -eq 'Clone') {
            if (Test-Path -LiteralPath $repositoryPath) {
                [string] $gitDirectory = Join-Path $repositoryPath '.git'

                if (-not (Test-Path -LiteralPath $gitDirectory -PathType Container)) {
                    throw "Destination path exists but is not a Git repository: $repositoryPath"
                }

                Write-Host "EXISTS: $repositoryName"
                $statusValue = 'existing'
            }
            elseif ($PSCmdlet.ShouldProcess($repositoryPath, "Clone $cloneUrl")) {
                try {
                    Invoke-XmipGit -Arguments @('clone', $cloneUrl, $repositoryPath) | Out-Host
                    Write-Host "CLONED: $repositoryName"
                    $statusValue = 'cloned'
                }
                catch {
                    # A declared repository that has not been created yet is the
                    # normal state of this manifest, not a failure. Most of what
                    # is declared carries maturity "reserved", so one absent
                    # repository must not stop the rest of the clone.
                    if (Test-Path -LiteralPath $repositoryPath) {
                        [hashtable] $partial = @{
                            LiteralPath = $repositoryPath
                            Recurse     = $true
                            Force       = $true
                            ErrorAction = 'SilentlyContinue'
                        }

                        Remove-Item @partial
                    }
                    Write-Warning "ABSENT: $repositoryName"
                    $statusValue = 'absent'
                }
            }
            else { $statusValue = 'skipped' }
        }
        elseif (-not (Test-Path -LiteralPath $repositoryPath)) {
            Write-Warning "MISSING: $repositoryName"
            $statusValue = 'missing'
        }
        elseif (-not (Test-Path -LiteralPath $gitDirectory -PathType Container)) {
            throw "Destination path exists but is not a Git repository: $repositoryPath"
        }
        elseif ($operation -eq 'Status') {
            $repositoryStatus = Get-RepositoryStatus -At $repositoryPath
            $branchName = $repositoryStatus.branch
            # No type constraint on $statusValue: it is reset to $null at the
            # top of each iteration, and constraining it to [string] would turn
            # that reset into '' for every later repository.
            $statusValue = 'dirty'
            [string] $position = 'no upstream'
            [string] $head = $branchName

            if ($repositoryStatus.clean) {
                $statusValue = 'clean'
            }

            if ($repositoryStatus.hasUpstream) {
                $position = 'ahead {0}, behind {1}' -f
                    $repositoryStatus.ahead, $repositoryStatus.behind
            }

            if ($repositoryStatus.detached) {
                $head = "detached $branchName"
            }

            [string] $counts = 'changed {0}; untracked {1}' -f
                $repositoryStatus.changed, $repositoryStatus.untracked

            Write-Host "STATUS: $repositoryName [$head] $statusValue; $position; $counts"
        }
        elseif ($operation -eq 'Pull') {
            if ($PSCmdlet.ShouldProcess($repositoryPath, 'Fetch, prune and fast-forward')) {
                [string[]] $fetch = @('fetch', '--all', '--prune')
                Invoke-XmipGit -At $repositoryPath -Arguments $fetch | Out-Host
                try {
                    Invoke-XmipGit -At $repositoryPath -Arguments @('pull', '--ff-only') | Out-Host
                    Write-Host "PULLED: $repositoryName"
                    $statusValue = 'pulled'
                }
                catch {
                    # A fast-forward that will not fast-forward is a fact about
                    # one repository, not a reason to stop visiting the rest.
                    Write-Warning "PULL FAILED: $repositoryName"
                    $statusValue = 'failed'
                }
            }
            else { $statusValue = 'skipped' }
        }
        elseif ($operation -eq 'Branch') {
            [string[]] $listBranches = @('branch', '--all', '--no-color')
            $branches = @(Invoke-XmipGit -At $repositoryPath -Arguments $listBranches)
            Write-Host "BRANCHES: $repositoryName"
            $branches | ForEach-Object { Write-Host "  $_" }
            $statusValue = 'listed'
        }
        elseif ($operation -eq 'BranchCreate') {
            $branchName = $Create
            [string[]] $verifyCreate = @('show-ref', '--verify', '--quiet', "refs/heads/$Create")

            if (Invoke-XmipGit -At $repositoryPath -Arguments $verifyCreate -Test) {
                Write-Host "BRANCH EXISTS: $repositoryName/$Create"
                $statusValue = 'branch-existing'
            }
            elseif ($PSCmdlet.ShouldProcess($repositoryPath,
                    "Create local branch '$Create' at HEAD")) {
                Invoke-XmipGit -At $repositoryPath -Arguments @('branch', $Create) | Out-Host
                Write-Host "BRANCH CREATED: $repositoryName/$Create"
                $statusValue = 'branch-created'
            }
            else { $statusValue = 'skipped' }
        }
        else {
            $branchName = $Push
            [string[]] $verifyPush = @('show-ref', '--verify', '--quiet', "refs/heads/$Push")

            if (-not (Invoke-XmipGit -At $repositoryPath -Arguments $verifyPush -Test)) {
                Write-Warning "BRANCH MISSING: $repositoryName/$Push"
                $statusValue = 'branch-missing'
            }
            elseif ($PSCmdlet.ShouldProcess($repositoryPath, "Push branch '$Push' to origin")) {
                Invoke-XmipGit -At $repositoryPath -Arguments @('push', 'origin', $Push) | Out-Host
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
        branch = switch ($operation) {
            'Push' { $Push }
            'BranchCreate' { $Create }
            default { $null }
        }
        repositoryCount = $repositoryNames.Count
        clean = @($results | Where-Object status -eq 'clean').Count
        dirty = @($results | Where-Object status -eq 'dirty').Count
        detached = @($results | Where-Object detached -eq $true).Count
        withoutUpstream = @(
            $results | Where-Object { $_.operation -eq 'status' -and $_.hasUpstream -eq $false }
        ).Count
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
        # One counter per line. A single 285-character interpolation is not a
        # summary, it is a wall that nobody reads to the end of.
        [string[]] $parts = @(
            "Total: $($summary.repositoryCount)"
            "Clean: $($summary.clean)"
            "Dirty: $($summary.dirty)"
            "Detached: $($summary.detached)"
            "Ahead: $($summary.ahead)"
            "Behind: $($summary.behind)"
            "No upstream: $($summary.withoutUpstream)"
            "Missing: $($summary.missing)"
        )
        
        Write-Host "Status completed. $($parts -join '; ')"
    }
    else {
        [string[]] $parts = @(
            "Total: $($summary.repositoryCount)"
            "Cloned: $($summary.cloned)"
            "Pulled: $($summary.pulled)"
            "Listed: $($summary.listed)"
            "Branch created: $($summary.branchCreated)"
            "Branch existing: $($summary.branchExisting)"
            "Pushed: $($summary.pushed)"
            "Existing: $($summary.existing)"
            "Missing: $($summary.missing)"
            "Branch missing: $($summary.branchMissing)"
            "Skipped: $($summary.skipped)"
        )
        
        Write-Host "$operation completed. $($parts -join '; ')"
    }

    if ($PassThru) { $summary }
}
