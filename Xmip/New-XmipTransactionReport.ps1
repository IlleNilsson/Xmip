#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    What the manifest declares against what GitHub has, for Sync-XmipEstate.

.DESCRIPTION
    Style: doc/governance/powershell-style.md
#>


function New-XmipTransactionReport {
    <#
        What the manifest declares against what GitHub has: missing,
        unexpected, and the counts Sync-XmipEstate reports and -Report writes.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory = $true)]
        $Manifest,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Actual
    )

    [object[]] $declared = @(
        Get-XmipPropertyValue -Object $Manifest -Name 'repositories' -Default @()
    )
    [hashtable] $desired = @{}

    foreach ($repository in $declared) {
        $desired[[string](Get-XmipPropertyValue -Object $repository -Name 'name')] = $repository
    }

    [hashtable] $actualMap = @{}

    foreach ($repository in @(ConvertTo-XmipArray -Value $Actual)) {
        if ($null -ne $repository) {
            [string] $name = [string](Get-XmipPropertyValue -Object $repository -Name 'name')
            $actualMap[$name] = $repository
        }
    }

    [hashtable] $unexpectedQuery = @{
        Actual   = @($actualMap.Keys)
        Declared = @($desired.Keys)
        Template = @((Get-XmipTemplate -Manifest $Manifest).Values)
    }

    [hashtable] $unversioned = @{ Object = $Manifest; Default = 'unversioned' }

    return [ordered]@{
        generatedAtUtc = [DateTime]::UtcNow.ToString('o')
        scriptVersion = $ExecutionContext.SessionState.Module.Version.ToString()
        schemaVersion = [string](Get-XmipPropertyValue @unversioned -Name 'schemaVersion')
        architectureVersion = [string](
            Get-XmipPropertyValue @unversioned -Name 'architectureVersion'
        )
        owner = [string](Get-XmipPropertyValue -Object $Manifest -Name 'owner')
        desiredCount = $desired.Count
        actualCount = @($actualMap.Keys | Where-Object { $desired.ContainsKey($_) }).Count
        missing = @($desired.Keys | Where-Object { -not $actualMap.ContainsKey($_) } | Sort-Object)

        unexpected = @(Get-XmipUnexpectedName @unexpectedQuery)
        operations = [ordered]@{
            created = 0
            configured = 0
            metadataWritten = 0
            commits = 0
            pushes = 0
            skipped = 0
        }
    }
}
