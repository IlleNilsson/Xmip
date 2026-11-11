#requires -PSEdition Core
#requires -Version 7.7.0

<#
    Core.Demo, the demo readiness check (ADR-0028, amendment 2026-11-10). The
    owner's demo is 2026-12-18, and the check proves a tree is ready for it:
    the Essentials roll, the web operations tool, the Desktop operations app
    and the VS Code extension with its language server, each said OK, FAILED
    or SKIPPED in words, and everything it started stopped. These check what
    can be checked without starting the cluster: the refusals, the start, the
    words, the stop when a part fails and what a run left when it died, that
    only what the run started is stopped, the roll timed from its spawn, the
    deployed gui.toml, the program dotnet names, the language server's
    framing, and the https probe where nothing answers, where a certificate
    reaches the anchor and where it does not. The cluster's name is the test
    cluster's (ADR-0056, amendment 2026-10-03).
#>

BeforeAll {
    $script:AuditBefore = $env:XMIP_AUDIT_DIRECTORY
    $env:XMIP_AUDIT_DIRECTORY = Join-Path -Path $TestDrive -ChildPath 'audit'

    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    $script:Cluster = (Get-XmipTestCluster).Name

    # Two of the test cluster's nodes, by place (ADR-0056, amendment
    # 2026-10-03): the roll's record names them, and the second is the one
    # left out when a node does not run.
    [string[]] $script:Pair = @((Get-XmipTestCluster).Nodes | Select-Object -First 2)

    <#
        .SYNOPSIS
        A fresh folder under this run's drive.
    #>
    function New-XmipDemoArea {
        param([string] $Name)

        [string] $area = Join-Path -Path $TestDrive -ChildPath $Name
        New-Item -ItemType Directory -Path $area -Force | Out-Null

        return $area
    }
}

AfterAll {
    $env:XMIP_AUDIT_DIRECTORY = $script:AuditBefore
}

