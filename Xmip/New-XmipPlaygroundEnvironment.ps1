#requires -Version 7.6.5

Set-StrictMode -Version Latest

# The Playground's tests by the names a person asks for them, and the scope
# segment the roll drives and publishes each under
# (test/core/playground/src/bin/roll.rs). The owner's shape, 2026-09-12:
# Start-XmipTest -Suite Core.Playground -Test HeavyLoad. 2026-09-19, the owner: the
# old scenario wording is replaced by the test names everywhere.
[System.Collections.Specialized.OrderedDictionary] $script:XmipPlaygroundTest = [ordered]@{
    RoundTrip      = 'round-trip'
    LowLatency     = 'low-latency'
    HeavyLoad      = 'heavy-load'
    Retention      = 'retention'
    Filing         = 'filing'
    ExclusiveClaim = 'exclusive-claim'
    DailyBacklog   = 'daily-backlog'
}

function ConvertTo-XmipPlaygroundScenario {
    <#
        .SYNOPSIS
            The roll's scenario names for the tests a person named, in order.
            Wildcards select among the seven; a pattern that matches none of
            them is REFUSED, naming the tests there are.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter()]
        [AllowEmptyCollection()]
        [SupportsWildcards()]
        [string[]] $Test = @()
    )

    [string[]] $wanted = @(
        Expand-XmipTestName -Test $Test -Known @($script:XmipPlaygroundTest.Keys)
    )
    [string[]] $scenarios = @()

    foreach ($name in $wanted) {
        $scenarios += $script:XmipPlaygroundTest[$name]
    }

    return $scenarios
}

function ConvertTo-XmipTestName {
    <#
        .SYNOPSIS
            The test a person knows for a scenario the roll published; the
            scenario's own name when it is not one of the seven (a node's
            record, the cluster's rollup of its nodes).
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

<#
    .SYNOPSIS
    Why a node selection cannot be run, or '' where it can.

    .DESCRIPTION
    -Nodes names the nodes, and those names are what -NodeRole gives roles to
    and -OnlineNodes marks online; they become the run's cluster file
    (Write-XmipTestCluster). There is no count: a node is configuration, and
    configuration names it (ADR-0056, amendment 2026-10-03).

    Said at the door and before anything is built (ADR-0055), by the one
    function both Start-XmipTest and the environment ask, so they cannot
    disagree about what was asked for.

    .PARAMETER Nodes
    What -Nodes was given, or $null where it was not given at all.

    .PARAMETER OnlineNodes
    What -OnlineNodes was given.

    .PARAMETER NodeRole
    What -NodeRole was given.

    .PARAMETER Test
    What -Test was given, for the roles the path needs.

    .PARAMETER Named
    True where -Nodes was given at all, however it was given.
#>
function Get-XmipNodeSelectionRefusal {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowEmptyCollection()]
        [AllowNull()]
        [string[]] $Nodes,

        [Parameter()]
        [AllowEmptyCollection()]
        [AllowNull()]
        [string[]] $OnlineNodes,

        [Parameter()]
        [AllowNull()]
        [hashtable] $NodeRole,

        [Parameter()]
        [AllowEmptyCollection()]
        [AllowNull()]
        [string[]] $Test,

        [Parameter()]
        [switch] $Named
    )

    if ($NodeRole -and -not $Named) {
        return '-NodeRole names nodes; name them all with -Nodes first.'
    }

    if ($Named) {
        [string[]] $online = @($OnlineNodes | Where-Object { $null -ne $_ })
        Assert-XmipNodeName -Nodes $Nodes -OnlineNodes $online
        Assert-XmipNodeRole -Nodes $Nodes -NodeRole $NodeRole
    }

    # A node declares its roles (ADR-0056), and RoundTrip across nodes needs
    # receive, process and send served somewhere.
    [hashtable] $asked = @{
        Nodes    = $Nodes
        Test     = $Test
        NodeRole = $NodeRole
    }

    return Get-XmipNodeRoleRefusal @asked
}


