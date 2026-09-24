#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Get-XmipTestResult {
    <#
        .SYNOPSIS
            What an Xmip test run says now: one object per scope from the
            snapshot it publishes — suite, scenario, transport, contract, state
            and the evidence.

        .DESCRIPTION
            A snapshot is published by a roll, so what this reads is the
            Playground's and says so.
            Reads the snapshot TOML a roll writes after every round (ADR-0028
            clause 4: a verdict is health, per scope) through the surfaces' own
            reader, Xmip.Surface's SnapshotOperator in the operator module, and
            emits one object per record, worst first, with the scope split into
            what an operator filters on.
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
            Only the single worst record, by the order every surface ranks by
            (ScopeTree.Worst): the worse mood, then the higher severity, then
            the scope.

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

    # Read by the surfaces' own snapshot reader and ranked by the runtime's
    # worst-first order: this module keeps no reader, no mood words and no
    # ranking of its own (the owner, 2026-09-24: code is placed once).
    Import-XmipOperatorModule
    # A full path: .NET does not share this session's location.
    $surface = [Xmip.Surface.SnapshotOperator]::new((Resolve-Path -LiteralPath $Path).ProviderPath)
    [string] $root = $surface.Root()

    [object[]] $kept = @(
        foreach ($record in @($surface.Health([Xmip.Surface.ScopeTree]::Root))) {
            $result = ConvertTo-XmipTestResult -Record $record -Root $root

            if (-not (Test-XmipTestResultWanted -Result $result -Test $Test -Node $Node)) {
                continue
            }

            [PSCustomObject]@{ Record = $record; Result = $result }
        }
    )

    if ($Worst) {
        $worstRecord = [Xmip.Surface.ScopeTree]::Worst(
            [Xmip.Abi.Operate.HealthRecord[]] @($kept | ForEach-Object { $_.Record }))

        return $kept |
            Where-Object { [object]::ReferenceEquals($_.Record, $worstRecord) } |
            Select-Object -First 1 -ExpandProperty Result
    }

    return $kept | ForEach-Object { $_.Result }
}

function Test-XmipTestResultWanted {
    <#
        .SYNOPSIS
            Whether one result is among the tests and the nodes asked for:
            each list a set of wildcards, and an absent list wants all.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [PSObject] $Result,

        [Parameter()]
        [AllowNull()]
        [string[]] $Test,

        [Parameter()]
        [AllowNull()]
        [string[]] $Node
    )

    if ($null -ne $Test -and @($Test | Where-Object { $Result.Test -like $_ }).Count -eq 0) {
        return $false
    }

    return ($null -eq $Node -or @($Node | Where-Object { $Result.Node -like $_ }).Count -gt 0)
}

function ConvertTo-XmipTestResult {
    <#
        .SYNOPSIS
            One published record as an Xmip.TestResult, its scope split
            into scenario, node, transport and contract.

        .PARAMETER Record
            A Xmip.Abi.Operate.HealthRecord, as SnapshotOperator reads it.

        .PARAMETER Root
            The scope the publisher publishes at; what is beneath it is split.
    #>
    [CmdletBinding()]
    [OutputType('Xmip.TestResult')]
    param(
        [Parameter(Mandatory)]
        [PSObject] $Record,

        [Parameter(Mandatory)]
        [string] $Root
    )

    [string[]] $segments = @([Xmip.Surface.ScopeTree]::Parts($Record.Scope))

    if ([Xmip.Surface.ScopeTree]::Beneath($Record.Scope, $Root)) {
        [int] $above = [Xmip.Surface.ScopeTree]::Parts($Root).Count
        $segments = @($segments | Select-Object -Skip $above)
    }

    [string] $node = ''

    if ($segments.Count -ge 2 -and $segments[0] -eq 'node') {
        $node = $segments[1]
        $segments = @($segments | Select-Object -Skip 2)
    }

    # A node that declared a stage publishes it straight under its own name,
    # whatever that name is: node/<node>/receive/tcp/json is RoundTrip's, as
    # round-trip/receive/tcp/json is when the roll runs the test whole. The
    # stage is read from the path, by the node crate's own words, never from
    # the node's name.
    if ($node -ne '' -and $segments.Count -ge 1 -and
        [Xmip.Surface.ScopeTree]::Stages.Contains($segments[0])) {
        $segments = @('round-trip') + $segments
    }

    [string] $scenario = if ($segments.Count -ge 1) { $segments[0] } else { '' }

    return [PSCustomObject]@{
        PSTypeName = 'Xmip.TestResult'
        Suite      = $script:XmipPlaygroundSuite
        Test       = ConvertTo-XmipTestName -Scenario $scenario
        Scenario   = $scenario
        Node       = $node
        Transport  = if ($segments.Count -ge 2) { $segments[1] } else { '' }
        Contract   = @($segments | Select-Object -Skip 2) -join '/'
        State      = [Xmip.Surface.English]::Mood($Record.State)
        Severity   = [int] $Record.Severity
        Evidence   = $Record.Evidence
        Observed   = $Record.Observed.LocalDateTime
        Scope      = $Record.Scope
    }
}
