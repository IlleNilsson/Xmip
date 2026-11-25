#requires -PSEdition Core
#requires -Version 7.7.0

<#
    The System Tests, the Systems Tests and the demo in containers,
    Start-XmipTest -Container (ADR-0015 and ADR-0028, amendments 2026-11-25):
    the container tool each host has, what a container is made from, and the
    containers a run makes and takes away, over a container tool held in
    memory. Nothing here makes a container; a roll in containers does.
#>

BeforeAll {
    # What these commands audit while they are tested goes to this run's own
    # drive (ADR-0062), and the session's own is given back after.
    $script:AuditBefore = $env:XMIP_AUDIT_DIRECTORY
    $env:XMIP_AUDIT_DIRECTORY = Join-Path -Path $TestDrive -ChildPath 'audit'
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')
    $script:ClusterName = (Get-XmipTestCluster).Name
}

AfterAll {
    $env:XMIP_AUDIT_DIRECTORY = $script:AuditBefore
}

Describe 'The container tool and what a container is made from' {
    It 'is wslc on Windows and podman on Linux, refused in words where absent' -Skip:(
        -not ($IsWindows -or $IsLinux)) {
        InModuleScope Xmip {
            [string] $tool = if ($IsWindows) { 'wslc' } else { 'podman' }
            Mock Get-Command { } -ParameterFilter { $Name -in 'wslc', 'podman' }
            { Get-XmipContainerTool } | Should -Throw -ExpectedMessage (
                "REFUSED: running as containers on * takes $tool, which this host has not: *")

            Mock Get-Command { [pscustomobject] @{ Source = "found/$Name" } } -ParameterFilter {
                $Name -in 'wslc', 'podman'
            }
            Get-XmipContainerTool | Should -Be "found/$tool"
        }
    }

    It 'runs the image the System Tests'' file names, and refuses a file naming none' {
        InModuleScope Xmip {
            [string] $file = (Get-XmipSystemTestLayout).Configuration
            Get-XmipContainerImage -Content (Read-XmipToml -Path $file) -File $file |
                Should -Not -BeNullOrEmpty
            { Get-XmipContainerImage -Content $null -File 'none.xmip' } |
                Should -Throw -ExpectedMessage '*REFUSED: none.xmip names no image a container*'
        }
    }

    It 'gives a container the Linux build, refused naming what builds what is not there' {
        InModuleScope Xmip -Parameters @{ Drive = $TestDrive } {
            param($Drive)

            $script:Built = @{
                Service = Join-Path $Drive 'xmip-service'
                FarEnd  = Join-Path $Drive 'xmip-system-test-external'
                Modules = Join-Path $Drive 'modules'
                Build   = 'Build-XmipService -Site of-the-test'
            }
            Mock Get-XmipBuiltProgram { $script:Built } -ParameterFilter { $Family -eq 'Linux' }
            $content = Read-XmipToml -Path (Get-XmipSystemTestLayout).Configuration
            [hashtable] $asked = @{ Estate = $Drive; Content = $content }

            { Get-XmipContainerBuild @asked } | Should -Throw -ExpectedMessage (
                "*REFUSED: a container runs $($script:Built.Service), which is not there: " +
                'Build-XmipService -Site of-the-test*')
            $null = New-Item -ItemType File -Path $script:Built.Service
            { Get-XmipContainerBuild @asked } | Should -Throw -ExpectedMessage (
                "*REFUSED: a far end's container runs $($script:Built.FarEnd)*")
            $null = New-Item -ItemType File -Path $script:Built.FarEnd
            { Get-XmipContainerBuild @asked } | Should -Throw -ExpectedMessage (
                '*name module libraries, which a container is given from*')
            $null = New-Item -ItemType Directory -Path $script:Built.Modules
            (Get-XmipContainerBuild @asked).Service | Should -Be $script:Built.Service
        }
    }
}

