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
            does (ADR-0011): Playground is a roll that runs detached until
            you stop it, Get-XmipTestStatus says what runs and Stop-XmipTest
            ends it; Estate is the Pester suite under test/, the estate's
            memory of every past defect, which runs here and now, says OK or
            FAILED and returns the Pester result. Acme.Playground is Acme's,
            and joins by a declaration rather than by an edit to Xmip.

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
            Which test suite to run: Playground (the default) or Estate,
            which are Xmip's own. A name with no provider is Xmip's, because
            core is the reserved provider (ADR-0011), so Playground and
            Core.Playground are the one suite and Playground is how it is
            spelled. Someone else's carries their name: Acme.Playground.
            Case does not matter. The Playground parameters below belong to
            the Playground alone.

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

            A provider adds a suite by dropping a declaration in test/suite,
            with no edit to Xmip's own source:

                provider = "Acme"
                name     = "Playground"
                command  = "Start-AcmeXmipTest"

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
            roll's cluster process, so -Nodes R1, P1, S1 is three node
            processes called that under one cluster called -Cluster. What
            each node does is the capability it is started with (ADR-0056),
            and every node runs its part of the tests you named. As a
            convenience of this cmdlet, a name beginning with R, P or S is
            shorthand for the receive, process or send capability — the
            shorthand lives here, at the operator's door, and nothing
            downstream reads a node's name. -NodeCapability states the
            capability outright and overrides it. A node neither named that
            way nor given a capability declares none and runs the
            shared-directory tests whole. RoundTrip across nodes hands each
            pair from receive to process to send between the processes, so
            each capability must be declared somewhere; it is REFUSED
            otherwise, naming the capability, before anything starts. An
            empty list, @(), is no nodes at any level.

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
            What each node declares it can do, stated per node and overriding
            the name shorthand: -Nodes alpha, beta -NodeCapability
            @{ alpha = 'receive'; beta = 'process,send' }. The values are
            receive, process and send, one or more, separated by commas or by
            plus; an unknown word, or a node -Nodes does not name, is REFUSED
            before anything starts. A node the table does not name keeps the
            shorthand. ADR-0056 names two further kinds of capability,
            authentication and runtime, which the Playground does not model.

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
            <Cluster>-snapshot.toml beside its history and activity. Two
            rolls with two names are two clusters side by side, each with
            its own web GUI:
            Start-XmipTest -Cluster C2 -PassThru | Start-XmipOperationWeb -Url ...

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
            Start-XmipTest -Suite Playground -Cluster C1

        .EXAMPLE
            Start-XmipTest -Suite Playground -Cluster C1 -Test HeavyLoad -Stress Harsh

        .EXAMPLE
            Start-XmipTest -Suite Playground -Cluster C1 -Nodes R1, P1 -PassThru |
                Start-XmipOperationWeb

        .EXAMPLE
            Start-XmipTest -Test RoundTrip -Cluster C1 -Nodes R1, R2, P1, S1 -OnlineNodes R1, S1

        .EXAMPLE
            Start-XmipTest -Test RoundTrip -Cluster C1 -Nodes alpha, beta, gamma -NodeCapability
                @{ alpha = 'receive'; beta = 'process'; gamma = 'send' }

        .EXAMPLE
            Start-XmipTest -Suite Estate -Test Rust.Style, XmipTest

        .EXAMPLE
            Start-XmipTest -Cluster C1 -Duration 00:15:00 -TimeFactor 9.5e-6 -WhatIf

        .EXAMPLE
            Start-XmipTest -Suite Estate

        .EXAMPLE
            (Start-XmipTest -Suite Estate).Failed | Format-Table ExpandedPath

        .EXAMPLE
            Start-XmipTest -Suite Acme.Playground -Cluster C1

        .EXAMPLE
            Start-XmipTest -Suite Estate -Test Sync-Xmip*

        .EXAMPLE
            Start-XmipTest -Suite * -Cluster C1

        .EXAMPLE
            Start-XmipTest -Suite *Play* -Cluster C1
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
        [string] $Suite = 'Playground',

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

            # Bare or qualified, both name the estate's suite (ADR-0059,
            # amendment 2026-09-19); omitted, -Suite is the Playground.
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

    # Which suites there are is read, never declared at the parameter: Acme's
    # is a file a provider dropped, and this session may have started before
    # it existed. Refused here, before anything is built or spawned.
    [object[]] $known = @(Get-XmipTestSuite)
    [string] $refused = Get-XmipTestSuiteRefusal -Name $Suite -Known $known

    if ($refused -ne '') {
        Write-Error $refused
        return
    }

    # Whatever was typed, the suite says what it is called: Core.Playground
    # resolves to the Playground and the record carries the canonical
    # spelling (ADR-0059, amendment 2026-09-19). A pattern may name several,
    # and then each is run in turn.
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

    $layout = Get-XmipPlaygroundLayout

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = $layout.Area
    }

    [hashtable] $choice = Get-XmipPlaygroundChoice -Bound $PSBoundParameters
    $choice.Stress = $Stress
    $choice.Test = $Test
    $choice.Snapshot = Join-Path -Path $Path -ChildPath "$Cluster-snapshot.toml"
    $choice.History = Join-Path -Path $Path -ChildPath "$Cluster-history.toml"
    $choice.Activity = Join-Path -Path $Path -ChildPath "$Cluster-activity.toml"

    [bool] $boundNodes = $PSBoundParameters.ContainsKey('Nodes')
    [string] $of = if ($Test.Count -gt 0) { " of $($Test -join ', ')" } else { '' }
    [string] $for = if ($Rounds -gt 0) { " for $Rounds rounds" } else { ' until stopped' }
    [string] $with = if (-not $boundNodes) {
        ", the $($Stress.ToLowerInvariant()) level's full complement"
    }
    elseif ($Nodes.Count -eq 0) { ', no nodes' } else { ", nodes $($Nodes -join ', ')" }
    [string] $online = if ($OnlineNodes.Count -gt 0) { " ($($OnlineNodes -join ', ') online)" }
    [string] $what = "roll at $($Stress.ToLowerInvariant())$of$for$with$online as cluster $Cluster"

    if (-not $PSCmdlet.ShouldProcess("the Xmip Playground in $Path", "Start a $what")) {
        return
    }

    [string] $roll = Invoke-XmipPlaygroundBuild -Binary roll
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    Remove-XmipPlaygroundStaleRecord -Path $Path

    # A roll is a cluster, and two rolls are two clusters (ADR-0028; ADR-0052,
    # ruling 1 of 2026-09-14). Two under one name publish to one file and each
    # overwrites the other: on 2026-09-18 three rolled as CC1, the surfaces
    # saw 803, 2,259 and 11,499 leaves in turn, and the prompt went blank.
    [int[]] $rolling = @(Get-XmipPlaygroundRolling -Path $Path -Cluster $Cluster)

    if ($rolling.Count -gt 0) {
        Write-Error ("REFUSED: cluster $Cluster is already rolling as pid " +
            "$($rolling -join ', '). Stop it with Stop-XmipTest -Id " +
            "$($rolling -join ', '), or name another cluster.")
        return
    }

    # Omitted, -Nodes is the level's full complement, resolved here so the run
    # record says what an operator got and the roll is told by name rather than
    # left to decide twice (ADR-0059, amendment 2026-09-19). The count is the
    # rig's to answer, so the rig is asked.
    if (-not $boundNodes) {
        $complement = Get-XmipNodeComplement -Roll $roll -Stress $Stress
        $Nodes = $complement.Nodes
        $NodeCapability = $complement.NodeCapability
        $choice.Nodes = $Nodes
        $choice.NodeCapability = $NodeCapability

        # A complement that refused itself would be no answer at all, so this
        # asks before anything is spawned, as a named roster is asked.
        $asked = @{
            Nodes          = $Nodes
            Test           = $Test
            NodeCapability = $NodeCapability
        }
        [string] $composed = Get-XmipNodeCapabilityRefusal @asked

        if ($composed -ne '') {
            Write-Error $composed
            return
        }

        # Said, not left to be noticed (ADR-0055 clause 5): a level with fewer
        # nodes than the path has stages runs RoundTrip whole in the roll.
        [bool] $roundTrip = (Test-XmipWholeSuite -Test $Test) -or ('RoundTrip' -in $Test)

        if ($roundTrip -and -not $complement.Covers) {
            Write-Warning ("The $($Stress.ToLowerInvariant()) level brings " +
                "$($Nodes.Count) node(s) on this machine, too few for receive, " +
                'process and send: they declare no stage and RoundTrip runs whole ' +
                'in the roll. Name -Nodes R1, P1, S1 to split the message path.')
        }
    }

    [hashtable] $environment = New-XmipPlaygroundEnvironment @choice

    $launch = @{
        FilePath         = $roll
        WorkingDirectory = $layout.Playground
        Environment      = $environment
        WindowStyle      = 'Hidden'
        PassThru         = $true
    }

    if ($Rounds -gt 0) {
        $launch.ArgumentList = @("$Rounds")
    }

    # The log is named for the start time, since Start-Process wants the file
    # named before the pid exists; the run record says which log is whose.
    [string] $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $launch.RedirectStandardOutput = Join-Path -Path $Path -ChildPath "roll-$stamp.log"
    $launch.RedirectStandardError = Join-Path -Path $Path -ChildPath "roll-$stamp.err"

    $process = Start-Process @launch

    [bool] $boundDuration = $PSBoundParameters.ContainsKey('Duration')
    [bool] $boundFactor = $PSBoundParameters.ContainsKey('TimeFactor')

    # The nodes are the resolved ones either way: an operator who named none
    # can read what they got, and node_names says which of the two it was.
    $record = [ordered]@{
        suite       = $Suite
        cluster     = $Cluster
        pid         = $process.Id
        started     = $process.StartTime.ToString('o')
        stress      = $Stress.ToLowerInvariant()
        tests       = @($Test)
        rounds      = $Rounds
        nodes       = @($Nodes)
        node_names  = if ($boundNodes) { 'named' } else { 'complement' }
        online      = @($OnlineNodes)
        duration_s  = if ($boundDuration) { $Duration.TotalSeconds } else { 0 }
        time_factor = if ($boundFactor) { $TimeFactor } else { 1.0 }
        snapshot    = $environment.XMIP_PLAYGROUND_SNAPSHOT
        history     = $environment.XMIP_PLAYGROUND_HISTORY
        activity    = $environment.XMIP_PLAYGROUND_ACTIVITY
        log         = $launch.RedirectStandardOutput
    }

    Import-Module PSToml -ErrorAction Stop
    [string] $recordPath = Join-Path -Path $Path -ChildPath "roll-$($process.Id).toml"
    ConvertTo-Toml -InputObject $record | Set-Content -LiteralPath $recordPath -Encoding utf8
    [string] $declared = Get-XmipNodeCapabilityText -Nodes $Nodes -NodeCapability $NodeCapability
    [string] $roster = if ($declared -ne '') { "; roster $declared" } else { '' }
    Write-Verbose "started $what$roster as pid $($process.Id); record at $recordPath"

    # The prompt, where this session shows one, follows the roll just started:
    # the shipped document names C1, and on 2026-09-18 a roll named CC1 left
    # the prompt frozen on another cluster's file. Said here because this
    # command knows the file; nothing is loaded that is not loaded already.
    $prompt = 'Xmip.PowerShell.PromptMonitor' -as [type]

    if ($null -ne $prompt) {
        $prompt::Follow($environment.XMIP_PLAYGROUND_SNAPSHOT)
    }

    if ($PassThru) {
        return Get-XmipTestStatus -Path $Path | Where-Object { $_.Id -eq $process.Id }
    }
}

