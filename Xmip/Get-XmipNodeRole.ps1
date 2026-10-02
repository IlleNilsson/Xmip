#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Get-XmipNodeRoleWord {
    <#
        .SYNOPSIS
            The words a node may declare: its roles, as node::NodeRole::WORDS
            says them. Pure.

        .DESCRIPTION
            Eight roles (ADR-0056, amendments 2026-10-01): operational,
            monitoring, receiving, processing, sending, executing — the sum of
            the three before it, in one process — development, and storage,
            Xmip Storage, the doorway every other node calls. The list is
            the node crate's; this module keeps no copy and asks Xmip.Surface,
            which calls the runtime.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    Import-XmipOperatorModule

    return [string[]] @([Xmip.Surface.NodeCapability]::RoleWords)
}

function ConvertTo-XmipNodeRole {
    <#
        .SYNOPSIS
            The role words a value says, as the node binary's --role takes
            them.

        .DESCRIPTION
            A string or a list, separated by commas or by +. The words and the
            parse are the node crate's, node::NodeRole::declared (ADR-0056,
            amendments 2026-09-24 and 2026-10-01), and this module keeps no
            copy: it asks Xmip.Surface's NodeCapability, which calls that
            parse in the runtime. Each word is lowercase exactly, receiving,
            processing and sending together come back as executing, their sum,
            and an unknown word is refused before anything starts (ADR-0055) in
            that parse's own sentence. Nothing declares nothing.

        .PARAMETER Role
            What was said for one node: 'receiving', 'processing,sending',
            'executing', or a list.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Role
    )

    Import-XmipOperatorModule

    [string] $said = @(@($Role) | Where-Object { $null -ne $_ }) -join ','
    [string] $refusal = ''
    [string[]] $roles = @([Xmip.Surface.NodeCapability]::Ordered($said, [ref] $refusal))

    if ($refusal -ne '') {
        throw $refusal
    }

    return ($roles -join ',')
}

function Get-XmipNodeRole {
    <#
        .SYNOPSIS
            The roles the node called Name declares: what -NodeRole says for
            it, and nothing at all otherwise. Pure.

        .DESCRIPTION
            A node declares its roles and nothing is inferred (ADR-0056). Until
            2026-09-20 one exception stood — a name beginning with R, P or S
            was read as receive, process or send — and the owner struck it:
            *Rn, Pn and Sn are arbitrary node names.* Nowhere in Xmip does a
            letter of a name mean anything now.

            A node given no role declares none and runs the shared-directory
            tests whole, which is a real answer and not an error;
            Start-XmipTest says so in words where RoundTrip was asked for. The
            other way to have the message path covered is to omit -Nodes, and
            let the level's complement deal the roles by position.

        .PARAMETER Name
            The node's name.

        .PARAMETER NodeRole
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
        [hashtable] $NodeRole
    )

    if ($null -ne $NodeRole) {
        foreach ($key in @($NodeRole.Keys)) {
            if ($key -ieq $Name) {
                return (ConvertTo-XmipNodeRole -Role $NodeRole[$key])
            }
        }
    }

    return ''
}

function Get-XmipNodeRoleText {
    <#
        .SYNOPSIS
            The roles each node declares, as the roll reads them from
            XMIP_PLAYGROUND_NODE_ROLES: name=role+role, comma separated, nodes
            that declare nothing left out. Pure.

        .PARAMETER Nodes
            The nodes, by name.

        .PARAMETER NodeRole
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
        [hashtable] $NodeRole
    )

    [string[]] $declared = @(
        $Nodes |
            Where-Object { $null -ne $_ } |
            ForEach-Object {
                [string] $words = Get-XmipNodeRole -Name $_ -NodeRole $NodeRole

                if ($words -ne '') { "$_=$($words -replace ',', '+')" }
            }
    )

    return $declared -join ','
}

function Assert-XmipNodeRole {
    <#
        .SYNOPSIS
            Every role stated is well formed and given to a node that was
            named. Throws otherwise, before anything starts (ADR-0055).

        .PARAMETER Nodes
            The nodes, by name.

        .PARAMETER NodeRole
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
        [hashtable] $NodeRole
    )

    if ($null -eq $NodeRole) {
        return
    }

    [string[]] $strangers = @(
        $NodeRole.Keys | Where-Object { [string] $_ -notin $Nodes }
    )

    if ($strangers.Count -gt 0) {
        throw ("REFUSED: -NodeRole names $($strangers -join ', '), which -Nodes " +
            "does not; the nodes are $($Nodes -join ', ').")
    }

    foreach ($key in @($NodeRole.Keys)) {
        ConvertTo-XmipNodeRole -Role $NodeRole[$key] | Out-Null
    }
}

