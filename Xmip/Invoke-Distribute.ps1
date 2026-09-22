#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    Git, run once per repository: what each is, where it stands, and handing
    a change to all of them.

.DESCRIPTION
    Nested inside Sync-XmipRepository until 2026-09-22, when that function was
    561 lines and its file 597 against the 400 the estate allows. None of these
    read anything from it, so lifting changed nothing but where they live.

    Style: doc/governance/powershell-style.md
#>

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
    [string[]] $headRef = @('symbolic-ref', '--quiet', '--short', 'HEAD')
    [string] $branch = Get-GitLine -At $At -Arguments $headRef
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
            Where-Object {
                Test-Path -LiteralPath (Join-Path $Source $_.From) -PathType Container
            } |
            ForEach-Object { $_.From }
    )

    if (0 -lt $directories.Count) {
        [string] $detail = $directories -join ', '
        throw "Distribute moves files, not directories. Name the file: $detail"
    }

    $results = [Collections.Generic.List[object]]::new()
    $touched = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    # A composed estate keeps its working copies as submodules inside this
    # repository, so a repository name resolves to module/<domain>/<leaf>
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
        elseif (-not (Test-Path -LiteralPath $repository -PathType Container)) {
            $outcome = 'repository-absent'
        }
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
            [string[]] $remove = @('rm', '--quiet', '--force', '--', $item.From)
            Invoke-Git -At $Source -Arguments $remove | Out-Null
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
    Write-Host ('Nothing was pushed. Review each repository, ' +
        'then Sync-XmipRepository -Push <branch>.')
    Write-Host 'Xmip itself is left with the removals staged and uncommitted, on purpose:'
    Write-Host 'the source repository is the one worth reading before it changes.'
    return $results
}
