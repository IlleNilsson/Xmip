#Requires -Version 7.6.5

# The deploy profiles and sites (ADR-0015, amendment 2026-10-01). A site under
# deploy/site picks a target and its node roles from the profiles under
# deploy/profile, and the technologies its user chose (amendment 2026-10-19),
# and Build-XmipService turns it into a build. This holds the estate to it:
# every built technology is mounted where the landing builds and tests it and
# has tests of its own, a target claims only built technologies, every role
# carrying archive names the archive targets (amendment 2026-10-14), the role
# files are the node's own role words, every feature named is the root
# crate's, and every site resolves, or is refused exactly where its target
# says. The deploy files name a site that exists.

BeforeDiscovery {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    $script:SiteName = @(
        Get-ChildItem -LiteralPath (Join-Path $script:Root 'deploy/site') -Filter '*.toml' |
            ForEach-Object { @{ Name = $_.BaseName } }
    )
}

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    $script:Manifest = Get-XmipManifest -Path (Join-Path $script:Root 'architecture.toml')

    # Everything the tests ask, read once through the module's own readers
    # and handed out as plain values.
    $script:Read = InModuleScope Xmip -Parameters @{
        Root     = $script:Root
        Manifest = $script:Manifest
    } {
        param($Root, $Manifest)

        [object[]] $technology = @(Get-XmipBuiltTechnology -Manifest $Manifest)
        [hashtable] $read = @{
            Technology = $technology
            Claimed    = @(Get-XmipTargetClaim -Root $Root)
            Archived   = @(Get-XmipArchiveTarget -Root $Root)
            Cargo      = Get-XmipRootCargo -Root $Root
            Profile    = @{}
            SiteTarget = @{}
        }

        foreach ($kind in 'target', 'role') {
            $read.Profile[$kind] = [ordered] @{}

            foreach ($name in @(Get-XmipProfileName -Root $Root -Kind $kind)) {
                $file = Get-XmipProfile -Root $Root -Kind $kind -Name $name
                $refuses = Get-TomlValue -Node $file -Name 'refuses' -Default @{}

                $read.Profile[$kind][$name] = @{
                    Features = @(Get-TomlValue -Node $file -Name 'features' -Default @())
                    Refuses  = @(Get-TomlKey -Node $refuses)
                    Roles    = @(Get-TomlValue -Node $file -Name 'roles' -Default @())
                    Archives = @(Get-TomlValue -Node $file -Name 'archives' -Default @())
                    Instead  = $null -ne (Get-TomlValue -Node $file -Name 'instead')
                }
            }
        }

        # Where each crate is, and what the landing builds and tests: every
        # declared module, nested included (Get-XmipDeclaredModule).
        $read.Crate = @{}

        foreach ($crate in @(Get-XmipEstateCrate -RepositoryRoot $Root)) {
            $read.Crate[$crate.Name] = $crate.Directory
        }

        $read.Declared = @(Get-XmipDeclaredModule -RepositoryRoot $Root)

        [string] $sites = Join-Path $Root 'deploy/site'

        foreach ($file in Get-ChildItem -LiteralPath $sites -Filter '*.toml') {
            $site = Read-XmipToml -Path $file.FullName
            $read.SiteTarget[$file.BaseName] = [string] (Get-TomlValue -Node $site -Name 'target')
        }

        return $read
    }

    function Resolve-XmipTestSite {
        param([string] $Site)

        InModuleScope Xmip -Parameters @{
            Root     = $script:Root
            Site     = $Site
            Manifest = $script:Manifest
        } {
            param($Root, $Site, $Manifest)
            Resolve-XmipSite -Root $Root -Site $Site -Manifest $Manifest
        }
    }
}

Describe 'Targets claim, and archiving roles name, what is built' {
    BeforeAll {
        # The archive targets: the built technologies of the archive
        # capability, whose name is the capability's and the leaf.
        $script:Archive = @(
            $script:Read.Technology |
                Where-Object { $_.Name -ceq "xmip-core-archive-$($_.Leaf)" } |
                ForEach-Object -MemberName Name
        )
    }

    It 'finds something built' {
        $script:Read.Technology.Count | Should -BeGreaterThan 50
        $script:Archive.Count | Should -BeGreaterThan 0
    }

    It 'claims only built technologies' {
        $script:Read.Claimed | Where-Object { $_ -notin $script:Read.Technology.Name } |
            Should -BeNullOrEmpty
    }

    It 'names archive targets in every role carrying archive, and only there' {
        [string[]] $wrong = @(
            foreach ($role in $script:Read.Profile['role'].GetEnumerator()) {
                [bool] $archives = 'archive' -cin $role.Value.Features

                if ($archives -and $role.Value.Archives.Count -eq 0) {
                    "role $($role.Key) carries archive and names no archive target"
                }

                if (-not $archives -and $role.Value.Archives.Count -gt 0) {
                    "role $($role.Key) names archive targets and does not carry archive"
                }

                $role.Value.Archives | Where-Object { $_ -cnotin $script:Archive } |
                    ForEach-Object { "role $($role.Key): $_ is no built archive target" }
            }
        )

        $wrong | Should -BeNullOrEmpty
    }
}

