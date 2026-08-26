#requires -PSEdition Core
#requires -Version 7.6

<#
    docs/planning/allocation.toml is the plan for moving every document and
    source file into the repository that owns it. Sync-XmipRepository -Distribute
    executes it.

    It rotted without anyone noticing. Twenty-seven [[move]] entries survived
    the ADR-0020 consolidation: eleven named files that had been deleted, and
    sixteen named files whose content had been folded into the six architecture
    documents. Running it would have scattered sixteen superseded documents
    across sixteen repositories, turning one consolidation into forty-three.

    A hand-maintained [count] block claimed none of that could happen. These
    tests are what that block should have been.
#>

# A ratchet, not a target. docs/architecture holds thirty-one files against
# ADR-0020's six; asserting six today would fail on day one, and a test that is
# always red is a test nobody reads. Lower this as allocation.toml section 3b
# is worked through — it may fall and may not rise, so the consolidation cannot
# go backwards while nobody is looking.
#
# At file scope rather than in BeforeAll: Pester discovers test names before it
# runs BeforeAll, and a name interpolating a BeforeAll variable reads as
# 'no more than  files'.
[int] $script:ExtraCeiling = 1

BeforeAll {
    $script:Root = Join-Path $PSScriptRoot '..'
    $script:AllocationPath = Join-Path $script:Root 'docs/planning/allocation.toml'
    [int] $script:ExtraCeiling = 1

    Import-Module PSToml -ErrorAction Stop
    Import-Module (Join-Path $script:Root 'Xmip/Xmip.psd1') -Force

    [string] $text = Get-Content -LiteralPath $script:AllocationPath -Raw -Encoding utf8
    $script:Allocation = ConvertFrom-Toml -InputObject $text

    <#
        .SYNOPSIS
        The entries of one allocation section, always as an array.

        .DESCRIPTION
        ConvertFrom-Toml returns an IDictionary, so a missing section is absent
        rather than empty and PSObject.Properties does not enumerate its keys.
        Both of those have already cost a defect apiece in this repository.
    #>
    function Get-AllocationEntry {
        [CmdletBinding()]
        [OutputType([object])]
        param(
            [Parameter(Mandatory = $true)]
            [string] $Section
        )

        if (-not $script:Allocation.Contains($Section)) {
            return @()
        }

        return @($script:Allocation[$Section])
    }

    <#
        .SYNOPSIS
        A path as written in the map, resolved against the repository root.

        .DESCRIPTION
        Returns $null for entries that are not single real paths: comma-joined
        lists and wildcards are both used deliberately in this file and neither
        is a thing Test-Path should be asked about.
    #>
    function Resolve-AllocationPath {
        [CmdletBinding()]
        [OutputType([string])]
        param(
            [Parameter(Mandatory = $true)]
            [AllowEmptyString()]
            [string] $Path
        )

        if ([string]::IsNullOrWhiteSpace($Path)) {
            return $null
        }

        if ($Path.Contains(',') -or $Path.Contains('*')) {
            return $null
        }

        return Join-Path $script:Root $Path
    }
}

Describe 'Every executable entry names a file that exists' {
    It 'has no [[move]] whose source is missing' {
        # The failure this catches by name: eleven entries pointing at
        # Xmip-Audit-Architecture.md, module-loading.md, database-selection.md
        # and eight more, all deleted during consolidation.
        [string[]] $missing = @()

        foreach ($entry in (Get-AllocationEntry -Section 'move')) {
            [string] $resolved = Resolve-AllocationPath -Path ([string] $entry.from)

            if ($null -eq $resolved) {
                continue
            }

            if (-not (Test-Path -LiteralPath $resolved)) {
                $missing += [string] $entry.from
            }
        }

        [string] $detail = $missing -join "`n"

        $missing.Count | Should -Be 0 -Because "these move sources do not exist:`n$detail"
    }

    It 'supersedes nothing with a document that does not exist' {
        <#
            The first version of this test asserted the opposite — that a
            superseded file must still be on disk — and failed on thirty-two
            entries whose files had already been deleted. That is the list
            working, not failing: an entry exists so that someone removes the
            file, and thirty-two of them did.

            This is the invariant that actually holds. A replacement must exist,
            because 'X is superseded by Y' is a promise that Y is somewhere to
            be read. Paths are relative to the repository root; a replacedBy
            that names a repository rather than a file is skipped.
        #>
        # replacedBy is prose, not a path: 'runtime-model.md and
        # repository-model.md' is a legitimate value, and reading the whole
        # string as one filename reported two false failures on the first run.
        # Pull out every document it names and require each of them.
        [regex] $document = [regex]::new('[\w./-]+\.(?:md|toml)')

        [string[]] $broken = @()

        foreach ($entry in (Get-AllocationEntry -Section 'superseded')) {
            [string] $replacement = [string] $entry.replacedBy

            foreach ($named in $document.Matches($replacement)) {
                [string] $resolved = Resolve-AllocationPath -Path $named.Value

                if ($null -eq $resolved) {
                    continue
                }

                if (-not (Test-Path -LiteralPath $resolved)) {
                    $broken += "$($entry.path) -> $($named.Value)"
                }
            }
        }

        [string] $detail = $broken -join "`n"

        $broken.Count | Should -Be 0 -Because "replaced by something absent:`n$detail"
    }
}

