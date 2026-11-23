#requires -PSEdition Core
#requires -Version 7.7.0

<#
    A suite of the internal tests runs on another computer by -ComputerName:
    Start-XmipTest sends the estate there as a difference and that computer's
    own Start-XmipTest starts it; Get-XmipTestStatus, Get-XmipTestResult and
    Stop-XmipTest read and stop it there. Until 2026-11-23 the Linux checks
    ran through two bash scripts outside the estate (the owner, 2026-11-23:
    "Do what you recommend"). Core.Internal, the internal tests of named
    modules, came the same day.

    Nothing here reaches a computer: ssh and scp are mocked, and what crosses
    is asserted. The computer's name in these tests is a stand-in, build1.
#>

BeforeAll {
    $script:AuditBefore = $env:XMIP_AUDIT_DIRECTORY
    $env:XMIP_AUDIT_DIRECTORY = Join-Path -Path $TestDrive -ChildPath 'audit'

    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    # A computer as Read-XmipTestComputer returns it, and nothing it names
    # exists: every test that needs one mocks what would reach it.
    $script:Computer = [pscustomobject]@{
        Name = 'build1'; Host = 'build1.example'; User = 'tester'; Key = 'key'
        Folder = 'xmip-test'; Slots = 2; File = 'build1.toml'
        State = Join-Path -Path $TestDrive -ChildPath 'state'
    }

    # A row as a computer's Get-XmipTestStatus answers it, crossed.
    $script:FarRow = [pscustomobject]@{
        Suite = 'Core.Estate'; Kind = 'pester'; State = 'running'; Id = 42
        Tests = @('Toml'); Log = '/far/estate.log'; ComputerName = $null
    }
}

