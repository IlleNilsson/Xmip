#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    The deploy profiles: targets, roles and domains under deploy/profile, and
    what the root crate's Cargo.toml says a build can link.

.DESCRIPTION
    A target is what a build runs on, a role what its node is for, a domain
    what it integrates (ADR-0015, amendment 2026-10-01). Each is a TOML file
    named by its word; a site under deploy/site picks one target, its roles
    and its domains, and Resolve-XmipSite turns that into features.

    Style: doc/governance/powershell-style.md
#>

# Where the profiles and the sites are, relative to the estate root.
[string] $script:XmipProfileDirectory = 'deploy/profile'
[string] $script:XmipSiteDirectory = 'deploy/site'


function Get-XmipProfileName {
    <#
        .SYNOPSIS
            Every profile of one kind, by its word: the file names under
            deploy/profile/<kind>, sorted.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        [ValidateSet('target', 'role', 'domain')]
        [string] $Kind
    )

    [string] $directory = Join-Path $Root "$script:XmipProfileDirectory/$Kind"
    [object[]] $file = @(Get-ChildItem -LiteralPath $directory -Filter '*.toml' -File)

    return @($file.BaseName | Sort-Object)
}


function Get-XmipProfile {
    <#
        .SYNOPSIS
            One profile, read; REFUSED in words naming the ones there are
            when no profile of that kind has the word.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        [ValidateSet('target', 'role', 'domain')]
        [string] $Kind,

        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    [string[]] $known = @(Get-XmipProfileName -Root $Root -Kind $Kind)

    if ($Name -cnotin $known) {
        throw "REFUSED: there is no $Kind called '$Name'; the ${Kind}s are $($known -join ', ')."
    }

    return (Read-XmipToml -Path (Join-Path $Root "$script:XmipProfileDirectory/$Kind/$Name.toml"))
}


function Get-XmipRoleFeature {
    <#
        .SYNOPSIS
            The root crate features one role is built with, its composed
            roles expanded (executing is receiving, processing and sending),
            each with the role that brought it.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        [string] $Role
    )

    $read = Get-XmipProfile -Root $Root -Kind 'role' -Name $Role

    foreach ($feature in @(Get-TomlValue -Node $read -Name 'features' -Default @())) {
        [pscustomobject] @{ Feature = [string] $feature; From = "role $Role" }
    }

    foreach ($composed in @(Get-TomlValue -Node $read -Name 'roles' -Default @())) {
        Get-XmipRoleFeature -Root $Root -Role ([string] $composed)
    }
}


function Get-XmipTargetClaim {
    <#
        .SYNOPSIS
            Every technology a target claims: the runtime store's engines and
            the key stores, which are a target's business and no domain's.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root
    )

    [string[]] $claimed = @(
        foreach ($target in @(Get-XmipProfileName -Root $Root -Kind 'target')) {
            $read = Get-XmipProfile -Root $Root -Kind 'target' -Name $target
            @(Get-TomlValue -Node $read -Name 'claims' -Default @())
        }
    )

    return @($claimed | Sort-Object -Unique)
}


function Get-XmipDomainTechnology {
    <#
        .SYNOPSIS
            A domain's members: every built technology whose leaf the domain
            names among its standards, across capabilities, less what a
            target claims.

        .PARAMETER Technology
            Get-XmipBuiltTechnology's answer, read once by the caller.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        [object[]] $Technology,

        [Parameter(Mandatory = $true)]
        [string] $Domain
    )

    $read = Get-XmipProfile -Root $Root -Kind 'domain' -Name $Domain
    [string[]] $standard = @(Get-TomlValue -Node $read -Name 'standards' -Default @())
    [string[]] $claimed = @(Get-XmipTargetClaim -Root $Root)

    [object[]] $member = @(
        $Technology | Where-Object { $_.Leaf -cin $standard -and $_.Name -notin $claimed }
    )

    return @($member.Name)
}


function Get-XmipRootCargo {
    <#
        .SYNOPSIS
            What the root crate's Cargo.toml says a build can be: its
            features, the technology each links, and the features
            xmip-service always needs.

        .DESCRIPTION
            Features is every name in [features] but default. Linked maps a
            technology to the feature that links it: a feature listing
            `dep:<alias>` where [dependencies] <alias> has package =
            "<technology>" (transport-tcp links xmip-core-transport-tcp).
            Required is xmip-service's [[bin]] required-features, the one
            place that says what the program cannot be built without.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root
    )

    $cargo = Read-XmipToml -Path (Join-Path $Root 'Cargo.toml')
    $features = Get-TomlValue -Node $cargo -Name 'features' -Default @{}
    $dependencies = Get-TomlValue -Node $cargo -Name 'dependencies' -Default @{}
    [hashtable] $linked = @{}

    foreach ($feature in @(Get-TomlKey -Node $features)) {
        foreach ($item in @(Get-TomlValue -Node $features -Name $feature -Default @())) {
            if ([string] $item -match '^dep:(.+)$') {
                $dependency = Get-TomlValue -Node $dependencies -Name $Matches[1]
                [string] $package = Get-TomlValue -Node $dependency -Name 'package' -Default ''

                if ('' -ne $package) {
                    $linked[$package] = $feature
                }
            }
        }
    }

    $service = @(Get-TomlValue -Node $cargo -Name 'bin' -Default @()) |
        Where-Object { (Get-TomlValue -Node $_ -Name 'name') -ceq 'xmip-service' }

    return [pscustomobject] @{
        Features = @(Get-TomlKey -Node $features | Where-Object { $_ -cne 'default' })
        Linked   = $linked
        Required = @(Get-TomlValue -Node $service -Name 'required-features' -Default @())
    }
}
