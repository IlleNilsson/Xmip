#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    The one place a site becomes a build: the features its target, roles and
    domains need, refused where the target cannot have one.

.DESCRIPTION
    A site (deploy/site/<name>.toml) picks a target, its roles and its
    domains. The build carries the target's features, every role's, and each
    domain technology the root crate links through a feature; xmip-service's
    own required features are always on. The target vetoes: a role or a
    domain needing a feature the target refuses is REFUSED, in words naming
    the role or domain, the feature and the target's reason (ADR-0055). The
    build sets what is possible; the node's TOML picks from it at run time
    (ADR-0015, amendment 2026-10-01).

    Style: doc/governance/powershell-style.md
#>


function Resolve-XmipSite {
    <#
        .SYNOPSIS
            A site's build plan: Site, Target, Roles, Domains, Features,
            Unlinked and Command. Throws REFUSED in words when the site
            cannot be built.

        .PARAMETER Root
            The estate root.

        .PARAMETER Site
            A site's name under deploy/site, or the path of a site file.

        .PARAMETER Manifest
            The manifest, from Get-XmipManifest.

        .PARAMETER CargoArgument
            Further arguments for cargo, after the subcommand.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        [string] $Site,

        [Parameter(Mandatory = $true)]
        $Manifest,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]] $CargoArgument = @()
    )

    [string] $path = Find-XmipSiteFile -Root $Root -Site $Site
    [string] $siteName = [IO.Path]::GetFileNameWithoutExtension($path)
    $read = Read-XmipToml -Path $path
    [string] $target = Get-TomlValue -Node $read -Name 'target' -Default ''
    [string[]] $roles = @(Get-TomlValue -Node $read -Name 'roles' -Default @())
    [string[]] $domains = @(Get-TomlValue -Node $read -Name 'domains' -Default @())
    $targetRead = Get-XmipProfile -Root $Root -Kind 'target' -Name $target

    Assert-XmipTargetBuildsService -Root $Root -Site $siteName -Target $target -Read $targetRead

    $cargo = Get-XmipRootCargo -Root $Root
    [object[]] $technology = @(Get-XmipBuiltTechnology -Manifest $Manifest)
    [object[]] $needed = @(
        foreach ($feature in @(Get-TomlValue -Node $targetRead -Name 'features' -Default @())) {
            [pscustomobject] @{ Feature = [string] $feature; From = "target $target" }
        }
        foreach ($role in $roles) {
            Get-XmipRoleFeature -Root $Root -Role $role
        }
    )
    [string[]] $member = @()

    foreach ($domain in $domains) {
        [hashtable] $asked = @{ Root = $Root; Technology = $technology; Domain = $domain }

        foreach ($name in @(Get-XmipDomainTechnology @asked)) {
            $member += $name

            if ($cargo.Linked.ContainsKey($name)) {
                [string] $from = "domain $domain (through $name)"
                $needed += [pscustomobject] @{ Feature = $cargo.Linked[$name]; From = $from }
            }
        }
    }

    $member = @($member | Sort-Object -Unique)

    Assert-XmipTargetVeto -Site $siteName -Target $target -Read $targetRead -Needed $needed

    [string[]] $features = @(@($cargo.Required) + @($needed.Feature) | Sort-Object -Unique)
    [string[]] $argument = @(
        'build', '--bin', 'xmip-service', '--no-default-features',
        '--features', ($features -join ',')
    ) + $CargoArgument

    $plan = [pscustomobject] @{
        PSTypeName = 'Xmip.SiteBuild'
        Site       = $siteName
        Target     = $target
        Roles      = $roles
        Domains    = $domains
        Features   = $features
        Unlinked   = @($member | Where-Object { -not $cargo.Linked.ContainsKey($_) })
        Command    = 'cargo ' + ($argument -join ' ')
        Argument   = $argument
    }

    # Argument is what Build-XmipService hands cargo; Command says it.
    [string[]] $shown = @('Site', 'Target', 'Roles', 'Domains', 'Features', 'Unlinked', 'Command')
    [System.Management.Automation.PSMemberInfo[]] $standard = @(
        [System.Management.Automation.PSPropertySet]::new('DefaultDisplayPropertySet', $shown)
    )
    $plan.PSObject.Members.Add(
        [System.Management.Automation.PSMemberSet]::new('PSStandardMembers', $standard))

    return $plan
}


function Find-XmipSiteFile {
    <#
        .SYNOPSIS
            The file a -Site names: a path to one, or a name under deploy/site.
            REFUSED in words naming the sites there are when neither is found.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        [string] $Site
    )

    if ($Site.EndsWith('.toml') -and (Test-Path -LiteralPath $Site -PathType Leaf)) {
        return (Resolve-Path -LiteralPath $Site).ProviderPath
    }

    [string] $directory = Join-Path $Root $script:XmipSiteDirectory
    [string] $named = Join-Path $directory "$Site.toml"

    if (Test-Path -LiteralPath $named -PathType Leaf) {
        return $named
    }

    [string[]] $known = @(Get-ChildItem -LiteralPath $directory -Filter '*.toml' -File).BaseName

    throw "REFUSED: there is no site called '$Site'; the sites are $($known -join ', ')."
}


function Assert-XmipTargetBuildsService {
    <#
        .SYNOPSIS
            REFUSED when the target cannot run xmip-service at all, saying
            why and the command that builds what it can run instead.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        [string] $Site,

        [Parameter(Mandatory = $true)]
        [string] $Target,

        [Parameter(Mandatory = $true)]
        $Read
    )

    $instead = Get-TomlValue -Node $Read -Name 'instead' -Default $null

    if ($null -eq $instead) {
        return
    }

    [string] $triple = @(Get-TomlValue -Node $Read -Name 'triples' -Default @())[0]
    [string[]] $feature = @(Get-TomlValue -Node $instead -Name 'features' -Default @())
    [string] $command = 'cargo build --manifest-path {0} --no-default-features{1} --target {2}' -f
        (Get-TomlValue -Node $instead -Name 'manifest'),
        $(if ($feature.Count -gt 0) { " --features $($feature -join ',')" } else { '' }),
        $triple

    throw ("REFUSED: site $Site is on the $Target target, which cannot run xmip-service: " +
        "$((Get-TomlValue -Node $instead -Name 'reason').Trim()) What builds for it: $command")
}


function Assert-XmipTargetVeto {
    <#
        .SYNOPSIS
            REFUSED when a role or a domain needs a feature the target
            refuses, naming each: the role or domain, the feature and the
            target's reason.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Site,

        [Parameter(Mandatory = $true)]
        [string] $Target,

        [Parameter(Mandatory = $true)]
        $Read,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Needed
    )

    $refuses = Get-TomlValue -Node $Read -Name 'refuses' -Default @{}
    [string[]] $refused = @(Get-TomlKey -Node $refuses)

    [string[]] $said = @(
        foreach ($need in @($Needed | Where-Object { $_.Feature -cin $refused })) {
            [string] $reason = (Get-TomlValue -Node $refuses -Name $need.Feature).Trim()
            "$($need.From) needs $($need.Feature), which the $Target target refuses: $reason"
        }
    )
    $said = @($said | Sort-Object -Unique)

    if ($said.Count -gt 0) {
        throw "REFUSED: site $Site cannot be built. $($said -join ' ')"
    }
}
