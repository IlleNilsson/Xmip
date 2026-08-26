#requires -PSEdition Core
#requires -Version 7.6

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

        # Executes docs/planning/allocation.toml: puts every document and every
        # source file in the repository that owns it. Local only. It stages and
        # commits in each working copy and pushes nothing, so the whole estate
        # can be read before any of it leaves the machine.
        [Parameter(Mandatory, ParameterSetName = 'Distribute')]
        [switch] $Distribute,

        [Parameter(ParameterSetName = 'Distribute')]
        [string] $AllocationPath = (Join-Path (Get-XmipRepositoryRoot) 'docs/planning/allocation.toml'),

        [Parameter(ParameterSetName = 'Distribute')]
        [string] $SourcePath = ((Get-XmipRepositoryRoot)),

        [string] $ManifestPath = (Join-Path (Get-XmipRepositoryRoot) 'architecture.toml'),
        # Beside the script's repository, not inside it. The natural place to run
        # this from is the repository that holds it, and cloning thirty siblings
        # into your own working tree is not what anyone means by -Clone.
        [string] $DestinationPath = (Join-Path (Split-Path -Parent (Get-XmipRepositoryRoot)) 'xmip-repositories'),

        [ValidateSet('Https', 'Ssh')]
        [string] $Transport = 'Https',

        [switch] $ModulesOnly,

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
                [string] $newLine = [Environment]::NewLine
                [string] $command = $Arguments -join ' '
                [string] $detail = $output -join $newLine

                throw "Git command failed: git $command$newLine$detail"
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

    function Get-GitLine {
        # Most git plumbing here answers with exactly one line, and reading the
        # first of an array at every call site is what pushed those call sites
        # past 120 characters. Returns '' when git says nothing.
        param([Parameter(Mandatory)] [string[]] $Arguments, [Parameter(Mandatory)] [string] $At)

        [string[]] $lines = @(Invoke-Git -At $At -Arguments $Arguments)

        if (0 -eq $lines.Count) {
            return ''
        }

        return [string] $lines[0]
    }

    function Get-RepositoryNames {
        param([Parameter(Mandatory)] $Manifest, [switch] $ModulesOnly)

        # The manifest is one flat list now: Expand-XmipEstate has already
        # walked the tree. Role is what separates a module from one of its
        # technology implementations, and -ModulesOnly stops at the modules,
        # because the implementations are mostly declared and not yet created
        # and cloning them is a long walk for a lot of ABSENT.
        $repositories = @(Get-PropertyValue $Manifest 'repositories' @())
        if ($ModulesOnly) {
            $repositories = @($repositories | Where-Object {
                    [string](Get-PropertyValue $_ 'repositoryRole') -ne 'technology-implementation'
                })
        }

        @($repositories |
                ForEach-Object { [string](Get-PropertyValue $_ 'name') } |
                Where-Object { $_ } |
                Sort-Object -Unique)
    }

    function Get-RepositoryStatus {
        param([Parameter(Mandatory)] [string] $At)

        $porcelain = @(Invoke-Git -At $At -Arguments @('status', '--porcelain=v1'))
        [string] $branch = Get-GitLine -At $At -Arguments @('symbolic-ref', '--quiet', '--short', 'HEAD')
        $detached = -not $branch

        if ($detached) {
            $branch = Get-GitLine -At $At -Arguments @('rev-parse', '--short', 'HEAD')
        }

        $ahead = 0
        $behind = 0

        [string[]] $upstreamRef = @(
            'rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{upstream}'
        )

        $hasUpstream = Test-GitCommand -At $At -Arguments $upstreamRef

        if ($hasUpstream) {
            [string[]] $countArguments = @(
                'rev-list', '--left-right', '--count', 'HEAD...@{upstream}'
            )

            [string] $counts = Get-GitLine -At $At -Arguments $countArguments
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

    function Invoke-Distribute {
        param(
            [Parameter(Mandatory)] [string] $Allocation,
            [Parameter(Mandatory)] [string] $Source,
            [Parameter(Mandatory)] [string] $Destination
        )

        if (-not (Test-Path -LiteralPath $Allocation -PathType Leaf)) {
            throw "Allocation map not found: $Allocation"
        }
        Import-Module PSToml -ErrorAction Stop
        $map = Get-Content -LiteralPath $Allocation -Raw -Encoding utf8 | ConvertFrom-Toml

        # A move entry and a decision entry that carries a destination are the
        # same instruction wearing two names. Read both or the eleven answered
        # questions do nothing.
        # Get-TomlValue, not Get-PropertyValue. ConvertFrom-Toml returns an
        # IDictionary, whose keys are not PSObject properties, so
        # Get-PropertyValue returned @() for both sections. Distribute planned
        # nothing and reported "completed" — the same defect that made
        # -IncludeOptional permanently false.
        $planned = [Collections.Generic.List[object]]::new()
        foreach ($entry in @(Get-TomlValue $map 'move' @())) {
            $planned.Add([pscustomobject]@{
                    From = [string](Get-TomlValue $entry 'from')
                    To = [string](Get-TomlValue $entry 'to')
                    Path = [string](Get-TomlValue $entry 'path')
                    Source = 'move'
                })
        }
        foreach ($entry in @(Get-TomlValue $map 'decision' @())) {
            $to = [string](Get-TomlValue $entry 'to')
            if (-not $to) { continue }
            $planned.Add([pscustomobject]@{
                    From = [string](Get-TomlValue $entry 'path')
                    To = $to
                    Path = [string](Get-TomlValue $entry 'newPath')
                    Source = "decision $([string](Get-TomlValue $entry 'question'))"
                })
        }

        # Validate the whole plan before performing any of it. This moves files
        # across repository boundaries and cannot be rolled back, so a bad entry
        # must stop the run at nothing done rather than at eleven done.
        [string[]] $directories = @(
            $planned |
                Where-Object { Test-Path -LiteralPath (Join-Path $Source $_.From) -PathType Container } |
                ForEach-Object { $_.From }
        )

        if (0 -lt $directories.Count) {
            [string] $detail = $directories -join ', '
            throw "Distribute moves files, not directories. Name the file: $detail"
        }

        $results = [Collections.Generic.List[object]]::new()
        $touched = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

        # A composed estate keeps its working copies as submodules inside this
        # repository, so a repository name resolves to modules/<domain>/<leaf>
        # rather than to a sibling clone. Without this, Distribute writes into
        # ../xmip-repositories and the submodule that owns the file never sees
        # it.
        [hashtable] $mountOf = Get-XmipMountedPath -Root $Source

        foreach ($item in $planned) {
            $outcome = 'moved'
            $from = Join-Path $Source $item.From
            [string] $mount = [string] $mountOf[$item.To]

            $repository = if ([string]::IsNullOrEmpty($mount)) {
                Join-Path $Destination $item.To
            }
            else {
                Join-Path $Source $mount
            }
            $target = Join-Path $repository ($item.Path ? $item.Path : (Split-Path -Leaf $item.From))

            if (-not (Test-Path -LiteralPath $from)) { $outcome = 'source-missing' }
            elseif (-not (Test-Path -LiteralPath $repository -PathType Container)) { $outcome = 'repository-absent' }
            elseif (Test-Path -LiteralPath $target) {
                # Every module carries a four-line src/lib.rs from the template,
                # so a target existing does not mean a target with content in
                # it. Refusing there made the tool careful about the wrong
                # thing: four real moves would have reported target-exists and
                # been skipped, against a placeholder that says "replace this".
                $outcome = if (Test-XmipTemplateStub -Path $target) { 'moved' } else { 'target-exists' }
            }

            [string] $move = '{0} -> {1}/{2}' -f $item.From, $item.To, $item.Path

            if ($outcome -eq 'moved' -and $PSCmdlet.ShouldProcess($move, 'Distribute')) {
                $directory = Split-Path -Parent $target
                if ($directory) { New-Item -ItemType Directory -Force -Path $directory | Out-Null }

                # A cross-repository move cannot keep history: git mv is
                # in-repository only, and rewriting 51 files through
                # filter-repo would cost more than it returns while Xmip's own
                # history still holds every one of them. Copy, add, and remove
                # from the source. The past stays findable where it happened.
                Copy-Item -LiteralPath $from -Destination $target -Force
                Invoke-Git -At $repository -Arguments @('add', '--', $item.Path) | Out-Null
                # --force because git rm refuses a locally modified file, and
                # the copy into the target is already made by this point.
                Invoke-Git -At $Source -Arguments @('rm', '--quiet', '--force', '--', $item.From) | Out-Null
                [void] $touched.Add($item.To)
            }

            $results.Add([pscustomobject]@{
                    from = $item.From; to = $item.To; path = $item.Path
                    origin = $item.Source; outcome = $outcome
                })
        }

        foreach ($repository in $touched) {
            $at = Join-Path $Destination $repository
            if ($PSCmdlet.ShouldProcess($repository, 'Commit adopted files')) {
                Invoke-Git -At $at -Arguments @('commit', '--quiet', '-m',
                    'Adopt the files this repository owns, per Xmip allocation.toml') | Out-Null
            }
        }

        $byOutcome = $results | Group-Object outcome | ForEach-Object { "$($_.Name): $($_.Count)" }
        [string] $summary = $byOutcome -join '; '

        Write-Host "Distribute completed. Planned: $($results.Count); $summary"
        Write-Host "Repositories committed: $($touched.Count)."
        Write-Host 'Nothing was pushed. Review each repository, then Sync-XmipRepository -Push <branch>.'
        Write-Host 'Xmip itself is left with the removals staged and uncommitted, on purpose:'
        Write-Host 'the source repository is the one worth reading before it changes.'
        return $results
    }

    if ($PSCmdlet.ParameterSetName -eq 'Distribute') {
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) { throw "Required command 'git' was not found." }
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
    elseif ($operation -ne 'Clone' -and -not (Test-Path -LiteralPath $resolvedDestination -PathType Container)) {
        throw "Destination directory does not exist: $resolvedDestination"
    }

    $results = [Collections.Generic.List[object]]::new()

    foreach ($repositoryName in $repositoryNames) {
        $repositoryPath = Join-Path $resolvedDestination $repositoryName
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
                    Invoke-Git -Arguments @('clone', $cloneUrl, $repositoryPath) | Out-Host
                    Write-Host "CLONED: $repositoryName"
                    $statusValue = 'cloned'
                }
                catch {
                    # A declared repository that has not been created yet is the
                    # normal state of this manifest, not a failure. Most of what
                    # is declared carries maturity "reserved", so one absent
                    # repository must not stop the rest of the clone.
                    if (Test-Path -LiteralPath $repositoryPath) {
                        Remove-Item -LiteralPath $repositoryPath -Recurse -Force -ErrorAction SilentlyContinue
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
        elseif (-not (Test-Path -LiteralPath (Join-Path $repositoryPath '.git') -PathType Container)) {
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
                $position = 'ahead {0}, behind {1}' -f $repositoryStatus.ahead, $repositoryStatus.behind
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
                Invoke-Git -At $repositoryPath -Arguments @('fetch', '--all', '--prune') | Out-Host
                try {
                    Invoke-Git -At $repositoryPath -Arguments @('pull', '--ff-only') | Out-Host
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
            $branches = @(Invoke-Git -At $repositoryPath -Arguments @('branch', '--all', '--no-color'))
            Write-Host "BRANCHES: $repositoryName"
            $branches | ForEach-Object { Write-Host "  $_" }
            $statusValue = 'listed'
        }
        elseif ($operation -eq 'BranchCreate') {
            $branchName = $Create
            [string[]] $verifyCreate = @('show-ref', '--verify', '--quiet', "refs/heads/$Create")

            if (Test-GitCommand -At $repositoryPath -Arguments $verifyCreate) {
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
            [string[]] $verifyPush = @('show-ref', '--verify', '--quiet', "refs/heads/$Push")

            if (-not (Test-GitCommand -At $repositoryPath -Arguments $verifyPush)) {
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