Describe 'The containers a run makes and takes away' {
    It 'makes one for each node and far end, every port published, each node waited for' {
        [hashtable] $given = @{
            Area = (Join-Path $TestDrive 'made'); Cluster = $script:ClusterName
        }

        InModuleScope Xmip -Parameters $given {
            param($Area, $Cluster)

            $layout = Get-XmipSystemTestLayout
            [hashtable[]] $listed = @(Resolve-XmipDeployMachine -Cluster (
                    Read-XmipToml -Path $layout.Configuration))
            [string[]] $far = @($listed | Where-Object { $_.kind -eq 'far end' } |
                    ForEach-Object { $_.name })
            [string[]] $nodes = @(@($listed | Where-Object { $_.storage }) + @($listed |
                        Where-Object { $_.kind -eq 'node' -and -not $_.storage }) |
                    ForEach-Object { $_.name })
            [string] $network = "Xmip-$Cluster"

            # The slice's own writer is the deployment's, dot-sourced where it
            # is called; here it is named so it can be held.
            . (Join-Path $layout.Root 'deploy/dsc/msdsc/environment/EnvironmentSlice.ps1')
            $script:Sliced = [Collections.Generic.List[hashtable]]::new()
            $script:Told = [Collections.Generic.List[string]]::new()
            $script:Network = $network
            Mock Get-XmipContainerTool { 'tool' }
            Mock Get-XmipContainerImage { 'an image' }
            Mock Get-XmipContainerBuild {
                @{ Service = 'built/xmip-service'; FarEnd = 'built/far-end'; Modules = '' }
            }
            Mock Initialize-XmipSystemTestAuthority { }
            Mock Initialize-XmipDeployIdentity { }
            Mock Copy-XmipSystemTestImage { }
            Mock New-XmipContainerFolder { Join-Path $State "$Name/config" }
            Mock Set-EnvironmentSlice { $script:Sliced.Add($Instance) }
            Mock Get-XmipListeningPort { if ($Program -eq 'listener') { 7422, 7423 } else { 7401 } }
            Mock Invoke-XmipContainerTool {
                $script:Told.Add($Argument -join ' ')
                if ($Argument[0] -eq 'inspect') {
                    '[{"NetworkSettings":{"Networks":{"' + $script:Network +
                    '":{"IPAddress":"192.0.2.30"}}}}]'
                }
            }

            [hashtable] $asked = @{
                Cluster = $Cluster; Area = $Area; Slicer = 'slicer'; Listener = 'listener'
            }
            $made = Start-XmipSystemTestContainer @asked

            $script:Told[0] | Should -Be "network create $network"
            [string[]] $created = @($script:Told | Where-Object { $_ -like 'create *' })
            $created.Count | Should -Be ($far.Count + $nodes.Count)
            foreach ($name in $far) {
                [string] $one = $created | Where-Object {
                    $_ -like "create --name xmip-system-test-$Cluster-external-$name *" }
                $one | Should -BeLike "* --network $network --network-alias $name *"
                $one | Should -Match '-p 127\.0\.0\.1:\d+:7422 -p 127\.0\.0\.1:\d+:7423 an image '
                $one | Should -BeLike "*/xmip/bin/far-end --name $name --serve *"
            }
            foreach ($name in $nodes) {
                [string] $one = $created | Where-Object {
                    $_ -like "create --name xmip-system-test-$Cluster-node-$name *" }
                $one | Should -Match '-p 127\.0\.0\.1:\d+:7401 an image /xmip/bin/xmip-service '
                [string] $into = "xmip-system-test-$Cluster-node-${name}:/xmip"
                @($script:Told | Where-Object { $_ -like "cp *${name}?config $into" }).Count |
                    Should -Be 1
            }

            # Each node waited for in order, Xmip Storage first.
            [string[]] $waited = @($script:Told | Where-Object { $_ -like 'exec *' } |
                    ForEach-Object { ($_ -split ' ')[1] })
            $waited | Should -Be @($nodes | ForEach-Object { "xmip-system-test-$Cluster-node-$_" })

            # Sliced as a deployment slices: bound to the receivers, listening.
            $script:Sliced.Count | Should -Be $nodes.Count
            $script:Sliced[0].nodes | Should -Be ($nodes -join ',')
            $script:Sliced[0].listen | Should -BeTrue
            $script:Sliced[0].program | Should -Be 'slicer'

            @($made.Nodes.Keys) | Should -Be $nodes
            @($made.FarEnds.Keys) | Should -Be $far
            $made.Published.Count | Should -Be ($nodes.Count + 2 * $far.Count)
            @($made.Published.Values | Sort-Object -Unique).Count | Should -Be $made.Published.Count
            $made.Published["$($nodes[0]):7401"] | Should -Match '^127\.0\.0\.1:\d+$'

            $record = Read-XmipToml -Path (Join-Path $Area "container/$Cluster/containers.toml")
            @(Get-TomlValue -Node $record -Name 'containers').Count | Should -Be $created.Count
        }
    }

    It 'takes away what a run recorded and is there, and nothing where none is recorded' {
        [hashtable] $given = @{
            Area = (Join-Path $TestDrive 'taken'); Cluster = $script:ClusterName
        }

        InModuleScope Xmip -Parameters $given {
            param($Area, $Cluster)

            $script:Told = [Collections.Generic.List[string]]::new()
            Mock Invoke-XmipContainerTool { $script:Told.Add($Argument -join ' ') }
            Mock Test-XmipContainerThere { $Argument[-1] -ne 'gone' }

            Remove-XmipSystemTestContainer -Cluster $Cluster -Area $Area
            $script:Told.Count | Should -Be 0

            [string] $path = Join-Path $Area "container/$Cluster/containers.toml"
            $null = New-Item -ItemType Directory -Path (Split-Path -Path $path) -Force
            Write-XmipToml -Path $path -Value ([ordered]@{
                    tool = 'tool'; network = "Xmip-$Cluster"; containers = @('one', 'gone', 'two')
                })
            Remove-XmipSystemTestContainer -Cluster $Cluster -Area $Area -Confirm:$false

            @($script:Told) | Should -Be @('rm -f one two', "network rm Xmip-$Cluster")
            Test-Path -LiteralPath $path | Should -BeFalse
        }
    }

    It 'knows a container or network is there by what the tool answers, not by its exit alone' {
        InModuleScope Xmip {
            # wslc 5.0.1 answers a network that is not there with 0, its
            # words and an empty array; podman answers otherwise than 0.
            Mock Invoke-XmipContainerTool { "Network not found: 'Xmip-gone'", '[]' }
            Test-XmipContainerThere -Tool 'tool' -Argument 'network', 'inspect', 'Xmip-gone' |
                Should -BeFalse

            Mock Invoke-XmipContainerTool { '[', '  { "Name": "Xmip-there" }', ']' }
            Test-XmipContainerThere -Tool 'tool' -Argument 'network', 'inspect', 'Xmip-there' |
                Should -BeTrue

            Mock Invoke-XmipContainerTool { throw 'FAILED: tool inspect exited 125: no such' }
            Test-XmipContainerThere -Tool 'tool' -Argument 'inspect', 'gone' | Should -BeFalse
        }
    }

    It 'takes them away where a build fails once it made them, the fault kept' {
        [hashtable] $given = @{
            Area = (Join-Path $TestDrive 'failed'); Cluster = $script:ClusterName
        }

        InModuleScope Xmip -Parameters $given {
            param($Area, $Cluster)

            $null = New-Item -ItemType Directory -Path $Area -Force
            [string] $handed = Join-Path $Area 'build.clixml'
            [string] $record = Join-Path $Area 'build.toml'
            [hashtable] $start = @{
                Cluster = $Cluster; RunsAs = 'Container'; Path = $Area; Choice = @{}
            }
            $script:Expected = $start
            Mock Invoke-XmipSystemTestBuild { 'roll' }
            Mock Invoke-XmipSystemTestService { 'xmip-service' }
            Mock Start-XmipSystemTestContainer { throw 'FAILED: DS1 was not ready' }
            Mock Start-XmipSystemTestRollProcess { 7 }
            Mock Remove-XmipSystemTestContainer { }

            Export-Clixml -LiteralPath $handed -InputObject $start
            Complete-XmipSystemTestBuild -Record $record -Handed $handed
            Should -Invoke Remove-XmipSystemTestContainer -Times 1 -Exactly -ParameterFilter {
                $Cluster -eq $script:Expected.Cluster -and $Area -eq $script:Expected.Path
            }
            Should -Invoke Start-XmipSystemTestRollProcess -Times 0
            $written = Read-XmipToml -Path $record
            Get-TomlValue -Node $written -Name 'state' | Should -Be 'FAILED'
            Get-TomlValue -Node $written -Name 'fault' | Should -Be 'FAILED: DS1 was not ready'

            Mock Remove-XmipSystemTestContainer { throw 'FAILED: tool rm exited 1: busy' }
            Export-Clixml -LiteralPath $handed -InputObject $start
            Complete-XmipSystemTestBuild -Record $record -Handed $handed
            Get-TomlValue -Node (Read-XmipToml -Path $record) -Name 'fault' | Should -Be (
                'FAILED: DS1 was not ready The containers were not taken away: ' +
                'FAILED: tool rm exited 1: busy')
        }
    }

    It 'goes with a roll or a build Stop-XmipTest stops, and with no run of another kind' {
        [hashtable] $given = @{
            Area = (Join-Path $TestDrive 'stopped'); Cluster = $script:ClusterName
        }

        InModuleScope Xmip -Parameters $given {
            param($Area, $Cluster)

            $script:Expected = @{ Cluster = $Cluster; Path = $Area }
            [scriptblock] $listed = {
                param([int] $Id, [string] $Kind, [string] $State, [string] $RunsAs)
                [hashtable] $row = @{
                    Suite = 'Core.System'; Kind = $Kind; State = $State; Id = $Id
                }
                New-XmipTestStatus @row -Property @{
                    RunsAs = $RunsAs; Cluster = $script:Expected.Cluster
                    Path = $script:Expected.Path; Record = ''; Stress = 'Calm'
                }
            }
            $script:Listed = @(
                & $listed -Id 31 -Kind 'build' -State 'building' -RunsAs 'Container'
                & $listed -Id 32 -Kind 'roll' -State 'running' -RunsAs 'Container'
                & $listed -Id 33 -Kind 'roll' -State 'running' -RunsAs 'Process'
            )
            Mock Get-XmipTestStatus { $script:Listed }
            Mock Stop-XmipDetachedRun { }
            Mock Get-XmipTestNode { }
            Mock Stop-XmipTestCluster { }
            Mock Stop-XmipProcess { }
            Mock Remove-XmipSystemTestImage { }
            Mock Remove-XmipSystemTestContainer { }
            Mock Write-XmipAudit { }
            Mock Update-XmipPromptFollowing { }

            Stop-XmipTest -Id 31, 32, 33 -Confirm:$false
            Should -Invoke Remove-XmipSystemTestContainer -Times 2 -Exactly -ParameterFilter {
                $Cluster -eq $script:Expected.Cluster -and $Area -eq $script:Expected.Path
            }
            Should -Invoke Remove-XmipSystemTestContainer -Times 2 -Exactly
        }
    }
}