# "Test all" (the owner, 2026-10-19; ADR-0015, amendment 2026-10-19): a
# node's technologies are its user's choice, so every built technology is
# one a user may choose, and each is built and tested. The landing builds
# every declared module with every feature it declares and runs its tests
# (Publish-XmipChange, Test-XmipModule); this holds each built technology to
# being such a module, with tests of its own.
Describe 'Every built technology is built and tested' {
    It 'mounts every built technology as a module the landing verifies' {
        [string] $prefix = ($script:Root -replace '\\', '/').TrimEnd('/') + '/'
        [string[]] $wrong = @(
            foreach ($name in $script:Read.Technology.Name) {
                [string] $directory = $script:Read.Crate[$name]

                if (-not $directory) {
                    "$name is declared built and mounted nowhere"
                    continue
                }

                [string] $mount = $directory.Substring($prefix.Length)

                if ($mount -cnotin $script:Read.Declared) {
                    "$name, at $mount, is no declared module"
                }
            }
        )

        $wrong | Should -BeNullOrEmpty
    }

    It 'finds tests in every built technology' {
        [string] $output = '[\\/](target|target-[^\\/]+)[\\/]'
        [string[]] $untested = @(
            foreach ($name in $script:Read.Technology.Name) {
                [string] $directory = $script:Read.Crate[$name]

                if (-not $directory) {
                    continue
                }

                [object[]] $source = @(
                    Get-ChildItem -LiteralPath $directory -Filter '*.rs' -File -Recurse |
                        Where-Object { $_.FullName -notmatch $output }
                )
                $found = $source | Select-String -Pattern '#[test]' -SimpleMatch -List

                if ($null -eq $found) {
                    "$name has no test"
                }
            }
        )

        $untested | Should -BeNullOrEmpty
    }
}

Describe 'The profiles name what exists' {
    It 'has a role file for exactly the node''s role words' {
        [string[]] $word = @(InModuleScope Xmip { Get-XmipNodeRoleWord })

        @($script:Read.Profile['role'].Keys | Sort-Object) | Should -Be @($word | Sort-Object)
    }

    It 'names only the root crate''s features, in every target and role' {
        [string[]] $declared = @($script:Read.Cargo.Features)
        [string[]] $unknown = @(
            foreach ($kind in 'target', 'role') {
                foreach ($entry in $script:Read.Profile[$kind].GetEnumerator()) {
                    @($entry.Value.Features) + @($entry.Value.Refuses) |
                        Where-Object { $_ -cnotin $declared } |
                        ForEach-Object { "$kind $($entry.Key): $_" }
                }
            }
        )

        $unknown | Should -BeNullOrEmpty
    }

    It 'composes roles only of roles' {
        [string[]] $role = @($script:Read.Profile['role'].Keys)
        [string[]] $unknown = @(
            $script:Read.Profile['role'].Values.Roles | Where-Object { $_ -cnotin $role }
        )

        $unknown | Should -BeNullOrEmpty
    }
}

