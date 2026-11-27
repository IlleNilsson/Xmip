#Requires -Version 7.7.0

# The deploy profiles and sites (ADR-0015, amendment 2026-10-01). A site under
# deploy/site picks a target and its node roles from the profiles under
# deploy/profile, and the technologies its user chose (amendment 2026-10-19),
# and Build-XmipService turns it into a build. This holds the estate to it:
# every built technology is mounted where the landing builds and tests it and
# has tests of its own, the role files are the node's own role words, every
# feature named is the root crate's, and every site resolves, or is refused
# exactly where its target says. The deploy files name a site that exists.

BeforeDiscovery {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    $script:SiteName = @(
        Get-ChildItem -LiteralPath (Join-Path $script:Root 'deploy/site') -Filter '*.xmip' |
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

        foreach ($file in Get-ChildItem -LiteralPath $sites -Filter '*.xmip') {
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

# "Test all" (the owner, 2026-10-19; ADR-0015, amendment 2026-10-19): a
# node's technologies are its user's choice, so every built technology is
# one a user may choose, and each is built and tested. The landing builds
# every declared module with every feature it declares and runs its tests
# (Publish-XmipChange, Test-XmipRustChange); this holds each built technology to
# being such a module, with tests of its own.
Describe 'Every built technology is built and tested' {
    It 'finds something built' {
        $script:Read.Technology.Count | Should -BeGreaterThan 50
    }

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

    It 'builds the technologies its site names, and links those it can' {
        [string] $path = Join-Path $TestDrive 'chosen.xmip'
        Set-Content -LiteralPath $path -Value @(
            'target = "server"'
            'roles = ["receiving"]'
            'technologies = ["xmip-core-transport-smtp", "xmip-core-transport-aws-s3",'
            '    "xmip-core-transport-aws"]'
        )

        $plan = Resolve-XmipTestSite -Site $path

        $plan.Technologies | Should -Be @(
            'xmip-core-transport-smtp', 'xmip-core-transport-aws-s3', 'xmip-core-transport-aws'
        )
        $plan.Features | Should -Contain 'transport-smtp'
        # Presenting the secret its Location names, aws-s3 is linked since
        # 2026-11-25; aws, what AWS's transports speak and no transport, is
        # not (architecture.toml, linked-transports). It was zigbee until
        # 2026-11-27, when zigbee and Bluetooth were linked on Linux.
        $plan.Features | Should -Contain 'transport-aws-s3'
        $plan.Unlinked | Should -Be @('xmip-core-transport-aws')
    }

    # Site chooses (the owner, 2026-10-20; ADR-0015, amendment 2026-10-20):
    # an archive target is a technology like every other, and the role that
    # archives brings the archive feature, not the targets.
    It 'builds the archive targets its site names, beside its role''s archive feature' {
        [string] $path = Join-Path $TestDrive 'archived.xmip'
        Set-Content -LiteralPath $path -Value @(
            'target = "server"'
            'roles = ["sending"]'
            'technologies = ["xmip-core-archive-parquet"]'
        )

        $plan = Resolve-XmipTestSite -Site $path

        $plan.Technologies | Should -Be @('xmip-core-archive-parquet')
        $plan.Features | Should -Contain 'archive'
        $plan.Features | Should -Contain 'retain'
        @($plan.PSObject.Properties.Name) | Should -Not -Contain 'Archives'
    }

    It 'refuses a role the target refuses a feature of, in words' {
        [string] $path = Join-Path $TestDrive 'roaming.xmip'
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
        [string] $path = Join-Path $TestDrive 'unknown.xmip'
        Set-Content -LiteralPath $path -Value @(
            'target = "server"'
            'roles = ["astronomy"]'
        )

        { Resolve-XmipTestSite -Site $path } |
            Should -Throw -ExpectedMessage "REFUSED: there is no role called 'astronomy'*"
    }

    It 'refuses a site naming no built technology' {
        [string] $path = Join-Path $TestDrive 'unbuilt.xmip'
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

        [string] $named = '(?m)^\s*(site|xmip_site): deploy/site/(?<site>[a-z0-9-]+)\.xmip\s*$'

        $text -match $named | Should -BeTrue -Because "$_ names the site its node is built from"
        Join-Path $script:Root "deploy/site/$($Matches['site']).xmip" | Should -Exist
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
        'macos/distribution.xml'
        'macos/scripts/postinstall'
    ) {
        Get-Content -LiteralPath (Join-Path $script:Package $_) -Raw |
            Should -Match 'WRITTEN, NOT (BUILT|RUN)'
    }

    It 'refuses a .deb or .rpm off Linux, naming what its build needs' -Skip:$IsLinux {
        foreach ($kind in 'deb', 'rpm') {
            {
                InModuleScope Xmip -Parameters @{ Kind = $kind } {
                    param($Kind)
                    Assert-XmipPackageBuildable -Package $Kind
                }
            } | Should -Throw ("REFUSED: -Package $kind is not built on this machine. " +
                "A .$kind is built on Linux*")
        }
    }

    It 'builds a .deb or .rpm on Linux where nfpm is, and refuses it where not' -Skip:(
        -not $IsLinux) {
        InModuleScope Xmip {
            Mock Get-Command { [pscustomobject] @{ Name = 'nfpm' } } -ParameterFilter {
                $Name -eq 'nfpm' }
            { Assert-XmipPackageBuildable -Package 'deb', 'rpm' } | Should -Not -Throw
            Mock Get-Command { $null } -ParameterFilter { $Name -eq 'nfpm' }
            { Assert-XmipPackageBuildable -Package 'rpm' } |
                Should -Throw '*made by nfpm 2.48, which is not on PATH*'
        }
    }

    It 'makes the <_> by nfpm.yaml from the staged binaries, version and amd64' -ForEach @(
        'deb', 'rpm') {
        [string] $stage = Join-Path $TestDrive 'stage'
        $global:XmipTestNfpm = @()
        function global:nfpm {
            $global:XmipTestNfpm = @($args) + @("dir=$($env:XMIP_BINARY_DIRECTORY)",
                "version=$($env:XMIP_VERSION)", "arch=$($env:XMIP_ARCH)", "at=$(Get-Location)")
            $global:LASTEXITCODE = 0
        }
        try {
            [string] $made = InModuleScope Xmip -Parameters @{ Kind = $_; Stage = $stage
                Root = $script:Root; Output = [string] $TestDrive } {
                param($Kind, $Stage, $Root, $Output)
                [hashtable] $made = @{ Root = $Root; Site = 'personal-computer'; Version = '0.1.1'
                    Architecture = 'x64'; Stage = $Stage; Output = $Output; Kind = $Kind }
                New-XmipLinuxPackage @made 6> $null
            }
        }
        finally {
            # The global function itself: a scope in a provider path names none.
            Remove-Item -Path 'Function:\nfpm'
        }
        $made | Should -Be (Join-Path $TestDrive "xmip-0.1.1-personal-computer-linux-x64.$_")
        $global:XmipTestNfpm[0..6] | Should -Be @('package', '--config', 'nfpm.yaml', '--packager',
            $_, '--target', $made)
        $global:XmipTestNfpm | Should -Contain "dir=$(Join-Path $stage 'xmip/bin')"
        $global:XmipTestNfpm | Should -Contain 'version=0.1.1'
        $global:XmipTestNfpm | Should -Contain 'arch=amd64'
        $global:XmipTestNfpm | Should -Contain "at=$(Join-Path $script:Package 'linux')"
        $env:XMIP_ARCH | Should -BeNullOrEmpty -Because 'the variables are put back'
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

    # The command line ships in every package (ADR-0015, amendment
    # 2026-11-19): what each declares is Get-XmipPackageProgram's list, the
    # one list of the programs, and `xmip` is on PATH where there is an
    # installer.
    It 'names, in <Path>, exactly the programs every package carries' -ForEach @(
        @{
            Path    = 'windows/Package.wxs'
            System  = 'windows'
            Pattern = '\$\(var\.BinaryDirectory\)\\(?<file>[^"]+)"'
        }
        @{
            Path    = 'linux/nfpm.yaml'
            System  = 'linux'
            Pattern = '(?m)^\s+- src: \$\{XMIP_BINARY_DIRECTORY\}/(?<file>\S+)\s*$'
        }
        @{
            Path    = 'archive/README.md'
            System  = 'windows'
            Pattern = '(?m)^\| `bin/(?<file>[^`]+)`'
        }
    ) {
        [string] $text = Get-Content -LiteralPath (Join-Path $script:Package $Path) -Raw
        [string[]] $named = @(
            [regex]::Matches($text, $Pattern) | ForEach-Object { $_.Groups['file'].Value })
        [string[]] $program = @(
            InModuleScope Xmip -Parameters @{ System = $System } {
                param($System)
                (Get-XmipPackageProgram -System $System).File
            })

        if ($Path -like 'archive/*') {
            # The archive's README names a program as every system does, with
            # its .exe said beside it.
            $program = @($program -replace '\.exe$', '')
        }

        $named.Count | Should -Be 3
        @($named | Sort-Object) | Should -Be @($program | Sort-Object)
    }

    It 'puts the MSI''s bin folder on the machine''s PATH with xmip.exe, while installed' {
        [xml] $wxs = Get-Content -LiteralPath (Join-Path $script:Package 'windows/Package.wxs') -Raw
        [hashtable] $namespace = @{ w = 'http://wixtoolset.org/schemas/v4/wxs' }
        [object[]] $found = @(
            Select-Xml -Xml $wxs -XPath '//w:Environment[@Name="PATH"]' -Namespace $namespace)

        $found.Count | Should -Be 1
        [Xml.XmlElement] $row = $found[0].Node
        $row.GetAttribute('Value') | Should -Be '[BINFOLDER]'
        $row.GetAttribute('Action') | Should -Be 'set'
        $row.GetAttribute('Part') | Should -Be 'last'
        $row.GetAttribute('System') | Should -Be 'yes'
        $row.GetAttribute('Permanent') | Should -Be 'no'

        # In the component that installs xmip.exe, so the two go together.
        [Xml.XmlElement] $component = $row.ParentNode
        $component.GetAttribute('Directory') | Should -Be 'BINFOLDER'
        $component.GetElementsByTagName('File')[0].GetAttribute('Source') |
            Should -BeLike '*\xmip.exe'
    }

    It 'links /usr/bin/xmip to the command line in the .deb and .rpm, run as xmip-service is' {
        $nfpm = Read-XmipTestYaml -Path (Join-Path $script:Package 'linux/nfpm.yaml')
        [object[]] $content = @($nfpm['contents'])
        [object[]] $link = @($content | Where-Object { $_['type'] -eq 'symlink' })

        $link.Count | Should -Be 1
        $link[0]['src'] | Should -Be '/opt/xmip/bin/xmip'
        $link[0]['dst'] | Should -Be '/usr/bin/xmip'

        $service = $content | Where-Object { $_['dst'] -eq '/opt/xmip/bin/xmip-service' }
        $command = $content | Where-Object { $_['dst'] -eq '/opt/xmip/bin/xmip' }
        $command['file_info']['mode'] | Should -Be $service['file_info']['mode']
    }

    It 'links /usr/local/bin/xmip to the command line in the macOS postinstall' {
        Get-Content -LiteralPath (Join-Path $script:Package 'macos/scripts/postinstall') -Raw |
            Should -Match ([regex]::Escape('ln -sf /opt/xmip/bin/xmip /usr/local/bin/xmip'))
    }

    It 'names xmip among the commands of the winget manifest' {
        [string] $msi = Join-Path $TestDrive 'xmip-0.1.1-personal-computer-x64.msi'
        Set-Content -LiteralPath $msi -Value 'msi'

        [string] $folder = InModuleScope Xmip -Parameters @{
            Msi  = $msi
            Into = Join-Path $TestDrive 'winget'
        } {
            param($Msi, $Into)
            Mock Get-XmipMsiProperty { '{00000000-0000-0000-0000-000000000000}' }
            New-XmipWingetManifest -Msi $Msi -Version '0.1.1' -Architecture x64 -Destination $Into
        }

        $installer = Read-XmipTestYaml -Path (Join-Path $folder 'Xmip.Xmip.installer.yaml')
        @($installer['Commands']) | Should -Be @('xmip')
    }

    Context 'A package''s staging, with cargo mocked' {
        BeforeAll {
            # An estate of its own: the root crate's version and the folders
            # of the library and the command line, members of its one
            # workspace. xmip-service is built, as Build-XmipService leaves
            # it; cargo writes what it builds where it would, and the command
            # line's build.rs the developer's cli.toml beside xmip.
            [string] $script:Estate = Join-Path $TestDrive 'estate'
            [string] $script:Target = Join-Path $TestDrive 'target'

            foreach ($folder in 'module/core/operation/operate', 'module/core/operation/cli') {
                $null = New-Item -ItemType Directory -Path (Join-Path $script:Estate $folder) -Force
            }
            Set-Content -LiteralPath (Join-Path $script:Estate 'Cargo.toml') -Value @(
                '[package]', 'name = "xmip"', 'version = "0.1.1"')

            [object[]] $script:Program = @(InModuleScope Xmip { Get-XmipPackageProgram })
            $service = $script:Program | Where-Object -Property Kind -EQ 'Service'
            [string] $release = Join-Path $script:Target 'release'
            $null = New-Item -ItemType Directory -Path $release -Force
            Set-Content -LiteralPath (Join-Path $release $service.File) -Value $service.Kind

            [string] $script:Was = $env:CARGO_TARGET_DIR
            [string] $script:Before = (Get-Location).Path
            $env:CARGO_TARGET_DIR = $script:Target
            $global:XmipTestCargo = [Collections.Generic.List[object]]::new()

            try {
                $script:Made = InModuleScope Xmip -Parameters @{ Root = $script:Estate } {
                    param($Root)
                    Mock Invoke-XmipTool {
                        $global:XmipTestCargo.Add([pscustomobject] @{
                                Argument = @($Argument)
                                At       = (Get-Location).Path
                                Target   = $env:CARGO_TARGET_DIR
                            })
                        [string] $kind = if ($Argument -contains '--lib') { 'Library' }
                        else { 'Command' }
                        $one = Get-XmipPackageProgram | Where-Object -Property Kind -EQ $kind
                        [string] $into = Join-Path $env:CARGO_TARGET_DIR 'release'
                        $null = New-Item -ItemType Directory -Path $into -Force
                        Set-Content -LiteralPath (Join-Path $into $one.File) -Value $kind

                        if ($kind -eq 'Command') {
                            Set-Content -LiteralPath (Join-Path $into 'cli.toml') -Value '[Xmip]'
                        }

                        [pscustomobject] @{ Passed = $true; Said = @() }
                    }
                    Mock New-XmipArchive { 'archive.zip' }
                    Mock Write-XmipStep { }

                    [hashtable] $asked = @{
                        Root          = $Root
                        Site          = 'personal-computer'
                        Package       = 'archive'
                        CargoArgument = '--release', '--locked'
                    }
                    New-XmipPackage @asked
                }
                $script:After = $env:CARGO_TARGET_DIR
                $script:Cargo = @($global:XmipTestCargo)
            }
            finally {
                $env:CARGO_TARGET_DIR = $script:Was
                Remove-Variable -Name XmipTestCargo -Scope Global
            }

            # -Force: off Windows, .local-work is hidden by its leading dot.
            [hashtable] $listing = @{
                LiteralPath = $script:Estate
                Directory   = $true
                Recurse     = $true
                Force       = $true
            }
            [object[]] $staged = @(Get-ChildItem @listing)
            $script:Bin = $staged |
                Where-Object { $_.Name -eq 'bin' -and $_.Parent.Name -eq 'xmip' }
        }

        It 'stages the three programs, each from its own build, and never a cli.toml' {
            $script:Made.Kind | Should -Be 'archive'
            @($script:Bin).Count | Should -Be 1

            [string[]] $staged = @(Get-ChildItem -LiteralPath $script:Bin.FullName -File).Name
            @($staged | Sort-Object) | Should -Be @($script:Program.File | Sort-Object)
            Join-Path $script:Target 'release/cli.toml' | Should -Exist
            Join-Path $script:Bin.FullName 'cli.toml' | Should -Not -Exist

            foreach ($one in $script:Program) {
                Get-Content -LiteralPath (Join-Path $script:Bin.FullName $one.File) |
                    Should -Be $one.Kind
            }
        }

        It 'builds <Kind> in its folder with the site''s arguments, beside the service' -ForEach @(
            @{ Kind = 'Library'; Build = @('build', '--lib') }
            @{ Kind = 'Command'; Build = @('build', '--bin', 'xmip') }
        ) {
            $one = $script:Program | Where-Object -Property Kind -EQ $Kind
            [string] $folder = [IO.Path]::GetFullPath((Join-Path $script:Estate $one.Folder))
            [object[]] $call = @($script:Cargo |
                    Where-Object { [IO.Path]::GetFullPath($_.At) -eq $folder })

            $call.Count | Should -Be 1
            $call[0].Argument | Should -Be (@($Build) + @('--release', '--locked'))
            $call[0].Target | Should -Be $script:Target
        }

        It 'gives the session its folder and CARGO_TARGET_DIR back' {
            $script:Cargo.Count | Should -Be 2 -Because 'xmip-service was built before'
            $script:After | Should -Be $script:Target
            (Get-Location).Path | Should -Be $script:Before
        }
    }

    It 'gives both back when cargo fails, saying the command and the crate in words' {
        [string] $before = (Get-Location).Path
        [string] $was = $env:CARGO_TARGET_DIR
        [string] $crate = [IO.Path]::GetFullPath($TestDrive)
        Remove-Item -Path 'env:CARGO_TARGET_DIR' -ErrorAction SilentlyContinue

        try {
            {
                InModuleScope Xmip -Parameters @{ Root = [string] $TestDrive } {
                    param($Root)
                    Mock Invoke-XmipTool { [pscustomobject] @{ Passed = $false; Said = @() } }
                    [hashtable] $building = @{
                        Root            = $Root
                        Folder          = '.'
                        TargetDirectory = Join-Path $Root 'target'
                        Argument        = 'build', '--bin', 'xmip'
                    }
                    Invoke-XmipCrateBuild @building
                }
            } | Should -Throw "FAILED: cargo build --bin xmip, in $crate."

            $env:CARGO_TARGET_DIR | Should -BeNullOrEmpty
            (Get-Location).Path | Should -Be $before
        }
        finally {
            if ($was) {
                $env:CARGO_TARGET_DIR = $was
            }
        }
    }
}
