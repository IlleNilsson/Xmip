#requires -PSEdition Core
#requires -Version 7.6.5

<#
    The Playground is started by a person and by nothing else. On 2026-09-12
    the owner found a roll, forty nodes and a web host restarting themselves
    every thirty seconds from a hidden shell an assistant had left behind, and
    ruled: clean instructions, and processes start when he says. These are the
    cheap checks on the cmdlets that replaced it — Start, Get and Stop for the
    roll, the emulated nodes and the web monitor — over pure helpers and
    fixtures, never over a running binary. The suite starts nothing.
#>

BeforeAll {
    # What these commands audit while they are tested goes to this run's own
    # drive, never to .local-work/audit or the operating system's log
    # (ADR-0062): stated over whatever the session had, and given back after.
    $script:AuditBefore = $env:XMIP_AUDIT_DIRECTORY
    $env:XMIP_AUDIT_DIRECTORY = Join-Path -Path $TestDrive -ChildPath 'audit'

    <#
        .SYNOPSIS
        Start-XmipTest's source, every file of it.

        .DESCRIPTION
        One file of 944 lines until 2026-09-22 and a family now: the cmdlet,
        the suite groups, the estate's suite, the Playground's checks and the
        roll it hands its work to. A test asking what the start does reads all
        of them, so it does not care which file a line moved to.
    #>
    function Get-XmipStartSource {
        [string] $module = Join-Path (Get-XmipRepositoryRoot) 'Xmip'

        [string[]] $family = @(
            'Start-XmipTest.ps1', 'Start-XmipTestSuiteGroup.ps1', 'Start-XmipEstateSuite.ps1'
            'Resolve-XmipPlaygroundChoice.ps1', 'Start-XmipPlaygroundRoll.ps1'
        )

        return (($family | ForEach-Object {
                    Get-Content -Raw -LiteralPath (Join-Path $module $_)
                }) -join "`n")
    }

    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    # Every cluster and node name below is the test cluster's (ADR-0056,
    # amendment 2026-10-03): its own name, and the first node declaring each
    # stage of the message path. A name a case needs beyond those is built
    # from them.
    $script:Cluster = Get-XmipTestCluster
    $script:Stage = @{}

    foreach ($role in 'receiving', 'processing', 'sending') {
        $script:Stage[$role] = @($script:Cluster.Nodes | Where-Object {
                @($script:Cluster.Role[$_] -split '[,+ ]+') -contains $role
            })[0]
    }

    $script:Named = @{ Cluster = $script:Cluster; Stage = $script:Stage }
}

