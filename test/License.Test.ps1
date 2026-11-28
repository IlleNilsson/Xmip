#requires -PSEdition Core
#requires -Version 7.7.0

<#
    ADR-0075 and ADR-0061, amendment 2026-11-24: everything a developer's
    module links or compiles into itself is Apache-2.0, so a module stays its
    author's to license — the module boundary, xmip-core-abi, with
    Xmip.Module and the `dotnet new` templates in it — and the rest of Xmip
    is AGPL-3.0-or-later (ADR-0023), the .NET repository template among it.
    The boundary links nothing of the rest. Each example, which a developer
    copies into a module of their own, is Apache-2.0 as the boundary is
    (ADR-0023, amendment 2026-11-28), read from the manifest's domain.
#>

Describe 'ADR-0075: the module boundary is Apache-2.0, the rest of Xmip AGPL-3.0-or-later' {
    BeforeAll {
        . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

        # What a module links or compiles into itself.
        $script:Boundary = @('module/foundation/abi')

        # What a developer copies into a module: every mounted repository
        # the manifest's domain names an Example.
        $script:Example = @(
            InModuleScope Xmip -Parameters @{ Root = $script:Root } {
                param($Root)
                Get-XmipEstateRepository -Root $Root |
                    Where-Object { $_.Domain -eq 'Example' -and $_.Mounted } |
                    ForEach-Object Mount
            }
        )

        <#
            .SYNOPSIS
            The files git holds under a folder of the estate and the working
            tree still has, each with its path from the estate's root.
        #>
        function Get-HeldFile {
            [CmdletBinding()]
            [OutputType([string[]])]
            param(
                [Parameter(Mandatory = $true)]
                [string] $Folder
            )

            [string] $at = Join-Path -Path $script:Root -ChildPath $Folder

            @(git -C $at ls-files) |
                ForEach-Object { "$Folder/$_" } |
                Where-Object { Test-Path -LiteralPath (Join-Path $script:Root $_) -PathType Leaf }
        }
    }

    It 'gives the boundary and each example the Apache-2.0 text and a NOTICE' {
        $script:Example | Should -Not -BeNullOrEmpty -Because 'the manifest declares the examples'

        foreach ($folder in ($script:Boundary + $script:Example)) {
            [string] $path = Join-Path -Path $script:Root -ChildPath $folder
            [string] $license = Get-Content -LiteralPath (Join-Path $path 'LICENSE') -Raw

            $license | Should -Match 'Apache License\s+Version 2\.0, January 2004' -Because $folder
            Join-Path $path 'NOTICE' | Should -Exist -Because $folder
        }
    }

    It 'declares Apache-2.0 in every crate, package and SPDX line it holds' {
        [string[]] $wrong = @()
        [string[]] $held = @(
            ($script:Boundary + $script:Example) | ForEach-Object { Get-HeldFile -Folder $_ }
        )

        foreach ($file in $held) {
            [string] $text = Get-Content -LiteralPath (Join-Path $script:Root $file) -Raw

            if ($text -match 'SPDX-License-Identifier:\s*(?!Apache-2\.0\b)\S+') {
                $wrong += "$file names $($Matches[0])"
            }

            # Said by the crate itself: one taking the estate's
            # `license.workspace = true` would be AGPL-3.0-or-later.
            if ($file -match '(^|/)Cargo\.toml$' -and
                $text -notmatch '(?m)^license\s*=\s*"Apache-2\.0"\s*$') {
                $wrong += "$file is not license = ""Apache-2.0"""
            }

            if ($text -match '<PackageLicenseExpression>(?!Apache-2\.0<)') {
                $wrong += "$file packs another license"
            }
        }

        $wrong | Should -BeNullOrEmpty
    }

    It 'links nothing of the rest of Xmip into the boundary' {
        # The crate depends on no Xmip crate, and no project references one
        # outside its own repository, so nothing AGPL is compiled in.
        # Read as the estate map reads what a crate uses: an estate crate it
        # takes from the root's [workspace.dependencies] is named through the
        # root's entry (ADR-0005, amendment 2026-11-28).
        [string] $abi = Join-Path -Path $script:Root -ChildPath 'module/foundation/abi'
        [string[]] $estate = @(
            InModuleScope Xmip -Parameters @{ Root = $script:Root; Abi = $abi } {
                param($Root, $Abi)
                [hashtable] $workspace = Get-XmipWorkspaceDependency -RepositoryRoot $Root
                Get-XmipCargoUse -Directory $Abi -Workspace $workspace
            }
        )

        $estate | Should -BeNullOrEmpty -Because 'the boundary links no other crate of Xmip'

        [string[]] $projects = @(
            $script:Boundary |
                ForEach-Object { Get-HeldFile -Folder $_ } |
                Where-Object { $_ -match '\.csproj$' }
        )

        foreach ($file in $projects) {
            [string] $text = Get-Content -LiteralPath (Join-Path $script:Root $file) -Raw

            $text | Should -Not -Match 'ProjectReference Include="(\.\.\\){3,}' -Because $file
        }
    }

    It 'keeps the .NET repository template AGPL-3.0-or-later, as what it generates' {
        [string] $template = Join-Path -Path $script:Root -ChildPath 'template/dotnet'
        [string] $license = Get-Content -LiteralPath (Join-Path $template 'LICENSE') -Raw
        [string] $propsPath = Join-Path $template 'Directory.Build.props'
        [string] $props = Get-Content -LiteralPath $propsPath -Raw

        $license | Should -Match 'GNU AFFERO GENERAL PUBLIC LICENSE'
        $props | Should -Match '<PackageLicenseExpression>AGPL-3\.0-or-later<'
        Join-Path $template 'NOTICE' | Should -Not -Exist
    }

    It 'keeps every other crate of the estate AGPL-3.0-or-later' {
        # The root's manifest too: what a crate takes with
        # `license.workspace = true` is its [workspace.package]'s.
        [string[]] $roots = @('.src', 'module', 'test', 'template', 'sdk') |
            ForEach-Object { Join-Path -Path $script:Root -ChildPath $_ }
        [string[]] $boundary = $script:Boundary | ForEach-Object {
            (Join-Path -Path $script:Root -ChildPath $_) + [IO.Path]::DirectorySeparatorChar
        }
        [System.IO.FileInfo[]] $crates = @(
            Get-Item -LiteralPath (Join-Path -Path $script:Root -ChildPath 'Cargo.toml')
            InModuleScope Xmip -Parameters @{ Roots = $roots } {
                param($Roots)
                Find-XmipFile -Path $Roots -Filter 'Cargo.toml'
            }
        )
        [string[]] $wrong = @(
            $crates |
                Where-Object {
                    [string] $path = $_.FullName
                    -not ($boundary | Where-Object { $path.StartsWith($_) })
                } |
                Where-Object {
                    (Get-Content -LiteralPath $_.FullName -Raw) -match
                        '(?m)^license\s*=\s*"(?!AGPL-3\.0-or-later")'
                } |
                ForEach-Object { [IO.Path]::GetRelativePath($script:Root, $_.FullName) }
        )

        $wrong | Should -BeNullOrEmpty
    }
}
