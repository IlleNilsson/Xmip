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

function Assert-XmipNodeName {
    <#
        .SYNOPSIS
            The nodes a person named are well formed, distinct, and the online
            ones are among them. Throws otherwise; a node is a process, and a
            process is named once.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter()]
        [AllowEmptyCollection()]
        [string[]] $Nodes = @(),

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]] $OnlineNodes = @()
    )

    [string[]] $every = @(@($Nodes) + @($OnlineNodes) | Where-Object { $null -ne $_ })

    foreach ($name in $every) {
        if ($name -notmatch '^[A-Za-z][A-Za-z0-9-]*$') {
            throw "A node's name is letters, digits and hyphens, starting with a letter: not $name."
        }
    }

    [string[]] $twice = @(
        $Nodes |
            Group-Object { $_.ToLowerInvariant() } |
            Where-Object -Property Count -GT -Value 1 |
            ForEach-Object { $_.Group[0] }
    )

    if ($twice.Count -gt 0) {
        throw "A node is named once: $($twice -join ', ') appear more than once in -Nodes."
    }

    [string[]] $strangers = @($OnlineNodes | Where-Object { $_ -notin $Nodes })

    if ($strangers.Count -gt 0) {
        throw "-OnlineNodes names nodes -Nodes does not: $($strangers -join ', ')."
    }
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
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]] $Nodes,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]] $OnlineNodes,

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

    # Nodes are named, not numbered (the owner, 2026-09-12): a list of names is
    # one process each; an empty list is no fleet at any level; nothing said
    # leaves the level its own numbered fleet.
    if ($null -ne $Nodes) {
        [string[]] $online = @($OnlineNodes | Where-Object { $null -ne $_ })
        Assert-XmipNodeName -Nodes $Nodes -OnlineNodes $online

        if ($Nodes.Count -eq 0) {
            $environment.XMIP_PLAYGROUND_NODES = '0'
        }
        else {
            $environment.XMIP_PLAYGROUND_NODE_NAMES = $Nodes -join ','
            $environment.XMIP_PLAYGROUND_ONLINE_NODES = $online -join ','
        }
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
