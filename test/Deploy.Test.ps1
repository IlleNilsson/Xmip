#Requires -Version 7.6.5

# The deploy profiles and sites (ADR-0015, amendment 2026-10-01). A site under
# deploy/site picks a target, its node roles and its domains from the
# profiles under deploy/profile, and Build-XmipService turns it into a build.
# This holds the profiles to the estate they describe: every built technology
# serves a domain or is a target's, every standard a domain names is one a
# technology has, the role files are the node's own role words, every feature
# named is the root crate's, and every site resolves, or is refused exactly
# where its target says. The deploy files name a site that exists.

BeforeDiscovery {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    $manifest = Get-XmipManifest -Path (Join-Path $script:Root 'architecture.toml')
    $script:Built = @(
        InModuleScope Xmip -Parameters @{ Manifest = $manifest } {
            param($Manifest)
            @(Get-XmipBuiltTechnology -Manifest $Manifest).Name
        }
    )
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
            Cargo      = Get-XmipRootCargo -Root $Root
            Profile    = @{}
            SiteTarget = @{}
        }

        foreach ($kind in 'target', 'role', 'domain') {
            $read.Profile[$kind] = [ordered] @{}

            foreach ($name in @(Get-XmipProfileName -Root $Root -Kind $kind)) {
                $file = Get-XmipProfile -Root $Root -Kind $kind -Name $name
                $refuses = Get-TomlValue -Node $file -Name 'refuses' -Default @{}

                $read.Profile[$kind][$name] = @{
                    Features  = @(Get-TomlValue -Node $file -Name 'features' -Default @())
                    Refuses   = @(Get-TomlKey -Node $refuses)
                    Roles     = @(Get-TomlValue -Node $file -Name 'roles' -Default @())
                    Standards = @(Get-TomlValue -Node $file -Name 'standards' -Default @())
                    Instead   = $null -ne (Get-TomlValue -Node $file -Name 'instead')
                }
            }
        }

        $read.Member = @(
            foreach ($domain in $read.Profile['domain'].Keys) {
                [hashtable] $asked = @{ Root = $Root; Technology = $technology; Domain = $domain }
                Get-XmipDomainTechnology @asked
            }
        )

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

Describe 'Every built technology is in a domain or a target''s' {
    It 'finds something built to place' {
        $script:Read.Technology.Count | Should -BeGreaterThan 50
    }

    It 'places <_>' -ForEach $script:Built {
        $placed = $_ -in $script:Read.Member -or $_ -in $script:Read.Claimed

        $placed | Should -BeTrue -Because (
            "$_ serves no domain under deploy/profile/domain and no target claims it")
    }

    It 'claims only built technologies' {
        $script:Read.Claimed | Where-Object { $_ -notin $script:Read.Technology.Name } |
            Should -BeNullOrEmpty
    }
}

Describe 'The profiles name what exists' {
    It 'names, in each domain, only standards some built technology has' {
        [string[]] $leaf = @($script:Read.Technology.Leaf)
        [string[]] $unmatched = @(
            foreach ($domain in $script:Read.Profile['domain'].GetEnumerator()) {
                $domain.Value.Standards | Where-Object { $_ -cnotin $leaf } |
                    ForEach-Object { "$($domain.Key): $_" }
            }
        )

        $unmatched | Should -BeNullOrEmpty
    }

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

    It 'refuses a role the target refuses a feature of, in words' {
        [string] $path = Join-Path $TestDrive 'roaming.toml'
        Set-Content -LiteralPath $path -Value @(
            'target = "computer"'
            'roles = ["operational"]'
            'domains = ["mail"]'
        )

        { Resolve-XmipTestSite -Site $path } | Should -Throw -ExpectedMessage (
            'REFUSED: site roaming cannot be built. role operational needs cluster, ' +
            'which the computer target refuses: *')
    }

    It 'refuses a site naming no profile there is' {
        [string] $path = Join-Path $TestDrive 'unknown.toml'
        Set-Content -LiteralPath $path -Value @(
            'target = "server"'
            'roles = ["executing"]'
            'domains = ["astronomy"]'
        )

        { Resolve-XmipTestSite -Site $path } |
            Should -Throw -ExpectedMessage "REFUSED: there is no domain called 'astronomy'*"
    }
}

Describe 'The deploy files name a site' {
    It 'names, in <_>, a site that exists' -ForEach @(
        'deploy/dsc/xmip-node.dsc.yaml'
        'deploy/ansible/roles/xmip_node/defaults/main.yml'
    ) {
        [string] $text = Get-Content -LiteralPath (Join-Path $script:Root $_) -Raw

        [string] $named = '(?m)^\s*(site|xmip_site): deploy/site/(?<site>[a-z0-9-]+)\.toml\s*$'

        $text -match $named | Should -BeTrue -Because "$_ names the site its node is built from"
        Join-Path $script:Root "deploy/site/$($Matches['site']).toml" | Should -Exist
    }
}