function Get-XmipNodeRoleRefusal {
    <#
        .SYNOPSIS
            Why RoundTrip cannot run across the nodes named, or the empty
            string when it can. Pure, and asked before anything is spawned.

        .DESCRIPTION
            RoundTrip across nodes hands every pair from a node serving
            receive to one serving process to one serving send, so each stage
            must be served somewhere: receiving, processing and sending each
            serve one, executing all three. Which stages a role serves is the
            node crate's (node::NodeRole::stages, called in the runtime). No
            node serving any stage is no refusal — the roll runs RoundTrip
            whole — and neither is a run that does not include RoundTrip. No
            -Test means every test, RoundTrip among them. The roll refuses the
            same way (test/core/playground/src/roster.rs); this says it before
            a process starts.

        .PARAMETER Nodes
            The nodes, by name.

        .PARAMETER Test
            The tests named; none named is every test.

        .PARAMETER NodeRole
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
        [hashtable] $NodeRole
    )

    [string[]] $tests = @($Test | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    if ($tests.Count -gt 0 -and 'RoundTrip' -notin $tests) {
        return ''
    }

    [string] $declared = Get-XmipNodeRoleText -Nodes $Nodes -NodeRole $NodeRole
    [string[]] $served = @(
        $declared -split ',' |
            Where-Object { $_ -ne '' } |
            ForEach-Object { [Xmip.Surface.NodeCapability]::Started($_).Stages }
    )

    if ($served.Count -eq 0) {
        return ''
    }

    [string[]] $missing = @(
        Get-XmipNodeRoleWord | Where-Object {
            [string[]] $stages = @([Xmip.Surface.NodeCapability]::Started("n=$_").Stages)
            $stages.Count -eq 1 -and $stages[0] -notin $served
        }
    )

    if ($missing.Count -eq 0) {
        return ''
    }

    return ('REFUSED. RoundTrip across nodes needs the receiving, processing and sending ' +
        "roles declared, or executing; no node declares $($missing -join ' or '). " +
        'State them with -NodeRole, one entry per node — ' +
        "-NodeRole @{ $($Nodes[0]) = 'receiving' } — or omit -Nodes and take " +
        "the level's full complement, which deals the whole path.")
}

function Get-XmipNodeRoleWarning {
    <#
        .SYNOPSIS
            What an operator who named nodes and declared nothing is about to
            get, said before anything spawns, or the empty string where there
            is nothing to say. Pure.

        .DESCRIPTION
            A node's name means nothing (the owner, 2026-09-20: Rn, Pn and Sn
            are arbitrary node names), so -Nodes alpha, beta, gamma with no
            -NodeRole is three nodes that declare no role. That is legal — they
            run the shared-directory tests whole and the roll runs RoundTrip
            itself — and it is probably not what the operator meant, so it is
            said rather than discovered (ADR-0055 clause 5). Not refused:
            running whole tests is a real answer.

        .PARAMETER Nodes
            The nodes, by name.

        .PARAMETER Test
            The tests named; none named is every test.

        .PARAMETER NodeRole
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
        [hashtable] $NodeRole
    )

    [string[]] $named = @($Nodes | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    [string[]] $tests = @($Test | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    if ($named.Count -eq 0 -or ($tests.Count -gt 0 -and 'RoundTrip' -notin $tests)) {
        return ''
    }

    [string] $declared = Get-XmipNodeRoleText -Nodes $named -NodeRole $NodeRole

    if ($declared -ne '') {
        return ''
    }

    return ("None of $($named -join ', ') declares a role, so each runs the " +
        'shared-directory tests whole and RoundTrip runs in the roll rather than ' +
        'across the nodes. A node name says nothing about what it does (ADR-0056). ' +
        "Split the message path with -NodeRole @{ $($named[0]) = 'receiving' } " +
        "and so on, or give one node 'executing', or omit -Nodes to take the " +
        "level's full complement.")
}
