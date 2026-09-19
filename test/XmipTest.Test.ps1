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
        # a test run crosses none. The Pester door is -Suite Estate.
        foreach ($name in 'Start-XmipTest', 'Get-XmipTestStatus', 'Stop-XmipTest') {
            Get-Command -Module Xmip -Name $name | Should -Not -BeNullOrEmpty
        }

        [string[]] $verbs = @(Get-Command -Module Xmip -Noun XmipTest | ForEach-Object { $_.Verb })

        @($verbs | Sort-Object) | Should -Be @('Start', 'Stop')
        Get-Command -Module Xmip -Name 'Invoke-XmipTest*' | Should -BeNullOrEmpty
    }

    It 'reads "Start-XmipTest Playground HeavyLoad" as suite then test, nothing else by position' {
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

    It 'offers the Playground and the estate suite, Playground first' {
        [string[]] $suites = @(
            (Get-Command -Name Start-XmipTest).Parameters['Suite'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } |
                ForEach-Object { $_.ValidValues }
        )

        $suites | Should -Be @('Playground', 'Estate')
    }

    It 'runs the estate suite in its own runspace, never in the module it tests' {
        # 2026-09-12: these files begin by removing Xmip and importing it
        # afresh. Run from inside the module, the suite tore down the module
        # that was running it, and every later call from the console found a
        # hollow module. A thread job keeps the runspace apart.
        [string] $door = Get-Content -Raw (Join-Path $script:Root 'Xmip/Start-XmipTest.ps1')

        $door | Should -Match 'Start-ThreadJob' -Because 'the suite removes the module it runs in'
        $door | Should -Not -Match '(?m)^\s*\$result = Invoke-Pester'
    }

    It 'refuses Playground switches on the estate suite' {
        { Start-XmipTest -Suite Estate -Stress Harsh -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*belong to the Playground suite*'
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

    It 'says the tests, the fleet, the online nodes and the limits the way the roll parses them' {
        InModuleScope Xmip {
            $chosen = @{
                Stress      = 'Brutal'
                Test        = @('roundtrip', 'HeavyLoad')
                Nodes       = @('R1', 'P1', 'S1')
                OnlineNodes = @('R1', 'S1')
                Cluster     = 'SN2'
                Duration    = [timespan]::FromMinutes(15)
                TimeFactor  = 9.5e-6
                LoadBytes   = '512mb'
                Snapshot    = 's'
                History     = 'h'
                Activity    = 'a'
            }
            $environment = New-XmipPlaygroundEnvironment @chosen

            $environment.XMIP_PLAYGROUND_SCENARIOS | Should -Be 'pingpong,load'
            $environment.XMIP_PLAYGROUND_NODE_NAMES | Should -Be 'R1,P1,S1'
            $environment.XMIP_PLAYGROUND_ONLINE_NODES | Should -Be 'R1,S1'
            $environment.XMIP_PLAYGROUND_CLUSTER | Should -Be 'SN2'
            $environment.Keys | Should -Not -Contain 'XMIP_PLAYGROUND_NODES'
            $environment.XMIP_PLAYGROUND_MAX_SECONDS | Should -Be '900'
            $environment.XMIP_PLAYGROUND_TIME_FACTOR | Should -Be '9.5E-06'
            $environment.XMIP_PLAYGROUND_LOAD_BYTES | Should -Be '512mb'
        }
    }

    It 'names nodes, one process each, and an empty list is no fleet' {
        InModuleScope Xmip {
            $none = @{ Stress = 'Harsh'; Nodes = @(); Snapshot = 's'; History = 'h' }
            $none.Activity = 'a'
            $environment = New-XmipPlaygroundEnvironment @none

            $environment.XMIP_PLAYGROUND_NODES | Should -Be '0'
            $environment.Keys | Should -Not -Contain 'XMIP_PLAYGROUND_NODE_NAMES'

            { Assert-XmipNodeName -Nodes 'R1', 'r1' } |
                Should -Throw -ExpectedMessage '*named once*'
            { Assert-XmipNodeName -Nodes 'R1' -OnlineNodes 'P1' } |
                Should -Throw -ExpectedMessage '*-Nodes does not*'
            { Assert-XmipNodeName -Nodes '1st' } |
                Should -Throw -ExpectedMessage '*starting with a letter*'
            { Assert-XmipNodeName -Nodes 'R1' } | Should -Not -Throw
            { Assert-XmipNodeName -Nodes 'R1', 'P1-2' -OnlineNodes 'P1-2' } |
                Should -Not -Throw
        }
    }

    It 'names a test for every scenario the roll drives, and nothing the roll does not' {
        # The owner's names — HeavyLoad, LowLatency — over the roll's scenario
        # names. SCENARIOS in roll.rs is the roll's list; the map must cover it
        # exactly, or a test is unreachable or names nothing.
        [string] $roll = Get-Content -Raw (Join-Path $script:Root 'test/playground/src/bin/roll.rs')
        [string] $pattern = '(?s)const SCENARIOS: \[&str; \d+\] = \[(.*?)\];'
        [string] $list = [regex]::Match($roll, $pattern).Groups[1].Value
        [string[]] $scenarios = @(
            [regex]::Matches($list, '"([a-z]+)"') | ForEach-Object { $_.Groups[1].Value }
        )

        InModuleScope Xmip -Parameters @{ Scenarios = $scenarios } {
            [string[]] $mapped = @($script:XmipPlaygroundTest.Values | Sort-Object)

            $mapped | Should -Be @($Scenarios | Sort-Object)
            ConvertTo-XmipPlaygroundScenario -Test 'HeavyLoad', 'LowLatency' |
                Should -Be @('load', 'furious')
            ConvertTo-XmipTestName -Scenario 'furious' | Should -Be 'LowLatency'
            ConvertTo-XmipTestName -Scenario 'fleet' | Should -Be 'fleet'
            { ConvertTo-XmipPlaygroundScenario -Test 'Typo' } |
                Should -Throw -ExpectedMessage '*No Playground test*'
        }
    }

    It 'refuses a roll without a cluster name, since the owner names the cluster' {
        # 2026-09-14: a test may spawn nodes, never a cluster. No default name.
        { Start-XmipTest -Suite Playground -Nodes R1 -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*you name it*'
        (Get-Command -Name Start-XmipTest).Parameters['Cluster'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.PSDefaultValueAttribute] } |
            Should -BeNullOrEmpty
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
        # roll.rs and switch.rs are the source of the names; a variable the
        # roll reads that no parameter can set is a switch an operator cannot
        # reach from PowerShell.
        [string] $roll = Get-Content -Raw (Join-Path $script:Root 'test/playground/src/bin/roll.rs')
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

Describe 'What a node was started with' {
    It 'is read back from its command line, quoted paths whole' {
        InModuleScope Xmip {
            [string] $line = '"D:\a b\xmip-playground-node.exe" --name node-03 ' +
                '--shared "D:\a b\shared" ' +
                '--stress harsh --rounds 0 --snapshot "D:\a b\node-03.toml" ' +
                '--interval-ms 500 --online true'
            $flags = Read-XmipTestNodeCommandLine -CommandLine $line

            $flags.Name | Should -Be 'node-03'
            $flags.Shared | Should -Be 'D:\a b\shared'
            $flags.Stress | Should -Be 'harsh'
            $flags.Rounds | Should -Be 0
            $flags.Snapshot | Should -Be 'D:\a b\node-03.toml'
            $flags.Interval | Should -Be ([timespan]::FromMilliseconds(500))
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
scope = "xmip:///playground/pingpong/tcp/json"
state = "fine"
severity = 0
evidence = "12 rounds, all whole"
observed_unix_nanos = 1789208338038783900

[[records]]
scope = "xmip:///playground/node/node-02/claim/file/parallel"
state = "done"
severity = 90
evidence = "claimed twice"
observed_unix_nanos = 1789208338038783900

[[records]]
scope = "xmip:///playground/fleet"
state = "stressed"
severity = 40
evidence = "node-02 restarted once"
observed_unix_nanos = 1789208338038783900
'@ | Set-Content -LiteralPath $script:Snapshot -Encoding utf8
    }

    It 'splits a scope into scenario, node, transport and contract' {
        [object[]] $results = @(Get-XmipTestResult -Path $script:Snapshot)

        $results.Count | Should -Be 3

        $pingpong = $results | Where-Object Scenario -eq 'pingpong'
        $pingpong.Test | Should -Be 'RoundTrip'
        $pingpong.Transport | Should -Be 'tcp'
        $pingpong.Contract | Should -Be 'json'
        $pingpong.Node | Should -Be ''

        $claim = $results | Where-Object Scenario -eq 'claim'
        $claim.Node | Should -Be 'node-02'
        $claim.Transport | Should -Be 'file'
        $claim.Contract | Should -Be 'parallel'

        ($results | Where-Object Scenario -eq 'fleet').Transport | Should -Be ''
    }

    It 'filters by test and by node, and names the worst' {
        @(Get-XmipTestResult -Path $script:Snapshot -Test RoundTrip).Count | Should -Be 1
        @(Get-XmipTestResult -Path $script:Snapshot -Node 'node-*').Count | Should -Be 1
        (Get-XmipTestResult -Path $script:Snapshot -Worst).State | Should -Be 'done'
    }

    It 'takes the directory the snapshot is in' {
        @(Get-XmipTestResult -Path $TestDrive).Count | Should -Be 3
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
            Set-Content -LiteralPath (Join-Path $Area 'roll-4242.toml') -Encoding utf8 -Value @(
                'suite = "playground"'
                'cluster = "CC1"'
                'pid = 4242'
            )
            Set-Content -LiteralPath (Join-Path $Area 'roll-4343.toml') -Encoding utf8 -Value @(
                'suite = "playground"'
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
                [PSCustomObject]@{ Suite = 'Playground'; Cluster = 'C1' }
            }

            Start-XmipOperationWeb -WarningVariable said -WarningAction SilentlyContinue
            "$said" | Should -BeLike '*will not show the roll C1*Get-XmipTestStatus |*'

            Start-XmipOperationWeb -Snapshot 'x.toml' -WarningVariable quiet
            $quiet | Should -BeNullOrEmpty -Because 'it was pointed at a snapshot'
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