# The parameters that mean something only to the Playground suite.
[string[]] $script:XmipPlaygroundOnly = @(
    'Cluster',
    'Stress', 'Rounds', 'Duration', 'TimeFactor'
    'Nodes', 'OnlineNodes', 'NodeCapability', 'LoadBytes', 'PassThru'
)

function Start-XmipTestSuiteGroup {
    <#
        .SYNOPSIS
            Runs every suite a pattern matched, in the order they are listed,
            saying in words which are about to run and which did not start.

        .DESCRIPTION
            Each is started through Start-XmipTest itself, so a group run and
            a single run are the same run: the same refusals, the same
            records, the same -WhatIf. Two things differ, and only because a
            pattern chose the group rather than an operator naming one suite.

            A switch that belongs to the Playground alone is dropped for the
            estate's Pester suite rather than refused — -Suite * -Cluster Z3
            is not a mistake about -Cluster; it is a roll on Z3 with the
            estate's files beside it. A provider's command keeps everything,
            since only the provider knows what its command takes.

            One suite that will not start does not stop the others, which is
            the rule a malformed declaration already follows (ADR-0059): what
            another provider wrote may never stop Xmip's own tests. Each
            failure is said by name and again at the end.

        .PARAMETER Suite
            The suites matched, in the order Get-XmipTestSuite lists them.

        .PARAMETER Bound
            What Start-XmipTest was called with.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [object[]] $Suite,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Bound
    )

    [string[]] $names = @($Suite | ForEach-Object { $_.Name })
    Write-Host "Running $($names.Count) suites in order: $($names -join ', ')."

    [System.Collections.Generic.List[string]] $refused = @()

    foreach ($one in $Suite) {
        [hashtable] $forward = @{}

        foreach ($key in @($Bound.Keys)) {
            $forward[$key] = $Bound[$key]
        }

        $forward['Suite'] = $one.Name
        $forward['ErrorAction'] = 'Stop'

        if ($one.Kind -eq 'pester') {
            foreach ($only in $script:XmipPlaygroundOnly) {
                $forward.Remove($only)
            }
        }

        try {
            Start-XmipTest @forward
        }
        catch {
            $refused.Add($one.Name)
            Write-Host "FAILED $($one.Name) did not start: $($_.Exception.Message)"
        }
    }

    [string] $ran = $names -join ', '

    if ($refused.Count -eq 0) {
        Write-Host "OK $($names.Count) suites started: $ran."
        return
    }

    [string] $missing = $refused -join ', '
    Write-Host "FAILED $($refused.Count) of $($names.Count) did not start: $missing."
}

