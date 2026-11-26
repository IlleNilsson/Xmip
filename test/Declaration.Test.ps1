#requires -PSEdition Core
#requires -Version 7.7.0

using namespace System.Collections.Generic

<#
    A technology built with its declaration alone pulls in no heavy
    dependency (open problem 48, step 1; ADR-0064, amendments 2026-10-22 and
    2026-11-26). The owner, 2026-10-22: the runtime library the surfaces
    load carries every technology's declaration — names, settings, kinds and
    words, not the technologies' code — by a `declaration` feature in each
    technology crate, its code and its dependencies behind the default
    feature, gathered by one crate the surfaces' build links (step 3, to
    come).

    Heavy is whatever a technology's code is built on and its declaration is
    not. A declaration may compile its capability and what the capability
    compiles, which the surfaces' library links already through the runtime,
    and other technologies' declarations, each held here as well. Any other
    crate in a declaration's build is a dependency the default feature left
    out, and the surfaces' library would carry it.

    The builds are what `cargo tree` resolves, offline, in the estate's one
    workspace (ADR-0016, amendment 2026-11-20): every technology declaring
    the feature at once, with --no-default-features --features declaration,
    as a gathering crate builds them, and each capability with its own
    defaults.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    [string] $manifest = Join-Path $script:Root 'Cargo.toml'

    <#
        .SYNOPSIS
            What each of `Package` compiles, built as `Argument` says: each
            package's name to the names of every crate in its build, itself
            included, from one `cargo tree` over all of them. Nothing where
            cargo cannot resolve the build.

        .PARAMETER Package
            The estate's crates, by package name.

        .PARAMETER Argument
            What else cargo is told: the features.
    #>
    function Get-XmipTestBuilt {
        [CmdletBinding()]
        [OutputType([hashtable])]
        param(
            [Parameter(Mandatory = $true)]
            [string[]] $Package,

            [Parameter(Mandatory = $true)]
            [AllowEmptyCollection()]
            [string[]] $Argument
        )

        [string[]] $selected = @($Package | ForEach-Object { '-p'; $_ })
        [string[]] $asked = @(
            'tree', '--offline', '--manifest-path', $manifest, '-e', 'normal',
            '--prefix', 'depth', '--format', '{p}'
        ) + $selected + $Argument
        [string[]] $line = @(& cargo @asked 2>$null)

        if ($LASTEXITCODE -ne 0) {
            return @{}
        }

        return Get-XmipTestClosure -Line $line
    }

    <#
        .SYNOPSIS
            Every root of a `cargo tree --prefix depth` listing to the names
            of every crate under it, itself included. A crate cargo printed
            once and marked `(*)` after is followed where it was printed.

        .PARAMETER Line
            The listing, one crate a line, a blank line between two roots.
    #>
    function Get-XmipTestClosure {
        [CmdletBinding()]
        [OutputType([hashtable])]
        param(
            [Parameter(Mandatory = $true)]
            [AllowEmptyCollection()]
            [AllowEmptyString()]
            [string[]] $Line
        )

        [hashtable] $under = @{}
        [List[string]] $root = [List[string]]::new()
        [List[string]] $path = [List[string]]::new()

        foreach ($text in $Line) {
            if ($text -notmatch '^(\d+)(\S+) v') {
                continue
            }

            [int] $depth = [int] $Matches[1]
            [string] $name = $Matches[2]
            $path.RemoveRange($depth, $path.Count - $depth)
            $path.Add($name)

            if ($depth -eq 0) {
                $root.Add($name)
            }
            elseif (-not $under.ContainsKey($path[$depth - 1])) {
                $under[$path[$depth - 1]] = [HashSet[string]]::new()
            }

            if ($depth -gt 0) {
                $null = $under[$path[$depth - 1]].Add($name)
            }
        }

        [hashtable] $built = @{}

        foreach ($each in $root) {
            $built[$each] = Get-XmipTestReached -From $each -Under $under
        }

        return $built
    }

    <#
        .SYNOPSIS
            `From` and every crate it reaches through `Under`.

        .PARAMETER From
            The crate the walk starts at.

        .PARAMETER Under
            Each crate's name to the names of the crates it depends on.
    #>
    function Get-XmipTestReached {
        [CmdletBinding()]
        [OutputType([HashSet[string]])]
        param(
            [Parameter(Mandatory = $true)]
            [string] $From,

            [Parameter(Mandatory = $true)]
            [hashtable] $Under
        )

        [HashSet[string]] $reached = [HashSet[string]]::new()
        [Stack[string]] $next = [Stack[string]]::new()
        $next.Push($From)

        while ($next.Count -gt 0) {
            [string] $name = $next.Pop()

            if ($reached.Add($name) -and $Under.ContainsKey($name)) {
                foreach ($below in $Under[$name]) {
                    $next.Push($below)
                }
            }
        }

        return , $reached
    }

    # The estate's crates, read once: which declare a `declaration` feature,
    # and what each one's capability is, from the manifest.
    [string[]] $arguments = @(
        'metadata', '--offline', '--no-deps', '--format-version', '1', '--manifest-path', $manifest
    )
    $metadata = & cargo @arguments 2>$null | ConvertFrom-Json -Depth 64 -AsHashtable
    $script:Resolved = $LASTEXITCODE -eq 0 -and $null -ne $metadata

    [string[]] $script:Declaring = @(
        if ($script:Resolved) {
            $metadata.packages |
                Where-Object { $_.features.ContainsKey('declaration') } |
                ForEach-Object { [string] $_.name } |
                Sort-Object
        }
    )

    [hashtable] $script:Parent = @{}
    foreach ($repository in @(Get-XmipEstateRepository -Root $script:Root)) {
        $script:Parent[$repository.Name] = [string] $repository.Parent
    }

    [string[]] $script:Capability = @(
        $script:Declaring |
            ForEach-Object { $script:Parent[$_] } |
            Where-Object { -not [string]::IsNullOrEmpty($_) } |
            Sort-Object -Unique
    )

    [hashtable] $script:Alone = @{}
    [hashtable] $script:Whole = @{}

    if ($script:Declaring.Count -gt 0) {
        [string[]] $declarationAlone = @('--no-default-features', '--features', 'declaration')
        $script:Alone = Get-XmipTestBuilt -Package $script:Declaring -Argument $declarationAlone
        $script:Whole = Get-XmipTestBuilt -Package $script:Capability -Argument @()
    }

    <#
        .SYNOPSIS
            What `Package`'s declaration may compile: its capability's build
            and every technology's declaration.

        .PARAMETER Package
            The crate declaring it.
    #>
    function Get-XmipTestAllowed {
        [CmdletBinding()]
        [OutputType([HashSet[string]])]
        param(
            [Parameter(Mandatory = $true)]
            [string] $Package
        )

        [HashSet[string]] $allowed = [HashSet[string]]::new([string[]] $script:Declaring)
        [string] $capability = $script:Parent[$Package]

        if (-not [string]::IsNullOrEmpty($capability) -and $script:Whole.ContainsKey($capability)) {
            $allowed.UnionWith($script:Whole[$capability])
        }

        return , $allowed
    }
}

