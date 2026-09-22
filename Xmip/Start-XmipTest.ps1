#requires -Version 7.6.5

Set-StrictMode -Version Latest

function Start-XmipTest {
    <#
        .SYNOPSIS
            Starts one run of an Xmip test suite, detached, with the stress,
            tests, nodes and limits you choose. Nothing starts unless you
            call this.

        .DESCRIPTION
            Xmip provides its tests as suites, and -Suite says which one runs.
            A suite carries the provider who publishes it, exactly as a module
            does (ADR-0011): Core.Playground is a roll that runs detached
            until you stop it, Get-XmipTestStatus says what runs and
            Stop-XmipTest ends it; Core.Estate is the Pester suite under
            test/, the estate's memory of every past defect, which runs here
            and now, says OK or FAILED and returns the Pester result.
            A third party's suite is <Provider>.<Name> and joins by a
            declaration rather than by an edit to Xmip.

            The Playground (ADR-0028) is the estate's integration test over
            time: a roll drives every scenario round after round and publishes
            a snapshot, a history and the recent activity as TOML files a
            monitor reads. This starts exactly one roll as a background
            process, hands it every switch through its own environment — your
            session's environment is untouched — and writes a run record beside
            the snapshot so Get-XmipTestStatus can say what is running and
            Stop-XmipTest can end it, nodes first.

            A roll spawns one cluster process and the cluster spawns one
            process per node (the owner, 2026-09-19: even clusters have to be
            spawned as processes during tests). Get-XmipProcess shows all
            three kinds with the location and purpose each declared, and
            Stop-XmipTest ends the tree from the leaves up.

            The roll, cluster and node binaries are built first, a no-op when
            they are current, so a roll never runs yesterday's scenarios. The
            roll's own output goes
            to `roll-<start time>.log` and `.err` under -Path, one line per
            round; the run record `roll-<pid>.toml` beside them says which log
            is whose.

        .PARAMETER Suite
            Which test suite to run: Core.Playground (the default) or
            Core.Estate, which are Xmip's own. Every suite is
            <Provider>.<Name> and core is the reserved provider that means
            Xmip itself (ADR-0011), so Core.Playground is how the Playground
            is spelled — in the run record, in every refusal and on every
            surface. A bare Playground is still accepted and resolves to it,
            so nothing typed before this means anything else now. A third
            party's suite carries its own provider: <Provider>.<Name>. Case
            does not matter. The Playground parameters below belong to the
            Playground alone.

            Wildcards select a group, exactly as -Test does (the owner,
            2026-09-19): -Suite * is every suite this estate knows, -Suite
            *Play* is the Playground, and a literal name is one suite as
            before. A pattern matching nothing is REFUSED, naming it and the
            suites there are, before anything starts.

            Several suites matched run one after another in the order they
            are listed, each returning what it returns — the Playground a
            detached roll that comes back at once, the estate a Pester run
            that blocks, a provider's whatever its command gives — so a
            caller reads the stream by type. It is said in words which are
            about to run and which did not start; one suite failing to start
            never stops the rest. A switch that belongs to one suite alone is
            not a fault when a pattern chose the group: -Suite * -Cluster Z3
            rolls on Z3 and runs the estate's Pester files beside it.

            A third party adds a suite by dropping a declaration in
            test/suite, with no edit to Xmip's own source. Example stands in
            for whatever it calls itself; the estate names no placeholder
            company (ADR-0059, amendment 2026-09-20):

                provider = "Example"
                name     = "Playground"
                command  = "Start-ExampleXmipTest"

            Start-XmipTest hands that command everything it was given beside
            -Suite. A declaration missing any of the three, or claiming the
            reserved provider core, is REFUSED by name.

        .PARAMETER Stress
            How hard: Calm, Realistic, Harsh or Brutal. Omit it and the roll
            runs at Brutal, the hardest level there is: an omitted selector
            means the most the rig can give (ADR-0059, amendment 2026-09-19,
            where the rule and the owner's words live). Naming a level pins
            it, so -Stress Calm is calm.

        .PARAMETER Test
            Which tests of the suite to run. Omit it, for any suite and any
            provider, and the whole suite runs (the owner, 2026-09-19). The
            Playground's are RoundTrip, LowLatency, HeavyLoad, Retention,
            Filing, ExclusiveClaim and DailyBacklog. The estate's are its
            Pester files by name: Allocation, Decision, Rust.Style, XmipTest
            and the rest of test/. Tab completes either.

            Wildcards select a group: -Test Round* is RoundTrip, -Test * is
            every test and says the same as omitting it. A pattern that
            matches nothing is REFUSED, naming it and the tests there are,
            before anything starts. Wildcards, not regular expressions —
            Rust.Style is a test name and the dot in it is a dot.

        .PARAMETER Rounds
            Run this many rounds and stop. Omit, or 0, to roll until stopped.

        .PARAMETER Duration
            A wall-clock ceiling; the roll stops when it is reached whatever
            the round count.

        .PARAMETER TimeFactor
            The factor on simulated time: 1 is real time, below 1 runs the
            simulated clock faster (the Retention test ages on it).

        .PARAMETER Nodes
            The nodes to simulate, by name — one process each, spawned by the
            roll's cluster process, so -Nodes alpha, beta, gamma is three node
            processes called that under one cluster called -Cluster. What
            each node does is the capability it is started with (ADR-0056),
            stated with -NodeCapability. A name says nothing about it: the
            owner, 2026-09-20, *Rn, Pn and Sn are arbitrary node names*, and
            the one shorthand this cmdlet used to keep is gone. A node given
            no capability declares none and runs the shared-directory tests
            whole, which is said in words where RoundTrip was asked for.
            RoundTrip across nodes hands each pair from receive to process to
            send between the processes, so each capability must be declared
            somewhere; it is REFUSED otherwise, naming the capability, before
            anything starts. An empty list, @(), is no nodes at any level.

            A node's name is also the last word of its process name —
            xmip-playground-<cluster>-node-<node> (ADR-0053, amendment
            2026-09-20) — so it takes the shape -Cluster takes, and that is
            all: no word is reserved, and a node called roll is a node called
            roll. Anything a file cannot be called is REFUSED before a process
            starts.

            Omit it and the level brings its full complement (ADR-0059,
            amendment 2026-09-19): its own count of nodes — one, three, ten or
            forty, scaled to the machine's headroom — named node-01 up and
            dealt receive, process, send and round again, so the message path
            is covered and the run never refuses a roster it composed itself.
            A level with fewer than three nodes cannot cover the path; those
            nodes declare no stage, RoundTrip runs whole in the roll, and it
            is said. The run record and the [run] table carry the nodes that
            were resolved.

        .PARAMETER NodeCapability
            What each node declares it can do, stated per node: -Nodes alpha,
            beta -NodeCapability @{ alpha = 'receive'; beta = 'process,send' }.
            The values are receive, process and send, one or more, separated
            by commas or by plus; an unknown word, or a node -Nodes does not
            name, is REFUSED before anything starts. A node the table does not
            name declares nothing. This is the only way a named node gets a
            capability; omit -Nodes instead and the level's complement deals
            them over the whole message path. ADR-0056 names two further kinds
            of capability, authentication and runtime, which the Playground
            does not model.

        .PARAMETER OnlineNodes
            Which of the named nodes may assume a route to the internet
            (ADR-0045) — the online capability of ADR-0056, by name. None
            unless said; each must be in -Nodes.

        .PARAMETER Cluster
            The cluster this roll starts (ADR-0028), by the name you give it
            — required: you name the cluster, and a test spawns a cluster and
            its nodes, never invents a name for one (the owner, 2026-09-14
            and 2026-09-19). The
            scope root is xmip:///<Cluster> and the run publishes to
            <Cluster>-snapshot.toml beside its history and activity. Any name
            a file can carry will do, and none of them means anything to
            Xmip. Two rolls with two names are two clusters side by side,
            each with its own web GUI:
            Start-XmipTest -Cluster orders -PassThru | Start-XmipOperationWeb -Url ...

        .PARAMETER LoadBytes
            The HeavyLoad test's payload: a number or a size like 512mb or 2gb.
            Omit for a megabyte.

        .PARAMETER Path
            Playground: where the run writes — snapshot, history, activity,
            run record and the roll's own log; defaults to
            `.local-work/playground` under the repository. Estate: the
            directory of Pester tests; defaults to test/ under the repository.

        .PARAMETER PassThru
            Return the Xmip.TestStatus object for the roll started.

        .EXAMPLE
            Start-XmipTest -Suite Core.Playground -Cluster C1

        .EXAMPLE
            Start-XmipTest -Suite Core.Playground -Cluster C1 -Test HeavyLoad -Stress Harsh

        .EXAMPLE
            Start-XmipTest -Suite Core.Playground -Cluster C1 -Nodes alpha, beta -PassThru |
                Start-XmipOperationWeb

        .EXAMPLE
            Start-XmipTest -Test RoundTrip -Cluster orders -Nodes east, west, mill, quay
                -OnlineNodes east, quay -NodeCapability @{ east = 'receive'
                    west = 'receive'; mill = 'process'; quay = 'send' }

        .EXAMPLE
            Start-XmipTest -Test RoundTrip -Cluster north -Nodes alpha, beta, gamma
                -NodeCapability @{ alpha = 'receive'; beta = 'process'; gamma = 'send' }

        .EXAMPLE
            Start-XmipTest -Suite Core.Estate -Test Rust.Style, XmipTest

        .EXAMPLE
            Start-XmipTest -Cluster nightly -Duration 00:15:00 -TimeFactor 9.5e-6 -WhatIf

        .EXAMPLE
            Start-XmipTest -Suite Core.Estate

        .EXAMPLE
            (Start-XmipTest -Suite Core.Estate).Failed | Format-Table ExpandedPath

        .EXAMPLE
            Start-XmipTest -Suite Example.Playground -Cluster orders

        .EXAMPLE
            Start-XmipTest -Suite Core.Estate -Test Sync-Xmip*

        .EXAMPLE
            Start-XmipTest -Suite * -Cluster orders

        .EXAMPLE
            Start-XmipTest -Suite *Play* -Cluster orders
    #>
    [CmdletBinding(SupportsShouldProcess, PositionalBinding = $false)]
    [OutputType('Xmip.TestStatus', 'Pester.Run')]
    param(
        # The sentence is "start the Playground's HeavyLoad": suite first, then
        # the tests, and nothing else by position (the owner, 2026-09-12).
        #
        # Neither the set nor the shape is declared here (ADR-0055 clauses 1
        # and 2; ADR-0059, amendment 2026-09-19): a provider's suite is
        # declared, not compiled in, so no ValidateSet can know it, and a
        # ValidatePattern's refusal reaches the operator wrapped in
        # PowerShell's own words. The completer offers the ones there are;
        # the body refuses the rest, in the estate's words.
        [Parameter(Position = 0)]
        [SupportsWildcards()]
        [ArgumentCompleter({
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            # A completer runs in the caller's scope and not the module's, so
            # the suites are asked of the module itself. The -Test completer
            # below calls straight out because Get-XmipRepositoryRoot is
            # exported and Get-XmipTestSuite deliberately is not: a suite is a
            # parameter of Start-XmipTest, never a cmdlet of its own.
            $module = Get-Module -Name Xmip | Select-Object -First 1

            if ($null -eq $module) {
                return
            }

            & $module { Get-XmipTestSuite } |
                ForEach-Object { $_.Name } |
                Where-Object { $_ -like "$wordToComplete*" }
        })]
        [string] $Suite = 'Core.Playground',

        # The hardest level, because an omitted selector means the most the
        # rig can give and not a cautious default (the owner, 2026-09-19;
        # ADR-0059). Naming a level still pins it.
        [Parameter()]
        [ValidateSet('Calm', 'Realistic', 'Harsh', 'Brutal')]
        [string] $Stress = 'Brutal',

        [Parameter(Position = 1)]
        [SupportsWildcards()]
        [ArgumentCompleter({
            param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

            # Qualified or bare, both name the estate's suite, and
            # Core.Estate is the spelling (ADR-0059, amendment 2026-09-20);
            # omitted, -Suite is the Playground.
            [string] $asked = "$($fakeBoundParameters['Suite'])"

            [string[]] $names = if ($asked -ieq 'Estate' -or $asked -ieq 'Core.Estate') {
                [string] $root = Get-XmipRepositoryRoot
                Get-ChildItem -Path (Join-Path -Path $root -ChildPath 'test') -Filter '*.Test.ps1' |
                    ForEach-Object { $_.Name -replace '\.Test\.ps1$', '' }
            }
            else {
                'RoundTrip', 'LowLatency', 'HeavyLoad', 'Retention'
                'Filing', 'ExclusiveClaim', 'DailyBacklog'
            }

            $names | Where-Object { $_ -like "$wordToComplete*" }
        })]
        [string[]] $Test = @(),

        [Parameter()]
        [ValidateRange(0, [int]::MaxValue)]
        [int] $Rounds = 0,

        [Parameter()]
        [timespan] $Duration,

        [Parameter()]
        [ValidateRange(0.0000001, 1000.0)]
        [double] $TimeFactor,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]] $Nodes,

        [Parameter()]
        [AllowNull()]
        [hashtable] $NodeCapability,

        [Parameter()]
        [string[]] $OnlineNodes = @(),

        [Parameter()]
        [ValidatePattern('^[A-Za-z][A-Za-z0-9-]*$')]
        [string] $Cluster,

        [Parameter()]
        [ValidatePattern('^\d+\s*(gb|g|mb|m|kb|k)?$')]
        [string] $LoadBytes,

        [Parameter()]
        [string] $Path,

        [Parameter()]
        [switch] $PassThru
    )

    # The first failure ends the call; a cascade of twenty errors after one
    # missing piece is what the owner saw on 2026-09-12.
    $ErrorActionPreference = 'Stop'

    # Which suites there are is read, never declared at the parameter: a
    # third party's is a file it dropped, and this session may have started
    # before it existed. Refused here, before anything is built or spawned.
    [object[]] $known = @(Get-XmipTestSuite)
    [string] $refused = Get-XmipTestSuiteRefusal -Name $Suite -Known $known

    if ($refused -ne '') {
        Write-Error $refused
        return
    }

    # Whatever was typed, the suite says what it is called: a bare Playground
    # resolves to the Playground and the record carries the canonical
    # spelling, Core.Playground (ADR-0059, amendment 2026-09-20). A pattern
    # may name several, and then each is run in turn.
    [object[]] $matched = @(Get-XmipNamedTestSuite -Name $Suite -Known $known)

    if ($matched.Count -gt 1) {
        return Start-XmipTestSuiteGroup -Suite $matched -Bound $PSBoundParameters
    }

    $chosen = $matched[0]
    $Suite = $chosen.Name

    if ($chosen.Kind -eq 'pester') {
        [string[]] $foreign = @(
            $PSBoundParameters.Keys | Where-Object { $_ -in $script:XmipPlaygroundOnly }
        )

        if ($foreign.Count -gt 0) {
            Write-Error ("-$($foreign -join ', -') belong to " +
                "$script:XmipPlaygroundSuite, not $Suite.")
            return
        }

        if (-not $PSCmdlet.ShouldProcess("the $Suite Pester suite", 'Start')) {
            return
        }

        return Start-XmipEstateSuite -Path $Path -Test $Test
    }

    if ($chosen.Kind -eq 'command') {
        return Start-XmipProviderSuite -Suite $chosen -Bound $PSBoundParameters
    }

    # A pattern selects among the suite's tests: -Test Round* is RoundTrip and
    # -Test * is every one, which is exactly what omitting -Test means. Done
    # here so the run record carries the tests rather than the pattern, and so
    # a pattern matching nothing is refused before anything is built.
    if (Test-XmipWholeSuite -Test $Test) {
        $Test = @()
    }
    else {
        $Test = @(Expand-XmipTestName -Test $Test -Known @($script:XmipPlaygroundTest.Keys))
    }

    if ($OnlineNodes.Count -gt 0 -and -not $PSBoundParameters.ContainsKey('Nodes')) {
        Write-Error '-OnlineNodes names nodes; name them all with -Nodes first.'
        return
    }

    if ($NodeCapability -and -not $PSBoundParameters.ContainsKey('Nodes')) {
        Write-Error '-NodeCapability names nodes; name them all with -Nodes first.'
        return
    }

    if ($PSBoundParameters.ContainsKey('Nodes')) {
        Assert-XmipNodeName -Nodes $Nodes -OnlineNodes $OnlineNodes
        Assert-XmipNodeCapability -Nodes $Nodes -NodeCapability $NodeCapability
    }

    # You name the cluster; a test spawns nodes, never a cluster (the owner,
    # 2026-09-14). Nothing here invents a name for a roll.
    if ([string]::IsNullOrWhiteSpace($Cluster)) {
        Write-Error 'A roll is a cluster and you name it: -Cluster <name>.'
        return
    }

    # A node declares what it can do (ADR-0056), and RoundTrip across nodes
    # needs receive, process and send declared somewhere. Said here, before
    # anything is built or spawned; the roll refuses the same way for one
    # started by hand.
    [hashtable] $asked = @{
        Nodes          = $Nodes
        Test           = $Test
        NodeCapability = $NodeCapability
    }
    [string] $refusal = Get-XmipNodeCapabilityRefusal @asked

    if ($refusal -ne '') {
        Write-Error $refusal
        return
    }

    # A node's name means nothing (the owner, 2026-09-20: Rn, Pn and Sn are
    # arbitrary node names), so nodes named with no capability stated declare
    # none. That is legal and is probably not what was meant, so it is said
    # rather than discovered (ADR-0055 clause 5).
    [string] $said = Get-XmipNodeCapabilityWarning @asked

    if ($said -ne '') {
        Write-Warning $said
    }

    # Everything from here is the Playground's own work — building, spawning
    # and recording the roll — and is a function of its own since 2026-09-22.
    # It is handed this cmdlet so -WhatIf and -Confirm still decide there.
    [hashtable] $playground = @{
        Caller = $PSCmdlet
        Bound  = $PSBoundParameters
        Suite = $Suite
        Stress = $Stress
        Test = $Test
        Rounds = $Rounds
        Duration = $Duration
        TimeFactor = $TimeFactor
        Nodes = $Nodes
        NodeCapability = $NodeCapability
        OnlineNodes = $OnlineNodes
        Cluster = $Cluster
        Path = $Path
        PassThru = $PassThru
    }

    # A parameter nobody gave is not handed on. An unbound [timespan] is
    # $null here and a [timespan] parameter refuses $null; the roll asks
    # -Bound what was given, never whether a value is present.
    foreach ($key in @($playground.Keys)) {
        if ($null -eq $playground[$key]) {
            $playground.Remove($key)
        }
    }

    Start-XmipPlaygroundRoll @playground
}