Describe 'Every destination is a real repository' {
    It 'moves only to repositories architecture.toml declares' {
        $manifest = Get-XmipManifest -Path (Join-Path $script:Root 'architecture.toml')
        [string[]] $declared = @($manifest.repositories | ForEach-Object { [string] $_.name })

        foreach ($entry in (Get-AllocationEntry -Section 'move')) {
            [string] $destination = [string] $entry.to

            if ([string]::IsNullOrWhiteSpace($destination)) {
                continue
            }

            [string] $because = "allocation.toml moves a file to $destination"

            $declared | Should -Contain $destination -Because $because
        }
    }
}

Describe 'No file is claimed twice' {
    It 'names no path in more than one section' {
        # A file that is both moved and superseded is a file whose fate depends
        # on which section the reader happened to open.
        [hashtable] $seen = @{}
        [string[]] $collisions = @()

        [hashtable] $sections = @{
            move        = 'from'
            superseded  = 'path'
            remove      = 'path'
            consolidate = 'paths'
        }

        foreach ($section in $sections.Keys) {
            foreach ($entry in (Get-AllocationEntry -Section $section)) {
                [string[]] $paths = @($entry.($sections[$section]))

                foreach ($path in $paths) {
                    if ([string]::IsNullOrWhiteSpace($path) -or $path.Contains('*')) {
                        continue
                    }

                    if ($seen.ContainsKey($path)) {
                        $collisions += "$path is in both $($seen[$path]) and $section"
                        continue
                    }

                    $seen[$path] = $section
                }
            }
        }

        [string] $detail = $collisions -join "`n"

        $collisions.Count | Should -Be 0 -Because "claimed twice:`n$detail"
    }
}

Describe 'ADR-0020: six architecture documents' {
    It "holds no more than $script:ExtraCeiling files beyond the six" {
        [string] $architecture = Join-Path $script:Root 'docs/architecture'

        [string[]] $allowed = @(
            'runtime-model.md'
            'repository-model.md'
            'module-model.md'
            'deployment-model.md'
            'observability-model.md'
            'identity-by-technology.md'
        )

        [string[]] $actual = @(
            Get-ChildItem -Path $architecture -File -Filter '*.md' |
                ForEach-Object { $_.Name }
        )

        [string[]] $extra = @($actual | Where-Object { $_ -notin $allowed })

        Write-Host "  docs/architecture holds $($extra.Count) files beyond the six"

        [string] $detail = ($extra | Sort-Object) -join "`n"
        [string] $because = "waiting on allocation.toml section 3b:`n$detail"

        $extra.Count | Should -BeLessOrEqual $script:ExtraCeiling -Because $because
    }

    It 'keeps the five documents that stay in Xmip' {
        # The other direction, and the one that matters more: consolidation
        # must not lose a target document while removing its sources.
        #
        # Five, not six. identity-by-technology.md is the sixth and it moves to
        # xmip-core-authenticate per allocation.toml section 3, so requiring it
        # here would fail the moment Distribute succeeds.
        [string] $architecture = Join-Path $script:Root 'docs/architecture'

        [string[]] $required = @(
            'runtime-model.md'
            'repository-model.md'
            'module-model.md'
            'deployment-model.md'
            'observability-model.md'
        )

        foreach ($name in $required) {
            [string] $path = Join-Path $architecture $name

            Test-Path -LiteralPath $path |
                Should -BeTrue -Because "ADR-0020 names $name as one of the six"
        }
    }
}
