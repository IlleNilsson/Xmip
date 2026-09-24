#requires -Version 7.6.5

Set-StrictMode -Version Latest

function ConvertFrom-XmipRosterText {
    <#
        .SYNOPSIS
            The nodes and the capabilities a roster text says, as -Nodes and
            -NodeCapability take them. Pure.

        .DESCRIPTION
            The text is the roll's own spelling of a roster
            (test/core/playground/src/roster.rs): name, or name=capability, or
            name=capability+capability, comma separated. Every node named is
            in the table, declaring nothing where it declared nothing, so
            nothing downstream falls back to reading a letter off a name
            (ADR-0056). An unknown word is REFUSED by
            ConvertTo-XmipNodeCapability.

        .PARAMETER Text
            The roster, as the roll writes it.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    [string[]] $nodes = @()
    [hashtable] $declared = @{}

    foreach ($entry in @($Text -split ',')) {
        [string] $one = $entry.Trim()

        if ($one -eq '') {
            continue
        }

        [string[]] $parts = @($one -split '=', 2)
        [string] $name = $parts[0].Trim()
        $nodes += $name
        $declared[$name] = if ($parts.Count -gt 1) {
            ConvertTo-XmipNodeCapability -Capability $parts[1]
        }
        else {
            ''
        }
    }

    # Whether the message path is covered: receive, process and send declared
    # somewhere among them. A complement too small to cover it declares no
    # stage at all, and the roll then runs RoundTrip whole (complement.rs).
    [string[]] $words = @(
        $declared.Values | ForEach-Object { $_ -split ',' } | Where-Object { $_ -ne '' }
    )
    [string[]] $missing = @($script:XmipNodeCapability | Where-Object { $_ -notin $words })

    return [PSCustomObject]@{
        Nodes          = $nodes
        NodeCapability = $declared
        Text           = $Text
        Covers         = ($missing.Count -eq 0)
    }
}

<#
    .SYNOPSIS
    How many nodes `-Nodes` asked for, where it asked with a number.

    .DESCRIPTION
    A node's name starts with a letter, so a lone number is no name and can
    only be a count: `-Nodes 6` is six nodes and `-Nodes east, west` is two
    named ones. The owner, 2026-09-23: *how many nodes in each cluster I
    want*.

    The nodes a count brings are the roll's to name and to deal over receive,
    process and send (`complement::of_count`) — the same dealing an omitted
    -Nodes gets — so nothing here invents either.

    Returns the count, or `-1` where this is a list of names.

    .PARAMETER Nodes
    What -Nodes was given.
#>
function Get-XmipNodeCount {
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowNull()]
        [string[]] $Nodes
    )

    [string[]] $said = @($Nodes | Where-Object { $null -ne $_ })

    if ($said.Count -ne 1 -or $said[0] -notmatch '^\d+$') {
        return -1
    }

    return [int] $said[0]
}


function Get-XmipNodeComplement {
    <#
        .SYNOPSIS
            The full complement a stress level brings: the nodes an omitted
            -Nodes means, by name, with what each declares.

        .DESCRIPTION
            An omitted selector on Start-XmipTest means the most the rig can
            give (ADR-0059, amendment 2026-09-19), so an omitted -Nodes is the
            level's own count of nodes, dealt over receive, process and send.
            How many a level brings, and how they are dealt, is the roll's to
            answer and nobody else's: the count is scaled to the machine's
            headroom, which only the rig measures. So this asks the roll
            itself — `xmip-playground-roll --roster <level>`, which prints the
            complement and starts nothing — and the answer is then handed back
            to the roll by name, so the door and the run agree on one roster
            and the run record can say what an operator got.

            Refused before anything is spawned (ADR-0055): a roll that cannot
            answer is said by name, with what it said.

        .PARAMETER Roll
            The roll binary, from Invoke-XmipPlaygroundBuild.

        .PARAMETER Stress
            The level whose complement to bring.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string] $Roll,

        [Parameter(Mandatory)]
        [ValidateSet('Calm', 'Realistic', 'Harsh', 'Brutal')]
        [string] $Stress
    )

    # The exit code is read here rather than thrown by PowerShell, so the
    # refusal names the roll and what it said instead of a code (ADR-0055).
    # Assigned in this scope alone; the caller's preference is untouched.
    $PSNativeCommandUseErrorActionPreference = $false
    [string] $level = $Stress.ToLowerInvariant()
    [string[]] $said = @(& $Roll '--roster' $level 2>&1 | ForEach-Object { "$_" })

    if ($LASTEXITCODE -ne 0) {
        throw ("REFUSED: $Roll could not say what the $level level brings " +
            "(exit $LASTEXITCODE): $($said -join ' ')")
    }

    [string] $text = if ($said.Count -gt 0) { $said[-1].Trim() } else { '' }

    return ConvertFrom-XmipRosterText -Text $text
}
