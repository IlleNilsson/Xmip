#requires -PSEdition Core
#requires -Version 7.6.7

<#
    A roll builds detached. The owner, 2026-10-13, of Start-XmipTest holding his
    console during the first build: the build runs detached too — Start-XmipTest
    returns at once, Get-XmipTestStatus says building, with progress, until the
    nodes start, a build that fails is the run's state with its reason, and
    Stop-XmipTest stops a build. These check it over fixtures and one sleeping
    pwsh standing in for a build; nothing here runs cargo or a roll. The names
    are the test cluster's (ADR-0056, amendment 2026-10-03).
#>

BeforeAll {
    $script:AuditBefore = $env:XMIP_AUDIT_DIRECTORY
    $env:XMIP_AUDIT_DIRECTORY = Join-Path -Path $TestDrive -ChildPath 'audit'

    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    $script:Cluster = Get-XmipTestCluster
    [string] $first = $script:Cluster.Nodes[0]
    $script:Named = @{ Cluster = $script:Cluster.Name; Node = $first }

    <#
        .SYNOPSIS
        A fresh roll area under this run's drive.
    #>
    function New-XmipBuildArea {
        param([string] $Name)

        [string] $area = Join-Path -Path $TestDrive -ChildPath $Name
        New-Item -ItemType Directory -Path $area -Force | Out-Null

        return $area
    }
}

AfterAll {
    $env:XMIP_AUDIT_DIRECTORY = $script:AuditBefore
}