Describe 'Start, Get and Stop, and nothing else' {
    It 'has exactly those verbs for the nodes and the web host' {
        foreach ($noun in 'XmipTestNode', 'XmipOperationWeb') {
            [string[]] $verbs = @(Get-Command -Module Xmip -Noun $noun | ForEach-Object { $_.Verb })

            [string[]] $sorted = @($verbs | Sort-Object)

            $sorted | Should -Be @('Get', 'Start', 'Stop') -Because "$noun is operated"
        }
    }

    It 'starts, reports and stops a test run under the names the owner chose' {
        # 2026-09-12: Start-XmipTest, Get-XmipTestStatus and Stop-XmipTest — the
        # Playground is one suite Xmip provides, and a transport's or a
        # contract's suite may join it. He voted for Start, not Invoke: Invoke
        # is for crossing a boundary — a language, a process, a computer — and
        # a test run crosses none. The Pester door is -Suite Core.Estate.
        foreach ($name in 'Start-XmipTest', 'Get-XmipTestStatus', 'Stop-XmipTest') {
            Get-Command -Module Xmip -Name $name | Should -Not -BeNullOrEmpty
        }

        [string[]] $verbs = @(Get-Command -Module Xmip -Noun XmipTest | ForEach-Object { $_.Verb })

        @($verbs | Sort-Object) | Should -Be @('Start', 'Stop')
        Get-Command -Module Xmip -Name 'Invoke-XmipTest*' | Should -BeNullOrEmpty
    }

    It 'reads "Start-XmipTest Core.Playground HeavyLoad" as suite then test, nothing by position' {
        # 2026-09-12: typed positionally, the second word landed on -Stress.
        $parameters = (Get-Command -Name Start-XmipTest).Parameters
        [hashtable] $position = @{}

        foreach ($name in $parameters.Keys) {
            $attribute = $parameters[$name].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
                Select-Object -First 1

            if ($null -ne $attribute -and $attribute.Position -ge 0) {
                $position[$name] = $attribute.Position
            }
        }

        $position.Keys | Sort-Object | Should -Be @('Suite', 'Test')
        $position.Suite | Should -Be 0
        $position.Test | Should -Be 1
    }

    It 'offers the Playground and the estate suite by name, Playground first' {
        # ADR-0059: a suite carries its provider, and which suites there are
        # cannot be a ValidateSet, since a provider declares its own. The shape
        # is the door; the completer is the offer (ADR-0055 clauses 1 and 4).
        $parameter = (Get-Command -Name Start-XmipTest).Parameters['Suite']

        $parameter.Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } |
            Should -BeNullOrEmpty -Because 'a third party''s suite is not knowable here'

        $completer = $parameter.Attributes |
            Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] } |
            Select-Object -First 1

        [string[]] $offered = @(
            $completer.ScriptBlock.Invoke('Start-XmipTest', 'Suite', '', $null, @{})
        )

        $offered | Should -Be @('Core.Playground', 'Core.Estate')
    }

    It 'canonicalizes every spelling to the qualified name, and accepts the bare one' {
        # The owner, 2026-09-20: "Sort it, there was a decision made. It's
        # name is Core.Playground, to give place for third parties." The
        # qualified form is canonical again; a bare name is still accepted
        # and resolves to it, so nothing he has typed refuses (ADR-0059,
        # amendment 2026-09-20). The assertion is on what comes back, not on
        # what goes in: one spelling out of three spellings in.
        InModuleScope Xmip {
            [object[]] $known = @(Get-XmipTestSuite)

            foreach ($spelling in 'Playground', 'Core.Playground', 'core.playground') {
                (Get-XmipNamedTestSuite -Name $spelling -Known $known).Name |
                    Should -Be 'Core.Playground'
                Get-XmipTestSuiteRefusal -Name $spelling -Known $known | Should -Be ''
            }

            foreach ($spelling in 'Estate', 'Core.Estate', 'CORE.ESTATE') {
                (Get-XmipNamedTestSuite -Name $spelling -Known $known).Name |
                    Should -Be 'Core.Estate'
                Get-XmipTestSuiteRefusal -Name $spelling -Known $known | Should -Be ''
            }

            # A bare name reaches the reserved provider's suites and no one
            # else's: it is shorthand for Core., never for whoever declared
            # a suite of the same name.
            [hashtable] $declared = @{
                Provider = 'Example'
                Name     = 'Playground'
                Kind     = 'command'
                Command  = 'Start-ExampleXmipTest'
            }
            [object[]] $third = @($known; New-XmipTestSuite @declared)

            @(Get-XmipNamedTestSuite -Name 'Playground' -Known $third).Name |
                Should -Be 'Core.Playground'
        }
    }

    It 'refuses a bare name nobody provides, and says how a provider''s is spelled' {
        [string] $expected = '*REFUSED. No test suite is called Nonsense*' +
            'Core.Playground, Core.Estate*<Provider>.<Name>*'

        { Start-XmipTest -Suite Nonsense -ErrorAction Stop } |
            Should -Throw -ExpectedMessage $expected
        { Start-XmipTest -Suite 'Core.' -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*REFUSED. No test suite is called Core.*'
    }

    It 'filters -Suite as it filters -Test, and refuses a pattern matching nothing' {
        # The owner, 2026-09-19: "Filter the -Suite as the -Test parameter."
        # ADR-0059 clause 7 said -Suite stays exact; he struck it.
        InModuleScope Xmip {
            [object[]] $known = @(Get-XmipTestSuite)

            @(Get-XmipNamedTestSuite -Name '*' -Known $known | ForEach-Object { $_.Name }) |
                Should -Be @('Core.Playground', 'Core.Estate')
            @(Get-XmipNamedTestSuite -Name '*Play*' -Known $known).Name |
                Should -Be 'Core.Playground'
            @(Get-XmipNamedTestSuite -Name 'Core.*' -Known $known).Count | Should -Be 2
            @(Get-XmipNamedTestSuite -Name 'Nope*' -Known $known).Count | Should -Be 0

            Get-XmipTestSuiteRefusal -Name '*' -Known $known | Should -Be ''
            Get-XmipTestSuiteRefusal -Name 'Nope*' -Known $known |
                Should -BeLike 'REFUSED. No test suite matches Nope*Core.Playground, Core.Estate*'
        }

        { Start-XmipTest -Suite 'Nope*' -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*REFUSED. No test suite matches Nope**'
    }

    It 'runs every suite a pattern matched, in order, and says which are about to run' {
        # -Suite * is the Playground and the estate, each started the way it
        # starts. -Cluster belongs to the Playground alone and is dropped for
        # the Pester suite rather than refused, because a pattern chose the
        # group; an operator who named one suite is still refused.
        [string[]] $said = @(
            Start-XmipTest -Suite * -Cluster $script:Cluster.Name -Rounds 1 -WhatIf 6>&1 |
                ForEach-Object { "$_" }
        )

        "$said" | Should -BeLike '*Running 2 suites in order: Core.Playground, Core.Estate.*'
        "$said" | Should -BeLike '*OK 2 suites started: Core.Playground, Core.Estate.*'
    }

    It 'refuses a qualified suite nobody provides, naming the suites there are' {
        [string] $expected = '*REFUSED. No test suite is called Example.Playground*' +
            'Core.Playground, Core.Estate*'

        { Start-XmipTest -Suite Example.Playground -ErrorAction Stop } |
            Should -Throw -ExpectedMessage $expected
    }

    It 'runs the estate suite in a pwsh of its own, never in the module it tests' {
        # 2026-09-12: these files begin by removing Xmip and importing it
        # afresh. Run from inside the module, the suite tore down the module
        # that was running it. A thread job kept the runspace apart and held
        # the console until it ended: ten minutes, on 2026-09-25. A process
        # of its own keeps both apart, and nothing waits for it.
        [string] $door = Get-XmipStartSource

        $door | Should -Match '-EncodedCommand' -Because 'the suite removes the module it runs in'
        $door | Should -Not -Match 'Start-ThreadJob|Receive-Job'
        $door | Should -Not -Match '(?m)^\s*\$result = Invoke-Pester'
    }

    It 'refuses Playground switches on the estate suite' {
        { Start-XmipTest -Suite Core.Estate -Stress Harsh -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*belong to Core.Playground, not Core.Estate*'
    }

    It 'rehearses every Start and Stop with -WhatIf' {
        [object[]] $commands = @(Get-Command -Module Xmip -Verb Start, Stop)
        [string[]] $doors = @($commands | ForEach-Object { $_.Name })

        foreach ($name in $doors) {
            (Get-Command -Name $name).Parameters.Keys |
                Should -Contain 'WhatIf' -Because "$name changes what runs on the machine"
        }
    }

    It 'lets a test status object name the snapshot a web monitor reads' {
        # Start-XmipTest -PassThru | Start-XmipOperationWeb: the property and the
        # parameter share a name, and the parameter binds by it.
        $parameter = (Get-Command -Name Start-XmipOperationWeb).Parameters['Snapshot']
        $binding = $parameter.Attributes |
            Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }

        $binding.ValueFromPipelineByPropertyName | Should -BeTrue
    }

    It 'finds the repository from any directory, through where the module lives' {
        # 2026-09-12: from his home directory every cmdlet threw "No
        # architecture.toml found at or above". The module is a junction into
        # the repository; its own location answers when the directory does not.
        $manifest = Get-Item (Join-Path $script:Root 'architecture.toml')
        [string] $expected = $manifest.Directory.FullName

        Get-XmipRepositoryRoot -StartAt ([System.IO.Path]::GetTempPath()) | Should -Be $expected
    }

    It 'names no automatic start anywhere in the module' {
        # The keeper is gone and nothing may grow back in its place: no module
        # file starts a roll, a node or the web host outside its Start-* door.
        [string[]] $files = @(
            Get-ChildItem -Path (Join-Path $script:Root 'Xmip') -Filter '*.ps*1' |
                Where-Object { $_.Name -notlike 'Start-Xmip*' } |
                Select-Object -ExpandProperty FullName
        )

        foreach ($file in $files) {
            Get-Content -LiteralPath $file -Raw | Should -Not -Match 'Start-Process' -Because $file
        }
    }
}

Describe 'The environment a roll is started with' {
    It 'sets only what was chosen, with the names the roll reads' {
        InModuleScope Xmip {
            $least = @{ Stress = 'Harsh'; Area = 'a' }
            $environment = New-XmipPlaygroundEnvironment @least

            $environment.XMIP_PLAYGROUND_STRESS | Should -Be 'harsh'
            $environment.XMIP_PLAYGROUND_AREA | Should -Be 'a'
            $environment.Keys | Should -Not -Contain 'XMIP_ONLINE'
            $environment.Keys | Should -Not -Contain 'XMIP_PLAYGROUND_ONLINE_NODES'
            $environment.Keys | Should -Not -Contain 'XMIP_TEST_CLUSTER'
            $environment.Keys | Should -Not -Contain 'XMIP_PLAYGROUND_MAX_SECONDS'
            $environment.Keys | Should -Not -Contain 'XMIP_PLAYGROUND_SCENARIOS'
            $environment.Keys | Should -Not -Contain 'XMIP_PLAYGROUND_CLUSTER'
        }
    }

    It 'says the tests, the cluster file, the online nodes and the limits as the roll parses them' {
        InModuleScope Xmip -Parameters $script:Named {
            param($Cluster, $Stage)

            [string] $r = $Stage.receiving
            [string] $s = $Stage.sending
            $chosen = @{
                Stress      = 'Brutal'
                Test        = @('roundtrip', 'HeavyLoad')
                ClusterFile = $Cluster.Path
                OnlineNodes = @($r, $s)
                Cluster     = $Cluster.Name
                Duration    = [timespan]::FromMinutes(15)
                TimeFactor  = 9.5e-6
                LoadBytes   = '512mb'
                Image       = 'i'
                Area        = 'a'
            }
            $environment = New-XmipPlaygroundEnvironment @chosen

            $environment.XMIP_PLAYGROUND_SCENARIOS | Should -Be 'round-trip,heavy-load'
            $environment.XMIP_TEST_CLUSTER | Should -Be $Cluster.Path
            $environment.XMIP_PLAYGROUND_ONLINE_NODES | Should -Be "$r,$s"
            $environment.XMIP_PLAYGROUND_CLUSTER | Should -Be $Cluster.Name
            $environment.XMIP_PLAYGROUND_MAX_SECONDS | Should -Be '900'
            $environment.XMIP_PLAYGROUND_TIME_FACTOR | Should -Be '9.5E-06'
            $environment.XMIP_PLAYGROUND_LOAD_BYTES | Should -Be '512mb'
            $environment.XMIP_PLAYGROUND_IMAGES | Should -Be 'i'
        }
    }

    It 'writes the nodes named into the run''s cluster file, and an empty list is no nodes' {
        # The owner, 2026-10-03: parameters and configuration, xmip.toml. A
        # node is configuration and there is no count: what -Nodes names is
        # written with -Cluster and -NodeRole, and read back as the roll reads
        # it (ADR-0056, amendment 2026-10-03).
        InModuleScope Xmip -Parameters $script:Named {
            param($Cluster, $Stage)

            [string] $r = $Stage.receiving
            [string] $p = $Stage.processing
            [string] $area = Join-Path $TestDrive 'run'
            $typed = @{
                Cluster  = $Cluster.Name
                Nodes    = @($r, $p)
                NodeRole = @{ $r = 'receiving' }
                Path     = $area
            }
            [string] $file = Write-XmipTestCluster @typed
            $read = Read-XmipTestCluster -Path $file

            $file | Should -Be (Join-Path $area "$($Cluster.Name).xmip.toml")
            $read.Name | Should -Be $Cluster.Name
            [string[]] $ordinal = @($r, $p)
            [Array]::Sort($ordinal, [StringComparer]::Ordinal)
            $read.Nodes | Should -Be $ordinal
            $read.Role[$r] | Should -Be 'receiving'
            $read.Role[$p] | Should -Be ''

            $none = Write-XmipTestCluster -Cluster $Cluster.Name -Nodes @() -Path $area
            (Read-XmipTestCluster -Path $none).Nodes | Should -BeNullOrEmpty

            # Omitted, the test cluster's file as it is.
            Get-XmipTestClusterPath | Should -Be $Cluster.Path
            (Read-XmipTestCluster -Path $Cluster.Path).Nodes | Should -Be $Cluster.Nodes
        }
    }

    It 'refuses a node named twice, an online node not named, and a name no file can carry' {
        InModuleScope Xmip -Parameters $script:Named {
            param($Cluster, $Stage)

            [string] $r = $Stage.receiving
            [string] $p = $Stage.processing

            { Assert-XmipNodeName -Nodes $r, $r.ToLowerInvariant() } |
                Should -Throw -ExpectedMessage '*named once*'
            { Assert-XmipNodeName -Nodes $r -OnlineNodes $p } |
                Should -Throw -ExpectedMessage '*-Nodes does not*'
            { Assert-XmipNodeName -Nodes '1st' } |
                Should -Throw -ExpectedMessage '*starting with a letter*'
            { Assert-XmipNodeName -Nodes $r } | Should -Not -Throw
            { Assert-XmipNodeName -Nodes $r, "$p-2" -OnlineNodes "$p-2" } |
                Should -Not -Throw

            # A node's name is the last word of its process name and so a
            # file name (ADR-0053, amendment 2026-09-20) — and nothing more.
            # The owner, 2026-09-20: "A node is a node and can have one or
            # more roles, roll is something different." The marker in
            # xmip-playground-<cluster>-node-<name> carries the kind, so no
            # word is reserved and no name is refused for the shape's sake.
            foreach ($free in 'roll', 'Cluster', "$r-roll", "$p-cluster", 'node') {
                { Assert-XmipNodeName -Nodes $free } | Should -Not -Throw
            }
        }
    }

    It 'names a test for every scenario the roll drives, and nothing the roll does not' {
        # The owner's names — HeavyLoad, LowLatency — over the roll's scenario
        # names. SCENARIOS in scenario.rs is the roll's list and the node's; the
        # map must cover it exactly, or a test is unreachable or names nothing.
        [string] $scenarios = Join-Path $script:Root 'test/core/playground/src/scenario.rs'
        [string] $roll = Get-Content -Raw $scenarios
        [string] $pattern = '(?s)const SCENARIOS: \[&str; \d+\] = \[(.*?)\];'
        [string] $list = [regex]::Match($roll, $pattern).Groups[1].Value
        [string[]] $scenarios = @(
            [regex]::Matches($list, '"([a-z-]+)"') | ForEach-Object { $_.Groups[1].Value }
        )

        InModuleScope Xmip -Parameters @{ Scenarios = $scenarios } {
            [string[]] $mapped = @($script:XmipPlaygroundTest.Values | Sort-Object)

            $mapped | Should -Be @($Scenarios | Sort-Object)
            ConvertTo-XmipPlaygroundScenario -Test 'HeavyLoad', 'LowLatency' |
                Should -Be @('heavy-load', 'low-latency')
            ConvertTo-XmipTestName -Scenario 'low-latency' | Should -Be 'LowLatency'
            ConvertTo-XmipTestName -Scenario 'node' | Should -Be 'node'
            { ConvertTo-XmipPlaygroundScenario -Test 'Typo' } |
                Should -Throw -ExpectedMessage 'REFUSED. No test matches Typo*'
        }
    }

    It 'refuses a roll without a cluster name, since the owner names the cluster' {
        # 2026-09-14: a test may spawn nodes, never a cluster. No default name.
        [string] $node = $script:Stage.receiving

        { Start-XmipTest -Suite Core.Playground -Nodes $node -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*you name it*'
        (Get-Command -Name Start-XmipTest).Parameters['Cluster'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.PSDefaultValueAttribute] } |
            Should -BeNullOrEmpty
    }

    It 'reads no letter of a node''s name, at the door or anywhere else' {
        # The owner, 2026-09-20: "Rn, Pn and Sn are arbitrary node names."
        # Start-XmipTest kept the last shorthand in the estate for a day and
        # it is struck (ADR-0056, amendment). A node carries what
        # -NodeRole states for it and nothing otherwise. Pure.
        InModuleScope Xmip -Parameters $script:Named {
            param($Cluster, $Stage)

            # The words a role is said in, and the test cluster's own names,
            # whatever their letters suggest.
            foreach ($name in @('receiving', 'process') + $Cluster.Nodes) {
                Get-XmipNodeRole -Name $name | Should -Be ''
            }

            [string] $r = $Stage.receiving
            [string] $p = $Stage.processing
            [string] $s = $Stage.sending
            $stated = @{ $r = 'receiving'; $s = 'processing,sending'; $p = @() }
            Get-XmipNodeRole -Name $r -NodeRole $stated | Should -Be 'receiving'
            Get-XmipNodeRole -Name $s -NodeRole $stated | Should -Be 'processing,sending'
            Get-XmipNodeRole -Name $p -NodeRole $stated | Should -Be ''

            Get-XmipNodeRoleText -Nodes $Cluster.Nodes | Should -Be ''
            Get-XmipNodeRoleText -Nodes $r, $p -NodeRole $stated |
                Should -Be "$r=receiving"
            Get-XmipNodeRoleText -Nodes $r, $p -NodeRole @{
                $r = 'receiving'; $p = 'processing+sending'
            } | Should -Be "$r=receiving,$p=processing+sending"

            { ConvertTo-XmipNodeRole -Role 'relay' } |
                Should -Throw -ExpectedMessage 'REFUSED: no role is called relay*'
            { Assert-XmipNodeRole -Nodes $r -NodeRole @{ $s = 'sending' } } |
                Should -Throw -ExpectedMessage '*-Nodes does not*'
        }
    }

    It 'reads a role by the node crate''s rule, and keeps no copy of it' {
        # node::NodeRole::declared is the one parse (open problem 25, row i;
        # ADR-0056, amendment 2026-10-01), and
        # since 2026-09-24 the one implementation: this module asks
        # Xmip.Surface, which calls it in the runtime (xmip_operate.h section
        # 7). No word list is written here, in the surface, or anywhere but
        # the node crate (the owner, 2026-09-24: code is placed once).
        [string] $root = Get-XmipRepositoryRoot
        [string] $list = '[''"]receive[''"],\s*[''"]process[''"],\s*[''"]send[''"]|' +
            '[''"]receiving[''"],\s*[''"]processing[''"],\s*[''"]sending[''"]'

        foreach ($copy in @(
                'Xmip/Get-XmipNodeRole.ps1'
                'Xmip/Write-XmipTestCluster.ps1'
                'module/foundation/abi/dotnet/Xmip.Surface/ScopeTree.cs'
                'module/foundation/abi/dotnet/Xmip.Surface/NodeCapability.cs')) {
            Get-Content -Raw -LiteralPath (Join-Path $root $copy) |
                Should -Not -Match $list -Because "$copy calls the node crate's words"
        }

        InModuleScope Xmip {
            ConvertTo-XmipNodeRole -Role 'sending + receiving' | Should -Be 'receiving,sending'
            ConvertTo-XmipNodeRole -Role @('processing', 'sending') |
                Should -Be 'processing,sending'
            ConvertTo-XmipNodeRole -Role 'sending,receiving,processing' | Should -Be 'executing'
            Get-XmipNodeRoleWord | Should -Be @(
                'operational', 'monitoring', 'receiving', 'processing', 'sending', 'executing',
                'development', 'storage')

            foreach ($said in 'Sending + RECEIVING', 'receiving,relay+hold', 'receive') {
                [string] $refusal = ''
                [Xmip.Surface.NodeCapability]::Ordered($said, [ref] $refusal) | Out-Null

                $refusal | Should -BeLike 'REFUSED: no role is called *'
                { ConvertTo-XmipNodeRole -Role $said } |
                    Should -Throw -ExpectedMessage $refusal
            }
        }
    }

    It 'reads a publication, a stage and a capability record through the runtime' {
        # The owner, 2026-09-24: code is placed once. A publication's keys and
        # words are observe::Publication's, read for a surface by the runtime
        # (xmip_operate.h section 8); what a stage counts and whether it
        # pauses are observe::Counted's and node::Stage's; where a node's
        # capability record sits and how it reads are observe::capability's
        # and node::Capability's (section 7). None is written in .NET.
        [string] $root = Get-XmipRepositoryRoot
        [string] $words = '"(streams|journeys|retrying|virtual-machine|request-response|' +
            'publish-consume|fire-and-forget|configured|declares |receive location)"|' +
            'Tomlyn|is "receive" or "send"|\], "capability"'

        foreach ($copy in @(
                'module/foundation/abi/dotnet/Xmip.Surface/SnapshotOperator.cs'
                'module/foundation/abi/dotnet/Xmip.Surface/RunHeader.cs'
                'module/foundation/abi/dotnet/Xmip.Surface/NodeCapability.cs'
                'module/foundation/abi/dotnet/Xmip.Surface/ScopeIndex.cs'
                'module/foundation/abi/dotnet/Xmip.Surface/ScopeTree.cs'
                'module/core/operation/cli/src/Xmip.Cli/MeasureCommand.cs'
                'module/core/operation/gui/src/Xmip.Gui/Pages/Cluster.razor'
                'module/core/operation/gui/src/Xmip.Gui/Pages/Configuration.razor')) {
            Get-Content -Raw -LiteralPath (Join-Path $root $copy) |
                Should -Not -Match $words -Because "$copy calls the runtime for them"
        }
    }

    It 'says what nodes with no role will do, and does not refuse it' {
        # ADR-0055 clause 5: running whole tests is a real answer, and it is
        # not what someone naming three nodes is likely to have meant. Said
        # before anything spawns, naming both ways to split the path.
        InModuleScope Xmip -Parameters $script:Named {
            param($Cluster, $Stage)

            [string[]] $three = @($Stage.receiving, $Stage.processing, $Stage.sending)
            [string] $said = Get-XmipNodeRoleWarning -Nodes $three

            $said | Should -BeLike "*None of $($three -join ', ') declares a role*"
            $said | Should -BeLike '*-NodeRole*'
            $said | Should -BeLike '*omit -Nodes*'

            # Nothing to say: a role declared, a run without RoundTrip, or
            # no nodes named at all.
            [string] $r = $Stage.receiving
            Get-XmipNodeRoleWarning -Nodes $r -NodeRole @{ $r = 'receiving' } |
                Should -Be ''
            Get-XmipNodeRoleWarning -Nodes $three[0, 1] -Test 'HeavyLoad' | Should -Be ''
            Get-XmipNodeRoleWarning | Should -Be ''
        }

        [hashtable] $door = @{
            Cluster = $script:Cluster.Name
            Nodes   = @($script:Stage.receiving, $script:Stage.processing, $script:Stage.sending)
        }
        Start-XmipTest @door -WhatIf -WarningVariable said | Out-Null
        "$said" | Should -BeLike '*declares a role*'
    }

    It 'refuses RoundTrip whose nodes leave a role undeclared, before anything starts' {
        # The path is receive to process to send between the node processes,
        # and the refusal names the role nobody declared, never a letter.
        InModuleScope Xmip -Parameters $script:Named {
            param($Cluster, $Stage)

            # The stages' nodes, and a second node for each built from its name.
            [string] $r = $Stage.receiving
            [string] $p = $Stage.processing
            [string] $s = $Stage.sending
            [string] $r2 = "${r}2"
            $whole = @{ $r = 'receiving'; $p = 'processing'; $s = 'sending' }
            $half = @{ $r = 'receiving'; $r2 = 'receiving'; $s = 'sending' }

            $six = @{
                Nodes          = @($r, $r2, $p, "${p}2", $s, "${s}2")
                Test           = 'RoundTrip'
                NodeRole       = $whole + @{
                    $r2 = 'receiving'; "${p}2" = 'processing'; "${s}2" = 'sending'
                }
            }
            Get-XmipNodeRoleRefusal @six | Should -Be ''

            # The signpost an operator meets most often now that a name says
            # nothing: it names the role nobody declared and both ways
            # to declare one.
            $short = @{
                Nodes = @($r, $r2, $s); Test = 'RoundTrip'; NodeRole = $half
            }
            [string] $said = Get-XmipNodeRoleRefusal @short

            $said | Should -BeLike 'REFUSED. RoundTrip across nodes*no node declares processing.*'
            $said | Should -BeLike '*-NodeRole*'
            $said | Should -BeLike '*omit -Nodes*'

            $one = @{ Nodes = @($r); NodeRole = @{ $r = 'receiving' } }
            Get-XmipNodeRoleRefusal @one | Should -BeLike '*declares processing or sending.*'
            Get-XmipNodeRoleRefusal @one -Test 'roundtrip', 'Filing' |
                Should -BeLike 'REFUSED.*'

            # Named for nothing, but declaring the whole path: no refusal.
            $named = @{ Nodes = @($r, $p, $s); NodeRole = $whole }
            Get-XmipNodeRoleRefusal @named | Should -Be ''

            # One executing node is the whole path in one process: no refusal.
            $executing = @{ Nodes = @($r, $p); NodeRole = @{ $r = 'executing' } }
            Get-XmipNodeRoleRefusal @executing | Should -Be ''

            # Not RoundTrip, nothing declared, or no nodes: nothing to refuse.
            # A node with no role stated declares nothing, so it is the third case.
            Get-XmipNodeRoleRefusal -Nodes $r -Test 'HeavyLoad' | Should -Be ''
            Get-XmipNodeRoleRefusal -Nodes $r | Should -Be ''
            Get-XmipNodeRoleRefusal -Nodes $Cluster.Nodes | Should -Be ''
            Get-XmipNodeRoleRefusal -Nodes @() | Should -Be ''
            Get-XmipNodeRoleRefusal | Should -Be ''

            $chosen = @{
                Nodes = @($r, $s); NodeRole = @{ $r = 'receiving'; $s = 'sending' }; Named = $true
            }
            Get-XmipNodeSelectionRefusal @chosen | Should -BeLike '*no node declares processing.*'
        }

        [string] $r = $script:Stage.receiving
        [string] $s = $script:Stage.sending
        [hashtable] $door = @{
            Test           = 'RoundTrip'
            Cluster        = $script:Cluster.Name
            Nodes          = @($r, $s)
            NodeRole       = @{ $r = 'receiving'; $s = 'sending' }
            ErrorAction    = 'Stop'
        }

        { Start-XmipTest @door } |
            Should -Throw -ExpectedMessage 'REFUSED. RoundTrip across nodes*declares processing.*'
    }

    It 'rolls at the hardest level when -Stress is omitted, and a named level pins it' {
        # The owner, 2026-09-19: "Omitted -Stress, Omitted -Nodes means bring
        # it all", and asked which, he chose the hardest level over every
        # level in turn (ADR-0059, amendment). An omitted selector is the most
        # the rig can give, not a cautious default.
        $ast = (Get-Command -Name Start-XmipTest).ScriptBlock.Ast
        $stress = $ast.Body.ParamBlock.Parameters |
            Where-Object { $_.Name.VariablePath.UserPath -eq 'Stress' }

        $stress.DefaultValue.Value | Should -Be 'Brutal'

        $offered = $stress.Attributes |
            Where-Object { $_.TypeName.Name -eq 'ValidateSet' } |
            Select-Object -First 1

        @($offered.PositionalArguments | ForEach-Object { $_.Value }) |
            Should -Be @('Calm', 'Realistic', 'Harsh', 'Brutal') -Because 'a level still pins'
    }

    It 'takes the test cluster''s nodes as configured when -Nodes is omitted' {
        # The owner, 2026-10-03: parameters and configuration, xmip.toml. An
        # omitted -Nodes is the test cluster's file as it is, every node
        # declaring the roles its roles key says, and asked as named nodes
        # are: the estate's test cluster covers the path and refuses nothing.
        InModuleScope Xmip -Parameters $script:Named {
            param($Cluster, $Stage)

            $read = Read-XmipTestCluster -Path (Get-XmipTestClusterPath)
            $declared = @{}
            $read.Role.Keys | ForEach-Object { $declared[$_] = $read.Role[$_] }

            $read.Nodes | Should -Be $Cluster.Nodes
            $declared[$Stage.receiving] | Should -Be 'receiving'
            Get-XmipNodeRoleRefusal -Nodes $read.Nodes -Test 'RoundTrip' -NodeRole $declared |
                Should -Be ''
        }

        # The record says the nodes and the file they came from, never an
        # empty list: an operator who typed no -Nodes can read what they got.
        [string] $door = Get-XmipStartSource

        $door | Should -Match '(?m)^\s*nodes\s+= @\(\$Nodes\)\s*$'
        $door | Should -Match "node_names.+else \{ 'configured' \}"
        $door | Should -Match '(?m)^\s*cluster_file\s+= \$clusterFile\s*$'
    }

    It 'refuses an online node that was not named a node' {
        [string] $r = $script:Stage.receiving
        [string] $p = $script:Stage.processing

        { Start-XmipTest -Nodes $r -OnlineNodes $p -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*-Nodes does not*'
        { Start-XmipTest -OnlineNodes $r -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*name them all*'
        { Start-XmipTestNode -Nodes $r -OnlineNodes $p -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*-Nodes does not*'
    }

    It 'reads every variable the roll documents' {
        # roll.rs, environment.rs and switch.rs are the source of the names; a
        # variable the roll reads that no parameter can set is a switch an
        # operator cannot reach from PowerShell.
        [string] $roll = @(
            'test/core/playground/src/bin/roll.rs'
            'test/core/playground/src/environment.rs'
        ) | ForEach-Object { Get-Content -Raw (Join-Path $script:Root $_) }
        [string[]] $documented = @(
            [regex]::Matches($roll, 'XMIP_PLAYGROUND_[A-Z_]+') |
                ForEach-Object { $_.Value } |
                Sort-Object -Unique |
                Where-Object { $_ -ne 'XMIP_PLAYGROUND_NODE' }
        )
        [string] $file = Join-Path $script:Root 'Xmip/New-XmipPlaygroundEnvironment.ps1'
        [string] $builder = Get-Content -Raw -LiteralPath $file

        foreach ($variable in $documented) {
            $builder | Should -Match $variable -Because "the roll reads $variable"
        }
    }
}

Describe 'A suite carries its provider' {
    It 'reads a third party''s declaration and makes room for its suite' {
        # ADR-0059, and the point of the whole change: a third party adds a
        # suite by dropping a file, with no edit to Xmip's own source.
        # Example is a stand-in token and not a company: the estate names
        # no placeholder company (ADR-0059, amendment 2026-09-20).
        InModuleScope Xmip -Parameters @{ Area = $TestDrive } {
            param($Area)

            [string] $area = Join-Path $Area 'suite'
            New-Item -ItemType Directory -Path $area | Out-Null
            Set-Content -LiteralPath (Join-Path $area 'example.toml') -Encoding utf8 -Value @(
                'provider = "Example"'
                'name = "Playground"'
                'command = "Start-ExampleXmipTest"'
            )

            [object[]] $known = @(Get-XmipTestSuite -Path $area)

            @($known | ForEach-Object { $_.Name }) |
                Should -Be @('Core.Playground', 'Core.Estate', 'Example.Playground')
            $known[2].Kind | Should -Be 'command'
            $known[2].Command | Should -Be 'Start-ExampleXmipTest'
            $known[2].Provider | Should -Be 'Example'
            Get-XmipTestSuiteRefusal -Name 'example.playground' -Known $known |
                Should -Be ''
        }
    }

    It 'warns a half-written declaration by name, and keeps the other suites' {
        InModuleScope Xmip -Parameters @{ Area = $TestDrive } {
            param($Area)

            [string] $area = Join-Path $Area 'bad'
            New-Item -ItemType Directory -Path $area | Out-Null
            [string] $file = Join-Path $area 'half.toml'
            Set-Content -LiteralPath $file -Encoding utf8 -Value @(
                'provider = "Example"'
                'name = "Playground"'
            )

            [object[]] $read = @(
                Get-XmipTestSuite -Path $area -WarningVariable said -WarningAction SilentlyContinue
            )
            "$said" | Should -BeLike '*REFUSED*declares no command*'
            @($read | Where-Object { $_.Provider -eq 'Example' }) | Should -BeNullOrEmpty
            @($read | ForEach-Object { $_.Name }) | Should -Contain 'Core.Estate'

            Set-Content -LiteralPath $file -Encoding utf8 -Value @(
                'provider = "core"'
                'name = "Playground"'
                'command = "Start-ExampleXmipTest"'
            )

            [object[]] $read = @(
                Get-XmipTestSuite -Path $area -WarningVariable said -WarningAction SilentlyContinue
            )
            "$said" | Should -BeLike '*REFUSED*reserved for Xmip itself*'
            @($read | Where-Object { $_.Provider -eq 'Example' }) | Should -BeNullOrEmpty
            @($read | ForEach-Object { $_.Name }) | Should -Contain 'Core.Estate'

            Set-Content -LiteralPath $file -Encoding utf8 -Value @(
                'provider = "Example Ltd"'
                'name = "Playground"'
                'command = "Start-ExampleXmipTest"'
            )

            [object[]] $read = @(
                Get-XmipTestSuite -Path $area -WarningVariable said -WarningAction SilentlyContinue
            )
            "$said" | Should -BeLike '*REFUSED*which is not a name*'
            @($read | Where-Object { $_.Provider -eq 'Example' }) | Should -BeNullOrEmpty
            @($read | ForEach-Object { $_.Name }) | Should -Contain 'Core.Estate'
        }
    }

    It 'starts a provider''s suite through the command it declared, and refuses one it has not' {
        InModuleScope Xmip -Parameters $script:Named {
            param($Cluster, $Stage)

            [string] $c = $Cluster.Name
            [hashtable] $made = @{
                Provider = 'Example'
                Name     = 'Playground'
                Kind     = 'command'
                Command  = 'Start-ExampleXmipTest'
                Source   = 'example.toml'
            }
            $theirs = New-XmipTestSuite @made

            { Start-XmipProviderSuite -Suite $theirs -Bound @{} -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*REFUSED. Example.Playground starts with*'

            # The provider's own command, once this session has it. -Test is
            # handed on only when tests were named: nothing named is the whole
            # suite, and the provider's command is called as it would be by
            # hand for a full run.
            function global:Start-ExampleXmipTest {
                param($Cluster, $Test)

                return "example:$Cluster`:$($Test -join ',')"
            }

            try {
                [hashtable] $whole = @{ Cluster = $c; Test = @() }
                Start-XmipProviderSuite -Suite $theirs -Bound $whole |
                    Should -Be "example:${c}:"

                [hashtable] $named = @{ Cluster = $c; Test = @('Smoke') }
                Start-XmipProviderSuite -Suite $theirs -Bound $named |
                    Should -Be "example:${c}:Smoke"
            }
            finally {
                Remove-Item -LiteralPath 'function:global:Start-ExampleXmipTest' -Force
            }
        }
    }

    It 'runs the whole suite when no test is named, for every suite and every provider' {
        # The owner, 2026-09-19: -Suite with -Test excluded means run all
        # tests in the suite. One rule, one place, not two behaviors that
        # happen to agree.
        [string] $source = Get-XmipStartSource

        InModuleScope Xmip -Parameters @{ Source = $source } {
            param([string] $Source)

            Test-XmipWholeSuite | Should -BeTrue
            Test-XmipWholeSuite -Test @() | Should -BeTrue
            Test-XmipWholeSuite -Test @('') | Should -BeTrue
            Test-XmipWholeSuite -Test 'HeavyLoad' | Should -BeFalse

            # Playground: no scenarios named is every scenario, which the
            # roll reads from the variable being unset.
            $whole = @{ Stress = 'Calm'; Area = 'a' }
            $environment = New-XmipPlaygroundEnvironment @whole

            $environment.ContainsKey('XMIP_PLAYGROUND_SCENARIOS') | Should -BeFalse
            (New-XmipPlaygroundEnvironment @whole -Test HeavyLoad).XMIP_PLAYGROUND_SCENARIOS |
                Should -Be 'heavy-load'

            # Estate: no file named is every *.Test.ps1 under test/, and
            # the same predicate is what decides it there.
            $Source | Should -Match 'if \(-not \(Test-XmipWholeSuite -Test \$Test\)\) \{'
        }
    }

    It 'selects tests with wildcards, and -Test * says what omitting it says' {
        # The owner, 2026-09-19: use wild characters for parameters, for
        # instance -Test *. Wildcards and not regular expressions (ADR-0059):
        # Rust.Style is a test name and the dot in it is a dot.
        InModuleScope Xmip {
            [string[]] $seven = @($script:XmipPlaygroundTest.Keys)

            Expand-XmipTestName -Test 'Round*' -Known $seven | Should -Be @('RoundTrip')
            @(Expand-XmipTestName -Test '*' -Known $seven).Count | Should -Be $seven.Count
            Expand-XmipTestName -Test 'Heavy*', 'Heavy*' -Known $seven |
                Should -Be @('HeavyLoad') -Because 'a test named twice runs once'

            # The dot is a dot. Under a regular expression Rust.Style would
            # take RustXStyle with it; under a wildcard it takes only itself.
            [string[]] $files = @('Rust.Style', 'RustXStyle', 'XmipTest')
            Expand-XmipTestName -Test 'Rust.Style' -Known $files | Should -Be @('Rust.Style')

            { Expand-XmipTestName -Test 'Nope*' -Known $seven } |
                Should -Throw -ExpectedMessage 'REFUSED. No test matches Nope**RoundTrip*'

            ConvertTo-XmipPlaygroundScenario -Test 'Round*' | Should -Be @('round-trip')

            # -Test * is the whole suite, exactly as omitting it is: neither
            # sets XMIP_PLAYGROUND_SCENARIOS, which is how the roll is told.
            $whole = @{ Stress = 'Calm'; Area = 'a' }
            $star = New-XmipPlaygroundEnvironment @whole -Test '*'
            $none = New-XmipPlaygroundEnvironment @whole

            $star.ContainsKey('XMIP_PLAYGROUND_SCENARIOS') | Should -BeFalse
            @($star.Keys | Sort-Object) | Should -Be @($none.Keys | Sort-Object)
            Test-XmipWholeSuite -Test '*' | Should -BeTrue
        }
    }

    It 'takes wildcards where a parameter filters, and not where one names' {
        # The owner's rule, 2026-09-19: a filter takes wild characters; a
        # parameter that names what to spawn does not. [SupportsWildcards()]
        # is how a parameter announces it, and Get-Help shows it.
        [hashtable] $filters = @{
            'Start-XmipTest'     = @('Suite', 'Test')
            'Get-XmipTestResult' = @('Test', 'Node', 'Suite')
            'Get-XmipTestStatus' = @('Cluster')
            'Stop-XmipTest'      = @('Cluster', 'Test', 'Suite')
            'Get-XmipTestNode'   = @('Name')
            'Get-XmipProcess'    = @('Name')
        }

        [type] $wild = [System.Management.Automation.SupportsWildcardsAttribute]

        foreach ($command in $filters.Keys) {
            foreach ($parameter in $filters[$command]) {
                $said = (Get-Command -Name $command).Parameters[$parameter].Attributes |
                    Where-Object { $_ -is $wild }

                $said | Should -Not -BeNullOrEmpty -Because "$command -$parameter filters"
            }
        }

        # Named, not matched: -Nodes and -Cluster on Start-XmipTest name what
        # to spawn. -Suite was here until 2026-09-19, on the argument that a
        # wildcard would leave "which provider did I run" unanswerable; the
        # owner struck it — "Filter the -Suite as the -Test parameter" — and
        # a run records its own resolved suite, so the question is answered
        # per run rather than per command (ADR-0059, amendment).
        foreach ($named in 'Nodes', 'Cluster') {
            $said = (Get-Command -Name Start-XmipTest).Parameters[$named].Attributes |
                Where-Object { $_ -is $wild }

            $said | Should -BeNullOrEmpty -Because "-$named names, it does not filter"
        }
    }
}

Describe 'What a node was started with' {
    It 'is what it declared, and no command line is read' {
        # The node binary declares its flags where it starts (ADR-0053), read
        # back by the node through the runtime's library. Until 2026-09-27 this
        # module parsed the node's command line with a copy of its defaults
        # and of the words --online takes.
        InModuleScope Xmip -Parameters $script:Named {
            param($Cluster, $Stage)

            Get-Command -Name 'Read-XmipTestNodeCommandLine' -ErrorAction SilentlyContinue |
                Should -BeNullOrEmpty

            [string] $p = $Stage.processing
            [string] $location = "$($Cluster.Scope)/node/$p"
            $self = Get-Process -Id $PID
            [hashtable] $declared = @{
                $PID = [ordered]@{
                    name        = "xmip-playground-$($Cluster.Name)-node-$p"
                    location    = $location
                    purpose     = 'test'
                    node        = $p
                    shared      = 'D:\a b\shared'
                    stress      = 'harsh'
                    rounds      = '0'
                    snapshot    = "D:\a b\$p.toml"
                    interval_ms = '500'
                    role        = 'processing,sending'
                    online      = 'true'
                }
            }

            $node = ConvertTo-XmipTestNode -Process $self -Declared $declared

            $node.Name | Should -Be $p
            $node.Shared | Should -Be 'D:\a b\shared'
            $node.Stress | Should -Be 'harsh'
            $node.Rounds | Should -Be 0
            $node.Snapshot | Should -Be "D:\a b\$p.toml"
            $node.Interval | Should -Be ([timespan]::FromMilliseconds(500))
            $node.Role | Should -Be 'processing,sending'
            $node.Online | Should -BeTrue
            $node.Location | Should -Be $location
        }
    }

    It 'says nothing for a node that declared nothing, rather than a guess' {
        InModuleScope Xmip {
            $node = ConvertTo-XmipTestNode -Process (Get-Process -Id $PID) -Declared @{}

            $node.Name | Should -BeNullOrEmpty
            $node.Interval | Should -BeNullOrEmpty
            $node.Online | Should -BeFalse
            $node.Role | Should -Be ''
        }
    }
}

Describe 'What a run says' {
    BeforeAll {
        # The claim is the processing node's, the receive stage the
        # receiving node's.
        [string] $scope = $script:Cluster.Scope
        [string] $claimed = $script:Stage.processing
        [string] $receiver = $script:Stage.receiving
        $script:Snapshot = Join-Path $TestDrive "$($script:Cluster.Name)-snapshot.toml"
        @"
source = "playground"
node = "$scope"

[[records]]
scope = "$scope/round-trip/tcp/json"
state = "fine"
severity = 0
evidence = "12 rounds, all whole"
observed_unix_nanos = 1789208338038783900

[[records]]
scope = "$scope/node/$claimed/exclusive-claim/file/parallel"
state = "done"
severity = 90
evidence = "claimed twice"
observed_unix_nanos = 1789208338038783900

[[records]]
scope = "$scope/node/$receiver/receive/tcp/json"
state = "fine"
severity = 0
evidence = "12/12 rounds passed"
observed_unix_nanos = 1789208338038783900

[[records]]
scope = "$scope/node"
state = "stressed"
severity = 40
evidence = "$claimed restarted once"
observed_unix_nanos = 1789208338038783900
"@ | Set-Content -LiteralPath $script:Snapshot -Encoding utf8
    }

    It 'splits a scope into scenario, node, transport and contract' {
        [object[]] $results = @(Get-XmipTestResult -Path $script:Snapshot)

        $results.Count | Should -Be 4

        $roundTrip = $results | Where-Object { $_.Scenario -eq 'round-trip' -and $_.Node -eq '' }
        $roundTrip.Test | Should -Be 'RoundTrip'
        $roundTrip.Transport | Should -Be 'tcp'
        $roundTrip.Contract | Should -Be 'json'
        $roundTrip.Node | Should -Be ''

        $claim = $results | Where-Object Scenario -eq 'exclusive-claim'
        $claim.Node | Should -Be $script:Stage.processing
        $claim.Transport | Should -Be 'file'
        $claim.Contract | Should -Be 'parallel'

        # A role node's stage is RoundTrip's, published under the node.
        $received = $results | Where-Object Node -eq $script:Stage.receiving
        $received.Test | Should -Be 'RoundTrip'
        $received.Transport | Should -Be 'receive'
        $received.Contract | Should -Be 'tcp/json'

        # The cluster's rollup of its nodes is no node's record.
        $rollup = $results | Where-Object Scenario -eq 'node'
        $rollup.Node | Should -Be ''
        $rollup.Transport | Should -Be ''
    }

    It 'filters by test and by node, and names the worst' {
        @(Get-XmipTestResult -Path $script:Snapshot -Test RoundTrip).Count | Should -Be 2
        # A wildcard over each node's first letter picks that node alone.
        [string] $claimed = "$($script:Stage.processing[0])*"
        [string] $receiver = "$($script:Stage.receiving[0])*"

        @(Get-XmipTestResult -Path $script:Snapshot -Node $claimed).Count | Should -Be 1
        @(Get-XmipTestResult -Path $script:Snapshot -Node $receiver).Count | Should -Be 1
        (Get-XmipTestResult -Path $script:Snapshot -Worst).State | Should -Be 'done'
    }

    It 'names the worst by mood before severity, as every surface does' {
        # It sorted by severity alone, so a stressed leaf at 95 outranked a
        # done one at 90 here and nowhere else (found 2026-09-24).
        [string] $louder = Join-Path $TestDrive 'louder'
        New-Item -ItemType Directory -Path $louder | Out-Null
        [string] $copy = Join-Path $louder (Split-Path -Leaf $script:Snapshot)
        (Get-Content -LiteralPath $script:Snapshot -Raw) -replace 'severity = 40', 'severity = 95' |
            Set-Content -LiteralPath $copy -Encoding utf8

        (Get-XmipTestResult -Path $louder -Worst).State | Should -Be 'done'
    }

    It 'reads the snapshot and ranks the worst through the surface, keeping no copy' {
        # The owner, 2026-09-24: code is placed once. The snapshot reader is
        # SnapshotOperator's and the worst-first order the runtime's
        # (observe::Standing, called through ScopeTree.Worst); this module
        # parses no snapshot and ranks no mood of its own.
        [string] $script = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot (
            '../Xmip/Get-XmipTestResult.ps1'))

        $script | Should -Not -Match 'ConvertFrom-Toml|\$moods|''holding'''
        $script | Should -Match 'SnapshotOperator'
        $script | Should -Match 'ScopeTree\]::Worst'

        InModuleScope Xmip -Parameters @{ Snapshot = $script:Snapshot } {
            param($Snapshot)

            $surface = [Xmip.Surface.SnapshotOperator]::new($Snapshot)
            $all = $surface.Health([Xmip.Surface.ScopeTree]::Root)

            (Get-XmipTestResult -Path $Snapshot -Worst).Scope |
                Should -Be ([Xmip.Surface.ScopeTree]::Worst($all).Scope)
        }
    }

    It 'takes a wildcard where it takes a test name' {
        # The owner, 2026-09-19: wild characters on a filter parameter.
        @(Get-XmipTestResult -Path $script:Snapshot -Test 'Round*').Count | Should -Be 2
        @(Get-XmipTestResult -Path $script:Snapshot -Test '*').Count | Should -Be 4
        @(Get-XmipTestResult -Path $script:Snapshot -Test 'Exclusive*', 'node').Count |
            Should -Be 2
        @(Get-XmipTestResult -Path $script:Snapshot -Test 'Nope*').Count | Should -Be 0
    }

    It 'takes the directory the snapshot is in' {
        @(Get-XmipTestResult -Path $TestDrive).Count | Should -Be 4
    }

    It 'refuses to guess between two clusters in one directory' {
        [string] $two = Join-Path $TestDrive 'two'
        New-Item -ItemType Directory -Path $two | Out-Null
        [string[]] $files = @($script:Cluster.Name, "$($script:Cluster.Name)2") |
            ForEach-Object { "$_-snapshot.toml" }

        foreach ($file in $files) {
            Copy-Item -Path $script:Snapshot -Destination (Join-Path $two $file)
        }

        [string] $said = try {
            Get-XmipTestResult -Path $two -ErrorAction Stop
        }
        catch {
            "$_"
        }

        foreach ($file in $files) {
            $said | Should -BeLike "*$file*"
        }
    }

    It 'says where a snapshot should be when there is none' {
        { Get-XmipTestResult -Path (Join-Path $TestDrive 'nowhere') -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*No snapshot*'
    }
}

Describe 'A cluster rolls once' {
    It 'finds the roll already running as a cluster, and none for another name' {
        InModuleScope Xmip -Parameters @{ Area = $TestDrive; Name = $script:Cluster.Name } {
            param($Area, $Name)

            # 2026-09-18: three rolls of one cluster overwrote one another's
            # snapshot. One record spells the suite as this morning wrote it
            # and one as the estate writes it now: a run is found by its
            # cluster, and an older record still reads (ADR-0059, 2026-09-20).
            # The names hold one another: the test cluster's is the end of
            # the first, which begins the second.
            [string] $one = "$($Name[0])$Name"
            [string] $ten = "${one}0"
            Set-Content -LiteralPath (Join-Path $Area 'roll-4242.toml') -Encoding utf8 -Value @(
                'suite = "Playground"'
                "cluster = `"$one`""
                'pid = 4242'
            )
            Set-Content -LiteralPath (Join-Path $Area 'roll-4343.toml') -Encoding utf8 -Value @(
                'suite = "Core.Playground"'
                "cluster = `"$ten`""
                'pid = 4343'
            )

            @(Get-XmipPlaygroundRolling -Path $Area -Cluster $one) | Should -Be @(4242)
            @(Get-XmipPlaygroundRolling -Path $Area -Cluster $ten) | Should -Be @(4343)
            @(Get-XmipPlaygroundRolling -Path $Area -Cluster $Name).Count | Should -Be 0
        }
    }
}

Describe 'What a web host reads' {
    It 'is read back from its command line' {
        InModuleScope Xmip {
            [string] $line = 'xmip-gui-web.exe ' +
                '--Kestrel:Endpoints:Http:Url=http://127.0.0.1:5087 ' +
                '--Xmip:Surface=snapshot "--Xmip:Snapshot=D:\a b\snapshot.toml"'

            Read-XmipOperationWebArgument -CommandLine $line -Name 'Kestrel:Endpoints:Http:Url' |
                Should -Be 'http://127.0.0.1:5087'
            Read-XmipOperationWebArgument -CommandLine $line -Name 'Xmip:Surface' |
                Should -Be 'snapshot'
            Read-XmipOperationWebArgument -CommandLine $line -Name 'Xmip:Role' | Should -Be ''
        }
    }

    It 'warns that it will not show a roll it was not pointed at, and says how to' {
        InModuleScope Xmip -Parameters @{ Name = $script:Cluster.Name } {
            param($Name)

            $rolling = [PSCustomObject]@{ Suite = 'Core.Playground'; Cluster = $Name }
            Mock -CommandName Start-Process -MockWith { [PSCustomObject]@{ Id = 1 } }
            Mock -CommandName Test-XmipOperationWebAnswering -MockWith { $false }
            Mock -CommandName Get-XmipTestStatus -MockWith { $rolling }

            Start-XmipOperationWeb -WarningVariable said -WarningAction SilentlyContinue
            "$said" | Should -BeLike "*will not show the roll $Name*Get-XmipTestStatus |*"

            # A snapshot that is there: ADR-0055 refuses one that is not.
            [string] $real = Join-Path ([System.IO.Path]::GetTempPath()) 'xmip-warn.toml'
            Set-Content -LiteralPath $real -Value '' -NoNewline

            try {
                Start-XmipOperationWeb -Snapshot $real -WarningVariable quiet
                $quiet | Should -BeNullOrEmpty -Because 'it was pointed at a snapshot'
            }
            finally {
                Remove-Item -LiteralPath $real -Force -ErrorAction SilentlyContinue
            }
        }
    }

    It 'refuses a snapshot that is not there and an address that is not one' {
        # ADR-0055: the door is the parameter. A host over a path that is
        # not there answers and shows nothing, which is what the owner met
        # three times on 2026-09-19.
        InModuleScope Xmip {
            Mock -CommandName Start-Process -MockWith { [PSCustomObject]@{ Id = 1 } }

            [string] $gone = Join-Path ([System.IO.Path]::GetTempPath()) 'xmip-no-such.toml'

            { Start-XmipOperationWeb -Snapshot $gone } |
                Should -Throw -ExpectedMessage '*REFUSED*No snapshot*'
            { Start-XmipOperationWeb -Url 'localhost:5087' } |
                Should -Throw -ExpectedMessage '*REFUSED*not an address*'
            Should -Invoke -CommandName Start-Process -Times 0
        }
    }

    It 'waits for a snapshot a rolling cluster has not published yet' {
        # The owner, 2026-09-23, piping two fresh rolls into the monitor: a
        # roll publishes when its first round ends, so the file a run names
        # is not there yet, and being refused for it is the tool arguing with
        # what it was just told. It waits instead, and only while the run is
        # there.
        InModuleScope Xmip -Parameters @{ Name = $script:Cluster.Name } {
            param($Name)

            [string] $coming = Join-Path ([System.IO.Path]::GetTempPath()) (
                "xmip-$Name-snapshot.toml")
            $rolling = [PSCustomObject]@{ Cluster = $Name; Snapshot = $coming }

            Mock -CommandName Get-XmipTestStatus -MockWith { $rolling }
            Mock -CommandName Start-Sleep -MockWith {
                # The round ends while the wait sleeps.
                Set-Content -LiteralPath $coming -Value 'published'
            }

            { Wait-XmipSnapshot -Path $coming } | Should -Not -Throw
            Should -Invoke -CommandName Start-Sleep -Times 1
            Remove-Item -LiteralPath $coming -ErrorAction SilentlyContinue
        }
    }

    It 'refuses a snapshot a run names and then stops without publishing' {
        InModuleScope Xmip -Parameters @{ Name = $script:Cluster.Name } {
            param($Name)

            [string] $never = Join-Path ([System.IO.Path]::GetTempPath()) (
                "xmip-$Name-never-snapshot.toml")
            $rolling = [PSCustomObject]@{ Cluster = $Name; Snapshot = $never }
            $script:asked = 0

            Mock -CommandName Start-Sleep -MockWith { }
            Mock -CommandName Get-XmipTestStatus -MockWith {
                $script:asked++
                if ($script:asked -eq 1) { $rolling } else { @() }
            }

            { Wait-XmipSnapshot -Path $never } |
                Should -Throw -ExpectedMessage "*REFUSED*$Name stopped without publishing*"
        }
    }

    It 'refuses an empty pipeline: nothing is rolling, so there is nothing to follow' {
        InModuleScope Xmip {
            Mock -CommandName Start-Process -MockWith { [PSCustomObject]@{ Id = 1 } }

            { @() | Start-XmipOperationWeb } |
                Should -Throw -ExpectedMessage 'REFUSED*nothing is rolling*'
            Should -Invoke -CommandName Start-Process -Times 0
        }
    }

    It 'refuses an address that already answers, and starts nothing there' {
        # The owner's console, 2026-09-19: a second host on a held port died
        # silently and the first kept answering over the wrong surface.
        InModuleScope Xmip {
            $listener = [System.Net.Sockets.TcpListener]::new(
                [System.Net.IPAddress]::Loopback, 0)
            $listener.Start()

            try {
                [string] $url = "http://127.0.0.1:$($listener.LocalEndpoint.Port)"
                Mock -CommandName Start-Process -MockWith { }

                Test-XmipOperationWebAnswering -Url $url | Should -BeTrue
                { Start-XmipOperationWeb -Url $url } | Should -Throw -ExpectedMessage 'REFUSED*'
                Should -Invoke -CommandName Start-Process -Times 0
            }
            finally {
                $listener.Stop()
            }

            Test-XmipOperationWebAnswering -Url $url | Should -BeFalse
        }
    }
}

Describe 'A run whose binaries changed underneath it' {
    <#
        2026-09-19: the owner's roll, its cluster and its nodes were alive
        while Get-XmipTestStatus and Get-XmipTestNode said nothing, because the
        Playground binaries had been rebuilt under the running processes. A
        process Xmip started and cannot find is a process Xmip cannot stop, so
        the file on disk no longer decides, and a disagreement is said.
    #>
    BeforeAll {
        $script:Built = 'D:/playground/target/debug/xmip-playground-roll.exe'
        $script:Moved = 'D:/playground/target/debug/xmip-playground-roll.exe.old'
    }

    It 'is still the Playground''s run, and the image is said not to be the file' {
        InModuleScope Xmip -Parameters @{ Built = $script:Built; Moved = $script:Moved } {
            param($Built, $Moved)

            [hashtable] $rebuilt = @{
                Id       = 4242
                Name     = 'xmip-playground-roll'
                Image    = $Moved
                Declared = ''
                Expected = $Built
            }

            Test-XmipPlaygroundImage @rebuilt -WarningVariable said -WarningAction Continue |
                Should -BeTrue -Because 'it is the run, whatever happened to the file'
            "$said" | Should -BeLike '*rebuilt, renamed or moved*'
        }
    }

    It 'takes the binary a process declared it started from as proof' {
        InModuleScope Xmip -Parameters @{ Built = $script:Built } {
            param($Built)

            # ADR-0053: it said where it started, and that does not change.
            [hashtable] $elevated = @{
                Id       = 4242
                Name     = 'xmip-playground-roll'
                Image    = ''
                Declared = $Built
                Expected = $Built
            }

            Test-XmipPlaygroundImage @elevated -WarningVariable quiet | Should -BeTrue
            $quiet | Should -BeNullOrEmpty -Because 'nothing disagreed'
        }
    }

    It 'is not a process that is no Xmip process' {
        InModuleScope Xmip -Parameters @{ Built = $script:Built } {
            param($Built)

            [hashtable] $stranger = @{
                Id       = 4242
                Name     = 'notepad'
                Image    = 'C:/Windows/notepad.exe'
                Declared = ''
                Expected = $Built
            }

            Test-XmipPlaygroundImage @stranger | Should -BeFalse
        }
    }

    It 'names a parent by its pid, never by the file its image came from' {
        # The half that cost three orphaned nodes: this machine calls a parent
        # by the image file's current name, so a rebuild renamed every parent
        # and no node had a roll to be stopped with.
        InModuleScope Xmip {
            [hashtable] $said = @{ 4242 = @{ name = 'xmip-playground-cluster' } }

            Resolve-XmipProcessName -Id 4242 -Declared $said |
                Should -Be 'xmip-playground-cluster'
            Resolve-XmipProcessName -Id 0 -Declared $said | Should -Be ''
            Resolve-XmipProcessName -Id 2000000000 -Declared @{ } | Should -Be ''
        }
    }
}

Describe 'A stopped roll leaves no node of its cluster running' {
    <#
        2026-09-25: a brutal roll's cluster restarted its nodes faster than
        they could be listed. Get-XmipTestStatus said Nodes: none, the nodes'
        parents could not be read at the moment they were asked, and
        Stop-XmipTest left seventeen of them running after their cluster
        ended. A node's cluster is what it declared (ADR-0053), which does not
        depend on the moment; the stop ends every process declared in the
        cluster, whatever the process tree said.
    #>
    It 'reads a declared location as the cluster''s, and a longer name as another''s' {
        InModuleScope Xmip -Parameters $script:Named {
            param($Cluster, $Stage)

            # A longer name the test cluster's begins.
            [string] $c = $Cluster.Name
            [string] $node = $Cluster.Nodes[0]
            Test-XmipClusterLocation -Location $Cluster.Scope -Cluster $c | Should -BeTrue
            Test-XmipClusterLocation -Location "$($Cluster.Scope)/node/$node" -Cluster $c |
                Should -BeTrue
            Test-XmipClusterLocation -Location "$($Cluster.Scope)0/node/$node" -Cluster $c |
                Should -BeFalse
            Test-XmipClusterLocation -Location '' -Cluster $c | Should -BeFalse
            Test-XmipClusterLocation -Location $Cluster.Scope -Cluster '' | Should -BeFalse
        }
    }

    It 'counts a node whose parent could not be read as its cluster''s roll''s' {
        InModuleScope Xmip -Parameters $script:Named {
            param($Cluster, $Stage)

            [string] $node = $Cluster.Nodes[0]
            $roll = [PSCustomObject]@{ Id = 4242; Cluster = $Cluster.Name }
            $orphan = [PSCustomObject]@{
                Parent = $null; Location = "$($Cluster.Scope)/node/$node"
            }
            $child = [PSCustomObject]@{ Parent = 4242; Location = '' }
            $other = [PSCustomObject]@{
                Parent = $null; Location = "$($Cluster.Scope)2/node/$node"
            }

            Test-XmipTestNodeOfRoll -Node $orphan -Roll $roll | Should -BeTrue
            Test-XmipTestNodeOfRoll -Node $child -Roll $roll | Should -BeTrue
            Test-XmipTestNodeOfRoll -Node $other -Roll $roll | Should -BeFalse
        }
    }

    It 'ends every process declared in the cluster, and nothing declared elsewhere' {
        InModuleScope Xmip -Parameters $script:Named {
            param($Cluster, $Stage)

            # The test cluster, and another whose name begins with its name.
            [string] $c = $Cluster.Name
            [string] $longer = "${c}0"
            [string] $node = $Cluster.Nodes[0]
            [hashtable] $declared = @{
                4242 = @{ name = "xmip-playground-$c-roll"; location = $Cluster.Scope }
                4243 = @{ name = "xmip-playground-$c-cluster"; location = $Cluster.Scope }
                4244 = @{
                    name     = "xmip-playground-$c-node-$node"
                    location = "$($Cluster.Scope)/node/$node"
                }
                4245 = @{
                    name     = "xmip-playground-$longer-node-$node"
                    location = "xmip:///$longer/node/$node"
                }
            }
            Mock Get-XmipPlaygroundProcess { }
            Mock Wait-Process { }
            Mock Stop-Process { }
            Mock Read-XmipProcessDeclaration { $declared }

            Stop-XmipTestCluster -Parent 4242 -Cluster $c

            Should -Invoke Stop-Process -Times 1 -Exactly -ParameterFilter { $Id -eq 4243 }
            Should -Invoke Stop-Process -Times 1 -Exactly -ParameterFilter { $Id -eq 4244 }
            Should -Invoke Stop-Process -Times 0 -Exactly -ParameterFilter { $Id -eq 4245 }
            Should -Invoke Stop-Process -Times 0 -Exactly -ParameterFilter { $Id -eq 4242 }
        }
    }

    It 'asks the nodes of a roll to leave by what they declared, not by the tree alone' {
        [string] $source = Get-Content -Raw -LiteralPath (
            Join-Path $script:Root 'Xmip/Stop-XmipTest.ps1')

        $source | Should -Match 'Test-XmipTestNodeOfRoll -Node \$_ -Roll \$roll'
        $source | Should -Match 'Stop-XmipTestCluster -Parent \$number -Cluster'
    }
}

Describe 'What a history file holds' {
    <#
        ADR-0029: a history point is a counted measurement over time. Every
        history the Playground published between 2026-09-05 and 2026-09-19
        held none, and no surface said so.
    #>
    It 'is read back point by point, oldest first' {
        [hashtable] $given = @{ Area = $TestDrive; Scope = $script:Cluster.Scope }

        InModuleScope Xmip -Parameters $given {
            param($Area, $Scope)

            [string] $path = Join-Path $Area 'history.toml'
            Set-Content -LiteralPath $path -Encoding utf8 -Value @(
                "node = `"$Scope`""
                '[[points]]'
                'counted = "bytes"'
                'observed_unix_nanos = 1757000000000000000'
                'value = 1024'
                '[[points]]'
                'counted = "messages"'
                'observed_unix_nanos = 1757000001000000000'
                'value = 7'
            )

            [object[]] $read = @(Get-XmipHistory -Path $path)

            $read.Count | Should -Be 2
            $read[0].Node | Should -Be $Scope
            $read[0].Counted | Should -Be 'bytes'
            $read[0].Value | Should -Be 1024
            @(Get-XmipHistory -Path $path -Counted messages).Value | Should -Be 7
            { Get-XmipHistory -Path $path -Counted Messages -ErrorAction Stop } |
                Should -Throw -ExpectedMessage 'REFUSED: no counted kind is called Messages*'
        }
    }

    It 'reads the file through the runtime''s reader, walking no TOML and naming no kind' {
        # The owner, 2026-09-24: code is placed once. The history's shape is
        # observe::Curve's, read through xmip_operate.h section 8.
        [string] $script = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot (
            '../Xmip/Get-XmipHistory.ps1'))

        $script | Should -Not -Match 'ConvertFrom-Toml|Get-TomlValue|''(streams|bytes)'''
        $script | Should -Match 'Publications\.Curve'
    }

    It 'says in words that a producer wrote no points, rather than nothing' {
        [hashtable] $given = @{ Area = $TestDrive; Scope = $script:Cluster.Scope }

        InModuleScope Xmip -Parameters $given {
            param($Area, $Scope)

            [string] $path = Join-Path $Area 'empty-history.toml'
            Set-Content -LiteralPath $path -Encoding utf8 -Value @(
                "node = `"$Scope`""
                'points = []'
            )

            [object[]] $read = @(
                Get-XmipHistory -Path $path -WarningVariable said -WarningAction Continue
            )

            $read.Count | Should -Be 0
            "$said" | Should -BeLike '*holds no points*'
        }
    }
}

Describe 'Stop-XmipTest picks runs by cluster and test, and refuses what it cannot do' {
    # The owner, 2026-09-21: Stop-XmipTest -Cluster <Cluster> -Test <Test> was
    # missing, and -Test was bound to the pipeline's status object, so the
    # word meant a test on Start-XmipTest and a run on Stop-XmipTest.
    BeforeAll {
        # A run as Get-XmipTestStatus describes it, and nothing more: the
        # choosing is tested without a process started or stopped.
        function New-FakeRoll {
            param([int] $Id, [string] $Cluster, [string[]] $Tests = @())

            [PSCustomObject]@{
                Id      = $Id
                Cluster = $Cluster
                Suite   = 'Core.Playground'
                Tests   = $Tests
            }
        }

        # Three clusters' names: the test cluster's and two built from it.
        [string] $c = $script:Cluster.Name
        $script:One = $c
        $script:Two = "${c}2"
        $script:Three = "${c}3"
    }

    It 'takes a test by name, and the pipeline object as -InputObject' {
        $parameters = (Get-Command -Name Stop-XmipTest).Parameters

        $parameters['Test'].ParameterType | Should -Be ([string[]])
        $parameters['InputObject'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } |
            ForEach-Object { $_.ValueFromPipeline } |
            Should -Contain $true

        @($parameters['Cluster'].ParameterSets.Keys) | Should -Contain 'Filter'
        @($parameters['Test'].ParameterSets.Keys) | Should -Contain 'Filter'
    }

    It 'stops the run a cluster and a test name pick, as they were started' {
        [object[]] $running = @(
            New-FakeRoll -Id 11 -Cluster $script:One -Tests RoundTrip
            New-FakeRoll -Id 12 -Cluster $script:Two -Tests RoundTrip, Retention
            New-FakeRoll -Id 13 -Cluster $script:Three
        )
        [hashtable] $given = @{
            Running = $running; One = $script:One; Two = $script:Two; Three = $script:Three
        }

        InModuleScope Xmip -Parameters $given {
            param($Running, $One, $Two, $Three)

            @(Select-XmipTestRoll -Running $Running -Cluster $One -Test RoundTrip).Id |
                Should -Be 11
            @(Select-XmipTestRoll -Running $Running -Cluster $Two -Test RoundTrip, Retention).Id |
                Should -Be 12
            @(Select-XmipTestRoll -Running $Running -Cluster $Three -Test '*').Id |
                Should -Be 13 -Because 'a run of the whole suite is every test in it'
            @(Select-XmipTestRoll -Running $Running).Count |
                Should -Be 3 -Because 'nothing named is every run'
        }
    }

    It 'refuses a run that also drives a test not named, and picks nothing' {
        [object[]] $running = @(
            New-FakeRoll -Id 11 -Cluster $script:One -Tests RoundTrip
            New-FakeRoll -Id 12 -Cluster $script:Two -Tests RoundTrip, Retention
        )

        InModuleScope Xmip -Parameters @{ Running = $running } {
            param($Running)

            { Select-XmipTestRoll -Running $Running -Test RoundTrip -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*REFUSED*also runs Retention*Nothing was stopped*'

            # The first alone would qualify and is not picked: a refused command has
            # done nothing (ADR-0055 clause 2).
            [object[]] $picked = @(
                Select-XmipTestRoll -Running $Running -Test RoundTrip -ErrorAction SilentlyContinue
            )
            $picked.Count | Should -Be 0
        }
    }

    It 'refuses a cluster or a test that nothing running matches, naming what is' {
        [object[]] $running = @(New-FakeRoll -Id 11 -Cluster $script:One -Tests RoundTrip)
        [hashtable] $given = @{ Running = $running; One = $script:One; Two = $script:Two }

        InModuleScope Xmip -Parameters $given {
            param($Running, $One, $Two)

            [string] $nothing = "*REFUSED. No roll matches $Two. Rolling now: " +
                "$One running RoundTrip.*"
            { Select-XmipTestRoll -Running $Running -Cluster $Two -ErrorAction Stop } |
                Should -Throw -ExpectedMessage $nothing

            [string] $none = "*REFUSED. No roll on $One runs a test matching Storm.*"
            { Select-XmipTestRoll -Running $Running -Cluster $One -Test Storm -ErrorAction Stop } |
                Should -Throw -ExpectedMessage $none
            { Select-XmipTestRoll -Running @() -Test RoundTrip -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Nothing is rolling.*'
        }
    }

    It 'picks by suite as Start-XmipTest names it, and names a run with no cluster' {
        # The estate's Pester run has no cluster; -Suite is how it is named
        # among the runs, and it is spelled as Start-XmipTest spells it.
        [object[]] $running = @(
            New-FakeRoll -Id 11 -Cluster $script:One -Tests RoundTrip
            [PSCustomObject]@{ Id = 77; Cluster = $null; Suite = 'Core.Estate'; Tests = @() }
        )

        InModuleScope Xmip -Parameters @{ Running = $running; One = $script:One } {
            param($Running, $One)

            @(Select-XmipTestRoll -Running $Running -Suite Estate).Id | Should -Be 77
            @(Select-XmipTestRoll -Running $Running -Suite 'Core.*').Count | Should -Be 2

            [string] $nothing = '*REFUSED. No run of a suite matching Nope* is running.*' +
                "$One running RoundTrip; Core.Estate 77 running the whole suite.*"
            { Select-XmipTestRoll -Running $Running -Suite 'Nope*' -ErrorAction Stop } |
                Should -Throw -ExpectedMessage $nothing
        }
    }
}

Describe 'A run of the estate suite is started, observed and stopped like a roll' {
    <#
        The owner, 2026-09-25: Start-XmipTest -Suite Core.Estate held his
        console for ten minutes. It runs in a pwsh of its own now and writes
        a record; these check the start without running the estate's suite,
        over a directory of two tiny test files, and the record without a
        process at all.
    #>
    BeforeAll {
        $script:Tiny = Join-Path $TestDrive 'tiny'
        $script:Area = Join-Path $TestDrive 'estate'
        New-Item -ItemType Directory -Path $script:Tiny, $script:Area | Out-Null

        Set-Content -LiteralPath (Join-Path $script:Tiny 'Kept.Test.ps1') -Encoding utf8 -Value @(
            "Describe 'kept' { It 'holds' { 1 | Should -Be 1 } }"
        )
        Set-Content -LiteralPath (Join-Path $script:Tiny 'Broken.Test.ps1') -Encoding utf8 -Value @(
            "Describe 'broken' { It 'breaks' { 1 | Should -Be 2 } }"
        )
    }

    It 'starts in its own pwsh, returns at once running, and writes the verdict itself' {
        [hashtable] $given = @{ Tiny = $script:Tiny; Area = $script:Area }

        InModuleScope Xmip -Parameters $given {
            param($Tiny, $Area)

            $real = Get-XmipPlaygroundLayout
            Mock -CommandName Get-XmipPlaygroundLayout -MockWith {
                [PSCustomObject]@{ Root = $real.Root; Estate = $Area; Suffix = $real.Suffix }
            }

            [datetime] $asked = Get-Date
            $run = Start-XmipEstateSuite -Path $Tiny -Test 'Kept', 'Brok*' 6>$null

            ((Get-Date) - $asked).TotalSeconds | Should -BeLessThan 15 -Because 'nothing waits'
            $run.Suite | Should -Be 'Core.Estate'
            $run.Kind | Should -Be 'pester'
            $run.State | Should -Be 'running'
            @($run.Tests) | Should -Be @('Kept', 'Broken')
            Test-Path -LiteralPath $run.Record | Should -BeTrue

            [datetime] $until = (Get-Date).AddMinutes(3)

            while ((Get-Date) -lt $until -and
                (Get-XmipEstateRun -Path $Area | Where-Object Id -EQ $run.Id).State -eq 'running') {
                Start-Sleep -Milliseconds 500
            }

            $ended = Get-XmipEstateRun -Path $Area | Where-Object Id -EQ $run.Id
            $ended.State | Should -Be 'FAILED' -Because (Get-Content -Raw $ended.Log)
            $ended.Passed | Should -Be 1
            $ended.Failed | Should -Be 1

            [object[]] $failed = @(Get-XmipTestResult -Suite Core.Estate -Path $Area)
            $failed.Count | Should -Be 1
            $failed[0].Test | Should -Be 'Broken'
            $failed[0].Name | Should -Be 'broken.breaks'
            $failed[0].Message | Should -BeLike '*Expected 2*'
            @(Get-XmipTestResult -Suite Core.Estate -Path $Area -Test 'Kept').Count | Should -Be 0
        }
    }

    It 'refuses a file pattern that matches nothing, before anything starts' {
        InModuleScope Xmip -Parameters @{ Tiny = $script:Tiny } {
            param($Tiny)

            Mock -CommandName Start-Process -MockWith { }

            { Start-XmipEstateSuite -Path $Tiny -Test 'Nope*' } |
                Should -Throw -ExpectedMessage 'REFUSED. No test matches Nope*Broken, Kept*'
            Should -Invoke -CommandName Start-Process -Times 0
        }
    }

    It 'reads a record, says a run that died without a verdict FAILED, and never OK' {
        InModuleScope Xmip -Parameters @{ Area = (Join-Path $TestDrive 'died') } {
            param($Area)

            New-Item -ItemType Directory -Path $Area | Out-Null
            Set-Content -LiteralPath (Join-Path $Area 'estate-20260925-120000-000.toml') -Value @(
                'suite = "Core.Estate"'
                'pid = 2000000000'
                'started = "2026-09-25T10:00:00.0000000Z"'
                'tests = []'
                'log = "x.log"'
            )

            $run = Get-XmipEstateRun -Path $Area
            $run.State | Should -Be 'FAILED'
            $run.Fault | Should -BeLike '*without a verdict*'

            (Get-XmipEstateResult -Path $Area).Message | Should -BeLike '*without a verdict*'

            Remove-XmipEstateFinished -Path $Area
            @(Get-XmipEstateRun -Path $Area).Count | Should -Be 0
        }
    }

    It 'stops a running one, its pwsh and its record, and refuses one that ended' {
        InModuleScope Xmip -Parameters @{ Area = (Join-Path $TestDrive 'stop') } {
            param($Area)

            New-Item -ItemType Directory -Path $Area | Out-Null
            [hashtable] $sleeping = @{
                FilePath     = Join-Path $PSHOME "pwsh$((Get-XmipPlaygroundLayout).Suffix)"
                ArgumentList = @('-NoProfile', '-Command', 'Start-Sleep -Seconds 120')
                PassThru     = $true
            }

            if ($IsWindows) {
                $sleeping.WindowStyle = 'Hidden'
            }

            $process = Start-Process @sleeping
            [hashtable] $start = @{
                Record  = Join-Path $Area 'estate-20260925-120000-001.toml'
                Suite   = 'Core.Estate'
                Path    = $Area
                Log     = Join-Path $Area 'estate-20260925-120000-001.log'
                Id      = $process.Id
                Started = $process.StartTime
            }
            Write-XmipEstateStart @start

            $run = Get-XmipEstateRun -Path $Area
            $run.State | Should -Be 'running'

            Stop-XmipEstateRun -Run $run
            $process.HasExited | Should -BeTrue
            Test-Path -LiteralPath $start.Record | Should -BeFalse

            Mock -CommandName Get-XmipTestStatus -MockWith {
                [PSCustomObject]@{ Id = 5; Kind = 'pester'; State = 'OK'; Suite = 'Core.Estate' }
            }
            { Stop-XmipTest -Id 5 -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*REFUSED*run 5 has ended (OK)*'
        }
    }
}

AfterAll {
    $env:XMIP_AUDIT_DIRECTORY = $script:AuditBefore
}
