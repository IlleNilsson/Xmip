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

function Get-XmipRepositoryName {
    <#
        The names of the declared repositories, sorted. The manifest is one
        flat list: Expand-XmipEstate has already walked the tree. Role is what
        separates a module from one of its technology implementations, and
        -ModulesOnly stops at the modules, because the implementations are
        mostly declared and not yet created and cloning them is a long walk
        for a lot of ABSENT.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        $Manifest,

        [Parameter(Mandatory = $false)]
        [switch] $ModulesOnly
    )

    $repositories = @(Get-XmipPropertyValue -Object $Manifest -Name 'repositories' -Default @())

    if ($ModulesOnly) {
        $repositories = @($repositories | Where-Object {
                [string] $role = [string](
                    Get-XmipPropertyValue -Object $_ -Name 'repositoryRole'
                )
                $role -ne 'technology-implementation'
            })
    }

    @($repositories |
            ForEach-Object { [string](Get-XmipPropertyValue -Object $_ -Name 'name') } |
            Where-Object { $_ } |
            Sort-Object -Unique)
}

function Invoke-XmipDistribution {
    <#
        Executes doc/planning/allocation.toml: every [[move]], and every
        [[decision]] that carries a destination, from the source working tree
        into the repository that owns the file. Sync-XmipRepository
        -Distribute.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Allocation,

        [Parameter(Mandatory = $true)]
        [string] $Source,

        [Parameter(Mandatory = $true)]
        [string] $Destination
    )

    if (-not (Test-Path -LiteralPath $Allocation -PathType Leaf)) {
        throw "Allocation map not found: $Allocation"
    }
    $map = Read-XmipToml -Path $Allocation

    # A move entry and a decision entry that carries a destination are the
    # same instruction wearing two names. Read both or the eleven answered
    # questions do nothing.
    # Get-TomlValue, not Get-XmipPropertyValue. Read-XmipToml returns an
    # IDictionary, whose keys are not PSObject properties, so
    # Get-XmipPropertyValue returned @() for both sections. Distribute planned
    # nothing and reported "completed" — the same defect that made
    # -IncludeOptional permanently false.
    $planned = [Collections.Generic.List[object]]::new()
    foreach ($entry in @(Get-TomlValue -Node $map -Name 'move' -Default @())) {
        $planned.Add([pscustomobject]@{
                From = [string](Get-TomlValue -Node $entry -Name 'from')
                To = [string](Get-TomlValue -Node $entry -Name 'to')
                Path = [string](Get-TomlValue -Node $entry -Name 'path')
                Source = 'move'
            })
    }
    foreach ($entry in @(Get-TomlValue -Node $map -Name 'decision' -Default @())) {
        $to = [string](Get-TomlValue -Node $entry -Name 'to')
        if (-not $to) { continue }
        $planned.Add([pscustomobject]@{
                From = [string](Get-TomlValue -Node $entry -Name 'path')
                To = $to
                Path = [string](Get-TomlValue -Node $entry -Name 'newPath')
                Source = "decision $([string](Get-TomlValue -Node $entry -Name 'question'))"
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
    # repository, so a repository name resolves to its mount under module/
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
            Invoke-XmipGit -At $repository -Arguments @('add', '--', $item.Path) | Out-Null
            # --force because git rm refuses a locally modified file, and
            # the copy into the target is already made by this point.
            [string[]] $remove = @('rm', '--quiet', '--force', '--', $item.From)
            Invoke-XmipGit -At $Source -Arguments $remove | Out-Null
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
            Invoke-XmipGit -At $at -Arguments @('commit', '--quiet', '-m',
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