Describe 'A technology built with its declaration alone pulls in no heavy dependency' {
    It 'resolves the estate offline and finds the technologies that declare one' {
        $script:Resolved | Should -BeTrue -Because (
            'cargo metadata --offline resolves the workspace once its dependencies are ' +
            'fetched; fetch them once with a build'
        )
        $script:Declaring.Count | Should -BeGreaterThan 0 -Because (
            'a technology crate declares a `declaration` feature, its code behind the ' +
            'default (ADR-0064, amendment 2026-10-22)'
        )
        @($script:Declaring | Where-Object { -not $script:Alone.ContainsKey($_) }) |
            Should -BeNullOrEmpty -Because 'cargo builds every declaration alone'
        @($script:Capability | Where-Object { -not $script:Whole.ContainsKey($_) }) |
            Should -BeNullOrEmpty -Because 'each declaration is held to its capability''s build'
    }

    It 'compiles nothing for a declaration but its capability''s build and other declarations' {
        [string[]] $heavy = @(
            foreach ($package in $script:Declaring) {
                [HashSet[string]] $allowed = Get-XmipTestAllowed -Package $package
                [string[]] $beyond = @(
                    $script:Alone[$package] | Where-Object { -not $allowed.Contains($_) } |
                        Sort-Object
                )

                if ($beyond.Count -gt 0) {
                    "$($package): $($beyond -join ', ')"
                }
            }
        )

        $heavy | Should -BeNullOrEmpty -Because (
            "a declaration's build compiles these, which only the technology's code " +
            "needs; put each behind the default feature:`n" + ($heavy -join "`n")
        )
    }
}
