#requires -PSEdition Core
#requires -Version 7.6.5

<#
.SYNOPSIS
    What Start-XmipTest refuses and warns of for a Playground roll, before
    anything is built or spawned.

.DESCRIPTION
    Part of Start-XmipTest until 2026-09-27, when that file was 474 lines
    against the 400 the estate allows. Start-XmipTest chooses the suite;
    this checks what was asked of the Playground; Start-XmipPlaygroundRoll
    builds, spawns and records.

    Style: doc/governance/powershell-style.md
#>


function Resolve-XmipPlaygroundChoice {
    <#
        .SYNOPSIS
            The roll's arguments with -Test resolved to the tests it names,
            or $null after saying in words why the roll is refused.

        .PARAMETER Choice
            What Start-XmipTest hands Start-XmipPlaygroundRoll, Bound among it.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Choice
    )

    foreach ($name in 'Test', 'Nodes', 'OnlineNodes', 'NodeCapability', 'Cluster') {
        if (-not $Choice.ContainsKey($name)) {
            $Choice[$name] = $null
        }
    }

    # A pattern selects among the suite's tests: -Test Round* is RoundTrip and
    # -Test * is every one, which is exactly what omitting -Test means. Done
    # here so the run record carries the tests rather than the pattern, and so
    # a pattern matching nothing is refused before anything is built.
    if (Test-XmipWholeSuite -Test $Choice.Test) {
        $Choice.Test = @()
    }
    else {
        [string[]] $known = @($script:XmipPlaygroundTest.Keys)
        $Choice.Test = @(Expand-XmipTestName -Test $Choice.Test -Known $known)
    }

    if ($Choice.OnlineNodes.Count -gt 0 -and -not $Choice.Bound.ContainsKey('Nodes')) {
        Write-Error '-OnlineNodes names nodes; name them all with -Nodes first.'
        return $null
    }

    [int] $count = Get-XmipNodeCount -Nodes $Choice.Nodes
    [hashtable] $selection = @{
        Nodes          = $Choice.Nodes
        OnlineNodes    = $Choice.OnlineNodes
        NodeCapability = $Choice.NodeCapability
        Test           = $Choice.Test
        Named          = $Choice.Bound.ContainsKey('Nodes')
    }
    [string] $refused = Get-XmipNodeSelectionRefusal @selection

    if ($refused -ne '') {
        Write-Error $refused
        return $null
    }

    # You name the cluster; a test spawns nodes, never a cluster (the owner,
    # 2026-09-14). Nothing here invents a name for a roll.
    if ([string]::IsNullOrWhiteSpace($Choice.Cluster)) {
        Write-Error 'A roll is a cluster and you name it: -Cluster <name>.'
        return $null
    }

    # A count names nothing, so only names can be warned about.
    [hashtable] $asked = @{
        Nodes          = if ($count -ge 0) { $null } else { $Choice.Nodes }
        Test           = $Choice.Test
        NodeCapability = $Choice.NodeCapability
    }

    # A node's name means nothing (the owner, 2026-09-20: Rn, Pn and Sn are
    # arbitrary node names), so nodes named with no capability stated declare
    # none. That is legal and is probably not what was meant, so it is said
    # rather than discovered (ADR-0055 clause 5).
    [string] $said = Get-XmipNodeCapabilityWarning @asked

    if ($said -ne '') {
        Write-Warning $said
    }

    # A parameter nobody gave is not handed on. An unbound [timespan] is
    # $null here and a [timespan] parameter refuses $null; the roll asks
    # -Bound what was given, never whether a value is present.
    foreach ($key in @($Choice.Keys)) {
        if ($null -eq $Choice[$key]) {
            $Choice.Remove($key)
        }
    }

    return $Choice
}
