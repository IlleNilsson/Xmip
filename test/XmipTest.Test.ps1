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
    <#
        .SYNOPSIS
        Start-XmipTest's source, every file of it.

        .DESCRIPTION
        One file of 944 lines until 2026-09-22 and a family now: the cmdlet,
        the suite groups, and the Playground roll it hands its work to. A test
        asking what the start does reads all three, so it does not care which
        file a line moved to.
    #>
    function Get-XmipStartSource {
        [string] $module = Join-Path (Get-XmipRepositoryRoot) 'Xmip'

        return ((
                'Start-XmipTest.ps1', 'Start-XmipTestSuiteGroup.ps1',
                'Start-XmipPlaygroundRoll.ps1' | ForEach-Object {
                    Get-Content -Raw -LiteralPath (Join-Path $module $_)
                }
            ) -join "`n")
    }

    $script:Root = Join-Path $PSScriptRoot '..'
    $script:ManifestPath = Join-Path $script:Root 'Xmip/Xmip.psd1'

    Get-Module -Name Xmip -All | Remove-Module -Force -ErrorAction SilentlyContinue
    Import-Module $script:ManifestPath -Force
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
            Start-XmipTest -Suite * -Cluster Z3 -Rounds 1 -WhatIf 6>&1 |
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

    It 'runs the estate suite in its own runspace, never in the module it tests' {
        # 2026-09-12: these files begin by removing Xmip and importing it
        # afresh. Run from inside the module, the suite tore down the module
        # that was running it, and every later call from the console found a
        # hollow module. A thread job keeps the runspace apart.
        [string] $door = Get-XmipStartSource

        $door | Should -Match 'Start-ThreadJob' -Because 'the suite removes the module it runs in'
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
            $least = @{ Stress = 'Harsh'; Snapshot = 's'; History = 'h'; Activity = 'a' }
            $environment = New-XmipPlaygroundEnvironment @least

            $environment.XMIP_PLAYGROUND_STRESS | Should -Be 'harsh'
            $environment.XMIP_PLAYGROUND_SNAPSHOT | Should -Be 's'
            $environment.Keys | Should -Not -Contain 'XMIP_ONLINE'
            $environment.Keys | Should -Not -Contain 'XMIP_PLAYGROUND_ONLINE_NODES'
            $environment.Keys | Should -Not -Contain 'XMIP_PLAYGROUND_NODES'
            $environment.Keys | Should -Not -Contain 'XMIP_PLAYGROUND_MAX_SECONDS'
            $environment.Keys | Should -Not -Contain 'XMIP_PLAYGROUND_SCENARIOS'
            $environment.Keys | Should -Not -Contain 'XMIP_PLAYGROUND_CLUSTER'
        }
    }

    It 'says the tests, the nodes, the online nodes and the limits the way the roll parses them' {
        InModuleScope Xmip {
            $chosen = @{
                Stress         = 'Brutal'
                Test           = @('roundtrip', 'HeavyLoad')
                Nodes          = @('R1', 'P1', 'S1')
                NodeCapability = @{ R1 = 'receive'; P1 = 'process'; S1 = 'send' }
                OnlineNodes    = @('R1', 'S1')
                Cluster        = 'SN2'
                Duration       = [timespan]::FromMinutes(15)
                TimeFactor     = 9.5e-6
                LoadBytes      = '512mb'
                Image          = 'i'
                Snapshot       = 's'
                History        = 'h'
                Activity       = 'a'
            }
            $environment = New-XmipPlaygroundEnvironment @chosen

            $environment.XMIP_PLAYGROUND_SCENARIOS | Should -Be 'round-trip,heavy-load'
            $environment.XMIP_PLAYGROUND_NODE_NAMES | Should -Be 'R1,P1,S1'
            $environment.XMIP_PLAYGROUND_ONLINE_NODES | Should -Be 'R1,S1'
            $environment.XMIP_PLAYGROUND_NODE_CAPABILITIES |
                Should -Be 'R1=receive,P1=process,S1=send'
            $environment.XMIP_PLAYGROUND_CLUSTER | Should -Be 'SN2'
            $environment.Keys | Should -Not -Contain 'XMIP_PLAYGROUND_NODES'
            $environment.XMIP_PLAYGROUND_MAX_SECONDS | Should -Be '900'
            $environment.XMIP_PLAYGROUND_TIME_FACTOR | Should -Be '9.5E-06'
            $environment.XMIP_PLAYGROUND_LOAD_BYTES | Should -Be '512mb'
            $environment.XMIP_PLAYGROUND_IMAGES | Should -Be 'i'
        }
    }

    It 'takes how many nodes as well as which, and leaves the naming to the roll' {
        # The owner, 2026-09-23: how many nodes in each cluster I want. A
        # node's name starts with a letter, so a lone number is no name and
        # can only be a count; the roll names those nodes and deals them over
        # receive, process and send, as it does for an omitted -Nodes.
        InModuleScope Xmip {
            $common = @{ Stress = 'Calm'; Snapshot = 's'; History = 'h'; Activity = 'a' }

            $counted = New-XmipPlaygroundEnvironment @common -Cluster orders -Nodes 6
            $named = New-XmipPlaygroundEnvironment @common -Cluster orders -Nodes 'east', 'west'

            $counted.XMIP_PLAYGROUND_NODES | Should -Be '6'
            $counted.Keys | Should -Not -Contain 'XMIP_PLAYGROUND_NODE_NAMES'
            $named.XMIP_PLAYGROUND_NODE_NAMES | Should -Be 'east,west'
            $named.Keys | Should -Not -Contain 'XMIP_PLAYGROUND_NODES'

            Get-XmipNodeCount -Nodes @('6') | Should -Be 6
            Get-XmipNodeCount -Nodes @('0') | Should -Be 0
            Get-XmipNodeCount -Nodes @('east', 'west') | Should -Be -1
            Get-XmipNodeCount -Nodes @('R1') | Should -Be -1
            Get-XmipNodeCount -Nodes @() | Should -Be -1
        }
    }

    It 'names nodes, one process each, and an empty list is no nodes' {
        InModuleScope Xmip {
            $none = @{ Stress = 'Harsh'; Nodes = @(); Snapshot = 's'; History = 'h' }
            $none.Activity = 'a'
            $environment = New-XmipPlaygroundEnvironment @none

            $environment.XMIP_PLAYGROUND_NODES | Should -Be '0'
            $environment.Keys | Should -Not -Contain 'XMIP_PLAYGROUND_NODE_NAMES'
            $environment.Keys | Should -Not -Contain 'XMIP_PLAYGROUND_NODE_CAPABILITIES'

            { Assert-XmipNodeName -Nodes 'R1', 'r1' } |
                Should -Throw -ExpectedMessage '*named once*'
            { Assert-XmipNodeName -Nodes 'R1' -OnlineNodes 'P1' } |
                Should -Throw -ExpectedMessage '*-Nodes does not*'
            { Assert-XmipNodeName -Nodes '1st' } |
                Should -Throw -ExpectedMessage '*starting with a letter*'
            { Assert-XmipNodeName -Nodes 'R1' } | Should -Not -Throw
            { Assert-XmipNodeName -Nodes 'R1', 'P1-2' -OnlineNodes 'P1-2' } |
                Should -Not -Throw

            # A node's name is the last word of its process name and so a
            # file name (ADR-0053, amendment 2026-09-20) — and nothing more.
            # The owner, 2026-09-20: "A node is a node and can have one or
            # more roles, roll is something different." The marker in
            # xmip-playground-<cluster>-node-<name> carries the kind, so no
            # word is reserved and no name is refused for the shape's sake.
            foreach ($free in 'roll', 'Cluster', 'edge-roll', 'west-cluster', 'node') {
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
        { Start-XmipTest -Suite Core.Playground -Nodes R1 -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*you name it*'
        (Get-Command -Name Start-XmipTest).Parameters['Cluster'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.PSDefaultValueAttribute] } |
            Should -BeNullOrEmpty
    }

    It 'reads no letter of a node''s name, at the door or anywhere else' {
        # The owner, 2026-09-20: "Rn, Pn and Sn are arbitrary node names."
        # Start-XmipTest kept the last shorthand in the estate for a day and
        # it is struck (ADR-0056, amendment). A node carries what
        # -NodeCapability states for it and nothing otherwise. Pure.
        InModuleScope Xmip {
            foreach ($name in 'R1', 'p2', 'Send3', 'node-01', 'R-1') {
                Get-XmipNodeCapability -Name $name | Should -Be ''
            }

            $stated = @{ alpha = 'receive'; R1 = 'process,send'; beta = @() }
            Get-XmipNodeCapability -Name 'alpha' -NodeCapability $stated | Should -Be 'receive'
            Get-XmipNodeCapability -Name 'R1' -NodeCapability $stated | Should -Be 'process,send'
            Get-XmipNodeCapability -Name 'beta' -NodeCapability $stated | Should -Be ''

            Get-XmipNodeCapabilityText -Nodes 'R1', 'P1', 'S1', 'node-01' | Should -Be ''
            Get-XmipNodeCapabilityText -Nodes 'alpha', 'beta' -NodeCapability $stated |
                Should -Be 'alpha=receive'
            Get-XmipNodeCapabilityText -Nodes 'R1', 'P1' -NodeCapability @{
                R1 = 'receive'; P1 = 'process+send'
            } | Should -Be 'R1=receive,P1=process+send'

            { ConvertTo-XmipNodeCapability -Capability 'relay' } |
                Should -Throw -ExpectedMessage 'REFUSED: no capability is called relay*'
            { Assert-XmipNodeCapability -Nodes 'alpha' -NodeCapability @{ gamma = 'send' } } |
                Should -Throw -ExpectedMessage '*-Nodes does not*'
        }
    }

    It 'says what nodes with no capability will do, and does not refuse it' {
        # ADR-0055 clause 5: running whole tests is a real answer, and it is
        # not what someone typing R1, P1, S1 is likely to have meant. Said
        # before anything spawns, naming both ways to split the path.
        InModuleScope Xmip {
            [string] $said = Get-XmipNodeCapabilityWarning -Nodes 'R1', 'P1', 'S1'

            $said | Should -BeLike '*None of R1, P1, S1 declares a stage*'
            $said | Should -BeLike '*-NodeCapability*'
            $said | Should -BeLike '*omit -Nodes*'

            # Nothing to say: a stage declared, a run without RoundTrip, or
            # no nodes named at all.
            Get-XmipNodeCapabilityWarning -Nodes 'alpha' -NodeCapability @{ alpha = 'receive' } |
                Should -Be ''
            Get-XmipNodeCapabilityWarning -Nodes 'R1', 'P1' -Test 'HeavyLoad' | Should -Be ''
            Get-XmipNodeCapabilityWarning | Should -Be ''
        }

        Start-XmipTest -Cluster Z9 -Nodes R1, P1, S1 -WhatIf -WarningVariable said |
            Out-Null
        "$said" | Should -BeLike '*declares a stage*'
    }

    It 'refuses RoundTrip whose nodes leave a capability undeclared, before anything starts' {
        # The path is receive to process to send between the node processes,
        # and the refusal names the capability nobody declared, never a letter.
        InModuleScope Xmip {
            $whole = @{ R1 = 'receive'; P1 = 'process'; S1 = 'send' }
            $half = @{ R1 = 'receive'; R2 = 'receive'; S1 = 'send' }

            $six = @{
                Nodes          = @('R1', 'R2', 'P1', 'P2', 'S1', 'S2')
                Test           = 'RoundTrip'
                NodeCapability = $whole + @{ R2 = 'receive'; P2 = 'process'; S2 = 'send' }
            }
            Get-XmipNodeCapabilityRefusal @six | Should -Be ''

            # The signpost an operator meets most often now that a name says
            # nothing: it names the capability nobody declared and both ways
            # to declare one.
            $short = @{ Nodes = @('R1', 'R2', 'S1'); Test = 'RoundTrip'; NodeCapability = $half }
            [string] $said = Get-XmipNodeCapabilityRefusal @short

            $said | Should -BeLike 'REFUSED. RoundTrip across nodes*no node declares process.*'
            $said | Should -BeLike '*-NodeCapability*'
            $said | Should -BeLike '*omit -Nodes*'

            $one = @{ Nodes = @('R1'); NodeCapability = @{ R1 = 'receive' } }
            Get-XmipNodeCapabilityRefusal @one | Should -BeLike '*declares process or send.*'
            Get-XmipNodeCapabilityRefusal @one -Test 'roundtrip', 'Filing' |
                Should -BeLike 'REFUSED.*'

            # Named for nothing, but declaring the whole path: no refusal.
            $stated = @{ alpha = 'receive'; beta = 'process'; gamma = 'send' }
            $named = @{ Nodes = @('alpha', 'beta', 'gamma'); NodeCapability = $stated }
            Get-XmipNodeCapabilityRefusal @named | Should -Be ''

            # Not RoundTrip, nothing declared, or no nodes: nothing to refuse.
            # R1 alone declares nothing at all now, so it is the third case.
            Get-XmipNodeCapabilityRefusal -Nodes 'R1' -Test 'HeavyLoad' | Should -Be ''
            Get-XmipNodeCapabilityRefusal -Nodes 'R1' | Should -Be ''
            Get-XmipNodeCapabilityRefusal -Nodes 'node-01', 'node-02' | Should -Be ''
            Get-XmipNodeCapabilityRefusal -Nodes @() | Should -Be ''
            Get-XmipNodeCapabilityRefusal | Should -Be ''

            $chosen = @{ Stress = 'Calm'; Nodes = @('R1', 'S1'); Snapshot = 's'; History = 'h' }
            $chosen.Activity = 'a'
            $chosen.NodeCapability = @{ R1 = 'receive'; S1 = 'send' }
            { New-XmipPlaygroundEnvironment @chosen } |
                Should -Throw -ExpectedMessage '*no node declares process.*'
        }

        [hashtable] $door = @{
            Test           = 'RoundTrip'
            Cluster        = 'Z8'
            Nodes          = @('R1', 'S1')
            NodeCapability = @{ R1 = 'receive'; S1 = 'send' }
            ErrorAction    = 'Stop'
        }

        { Start-XmipTest @door } |
            Should -Throw -ExpectedMessage 'REFUSED. RoundTrip across nodes*declares process.*'
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

    It 'brings the level''s full complement when -Nodes is omitted, covering the path' {
        # The complement is the roll's to compose — the count is scaled to the
        # machine's headroom and only the rig measures it — so the door asks
        # for it and hands it back by name. What arrives is parsed here, and a
        # roster the door composed itself must never refuse itself.
        InModuleScope Xmip {
            $dealt = ConvertFrom-XmipRosterText -Text (
                'node-01=receive,node-02=process,node-03=send,node-04=receive')

            $dealt.Nodes | Should -Be @('node-01', 'node-02', 'node-03', 'node-04')
            $dealt.NodeCapability['node-04'] | Should -Be 'receive'
            $dealt.Covers | Should -BeTrue

            [hashtable] $asked = @{
                Nodes          = $dealt.Nodes
                Test           = 'RoundTrip'
                NodeCapability = $dealt.NodeCapability
            }
            Get-XmipNodeCapabilityRefusal @asked | Should -Be ''

            # Too few nodes for three stages: they declare nothing, the roll
            # runs RoundTrip whole, and nothing refuses itself.
            $small = ConvertFrom-XmipRosterText -Text 'node-01,node-02'

            $small.Covers | Should -BeFalse
            $small.NodeCapability['node-01'] | Should -Be ''
            $asked.Nodes = $small.Nodes
            $asked.NodeCapability = $small.NodeCapability

            Get-XmipNodeCapabilityRefusal @asked | Should -Be ''

            { ConvertFrom-XmipRosterText -Text 'node-01=relay' } |
                Should -Throw -ExpectedMessage 'REFUSED: no capability is called relay*'
        }

        # The record says the nodes that were resolved, never an empty list:
        # an operator who typed neither switch can read what they got.
        [string] $door = Get-XmipStartSource

        $door | Should -Match '(?m)^\s*nodes\s+= @\(\$Nodes\)\s*$'
        $door | Should -Match "node_names.+else \{ 'complement' \}"
    }

    It 'refuses an online node that was not named a node' {
        { Start-XmipTest -Nodes R1 -OnlineNodes P1 -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*-Nodes does not*'
        { Start-XmipTest -OnlineNodes R1 -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*name them all*'
        { Start-XmipTestNode -Nodes R1 -OnlineNodes P1 -ErrorAction Stop } |
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
        InModuleScope Xmip {
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
                [hashtable] $whole = @{ Cluster = 'Z9'; Test = @() }
                Start-XmipProviderSuite -Suite $theirs -Bound $whole |
                    Should -Be 'example:Z9:'

                [hashtable] $named = @{ Cluster = 'Z9'; Test = @('Smoke') }
                Start-XmipProviderSuite -Suite $theirs -Bound $named |
                    Should -Be 'example:Z9:Smoke'
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
            $whole = @{ Stress = 'Calm'; Snapshot = 's'; History = 'h'; Activity = 'a' }
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
            $whole = @{ Stress = 'Calm'; Snapshot = 's'; History = 'h'; Activity = 'a' }
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
            'Get-XmipTestResult' = @('Test', 'Node')
            'Get-XmipTestStatus' = @('Cluster')
            'Stop-XmipTest'      = @('Cluster', 'Test')
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
    It 'is read back from its command line, quoted paths whole' {
        InModuleScope Xmip {
            [string] $line = '"D:\a b\xmip-playground-node.exe" --name node-03 ' +
                '--shared "D:\a b\shared" ' +
                '--stress harsh --rounds 0 --snapshot "D:\a b\node-03.toml" ' +
                '--interval-ms 500 --can process,send --online true'
            $flags = Read-XmipTestNodeCommandLine -CommandLine $line

            $flags.Name | Should -Be 'node-03'
            $flags.Shared | Should -Be 'D:\a b\shared'
            $flags.Stress | Should -Be 'harsh'
            $flags.Rounds | Should -Be 0
            $flags.Snapshot | Should -Be 'D:\a b\node-03.toml'
            $flags.Interval | Should -Be ([timespan]::FromMilliseconds(500))
            $flags.Capability | Should -Be 'process,send'
            $flags.Online | Should -BeTrue
        }
    }

    It 'defaults the way the node binary does when a flag is absent' {
        InModuleScope Xmip {
            [string] $line = 'xmip-playground-node.exe --name n --rounds 3'
            $flags = Read-XmipTestNodeCommandLine -CommandLine $line

            $flags.Interval | Should -Be ([timespan]::FromMilliseconds(250))
            $flags.Online | Should -BeFalse
            $flags.Rounds | Should -Be 3
            $flags.Capability | Should -Be ''
        }
    }

    It 'reads the capability a node declared, and an empty one is no stage' {
        # ADR-0056: a node declares what it can do and nothing is read out of
        # its name. The cluster passes --can to every node it spawns, empty
        # for one that declared no stage and runs whole tests itself.
        InModuleScope Xmip {
            $one = Read-XmipTestNodeCommandLine -CommandLine (
                'xmip-playground-node.exe --name R1 --can receive --online true')
            $one.Capability | Should -Be 'receive'
            $one.Online | Should -BeTrue

            $none = Read-XmipTestNodeCommandLine -CommandLine (
                'xmip-playground-node.exe --name n1 --can "" --online false')
            $none.Capability | Should -Be ''
            $none.Online | Should -BeFalse
        }
    }
}

Describe 'What a run says' {
    BeforeAll {
        $script:Snapshot = Join-Path $TestDrive 'playground-snapshot.toml'
        @'
source = "playground"
node = "xmip:///playground"

[[records]]
scope = "xmip:///playground/round-trip/tcp/json"
state = "fine"
severity = 0
evidence = "12 rounds, all whole"
observed_unix_nanos = 1789208338038783900

[[records]]
scope = "xmip:///playground/node/node-02/exclusive-claim/file/parallel"
state = "done"
severity = 90
evidence = "claimed twice"
observed_unix_nanos = 1789208338038783900

[[records]]
scope = "xmip:///playground/node/R1/receive/tcp/json"
state = "fine"
severity = 0
evidence = "12/12 rounds passed"
observed_unix_nanos = 1789208338038783900

[[records]]
scope = "xmip:///playground/node"
state = "stressed"
severity = 40
evidence = "node-02 restarted once"
observed_unix_nanos = 1789208338038783900
'@ | Set-Content -LiteralPath $script:Snapshot -Encoding utf8
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
        $claim.Node | Should -Be 'node-02'
        $claim.Transport | Should -Be 'file'
        $claim.Contract | Should -Be 'parallel'

        # A role node's stage is RoundTrip's, published under the node.
        $received = $results | Where-Object Node -eq 'R1'
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
        @(Get-XmipTestResult -Path $script:Snapshot -Node 'node-*').Count | Should -Be 1
        @(Get-XmipTestResult -Path $script:Snapshot -Node 'R*').Count | Should -Be 1
        (Get-XmipTestResult -Path $script:Snapshot -Worst).State | Should -Be 'done'
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
        Copy-Item -Path $script:Snapshot -Destination (Join-Path $two 'C1-snapshot.toml')
        Copy-Item -Path $script:Snapshot -Destination (Join-Path $two 'C2-snapshot.toml')
        { Get-XmipTestResult -Path $two -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*C1-snapshot.toml, C2-snapshot.toml*'
    }

    It 'says where a snapshot should be when there is none' {
        { Get-XmipTestResult -Path (Join-Path $TestDrive 'nowhere') -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*No snapshot*'
    }
}

Describe 'A cluster rolls once' {
    It 'finds the roll already running as a cluster, and none for another name' {
        InModuleScope Xmip -Parameters @{ Area = $TestDrive } {
            param($Area)

            # 2026-09-18: three rolls as CC1 overwrote one another's snapshot.
            # One record spells the suite as this morning wrote it and one
            # as the estate writes it now: a run is found by its cluster,
            # and an older record still reads (ADR-0059, 2026-09-20).
            Set-Content -LiteralPath (Join-Path $Area 'roll-4242.toml') -Encoding utf8 -Value @(
                'suite = "Playground"'
                'cluster = "CC1"'
                'pid = 4242'
            )
            Set-Content -LiteralPath (Join-Path $Area 'roll-4343.toml') -Encoding utf8 -Value @(
                'suite = "Core.Playground"'
                'cluster = "CC10"'
                'pid = 4343'
            )

            @(Get-XmipPlaygroundRolling -Path $Area -Cluster 'CC1') | Should -Be @(4242)
            @(Get-XmipPlaygroundRolling -Path $Area -Cluster 'CC10') | Should -Be @(4343)
            @(Get-XmipPlaygroundRolling -Path $Area -Cluster 'C1').Count | Should -Be 0
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
        InModuleScope Xmip {
            Mock -CommandName Start-Process -MockWith { [PSCustomObject]@{ Id = 1 } }
            Mock -CommandName Test-XmipOperationWebAnswering -MockWith { $false }
            Mock -CommandName Get-XmipTestStatus -MockWith {
                [PSCustomObject]@{ Suite = 'Core.Playground'; Cluster = 'C1' }
            }

            Start-XmipOperationWeb -WarningVariable said -WarningAction SilentlyContinue
            "$said" | Should -BeLike '*will not show the roll C1*Get-XmipTestStatus |*'

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
        InModuleScope Xmip {
            [string] $coming = Join-Path ([System.IO.Path]::GetTempPath()) 'xmip-Q1-snapshot.toml'
            $rolling = [PSCustomObject]@{ Cluster = 'Q1'; Snapshot = $coming }

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
        InModuleScope Xmip {
            [string] $never = Join-Path ([System.IO.Path]::GetTempPath()) 'xmip-Q2-snapshot.toml'
            $rolling = [PSCustomObject]@{ Cluster = 'Q2'; Snapshot = $never }
            $script:asked = 0

            Mock -CommandName Start-Sleep -MockWith { }
            Mock -CommandName Get-XmipTestStatus -MockWith {
                $script:asked++
                if ($script:asked -eq 1) { $rolling } else { @() }
            }

            { Wait-XmipSnapshot -Path $never } |
                Should -Throw -ExpectedMessage '*REFUSED*Q2 stopped without publishing*'
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

Describe 'What a history file holds' {
    <#
        ADR-0029: a history point is a counted measurement over time. Every
        history the Playground published between 2026-09-05 and 2026-09-19
        held none, and no surface said so.
    #>
    It 'is read back point by point, oldest first' {
        InModuleScope Xmip -Parameters @{ Area = $TestDrive } {
            param($Area)

            [string] $path = Join-Path $Area 'Y1-history.toml'
            Set-Content -LiteralPath $path -Encoding utf8 -Value @(
                'node = "xmip:///Y1"'
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
            $read[0].Node | Should -Be 'xmip:///Y1'
            $read[0].Counted | Should -Be 'bytes'
            $read[0].Value | Should -Be 1024
            @(Get-XmipHistory -Path $path -Counted messages).Value | Should -Be 7
        }
    }

    It 'says in words that a producer wrote no points, rather than nothing' {
        InModuleScope Xmip -Parameters @{ Area = $TestDrive } {
            param($Area)

            [string] $path = Join-Path $Area 'Y2-history.toml'
            Set-Content -LiteralPath $path -Encoding utf8 -Value @(
                'node = "xmip:///Y2"'
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
            New-FakeRoll -Id 11 -Cluster C1 -Tests RoundTrip
            New-FakeRoll -Id 12 -Cluster C2 -Tests RoundTrip, Retention
            New-FakeRoll -Id 13 -Cluster C3
        )

        InModuleScope Xmip -Parameters @{ Running = $running } {
            param($Running)

            @(Select-XmipTestRoll -Running $Running -Cluster C1 -Test RoundTrip).Id |
                Should -Be 11
            @(Select-XmipTestRoll -Running $Running -Cluster C2 -Test RoundTrip, Retention).Id |
                Should -Be 12
            @(Select-XmipTestRoll -Running $Running -Cluster C3 -Test '*').Id |
                Should -Be 13 -Because 'a run of the whole suite is every test in it'
            @(Select-XmipTestRoll -Running $Running).Count |
                Should -Be 3 -Because 'nothing named is every run'
        }
    }

    It 'refuses a run that also drives a test not named, and picks nothing' {
        [object[]] $running = @(
            New-FakeRoll -Id 11 -Cluster C1 -Tests RoundTrip
            New-FakeRoll -Id 12 -Cluster C2 -Tests RoundTrip, Retention
        )

        InModuleScope Xmip -Parameters @{ Running = $running } {
            param($Running)

            { Select-XmipTestRoll -Running $Running -Test RoundTrip -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*REFUSED*also runs Retention*Nothing was stopped*'

            # C1 alone would qualify and is not picked: a refused command has
            # done nothing (ADR-0055 clause 2).
            [object[]] $picked = @(
                Select-XmipTestRoll -Running $Running -Test RoundTrip -ErrorAction SilentlyContinue
            )
            $picked.Count | Should -Be 0
        }
    }

    It 'refuses a cluster or a test that nothing running matches, naming what is' {
        [object[]] $running = @(New-FakeRoll -Id 11 -Cluster C1 -Tests RoundTrip)

        InModuleScope Xmip -Parameters @{ Running = $running } {
            param($Running)

            [string] $nothing = '*REFUSED. No roll matches Z9. Rolling now: C1 running RoundTrip.*'
            { Select-XmipTestRoll -Running $Running -Cluster Z9 -ErrorAction Stop } |
                Should -Throw -ExpectedMessage $nothing

            [string] $none = '*REFUSED. No roll on C1 runs a test matching Storm.*'
            { Select-XmipTestRoll -Running $Running -Cluster C1 -Test Storm -ErrorAction Stop } |
                Should -Throw -ExpectedMessage $none
            { Select-XmipTestRoll -Running @() -Test RoundTrip -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*Nothing is rolling.*'
        }
    }
}
