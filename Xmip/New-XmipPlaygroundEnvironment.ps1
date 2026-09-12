#requires -Version 7.6.5

Set-StrictMode -Version Latest

# The Playground's tests by the names a person asks for them, and the scenario
# the roll drives for each (test/playground/src/bin/roll.rs). The owner's shape,
# 2026-09-12: Start-XmipTest -Suite Playground -Test HeavyLoad.
[System.Collections.Specialized.OrderedDictionary] $script:XmipPlaygroundTest = [ordered]@{
    RoundTrip      = 'pingpong'
    LowLatency     = 'furious'
    HeavyLoad      = 'load'
    Retention      = 'secretary'
    Filing         = 'filing'
    ExclusiveClaim = 'claim'
    DailyBacklog   = 'daily'
}

function ConvertTo-XmipPlaygroundScenario {
    <#
        .SYNOPSIS
            The roll's scenario names for the tests a person named, in order.
            Unknown names are an error naming the tests there are.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter()]
        [AllowEmptyCollection()]
        [string[]] $Test = @()
    )

    [string[]] $scenarios = @()

    foreach ($name in $Test) {
        [string] $known = $script:XmipPlaygroundTest.Keys | Where-Object { $_ -ieq $name }

        if ([string]::IsNullOrEmpty($known)) {
            [string] $names = $script:XmipPlaygroundTest.Keys -join ', '

            throw "No Playground test is named $name. The tests are $names."
        }

        $scenarios += $script:XmipPlaygroundTest[$known]
    }

    return $scenarios
}

function ConvertTo-XmipTestName {
    <#
        .SYNOPSIS
            The test a person knows for a scenario the roll published; the
            scenario's own name when it is not one of the seven (a node's
            record, the fleet's rollup).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Scenario
    )

    foreach ($name in $script:XmipPlaygroundTest.Keys) {
        if ($script:XmipPlaygroundTest[$name] -eq $Scenario) {
            return $name
        }
    }

    return $Scenario
}

function New-XmipPlaygroundEnvironment {
    <#
        .SYNOPSIS
            The environment a roll is started with: every switch the roll reads,
            as the variables it reads them from. Pure, so a test can hold it up
            against the roll's own documentation.

        .DESCRIPTION
            The variables are the roll's (test/playground/src/bin/roll.rs) and
            carry the xmip prefix because they are external names (ADR-0030).
            Only what the caller chose is set — an unset variable is the
            roll's own default, and a roll started by hand behaves the same.
            The three publish paths are always set, so a run lands where
            Get-XmipTestResult and the web host look.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Calm', 'Realistic', 'Harsh', 'Brutal')]
        [string] $Stress,

        [Parameter()]
        [string[]] $Test = @(),

        [Parameter()]
        [Nullable[int]] $Nodes,

        [Parameter()]
        [Nullable[int]] $OnlineNodes,

        [Parameter()]
        [Nullable[timespan]] $Duration,

        [Parameter()]
        [Nullable[double]] $TimeFactor,

        [Parameter()]
        [string] $LoadBytes,

        [Parameter(Mandatory)]
        [string] $Snapshot,

        [Parameter(Mandatory)]
        [string] $History,

        [Parameter(Mandatory)]
        [string] $Activity
    )

    [hashtable] $environment = @{
        XMIP_PLAYGROUND_STRESS   = $Stress.ToLowerInvariant()
        XMIP_PLAYGROUND_SNAPSHOT = $Snapshot
        XMIP_PLAYGROUND_HISTORY  = $History
        XMIP_PLAYGROUND_ACTIVITY = $Activity
    }

    if ($Test.Count -gt 0) {
        [string[]] $scenarios = ConvertTo-XmipPlaygroundScenario -Test $Test
        $environment.XMIP_PLAYGROUND_SCENARIOS = $scenarios -join ','
    }

    if ($null -ne $Nodes) {
        $environment.XMIP_PLAYGROUND_NODES = "$Nodes"
    }

    if ($null -ne $OnlineNodes) {
        $environment.XMIP_PLAYGROUND_ONLINE_NODES = "$OnlineNodes"
    }

    $invariant = [System.Globalization.CultureInfo]::InvariantCulture

    if ($null -ne $Duration) {
        [double] $seconds = ([timespan] $Duration).TotalSeconds
        $environment.XMIP_PLAYGROUND_MAX_SECONDS = $seconds.ToString($invariant)
    }

    if ($null -ne $TimeFactor) {
        $environment.XMIP_PLAYGROUND_TIME_FACTOR = ([double] $TimeFactor).ToString('R', $invariant)
    }

    if (-not [string]::IsNullOrWhiteSpace($LoadBytes)) {
        $environment.XMIP_PLAYGROUND_LOAD_BYTES = $LoadBytes
    }

    return $environment
}
