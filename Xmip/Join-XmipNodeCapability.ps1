#requires -Version 7.7.0

Set-StrictMode -Version Latest

<#
    A node's Node capabilities as the System Tests write them into a run's
    cluster file: what -NodeCapability or the System Tests' own file says
    each node's environment gives it, joined with the roles beside them
    (ADR-0056, amendment 2026-11-24). Apart from Write-XmipTestCluster.ps1
    since 2026-11-25, when that file passed 400 lines.

    Style: doc/governance/powershell-style.md
#>

function ConvertTo-XmipNodeCapability {
    <#
        .SYNOPSIS
            The Node capabilities a value of -NodeCapability says, as words:
            'online, erp-direct', 'online+erp-direct' or @('online',
            'erp-direct'). Whether each is a Node capability is the node
            crate's to say (node::Capability::node_capabilities), as the run
            reads its cluster file before anything starts.

        .PARAMETER Capability
            One node's value.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Capability
    )

    return [string[]] @(
        @($Capability) | Where-Object { $null -ne $_ } |
            ForEach-Object { ([string] $_) -split '[,+]' } |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne '' }
    )
}

function Get-XmipNodeCapabilityEntry {
    <#
        .SYNOPSIS
            Each node's Node capabilities as a run's record lists them,
            <node>=online+erp-direct, as node::Capability::declared_entry
            writes them; a node declaring none is left out.

        .PARAMETER Capability
            The Node capabilities per node, as Read-XmipTestCluster reads
            them.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter()]
        [AllowNull()]
        [System.Collections.IDictionary] $Capability
    )

    if ($null -eq $Capability) {
        return [string[]] @()
    }

    return [string[]] @(
        foreach ($node in @($Capability.Keys)) {
            [string[]] $words = @($Capability[$node] | Where-Object { $null -ne $_ })

            if ($words.Count -gt 0) {
                "$node=$($words -join '+')"
            }
        }
    )
}

function Join-XmipNodeCapability {
    <#
        .SYNOPSIS
            The Node capabilities each of -Nodes declares in a run: what
            -NodeCapability states for it, else what the System Tests' file
            declares, else none (ADR-0056, amendment 2026-11-24).

        .PARAMETER Nodes
            The run's nodes.

        .PARAMETER NodeCapability
            What -NodeCapability stated per node, or $null.

        .PARAMETER Declared
            What the System Tests' file declares per node (Read-XmipSystemTestCluster).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]] $Nodes = @(),

        [Parameter()]
        [AllowNull()]
        [hashtable] $NodeCapability,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Declared
    )

    [hashtable] $joined = @{}

    foreach ($node in @($Nodes | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        [string[]] $stated = @(
            if ($null -ne $NodeCapability -and $NodeCapability.ContainsKey($node)) {
                ConvertTo-XmipNodeCapability -Capability $NodeCapability[$node]
            }
            elseif ($Declared.Contains($node)) {
                $Declared[$node] | Where-Object { $null -ne $_ }
            }
        )

        if ($stated.Count -gt 0) {
            $joined[$node] = $stated
        }
    }

    return $joined
}