Describe 'Start-XmipTest returns before the build' {
    It 'hands the build to a detached pwsh and never builds in the console' {
        [hashtable] $given = $script:Named + @{ Area = (New-XmipBuildArea -Name 'start') }

        InModuleScope Xmip -Parameters $given {
            param($Cluster, $Node, $Area)

            Mock Start-XmipPlaygroundBuild { 4242 }
            Mock Invoke-XmipPlaygroundBuild { throw 'the console built' }
            Mock Get-XmipPlaygroundPublication { throw 'no binary in this test' }
            Mock Get-XmipTestStatus { }
            Mock Write-Host { }

            [hashtable] $door = @{
                Suite    = 'Core.Playground'
                Cluster  = $Cluster
                Nodes    = @($Node)
                NodeRole = @{ $Node = 'executing' }
                Rounds   = 1
                Path     = $Area
            }
            Start-XmipTest @door

            Should -Invoke Invoke-XmipPlaygroundBuild -Times 0
            Should -Invoke Start-XmipPlaygroundBuild -Times 1 -ParameterFilter {
                $Start.Cluster -eq $Cluster -and $Start.Rounds -eq 1 -and
                    $Start.Path -eq $Area -and $Start.Snapshot -eq ''
            }
            Should -Invoke Write-Host -ParameterFilter { "$Object" -like '*pid 4242, detached*' }
        }
    }

    It 'refuses a cluster that is still building, before anything starts' {
        [hashtable] $given = $script:Named + @{ Area = (New-XmipBuildArea -Name 'twice') }

        InModuleScope Xmip -Parameters $given {
            param($Cluster, $Node, $Area)

            $script:Building = [pscustomobject]@{
                Id = 99; Kind = 'build'; State = 'building'; Cluster = $Cluster
            }
            Mock Get-XmipPlaygroundBuild { $script:Building }
            Mock Start-XmipPlaygroundBuild { 1 }

            [hashtable] $door = @{
                Cluster  = $Cluster
                Nodes    = @($Node)
                NodeRole = @{ $Node = 'executing' }
                Path     = $Area
            }

            { Start-XmipTest @door -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*REFUSED*rolling or building as pid 99*'
            Should -Invoke Start-XmipPlaygroundBuild -Times 0
        }
    }

    It 'builds only in the detached half, which the console starts encoded' {
        [string] $module = Join-Path $script:Root 'Xmip'
        [string] $console = Get-Content -Raw -LiteralPath (
            Join-Path $module 'Start-XmipPlaygroundRoll.ps1')
        [string] $detached = Get-Content -Raw -LiteralPath (
            Join-Path $module 'Start-XmipPlaygroundBuild.ps1')

        $console | Should -Not -Match 'Invoke-XmipPlaygroundBuild'
        $detached | Should -Match 'Invoke-XmipPlaygroundBuild -Binary roll'
        $detached | Should -Match '-EncodedCommand'
    }
}

Describe 'A build says how it stands' {
    It 'counts the crates cargo compiled, and says when it starts the roll' {
        [string] $area = New-XmipBuildArea -Name 'progress'
        [string] $log = Join-Path $area 'build-1.log'

        InModuleScope Xmip -Parameters @{ Log = $log } {
            param($Log)

            Get-XmipPlaygroundBuildProgress -Log $Log | Should -Be 'building'

            Set-Content -LiteralPath $Log -Value @(
                '   Compiling first-crate v0.1.0 (path)'
                '   Compiling second-crate v0.1.0'
            )
            Get-XmipPlaygroundBuildProgress -Log $Log |
                Should -Be 'building: 2 crates compiled, last second-crate'

            Add-Content -LiteralPath $Log -Value '    Finished `dev` profile in 9.0s'
            Get-XmipPlaygroundBuildProgress -Log $Log |
                Should -Be 'built 2 crates; starting the roll'
        }
    }

    It 'writes FAILED with cargo''s reason, and leaves nothing handed over' {
        [hashtable] $given = $script:Named + @{ Area = (New-XmipBuildArea -Name 'failed') }

        InModuleScope Xmip -Parameters $given {
            param($Cluster, $Node, $Area)

            [hashtable] $start = @{
                Suite = 'Core.Playground'; Cluster = $Cluster; Stress = 'Calm'
                Test = @(); Rounds = 1; Nodes = @($Node); OnlineNodes = @()
                Hidden = $false; Snapshot = ''; Path = $Area
                Log = Join-Path $Area 'build-1.log'
            }
            [string] $handed = Join-Path $Area 'build-1.clixml'
            [string] $record = Join-Path $Area 'build-1.toml'
            Export-Clixml -LiteralPath $handed -InputObject $start -Depth 5

            Mock Invoke-XmipPlaygroundBuild {
                throw 'cargo build --bin roll exited 101 in here: error: could not compile'
            }
            Mock Start-XmipPlaygroundRollProcess { 7 }

            Complete-XmipPlaygroundBuild -Record $record -Handed $handed

            Test-Path -LiteralPath $handed | Should -BeFalse
            Should -Invoke Start-XmipPlaygroundRollProcess -Times 0

            $build = Get-XmipPlaygroundBuild -Path $Area
            $build.Kind | Should -Be 'build'
            $build.State | Should -Be 'FAILED'
            $build.Cluster | Should -Be $Cluster
            $build.Fault | Should -BeLike '*error: could not compile*'
            $build.Tally | Should -Be $build.Fault
        }
    }

    It 'leaves the record to the roll once the roll is spawned' {
        [hashtable] $given = $script:Named + @{ Area = (New-XmipBuildArea -Name 'built') }

        InModuleScope Xmip -Parameters $given {
            param($Cluster, $Node, $Area)

            [hashtable] $start = @{ Cluster = $Cluster; Nodes = @($Node); Path = $Area }
            [string] $handed = Join-Path $Area 'build-2.clixml'
            [string] $record = Join-Path $Area 'build-2.toml'
            Export-Clixml -LiteralPath $handed -InputObject $start -Depth 5
            Set-Content -LiteralPath $record -Value 'pid = 1'

            Mock Invoke-XmipPlaygroundBuild { 'roll' }
            Mock Invoke-XmipPlaygroundService { 'service' }
            Mock Start-XmipPlaygroundRollProcess { 7 }

            Complete-XmipPlaygroundBuild -Record $record -Handed $handed

            Should -Invoke Start-XmipPlaygroundRollProcess -Times 1 -ParameterFilter {
                $Start.Cluster -eq $Cluster
            }
            Test-Path -LiteralPath $record | Should -BeFalse
        }
    }

    It 'says a build whose pwsh died FAILED, and a new start of its cluster clears it' {
        [hashtable] $given = $script:Named + @{ Area = (New-XmipBuildArea -Name 'died') }

        InModuleScope Xmip -Parameters $given {
            param($Cluster, $Node, $Area)

            foreach ($pair in @(@('3', $Cluster), @('4', "${Cluster}2"))) {
                [hashtable] $start = @{ Cluster = $pair[1]; Log = "$Area/build-$($pair[0]).log" }
                $written = New-XmipPlaygroundBuildRecord -Start $start -Id 2000000000 -Started (
                    [datetime] '2026-10-13T10:00:00Z')
                Write-XmipToml -Path (Join-Path $Area "build-$($pair[0]).toml") -Value $written
            }

            [object[]] $builds = @(Get-XmipPlaygroundBuild -Path $Area)
            $builds.Count | Should -Be 2
            $builds | ForEach-Object { $_.State | Should -Be 'FAILED' }
            $builds[0].Fault | Should -BeLike '*ended without starting its roll*'

            Remove-XmipPlaygroundBuildEnded -Path $Area -Cluster $Cluster -Confirm:$false
            @(Get-XmipPlaygroundBuild -Path $Area | ForEach-Object { $_.Cluster }) |
                Should -Be @("${Cluster}2")
        }
    }
}

Describe 'Stop-XmipTest stops a build' {
    It 'ends a building pwsh and what it started, and takes its record' {
        [hashtable] $given = $script:Named + @{ Area = (New-XmipBuildArea -Name 'stop') }

        InModuleScope Xmip -Parameters $given {
            param($Cluster, $Node, $Area)

            [hashtable] $sleeping = @{
                FilePath     = Join-Path $PSHOME "pwsh$((Get-XmipPlaygroundLayout).Suffix)"
                ArgumentList = @('-NoProfile', '-Command', 'Start-Sleep -Seconds 120')
                PassThru     = $true
            }

            if ($IsWindows) {
                $sleeping.WindowStyle = 'Hidden'
            }

            $process = Start-Process @sleeping
            [string] $log = Join-Path $Area 'build-5.log'
            Set-Content -LiteralPath $log -Value '   Compiling only-crate v0.1.0'
            [hashtable] $start = @{ Suite = 'Core.Playground'; Cluster = $Cluster; Log = $log }
            [hashtable] $began = @{ Start = $start; Id = $process.Id; Started = $process.StartTime }
            [string] $record = Join-Path $Area 'build-5.toml'
            Write-XmipToml -Path $record -Value (New-XmipPlaygroundBuildRecord @began)

            $build = Get-XmipPlaygroundBuild -Path $Area
            $build.State | Should -Be 'building'
            $build.Tally | Should -Be 'building: 1 crate compiled, last only-crate'

            $script:BuildArea = $Area
            Mock Get-XmipTestStatus { Get-XmipPlaygroundBuild -Path $script:BuildArea }

            Stop-XmipTest -Id $process.Id -Confirm:$false

            $process.HasExited | Should -BeTrue
            Test-Path -LiteralPath $record | Should -BeFalse
        }
    }

    It 'refuses a build that has ended, naming its state' {
        InModuleScope Xmip {
            Mock Get-XmipTestStatus {
                [pscustomobject]@{
                    Id = 6; Kind = 'build'; State = 'FAILED'; Suite = 'Core.Playground'
                }
            }

            { Stop-XmipTest -Id 6 -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*REFUSED*run 6 has ended (FAILED)*'
        }
    }
}
