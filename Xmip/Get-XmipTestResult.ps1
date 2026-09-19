#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Get-XmipTestResult {
    <#
        .SYNOPSIS
            What an Xmip test run says now: one object per scope from the
            snapshot it publishes — suite, scenario, transport, contract, state
            and the evidence.

        .DESCRIPTION
            A snapshot is published by a roll, so what this reads is
            Core.Playground's and says so.
            Reads the snapshot TOML a roll writes after every round (ADR-0028
            clause 4: a verdict is health, per scope) and emits one object per
            record, with the scope split into what an operator filters on.
            A record under `node/<name>` is that node's, and `node` alone
            is the cluster's rollup of its nodes. A role node publishes its
            stage of RoundTrip under its name, as
            node/<name>/<stage>/<transport>/<contract> — R receives, P
            processes, S sends — and those are RoundTrip's. It reads a file
            and computes nothing but the split — the judgement is the roll's
            (ADR-0027 clause 6).

        .PARAMETER Path
            The snapshot file, or a directory holding exactly one
            `<cluster>-snapshot.toml`; with more than one cluster there, name
            the file. Defaults to `.local-work/playground` under the
            repository.

        .PARAMETER Test
            Only these tests, by the names Start-XmipTest takes: RoundTrip,
            LowLatency, HeavyLoad, Retention, Filing, ExclusiveClaim,
            DailyBacklog; or node, for the cluster's rollup of its nodes.
            Wildcards allowed, as -Node takes them.

        .PARAMETER Node
            Only records published by these nodes, wildcards allowed.

        .PARAMETER Worst
            Only the single worst record — highest severity, first by scope.

        .EXAMPLE
            Get-XmipTestResult | Where-Object -Property State -NE -Value fine

        .EXAMPLE
            Get-XmipTestResult -Test RoundTrip -Worst
    #>
    [CmdletBinding()]
    [OutputType('Xmip.TestResult')]
    param(
        [Parameter()]
        [string] $Path,

        [Parameter()]
        [SupportsWildcards()]
        [string[]] $Test,

        [Parameter()]
        [SupportsWildcards()]
        [string[]] $Node,

        [Parameter()]
        [switch] $Worst
    )

    $ErrorActionPreference = 'Stop'

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = (Get-XmipPlaygroundLayout).Area
    }

    if (Test-Path -LiteralPath $Path -PathType Container) {
        $Path = Resolve-XmipClusterFile -Directory $Path -Kind 'snapshot'
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Error "No snapshot at $Path. A roll publishes one after its first round."
        return
    }

    Import-Module PSToml -ErrorAction Stop
    $document = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Toml
    [string] $root = "$($document.node)/"

    [object[]] $results = @(
        foreach ($record in @($document.records)) {
            $result = ConvertTo-XmipTestResult -Record $record -Root $root

            if ($PSBoundParameters.ContainsKey('Test')) {
                [bool] $wanted = @($Test | Where-Object { $result.Test -like $_ }).Count -gt 0

                if (-not $wanted) {
                    continue
                }
            }

            if ($PSBoundParameters.ContainsKey('Node')) {
                [bool] $matched = @($Node | Where-Object { $result.Node -like $_ }).Count -gt 0

                if (-not $matched) {
                    continue
                }
            }

            $result
        }
    )

    if ($Worst) {
        [object[]] $order = @(@{ Expression = 'Severity'; Descending = $true }, 'Scope')

        return $results | Sort-Object -Property $order | Select-Object -First 1
    }

    return $results
}

function ConvertTo-XmipTestResult {
    <#
        .SYNOPSIS
            One snapshot record as an Xmip.TestResult, its scope split
            into scenario, node, transport and contract.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.TestResult')]
    param(
        [Parameter(Mandatory)]
        [PSObject] $Record,

        [Parameter(Mandatory)]
        [string] $Root
    )

    [string] $leaf = "$($Record.scope)"

    if ($leaf.StartsWith($Root, [System.StringComparison]::Ordinal)) {
        $leaf = $leaf.Substring($Root.Length)
    }

    [string[]] $segments = @($leaf -split '/')
    [string] $node = ''

    if ($segments.Count -ge 2 -and $segments[0] -eq 'node') {
        $node = $segments[1]
        $segments = @($segments | Select-Object -Skip 2)
    }

    # A role node publishes its stage of RoundTrip straight under its name:
    # node/R1/receive/tcp/json is RoundTrip's, as round-trip/receive/tcp/json
    # is when the roll runs the test whole.
    if ($node -ne '' -and $segments.Count -ge 1 -and
        $segments[0] -in 'receive', 'process', 'send') {
        $segments = @('round-trip') + $segments
    }

    [long] $millis = [long] ([long] $Record.observed_unix_nanos / 1000000)
    [string[]] $rest = @($segments | Select-Object -Skip 2)
    [string] $contract = $rest -join '/'
    [string] $scenario = if ($segments.Count -ge 1) { $segments[0] } else { '' }

    return [PSCustomObject]@{
        PSTypeName = 'Xmip.TestResult'
        Suite      = $script:XmipPlaygroundSuite
        Test       = ConvertTo-XmipTestName -Scenario $scenario
        Scenario   = $scenario
        Node       = $node
        Transport  = if ($segments.Count -ge 2) { $segments[1] } else { '' }
        Contract   = $contract
        State      = "$($Record.state)"
        Severity   = [int] $Record.severity
        Evidence   = "$($Record.evidence)"
        Observed   = [DateTimeOffset]::FromUnixTimeMilliseconds($millis).LocalDateTime
        Scope      = "$($Record.scope)"
    }
}
