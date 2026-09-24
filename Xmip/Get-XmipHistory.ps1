#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Get-XmipHistory {
    <#
        .SYNOPSIS
            Reads a node's throughput history from the TOML file a producer
            publishes, one object per point.

        .DESCRIPTION
            The CLI's history surface, ADR-0029. The Xmip Playground (and, later,
            a running node) publishes its throughput over time as a TOML file —
            on disk the estate is TOML, and JSON is reserved for memory and the
            wire. This reads that file and emits one object per point, so an
            operator without a browser sees the same curve the UI draws, and can
            pipe it to Format-Table, Export-Csv or a chart.

            It reads a file and computes nothing: the history is what the
            producer retained, the same as the operator boundary (ADR-0027
            clause 6). The file's shape is observe::Curve's, and it is read by
            the runtime's one reader through the operator module
            (xmip_operate.h section 8); this function walks no TOML and names no
            counted word of its own (the owner, 2026-09-24: code is placed
            once).

        .PARAMETER Path
            The history file to read, or a directory holding one cluster's
            history file, `<cluster>-history.toml`. Defaults to the run area,
            `.local-work/playground` under the repository, so no argument is
            needed while one cluster rolls.

        .PARAMETER Counted
            Limit to one kind, by the word the runtime calls it — a history
            carries streams, messages and bytes. Omit for all three. A word that
            names no kind is refused.

        .PARAMETER Since
            Only points at or after this time. Omit for the whole retained
            window.

        .EXAMPLE
            Get-XmipHistory -Counted bytes | Format-Table -AutoSize

        .EXAMPLE
            Get-XmipHistory -Since (Get-Date).AddMinutes(-5)
    #>
    [CmdletBinding()]
    [OutputType('Xmip.History')]
    param(
        [Parameter()]
        [string] $Path,

        [Parameter()]
        [string] $Counted,

        [Parameter()]
        [datetime] $Since
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = (Get-XmipPlaygroundLayout).Area
    }

    if (Test-Path -LiteralPath $Path -PathType Container) {
        $Path = Resolve-XmipClusterFile -Directory $Path -Kind 'history'
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Error "No history file at $Path. A roll writes one after its first round."
        return
    }

    Import-XmipOperatorModule

    [string[]] $words = @(
        [enum]::GetValues([Xmip.Abi.Operate.Counted]) |
            ForEach-Object { [Xmip.Surface.English]::Kind($_) }
    )

    if ($Counted -and $Counted -cnotin $words) {
        Write-Error ("REFUSED: no counted kind is called $Counted; the kinds are " +
            "$($words -join ', ').")
        return
    }

    [string] $refusal = ''
    $points = [Xmip.Surface.RuntimeLibrary]::Rules.Publications.Curve(
        (Get-Content -LiteralPath $Path -Raw), [ref] $refusal)

    if ($null -eq $points) {
        Write-Error "The history at $Path is not one: $refusal"
        return
    }

    # A file with no points at all is the producer's fault, not the reader's,
    # and it is said rather than answered with silence (ADR-0055). Every
    # history the Playground published between 2026-09-05 and 2026-09-19 was
    # one of these, and nobody noticed because nothing said anything.
    if ($points.Count -eq 0) {
        Write-Warning "The history at $Path holds no points; its producer wrote none."
        return
    }

    foreach ($point in $points) {
        [string] $kind = [Xmip.Surface.English]::Kind($point.Counted)

        if ($Counted -and $kind -cne $Counted) {
            continue
        }

        if ($PSBoundParameters.ContainsKey('Since') -and
            $point.Observed -lt [DateTimeOffset]::new($Since)) {
            continue
        }

        [PSCustomObject]@{
            PSTypeName = 'Xmip.History'
            Node       = $point.Scope
            Counted    = $kind
            Value      = [long] $point.Value
            Observed   = $point.Observed.LocalDateTime
        }
    }
}
