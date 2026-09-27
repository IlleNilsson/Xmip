#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    The deploy lists, generated from the manifest.

.DESCRIPTION
    deploy/dsc/xmip-node.dsc.yaml and deploy/ansible/roles/xmip_node/defaults/main.yml
    each name every technology a node carries and which of them start. They
    were written by hand and held equal to architecture.toml by a test, and
    on 2026-09-09 hand-edited three times in one day. Now the manifest says
    both: every technology it declares built is carried, and its [deploy]
    table says which start. Sync-XmipEstate -Deploy writes the lists;
    test/Deploy.Test.ps1 fails when a file is not what this would write.

    Style: doc/governance/powershell-style.md
#>

# The two files, relative to the estate root.
[string] $script:XmipDeployDsc = 'deploy/dsc/xmip-node.dsc.yaml'
[string] $script:XmipDeployAnsible = 'deploy/ansible/roles/xmip_node/defaults/main.yml'


function Get-XmipDeployedTechnology {
    <#
        .SYNOPSIS
            The technologies a node carries: every one the manifest declares
            built, by repository name, with whether it starts.

        .DESCRIPTION
            Built is scaffolded or beyond (ADR-0060's ladder): a reserved or
            planned technology has nothing to load. Left out, because none is
            a technology a Location names: a language binding of the contract
            capability and everything under an operator surface (both declare
            a primaryLanguage; a surface's children drive a node from outside,
            ADR-0014), whatever sits under a library (linked into what uses
            it, never loaded, the owner 2026-09-23), and optional scaffolding
            such as the Playground, which exercises Xmip from outside
            (ADR-0036). Start is true for a name the manifest's [deploy]
            started list holds, which must be one carried.

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

    [string[]] $carried = @(
        foreach ($repository in @($Manifest.repositories)) {
            if (Test-XmipDeployedTechnology -Repository $repository -ByName $byName) {
                [string] $repository.name
            }
        }
    )

    $deploy = Get-TomlValue -Node $Manifest -Name 'deploy' -Default $null
    [string[]] $started = @(Get-TomlValue -Node $deploy -Name 'started' -Default @())

    foreach ($name in $started) {
        if ($name -notin $carried) {
            throw "architecture.toml [deploy] starts $name, which no node carries."
        }
    }

    foreach ($name in ($carried | Sort-Object)) {
        [pscustomobject] @{
            Name  = $name
            Start = $name -in $started
        }
    }
}


function Test-XmipDeployedTechnology {
    <#
        .SYNOPSIS
            Whether one repository is a technology a node carries; the rule
            Get-XmipDeployedTechnology states.
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


function New-XmipDeployList {
    <#
        .SYNOPSIS
            What each deploy file says once its lists are the manifest's, by
            the file's path from the root.

        .DESCRIPTION
            Only the lists are generated; the rest of each file is the
            operator's and is kept as it is. In the DSC document they are the
            `present` and `started` arrays of the node configuration it
            writes; in the Ansible defaults, `xmip_modules`, which ends the
            file.

        .PARAMETER Root
            The estate root.

        .PARAMETER Manifest
            The manifest, from Get-XmipManifest.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        $Manifest
    )

    [object[]] $technology = @(Get-XmipDeployedTechnology -Manifest $Manifest)

    [string] $dsc = Get-Content -LiteralPath (Join-Path $Root $script:XmipDeployDsc) -Raw
    [string] $ansible = Get-Content -LiteralPath (Join-Path $Root $script:XmipDeployAnsible) -Raw

    [string] $indent = ' ' * 14
    [string] $present = New-XmipDscArray -Key 'present' -Name @($technology.Name) -Indent $indent
    [string[]] $startedName = @($technology | Where-Object { $_.Start } | ForEach-Object Name)
    [string] $started = New-XmipDscArray -Key 'started' -Name $startedName -Indent $indent
    [string] $lists = "(?ms)^ {14}present = \[.*?^ {14}\]\n^ {14}started = \[.*?^ {14}\]\n"

    [string[]] $entry = @(
        foreach ($item in $technology) {
            [string] $start = if ($item.Start) { 'true' } else { 'false' }
            "  - { name: $($item.Name), start: $start }"
        }
    )

    [int] $at = $ansible.IndexOf("`nxmip_modules:`n", [StringComparison]::Ordinal)

    if ($at -lt 0 -or $dsc -notmatch $lists) {
        throw 'A deploy file has lost the lists it is generated around.'
    }

    return [ordered] @{
        $script:XmipDeployDsc     = [regex]::Replace($dsc, $lists, ($present + $started))
        $script:XmipDeployAnsible = $ansible.Substring(0, $at + 1) +
            "xmip_modules:`n" + ($entry -join "`n") + "`n"
    }
}


function New-XmipDscArray {
    <#
        .SYNOPSIS
            One TOML array of names inside the DSC document's here-string,
            one name to a line.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Key,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $Name,

        [Parameter(Mandatory = $true)]
        [string] $Indent
    )

    [string[]] $line = @("$Indent$Key = [") +
        @($Name | ForEach-Object { "$Indent  `"$_`"," }) +
        @("$Indent]")

    return (($line -join "`n") + "`n")
}


function Update-XmipDeployList {
    <#
        .SYNOPSIS
            Writes the deploy lists from the manifest; Sync-XmipEstate -Deploy.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Root,

        [Parameter(Mandatory = $true)]
        $Manifest
    )

    [System.Collections.Specialized.OrderedDictionary] $written =
        New-XmipDeployList -Root $Root -Manifest $Manifest

    foreach ($path in $written.Keys) {
        [string] $full = Join-Path $Root $path
        [string] $now = Get-Content -LiteralPath $full -Raw

        if ($now -ceq $written[$path]) {
            Write-XmipStep -Message "Deploy: $path is the manifest's already"
            continue
        }

        if ($PSCmdlet.ShouldProcess($path, 'Write the deploy lists')) {
            Set-Content -LiteralPath $full -Value $written[$path] -NoNewline -Encoding utf8NoBOM
            Write-XmipStep -Message "Deploy: wrote $path"
        }
    }
}
