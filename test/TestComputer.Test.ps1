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
        # ssh and scp would read either as an option and run what it names.
        Set-Content -LiteralPath (Join-Path $script:Area 'dash.toml') -Value @(
            'host = "h"', 'user = "-oProxyCommand=touch x"', "key = `"$key`"")
        Set-Content -LiteralPath (Join-Path $script:Area 'far.toml') -Value @(
            'host = "-oProxyCommand=touch x"', 'user = "u"', "key = `"$key`"")

        InModuleScope Xmip -Parameters @{ Area = $script:Area } {
            param($Area)

            Mock Get-XmipEstateLayout { [pscustomobject]@{ TestComputer = $Area } }

            $read = Read-XmipTestComputer -Name build1
            $read.Folder | Should -Be 'xmip-test'
            $read.Slots | Should -Be 2
            $read.State | Should -Be (Join-Path $Area 'build1')

            { Read-XmipTestComputer -Name up } |
                Should -Throw -ExpectedMessage "*REFUSED*folder = '../elsewhere'*"
            { Read-XmipTestComputer -Name dash } |
                Should -Throw -ExpectedMessage "*REFUSED*user = '-oProxyCommand=touch x'*"
            { Read-XmipTestComputer -Name far } |
                Should -Throw -ExpectedMessage "*REFUSED*host = '-oProxyCommand=touch x'*"
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

    It 'sends what Git would hold, and build output never, by what it holds' {
        # 2026-11-24: the walk sent whatever it found, a clone's own settings
        # and every ignored Cargo.lock and log among it (open problem 145).
        # deploy/profile/target is source, and a name rule once lost it; a
        # repository's own .git never travels.
        [string] $estate = Join-Path $TestDrive 'walked'
        [string] $one = Join-Path $estate 'module/one'

        foreach ($file in 'src/lib.rs', 'new.rs', 'ignored.txt', 'logs/a.log', 'local/x.json',
            'deploy/profile/target/p.toml', 'out/target/x.o', 'out/target/CACHEDIR.TAG',
            'Cargo.lock', 'module/one/Cargo.toml', 'module/one/Cargo.lock',
            'module/one/extra.rs', 'module/one/secret.env') {
            [string] $full = Join-Path $estate $file
            New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
            Set-Content -LiteralPath $full -Value 'x'
        }

        # The workspace's lock is ignored and still sent: the computer builds
        # what this one resolved. A submodule's is ignored and never read.
        Set-Content -LiteralPath (Join-Path $estate '.gitignore') -Value 'ignored.txt', 'logs/',
            'Cargo.lock'
        Set-Content -LiteralPath (Join-Path $one '.gitignore') -Value '*.env', 'Cargo.lock'
        & git -C $estate init -q 2>$null
        & git -C $one init -q 2>$null
        # This clone's own exclude, which no copy of the estate carries.
        Add-Content -LiteralPath (Join-Path $estate '.git/info/exclude') -Value 'local/'
        & git -C $estate add .gitignore src/lib.rs deploy/profile/target/p.toml 2>$null
        & git -C $one add .gitignore Cargo.toml 2>$null

        InModuleScope Xmip -Parameters @{ Estate = $estate } {
            param($Estate)

            [string[]] $paths = @(Get-XmipEstateSent -Root $Estate | ForEach-Object {
                    $_.Split("`t")[0] })

            $paths | Should -Be @('.gitignore', 'Cargo.lock', 'deploy/profile/target/p.toml',
                'module/one/.gitignore', 'module/one/Cargo.toml', 'module/one/extra.rs',
                'new.rs', 'src/lib.rs')
        }
    }

    It 'sends everything once, then only the difference, and everything where the mirror went' {
        [string] $estate = Join-Path $TestDrive 'sending'
        New-Item -ItemType Directory -Path (Join-Path $estate 'src') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $estate 'src/lib.rs') -Value 'one'
        & git -C $estate init -q 2>$null

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

    It 'sends everything again after a receive that failed, and keeps the list a refusal left' {
        # 2026-11-24: a receive that failed left the list of what was sent
        # as it was, so every later send computed the same difference and
        # failed the same way.
        [string] $estate = Join-Path $TestDrive 'failing'
        New-Item -ItemType Directory -Path (Join-Path $estate 'src') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $estate 'src/lib.rs') -Value 'one'
        & git -C $estate init -q 2>$null
        $computer = $script:Computer.PSObject.Copy()
        $computer.State = Join-Path $TestDrive 'state-failing'

        InModuleScope Xmip -Parameters @{ Estate = $estate; Computer = $computer } {
            param($Estate, $Computer)

            $script:Code = 0
            Mock Get-XmipEstateLayout { [pscustomobject]@{ Root = $Estate } }
            Mock Copy-XmipTestComputerFile { }
            Mock Invoke-XmipTestComputerShell {
                if ($Asked -eq 'probe') {
                    return [pscustomobject]@{ Code = 0; Out = @('held'); Err = @() }
                }

                [string] $said = if ($script:Code -eq $script:XmipTestComputerBusy) {
                    'REFUSED. A run is going on there.'
                }
                else { 'tar: p: Cannot open: Not a directory' }
                [pscustomobject]@{ Code = $script:Code; Out = @(); Err = @($said) }
            }
            [string] $listed = Join-Path $Computer.State 'sent.tsv'

            Send-XmipTestComputerEstate -Computer $Computer 6>$null
            $listed | Should -Exist

            $script:Code = 2
            { Send-XmipTestComputerEstate -Computer $Computer 6>$null } |
                Should -Throw -ExpectedMessage '*FAILED*Not a directory*'
            $listed | Should -Not -Exist

            $script:Code = 0
            Send-XmipTestComputerEstate -Computer $Computer 6>$null
            Should -Invoke Invoke-XmipTestComputerShell -Times 2 -Exactly -ParameterFilter {
                $Asked -eq 'receive' -and $Given -eq 'whole'
            }

            $script:Code = $script:XmipTestComputerBusy
            { Send-XmipTestComputerEstate -Computer $Computer 6>$null } |
                Should -Throw -ExpectedMessage 'REFUSED. A run is going on there.'
            $listed | Should -Exist -Because 'a refused receive changed nothing there'
        }
    }

    It 'takes a path that turned from a file into a folder, or back; a run holds the copy' -Skip:(
        -not ($IsLinux -and (Get-Command -Name flock -ErrorAction Ignore))) {
        # The computer's own shell, run here, where this is Linux.
        [string] $far = Join-Path $TestDrive 'far'
        [string] $folder = Join-Path $far 'w'
        [string] $mirror = Join-Path $folder 'mirror'
        [string] $shell = InModuleScope Xmip { $script:XmipTestComputerShell.Replace("`r`n", "`n") }
        [scriptblock] $receive = {
            param([string] $How)
            [string] $before = $env:HOME
            $env:HOME = $far

            try {
                & bash -c $shell xmip w receive 2 .local-work $How 2>&1 | Out-Null
                $LASTEXITCODE
            }
            finally {
                $env:HOME = $before
            }
        }
        [scriptblock] $pack = {
            param([string] $From, [string[]] $Path, [string[]] $Gone)
            & tar -cf (Join-Path $folder 'send.tar') -C $From @Path
            [string] $text = if ($Gone.Count -gt 0) { ($Gone -join "`n") + "`n" } else { '' }
            Set-Content -LiteralPath (Join-Path $folder 'gone.txt') -Value $text -NoNewline
        }

        [string] $first = Join-Path $TestDrive 'first'
        New-Item -ItemType Directory -Path (Join-Path $first 'q'), $folder -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $first 'p') -Value 'file'
        Set-Content -LiteralPath (Join-Path $first 'q/x') -Value 'in a folder'
        & $pack $first @('p', 'q/x') @()
        & $receive 'whole' | Should -Be 0

        [string] $second = Join-Path $TestDrive 'second'
        New-Item -ItemType Directory -Path (Join-Path $second 'p') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $second 'p/a') -Value 'now a folder'
        Set-Content -LiteralPath (Join-Path $second 'q') -Value 'now a file'
        & $pack $second @('p/a', 'q') @('p', 'q/x')
        & $receive 'difference' | Should -Be 0
        Join-Path $mirror 'p/a' | Should -Exist
        (Get-Item -LiteralPath (Join-Path $mirror 'q')).PSIsContainer | Should -BeFalse

        # A run holds the copy's lock: a send is refused before anything moves.
        [string] $held = Join-Path $folder 'held'
        [int] $busy = InModuleScope Xmip { $script:XmipTestComputerBusy }
        $holding = [System.Diagnostics.ProcessStartInfo]::new('bash')
        $holding.ArgumentList.Add('-c')
        $holding.ArgumentList.Add(
            "exec 8>'$folder/tree.lock'; flock -n 8 && touch '$held' && sleep 30")
        $holder = [System.Diagnostics.Process]::Start($holding)

        try {
            for ([int] $wait = 0; $wait -lt 50 -and -not (Test-Path -LiteralPath $held); $wait++) {
                Start-Sleep -Milliseconds 100
            }

            & $pack $first @('p') @()
            & $receive 'difference' | Should -Be $busy
            Join-Path $mirror 'p/a' | Should -Exist -Because 'a refused receive moves nothing'
        }
        finally {
            $holder.Kill($true)
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

    It 'says in its help which suites run there and which are started by name alone' {
        # 2026-11-24: the help said the first two suites it listed ran there,
        # Core.System among them, and named Core.Demo alone as started by name.
        [string] $help = (Get-Help -Name Start-XmipTest -Full | Out-String) -replace '\s+', ' '
        $table = InModuleScope Xmip {
            [pscustomobject]@{
                Alone = @(Get-XmipTestSuite | Where-Object ByName | ForEach-Object Name)
                There = @(Get-XmipTestSuite | Where-Object {
                        $script:XmipSuiteSwitch[$_.Kind] -contains 'ComputerName'
                    } | ForEach-Object Name)
            }
        }
        [scriptblock] $listed = {
            param([string[]] $Name)
            (@($Name | Select-Object -SkipLast 1) -join ', ') + " and $($Name[-1])"
        }

        $help | Should -Match ([regex]::Escape(
                "$(& $listed $table.There) run on a Linux test computer by -ComputerName"))
        $help | Should -Match ([regex]::Escape(
                "started by their name alone, $(& $listed $table.Alone);"))
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

            # A computer's words reach this console with no control character
            # in them: no title, link or clipboard write is obeyed here.
            Mock ssh { "said `e]52;c;Zm9v`athere"; "$($script:XmipTestComputerAnswer)AAAA" }

            [type] $information = [System.Management.Automation.InformationRecord]
            [object[]] $said = @(
                Invoke-XmipTestComputerShell -Computer $Computer -Asked observe -Given 'Zm9v' 6>&1
            )
            @($said | Where-Object { $_ -is $information } | ForEach-Object { "$_" }) |
                Should -Be @('build1| said ]52;c;Zm9vthere')
            ($said | Where-Object { $_ -isnot $information }).Out.Count | Should -Be 2

            # Nothing after `--` is an option, whatever the account begins with.
            Should -Invoke ssh -Times 1 -Exactly -ParameterFilter {
                [string] $all = $args -join ' '
                $all -match '-i key -o BatchMode=yes .+ -- tester@build1\.example' -and
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
            [string] $shell = $script:XmipTestComputerShell.Replace("`r`n", "`n")

            $shell | Should -Not -Match 'EncodedCommand\s+"'
            $shell | Should -Match 'pwsh -NoProfile -NonInteractive -Command "\$run"'
            $shell | Should -Match 'flock -n 9'
            $shell | Should -Match 'slot\$n\.lock'
            $shell | Should -Match 'Waiting for a build slot'
            $shell | Should -Match ('(?s)echo "Build slot \$taken of \$slots taken\."\s*\n' +
                'exec setsid --wait pwsh')

            # One run in a copy at a time, by the folder's lock, which the run
            # holds as it holds its slot: a second start and a send while it
            # runs are refused; no walk of every process's folder.
            $shell | Should -Match 'REFUSED\. A run is going on in \$tree' -Because (
                'a start never rewrites a copy a run works in')
            $shell | Should -Match 'exec 8>"\$folder/tree\.lock"\s+flock -n 8'
            $shell | Should -Not -Match 'readlink'
            foreach ($asked in 'probe', 'receive') {
                $shell | Should -Match "(?s)\n$asked\)\n(.*?\n)?  locked\n.*?;;"
            }
            $shell | Should -Match '(?m)^locked\nmkdir -p "\$tree"\nrsync'

            # A computer that is not Linux is refused by name at its probe.
            $shell | Should -Match 'lacks what a test computer needs'
            foreach ($tool in 'flock', 'setsid', 'rsync', 'git', 'pwsh') {
                $shell | Should -Match "for tool in .*\b$tool\b"
            }

            # What is gone goes first, then every empty folder, then the new.
            [int] $gone = $shell.IndexOf('rm -f -- < "$folder/gone.txt"')
            [int] $empty = $shell.IndexOf('-type d -empty -delete')
            [int] $extract = $shell.IndexOf('tar -xf "$folder/send.tar"')
            $gone | Should -BeGreaterThan 0
            $empty | Should -BeGreaterThan $gone
            $extract | Should -BeGreaterThan $empty
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

    It 'verifies the crates named alone, one cargo for each mode over them, then each built alone' {
        # 2026-11-24: a test, a lint and a test with every feature for each
        # crate, each cargo loading the whole workspace (open problem 147). A
        # crate built only through another's features is caught by its own
        # check. Not the root crate, not the timing programs.
        InModuleScope Xmip -Parameters @{ Root = $TestDrive } {
            param($Root)

            $script:Ran = [System.Collections.Generic.List[string]]::new()
            Mock Get-XmipWorkspacePlan {
                [pscustomobject]@{ Member = @('module/one', 'module/two') }
            }
            Mock Read-XmipModuleManifest { [pscustomobject]@{ Package = "pkg-$Module" } }
            Mock Test-XmipDeclaredFeature { $true }
            Mock Push-Location { }
            Mock Pop-Location { }
            Mock Invoke-XmipTool {
                $script:Ran.Add($Argument -join ' ')
                [pscustomobject]@{ Passed = $true; Said = @() }
            }

            [string[]] $named = @('module/one', 'module/two')
            Test-XmipRustChange -RepositoryRoot $Root -Module $named -Alone 6>$null

            [string] $both = '-p pkg-module/one -p pkg-module/two'
            $script:Ran | Should -Be @(
                "fmt --check $both"
                "clippy --all-targets --all-features --keep-going $both"
                "test --no-fail-fast $both"
                "clippy --all-targets --keep-going $both"
                "test --all-features --no-fail-fast $both"
                'check --all-targets -p pkg-module/one'
                'check --all-targets -p pkg-module/two'
            )
        }
    }

    It 'names each crate and test that failed, and runs every step to its end' {
        # 2026-11-24: a failed run said "Rust" with 0 passed (open problem 146).
        InModuleScope Xmip -Parameters @{ Root = $TestDrive } {
            param($Root)

            $script:Ran = [System.Collections.Generic.List[string]]::new()
            Mock Get-XmipWorkspacePlan {
                [pscustomobject]@{ Member = @('module/one', 'module/two') }
            }
            Mock Read-XmipModuleManifest {
                [pscustomobject]@{ Package = "pkg-$($Module.Split('/')[-1])" }
            }
            Mock Test-XmipDeclaredFeature { $false }
            Mock Push-Location { }
            Mock Pop-Location { }
            Mock Invoke-XmipTool {
                $script:Ran.Add($Argument -join ' ')

                if ($Argument[0] -ne 'test') {
                    return [pscustomobject]@{ Passed = $true; Said = @() }
                }

                [string[]] $said = @(
                    '     Running unittests src/lib.rs (target/debug/deps/pkg_two-0a1b2c3d4e5f6a7b)'
                    'test tests::adds_up ... FAILED'
                    '---- tests::adds_up stdout ----'
                    "thread 'tests::adds_up' (7) panicked at src/lib.rs:10:9:"
                    'assertion `left == right` failed: two is not three'
                    'failures:'
                    'error: test failed, to rerun pass `-p pkg-two --lib`'
                )
                [pscustomobject]@{
                    Passed = $false; Said = @(); Telling = @()
                    Failure = @(Get-XmipToolFailure -Tool cargo -Line $said)
                }
            }

            [string[]] $named = @('module/one', 'module/two')
            [object[]] $failed = @(
                Test-XmipRustChange -RepositoryRoot $Root -Module $named -Alone 6>$null
            )

            $failed.Count | Should -Be 1
            $failed[0].Module | Should -Be 'module/two'
            $failed[0].Test | Should -Be 'tests::adds_up'
            $failed[0].Message | Should -Be ('the tests: panicked at src/lib.rs:10:9: ' +
                'assertion `left == right` failed: two is not three')
            $script:Ran | Should -Contain 'check --all-targets -p pkg-two' -Because (
                'Core.Internal runs every step to its end')
        }
    }

    It 'reads what cargo and dotnet said failed: the crate or project, the test and why' {
        # Cargo's own words, 2026-11-24, warnings denied as the estate's
        # .cargo denies them.
        InModuleScope Xmip -Parameters @{ Root = $TestDrive } {
            param($Root)

            [string[]] $built = @(
                'warning: unused variable: `unused`'
                ' --> a/src/lib.rs:2:9'
                'error[E0425]: cannot find value `missing_value` in this scope'
                ' --> b/src/lib.rs:2:5'
                'error: `probe-a` (lib) generated 1 warning (run `cargo fix --lib -p probe-a`)'
                'error: could not compile `probe-b` (lib) due to 1 previous error'
                'Diff in \\?\D:\x\c\src\lib.rs:1:'
            )
            [object[]] $read = @(Get-XmipToolFailure -Tool cargo -Line $built)

            $read.Count | Should -Be 3
            $read[0].Package | Should -Be 'probe-a'
            $read[0].Message | Should -Be ('warns, and a warning fails the build: warning: ' +
                'unused variable: `unused` at a/src/lib.rs:2:9')
            $read[1].Package | Should -Be 'probe-b'
            $read[1].Message | Should -Be ('error[E0425]: cannot find value `missing_value` in ' +
                'this scope at b/src/lib.rs:2:5')
            $read[2].Path | Should -Be '\\?\D:\x\c\src\lib.rs'

            # A failure that names a file is read back to the crate holding it.
            [System.Collections.Specialized.OrderedDictionary] $package = [ordered]@{
                'module/one' = 'pkg-one'; 'module/one/two' = 'pkg-two'
            }
            Find-XmipFailedCrate -RepositoryRoot $Root -Package $package -Path (
                'module/one/two/src/lib.rs') | Should -Be 'module/one/two'
            Find-XmipFailedCrate -RepositoryRoot $Root -Package $package -Named 'pkg_one' |
                Should -Be 'module/one'

            [string[]] $tested = @(
                '  D:\x\Foo.cs(12,5): error CS0103: The name ''x'' does not exist [D:\x\Foo.csproj]'
                '  Failed Xmip.Surface.Test.ReadsIt [12 ms]'
                '  Error Message:'
                '   Assert.Equal() Failure: Values differ'
            )
            [object[]] $read = @(Get-XmipToolFailure -Tool dotnet -Line $tested)

            $read.Count | Should -Be 2
            $read[0].Package | Should -Be 'Foo'
            $read[0].Message | Should -BeLike 'error CS0103: *at D:\x\Foo.cs(12,5)'
            $read[1].Test | Should -Be 'Xmip.Surface.Test.ReadsIt'
            $read[1].Message | Should -Be 'Assert.Equal() Failure: Values differ'

            # What a part's pwsh returned: a string names a module; a failure
            # crosses whole; a passing $true is no failure.
            [object[]] $parts = @(ConvertTo-XmipPartFailure -Said @(
                    'module/x', $true,
                    [pscustomobject]@{ Module = 'm'; Test = 't'; Message = 'why' }))
            @($parts | ForEach-Object { "$($_.Module)|$($_.Test)|$($_.Message)" }) |
                Should -Be @('module/x||', 'm|t|why')
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

    It 'records each crate and test that failed with why, as Get-XmipTestResult reads it there' {
        # The record is what -ComputerName brings back: the words that say
        # why are in it, the part's log stays on the computer that ran it.
        [string] $area = Join-Path $TestDrive 'internal-named'
        New-Item -ItemType Directory -Path $area | Out-Null

        InModuleScope Xmip -Parameters @{ Area = $area; Root = $script:Root } {
            param($Area, $Root)

            [hashtable] $run = @{
                Record = Join-Path $Area 'estate-20261124-120000-000.toml'
                Suite  = 'Core.Internal'; Path = $Root; Test = @('module/one', 'module/two')
                Log    = Join-Path $Area 'estate-20261124-120000-000.log'
            }
            $verdict = [pscustomobject]@{
                Verified = @('module/one'); Skipped = @(); Failed = 'module/two'
                Failure  = @([pscustomobject]@{
                        Module = 'module/two'; Test = 'tests::adds_up'; Part = 'Rust'
                        Message = 'the tests: panicked at src/lib.rs:10:9: two is not three'
                        Log = '/far/part-rust.log'
                    })
            }
            Complete-XmipInternalRun @run -Verdict $verdict -Started (Get-Date)

            (Get-XmipEstateRun -Path $Area).Tally | Should -BeLike '1 passed, 1 failed, 0 skipped*'
            $failed = @(Get-XmipEstateResult -Path $Area -Suite Core.Internal)
            $failed.Count | Should -Be 1
            $failed[0].Test | Should -Be 'module/two'
            $failed[0].Name | Should -Be 'tests::adds_up'
            $failed[0].Message |
                Should -BeLike '*two is not three (Rust; its log: /far/part-rust.log)'
        }
    }

    It 'verifies a module''s own .NET projects, never those of a module nested in it' {
        # 2026-11-24: the root, which holds no project, found every module's,
        # and the whole suite built and tested each twice (review finding M8).
        [string] $estate = Join-Path $TestDrive 'projects'

        foreach ($file in 'own/Own.csproj', 'nested/.git', 'nested/src/Nested.csproj') {
            [string] $full = Join-Path $estate $file
            New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
            Set-Content -LiteralPath $full -Value 'x'
        }

        InModuleScope Xmip -Parameters @{ Estate = $estate } {
            param($Estate)

            @(Find-XmipModuleProject -Path $Estate | ForEach-Object Name) |
                Should -Be @('Own.csproj')
            @(Find-XmipModuleProject -Path (Join-Path $Estate 'nested') | ForEach-Object Name) |
                Should -Be @('Nested.csproj')
        }
    }

    It 'writes a value into a detached run''s script as a literal, whatever quote it holds' {
        # PowerShell ends a single-quoted string at four quotes besides the
        # ASCII apostrophe (the review of 2026-11-24).
        InModuleScope Xmip {
            [string] $value = "a$([char] 0x2019); Write-Output 'run' $([char] 0x2018)b"
            [string] $literal = ConvertTo-XmipLiteral -Text $value

            & ([scriptblock]::Create($literal)) | Should -Be $value
        }
    }
}

AfterAll {
    $env:XMIP_AUDIT_DIRECTORY = $script:AuditBefore
}
