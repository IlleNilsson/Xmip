#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Get-XmipTestResult {
    <#
        .SYNOPSIS
            What an Xmip test run says now: one object per scope from the
            snapshot it publishes — suite, scenario, transport, contract, state
            and the evidence.

        .DESCRIPTION
            The Playground is the one suite today, and a run of it is a roll.
            Reads the snapshot TOML a roll writes after every round (ADR-0028
            clause 4: a verdict is health, per scope) and emits one object per
            record, with the scope split into what an operator filters on.
            A record under `node/<name>` is a fleet node's; `fleet` is the
            fleet's own rollup. It reads a file and computes nothing but the
            split — the judgement is the roll's (ADR-0027 clause 6).

        .PARAMETER Path
            The snapshot file, or the directory holding
            `playground-snapshot.toml`. Defaults to the running roll's, else
            `.local-work/playground` under the repository.

        .PARAMETER Scenario
            Only these scenarios: pingpong, furious, load, secretary, filing,
            claim, daily, fleet, or a node's scenario.

        .PARAMETER Node
            Only records published by these fleet nodes, wildcards allowed.

        .PARAMETER Worst
            Only the single worst record — highest severity, first by scope.

        .EXAMPLE
            Get-XmipTestResult | Where-Object State -ne fine

        .EXAMPLE
            Get-XmipTestResult -Scenario pingpong -Worst
    #>
    [CmdletBinding()]
    [OutputType('Xmip.TestResult')]
    param(
        [Parameter()]
        [string] $Path,

        [Parameter()]
        [string[]] $Scenario,

        [Parameter()]
        [SupportsWildcards()]
        [string[]] $Node,

        [Parameter()]
        [switch] $Worst
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = (Get-XmipPlaygroundLayout).Area
    }

    if (Test-Path -LiteralPath $Path -PathType Container) {
        $Path = Join-Path -Path $Path -ChildPath 'playground-snapshot.toml'
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

            if ($PSBoundParameters.ContainsKey('Scenario') -and $result.Scenario -notin $Scenario) {
                continue
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

    [long] $millis = [long] ([long] $Record.observed_unix_nanos / 1000000)
    [string[]] $rest = @($segments | Select-Object -Skip 2)
    [string] $contract = $rest -join '/'

    return [PSCustomObject]@{
        PSTypeName = 'Xmip.TestResult'
        Suite      = 'Playground'
        Scenario   = if ($segments.Count -ge 1) { $segments[0] } else { '' }
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
