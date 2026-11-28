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


function Get-XmipRunsAs {
    <#
        .SYNOPSIS
            What a run runs as, in the word of the switch Start-XmipTest was
            given: VirtualMachine, Container, or Process where neither is.
            Pure.

        .DESCRIPTION
            The switches are in parameter sets of their own, so PowerShell
            refuses two together (ADR-0028, amendment 2026-11-25); a switch
            given as $false is not given. The rolls' and the demo readiness
            check's alike.

        .PARAMETER Bound
            What Start-XmipTest was called with.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Bound
    )

    foreach ($word in 'VirtualMachine', 'Container') {
        if ([bool] $Bound[$word]) {
            return $word
        }
    }

    return 'Process'
}


function Resolve-XmipRunsAs {
    <#
        .SYNOPSIS
            What a run reads before anything is built, by what it runs as:
            nothing as local processes; on virtual machines the environment
            Deploy-XmipEnvironment recorded (Resolve-XmipVirtualMachineRun);
            in containers nothing, the refusals asked first
            (Resolve-XmipContainerRun), since the run makes its containers
            once it is built (Start-XmipSystemTestContainer).

        .DESCRIPTION
            Local processes, containers, virtual machines and physical
            machines are the ways a run is placed (ADR-0015, amendment
            2026-11-24). The rolls' and the demo readiness check's alike.

        .PARAMETER Bound
            What Start-XmipTest was called with.

        .PARAMETER Cluster
            The cluster's name, as its file declares it (Get-XmipClusterName).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Bound,

        [Parameter(Mandatory)]
        [string] $Cluster
    )

    [string] $runsAs = Get-XmipRunsAs -Bound $Bound

    if ($runsAs -eq 'Container') {
        Resolve-XmipContainerRun -Bound $Bound
        return $null
    }

    if ($runsAs -eq 'VirtualMachine') {
        return Resolve-XmipVirtualMachineRun -Bound $Bound -Cluster $Cluster
    }

    return $null
}


function Resolve-XmipContainerRun {
    <#
        .SYNOPSIS
            REFUSED, by throwing, before anything is built, a run in
            containers this host cannot make; nothing where it can.

        .DESCRIPTION
            Start-XmipTest -Container makes a container for each node and far
            end of the Reference Environment once the run is built
            (Start-XmipSystemTestContainer; ADR-0015 and ADR-0028, amendments
            2026-11-25). Refused in this order: a host with no container tool
            (Get-XmipContainerTool), naming what installs it; -Nodes,
            -NodeRole or -NodeCapability, since the containers run the file's
            every node with what it declares; a file naming no image; and no
            Linux build of this tree to give the containers
            (Get-XmipContainerBuild), naming what builds it.

        .PARAMETER Bound
            What Start-XmipTest was called with.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Bound
    )

    $null = Get-XmipContainerTool
    $layout = Get-XmipSystemTestLayout
    [string] $file = $layout.Configuration
    [string[]] $chose = @(
        'Nodes', 'NodeRole', 'NodeCapability' | Where-Object { $Bound.ContainsKey($_) }
    )

    if ($chose.Count -gt 0) {
        throw ("REFUSED. -$($chose -join ', -') belong to -Process, not -Container: the " +
            "containers run every node of $file with what it declares.")
    }

    $content = Read-XmipToml -Path $file
    $null = Get-XmipContainerImage -Content $content -File $file
    $null = Get-XmipContainerBuild -Estate $layout.Root -Content $content
}


function Resolve-XmipVirtualMachineRun {
    <#
        .SYNOPSIS
            The environment a run on virtual machines reads, as
            Read-XmipDeployedEnvironment recorded it; REFUSED, by throwing,
            before anything is built or spawned.

        .DESCRIPTION
            Start-XmipTest -VirtualMachine never makes or starts a virtual
            machine: Deploy-XmipEnvironment made them from the Reference
            Environment, and this reads what it recorded (ADR-0015 and
            ADR-0028, amendments 2026-11-25). Refused in this order: a host
            that makes no virtual machine Xmip deploys, as
            Get-XmipDeployHypervisor says it; -Nodes, -NodeRole or
            -NodeCapability, since the machines run the file's every node with
            what it declares; no environment of the cluster deployed on this
            host; and a cluster file that is not the one deployed, by its
            SHA-256. The rolls' and the demo readiness check's alike.

        .PARAMETER Bound
            What Start-XmipTest was called with.

        .PARAMETER Cluster
            The cluster's name, as its file declares it (Get-XmipClusterName).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Bound,

        [Parameter(Mandatory)]
        [string] $Cluster
    )

    $null = Get-XmipDeployHypervisor
    [string] $file = (Get-XmipSystemTestLayout).Configuration
    [string[]] $chose = @(
        'Nodes', 'NodeRole', 'NodeCapability' | Where-Object { $Bound.ContainsKey($_) }
    )

    if ($chose.Count -gt 0) {
        throw ("REFUSED. -$($chose -join ', -') belong to -Process, not -VirtualMachine: " +
            "the machines Deploy-XmipEnvironment made run every node of $file with what it " +
            'declares.')
    }

    [string] $deploy = ("Deploy-XmipEnvironment -Path $file deploys it, " +
        'in an elevated Xmip PowerShell Console on Windows; -VirtualMachine never makes or ' +
        'starts a virtual machine.')
    $deployed = Read-XmipDeployedEnvironment -Cluster $Cluster

    if ($null -eq $deployed) {
        throw "REFUSED. No environment of cluster $Cluster is deployed on this host. $deploy"
    }

    [string] $now = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()

    if ($now -ne [string] $deployed.Sha256) {
        throw ("REFUSED. The environment of cluster $Cluster was deployed from a cluster " +
            "file whose SHA-256 is $($deployed.Sha256), and $file is $now. $deploy")
    }

    return $deployed
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

    foreach ($name in 'Test', 'Nodes', 'NodeCapability', 'NodeRole') {
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

    # The Reference Environment names the cluster; nothing typed names it,
    # and a test spawns nodes, never a cluster (the owner, 2026-09-14 and
    # 2026-11-28: CT should not exist; ADR-0028, amendment 2026-11-28).
    $Choice.Cluster = Get-XmipClusterName -Path (Get-XmipSystemTestLayout).Configuration

    # What the run runs as, by the switch given; on virtual machines the
    # environment Deploy-XmipEnvironment recorded, or REFUSED (ADR-0028,
    # amendment 2026-11-25).
    $Choice.RunsAs = Get-XmipRunsAs -Bound $Choice.Bound
    $Choice.Deployed = Resolve-XmipRunsAs -Bound $Choice.Bound -Cluster $Choice.Cluster

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
