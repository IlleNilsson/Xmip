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
            line: its name, stress level, whether it may assume the internet,
            its rounds, the directory it shares with its cluster and where it
            publishes. Parent is the roll the node belongs to — the cluster
            process spawns it and the roll spawns the cluster (the owner,
            2026-09-19), so the roll is its grandparent — or null for one
            started by Start-XmipTestNode or by hand.

        .PARAMETER Name
            Only nodes whose name matches, wildcards allowed.

        .EXAMPLE
            Get-XmipTestNode

        .EXAMPLE
            Get-XmipTestNode -Name 'node-0*' | Where-Object -Property Online -EQ -Value $true
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
        Get-Process -Name 'xmip-playground-node' -ErrorAction SilentlyContinue |
            Where-Object { Test-XmipPlaygroundBinary -Process $_ -Path $layout.Node }
    )

    foreach ($process in $processes) {
        $node = ConvertTo-XmipTestNode -Process $process

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
    #>
    [CmdletBinding()]
    [OutputType('Xmip.TestNode')]
    param(
        [Parameter(Mandatory)]
        [System.Diagnostics.Process] $Process
    )

    [string] $line = try { $Process.CommandLine } catch { '' }
    [hashtable] $flags = Read-XmipTestNodeCommandLine -CommandLine "$line"
    $parent = try { $Process.Parent } catch { $null }

    # Even clusters are spawned as processes (the owner, 2026-09-19): the
    # cluster is the node's parent and the roll is the cluster's, so the roll
    # a node belongs to is one step further up than it was.
    if ($null -ne $parent -and $parent.ProcessName -eq 'xmip-playground-cluster') {
        $parent = try { $parent.Parent } catch { $null }
    }

    [bool] $ofRoll = $null -ne $parent -and $parent.ProcessName -eq 'xmip-playground-roll'

    return [PSCustomObject]@{
        PSTypeName = 'Xmip.TestNode'
        Suite      = 'Playground'
        Name       = $flags.Name
        Id         = $Process.Id
        Stress     = $flags.Stress
        Online     = $flags.Online
        Rounds     = $flags.Rounds
        Interval   = $flags.Interval
        Parent     = if ($ofRoll) { $parent.Id } else { $null }
        Shared     = $flags.Shared
        Snapshot   = $flags.Snapshot
        StartTime  = $Process.StartTime
    }
}
