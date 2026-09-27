#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    What GitHub holds that the manifest does not declare, and the reverse.

.DESCRIPTION
    Apart from Sync-XmipEstate.ps1 since 2026-09-22, when that file was 1,303 lines
    against the 400 the estate allows, and the owner asked for the estate to be
    consolidated. Reconciling the estate is one command made of several subjects;
    each subject is a file.

    Style: doc/governance/powershell-style.md
#>


<#
    .SYNOPSIS
    The repository each language's new crates are generated from, by
    language; empty when the manifest names none.

    .DESCRIPTION
    `[crate.template]`, a table of language to owner/name. It also read the
    single string of schema 2.0 before 2026-08-27 and `cratePolicy` from
    schema 1 until 2026-09-21, when the owner ruled that nothing released
    means nothing to stay compatible with: *There is no point holding on to
    old repos or code.* The manifest has one shape and this reads that one.
#>
function Get-XmipTemplate {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        $Manifest
    )

    $crate = Get-TomlValue -Node $Manifest -Name 'crate' -Default $null
    $declared = Get-TomlValue -Node $crate -Name 'template' -Default $null

    if ($null -eq $declared) {
        return @{}
    }

    $templates = @{}

    foreach ($language in (Get-TomlKey -Node $declared)) {
        $templates[$language] = [string](Get-TomlValue -Node $declared -Name $language -Default '')
    }

    return $templates
}


<#
    .SYNOPSIS
    Repositories in the Xmip namespace that the manifest does not declare.

    .DESCRIPTION
    Only names beginning xmip-. The owner's other repositories are none of the
    estate's business, and reporting them would make the number noise rather
    than a finding.

    An unexpected repository is usually one of two things: something created
    deliberately and not yet declared, or something left behind under a name
    the manifest has since changed. The responses are opposites — declare it,
    or rename it — so this reports and does not guess.
#>
function Get-XmipUnexpectedName {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $Actual,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $Declared,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]] $Template = @()
    )

    $declaredSet = [System.Collections.Generic.HashSet[string]]::new(
        $Declared, [StringComparer]::OrdinalIgnoreCase)

    # The template repositories are referenced by the manifest — crate.template
    # — but are not repositories it declares, so they reported as unexpected on
    # the first run that could report anything. They are not stray; they are
    # what -Create generates from.
    #
    # Plural since 2026-08-27: one per language, and the estate has two.
    foreach ($name in $Template) {
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            [void] $declaredSet.Add(($name -split '/')[-1])
        }
    }

    return @(
        $Actual |
            Where-Object { $_ -like 'xmip-*' -and -not $declaredSet.Contains($_) } |
            Sort-Object
    )
}


<#
    .SYNOPSIS
    A case-insensitive set of the names on a collection of manifest entries.

    .DESCRIPTION
    Get-XmipGitHubRepository returns GitHub repository objects, not names.
    Declaring the caller's parameter [string[]] coerced them to type names and
    matched nothing, which reported every repository as waiting on creation.
#>
function Get-XmipNameSet {
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.HashSet[string]])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Entries
    )

    $names = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    foreach ($entry in @(ConvertTo-XmipArray -Value $Entries)) {
        [void] $names.Add([string](Get-XmipPropertyValue -Object $entry -Name 'name'))
    }

    return $names
}


<#
    .SYNOPSIS
    Splits missing repositories into actionable drift and expected absence.

    .DESCRIPTION
    A reserved repository that does not exist is not drift — repository-model.md
    section 3 says the manifest is the design and creation follows need.
    Reporting all of them printed 293 warnings to surface one action.
#>
function Split-XmipDrift {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        $Manifest,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $Missing
    )

    [hashtable] $maturityOf = @{}

    [object[]] $declared = @(
        Get-XmipPropertyValue -Object $Manifest -Name 'repositories' -Default @()
    )

    foreach ($repository in $declared) {
        [string] $name = [string](Get-XmipPropertyValue -Object $repository -Name 'name')
        $maturityOf[$name] = [string](
            Get-XmipPropertyValue -Object $repository -Name 'maturity' -Default 'reserved'
        )
    }

    $actionable = [System.Collections.Generic.List[object]]::new()
    $expected = [System.Collections.Generic.List[string]]::new()

    foreach ($name in $Missing) {
        [string] $maturity = [string] $maturityOf[$name]

        if ($maturity -eq 'reserved') {
            $expected.Add($name)
            continue
        }

        $actionable.Add([pscustomobject]@{ Name = $name; Maturity = $maturity })
    }

    return @{ actionable = @($actionable.ToArray()); expected = @($expected.ToArray()) }
}