function Start-XmipProviderSuite {
    <#
        .SYNOPSIS
            Starts a suite a provider declared, through the command the
            declaration names, with everything -Suite was given beside it.

        .DESCRIPTION
            Xmip runs nothing of its own here. The declaration says which
            command starts the suite and that command is the provider's
            (ADR-0011: the provider slot states who stands behind it). A
            command this session does not have is REFUSED by name, with the
            declaration that named it, before anything runs.

            -Test is forwarded only when the operator named tests. Nothing
            named is the whole suite, for every suite and every provider, so
            the provider's command is called the way it would be called by
            hand for a full run.

        .PARAMETER Suite
            The suite, from Get-XmipTestSuite.

        .PARAMETER Bound
            What Start-XmipTest was called with.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [PSTypeName('Xmip.TestSuite')]
        [PSObject] $Suite,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Bound
    )

    $command = Get-Command -Name $Suite.Command -ErrorAction SilentlyContinue

    if ($null -eq $command) {
        Write-Error ("REFUSED. $($Suite.Name) starts with $($Suite.Command), which this " +
            "session does not have. $($Suite.Source) declares it; import the module " +
            'that provides it, or correct the declaration.')
        return
    }

    [hashtable] $forward = @{}

    foreach ($given in @($Bound.Keys)) {
        if ($given -eq 'Suite') {
            continue
        }

        if ($given -eq 'Test' -and (Test-XmipWholeSuite -Test $Bound['Test'])) {
            continue
        }

        $forward[$given] = $Bound[$given]
    }

    if (-not $PSCmdlet.ShouldProcess($Suite.Name, 'Start')) {
        return
    }

    return & $command @forward
}