function Assert-XmipNodeName {
    <#
        .SYNOPSIS
            The nodes a person named are well formed, distinct, and the online
            ones are among them. Throws otherwise; a node is a process, and a
            process is named once.

        .DESCRIPTION
            A node's name is the last word of its process name and so a file
            name — xmip-playground-<cluster>-node-<node> (ADR-0053, amendment
            2026-09-20) — which is why the shape is the one -Cluster takes,
            and that is the whole of it. No word is reserved: the name carries
            a node marker, so a node called roll is a node called roll (the
            owner, 2026-09-20). Refused at the door with the reason, never
            mangled into something that happens to work (ADR-0055).
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
            The variables are the roll's (test/core/playground/src/bin/roll.rs) and
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
        [string] $ClusterFile,

        [Parameter()]
        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]] $OnlineNodes,

        [Parameter()]
        [string] $Cluster,

        [Parameter()]
        [Nullable[timespan]] $Duration,

        [Parameter()]
        [Nullable[double]] $TimeFactor,

        [Parameter()]
        [string] $LoadBytes,

        [Parameter()]
        [string] $Image,

        [Parameter()]
        [switch] $Hidden,

        [Parameter(Mandatory)]
        [string] $Area
    )

    # The roll names its snapshot, history and activity in the area itself
    # (Get-XmipPlaygroundPublication asks it where).
    [hashtable] $environment = @{
        XMIP_PLAYGROUND_STRESS = $Stress.ToLowerInvariant()
        XMIP_PLAYGROUND_AREA   = $Area
    }

    # Nothing named is the whole suite (the owner, 2026-09-19), and
    # Test-XmipWholeSuite is the one place that decides it. An unset
    # XMIP_PLAYGROUND_SCENARIOS is how the roll is told so.
    if (-not (Test-XmipWholeSuite -Test $Test)) {
        [string[]] $scenarios = ConvertTo-XmipPlaygroundScenario -Test $Test
        $environment.XMIP_PLAYGROUND_SCENARIOS = $scenarios -join ','
    }

    # The named cluster: the roll's scope root and the nodes' (ADR-0028). The
    # roll refuses without one; the name is the owner's, never invented here.
    if (-not [string]::IsNullOrWhiteSpace($Cluster)) {
        $environment.XMIP_PLAYGROUND_CLUSTER = $Cluster
    }

    # The nodes are the cluster's xmip.toml, each one process declaring the
    # roles its roles key says (ADR-0056, amendment 2026-10-03): the run's
    # own, written from -Nodes and -NodeRole, or the test cluster's. The
    # variable is the one every test fixture reads.
    # With them, which may assume the internet (ADR-0045), by name: none
    # named is none online, never every node's XMIP_ONLINE.
    if (-not [string]::IsNullOrWhiteSpace($ClusterFile)) {
        $environment.XMIP_TEST_CLUSTER = $ClusterFile
        [string[]] $online = @($OnlineNodes | Where-Object { $null -ne $_ })
        $environment.XMIP_PLAYGROUND_ONLINE_NODES = $online -join ','
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

    # Where this run's per-instance images go, so the cluster process and each
    # node link one and run under a name that says which cluster and which node
    # it is (ADR-0053, amendment 2026-09-20). Unset, nothing is linked and each
    # keeps the binary's own name, which is what a roll started by hand does.
    if (-not [string]::IsNullOrWhiteSpace($Image)) {
        $environment.XMIP_PLAYGROUND_IMAGES = $Image
    }

    # A run that declares itself hidden says so to the roll, which says it in
    # its [run] table, and to the cluster and nodes it spawns, which inherit it
    # and say it in their declarations and on every audit record (ADR-0028,
    # amendment 2026-09-30). Unset, the run is shown, whatever it is called.
    if ($Hidden) {
        $environment.XMIP_PLAYGROUND_HIDDEN = 'true'
    }

    return $environment
}
