#requires -PSEdition Core
#requires -Version 7.7.0

<#
    A third-party backend the estate reads a format through is linked by the
    one crate that owns that reading, and by no other, so a second reader
    cannot come back beside the first.

    The owner, 2026-11-13: *Do we have all code in the modules, repos that we
    should. This is a refactoring statement.* That day XML was read five ways:
    a scanner in `xmip-core-library-codec`, `roxmltree` in four crates,
    `quick-xml` in two, `sxd-document` in two and a walk of its own in the
    XML shape, besides the SAML gates' own. One reader took their place,
    `codec::xml`, over one backend; `sxd-document` and `sxd-xpath` stay as
    the `XPath` engine's evaluation model alone, filled from codec's reader
    (ADR-0044, amendment 2026-11-13).

    Every crate of the estate is read — every mounted repository's
    `Cargo.toml` and the root's — for what it names in its dependencies of
    every kind, its target-specific ones included. A backend listed here is
    named only by the crates listed with it; one listed with none is named by
    no crate. A new backend for a format the estate already reads is added
    here with the one crate that owns it, in the change that brings it.
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    # Each backend and the crates that may name it.
    [Collections.Specialized.OrderedDictionary] $script:Backend = [ordered] @{
        # XML: one reader, codec::xml, over one backend.
        'quick-xml'    = @('xmip-core-library-codec')
        # Text in the WHATWG encodings: one decoding, codec::charset, which
        # the XML reader's edge and prepare's Character Encoding call.
        'encoding_rs'  = @('xmip-core-library-codec')
        # XPath 1.0's engine and the document model it evaluates over.
        'sxd-document' = @('xmip-core-path-xpath')
        'sxd-xpath'    = @('xmip-core-path-xpath')
        # The XML readers the estate does not link.
        'roxmltree'    = @()
        'xmlparser'    = @()
        'xml-rs'       = @()
        'xmltree'      = @()
        'minidom'      = @()
        'xml5ever'     = @()
        'libxml'       = @()
        'serde-xml-rs' = @()
        'yaserde'      = @()
    }

    # Every crate and the packages it names, by package where a key renames
    # one: what a build links.
    $script:Crate = & (Get-Module -Name Xmip) {
        param([string] $Root)

        [string[]] $tables = @('dependencies', 'dev-dependencies', 'build-dependencies')

        [scriptblock] $named = {
            param($Table)

            foreach ($key in @(Get-TomlKey -Node $Table)) {
                $entry = Get-TomlValue -Node $Table -Name $key
                [string] $package = $key

                if ($entry -isnot [string]) {
                    $package = [string] (Get-TomlValue -Node $entry -Name 'package' -Default $key)
                }

                $package
            }
        }

        [string[]] $manifests = @(
            Join-Path $Root 'Cargo.toml'
            Get-XmipEstateRepository -Root $Root |
                Where-Object { $_.Mounted } |
                ForEach-Object { Join-Path (Join-Path $Root $_.Mount) 'Cargo.toml' }
        )

        foreach ($manifest in $manifests) {
            if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
                continue
            }

            $toml = Read-XmipToml -Path $manifest
            $package = Get-TomlValue -Node $toml -Name 'package'
            $targets = Get-TomlValue -Node $toml -Name 'target'

            [string[]] $uses = @(
                foreach ($table in $tables) {
                    & $named (Get-TomlValue -Node $toml -Name $table)

                    foreach ($target in @(Get-TomlKey -Node $targets)) {
                        $specific = Get-TomlValue -Node $targets -Name $target
                        & $named (Get-TomlValue -Node $specific -Name $table)
                    }
                }
            )

            [PSCustomObject] @{
                Name = [string] (Get-TomlValue -Node $package -Name 'name' -Default $manifest)
                Uses = [string[]] @($uses | Sort-Object -Unique)
            }
        }
    } $script:Root
}

Describe 'A third-party backend is linked by the one crate that owns it' {
    It 'reads most of the estate, so the check is not passing on nothing' {
        @($script:Crate).Count | Should -BeGreaterThan 100
        @($script:Crate | Where-Object { $_.Name -eq 'xmip-core-library-codec' }).Count |
            Should -Be 1
    }

    It 'finds each backend named only where it is allowed' {
        [string[]] $stray = @(
            foreach ($crate in $script:Crate) {
                foreach ($backend in $script:Backend.Keys) {
                    [string[]] $allowed = @($script:Backend[$backend])

                    if ($backend -in $crate.Uses -and $crate.Name -notin $allowed) {
                        [string] $where = if ($allowed.Count -gt 0) {
                            "only $($allowed -join ', ') may"
                        }
                        else {
                            'no crate of the estate does'
                        }

                        "$($crate.Name) names $backend, which $where"
                    }
                }
            }
        )

        $stray | Should -BeNullOrEmpty -Because (
            "a second reader beside the estate's one (ADR-0044, amendment 2026-11-13):`n" +
            ($stray -join "`n")
        )
    }

    It 'finds each allowed crate still naming its backend, so the list stays true' {
        [string[]] $gone = @(
            foreach ($backend in $script:Backend.Keys) {
                foreach ($allowed in @($script:Backend[$backend])) {
                    [PSCustomObject] $crate = $script:Crate |
                        Where-Object { $_.Name -eq $allowed } |
                        Select-Object -First 1

                    if ($null -eq $crate -or $backend -notin $crate.Uses) {
                        "$allowed no longer names $backend"
                    }
                }
            }
        )

        $gone | Should -BeNullOrEmpty -Because ($gone -join "`n")
    }
}
