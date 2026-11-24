#requires -PSEdition Core
#requires -Version 7.7.0

<#
.SYNOPSIS
    What Start-XmipTest refuses and warns of for a System Tests roll, before
    anything is built or spawned.

.DESCRIPTION
    Part of Start-XmipTest until 2026-09-27, when that file was 474 lines
    against the 400 the estate allows. Start-XmipTest chooses the suite;
    this checks what was asked of the System Tests; Start-XmipSystemTestRoll
    builds, spawns and records.

    Style: doc/governance/powershell-style.md
#>


function Get-XmipMachineChoiceRefusal {
    <#
        .SYNOPSIS
            Why a roll's -Certificate is refused, or the empty string. Pure.

        .DESCRIPTION
            The Systems Tests ask every node's machine with the operator
            certificate -Certificate names, so they need one; the System Tests
            run every node on this computer and ask nothing, so one given them
            is a choice they cannot honor. Refused before anything is built
            (ADR-0055 clause 2; ADR-0028, amendment 2026-11-23).

        .PARAMETER Machines
            Whether the suite chosen runs on an environment's machines.

        .PARAMETER Bound
            What Start-XmipTest was called with.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [bool] $Machines,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Bound
    )

    [bool] $given = $Bound.ContainsKey('Certificate')

    if ($Machines -and -not $given) {
        return ("REFUSED. $script:XmipSystemsTestSuite asks every node's machine with an " +
            'operator certificate: name its folder with -Certificate.')
    }

    if ($given -and -not $Machines) {
        return ("REFUSED. -Certificate belongs to $script:XmipSystemsTestSuite, not " +
            "$script:XmipSystemTestSuite, which runs every node here and asks no machine.")
    }

    return ''
}


function Resolve-XmipSystemTestChoice {
    <#
        .SYNOPSIS
            The roll's arguments with -Test resolved to the tests it names,
            or $null after saying in words why the roll is refused.

        .PARAMETER Choice
            What Start-XmipTest hands Start-XmipSystemTestRoll, Bound among it.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Choice
    )

    # A switch of another of Xmip's suites, -Tester, is refused by name.
    [hashtable] $switches = @{ Kind = 'roll'; Bound = $Choice.Bound; Chosen = $Choice.Suite }
    [string] $foreign = Get-XmipSuiteSwitchRefusal @switches

    if ($foreign -ne '') {
        Write-Error $foreign
        return $null
    }

    # The Systems Tests ask every node's machine with -Certificate's; the
    # System Tests ask no machine (ADR-0028, amendment 2026-11-23).
    [hashtable] $where = @{ Machines = [bool] $Choice.Machines; Bound = $Choice.Bound }
    [string] $machine = Get-XmipMachineChoiceRefusal @where

    if ($machine -ne '') {
        Write-Error $machine
        return $null
    }

    foreach ($name in 'Test', 'Nodes', 'NodeCapability', 'NodeRole', 'Cluster') {
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
        [string[]] $known = @($script:XmipScenarioOfTest.Keys)
        $Choice.Test = @(Expand-XmipTestName -Test $Choice.Test -Known $known)
    }

    [hashtable] $selection = @{
        Nodes          = $Choice.Nodes
        NodeCapability = $Choice.NodeCapability
        NodeRole       = $Choice.NodeRole
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

    # A node named with no role states the roles the System Tests' own file
    # declares for it (ADR-0028, amendment 2026-10-21).
    if ($Choice.Bound.ContainsKey('Nodes')) {
        [hashtable] $joined = @{
            Nodes    = $Choice.Nodes
            NodeRole = $Choice.NodeRole
            Declared = (Read-XmipSystemTestCluster).Role
        }
        $Choice.NodeRole = Join-XmipNodeRole @joined
    }

    # The nodes named; the System Tests file's are asked where they are read
    # (Start-XmipSystemTestRoll).
    [hashtable] $asked = @{
        Nodes    = $Choice.Nodes
        Test     = $Choice.Test
        NodeRole = $Choice.NodeRole
    }

    # A node's name means nothing (the owner, 2026-09-20: Rn, Pn and Sn are
    # arbitrary node names), so nodes named with no role stated declare
    # none. That is legal and is probably not what was meant, so it is said
    # rather than discovered (ADR-0055 clause 5).
    [string] $said = Get-XmipNodeRoleWarning @asked

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
