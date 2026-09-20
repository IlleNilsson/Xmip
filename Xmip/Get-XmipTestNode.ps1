#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Get-XmipTestNode {
    <#
        .SYNOPSIS
            The emulated node processes running on this machine — a roll's
            nodes and the ones started by hand — one object each.

        .DESCRIPTION
            A node is a process running the Playground's own node binary
            (ADR-0028 clause 2). What it is doing is read from its command
            line: its name, stress level, what it declared it can do, whether
            it may assume the internet, its rounds, the directory it shares
            with its cluster and where it publishes. Parent is the roll the
            node belongs to — the cluster process spawns it and the roll
            spawns the cluster (the owner, 2026-09-19), so the roll is its
            grandparent — or null for one started by Start-XmipTestNode or by
            hand.

            Capability is the feature capability the node declared (ADR-0056),
            in the words -NodeCapability takes them: 'receive',
            'process,send', or empty for a node that declared no stage and
            runs whole tests itself. Online is the online capability of the
            same record. The Playground models neither authentication nor
            runtime capability, so neither is here.

        .PARAMETER Name
            Only nodes whose name matches, wildcards allowed.

        .EXAMPLE
            Get-XmipTestNode

        .EXAMPLE
            Get-XmipTestNode -Name 'node-0*' | Where-Object -Property Online -EQ -Value $true

        .EXAMPLE
            Get-XmipTestNode | Where-Object -Property Capability -Match -Value 'send'
    #>
    [CmdletBinding()]
    [OutputType('Xmip.TestNode')]
    param(
        [Parameter()]
        [SupportsWildcards()]
        [string] $Name = '*'
    )

    $ErrorActionPreference = 'Stop'
    $layout = Get-XmipPlaygroundLayout

    [System.Diagnostics.Process[]] $processes = @(
        Get-XmipPlaygroundProcess -Name 'xmip-playground-*' -Path $layout.Node -Kind Node
    )

    [hashtable] $declared = Read-XmipProcessDeclaration -Path (Get-XmipProcessDirectory)

    foreach ($process in $processes) {
        $node = ConvertTo-XmipTestNode -Process $process -Declared $declared

        if ($node.Name -like $Name) {
            $node
        }
    }
}

function ConvertTo-XmipTestNode {
    <#
        .SYNOPSIS
            One node process as the Xmip.TestNode object every node
            cmdlet emits.

        .PARAMETER Process
            The node process.

        .PARAMETER Declared
            What the processes on this machine declared, by pid, when the
            caller has already read them (ADR-0053). Read here otherwise.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.TestNode')]
    param(
        [Parameter(Mandatory)]
        [System.Diagnostics.Process] $Process,

        [Parameter()]
        [hashtable] $Declared
    )

    [string] $line = try { $Process.CommandLine } catch { '' }
    [hashtable] $flags = Read-XmipTestNodeCommandLine -CommandLine "$line"
    [hashtable] $known = if ($null -ne $Declared) {
        $Declared
    }
    else {
        Read-XmipProcessDeclaration -Path (Get-XmipProcessDirectory)
    }
    $parent = try { $Process.Parent } catch { $null }

    # Even clusters are spawned as processes (the owner, 2026-09-19): the
    # cluster is the node's parent and the roll is the cluster's, so the roll
    # a node belongs to is one step further up than it was.
    #
    # A parent is named by its pid and never by the file its image came from:
    # this machine calls a parent by the file's current name, so rebuilding the
    # binaries under a running roll renamed every parent, no node had a roll,
    # and Stop-XmipTest left three of them running (2026-09-19).
    [int] $above = if ($null -ne $parent) { $parent.Id } else { 0 }

    # Judged by which of the three the name is, never by the whole name: since
    # 2026-09-20 a process carries its cluster, so xmip-playground-V1-cluster
    # is the cluster of V1 and xmip-playground-cluster is one nobody named. A
    # node called cluster is xmip-playground-V1-node-cluster and is neither.
    [string] $named = Resolve-XmipProcessName -Id $above -Declared $known

    if ((Get-XmipPlaygroundImageKind -Name $named) -eq 'Cluster') {
        $parent = try { $parent.Parent } catch { $null }
        $above = if ($null -ne $parent) { $parent.Id } else { 0 }
        $named = Resolve-XmipProcessName -Id $above -Declared $known
    }

    [bool] $ofRoll = (Get-XmipPlaygroundImageKind -Name $named) -eq 'Roll'

    return [PSCustomObject]@{
        PSTypeName = 'Xmip.TestNode'
        Suite      = $script:XmipPlaygroundSuite
        Name       = $flags.Name
        Id         = $Process.Id
        Stress     = $flags.Stress
        Capability = $flags.Capability
        Online     = $flags.Online
        Rounds     = $flags.Rounds
        Interval   = $flags.Interval
        Parent     = if ($ofRoll) { $above } else { $null }
        Shared     = $flags.Shared
        Snapshot   = $flags.Snapshot
        StartTime  = $Process.StartTime
    }
}