function Start-XmipEstateSuite {
    <#
        .SYNOPSIS
            Runs the estate's Pester suite under test/ and returns the result.

        .DESCRIPTION
            `Invoke-Pester -Path ./test` finds nothing since 2026-09-11: the
            estate's test files carry the singular suffix `.Test.ps1` and
            Pester looks for the plural. Get-XmipPesterConfiguration tells it,
            the same configuration the landing gate uses. The result is
            returned, not printed, so a caller reads `PassedCount`,
            `FailedCount` and `Failed` like any other object; the verdict is
            said in words, OK or FAILED, with each failing test named.

        .PARAMETER Path
            The directory of tests. Defaults to test/ under the repository.

        .PARAMETER Test
            The test files to run, by name without the suffix: Rust.Style runs
            test/Rust.Style.Test.ps1. Omit for every file — nothing named is
            the whole suite, and Test-XmipWholeSuite is where that is decided.
    #>
    [CmdletBinding()]
    [OutputType('Pester.Run')]
    param(
        [Parameter()]
        [string] $Path,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]] $Test = @()
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $Path = Join-Path -Path (Get-XmipRepositoryRoot) -ChildPath 'test'
    }

    $configuration = Get-XmipPesterConfiguration -Path $Path

    if (-not (Test-XmipWholeSuite -Test $Test)) {
        [string[]] $known = @(
            Get-ChildItem -LiteralPath $Path -Filter '*.Test.ps1' -File |
                ForEach-Object { $_.Name -replace '\.Test\.ps1$', '' } |
                Sort-Object
        )
        [string[]] $wanted = @(Expand-XmipTestName -Test $Test -Known $known)
        [string[]] $files = @(
            $wanted | ForEach-Object { Join-Path -Path $Path -ChildPath "$_.Test.ps1" }
        )

        $configuration.Run.Path = $files
    }

    # In its own runspace, never in this module's. The test files begin by
    # removing Xmip and importing it afresh; run from inside the module they
    # tore down the module that was running them, and every later call from
    # the console found a hollow module (2026-09-12). A thread job shares the
    # process, so the result comes back live, and its runspace is its own.
    $job = Start-ThreadJob -ScriptBlock {
        param($Configuration)

        Set-StrictMode -Off
        Invoke-Pester -Configuration $Configuration
    } -ArgumentList $configuration

    $result = Receive-Job -Job $job -Wait -AutoRemoveJob

    [string] $tally = "$($result.PassedCount) passed, $($result.FailedCount) failed"

    if ($result.FailedCount -eq 0) {
        Write-Host "OK $tally" -ForegroundColor Green
    }
    else {
        Write-Host "FAILED $tally" -ForegroundColor Red
    }

    foreach ($failure in $result.Failed) {
        Write-Host "   FAILED $($failure.ExpandedPath)" -ForegroundColor Red
    }

    return $result
}

