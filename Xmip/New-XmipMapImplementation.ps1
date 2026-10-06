#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    The estate map's section on what is built: one implementation state per
    user-facing capability, read from architecture.toml's [implementation].

.DESCRIPTION
    A documentation review of 2026-10-06 found documents describing decided
    behavior in the present tense where it was not built, or built and not
    in the assembled service. The owner asked for one authoritative state per
    capability, kept in one place, and a short phrase beside every promise
    pointing at it.

    The place is the manifest, because a state is a fact and ADR-0020 clause
    5 gives facts to the manifest and reasoning to documents; this renders
    it into the generated map, where `test/EstateMap.Test.ps1` holds the two
    equal. A document cites a state as a link whose text is the state and
    whose target is the entry's anchor here, and
    `test/Documentation.Test.ps1` fails a citation whose words the manifest
    does not say.

    Style: doc/governance/powershell-style.md
#>

# The four states, in the map's order, and the words a document cites them
# by. The key is what architecture.toml writes.
[System.Collections.Specialized.OrderedDictionary] $script:XmipImplementationState = [ordered]@{
    'assembled' = 'built, in the assembled service'
    'built'     = 'built, not in the assembled service'
    'decided'   = 'decided, not built'
    'open'      = 'open'
}


function Get-XmipMapImplementation {
    <#
        .SYNOPSIS
            Every [implementation] entry of the manifest, as objects.

        .DESCRIPTION
            Key, Name, State (the manifest's word), Said (the words a document
            cites), Note and Record, sorted by state in the map's order and
            then by key, so the map is the same on every machine. Throws on a
            state that is not one of the four, naming the entry.

        .PARAMETER Manifest
            The parsed manifest.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory = $true)]
        $Manifest
    )

    $table = Get-TomlValue -Node $Manifest -Name 'implementation' -Default $null

    if ($null -eq $table) {
        return @()
    }

    [string[]] $order = @($script:XmipImplementationState.Keys)
    [PSCustomObject[]] $entry = @(
        foreach ($key in @(Get-TomlKey -Node $table)) {
            $node = Get-TomlValue -Node $table -Name $key
            [string] $state = [string](Get-TomlValue -Node $node -Name 'state' -Default '')

            if ($state -notin $order) {
                throw ("architecture.toml [implementation.$key] says state = '$state'; " +
                    "it is one of: $($order -join ', ')")
            }

            [PSCustomObject] @{
                Key    = [string] $key
                Name   = [string](Get-TomlValue -Node $node -Name 'name' -Default $key)
                State  = $state
                Said   = [string] $script:XmipImplementationState[$state]
                Note   = [string](Get-TomlValue -Node $node -Name 'note' -Default '')
                Record = [string[]] @(Get-TomlValue -Node $node -Name 'record' -Default @())
            }
        }
    )

    return @(
        $entry | Sort-Object -Property @(
            @{ Expression = { [array]::IndexOf($order, $_.State) } }
            @{ Expression = { $_.Key } }
        )
    )
}


function New-XmipMapImplementation {
    <#
        .SYNOPSIS
            The map's section on what is built, one heading per entry.

        .DESCRIPTION
            Grouped by state; each entry under a heading that is its key, so
            `estate-map.md#<key>` is the anchor a document links to.

        .PARAMETER Manifest
            The parsed manifest.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        $Manifest
    )

    [PSCustomObject[]] $entry = @(Get-XmipMapImplementation -Manifest $Manifest)

    if ($entry.Count -eq 0) {
        return @()
    }

    [string] $opening = 'One state per user-facing capability, declared in the manifest''s ' +
        '`[implementation]` table: built, in the assembled service — `xmip-service`, or for ' +
        'an operator''s act the surfaces that operate it; built, not in the assembled ' +
        'service; decided, not built; or open. A document that promises one cites its ' +
        'state beside the promise, as a link to the entry here, and ' +
        '`test/Documentation.Test.ps1` fails a citation whose words the manifest does not ' +
        'say. The requirement stays in the document; this says how much of it is true ' +
        'now, and changes in the same change as the code that changes it.'

    [string[]] $line = @('## What is built', '') +
        @(Format-XmipMapLine -Text $opening -Indent '') + @('')

    foreach ($state in $script:XmipImplementationState.Keys) {
        [PSCustomObject[]] $group = @($entry | Where-Object { $_.State -eq $state })

        if ($group.Count -eq 0) {
            continue
        }

        [string] $said = [string] $script:XmipImplementationState[$state]
        $line += @("### $($said.Substring(0, 1).ToUpperInvariant())$($said.Substring(1))", '')

        foreach ($one in $group) {
            [string] $text = "**$($one.Name).** $($one.Note)"

            if ($one.Record.Count -gt 0) {
                $text += " Records: $($one.Record -join ', ')."
            }

            $line += @("#### ``$($one.Key)``", '') +
                @(Format-XmipMapLine -Text $text.Trim() -Indent '') + @('')
        }
    }

    return ($line + @('---', ''))
}