Describe 'Every site becomes a build, or is refused where its target says' {
    It 'has a site for every target' {
        [string[]] $used = @($script:Read.SiteTarget.Values)

        @($script:Read.Profile['target'].Keys | Where-Object { $_ -notin $used }) |
            Should -BeNullOrEmpty
    }

    It 'resolves <Name>' -ForEach $script:SiteName {
        [string] $target = $script:Read.SiteTarget[$Name]

        if ($script:Read.Profile['target'][$target].Instead) {
            { Resolve-XmipTestSite -Site $Name } |
                Should -Throw -ExpectedMessage "REFUSED: site $Name *--manifest-path*"
            return
        }

        $plan = Resolve-XmipTestSite -Site $Name

        $plan.Target | Should -Be $target
        $plan.Command | Should -BeLike 'cargo build --bin xmip-service --no-default-features *'
        foreach ($required in $script:Read.Cargo.Required) {
            $plan.Features | Should -Contain $required
        }
    }

    It 'builds the archive targets of its archiving roles' {
        $plan = Resolve-XmipTestSite -Site 'hospital-interface'

        $plan.Archives | Should -Contain 'xmip-core-archive-parquet'
        @($plan.Archives | Where-Object { $_ -cnotin $script:Read.Archived }) |
            Should -BeNullOrEmpty
    }

    It 'builds the technologies its site names, and links those it can' {
        [string] $path = Join-Path $TestDrive 'chosen.toml'
        Set-Content -LiteralPath $path -Value @(
            'target = "server"'
            'roles = ["receiving"]'
            'technologies = ["xmip-core-transport-file", "xmip-core-transport-smtp"]'
        )

        $plan = Resolve-XmipTestSite -Site $path

        $plan.Technologies | Should -Be @('xmip-core-transport-file', 'xmip-core-transport-smtp')
        $plan.Features | Should -Contain 'transport-file'
        $plan.Unlinked | Should -Contain 'xmip-core-transport-smtp'
        $plan.Archives | Should -BeNullOrEmpty
    }

    It 'refuses a role the target refuses a feature of, in words' {
        [string] $path = Join-Path $TestDrive 'roaming.toml'
        Set-Content -LiteralPath $path -Value @(
            'target = "computer"'
            'roles = ["operational"]'
            'technologies = ["xmip-core-transport-smtp"]'
        )

        { Resolve-XmipTestSite -Site $path } | Should -Throw -ExpectedMessage (
            'REFUSED: site roaming cannot be built. role operational needs cluster, ' +
            'which the computer target refuses: *')
    }

    It 'refuses a site naming no profile there is' {
        [string] $path = Join-Path $TestDrive 'unknown.toml'
        Set-Content -LiteralPath $path -Value @(
            'target = "server"'
            'roles = ["astronomy"]'
        )

        { Resolve-XmipTestSite -Site $path } |
            Should -Throw -ExpectedMessage "REFUSED: there is no role called 'astronomy'*"
    }

    It 'refuses a site naming no built technology' {
        [string] $path = Join-Path $TestDrive 'unbuilt.toml'
        Set-Content -LiteralPath $path -Value @(
            'target = "server"'
            'roles = ["executing"]'
            'technologies = ["xmip-core-transport-file", "xmip-core-transport-telescope"]'
        )

        { Resolve-XmipTestSite -Site $path } | Should -Throw -ExpectedMessage (
            'REFUSED: site unbuilt names xmip-core-transport-telescope, ' +
            'which is no built technology*')
    }
}

Describe 'The deploy files name a site' {
    It 'names, in <_>, a site that exists' -ForEach @(
        'deploy/dsc/ansible/roles/xmip_node/defaults/main.yml'
    ) {
        [string] $text = Get-Content -LiteralPath (Join-Path $script:Root $_) -Raw

        [string] $named = '(?m)^\s*(site|xmip_site): deploy/site/(?<site>[a-z0-9-]+)\.toml\s*$'

        $text -match $named | Should -BeTrue -Because "$_ names the site its node is built from"
        Join-Path $script:Root "deploy/site/$($Matches['site']).toml" | Should -Exist
    }
}

# The packages (ADR-0015, amendment 2026-10-13). Each installs by running
# xmip-service's own install switch and removes by its uninstall switch, so
# no package holds a copy of the layout, the starter or the registration;
# and a package this estate has not built says so where it is described.
Describe 'The packages under deploy/package' {
    BeforeAll {
        $script:Package = Join-Path $script:Root 'deploy/package'
    }

    It 'reads <_> as XML' -ForEach @(
        'windows/Package.wxs'
        'windows/Xmip.wixproj'
        'macos/distribution.xml'
    ) {
        { [xml] (Get-Content -LiteralPath (Join-Path $script:Package $_) -Raw) } |
            Should -Not -Throw
    }

    It 'installs and removes, in <Path>, through xmip-service' -ForEach @(
        @{ Path = 'windows/Package.wxs'; Switch = '--install', '--uninstall' }
        @{ Path = 'linux/postinstall.sh'; Switch = @('--install') }
        @{ Path = 'linux/preremove.sh'; Switch = @('--uninstall') }
        @{ Path = 'macos/scripts/postinstall'; Switch = @('--install') }
    ) {
        [string] $text = Get-Content -LiteralPath (Join-Path $script:Package $Path) -Raw

        $text | Should -Match 'xmip-service'
        foreach ($named in $Switch) {
            $text | Should -Match ([regex]::Escape($named))
        }
    }

    It 'says, in <_>, that it is written and not built' -ForEach @(
        'linux/nfpm.yaml'
        'linux/postinstall.sh'
        'linux/preremove.sh'
        'macos/distribution.xml'
        'macos/scripts/postinstall'
    ) {
        Get-Content -LiteralPath (Join-Path $script:Package $_) -Raw |
            Should -Match 'WRITTEN, NOT (BUILT|RUN)'
    }

    It 'names, in nfpm.yaml, scripts that exist' {
        [string] $linux = Join-Path $script:Package 'linux'
        [string] $text = Get-Content -LiteralPath (Join-Path $linux 'nfpm.yaml') -Raw

        $named = [regex]::Matches($text, '(?m)^\s+\w+: \./(?<file>\S+)\s*$')

        $named.Count | Should -Be 2 -Because 'nfpm.yaml names postinstall.sh and preremove.sh'
        foreach ($entry in $named) {
            Join-Path $linux $entry.Groups['file'].Value | Should -Exist
        }
    }
}
