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
            says for it, and nothing at all otherwise. Pure.

        .DESCRIPTION
            A node declares its capabilities and nothing is inferred
            (ADR-0056). Until 2026-09-20 this cmdlet kept one exception — a
            name beginning with R, P or S was read as receive, process or send
            — and the owner struck it: *Rn, Pn and Sn are arbitrary node
            names.* Nowhere in Xmip does a letter of a name mean anything now.

            A node given no capability declares none and runs the
            shared-directory tests whole, which is a real answer and not an
            error; Start-XmipTest says so in words where RoundTrip was asked
            for. The other way to have the message path covered is to omit
            -Nodes, and let the level's complement deal the capabilities by
            position.

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

    return ''
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
            What the operator stated per node. A node it does not name
            declares nothing, and is left out.
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
        "capability declared; no node declares $($missing -join ' or '). " +
        'State it with -NodeCapability, one entry per node — ' +
        "-NodeCapability @{ $($Nodes[0]) = 'receive' } — or omit -Nodes and take " +
        "the level's full complement, which deals the whole path.")
}

function Get-XmipNodeCapabilityWarning {
    <#
        .SYNOPSIS
            What an operator who named nodes and declared nothing is about to
            get, said before anything spawns, or the empty string where there
            is nothing to say. Pure.

        .DESCRIPTION
            A node's name means nothing (the owner, 2026-09-20: Rn, Pn and Sn
            are arbitrary node names), so -Nodes R1, P1, S1 with no
            -NodeCapability is three nodes that declare no stage. That is
            legal — they run the shared-directory tests whole and the roll runs
            RoundTrip itself — and it is probably not what the operator meant,
            so it is said rather than discovered (ADR-0055 clause 5). Not
            refused: running whole tests is a real answer.

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

    [string[]] $named = @($Nodes | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    [string[]] $tests = @($Test | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    if ($named.Count -eq 0 -or ($tests.Count -gt 0 -and 'RoundTrip' -notin $tests)) {
        return ''
    }

    [string] $declared = Get-XmipNodeCapabilityText -Nodes $named -NodeCapability $NodeCapability

    if ($declared -ne '') {
        return ''
    }

    return ("None of $($named -join ', ') declares a stage, so each runs the " +
        'shared-directory tests whole and RoundTrip runs in the roll rather than ' +
        'across the nodes. A node name says nothing about what it does (ADR-0056). ' +
        "Split the message path with -NodeCapability @{ $($named[0]) = 'receive' } " +
        "and so on, or omit -Nodes to take the level's full complement.")
}