Describe 'Core.Demo is one of Xmip''s suites, and refuses what it does not take' {
    It 'is the third of Xmip''s own, and Start-XmipTest takes its -Tester' {
        InModuleScope Xmip {
            $demo = Get-XmipTestSuite | Where-Object { $_.Name -eq 'Core.Demo' }

            $demo.Kind | Should -Be 'demo'
            $demo.Provider | Should -Be 'Core'
        }

        (Get-Command -Name Start-XmipTest).Parameters.Keys | Should -Contain 'Tester'
    }

    It 'refuses a switch it does not take, and its own on another suite, before anything' {
        InModuleScope Xmip -Parameters @{ Cluster = $script:Cluster } {
            param($Cluster)

            Mock Write-XmipAudit { }
            Mock Start-XmipDetachedShell { throw 'started' }

            [string] $rounds = '*REFUSED. -Rounds belong to Core.Essentials, not Core.Demo.*'
            [string] $tester = '*REFUSED. -Tester belong to Core.Demo, not Core.Estate.*'

            { Start-XmipTest -Suite Core.Demo -Cluster $Cluster -Rounds 3 -ErrorAction Stop } |
                Should -Throw -ExpectedMessage $rounds
            { Start-XmipTest -Suite Core.Estate -Tester someone -ErrorAction Stop } |
                Should -Throw -ExpectedMessage $tester

            [hashtable] $essentials = @{
                Suite = 'Core.Essentials'; Cluster = $Cluster; Tester = 'someone'; WhatIf = $true
            }
            { Start-XmipTest @essentials -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*-Tester belong to Core.Demo, not Core.Essentials*'
            { Start-XmipTest -Suite Core.Demo -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*REFUSED. Core.Demo*-Cluster <name>*'

            Should -Invoke Start-XmipDetachedShell -Times 0
        }
    }

    It 'starts nothing under -WhatIf' {
        InModuleScope Xmip -Parameters @{ Cluster = $script:Cluster } {
            param($Cluster)

            Mock Start-XmipDetachedShell { throw 'started' }

            Start-XmipTest -Suite Core.Demo -Cluster $Cluster -WhatIf

            Should -Invoke Start-XmipDetachedShell -Times 0
        }
    }

    It 'starts the check detached and lists it running from the record it writes' {
        [hashtable] $given = @{ Cluster = $script:Cluster; Area = (New-XmipDemoArea -Name 'start') }

        InModuleScope Xmip -Parameters $given {
            param($Cluster, $Area)

            $script:DemoArea = $Area
            Mock Write-XmipAudit { }
            Mock Write-Host { }
            Mock Get-XmipEssentialsLayout {
                [pscustomobject]@{ Demo = $script:DemoArea; Area = $script:DemoArea }
            }
            Mock Get-XmipClusterRunning { }
            Mock Start-XmipDetachedShell {
                $script:DemoScript = $Script
                Get-Process -Id $PID
            }

            [hashtable] $door = @{
                Suite   = 'Core.Demo'
                Cluster = $Cluster
                Stress  = 'Realistic'
                Tester  = "o'brien@example.org"
            }
            $run = Start-XmipTest @door

            $run.Kind | Should -Be 'demo'
            $run.State | Should -Be 'running'
            $run.Cluster | Should -Be $Cluster
            $run.Stress | Should -Be 'Realistic'
            $run.Id | Should -Be $PID
            $script:DemoScript | Should -Match 'Test-XmipDemoReady @Run'
            $script:DemoScript | Should -Match ([regex]::Escape("Tester = 'o''brien@example.org'"))
            Get-Content -Raw -LiteralPath $run.Record | Should -Match 'tester = "o''brien'
        }
    }

    It 'rolls at Realistic, the demo''s own stress, where -Stress is not given' {
        [hashtable] $given = @{ Cluster = $script:Cluster; Area = (New-XmipDemoArea -Name 'calm') }

        InModuleScope Xmip -Parameters $given {
            param($Cluster, $Area)

            $script:DemoArea = $Area
            Mock Write-XmipAudit { }
            Mock Write-Host { }
            Mock Get-XmipEssentialsLayout {
                [pscustomobject]@{ Demo = $script:DemoArea; Area = $script:DemoArea }
            }
            Mock Get-XmipClusterRunning { }
            Mock Start-XmipDetachedShell {
                $script:DemoScript = $Script
                Get-Process -Id $PID
            }

            # Never the Essentials' hardest, which an omitted -Stress is for a
            # roll asked for by itself.
            (Start-XmipTest -Suite Core.Demo -Cluster $Cluster).Stress | Should -Be 'Realistic'
            $script:DemoScript | Should -Match "Stress = 'Realistic'"
        }
    }

    It 'refuses a second run while one runs, before anything starts' {
        [hashtable] $given = @{ Cluster = $script:Cluster; Area = (New-XmipDemoArea -Name 'two') }

        InModuleScope Xmip -Parameters $given {
            param($Cluster, $Area)

            [hashtable] $began = @{
                Record  = Join-Path $Area 'demo-20261110-120000-000.toml'
                Cluster = $Cluster
                Log     = Join-Path $Area 'demo-20261110-120000-000.log'
                Id      = $PID
                Started = (Get-Process -Id $PID).StartTime
            }
            Write-XmipDemoRecord -Run (New-XmipDemoState @began)

            $script:DemoArea = $Area
            Mock Write-XmipAudit { }
            Mock Get-XmipEssentialsLayout {
                [pscustomobject]@{ Demo = $script:DemoArea; Area = $script:DemoArea }
            }
            Mock Get-XmipClusterRunning { }
            Mock Start-XmipDetachedShell { throw 'started' }

            { Start-XmipTest -Suite Core.Demo -Cluster $Cluster -ErrorAction Stop } |
                Should -Throw -ExpectedMessage "*REFUSED. The Core.Demo run $PID is still running*"
            Should -Invoke Start-XmipDetachedShell -Times 0
            Test-Path -LiteralPath $began.Record | Should -BeTrue
        }
    }

    It 'refuses a cluster that rolls or builds already, and never follows it' {
        [hashtable] $given = @{ Cluster = $script:Cluster; Area = (New-XmipDemoArea -Name 'taken') }

        InModuleScope Xmip -Parameters $given {
            param($Cluster, $Area)

            $script:DemoArea = $Area
            Mock Write-XmipAudit { }
            Mock Get-XmipEssentialsLayout {
                [pscustomobject]@{ Demo = $script:DemoArea; Area = $script:DemoArea }
            }
            Mock Get-XmipClusterRunning { 4242 }
            Mock Start-XmipDetachedShell { throw 'started' }
            $script:Asked = $Cluster
            [string] $refused = "*REFUSED. $Cluster already rolls or builds as pid 4242*"

            { Start-XmipTest -Suite Core.Demo -Cluster $Cluster -ErrorAction Stop } |
                Should -Throw -ExpectedMessage $refused
            Should -Invoke Start-XmipDetachedShell -Times 0
            Should -Invoke Get-XmipClusterRunning -Times 1 -ParameterFilter {
                $Cluster -eq $script:Asked -and $Path -eq $script:DemoArea
            }
        }
    }

    It 'stops what a run that died left running before it clears that run' {
        [hashtable] $given = @{ Cluster = $script:Cluster; Area = (New-XmipDemoArea -Name 'left') }

        InModuleScope Xmip -Parameters $given {
            param($Cluster, $Area)

            [hashtable] $began = @{
                Record  = Join-Path $Area 'demo-20261110-120000-000.toml'
                Cluster = $Cluster
                Log     = Join-Path $Area 'demo-20261110-120000-000.log'
                Id      = 2000000000
                Started = [datetime] '2026-11-10T10:00:00Z'
            }
            $dead = New-XmipDemoState @began
            $dead['launched']['roll'] = $Cluster
            $dead['launched']['web'] = 4141
            Write-XmipDemoRecord -Run $dead

            $script:DemoArea = $Area
            Mock Write-XmipAudit { }
            Mock Write-Host { }
            Mock Get-XmipEssentialsLayout {
                [pscustomobject]@{ Demo = $script:DemoArea; Area = $script:DemoArea }
            }
            Mock Get-XmipClusterRunning { }
            Mock Stop-XmipDemoStarted { New-XmipDemoPart -Name 'stop' -State 'OK' -Reason 'done' }
            Mock Start-XmipDetachedShell { Get-Process -Id $PID }

            $null = Start-XmipTest -Suite Core.Demo -Cluster $Cluster

            Should -Invoke Stop-XmipDemoStarted -Times 1 -ParameterFilter {
                $Launched['roll'] -eq $Cluster -and $Launched['web'] -eq 4141
            }
            Test-Path -LiteralPath $began.Record | Should -BeFalse
        }
    }
}

Describe 'A demo run says each part in words, and stops what it started however it ends' {
    BeforeEach {
        [string] $area = New-XmipDemoArea -Name ([guid]::NewGuid().ToString('n'))
        $script:Given = @{
            Cluster = $script:Cluster
            Area    = $area
            Record  = Join-Path $area 'demo-1.toml'
        }
    }

    It 'is FAILED naming the part that failed, and tries every other part' {
        InModuleScope Xmip -Parameters $script:Given {
            param($Cluster, $Area, $Record)

            Mock Write-XmipAudit { }
            Mock Write-Host { }
            Mock Test-XmipDemoRoll { "$Cluster rolls" }
            Mock Test-XmipDemoWeb { throw 'nothing answered https at https://127.0.0.1:5087' }
            Mock Test-XmipDemoDesktop { 'up for a minute' }
            Mock Test-XmipDemoExtension { 'answered initialize in 3 ms' }
            Mock Stop-XmipDemoStarted {
                New-XmipDemoPart -Name 'stop' -State 'OK' -Reason 'it had started nothing'
            }

            Test-XmipDemoReady -Record $Record -Cluster $Cluster -Log (Join-Path $Area 'demo-1.log')

            $run = Get-XmipDemoRun -Path $Area
            $run.State | Should -Be 'FAILED'
            $run.Tally | Should -Be '4 of 5 parts OK'

            [object[]] $parts = @(Get-XmipDemoResult -Path $Area)
            @($parts | ForEach-Object { $_.Name }) |
                Should -Be @('roll', 'web', 'desktop', 'extension', 'stop')
            $parts[1].State | Should -Be 'FAILED'
            $parts[1].Evidence |
                Should -Be 'FAILED web: nothing answered https at https://127.0.0.1:5087'
            $parts[2].State | Should -Be 'OK'
            Should -Invoke Stop-XmipDemoStarted -Times 1
        }
    }

    It 'is OK only when every part is' {
        InModuleScope Xmip -Parameters $script:Given {
            param($Cluster, $Area, $Record)

            Mock Write-XmipAudit { }
            Mock Write-Host { }
            Mock Test-XmipDemoRoll { 'rolls' }
            Mock Test-XmipDemoWeb { 'answers' }
            Mock Test-XmipDemoDesktop { 'up' }
            Mock Test-XmipDemoExtension { 'answers' }
            Mock Stop-XmipDemoStarted { New-XmipDemoPart -Name 'stop' -State 'OK' -Reason 'done' }

            Test-XmipDemoReady -Record $Record -Cluster $Cluster -Log (Join-Path $Area 'demo-1.log')

            (Get-XmipDemoRun -Path $Area).State | Should -Be 'OK'
            Should -Invoke Write-Host -ParameterFilter {
                "$Object" -like 'OK. Core.Demo over*5 of 5*'
            }
        }
    }

    It 'skips what reads the roll where the roll did not come up, and stops the roll it started' {
        InModuleScope Xmip -Parameters $script:Given {
            param($Cluster, $Area, $Record)

            Mock Write-XmipAudit { }
            Mock Write-Host { }
            Mock Test-XmipDemoRoll {
                $Run['launched']['roll'] = $Run['cluster']
                throw "the build of $($Run['cluster']) FAILED: error[E0425]"
            }
            Mock Test-XmipDemoWeb { 'answers' }
            Mock Test-XmipDemoDesktop { 'up' }
            Mock Test-XmipDemoExtension { 'answers' }
            Mock Stop-XmipDemoStarted { New-XmipDemoPart -Name 'stop' -State 'OK' -Reason 'done' }

            Test-XmipDemoReady -Record $Record -Cluster $Cluster -Log (Join-Path $Area 'demo-1.log')

            [object[]] $parts = @(Get-XmipDemoResult -Path $Area)
            $parts[0].Message | Should -Match 'FAILED: error\[E0425\]'
            @($parts[1].State, $parts[2].State) | Should -Be @('SKIPPED', 'SKIPPED')

            # The roll's own reason, never a guess at it: this roll built
            # nothing, and published nothing because of that.
            $parts[1].Message | Should -Be (
                "Not tried: the roll part did not pass (the build of $Cluster FAILED: " +
                'error[E0425]).')
            Should -Invoke Test-XmipDemoWeb -Times 0
            Should -Invoke Test-XmipDemoDesktop -Times 0
            Should -Invoke Test-XmipDemoExtension -Times 1
            Should -Invoke Stop-XmipDemoStarted -Times 1 -ParameterFilter {
                $Launched['roll'] -eq $Cluster
            }
            (Get-XmipDemoRun -Path $Area).State | Should -Be 'FAILED'
        }
    }

    It 'stops what it started and writes FAILED when the run itself breaks' {
        InModuleScope Xmip -Parameters $script:Given {
            param($Cluster, $Area, $Record)

            Mock Write-XmipAudit { }
            Mock Write-Host { }
            # The roll part launches a web host; the run breaks at the web
            # part, outside any part's own check.
            Mock Test-XmipDemoPart {
                if ($Name -eq 'web') {
                    throw 'the run broke'
                }

                $Run['launched']['web'] = 4242
                New-XmipDemoPart -Name $Name -State 'OK' -Reason 'rolls'
            }
            Mock Stop-XmipDemoStarted { New-XmipDemoPart -Name 'stop' -State 'OK' -Reason 'done' }
            [string] $log = Join-Path $Area 'x.log'

            { Test-XmipDemoReady -Record $Record -Cluster $Cluster -Log $log } |
                Should -Throw -ExpectedMessage 'the run broke'

            Should -Invoke Stop-XmipDemoStarted -Times 1 -ParameterFilter {
                $Launched['web'] -eq 4242
            }
            (Get-XmipDemoRun -Path $Area).State | Should -Be 'FAILED'
            @(Get-XmipDemoResult -Path $Area | ForEach-Object { $_.Message }) |
                Should -Contain 'the run broke off: the run broke'
        }
    }

    It 'says a run that ended without a verdict FAILED, never running and never OK' {
        [string] $area = New-XmipDemoArea -Name 'died'
        Set-Content -LiteralPath (Join-Path $area 'demo-20261110-120000-000.toml') -Value @(
            'suite = "Core.Demo"'
            'pid = 2000000000'
            'started = "2026-11-10T10:00:00.0000000Z"'
            "cluster = `"$script:Cluster`""
            'doing = "desktop"'
            'state = ""'
        )

        InModuleScope Xmip -Parameters @{ Area = $area } {
            param($Area)

            $run = Get-XmipDemoRun -Path $Area
            $run.State | Should -Be 'FAILED'
            $run.Fault | Should -BeLike '*without a verdict*'
            (Get-XmipDemoResult -Path $Area).Evidence |
                Should -BeLike 'FAILED run: *without a verdict*'
        }
    }
}

Describe 'The roll part rolls its own cluster from this tree, timed from its spawn' {
    It 'starts the roll at the stress asked, names its pids, and times it from the spawn' {
        [hashtable] $given = @{
            Cluster = $script:Cluster
            Area    = (New-XmipDemoArea -Name 'roll')
            Pair    = $script:Pair
        }

        InModuleScope Xmip -Parameters $given {
            param($Cluster, $Area, $Pair)

            [string] $recorded = Join-Path $Area 'roll-31.toml'
            Set-Content -LiteralPath $recorded -Value "nodes = [`"$($Pair[0])`", `"$($Pair[1])`"]"
            [string] $snapshot = Join-Path $Area "$Cluster-snapshot.xmip"
            Set-Content -LiteralPath $snapshot -Value ''

            # Spawned a minute and a half before the check first saw it.
            [hashtable] $row = @{
                Suite    = 'Core.Essentials'
                Kind     = 'roll'
                State    = 'running'
                Id       = 31
                Property = @{
                    Cluster   = $Cluster
                    Stress    = 'realistic'
                    StartTime = (Get-Date).AddSeconds(-90)
                    Nodes     = $Pair
                    Snapshot  = $snapshot
                    Record    = $recorded
                }
            }
            $script:Rolling = New-XmipTestStatus @row
            Mock Start-XmipTest { [pscustomobject]@{ Id = 21; Kind = 'build' } }
            Mock Get-XmipTestStatus { $script:Rolling }
            Mock Wait-XmipSnapshot { }
            Mock Write-XmipDemoRecord { }

            [hashtable] $began = @{
                Record  = Join-Path $Area 'demo-1.toml'
                Cluster = $Cluster
                Log     = Join-Path $Area 'demo-1.log'
                Id      = 1
                Started = Get-Date
            }
            $run = New-XmipDemoState @began
            [string] $said = Test-XmipDemoRoll -Run $run

            Should -Invoke Start-XmipTest -Times 1 -ParameterFilter {
                $Suite -eq 'Core.Essentials' -and $Stress -eq 'Realistic'
            }
            Should -Invoke Wait-XmipSnapshot -Times 1 -ParameterFilter {
                $Since -eq $script:Rolling.StartTime
            }
            @($run['launched']['roll_ids']) | Should -Be @(21, 31)
            $said -match '(\d+)(\.\d)? s after the roll was spawned' | Should -BeTrue
            [int] $Matches[1] | Should -BeGreaterOrEqual 89
            $said | Should -BeLike "*its nodes ($($Pair -join ', ')) run*"
        }
    }

    It 'says which declared nodes do not run once the roll published' {
        [hashtable] $given = @{
            Cluster = $script:Cluster
            Area    = (New-XmipDemoArea -Name 'nodes')
            Pair    = $script:Pair
        }

        InModuleScope Xmip -Parameters $given {
            param($Cluster, $Area, $Pair)

            [string] $recorded = Join-Path $Area 'roll-31.toml'
            Set-Content -LiteralPath $recorded -Value "nodes = [`"$($Pair[0])`", `"$($Pair[1])`"]"
            [hashtable] $row = @{
                Suite    = 'Core.Essentials'
                Kind     = 'roll'
                State    = 'running'
                Id       = 31
                Property = @{
                    Cluster   = $Cluster
                    StartTime = Get-Date
                    Nodes     = @($Pair[0])
                    Snapshot  = Join-Path $Area "$Cluster-snapshot.xmip"
                    Record    = $recorded
                }
            }
            $script:Rolling = New-XmipTestStatus @row
            Mock Get-XmipTestStatus { $script:Rolling }
            Mock Wait-XmipSnapshot { }

            { Wait-XmipDemoRoll -Roll $script:Rolling } |
                Should -Throw -ExpectedMessage "*its nodes $($Pair[1]) are not running*"
        }
    }
}

Describe 'Stop-XmipDemoStarted ends what a run launched, and only that' {
    BeforeEach {
        [string] $area = New-XmipDemoArea -Name ([guid]::NewGuid().ToString('n'))
        [string] $source = Join-Path $area 'source.toml'
        [string] $deployed = Join-Path $area 'deployed.toml'
        Set-Content -LiteralPath $source -Value "[Xmip]`nSurface = `"local`""
        Set-Content -LiteralPath $deployed -Value "[Xmip]`nSurface = `"snapshot`""

        # The desktop app is this pwsh, named as the run names what it
        # started: its pid, when it started and its program.
        $self = Get-Process -Id $PID
        $script:Launched = [ordered]@{
            roll            = $script:Cluster
            roll_ids        = @(31)
            web             = 41
            desktop         = $PID
            desktop_started = $self.StartTime.ToUniversalTime().ToString('o')
            desktop_program = $self.Path
            document        = $deployed
            source          = $source
        }
    }

    It 'stops the roll, the web host and the desktop app, and gives the document back' {
        InModuleScope Xmip -Parameters @{ Launched = $script:Launched } {
            param($Launched)

            Mock Get-XmipClusterRunning { 31 }
            Mock Stop-XmipTest { }
            Mock Get-XmipOperationWeb { [pscustomobject]@{ Id = 41 } }
            Mock Stop-XmipOperationWeb { }
            Mock Stop-XmipProcess { }

            $part = Stop-XmipDemoStarted -Launched $Launched

            $part.Name | Should -Be 'stop'
            $part.State | Should -Be 'OK'
            Should -Invoke Stop-XmipTest -Times 1 -ParameterFilter { $Id -contains 31 }
            Should -Invoke Stop-XmipOperationWeb -Times 1 -ParameterFilter { $Id -contains 41 }
            Should -Invoke Stop-XmipProcess -Times 1 -ParameterFilter { $Id -contains $PID }
            Get-Content -Raw -LiteralPath $Launched['document'] |
                Should -Be (Get-Content -Raw -LiteralPath $Launched['source'])
        }
    }

    It 'says what it could not stop, and still stops the rest' {
        InModuleScope Xmip -Parameters @{ Launched = $script:Launched } {
            param($Launched)

            Mock Get-XmipClusterRunning { 31 }
            Mock Stop-XmipTest { throw 'REFUSED: roll 31 could not be stopped' }
            Mock Get-XmipOperationWeb { [pscustomobject]@{ Id = 41 } }
            Mock Stop-XmipOperationWeb { }
            Mock Stop-XmipProcess { }

            $part = Stop-XmipDemoStarted -Launched $Launched

            $part.State | Should -Be 'FAILED'
            $part.Reason | Should -BeLike "$($Launched['roll']) was not stopped: REFUSED*"
            Should -Invoke Stop-XmipOperationWeb -Times 1
            Should -Invoke Stop-XmipProcess -Times 1
            Get-Content -Raw -LiteralPath $Launched['document'] | Should -Match 'local'
        }
    }

    It 'stops no roll of the cluster but its own, and no pid the system gave another since' {
        InModuleScope Xmip -Parameters @{ Launched = $script:Launched } {
            param($Launched)

            # Another rolls the cluster now (pid 77), and the desktop app's
            # pid is this pwsh's, which started at another time.
            $Launched['desktop_started'] = '2026-01-01T00:00:00.0000000Z'
            Mock Get-XmipClusterRunning { 77 }
            Mock Stop-XmipTest { }
            Mock Get-XmipOperationWeb { }
            Mock Stop-XmipOperationWeb { }
            Mock Stop-XmipProcess { }

            $part = Stop-XmipDemoStarted -Launched $Launched

            $part.State | Should -Be 'OK'
            $part.Reason | Should -BeLike "*the desktop app, pid $PID, had ended*"
            Should -Invoke Stop-XmipTest -Times 0
            Should -Invoke Stop-XmipProcess -Times 0
        }
    }

    It 'never stops by an empty pipeline, which would stop every run and every host' {
        InModuleScope Xmip -Parameters @{ Launched = $script:Launched } {
            param($Launched)

            Mock Get-XmipClusterRunning { }
            Mock Stop-XmipTest { }
            Mock Get-XmipOperationWeb { }
            Mock Stop-XmipOperationWeb { }
            Mock Stop-XmipProcess { }

            (Stop-XmipDemoStarted -Launched $Launched).State | Should -Be 'OK'
            Should -Invoke Stop-XmipTest -Times 0
            Should -Invoke Stop-XmipOperationWeb -Times 0
        }
    }

    It 'stops nothing where the run started nothing' {
        InModuleScope Xmip {
            Mock Stop-XmipTest { }
            Mock Stop-XmipOperationWeb { }
            Mock Stop-XmipProcess { }

            [hashtable] $none = @{ roll = ''; roll_ids = @(); web = 0; desktop = 0; document = '' }
            $part = Stop-XmipDemoStarted -Launched $none

            $part.Reason | Should -Be 'it had started nothing'
            Should -Invoke Stop-XmipTest -Times 0
            Should -Invoke Stop-XmipOperationWeb -Times 0
            Should -Invoke Stop-XmipProcess -Times 0
        }
    }

    It 'is what Stop-XmipTest runs before it ends a demo run''s pwsh' {
        [hashtable] $given = @{
            Area    = (New-XmipDemoArea -Name 'stop')
            Cluster = $script:Cluster
        }

        InModuleScope Xmip -Parameters $given {
            param($Area, $Cluster)

            [hashtable] $sleeping = @{
                FilePath     = Join-Path $PSHOME "pwsh$((Get-XmipEssentialsLayout).Suffix)"
                ArgumentList = @('-NoProfile', '-Command', 'Start-Sleep -Seconds 120')
                PassThru     = $true
            }

            if ($IsWindows) {
                $sleeping.WindowStyle = 'Hidden'
            }

            $process = Start-Process @sleeping

            # Ended whatever fails below: a test never leaves a process behind.
            try {
                [hashtable] $began = @{
                    Record  = Join-Path $Area 'demo-7.toml'
                    Cluster = $Cluster
                    Log     = Join-Path $Area 'demo-7.log'
                    Id      = $process.Id
                    Started = $process.StartTime
                }
                $state = New-XmipDemoState @began
                $state['launched']['roll'] = $Cluster
                Write-XmipDemoRecord -Run $state

                $script:DemoArea = $Area
                Mock Get-XmipTestStatus { Get-XmipDemoRun -Path $script:DemoArea }
                Mock Stop-XmipDemoStarted {
                    New-XmipDemoPart -Name 'stop' -State 'OK' -Reason 'done'
                }
                Mock Write-Host { }
                Mock Write-XmipAudit { }

                Stop-XmipTest -Id $process.Id -Confirm:$false

                $process.WaitForExit(5000) | Should -BeTrue
                Should -Invoke Stop-XmipDemoStarted -Times 1 -ParameterFilter {
                    $Launched['roll'] -eq $Cluster
                }
                Test-Path -LiteralPath $began.Record | Should -BeFalse
            }
            finally {
                if (-not $process.HasExited) {
                    $process.Kill($true)
                }
            }
        }
    }

    It 'stops what a run that died left, by -Id, where it would refuse any other ended run' {
        [hashtable] $given = @{
            Area    = (New-XmipDemoArea -Name 'died-stop')
            Cluster = $script:Cluster
        }

        InModuleScope Xmip -Parameters $given {
            param($Area, $Cluster)

            [hashtable] $began = @{
                Record  = Join-Path $Area 'demo-8.toml'
                Cluster = $Cluster
                Log     = Join-Path $Area 'demo-8.log'
                Id      = 2000000000
                Started = [datetime] '2026-11-10T10:00:00Z'
            }
            $dead = New-XmipDemoState @began
            $dead['launched']['roll'] = $Cluster
            Write-XmipDemoRecord -Run $dead

            $script:DemoArea = $Area
            Mock Get-XmipTestStatus { Get-XmipDemoRun -Path $script:DemoArea }
            Mock Stop-XmipDemoStarted { New-XmipDemoPart -Name 'stop' -State 'OK' -Reason 'done' }
            Mock Stop-XmipDetachedRun { throw 'its pwsh is gone' }
            Mock Write-Host { }
            Mock Write-XmipAudit { }

            { Stop-XmipTest -Id 2000000000 -Confirm:$false -ErrorAction Stop } | Should -Not -Throw

            Should -Invoke Stop-XmipDemoStarted -Times 1 -ParameterFilter {
                $Launched['roll'] -eq $Cluster
            }
            Test-Path -LiteralPath $began.Record | Should -BeFalse
        }
    }

    It 'still refuses, in words, a roll named by -Id that ended on its own' {
        InModuleScope Xmip -Parameters @{ Cluster = $script:Cluster } {
            param($Cluster)

            # Only a roll a demo run stopped in the same call is passed over.
            [hashtable] $row = @{
                Suite    = 'Core.Essentials'
                Kind     = 'roll'
                State    = 'running'
                Id       = 2000000001
                Property = @{ Cluster = $Cluster; Stress = 'Realistic' }
            }
            $script:Ended = New-XmipTestStatus @row
            Mock Get-XmipTestStatus { $script:Ended }
            Mock Get-XmipTestNode { }
            Mock Stop-XmipTestCluster { }
            Mock Stop-XmipProcess { throw 'no process has that id' }
            Mock Write-XmipAudit { }

            { Stop-XmipTest -Id 2000000001 -Confirm:$false -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*REFUSED: roll 2000000001 could not be stopped*'
        }
    }
}

Describe 'The desktop app reads its deployed gui.toml, never the source' {
    It 'points the deployed copy at the snapshot and keeps every other key' {
        [string] $area = New-XmipDemoArea -Name 'document'
        [string] $source = Join-Path $area 'gui.toml'
        [string] $deployed = Join-Path $area 'bin/gui.toml'
        [string] $snapshot = Join-Path $area "$script:Cluster-snapshot.xmip"
        New-Item -ItemType Directory -Path (Split-Path $deployed) | Out-Null
        Set-Content -LiteralPath $source -Value @(
            '# a comment the source keeps'
            '[Xmip]'
            'Surface = "local"'
            'Node = "edge-01"'
        )
        [string] $before = (Get-FileHash -LiteralPath $source).Hash

        InModuleScope Xmip -Parameters @{ S = $source; D = $deployed; N = $snapshot } {
            param($S, $D, $N)

            Set-XmipDemoDocument -Source $S -Deployed $D -Snapshot $N
            $read = Read-XmipToml -Path $D

            $read['Xmip']['Surface'] | Should -Be 'snapshot'
            $read['Xmip']['Snapshot'] | Should -Be ([System.IO.Path]::GetFullPath($N))
            $read['Xmip']['Node'] | Should -Be 'edge-01'
        }

        (Get-FileHash -LiteralPath $source).Hash | Should -Be $before
    }

    It 'refuses to write the source' {
        [string] $area = New-XmipDemoArea -Name 'source'
        [string] $source = Join-Path $area 'gui.toml'
        Set-Content -LiteralPath $source -Value "[Xmip]`nSurface = `"local`""

        InModuleScope Xmip -Parameters @{ S = $source; Cluster = $script:Cluster } {
            param($S, $Cluster)

            { Set-XmipDemoDocument -Source $S -Deployed $S -Snapshot "$Cluster-snapshot.xmip" } |
                Should -Throw -ExpectedMessage '*REFUSED*never the source*'
        }

        Get-Content -Raw -LiteralPath $source | Should -Match 'local'
    }

    It 'rewrites a document PSToml returned as an object as it rewrites a dictionary' {
        # Read-XmipToml's contract: one version of PSToml returns a
        # dictionary and the next a PSObject, so neither is indexed.
        [string] $area = New-XmipDemoArea -Name 'shape'
        [hashtable] $given = @{
            S = Join-Path $area 'gui.toml'
            D = Join-Path $area 'deployed.toml'
            N = Join-Path $area "$script:Cluster-snapshot.xmip"
        }
        Set-Content -LiteralPath $given.S -Value "[Xmip]`nSurface = `"local`""

        InModuleScope Xmip -Parameters $given {
            param($S, $D, $N)

            $script:Source = $S
            [scriptblock] $asObject = {
                [pscustomobject]@{
                    Xmip  = [pscustomobject]@{ Surface = 'local'; Node = 'edge-01' }
                    Other = [pscustomobject]@{ Kept = 'yes' }
                }
            }
            Mock Read-XmipToml -MockWith $asObject -ParameterFilter { $Path -eq $script:Source }

            Set-XmipDemoDocument -Source $S -Deployed $D -Snapshot $N

            # Read as text: the reader itself is the mock here.
            [string] $written = Get-Content -Raw -LiteralPath $D
            $written | Should -Match '(?m)^Surface = "snapshot"'
            $written | Should -Match '(?m)^Node = "edge-01"'
            $written | Should -Match '(?ms)^\[Other\]\s*Kept = "yes"'
        }
    }
}

Describe 'The desktop app is the program dotnet names, and is said only to have stayed up' {
    BeforeEach {
        [string] $area = New-XmipDemoArea -Name ([guid]::NewGuid().ToString('n'))
        [string] $dll = Join-Path $area 'Xmip.Operations.dll'
        [string] $exe = Join-Path $area 'Xmip.Operations.exe'
        Set-Content -LiteralPath $dll -Value ''
        Set-Content -LiteralPath $exe -Value ''
        $script:Given = @{ Area = $area; Dll = $dll; Exe = $exe; Cluster = $script:Cluster }
    }

    It 'takes the program from the line dotnet says it is, whatever notice comes after it' {
        InModuleScope Xmip -Parameters $script:Given {
            param($Area, $Dll, $Exe, $Cluster)

            # Invoke-XmipTool keeps standard error in the same lines.
            $script:Said = @(
                "$Area\Xmip.Operations.csproj : warning MSB3277: conflicts in $Area\Some.dll"
                $Dll
                'Workload updates are available. Run dotnet workload list for more information.'
            )
            Mock Invoke-XmipTool { [pscustomobject]@{ Passed = $true; Said = $script:Said } }

            Build-XmipDemoDesktop -Project $Area | Should -Be $Exe
            Select-XmipBuiltTarget -Said @($script:Said[0], $script:Said[2]) | Should -Be ''
        }
    }

    It 'says the app stayed up, and never that it read the snapshot' -Skip:(-not $IsWindows) {
        InModuleScope Xmip -Parameters $script:Given {
            param($Area, $Dll, $Exe, $Cluster)

            $script:Program = $Exe
            Mock Get-XmipEssentialsLayout { [pscustomobject]@{ Desktop = 'project' } }
            Mock Build-XmipDemoDesktop { $script:Program }
            Mock Set-XmipDemoDocument { }
            Mock Write-XmipDemoRecord { }
            Mock Start-XmipDemoDesktop { Get-Process -Id $PID }

            [timespan] $before = $script:XmipDemoDesktopUp
            $script:XmipDemoDesktopUp = [timespan]::FromMilliseconds(600)

            try {
                [hashtable] $began = @{
                    Record = 'r'; Cluster = $Cluster; Log = 'l'; Id = 1; Started = Get-Date
                }
                $run = New-XmipDemoState @began
                $run['snapshot'] = "$Cluster-snapshot.xmip"
                [string] $said = Test-XmipDemoDesktop -Run $run
            }
            finally {
                $script:XmipDemoDesktopUp = $before
            }

            $said | Should -BeLike '*stayed up for*that it read the snapshot is not proved*'
            $run['launched']['desktop'] | Should -Be $PID
            $run['launched']['desktop_program'] | Should -Be $Exe
            $run['launched']['desktop_started'] | Should -Not -BeNullOrEmpty
        }
    }

    It 'leaves the app out of what the run stops once it ends by itself' -Skip:(-not $IsWindows) {
        InModuleScope Xmip -Parameters $script:Given {
            param($Area, $Dll, $Exe, $Cluster)

            $script:Program = $Exe
            $script:Shell = (Get-Process -Id $PID).Path
            Mock Get-XmipEssentialsLayout { [pscustomobject]@{ Desktop = 'project' } }
            Mock Build-XmipDemoDesktop { $script:Program }
            Mock Set-XmipDemoDocument { }
            Mock Write-XmipDemoRecord { }
            Mock Start-XmipDemoDesktop {
                [hashtable] $ending = @{
                    FilePath     = $script:Shell
                    ArgumentList = @('-NoProfile', '-Command', 'exit 3')
                    WindowStyle  = 'Hidden'
                    PassThru     = $true
                }
                $ended = Start-Process @ending
                $ended.WaitForExit()
                $ended
            }

            [hashtable] $began = @{
                Record = 'r'; Cluster = $Cluster; Log = 'l'; Id = 1; Started = Get-Date
            }
            $run = New-XmipDemoState @began
            $run['snapshot'] = "$Cluster-snapshot.xmip"

            { Test-XmipDemoDesktop -Run $run } |
                Should -Throw -ExpectedMessage '*it ended * s after it started, exit code 3*'
            $run['launched']['desktop'] | Should -Be 0
        }
    }
}

Describe 'The language server is asked as an editor asks' {
    It 'frames a message by its UTF-8 length and reads it back' {
        InModuleScope Xmip {
            $stream = [System.IO.MemoryStream]::new()
            [hashtable] $message = @{ jsonrpc = '2.0'; id = 1; method = 'initialize'; note = 'é' }

            Write-XmipLspFrame -Stream $stream -Message $message
            $stream.Position = 0
            [string] $head = [System.Text.Encoding]::ASCII.GetString($stream.ToArray(), 0, 20)
            [string] $body = Read-XmipLspFrame -Stream $stream -Wait ([timespan]::FromSeconds(1))

            $head | Should -BeLike 'Content-Length: *'
            ($body | ConvertFrom-Json).note | Should -Be 'é'
            [int] $said = [int] ($head -replace '\D', '')
            $said | Should -Be ([System.Text.Encoding]::UTF8.GetByteCount($body))
        }
    }

    It 'passes over what a server says before it answers the request' {
        InModuleScope Xmip {
            $stream = [System.IO.MemoryStream]::new()
            [hashtable] $logged = @{
                jsonrpc = '2.0'; method = 'window/logMessage'; params = @{ message = 'up' }
            }
            [hashtable] $asks = @{ jsonrpc = '2.0'; id = 1; method = 'client/registerCapability' }
            [hashtable] $answer = @{ jsonrpc = '2.0'; id = 1; result = @{ capabilities = @{} } }

            foreach ($message in $logged, $asks, $answer) {
                Write-XmipLspFrame -Stream $stream -Message $message
            }

            $stream.Position = 0
            $read = Read-XmipLspAnswer -Stream $stream -Id 1 -Wait ([timespan]::FromSeconds(1))

            $read.ContainsKey('result') | Should -BeTrue
            $read.ContainsKey('method') | Should -BeFalse
        }
    }

    It 'says a server that closed its output, or did not answer, did not answer' {
        InModuleScope Xmip {
            [byte[]] $cut = [System.Text.Encoding]::ASCII.GetBytes("Content-Length: 40`r`n`r`n{")
            $ended = [System.IO.MemoryStream]::new($cut)
            { Read-XmipLspFrame -Stream $ended -Wait ([timespan]::FromSeconds(1)) } |
                Should -Throw -ExpectedMessage '*closed its output*'

            $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
            $listener.Start()
            $client = [System.Net.Sockets.TcpClient]::new()

            try {
                $client.Connect([System.Net.IPAddress]::Loopback, $listener.LocalEndpoint.Port)
                $quiet = $listener.AcceptTcpClient()
                [timespan] $brief = [timespan]::FromMilliseconds(200)

                { Read-XmipLspFrame -Stream $client.GetStream() -Wait $brief } |
                    Should -Throw -ExpectedMessage '*did not answer within*'
                $quiet.Dispose()
            }
            finally {
                $client.Dispose()
                $listener.Stop()
            }
        }
    }

    It 'finds the server where cargo says it wrote it' {
        InModuleScope Xmip {
            [string[]] $said = @(
                '{"reason":"compiler-artifact","target":{"name":"xmip_core"},"executable":null}'
                '   Compiling xmip-core-gui-vscode v0.1.0'
                '{"reason":"compiler-artifact","target":{"name":"xmip-lsp"},' +
                    '"executable":"D:/t/debug/xmip-lsp.exe"}'
                '{"reason":"build-finished","success":true}'
            )

            Get-XmipCargoExecutable -Said $said -Name 'xmip-lsp' |
                Should -Be 'D:/t/debug/xmip-lsp.exe'
            Get-XmipCargoExecutable -Said $said[0..1] -Name 'xmip-lsp' | Should -Be ''
        }
    }
}

Describe 'The web host is asked over https under the Essentials'' authority' {
    BeforeAll {
        <#
            .SYNOPSIS
            A certificate with its private key: an authority's, a leaf for
            127.0.0.1 under -Issuer, or a leaf signed by its own key.
        #>
        function New-XmipDemoCertificate {
            param([string] $Name, $Issuer, [switch] $Authority)

            [string] $x509 = 'System.Security.Cryptography.X509Certificates'
            $key = [System.Security.Cryptography.ECDsa]::Create(
                [System.Security.Cryptography.ECCurve+NamedCurves]::nistP256)
            $request = ("$x509.CertificateRequest" -as [type])::new(
                "CN=$Name", $key, [System.Security.Cryptography.HashAlgorithmName]::SHA256)

            if ($Authority) {
                [type] $constraints = "$x509.X509BasicConstraintsExtension" -as [type]
                $request.CertificateExtensions.Add($constraints::new($true, $false, 0, $true))
            }
            else {
                $names = ("$x509.SubjectAlternativeNameBuilder" -as [type])::new()
                $names.AddIpAddress([System.Net.IPAddress]::Loopback)
                $request.CertificateExtensions.Add($names.Build())
            }

            [datetimeoffset] $from = [datetimeoffset]::UtcNow.AddDays(-1)
            [datetimeoffset] $to = [datetimeoffset]::UtcNow.AddDays(1 + [int] [bool] $Authority)
            $made = if ($null -eq $Issuer) {
                $request.CreateSelfSigned($from, $to)
            }
            else {
                [byte[]] $serial = [guid]::NewGuid().ToByteArray()
                $serial[0] = $serial[0] -band 0x7f
                $public = $request.Create($Issuer, $from, $to, $serial)

                # An extension method, called as the static it is.
                ("$x509.ECDsaCertificateExtensions" -as [type])::CopyWithPrivateKey($public, $key)
            }

            # SChannel serves a key it can find, one loaded from PKCS #12.
            [byte[]] $pfx = $made.Export(("$x509.X509ContentType" -as [type])::Pkcs12)

            return ("$x509.X509CertificateLoader" -as [type])::LoadPkcs12($pfx, $null)
        }

        <#
            .SYNOPSIS
            A one-request https host on loopback serving -Certificate: what a
            browser meets at the web host, answering 204 to one request.
        #>
        function Start-XmipDemoTlsHost {
            param($Certificate)

            $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
            $listener.Start()
            $job = Start-ThreadJob -ArgumentList $listener, $Certificate -ScriptBlock {
                param($Listener, $Certificate)

                $client = $Listener.AcceptTcpClient()

                try {
                    $tls = [System.Net.Security.SslStream]::new($client.GetStream(), $false)
                    $tls.AuthenticateAsServer($Certificate, $false, $false)
                    $reader = [System.IO.StreamReader]::new($tls, [System.Text.Encoding]::ASCII)

                    while (-not [string]::IsNullOrEmpty($reader.ReadLine())) { }

                    [byte[]] $answer = [System.Text.Encoding]::ASCII.GetBytes(
                        "HTTP/1.1 204 No Content`r`nContent-Length: 0`r`nConnection: close`r`n`r`n")
                    $tls.Write($answer, 0, $answer.Length)
                    $tls.Flush()
                }
                catch {
                    $_.Exception.Message
                }
                finally {
                    $client.Dispose()
                }
            }

            return [pscustomobject]@{
                Listener = $listener
                Job      = $job
                Url      = "https://127.0.0.1:$($listener.LocalEndpoint.Port)"
            }
        }

        <#
            .SYNOPSIS
            Ends a host from Start-XmipDemoTlsHost, whatever it got to.
        #>
        function Stop-XmipDemoTlsHost {
            param($TlsHost)

            $TlsHost.Listener.Stop()
            $null = $TlsHost.Job | Wait-Job -Timeout 10
            $TlsHost.Job | Remove-Job -Force
        }

        $script:Authority = New-XmipDemoCertificate -Name 'anchor' -Authority
        $script:AnchorFile = Join-Path (New-XmipDemoArea -Name 'tls') 'authority.pem'
        Set-Content -LiteralPath $script:AnchorFile -Value $script:Authority.ExportCertificatePem()
    }

    It 'says the host answered where its certificate reaches the anchor' {
        $leaf = New-XmipDemoCertificate -Name '127.0.0.1' -Issuer $script:Authority
        $tlsHost = Start-XmipDemoTlsHost -Certificate $leaf

        try {
            InModuleScope Xmip -Parameters @{ Url = $tlsHost.Url; Anchor = $script:AnchorFile } {
                param($Url, $Anchor)

                [string] $said = Test-XmipDemoHttps -Url $Url -TrustAnchor $Anchor -Wait (
                    [timespan]::FromSeconds(10))
                $said | Should -BeLike 'answered HTTP 204 after * s'
            }
        }
        finally {
            Stop-XmipDemoTlsHost -TlsHost $tlsHost
        }
    }

    It 'says a certificate under another key does not reach the anchor' {
        $other = New-XmipDemoCertificate -Name '127.0.0.1'
        $tlsHost = Start-XmipDemoTlsHost -Certificate $other

        try {
            InModuleScope Xmip -Parameters @{ Url = $tlsHost.Url; Anchor = $script:AnchorFile } {
                param($Url, $Anchor)

                [hashtable] $asked = @{
                    Url = $Url; TrustAnchor = $Anchor; Wait = [timespan]::FromSeconds(10)
                }
                [string] $refused = "$Url presented a certificate that does not reach*"
                { Test-XmipDemoHttps @asked } | Should -Throw -ExpectedMessage $refused
            }
        }
        finally {
            Stop-XmipDemoTlsHost -TlsHost $tlsHost
        }
    }

    It 'says nothing answered, within its wait, where nothing listens' {
        [string] $anchor = Join-Path (New-XmipDemoArea -Name 'anchor') 'authority.pem'
        $key = [System.Security.Cryptography.ECDsa]::Create()
        $request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
            'CN=anchor', $key, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
        $made = $request.CreateSelfSigned([datetimeoffset]::Now.AddDays(-1), [datetimeoffset]::Now)
        Set-Content -LiteralPath $anchor -Value $made.ExportCertificatePem()

        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $listener.Start()
        [int] $port = $listener.LocalEndpoint.Port
        $listener.Stop()

        InModuleScope Xmip -Parameters @{ Anchor = $anchor; Port = $port } {
            param($Anchor, $Port)

            [hashtable] $asked = @{
                Url         = "https://127.0.0.1:$Port"
                TrustAnchor = $Anchor
                Wait        = [timespan]::FromSeconds(1)
            }

            { Test-XmipDemoHttps @asked } |
                Should -Throw -ExpectedMessage "*nothing answered https at https://127.0.0.1:$Port*"
        }
    }

    It 'takes the anchor the host was given only where it is the Essentials'' authority' {
        InModuleScope Xmip {
            [string] $authority = (Get-XmipEssentialsLayout).Authority
            $script:Line = "xmip-gui-web --Xmip:TrustAnchor=$(Join-Path $authority 'a.pem')"
            Mock Get-Process { [pscustomobject]@{ CommandLine = $script:Line } }

            Get-XmipDemoWebAnchor -Id 5 | Should -Be (Join-Path $authority 'a.pem')

            [string] $elsewhere = Join-Path ([System.IO.Path]::GetTempPath()) 'ca.pem'
            $script:Line = "xmip-gui-web --Xmip:TrustAnchor=$elsewhere"
            { Get-XmipDemoWebAnchor -Id 5 } |
                Should -Throw -ExpectedMessage "*not the Essentials' authority*"

            # A folder beside it whose name begins with the authority's.
            [string] $beside = [System.IO.Path]::TrimEndingDirectorySeparator($authority) + '-old'
            $script:Line = "xmip-gui-web --Xmip:TrustAnchor=$(Join-Path $beside 'ca.pem')"
            { Get-XmipDemoWebAnchor -Id 5 } |
                Should -Throw -ExpectedMessage "*not the Essentials' authority*"
        }
    }
}
