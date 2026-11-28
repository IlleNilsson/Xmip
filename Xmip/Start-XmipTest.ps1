#requires -Version 7.7.0

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
            does (ADR-0011): Core.System is a roll that runs detached
            until you stop it, Get-XmipTestStatus says what runs and
            Stop-XmipTest ends it; Core.Estate is the Pester suite under
            test/, the estate's memory of every past defect, which runs in a
            pwsh of its own, detached, and says OK or FAILED when it ends, as
            Core.Internal, named modules verified as a landing verifies them,
            does, and Core.Demo, the demo readiness check, does part by part.
            Core.Estate and Core.Internal run on a Linux or macOS test computer by -ComputerName.
            A third party's suite is <Provider>.<Name> and joins by a declaration.

            The System Tests (ADR-0028) is the estate's integration test over
            time: a roll drives every scenario round after round and publishes
            a snapshot, a history and the recent activity as TOML files a
            monitor reads. This starts exactly one roll as a background
            process, hands it every switch through its own environment — your
            session's environment is untouched — and writes a run record beside
            the snapshot so Get-XmipTestStatus can say what is running and
            Stop-XmipTest can end it, nodes first.

            As local processes a roll spawns one cluster process and the cluster
            spawns one process per node (the owner, 2026-09-19: even clusters
            have to be spawned as processes during tests). Get-XmipProcess shows all
            three kinds with the location and purpose each declared, and
            Stop-XmipTest ends the tree from the leaves up. Where a node
            declares the Storage role, each node runs as xmip-service instead,
            driven through its Receive Locations (ADR-0028, 2026-10-22).

            The roll, cluster and node binaries are built first, a no-op when
            they are current, so a roll never runs yesterday's scenarios. The
            build is detached and this returns at once (the owner, 2026-10-13):
            Get-XmipTestStatus says building, with the crates compiled, until
            the nodes start, or FAILED with cargo's first error; Stop-XmipTest
            stops it. Under -Path: `build-<start time>.log`, the roll's
            `roll-<start time>.log` and `.err`, and `roll-<pid>.toml`.

        .PARAMETER Suite
            Which test suite to run: Core.System (the default), the System
            Tests, the internals; Core.Systems, the Systems Tests, how nodes
            interact; Core.Estate; Core.Internal, the internal tests of modules
            as a landing verifies them; or Core.Demo. Every suite is <Provider>.<Name>
            and core is the reserved provider that means Xmip itself (ADR-0011):
            a bare System is accepted and resolves to Core.System. A third
            party's suite carries its own provider. Case does not matter. The
            parameters below are the two rolls', and Core.Demo takes -Cluster,
            -Stress, -Process, -VirtualMachine, -Container and its own -Tester.

            Wildcards select a group, exactly as -Test does (the owner,
            2026-09-19): -Suite * is every suite but those started by their name
            alone, Core.Systems, Core.Internal and Core.Demo; -Suite *Sys* is
            the System Tests, a literal name one suite as before. A pattern matching
            nothing is REFUSED, naming it and the suites there are, before anything starts.

            Several suites matched run one after another in the order they
            are listed, each returning what it returns — the System Tests a
            detached roll, the estate a detached Pester run, both back at
            once, a provider's whatever its command gives — so a caller reads
            the stream by type. It is said in words which are about to run and
            which did not start; one suite failing to start never stops the
            rest. A switch that belongs to one suite alone is not a fault when
            a pattern chose the group: -Suite * -Cluster <cluster> rolls on
            that cluster and runs the estate's Pester files beside it.

            A third party adds a suite by dropping a declaration in
            test/suite, with no edit to Xmip's own source. Example stands in
            for whatever it calls itself; the estate names no placeholder
            company (ADR-0059, amendment 2026-09-20):

                provider = "Example"
                name     = "System"
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
            System Tests' are RoundTrip, LowLatency, HeavyLoad, Retention,
            Filing, ExclusiveClaim and DailyBacklog. The estate's are its
            Pester files by name: Allocation, Decision, Rust.Style, XmipTest
            and the rest of test/; Core.Internal's, modules by folder as a
            landing names them, `.` the root crate. Tab completes each.

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
            The nodes, by name — one process each: -Nodes RX1, PX1, TX1 is three called that
            under one cluster called -Cluster. They are written, with
            -Cluster, -NodeRole and -NodeCapability, into the run's own cluster cluster.xmip,
            <Path>/<Cluster>.xmip, and XMIP_TEST_CLUSTER names it to the
            roll: a node is configuration (ADR-0056, amendment 2026-10-03), and
            there is no count. What each node does is the
            roles it is started with (ADR-0056), stated with
            -NodeRole. A name says nothing about it: the owner,
            2026-09-20, *Rn, Pn and Sn are arbitrary node names*. The names
            are the tester's: these examples call clusters CL1, CL2 and nodes
            RX1, PX1, TX1, as the owner names them (ADR-0056, amendment
            2026-11-12), a reminder to the person and never to Xmip. A node given no
            role declares none and runs the shared-directory tests
            whole, which is said in words where RoundTrip was asked for.
            RoundTrip across nodes hands each pair from receive to process to
            send between the processes, so each stage must be served
            somewhere; it is REFUSED otherwise, naming the role, before
            anything starts. An empty list, @(), is no nodes at any level.

            A node's name is also the last word of its process name —
            xmip-system-test-<cluster>-node-<node> (ADR-0053, amendment
            2026-09-20) — so it takes the shape -Cluster takes, and that is
            all: no word is reserved, and a node called roll is a node called
            roll. Anything a file cannot be called is REFUSED before a process
            starts.

            Omit it and the run takes every node of the System Tests' own
            cluster file, test/core/system-test/configuration/Xmip-reference-environment.xmip, one
            process each, declaring the roles its roles key says. A role the
            message path needs and no node declares is
            REFUSED before anything starts, as for named nodes. The run record
            and the [run] table carry the nodes and the cluster file.

        .PARAMETER NodeRole
            The roles each node declares, stated per node: -Nodes RX1, PX1
            -NodeRole @{ RX1 = 'receiving'; PX1 = 'processing,sending' }, or
            @{ EX1 = 'executing' }. The roles are node::NodeRole's (ADR-0056, amendment 2026-10-01):
            receiving, processing and sending serve one stage of the message
            path each, and executing serves all three in one process, the
            low-latency choice — each pair it receives stays in it to the end;
            operational, monitoring and development serve no stage. Lowercase
            exactly, by comma or plus; any other word ('Sending' and the old
            'receive' too), or a node -Nodes does not name, is REFUSED before
            anything starts. A node the table does not name declares what the
            Reference Environment declares for it, and nothing where
            that file does not declare it.
            ADR-0056 names two further kinds of capability, authentication and
            runtime, which the System Tests do not model.

        .PARAMETER NodeCapability
            Node capabilities per node, as -NodeRole: @{ RX1 = 'online, firewall-x' }, online the
            internet (ADR-0056, amendment 2026-11-24); unnamed, the System Tests' file's.

        .PARAMETER Cluster
            The cluster this roll starts (ADR-0028), by the name you give it
            — required: you name the cluster, and a test spawns a cluster and
            its nodes, never invents a name for one (the owner, 2026-09-14
            and 2026-09-19). The scope root is xmip:///<Cluster> and the run
            publishes to <Cluster>-snapshot.xmip beside its history and
            activity. Any name a file can carry will do, and none means
            anything to Xmip. Two rolls with two names are two clusters side
            by side, each with its own web GUI:
            Start-XmipTest -Cluster CL2 -PassThru | Start-XmipOperationWeb -Url ...

        .PARAMETER Process
            Each node and far end a local process, as with no switch; rolls' and Core.Demo's. -Proc.

        .PARAMETER VirtualMachine
            On the virtual machines Deploy-XmipEnvironment deployed for -Cluster here,
            at the addresses and with the operator certificate it recorded; nothing is
            built or started for them, no machine made or started. REFUSED before anything
            is built on a host that makes none, with -Nodes, -NodeRole or -NodeCapability,
            with nothing deployed, or another cluster file than the one deployed. -VM.

        .PARAMETER Container
            A Linux container each, WSL's on Windows, Podman's on Linux, made once built and taken
            away by Stop-XmipTest; REFUSED before anything is built, naming what it lacks. -C.

        .PARAMETER LoadBytes
            The HeavyLoad test's payload: a number or a size like 512mb or 2gb.
            Omit for a megabyte.

        .PARAMETER Path
            System Tests: where the run writes — snapshot, history, activity,
            run record and the roll's own log; defaults to
            `.local-work/system-test` under the repository. Estate: the
            directory of Pester tests; defaults to test/ under the repository.

        .PARAMETER PassThru
            Return the Xmip.TestStatus object for the run started, building.

        .PARAMETER Tester
            Core.Demo's alone: the person who demonstrates, as New-XmipCertificate
            -Operator named them, handed to Start-XmipOperationWeb -Tester.

        .PARAMETER ComputerName
            Core.Estate's and Core.Internal's: runs the suite detached on the Linux
            or macOS computer .local-work/test-computer/<name>.toml names, never in
            Git (Read-XmipTestComputer), in a copy of what Git holds of this estate.

        .EXAMPLE
            # Omitted -Nodes: the Reference Environment's nodes
            # ([nodes.RX1] roles = "receiving", and so on).
            Start-XmipTest -Suite Core.System -Cluster CL1

        .EXAMPLE
            Start-XmipTest -Suite Core.System -Cluster CL1 -Test HeavyLoad -Stress Harsh -Process

        .EXAMPLE
            Start-XmipTest -Suite Core.System -Cluster CL1 -Nodes RX1, TX1 -PassThru |
                Start-XmipOperationWeb

        .EXAMPLE
            # The names are the tester's; -NodeRole says what each does.
            Start-XmipTest -Test RoundTrip -Cluster CL1 -Nodes RX1, PX1, TX1
                -NodeRole @{ RX1 = 'receiving'; PX1 = 'processing'; TX1 = 'sending' }

        .EXAMPLE
            Start-XmipTest -Test RoundTrip -Cluster CL2 -Nodes RX1, RX2, PX1, TX1
                -NodeCapability @{ RX1 = 'online'; TX1 = 'online' } -NodeRole @{ RX1 = 'receiving'
                    RX2 = 'receiving'; PX1 = 'processing'; TX1 = 'sending' }

        .EXAMPLE
            Start-XmipTest -Suite Core.Estate -Test Rust.Style, XmipTest

        .EXAMPLE
            Start-XmipTest -Cluster CL1 -Duration 00:15:00 -TimeFactor 9.5e-6 -WhatIf

        .EXAMPLE
            Start-XmipTest -Suite Example.System -Cluster CL1

        .EXAMPLE
            Start-XmipTest -Suite Core.Estate -Test Sync-Xmip*

        .EXAMPLE
            Start-XmipTest -Suite * -Cluster CL1 -VirtualMachine

        .EXAMPLE
            Start-XmipTest -Suite Core.Demo -Cluster CL1 -Stress Realistic -Tester alice@example.org

        .EXAMPLE
            Start-XmipTest -Suite Core.Internal -Test module/foundation/core -ComputerName build1
    #>
    [CmdletBinding(SupportsShouldProcess, PositionalBinding = $false,
        DefaultParameterSetName = 'Process')]
    [OutputType('Xmip.TestStatus')]
    param(
        # The sentence is "start the System Tests' HeavyLoad": suite first, then
        # the tests, and nothing else by position (the owner, 2026-09-12).
        # Neither the set nor the shape is declared here: the completer offers
        # the suites there are and the body refuses the rest, in the estate's
        # words (Get-XmipTestSuiteRefusal says why; ADR-0055, ADR-0059).
        [Parameter(Position = 0)]
        [SupportsWildcards()]
        [ArgumentCompleter({
            & (Get-Module -Name Xmip | Select-Object -First 1) {
                Get-XmipTestSuiteChoice -Word $args[0] } $args[2]
        })]
        [string] $Suite = 'Core.System',

        # The hardest level, because an omitted selector means the most the
        # rig can give and not a cautious default (the owner, 2026-09-19;
        # ADR-0059). Naming a level still pins it.
        [Parameter()]
        [ValidateSet('Calm', 'Realistic', 'Harsh', 'Brutal')]
        [string] $Stress = 'Brutal',

        [Parameter(Position = 1)]
        [SupportsWildcards()]
        [ArgumentCompleter({
            & (Get-Module -Name Xmip | Select-Object -First 1) {
                Get-XmipTestChoice -Suite $args[0] -Word $args[1] } "$($args[4]['Suite'])" $args[2]
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
        [hashtable] $NodeRole,

        [Parameter()]
        [AllowNull()]
        [hashtable] $NodeCapability,

        [Parameter()]
        [ValidatePattern('^[A-Za-z][A-Za-z0-9-]*$')]
        [string] $Cluster,

        # In sets of their own, which PowerShell refuses together (ADR-0028).
        [Parameter(ParameterSetName = 'Process')]
        [Alias('Proc')]
        [switch] $Process,

        [Parameter(ParameterSetName = 'VirtualMachine')]
        [Alias('VM')]
        [switch] $VirtualMachine,

        [Parameter(ParameterSetName = 'Container')]
        [Alias('C')]
        [switch] $Container,

        [Parameter()]
        [ValidatePattern('^\d+\s*(gb|g|mb|m|kb|k)?$')]
        [string] $LoadBytes,

        [Parameter()]
        [string] $Path,

        [Parameter()]
        [switch] $PassThru,

        [Parameter()]
        [ValidateNotNullOrWhiteSpace()]
        [string] $Tester,

        [Parameter()]
        [ArgumentCompleter({
            & (Get-Module -Name Xmip | Select-Object -First 1) {
                Get-XmipTestComputerChoice -Word $args[0] } $args[2]
        })]
        [ValidateNotNullOrWhiteSpace()]
        [string] $ComputerName
    )

    # The first failure ends the call (a cascade of twenty errors, 2026-09-12).
    $ErrorActionPreference = 'Stop'

    # Every start, refusal and failure is audited (ADR-0062): under 'Stop' a
    # Write-Error ends the call in the trap, is recorded and goes on unchanged.
    trap { Write-XmipAudit -Action 'Start-XmipTest' -ErrorRecord $_; break }
    Write-XmipAudit -Action 'Start-XmipTest' -Phase Begin -Property $PSBoundParameters
    Assert-XmipModuleCurrent

    # Which suites there are is read, never declared at the parameter, and a
    # name that names none is refused before anything is built or spawned. A
    # pattern may name several, and then each is run in turn.
    [object[]] $matched = @(Resolve-XmipTestSuite -Name $Suite)

    if ($matched.Count -eq 0) {
        return
    }

    if ($matched.Count -gt 1) {
        return Start-XmipTestSuiteGroup -Suite $matched -Bound $PSBoundParameters
    }

    $chosen = $matched[0]
    $Suite = $chosen.Name

    [hashtable] $given = @{ Caller = $PSCmdlet; Bound = $PSBoundParameters }

    if ($chosen.Kind -ne 'roll') {
        return Start-XmipChosenSuite @given -Chosen $chosen -Path $Path -Test $Test
    }

    # The System Tests' own work, handed this cmdlet so -WhatIf and -Confirm
    # still decide there; a parameter nobody gave is not handed on.
    foreach ($name in $script:XmipRollHanded) {
        $given[$name] = Get-Variable -Name $name -ValueOnly
    }

    Start-XmipChosenRoll -Choice $given
}
