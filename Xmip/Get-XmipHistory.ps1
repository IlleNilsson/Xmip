#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Get-XmipHistory {
    <#
        .SYNOPSIS
            Reads a node's throughput history from the JSON file a producer
            publishes, one object per point.

        .DESCRIPTION
            The CLI's history surface, ADR-0029. The Xmip Playground (and, later,
            a running node) publishes its throughput over time as a JSON file —
            transport, never configuration, per the estate rule that JSON lives
            in memory or on the wire and TOML configures. This reads that file
            and emits one object per point, so an operator without a browser sees
            the same curve the UI draws, and can pipe it to Format-Table,
            Export-Csv or a chart.

            It reads a file and computes nothing: the history is what the
            producer retained, the same as the operator boundary (ADR-0027
            clause 6).

        .PARAMETER Path
            The history file to read. Defaults to the well-known temp file the
            playground writes to, so no argument is needed while it rolls.

        .PARAMETER Counted
            Limit to one kind — streams, messages or bytes. Omit for all three.

        .PARAMETER Since
            Only points at or after this time. Omit for the whole retained
            window.

        .EXAMPLE
            Get-XmipHistory -Counted bytes | Format-Table -AutoSize

        .EXAMPLE
            Get-XmipHistory -Since (Get-Date).AddMinutes(-5)
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string] $Path,

        [Parameter()]
        [ValidateSet('streams', 'messages', 'bytes')]
        [string] $Counted,

        [Parameter()]
        [datetime] $Since
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Join-Path ([System.IO.Path]::GetTempPath()) 'xmip-playground-history.json'
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Error "No history file at $Path. Is the playground rolling? (cargo run --bin roll)"
        return
    }

    $document = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json

    [string[]] $kinds = if ($Counted) { @($Counted) } else { @('streams', 'messages', 'bytes') }

    [long] $sinceNanos = if ($PSBoundParameters.ContainsKey('Since')) {
        [DateTimeOffset]::new($Since).ToUnixTimeMilliseconds() * 1000000
    }
    else {
        [long]::MinValue
    }

    foreach ($kind in $kinds) {
        if (-not ($document.series.PSObject.Properties.Name -contains $kind)) {
            continue
        }

        foreach ($point in $document.series.$kind) {
            if ([long] $point.observedUnixNanos -lt $sinceNanos) {
                continue
            }

            [long] $millis = [long] ($point.observedUnixNanos / 1000000)

            [PSCustomObject]@{
                Node     = $document.node
                Counted  = $kind
                Value    = [long] $point.value
                Observed = [DateTimeOffset]::FromUnixTimeMilliseconds($millis).LocalDateTime
            }
        }
    }
}
