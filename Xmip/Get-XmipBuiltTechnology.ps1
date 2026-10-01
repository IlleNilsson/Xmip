#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    The technologies the estate has built, each with the leaf of its tree
    position: what a domain profile names and a site builds from.

.DESCRIPTION
    One rule, read by the domain profiles under deploy/profile/domain
    (Get-XmipDomainTechnology) and by test/Deploy.Test.ps1, which holds
    every one of them to a domain or a target (ADR-0015, amendment
    2026-10-01).

    Style: doc/governance/powershell-style.md
#>


function Get-XmipBuiltTechnology {
    <#
        .SYNOPSIS
            Every technology the manifest declares built, by repository name,
            with its leaf.

        .DESCRIPTION
            Built is scaffolded or beyond (ADR-0060's ladder): a reserved or
            planned technology has nothing to link. Left out, because none is
            a technology a Location names: a language binding of the contract
            capability and everything under an operator surface (both declare
            a primaryLanguage; a surface's children drive a node from outside,
            ADR-0014), whatever sits under a library (linked into what uses
            it, never loaded, the owner 2026-09-23), and optional scaffolding
            such as the Playground, which exercises Xmip from outside
            (ADR-0036).

            The leaf is the last segment of the technology's position in the
            manifest's tree, which is its name less the capability it
            implements: xmip-core-message-hl7-er7 is hl7-er7, and
            xmip-core-transport-aws-sqs is aws-sqs.

        .PARAMETER Manifest
            The manifest, from Get-XmipManifest.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        $Manifest
    )

    [hashtable] $byName = @{}

    foreach ($repository in @($Manifest.repositories)) {
        $byName[[string] $repository.name] = $repository
    }

    [object[]] $built = @(
        foreach ($repository in @($Manifest.repositories)) {
            if (Test-XmipBuiltTechnology -Repository $repository -ByName $byName) {
                [string] $name = $repository.name
                [string] $parent = @($repository.dependencies)[0]

                [pscustomobject] @{
                    Name = $name
                    Leaf = $name.Substring($parent.Length + 1)
                }
            }
        }
    )

    return @($built | Sort-Object -Property Name)
}


function Test-XmipBuiltTechnology {
    <#
        .SYNOPSIS
            Whether one repository is a built technology; the rule
            Get-XmipBuiltTechnology states.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        $Repository,

        [Parameter(Mandatory = $true)]
        [hashtable] $ByName
    )

    if ([string] $Repository.repositoryRole -ne 'technology-implementation') {
        return $false
    }

    if ([string] $Repository.maturity -in @('reserved', 'planned')) {
        return $false
    }

    if ($Repository.optional -or '' -ne [string] $Repository.primaryLanguage) {
        return $false
    }

    $parent = $ByName[[string] @($Repository.dependencies)[0]]

    if ($null -eq $parent) {
        return $false
    }

    return (
        [string] $parent.architecturalDomain -ne 'Library' -and
        '' -eq [string] $parent.primaryLanguage
    )
}