Describe 'A test computer is a file of this machine, never of Git' {
    BeforeAll {
        $script:Area = Join-Path -Path $TestDrive -ChildPath 'test-computer'
        New-Item -ItemType Directory -Path $script:Area | Out-Null
        $script:KeyFile = Join-Path -Path $TestDrive -ChildPath 'id_test'
        Set-Content -LiteralPath $script:KeyFile -Value 'not a key'
    }

    It 'refuses a computer whose file is not there, naming the file and the keys it needs' {
        InModuleScope Xmip -Parameters @{ Area = $script:Area } {
            param($Area)

            Mock Get-XmipEstateLayout { [pscustomobject]@{ TestComputer = $Area } }

            { Read-XmipTestComputer -Name build1 } | Should -Throw -ExpectedMessage (
                '*REFUSED. No test computer is called build1*build1.toml is not there*' +
                'never in Git*host*user*key*')
        }
    }

    It 'refuses a file that does not say a key it needs, naming it' {
        Set-Content -LiteralPath (Join-Path $script:Area 'half.toml') -Value 'host = "h"'

        InModuleScope Xmip -Parameters @{ Area = $script:Area } {
            param($Area)

            Mock Get-XmipEstateLayout { [pscustomobject]@{ TestComputer = $Area } }

            { Read-XmipTestComputer -Name half } |
                Should -Throw -ExpectedMessage '*half.toml does not say user, key.*'
        }
    }

    It 'reads its defaults, and refuses a folder a shell would read as more' {
        [string] $key = $script:KeyFile.Replace('\', '/')
        Set-Content -LiteralPath (Join-Path $script:Area 'build1.toml') -Value @(
            'host = "build1.example"', 'user = "tester"', "key = `"$key`"")
        Set-Content -LiteralPath (Join-Path $script:Area 'up.toml') -Value @(
            'host = "h"', 'user = "u"', "key = `"$key`"", 'folder = "../elsewhere"')

        InModuleScope Xmip -Parameters @{ Area = $script:Area } {
            param($Area)

            Mock Get-XmipEstateLayout { [pscustomobject]@{ TestComputer = $Area } }

            $read = Read-XmipTestComputer -Name build1
            $read.Folder | Should -Be 'xmip-test'
            $read.Slots | Should -Be 2
            $read.State | Should -Be (Join-Path $Area 'build1')

            { Read-XmipTestComputer -Name up } |
                Should -Throw -ExpectedMessage "*REFUSED*folder = '../elsewhere'*"
            { Read-XmipTestComputer -Name 'a;b' } |
                Should -Throw -ExpectedMessage '*REFUSED. a;b is no computer''s name*'
            @(Get-XmipTestComputerChoice -Word 'bu') | Should -Be @('build1')
        }
    }

    It 'keeps every computer''s file in the working area, which Git ignores' {
        [string] $area = InModuleScope Xmip { (Get-XmipEstateLayout).TestComputer }
        [string] $relative = [IO.Path]::GetRelativePath($script:Root, $area).Replace('\', '/')

        & git -C $script:Root check-ignore -q "$relative/build1.toml"
        $LASTEXITCODE | Should -Be 0 -Because "$relative holds addresses and keys"
    }
}

Describe 'The estate travels as a difference' {
    It 'names what changed and what is gone since the last send' {
        InModuleScope Xmip {
            [string[]] $sent = @("a`t1`t10", "b`t2`t20", "c`t3`t30")
            [string[]] $now = @("a`t1`t10", "b`t2`t21", "d`t4`t40")

            $difference = Compare-XmipEstateSent -Sent $sent -Now $now
            $difference.Changed | Should -Be @('b', 'd')
            $difference.Gone | Should -Be @('c')

            (Compare-XmipEstateSent -Sent @() -Now $now).Changed | Should -Be @('a', 'b', 'd')
        }
    }

    It 'leaves build output out by what it holds, never by its name' {
        # deploy/profile/target is source, and a name rule once lost it; a
        # submodule's .git names where its repository is on this machine.
        [string] $estate = Join-Path $TestDrive 'walked'

        foreach ($file in 'src/lib.rs', 'deploy/profile/target/p.toml', 'out/target/x.o',
            'out/target/CACHEDIR.TAG', 'module/one/.git', 'module/one/Cargo.toml') {
            [string] $full = Join-Path $estate $file
            New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
            Set-Content -LiteralPath $full -Value 'x'
        }

        InModuleScope Xmip -Parameters @{ Estate = $estate } {
            param($Estate)

            [string[]] $paths = @(Get-XmipEstateSent -Root $Estate | ForEach-Object {
                    $_.Split("`t")[0] } | Sort-Object)

            $paths | Should -Be @('deploy/profile/target/p.toml', 'module/one/Cargo.toml',
                'src/lib.rs')
        }
    }

    It 'sends everything once, then only the difference, and everything where the mirror went' {
        [string] $estate = Join-Path $TestDrive 'sending'
        New-Item -ItemType Directory -Path (Join-Path $estate 'src') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $estate 'src/lib.rs') -Value 'one'

        [hashtable] $given = @{ Estate = $estate; Computer = $script:Computer }

        InModuleScope Xmip -Parameters $given {
            param($Estate, $Computer)

            $script:Held = 'none'
            Mock Get-XmipEstateLayout { [pscustomobject]@{ Root = $Estate } }
            Mock Copy-XmipTestComputerFile { }
            Mock Invoke-XmipTestComputerShell {
                [pscustomobject]@{ Code = 0; Out = @($script:Held); Err = @() }
            }

            Send-XmipTestComputerEstate -Computer $Computer 6>$null
            Should -Invoke Copy-XmipTestComputerFile -Times 1 -Exactly -ParameterFilter {
                $Name -contains 'send.tar' -and $Name -contains 'gone.txt'
            }
            Should -Invoke Invoke-XmipTestComputerShell -Times 1 -Exactly -ParameterFilter {
                $Asked -eq 'receive' -and $Given -eq 'whole'
            }

            $script:Held = 'held'
            [string] $said = Send-XmipTestComputerEstate -Computer $Computer 6>&1
            $said | Should -BeLike '*the difference to build1: 0 changed, 0 gone.*'
            Should -Invoke Invoke-XmipTestComputerShell -Times 1 -Exactly -ParameterFilter {
                $Asked -eq 'receive' -and $Given -eq 'difference'
            }

            # The mirror there is gone: everything again, never a difference
            # into nothing.
            $script:Held = 'none'
            Send-XmipTestComputerEstate -Computer $Computer 6>$null
            Should -Invoke Invoke-XmipTestComputerShell -Times 2 -Exactly -ParameterFilter {
                $Asked -eq 'receive' -and $Given -eq 'whole'
            }
        }
    }
}

Describe 'Start, Get and Stop take -ComputerName, and nothing new is a cmdlet' {
    It 'is a parameter of the four test cmdlets' {
        foreach ($name in 'Start-XmipTest', 'Get-XmipTestStatus', 'Stop-XmipTest',
            'Get-XmipTestResult') {
            (Get-Command -Name $name).Parameters.Keys | Should -Contain 'ComputerName'
        }

        Get-Command -Module Xmip -Noun '*Computer*' | Should -BeNullOrEmpty
    }

    It 'refuses what does not run there before anything is sent' {
        Mock Send-XmipTestComputerEstate -ModuleName Xmip { }

        { Start-XmipTest -Suite Core.System -ComputerName build1 -ErrorAction Stop } |
            Should -Throw -ExpectedMessage ('*REFUSED. -ComputerName belong to Core.Estate and ' +
                'Core.Internal, not Core.System.*')
        { Start-XmipTest -Suite Core.Estate -Path . -ComputerName build1 -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*REFUSED. -Path names a folder of this computer*'
        { Start-XmipTest -Suite Core.Estate -Test Nope* -ComputerName build1 -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*REFUSED. No test matches Nope*'
        Should -Invoke Send-XmipTestComputerEstate -ModuleName Xmip -Times 0
    }

    It 'sends nothing for -WhatIf' {
        Mock Read-XmipTestComputer -ModuleName Xmip { $script:Computer }
        Mock Send-XmipTestComputerEstate -ModuleName Xmip { }
        Mock Invoke-XmipTestComputer -ModuleName Xmip { }

        Start-XmipTest -Suite Core.Estate -ComputerName build1 -WhatIf
        Stop-XmipTest -ComputerName build1 -Suite Core.Estate -WhatIf

        Should -Invoke Send-XmipTestComputerEstate -ModuleName Xmip -Times 0
        Should -Invoke Invoke-XmipTestComputer -ModuleName Xmip -Times 0
    }

    It 'starts the suite there through that computer''s own Start-XmipTest' {
        Mock Read-XmipTestComputer -ModuleName Xmip { $script:Computer }
        Mock Send-XmipTestComputerEstate -ModuleName Xmip { }
        Mock Invoke-XmipTestComputer -ModuleName Xmip { $script:FarRow }

        $run = Start-XmipTest -Suite Core.Estate -Test Toml -ComputerName build1 6>$null

        $run.PSObject.TypeNames[0] | Should -Be 'Xmip.TestStatus'
        $run.ComputerName | Should -Be 'build1'
        $run.Id | Should -Be 42
        Should -Invoke Send-XmipTestComputerEstate -ModuleName Xmip -Times 1 -Exactly
        Should -Invoke Invoke-XmipTestComputer -ModuleName Xmip -Times 1 -Exactly -ParameterFilter {
            $Command -eq 'Start-XmipTest' -and $Start -and $Parameter.Suite -eq 'Core.Estate' -and
                "$($Parameter.Test)" -eq 'Toml' -and -not $Parameter.ContainsKey('ComputerName')
        }
    }

    It 'reads and stops runs there, a run on the pipeline where it runs' {
        Mock Read-XmipTestComputer -ModuleName Xmip { $script:Computer }
        Mock Invoke-XmipTestComputer -ModuleName Xmip { $script:FarRow } -ParameterFilter {
            $Command -eq 'Get-XmipTestStatus'
        }
        Mock Invoke-XmipTestComputer -ModuleName Xmip { } -ParameterFilter {
            $Command -eq 'Stop-XmipTest'
        }

        $listed = @(Get-XmipTestStatus -ComputerName build1)
        $listed.Count | Should -Be 1
        $listed[0].ComputerName | Should -Be 'build1'
        Should -Invoke Invoke-XmipTestComputer -ModuleName Xmip -Times 1 -ParameterFilter {
            $Command -eq 'Get-XmipTestStatus' -and $AllowAbsent -and $Parameter.Cluster -eq '*'
        }

        Stop-XmipTest -ComputerName build1 -Suite Core.Estate -Confirm:$false
        Should -Invoke Invoke-XmipTestComputer -ModuleName Xmip -Times 1 -ParameterFilter {
            $Command -eq 'Stop-XmipTest' -and $Parameter.Suite -eq 'Core.Estate' -and
                $Parameter.Confirm -eq $false
        }

        $listed | Stop-XmipTest -Confirm:$false
        Should -Invoke Invoke-XmipTestComputer -ModuleName Xmip -Times 1 -ParameterFilter {
            $Command -eq 'Stop-XmipTest' -and "$($Parameter.Id)" -eq '42'
        }
    }

    It 'stops an id given with -ComputerName there, and never the process of that id here' {
        Mock Read-XmipTestComputer -ModuleName Xmip { $script:Computer }
        Mock Invoke-XmipTestComputer -ModuleName Xmip { }
        Mock Get-XmipTestStatus -ModuleName Xmip { }

        Stop-XmipTest -ComputerName build1 -Id $PID -Confirm:$false

        Should -Invoke Invoke-XmipTestComputer -ModuleName Xmip -Times 1 -Exactly -ParameterFilter {
            $Command -eq 'Stop-XmipTest' -and "$($Parameter.Id)" -eq "$PID"
        }
        Should -Invoke Get-XmipTestStatus -ModuleName Xmip -Times 0
    }
}

Describe 'What crosses to the computer and back' {
    It 'hands the parameters over as PowerShell serializes them, and runs the copy''s module' {
        InModuleScope Xmip {
            [hashtable] $given = @{ Suite = 'Core.Internal'; Test = [string[]] @('a', 'b') }
            [string] $script = New-XmipTestComputerCommand -Command Start-XmipTest -Parameter $given

            $script | Should -Match ([regex]::Escape('Import-Module -Name ./Xmip/Xmip.psd1'))
            $script | Should -Match ([regex]::Escape("& 'Start-XmipTest' @given"))
            [string] $quoted = "(?m)^\s+'([A-Za-z0-9+/=]+)'\)\)"
            [string] $packed = [regex]::Match($script, $quoted).Groups[1].Value
            [string] $text = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($packed))
            $back = [System.Management.Automation.PSSerializer]::Deserialize($text)

            $back.Suite | Should -Be 'Core.Internal'
            @($back.Test) | Should -Be @('a', 'b')

            # A start makes the copy ready to build first, RocksDB's library
            # compiled once as any clone's is; nothing else does.
            $script | Should -Not -Match 'Install-XmipTestComputerLibrary'
            New-XmipTestComputerCommand -Command Start-XmipTest -Parameter $given -Prepare |
                Should -Match 'Install-XmipTestComputerLibrary -Confirm:\$false'
            Mock Invoke-XmipTestComputerShell {
                [pscustomobject]@{ Code = 0; Out = @(); Err = @() }
            }
            Mock New-XmipTestComputerCommand { 'x' }
            $null = Invoke-XmipTestComputer -Computer ([pscustomobject]@{ Name = 'n' }) -Command (
                'Start-XmipTest') -Parameter @{} -Start
            Should -Invoke New-XmipTestComputerCommand -Times 1 -Exactly -ParameterFilter {
                $Prepare
            }
        }
    }

    It 'calls ssh in one place, and shows what is said there as it is said, but the answer' {
        InModuleScope Xmip -Parameters @{ Computer = $script:Computer } {
            param($Computer)

            Mock ssh { 'said there'; "$($script:XmipTestComputerAnswer)AAAA" }

            [type] $information = [System.Management.Automation.InformationRecord]
            [object[]] $said = @(
                Invoke-XmipTestComputerShell -Computer $Computer -Asked observe -Given 'Zm9v' 6>&1
            )
            @($said | Where-Object { $_ -is $information } | ForEach-Object { "$_" }) |
                Should -Be @('build1| said there')
            ($said | Where-Object { $_ -isnot $information }).Out.Count | Should -Be 2

            Should -Invoke ssh -Times 1 -Exactly -ParameterFilter {
                [string] $all = $args -join ' '
                $all -match '-i key -o BatchMode=yes' -and $all -match 'tester@build1\.example' -and
                    $all -match 'bash -c .+ xmip xmip-test observe 2 \.local-work Zm9v$'
            }
        }
    }

    It 'reads the answer back from what was said, and refuses in the computer''s words' {
        InModuleScope Xmip -Parameters @{ Computer = $script:Computer } {
            param($Computer)

            [string] $sent = [System.Management.Automation.PSSerializer]::Serialize(
                @([pscustomobject]@{ Id = 7 }), 4)
            [string] $line = $script:XmipTestComputerAnswer +
                [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($sent))
            [hashtable] $read = @{
                Computer = $Computer; Doing = 'run'
                Answer   = [pscustomobject]@{ Code = 0; Out = @('said there', $line); Err = @() }
            }

            @(Read-XmipTestComputerAnswer @read)[0].Id | Should -Be 7

            $read.Answer = [pscustomobject]@{
                Code = 1; Out = @(); Err = @('REFUSED. No test matches Nope*.')
            }
            { Read-XmipTestComputerAnswer @read } |
                Should -Throw -ExpectedMessage 'REFUSED. No test matches Nope*'
        }
    }

    It 'runs pwsh there by -Command, in a build slot it waits for, saying so before it starts' {
        # 2026-11-23: pwsh given -EncodedCommand also writes what it shows to
        # stderr as CLIXML, and this side's PowerShell showed every line twice.
        # A wait for a slot writes a line before it starts anything, and a
        # line its console is gone for cannot be written: the wait ends there.
        InModuleScope Xmip {
            [string] $shell = $script:XmipTestComputerShell

            $shell | Should -Not -Match 'EncodedCommand\s+"'
            $shell | Should -Match 'pwsh -NoProfile -NonInteractive -Command "\$run"'
            $shell | Should -Match 'flock -n 9'
            $shell | Should -Match 'slot\$n\.lock'
            $shell | Should -Match 'Waiting for a build slot'
            $shell | Should -Match 'REFUSED\. A run is going on in \$tree' -Because (
                'a start never rewrites a copy a run works in')
            $shell | Should -Match ('(?s)echo "Build slot \$taken of \$slots taken\."\s*\n' +
                'exec setsid --wait pwsh')
        }
    }
}

Describe 'Core.Internal is the internal tests of named modules' {
    It 'is started by its name alone, and knows the modules a landing names' {
        InModuleScope Xmip {
            $internal = Get-XmipTestSuite | Where-Object Name -EQ 'Core.Internal'
            $internal.Kind | Should -Be 'internal'
            $internal.ByName | Should -BeTrue

            [string[]] $known = @(Get-XmipInternalTest -RepositoryRoot (Get-XmipRepositoryRoot))
            $known | Should -Contain '.'
            $known | Should -Contain 'module/foundation/core'
        }

        { Start-XmipTest -Suite Core.Internal -Test 'nowhere/*' -WhatIf -ErrorAction Stop } |
            Should -Throw -ExpectedMessage '*REFUSED. No test matches nowhere/*'
    }

    It 'verifies the crates named alone: not the root crate, not the timing programs' {
        InModuleScope Xmip -Parameters @{ Root = $TestDrive } {
            param($Root)

            $script:Ran = [System.Collections.Generic.List[string]]::new()
            Mock Get-XmipWorkspacePlan { [pscustomobject]@{ Member = @('module/one') } }
            Mock Read-XmipModuleManifest { [pscustomobject]@{ Package = "pkg-$Module" } }
            Mock Test-XmipDeclaredFeature { $false }
            Mock Push-Location { }
            Mock Pop-Location { }
            Mock Invoke-XmipTool {
                $script:Ran.Add($Argument -join ' ')
                [pscustomobject]@{ Passed = $true; Said = @() }
            }

            Test-XmipRustChange -RepositoryRoot $Root -Module 'module/one' -Alone 6>$null

            "$($script:Ran)" | Should -Not -Match 'measured'
            "$($script:Ran)" | Should -Not -Match 'pkg-\.'
            $script:Ran | Should -Contain 'fmt --check -p pkg-module/one'
            $script:Ran | Should -Contain 'test'
        }
    }

    It 'writes its verdict where an estate run is read, as its own suite' {
        [string] $area = Join-Path $TestDrive 'internal'
        New-Item -ItemType Directory -Path $area | Out-Null

        InModuleScope Xmip -Parameters @{ Area = $area; Root = $script:Root } {
            param($Area, $Root)

            [hashtable] $run = @{
                Record = Join-Path $Area 'estate-20261123-120000-000.toml'
                Suite  = 'Core.Internal'; Path = $Root; Test = @('module/one')
                Log    = Join-Path $Area 'estate-20261123-120000-000.log'
            }
            $stopped = [pscustomobject]@{ Verified = @(); Skipped = @(); Failed = 'module/one' }
            Complete-XmipInternalRun @run -Verdict $stopped -Started (Get-Date)

            $listed = Get-XmipEstateRun -Path $Area
            $listed.Kind | Should -Be 'internal'
            $listed.State | Should -Be 'FAILED'

            $failed = @(Get-XmipEstateResult -Path $Area -Suite Core.Internal)
            $failed[0].Test | Should -Be 'module/one'
            $failed[0].Message | Should -BeLike 'module/one did not verify*'
            { Get-XmipEstateResult -Path $Area -ErrorAction Stop } |
                Should -Throw -ExpectedMessage '*No run of Core.Estate is recorded*'
        }
    }
}

AfterAll {
    $env:XMIP_AUDIT_DIRECTORY = $script:AuditBefore
}
