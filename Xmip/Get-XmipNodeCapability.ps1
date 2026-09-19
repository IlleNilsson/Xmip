#requires -Version 7.6.5

Set-StrictMode -Version Latest

# The capability words a node may declare, in message-path order. The list is
# the roll's (test/playground/src/capability.rs), and ADR-0056 is the record:
# a node declares what it can do, and work is placed on a node whose
# capabilities satisfy it. The other two kinds ADR-0056 names — authentication
# and runtime capability — are not modelled in the rig.
[string[]] $script:XmipNodeCapability = @('receive', 'process', 'send')

function ConvertTo-XmipNodeCapability {
    <#
        .SYNOPSIS
            The capability words a value says, in message-path order, as the
            node binary's -can takes them. Pure.

        .DESCRIPTION
            A string or a list, separated by commas or by +. An unknown word
            is refused before anything starts (ADR-0055), naming the word and
            the values a capability would take. Nothing declares nothing.

        .PARAMETER Capability
            What was said for one node: 'receive', 'process,send', or a list.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Capability
    )

    [string[]] $words = @(
        @($Capability) |
            Where-Object { $null -ne $_ } |
            ForEach-Object { ([string] $_) -split '[,+]' } |
            ForEach-Object { $_.Trim().ToLowerInvariant() } |
            Where-Object { $_ -ne '' }
    )

    [string[]] $strangers = @($words | Where-Object { $_ -notin $script:XmipNodeCapability })

    if ($strangers.Count -gt 0) {
        throw ("REFUSED: no capability is called $($strangers -join ', '); a node " +
            "declares $($script:XmipNodeCapability -join ', '), or nothing at all.")
    }

    return (@($script:XmipNodeCapability | Where-Object { $_ -in $words }) -join ',')
}

function Get-XmipNodeCapability {
    <#
        .SYNOPSIS
            What the node called Name declares it can do: what -NodeCapability
            says for it, else the operator's shorthand on its name. Pure.

        .DESCRIPTION
            A node declares its capabilities and nothing is inferred
            (ADR-0056). The one shorthand is a convenience of this cmdlet and
            lives nowhere else: a name beginning with R, P or S, the rest
            letters and digits, is taken as receive, process or send, because
            the owner types -Nodes R1, P1, S1. -NodeCapability overrides it.
            A node neither named that way nor given a capability declares
            none and runs whole tests itself. Nothing downstream — not the
            roll, not the cluster, not a node, not a surface — reads a node's
            name.

        .PARAMETER Name
            The node's name.

        .PARAMETER NodeCapability
            What the operator stated per node, as a hashtable keyed by name.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Name,

        [Parameter()]
        [AllowNull()]
        [hashtable] $NodeCapability
    )

    if ($null -ne $NodeCapability) {
        foreach ($key in @($NodeCapability.Keys)) {
            if ($key -ieq $Name) {
                return (ConvertTo-XmipNodeCapability -Capability $NodeCapability[$key])
            }
        }
    }

    if ($Name -notmatch '^[RrPpSs][A-Za-z0-9]*$') {
        return ''
    }

    [string] $letter = $Name.Substring(0, 1).ToLowerInvariant()

    return @($script:XmipNodeCapability | Where-Object { $_.StartsWith($letter) })[0]
}

function Get-XmipNodeCapabilityText {
    <#
        .SYNOPSIS
            What each node declares, as the roll reads it from
            XMIP_PLAYGROUND_NODE_CAPABILITIES: name=capability+capability,
            comma separated, nodes that declare nothing left out. Pure.

        .PARAMETER Nodes
            The nodes, by name.

        .PARAMETER NodeCapability
            What the operator stated per node; the shorthand fills the rest.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]] $Nodes = @(),

        [Parameter()]
        [AllowNull()]
        [hashtable] $NodeCapability
    )

    [string[]] $declared = @(
        $Nodes |
            Where-Object { $null -ne $_ } |
            ForEach-Object {
                [string] $words = Get-XmipNodeCapability -Name $_ -NodeCapability $NodeCapability

                if ($words -ne '') { "$_=$($words -replace ',', '+')" }
            }
    )

    return $declared -join ','
}

function Assert-XmipNodeCapability {
    <#
        .SYNOPSIS
            Every capability stated is well formed and given to a node that
            was named. Throws otherwise, before anything starts (ADR-0055).

        .PARAMETER Nodes
            The nodes, by name.

        .PARAMETER NodeCapability
            What the operator stated per node.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]] $Nodes = @(),

        [Parameter()]
        [AllowNull()]
        [hashtable] $NodeCapability
    )

    if ($null -eq $NodeCapability) {
        return
    }

    [string[]] $strangers = @(
        $NodeCapability.Keys | Where-Object { [string] $_ -notin $Nodes }
    )

    if ($strangers.Count -gt 0) {
        throw ("REFUSED: -NodeCapability names $($strangers -join ', '), which -Nodes " +
            "does not; the nodes are $($Nodes -join ', ').")
    }

    foreach ($key in @($NodeCapability.Keys)) {
        ConvertTo-XmipNodeCapability -Capability $NodeCapability[$key] | Out-Null
    }
}

function Get-XmipNodeCapabilityRefusal {
    <#
        .SYNOPSIS
            Why RoundTrip cannot run across the nodes named, or the empty
            string when it can. Pure, and asked before anything is spawned.

        .DESCRIPTION
            RoundTrip across nodes hands every pair from a node that declared
            receive to one that declared process to one that declared send,
            so each capability must be declared somewhere. No node declaring
            any stage is no refusal — the roll runs RoundTrip whole — and
            neither is a run that does not include RoundTrip. No -Test means
            every test, RoundTrip among them. The roll refuses the same way
            (test/playground/src/roster.rs); this says it before a process
            starts.

        .PARAMETER Nodes
            The nodes, by name.

        .PARAMETER Test
            The tests named; none named is every test.

        .PARAMETER NodeCapability
            What the operator stated per node.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]] $Nodes = @(),

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]] $Test = @(),

        [Parameter()]
        [AllowNull()]
        [hashtable] $NodeCapability
    )

    [string[]] $tests = @($Test | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    if ($tests.Count -gt 0 -and 'RoundTrip' -notin $tests) {
        return ''
    }

    [string[]] $declared = @(
        $Nodes |
            Where-Object { $null -ne $_ } |
            ForEach-Object { Get-XmipNodeCapability -Name $_ -NodeCapability $NodeCapability } |
            ForEach-Object { $_ -split ',' } |
            Where-Object { $_ -ne '' }
    )

    if ($declared.Count -eq 0) {
        return ''
    }

    [string[]] $missing = @($script:XmipNodeCapability | Where-Object { $_ -notin $declared })

    if ($missing.Count -eq 0) {
        return ''
    }

    return ('REFUSED. RoundTrip across nodes needs the receive, process and send ' +
        "capability declared; no node declares $($missing -join ' or ').")
}