function Get-XmipPlaygroundChoice {
    <#
        .SYNOPSIS
            The optional roll switches the caller actually gave, as the
            arguments New-XmipPlaygroundEnvironment takes for them.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Bound
    )

    [hashtable] $chosen = @{}

    [string[]] $optional = @(
        'Nodes', 'OnlineNodes', 'NodeCapability'
        'Cluster', 'Duration', 'TimeFactor', 'LoadBytes'
    )

    foreach ($name in $optional) {
        if ($Bound.ContainsKey($name)) {
            $chosen[$name] = $Bound[$name]
        }
    }

    return $chosen
}

function Get-XmipPlaygroundRolling {
    <#
        .SYNOPSIS
            The pids rolling as a cluster, from the run records in a directory.
            Stale records are removed before this is asked, so a record here is
            a roll that runs.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Cluster
    )

    [string] $named = '^\s*cluster\s*=\s*"' + [regex]::Escape($Cluster) + '"\s*$'

    foreach ($file in @(Get-ChildItem -LiteralPath $Path -Filter 'roll-*.toml' -File)) {
        [string] $number = $file.BaseName -replace '^roll-', ''

        if ($number -match '^\d+$' -and
            (Select-String -LiteralPath $file.FullName -Pattern $named -Quiet)) {
            [int] $number
        }
    }
}

function Remove-XmipPlaygroundStaleRecord {
    <#
        .SYNOPSIS
            Deletes run records whose roll is no longer running — a roll that
            reached its rounds or its ceiling leaves one behind.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $layout = Get-XmipPlaygroundLayout

    foreach ($file in @(Get-ChildItem -LiteralPath $Path -Filter 'roll-*.toml' -File)) {
        [string] $number = $file.BaseName -replace '^roll-', ''

        if ($number -notmatch '^\d+$') {
            continue
        }

        $process = Get-Process -Id ([int] $number) -ErrorAction SilentlyContinue
        [bool] $alive = $null -ne $process -and
            (Test-XmipPlaygroundBinary -Process $process -Path $layout.Roll)

        if (-not $alive) {
            Remove-Item -LiteralPath $file.FullName -Force
        }
    }
}

# Which live processes are the Playground's is Get-XmipPlaygroundProcess.ps1:
# Test-XmipPlaygroundBinary moved there on 2026-09-19, with the finding that a
# rebuilt binary must not make a running roll disappear.
