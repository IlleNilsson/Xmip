#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Get-XmipHistory {
    <#
        .SYNOPSIS
            Reads a node's throughput history from the JSON file a producer
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
        $Path = Join-Path ([System.IO.Path]::GetTempPath()) 'playground-history.toml'
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Error "No history file at $Path. Is the playground rolling? (cargo run --bin roll)"
        return
    }

    Import-Module PSToml -ErrorAction Stop

    $document = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Toml

    [long] $sinceNanos = if ($PSBoundParameters.ContainsKey('Since')) {
        [DateTimeOffset]::new($Since).ToUnixTimeMilliseconds() * 1000000
    }
    else {
        [long]::MinValue
    }

    foreach ($point in $document.points) {
        if ($Counted -and $point.counted -ne $Counted) {
            continue
        }

        if ([long] $point.observed_unix_nanos -lt $sinceNanos) {
            continue
        }

        [long] $millis = [long] ($point.observed_unix_nanos / 1000000)

        [PSCustomObject]@{
            Node     = $document.node
            Counted  = $point.counted
            Value    = [long] $point.value
            Observed = [DateTimeOffset]::FromUnixTimeMilliseconds($millis).LocalDateTime
        }
    }
}
