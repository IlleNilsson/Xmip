#requires -PSEdition Core
#requires -Version 7.7.0

<#
    Deploy-XmipEnvironment (Xmip/Deploy-XmipEnvironment.ps1) without a
    hypervisor: what the one cluster file makes of both technologies
    (ADR-0015, amendment 2026-11-25).

    - A technology with no template for the hypervisor is refused; a Linux
      host refuses the Windows machines, naming why; Ansible on Windows is
      refused, naming the command to run in WSL, which carries the Windows
      host's kind; an unelevated run on Windows is refused, naming the
      elevated console; a second run of an environment is refused while one
      holds its private state, before it writes anything there.
    - msdsc installs one machine at a time: the next machine's first set
      comes only once the one before is in its desired state.
    - Each node is given the environment template's machine.dsc.yaml, with
      every parameter it declares and has no default for, its machine's
      family, every placed node and its family's package; every
      hypervisor's machine document is given what the answer medium reads,
      the host key among it, and the machine's description; the names step
      is there only where a machine is the network's DNS server.
    - A run that applies records what it made, deployed.toml, which
      Read-XmipDeployedEnvironment reads back; a run that only tests records
      nothing.
    - Ansible's inventory carries the same mapping as the msdsc steps, from
      the same file, and reaches each AlmaLinux machine with the
      environment's key and known_hosts, checked strictly, and its own
      Python; every group is written, an empty one too, and the tasks read
      a machine's facts through ansible_facts alone. Under --check every
      read runs and every change says it would, and a host that would
      change, or is not reached, is not in its desired state. firewalld's
      service is made permanent alone and the running firewall asked and
      reloaded; the package's headers are compared before it is upgraded;
      Ansible stages in a folder of its own.
    - The private state: the technology that made the environment, the
      other one refused; the environment's own SSH key, with no passphrase
      and readable by this account alone, a host key per AlmaLinux machine,
      known_hosts holding each by its name and address, each key kept from
      one run to the next; and on Windows the Administrator secret, made
      once.
    - No task of the Ansible set writes a network, pool, domain or kickstart
      of its own: deploy/dsc/machine does (test/DeployMachine.Test.ps1).

    What this host gives, and the machine list, are test/DeployHost.Test.ps1.
    The machines themselves are proved by running the command:
    deploy/dsc/README.md.

    Style: doc/governance/powershell-style.md
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    [string] $script:Cluster = (Get-XmipTestCluster).Name

    # The Reference Environment with what its machines need given, in a
    # folder of its own; -Linux all AlmaLinux, as any host makes it.
    function New-Environment {
        param(
            [string] $Technology = 'msdsc',
            [switch] $Linux
        )

        [string] $folder = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        return New-XmipTestEnvironment -Folder $folder -Technology $Technology -Linux:$Linux
    }

    # The nodes an environment places, in the order the node steps take them:
    # a name is the cluster file's, never the test's (ADR-0056, amendment
    # 2026-10-03).
    function Get-PlacedNode {
        param([hashtable] $Environment)

        @((Read-XmipTestEnvironment -Environment $Environment -Run ([string] $TestDrive)).Nodes |
                ForEach-Object { $_.node })
    }

    # Deploy-XmipEnvironment run over -Environment with every host step a
    # stand-in, each step answered by -Answer, given the step, the operation,
    # its round and -Value; the steps asked, in order.
    function Invoke-Deploy {
        param(
            [hashtable] $Environment,
            [scriptblock] $Answer = {
                param($Step)
                @{ Step = $Step.Name; InDesiredState = $true; Seconds = 0 }
            },
            [hashtable] $Value = @{},
            [switch] $WhatIf
        )

        [hashtable] $given = @{ Environment = $Environment; Answer = $Answer; Value = $Value
            WhatIf = $WhatIf.IsPresent; Cluster = $script:Cluster }
        return @(InModuleScope Xmip -Parameters $given {
                param($Environment, $Answer, $Value, $WhatIf, $Cluster)
                $script:Called = [Collections.Generic.List[string]]::new()
                $script:Rounds = @{}
                $script:Facts = $Environment.Facts
                $script:Answer = $Answer
                $script:Value = $Value
                Mock Get-XmipDeployRunFolder { [string] $TestDrive }
                Mock Get-XmipDeployStateFolder { [string] $TestDrive }
                Mock Get-XmipDeployHost { $script:Facts }
                Mock Write-XmipDeployHost { }
                Mock Test-XmipDeployElevated { $true }
                Mock Initialize-XmipDeployState {
                    @{ Folder = [string] $TestDrive; Key = 'k'; KnownHosts = 'h'; HostKey = @{} } }
                Mock Initialize-XmipDeployIdentity { }
                Mock Start-Sleep { }
                Mock Write-XmipDeployLine { }
                Mock Invoke-XmipDeployStep {
                    $script:Called.Add("$($Step.Name) $Operation")
                    $script:Rounds[$Step.Name] = 1 + [int] $script:Rounds[$Step.Name]
                    & $script:Answer $Step $Operation $script:Rounds[$Step.Name] $script:Value
                }
                Deploy-XmipEnvironment -Path $Environment.File -Cluster $Cluster -WhatIf:$WhatIf |
                    Out-Null
                $script:Called
            })
    }

    # The private state the module makes, in a folder of the test's own.
    function Initialize-State {
        param(
            [hashtable] $Environment,
            [string] $Folder,
            [string] $Technology = 'msdsc',
            [switch] $Record
        )

        [hashtable] $read = Read-XmipTestEnvironment -Environment $Environment -Run $Folder
        return & (Get-Module -Name Xmip) {
            param($Read, $Folder, $Technology, $Record)
            [IO.FileStream] $held = Lock-XmipDeployState -Folder $Folder
            try {
                Initialize-XmipDeployState -Read $Read -Folder $Folder -Technology (
                    $Technology) -Record:$Record
            }
            finally {
                $held.Dispose()
            }
        } $read $Folder $Technology $Record.IsPresent
    }

    # The tasks of an Ansible task file, those in a block too.
    function Get-AnsibleTask {
        param([string] $Path)

        foreach ($task in @(Read-XmipTestYaml -Path $Path)) {
            $task
            if ($task.Contains('block')) {
                @($task['block'])
            }
        }
    }
}

Describe 'The cluster file''s environment' {
    It 'refuses a hypervisor with no template in the technology it names' {
        $made = New-Environment -Technology 'ansible'
        $made.Hypervisor = 'nothing'
        { Read-XmipTestEnvironment -Environment $made -Run ([string] $TestDrive) } |
            Should -Throw '*ansible has no template*nothing*'
    }

    It 'refuses the Windows machines on a Linux host, naming why' {
        $made = New-XmipTestEnvironment -Folder (Join-Path $TestDrive 'linux') -Hypervisor 'libvirt'
        { Read-XmipTestEnvironment -Environment $made -Run ([string] $TestDrive) } |
            Should -Throw '*no Windows machine yet, XMIP-DC01*third amendment of 2026-11-22*'
    }

    It 'refuses Ansible on Windows, naming the WSL command with the host''s kind' -Skip:(
        -not $IsWindows) {
        $made = New-Environment -Technology 'ansible'
        [hashtable] $asked = @{ Path = $made.File; Cluster = $script:Cluster
            Technology = 'ansible'; WindowsHost = 'host'; WhatIf = $true }
        { Deploy-XmipEnvironment @asked } |
            Should -Throw (
                '*wsl.exe -- pwsh*-Technology ansible -Hypervisor hyperv -WindowsHost host*')
    }

    It 'refuses an unelevated run on Windows, naming the elevated console' -Skip:(-not $IsWindows) {
        $made = New-Environment -Linux
        InModuleScope Xmip -Parameters @{ File = $made.File; Cluster = $script:Cluster } {
            param($File, $Cluster)
            Mock Test-XmipDeployElevated { $false }
            Mock Lock-XmipDeployState { throw 'the state is not to be reached' }
            { Deploy-XmipEnvironment -Path $File -Cluster $Cluster -WhatIf } |
                Should -Throw '*elevated Xmip PowerShell Console*'
        }
    }

    It 'refuses a second run of the environment while one runs, before any step' {
        $made = New-Environment -Linux
        [string[]] $calls = @(InModuleScope Xmip -Parameters @{ Made = $made
                Cluster = $script:Cluster } {
                param($Made, $Cluster)
                $script:Called = [Collections.Generic.List[string]]::new()
                $script:Facts = $Made.Facts
                Mock Get-XmipDeployRunFolder { [string] $TestDrive }
                Mock Get-XmipDeployStateFolder { [string] $TestDrive }
                Mock Get-XmipDeployHost { $script:Facts }
                Mock Write-XmipDeployHost { }
                Mock Test-XmipDeployElevated { $true }
                Mock Initialize-XmipDeployState {
                    @{ Folder = [string] $TestDrive; Key = 'k'; KnownHosts = 'h'; HostKey = @{} } }
                Mock Initialize-XmipDeployIdentity { }
                Mock Write-XmipDeployLine { }
                Mock Invoke-XmipDeployStep {
                    $script:Called.Add($Step.Name)
                    @{ Step = $Step.Name; InDesiredState = $true; Seconds = 0 }
                }
                [IO.FileStream] $first = Lock-XmipDeployState -Folder $TestDrive
                try {
                    { Deploy-XmipEnvironment -Path $Made.File -Cluster $Cluster -WhatIf } |
                        Should -Throw 'REFUSED: another run of this environment holds*run.lock*'
                    $script:Called.Count | Should -Be 0
                }
                finally {
                    $first.Dispose()
                }
                # Released, the next run runs, and releases it in its turn.
                Deploy-XmipEnvironment -Path $Made.File -Cluster $Cluster -WhatIf | Out-Null
                Lock-XmipDeployState -Folder $TestDrive | ForEach-Object { $_.Dispose() }
                $script:Called
            })
        # Each step once, every one in its desired state.
        $calls.Count | Should -Be @(Get-XmipTestDeployStep -Environment $made -Run (
                [string] $TestDrive)).Count
    }
}

Describe 'msdsc' {
    It 'installs one machine at a time' {
        $made = New-Environment -Linux
        # Each machine answers on its third round.
        [string[]] $calls = @(Invoke-Deploy -Environment $made -Answer {
                param($Step, $Operation, $Round)
                [bool] $done = -not $Step.ContainsKey('Install') -or $Round -ge 3
                @{ Step = $Step.Name; InDesiredState = $done; Seconds = 0 }
            })
        # A step that installs is set until it is done before the next is
        # begun; every other step once.
        [hashtable[]] $steps = @(Get-XmipTestDeployStep -Environment $made -Run (
                [string] $TestDrive))
        [string[]] $expected = @(foreach ($step in $steps) {
                [int] $rounds = if ($step.ContainsKey('Install')) { 3 } else { 1 }
                @(1..$rounds | ForEach-Object { "$($step.Name) set" })
            })
        @($calls | Where-Object { $_ -like 'XMIP-* set' }) | Should -Not -BeNullOrEmpty
        $calls | Should -Be $expected
    }

    It 'tests a node again once every node is started, and fails one that still differs' {
        $made = New-Environment -Linux
        [string] $running = @(Get-PlacedNode -Environment $made)[-1]
        # A node runs once the nodes are started together.
        [scriptblock] $answer = {
            param($Step, $Operation, $Round, $Value)
            [bool] $done = $Step.Name -ne $Value.Running -or (
                $Operation -eq 'test' -and $Value.Settled)
            @{ Step = $Step.Name; InDesiredState = $done; Seconds = 0 }
        }
        [string[]] $calls = @(Invoke-Deploy -Environment $made -Answer $answer -Value @{
                Running = $running; Settled = $true })
        $calls[-2..-1] | Should -Be @('started set', "$running test")
        { Invoke-Deploy -Environment $made -Answer $answer -Value @{
                Running = $running; Settled = $false } } |
            Should -Throw "*not in their desired state after set: $running*"
    }

    It 'records what a run that applied made, and nothing for a run that only tests' {
        $made = New-Environment -Linux
        [string] $record = Join-Path $TestDrive 'deployed.toml'
        Remove-Item -LiteralPath $record -ErrorAction SilentlyContinue
        Invoke-Deploy -Environment $made -WhatIf | Out-Null
        Test-Path -LiteralPath $record | Should -BeFalse
        Invoke-Deploy -Environment $made | Out-Null
        [hashtable] $read = Read-XmipTestEnvironment -Environment $made -Run ([string] $TestDrive)
        $deployed = InModuleScope Xmip -Parameters @{ Cluster = $script:Cluster } {
            param($Cluster)
            Mock Get-XmipDeployStateFolder { [string] $TestDrive }
            Read-XmipDeployedEnvironment -Cluster $Cluster
        }
        $deployed.Cluster | Should -Be $script:Cluster
        $deployed.File | Should -Be $made.File
        $deployed.Sha256 | Should -Be (Get-FileHash -LiteralPath $made.File).Hash.ToLowerInvariant()
        @($deployed.Nodes.Keys) | Should -Be @($read.Nodes | ForEach-Object { $_.node })
        $deployed.Nodes[$read.Nodes[0].node] | Should -Be $read.Nodes[0].machine.address
        @($deployed.FarEnds.Keys) | Should -Be @($read.FarEnds | ForEach-Object { $_.name })
    }

    It 'gives each node its machine, every placed node and its family''s package' {
        $made = New-Environment
        [string[]] $placed = @(Get-PlacedNode -Environment $made)
        [hashtable[]] $steps = @(Get-XmipTestDeployStep -Environment $made -Run (
                [string] $TestDrive))
        [hashtable[]] $nodes = @($steps | Where-Object { $_.Value.ContainsKey('node') })
        @($nodes | ForEach-Object { $_.Name }) | Should -Be $placed
        [Collections.IDictionary] $declared = (
            Read-XmipTestYaml -Path $nodes[0].Document).parameters
        foreach ($name in $declared.Keys) {
            if (-not $declared[$name].Contains('defaultValue')) {
                $nodes[0].Value.ContainsKey($name) | Should -BeTrue -Because $name
            }
        }
        [hashtable] $linux = @($nodes | Where-Object { $_.Value.machine.family -eq 'Linux' })[0]
        $linux.Value.placed | Should -Be ($placed -join ',')
        $linux.Value.machine.name | Should -Be "XMIP-$($linux.Name)"
        $linux.Value.packages.Linux.file | Should -Be 'xmip.rpm'
        $linux.Value.tools.Linux.pwsh.sha256 | Should -Be 'ab'
        $linux.Value.common.knownHosts | Should -Be 'known_hosts'
    }

    It 'starts every node together last, since none accepts work before its Storage' {
        $made = New-Environment
        [hashtable[]] $steps = @(Get-XmipTestDeployStep -Environment $made -Run (
                [string] $TestDrive))
        $steps[-1].Name | Should -Be 'started'
        @($steps[-1].Value.nodes | ForEach-Object { $_.node }) |
            Should -Be @(Get-PlacedNode -Environment $made)
        $steps[-1].Value.common.keyPath | Should -Be 'key'
    }

    It 'gives every hypervisor''s machine document what the answer medium reads, on <_>' -ForEach @(
        'hyperv', 'libvirt') {
        # What deploy/dsc/machine's answer reads of a machine: a document
        # that does not pass one installs an AlmaLinux machine without it,
        # its host key among them, and every login to it is then refused.
        [string[]] $answered = @('name', 'address', 'domainName', 'network', 'image',
            'linuxAccount', 'sshPublicKeyPath', 'hostKeyPath', 'secretPath', 'description')
        [hashtable] $made = New-XmipTestEnvironment -Folder (Join-Path $TestDrive $_) -Hypervisor (
            $_) -Linux:($_ -eq 'libvirt')
        [hashtable[]] $machines = @(Get-XmipTestDeployStep -Environment $made -Run (
                [string] $TestDrive) | Where-Object { $_.Value.ContainsKey('image') })
        @($machines | Where-Object { $_.Value['image'].family -eq 'Linux' }).Count |
            Should -BeGreaterThan 0
        $document = Read-XmipTestYaml -Path $machines[0].Document
        [Collections.IDictionary] $passed = @($document.resources)[0].properties
        foreach ($name in $answered) {
            $document.parameters.Contains($name) | Should -BeTrue -Because "it declares $name"
            $passed[$name] | Should -Be "[parameters('$name')]" -Because "it passes $name"
            $machines[0].Value.ContainsKey($name) | Should -BeTrue -Because "the step gives $name"
        }
        $machines[0].Value.description | Should -BeLike "* $($machines[0].Name.Substring(5)) $(
            [char] 0x00B7) *"
    }

    It 'promotes the domain''s controller before the names, then joins each other Windows machine' {
        $made = New-XmipTestEnvironment -Folder (Join-Path $TestDrive 'domain')
        [hashtable[]] $steps = @(Get-XmipTestDeployStep -Environment $made -Run (
                [string] $TestDrive))
        [string[]] $names = @($steps | ForEach-Object { $_.Name })
        [string] $controller = "XMIP-$($made.Content['environment']['domain_controller'])"
        [string[]] $members = @($steps | Where-Object {
                $_.Value.ContainsKey('image') -and $_.Value['image'].family -eq 'Windows' -and
                $_.Name -ne $controller } | ForEach-Object { "domain-$($_.Name)" })
        [int] $promoted = [array]::IndexOf($names, "domain-$controller")
        [int] $named = [array]::IndexOf($names, 'names')
        $promoted | Should -BeGreaterThan ([array]::IndexOf($names, $controller))
        $named | Should -BeGreaterThan $promoted
        $members | Should -Not -BeNullOrEmpty
        foreach ($member in $members) {
            [array]::IndexOf($names, $member) | Should -BeGreaterThan $named
            $step = $steps | Where-Object { $_.Name -eq $member }
            $step.Value.controller | Should -BeFalse
            $step.ContainsKey('Install') | Should -BeTrue -Because 'a join restarts the machine'
        }
        ($steps | Where-Object { $_.Name -eq 'names' }).Value.tools.Windows.Keys |
            Sort-Object | Should -Be @('dsc', 'pwsh')
    }

    It 'gives the names to a DNS server only where one of the machines is it' {
        # No domain controller: the host answers the names, and no step gives them.
        [string[]] $without = @(Get-XmipTestDeployStep -Environment (New-Environment -Linux) -Run (
                [string] $TestDrive) | ForEach-Object { $_.Name })
        $without | Should -Not -Contain 'names'
        $made = New-XmipTestEnvironment -Folder (Join-Path $TestDrive 'names')
        [hashtable] $read = Read-XmipTestEnvironment -Environment $made -Run ([string] $TestDrive)
        [hashtable] $names = @(Get-XmipTestDeployStep -Environment $made -Run (
                [string] $TestDrive) | Where-Object { $_.Name -eq 'names' })[0]
        [string] $controller = $made.Content['environment']['domain_controller']
        $names.Value.server.name | Should -Be "XMIP-$controller"
        $names.Value.server.address | Should -Be $read.Common.network.dnsServer
        @($names.Value.records | ForEach-Object { $_.name }) | Should -Contain $read.Nodes[-1].node
    }
}

Describe 'Ansible' {
    It 'maps the nodes onto the machines as the msdsc steps do, reached strictly' {
        $made = New-Environment -Technology 'ansible' -Linux
        $made.Hypervisor = 'libvirt'
        [string] $path = Write-XmipTestInventory -Environment $made -Run $made.Folder
        $inventory = (Read-XmipTestYaml -Path $path).all.children
        [Collections.IDictionary] $nodes = $inventory.xmip_nodes.hosts
        [string[]] $mapped = @(Get-XmipTestDeployStep -Environment $made -Run (
                $made.Folder) | Where-Object { $_.Value.ContainsKey('node') } |
            ForEach-Object { "$($_.Value.machine.name) $($_.Name)" })
        # In the steps' order, the order the nodes play runs them in.
        [string] $text = Get-Content -LiteralPath $path -Raw
        [string[]] $order = @([regex]::Matches($text.Substring($text.IndexOf('xmip_nodes:')),
                '(?m)^\s+(XMIP-[\w-]+):\s*$') | ForEach-Object { $_.Groups[1].Value })
        @($order | ForEach-Object { "$_ $($nodes[$_].xmip_node_name)" }) | Should -Be $mapped
        $inventory.linux.vars.ansible_ssh_common_args |
            Should -Be '-o UserKnownHostsFile=known_hosts -o StrictHostKeyChecking=yes'
        $inventory.linux.vars.ansible_python_interpreter | Should -Be '/usr/bin/python3'
        $inventory.xmip_hypervisor_host.hosts.localhost.ansible_connection | Should -Be 'local'
        # No domain controller: no machine is the network's DNS server.
        @($inventory.xmip_name_server.hosts.Keys) | Should -BeNullOrEmpty
    }

    It 'reaches a Hyper-V host over WinRM, and the domain controller is the name server' {
        $made = New-XmipTestEnvironment -Folder (Join-Path $TestDrive 'hyperv') -Technology (
            'ansible')
        [string] $path = Write-XmipTestInventory -Environment $made -Run $made.Folder
        $inventory = (Read-XmipTestYaml -Path $path).all.children
        $inventory.xmip_hypervisor_host.hosts[$made.Facts.WindowsHost].ansible_connection |
            Should -Be 'winrm'
        @($inventory.xmip_name_server.hosts.Keys) |
            Should -Be @("XMIP-$($made.Content['environment']['domain_controller'])")
    }

    It 'reads a machine''s facts through ansible_facts, never as top-level variables' {
        # ansible-core 2.24 no longer injects facts as variables; what is left
        # is how a machine is reached and Ansible's own.
        [string] $own = '^ansible_(facts|host|port|user|connection|password|' +
            '(pwsh|python)_interpreter|winrm_\w+|ssh_\w+|become\w*|check_mode)$'
        [string[]] $found = @(Get-ChildItem -LiteralPath (
                Join-Path $script:Root 'deploy/dsc/ansible') -Recurse -File -Filter '*.yml' |
            Select-String -Pattern '\bansible_\w+' -AllMatches | ForEach-Object {
                foreach ($match in $_.Matches) {
                    if ($match.Value -notmatch $own) {
                        "$($_.Path):$($_.LineNumber) $($match.Value)"
                    }
                }
            })
        $found | Should -BeNullOrEmpty
    }

    It 'answers each host''s recap from the playbook, and refuses a run that fails' {
        function global:ansible-playbook {
            "PLAY [The environment's machines] ***"
            'PLAY RECAP ***'
            'localhost : ok=3 changed=1 unreachable=0 failed=0 skipped=0'
            'XMIP-IN01 : ok=12 changed=0 unreachable=0 failed=1 skipped=2'
            $global:LASTEXITCODE = $global:XmipTestExit
        }
        [scriptblock] $run = {
            InModuleScope Xmip -Parameters @{ Log = [string] $TestDrive; Estate = $script:Root } {
                param($Log, $Estate)
                [hashtable] $asked = @{ Inventory = 'inventory.yml'; Estate = $Estate; Log = $Log }
                Invoke-XmipDeployPlaybook @asked 6> $null
            }
        }
        try {
            $global:XmipTestExit = 0
            [object[]] $hosts = @(& $run)
            $global:XmipTestExit = 2
            $run | Should -Throw 'REFUSED: ansible-playbook exit 2*'
        }
        finally {
            # The global function itself: a scope in a provider path names none.
            Remove-Item -Path 'Function:\ansible-playbook'
        }
        @($hosts | ForEach-Object { "$($_.Host) $($_.Changed) $($_.InDesiredState)" }) |
            Should -Be @('localhost 1 True', 'XMIP-IN01 0 False')
    }

    It 'answers a host a check would change, or not reach, not in its desired state' {
        # A check of machines not made yet reaches none: answered, not refused.
        function global:ansible-playbook {
            "PLAY [The environment's machines] ***"
            'PLAY RECAP ***'
            'localhost : ok=9 changed=1 unreachable=0 failed=0 skipped=3'
            'XMIP-IN01 : ok=0 changed=0 unreachable=1 failed=0 skipped=0'
            'XMIP-APP03 : ok=25 changed=0 unreachable=0 failed=0 skipped=24'
            $global:LASTEXITCODE = 4
        }
        try {
            [object[]] $hosts = @(InModuleScope Xmip -Parameters @{
                    Log = [string] $TestDrive; Estate = $script:Root } {
                    param($Log, $Estate)
                    [hashtable] $asked = @{ Inventory = 'inventory.yml'; Estate = $Estate
                        Log = $Log; Named = @('XMIP-APP03', 'XMIP-APP04', 'XMIP-IN01') }
                    Invoke-XmipDeployPlaybook @asked -Check 6> $null
                })
        }
        finally {
            Remove-Item -Path 'Function:\ansible-playbook'
        }
        # XMIP-APP04 never came: a play run a host at a time stops at one unreached.
        @($hosts | ForEach-Object { "$($_.Host) $($_.Unreachable) $($_.InDesiredState)" }) |
            Should -Be @('localhost 0 False', 'XMIP-IN01 1 False', 'XMIP-APP03 0 True',
                'XMIP-APP04 1 False')
    }

    It 'runs every read under --check, and every command that changes says it would' {
        # The command module runs nothing under --check: a read is told to
        # run (check_mode: false), and a change names in removes or creates
        # the file it needs, which is how the module says it would run.
        [string] $roles = Join-Path $script:Root 'deploy/dsc/ansible/roles'
        [IO.FileInfo[]] $files = @(Get-ChildItem -LiteralPath $roles -Recurse -File -Filter (
                '*.yml') | Where-Object { $_.Directory.Name -eq 'tasks' })
        [string[]] $found = @(foreach ($file in $files) {
                foreach ($task in @(Get-AnsibleTask -Path $file.FullName)) {
                    [string] $module = @($task.Keys | Where-Object {
                            $_ -in 'ansible.builtin.command', 'ansible.windows.win_command' })[0]
                    if (-not $module) {
                        continue
                    }
                    [Collections.IDictionary] $asked = $task[$module]
                    [bool] $reads = $task.Contains('changed_when') -and
                        $false -eq $task['changed_when']
                    [bool] $told = $task.Contains('check_mode') -and $false -eq $task['check_mode']
                    [bool] $says = $asked.Contains('removes') -or $asked.Contains('creates')
                    if (($reads -and -not $told) -or (-not $reads -and -not $says)) {
                        "$($file.Name): $($task['name'])"
                    }
                }
            })
        $found | Should -BeNullOrEmpty
    }

    It 'makes the node''s firewalld service permanent alone, then asks the running one, reloads' {
        [object[]] $tasks = @(Get-AnsibleTask -Path (Join-Path $script:Root (
                    'deploy/dsc/ansible/roles/xmip_node/tasks/linux.yml')))
        [string[]] $names = @($tasks | ForEach-Object { $_['name'] })
        # firewalld refuses a service made permanent and enabled at once.
        @($tasks | Where-Object { $_.Contains('ansible.posix.firewalld') -and
                $_['ansible.posix.firewalld'].Contains('immediate') }) | Should -BeNullOrEmpty
        [int] $zone = [Array]::IndexOf($names, 'The node''s firewalld service in the zone')
        [int] $asked = [Array]::IndexOf($names,
            'Whether the running firewall holds the node''s service')
        [int] $reloaded = [Array]::IndexOf($names,
            'The firewall reloaded, so it runs as it is kept')
        $tasks[$zone]['ansible.posix.firewalld'].permanent | Should -BeTrue
        $asked | Should -BeGreaterThan $zone
        $reloaded | Should -BeGreaterThan $asked
        $tasks[$reloaded]['when'] | Should -Be 'xmip_firewall_running.rc != 0'
        # A build made again under one version: the headers compared first.
        [int] $headers = [Array]::IndexOf($names,
            'The headers of the package installed and of the one shipped')
        [int] $upgrade = [Array]::IndexOf($names,
            'The package shipped installed over another build, which runs xmip-service --install')
        $headers | Should -BeGreaterThan -1
        $upgrade | Should -BeGreaterThan $headers
        $tasks[$upgrade]['when'] | Should -BeLike '*xmip_header.results*'
    }

    It 'starts the network and the pool with the host in a task of its own, as libvirt says' {
        # virt_net and virt_pool answer a task naming a state before they look
        # at autostart (community.libvirt 2.4.0): one naming both never sets it.
        [object[]] $tasks = @(Get-AnsibleTask -Path (Join-Path $script:Root (
                    'deploy/dsc/ansible/roles/xmip_machine/tasks/libvirt.yml')))
        [string[]] $both = @(foreach ($task in $tasks) {
                foreach ($module in 'community.libvirt.virt_net', 'community.libvirt.virt_pool') {
                    if ($task.Contains($module) -and $task[$module].Contains('state') -and
                        $task[$module].Contains('autostart')) {
                        $task['name']
                    }
                }
            })
        $both | Should -BeNullOrEmpty
        @($tasks | Where-Object { $_.Contains('community.libvirt.virt_net') -and
                $_['community.libvirt.virt_net'].autostart }).Count | Should -Be 1
        @($tasks | Where-Object { $_.Contains('community.libvirt.virt_pool') -and
                $_['community.libvirt.virt_pool'].autostart }).Count | Should -Be 1
    }

    It 'stages in a folder of its own, never the one Microsoft DSC''s template stages in' {
        . (Join-Path $script:Root 'deploy/dsc/msdsc/environment/EnvironmentMachine.ps1')
        [string] $staging = (Read-XmipTestYaml -Path (Join-Path $script:Root (
                    'deploy/dsc/ansible/roles/xmip_node/defaults/main.yml'))).xmip_staging
        foreach ($family in 'Windows', 'Linux') {
            $staging.Contains((Get-EnvironmentStaging -Family $family)) |
                Should -BeFalse -Because "msdsc stages a $family machine's files there"
        }
    }

    It 'never trusts a libvirt machine''s record without its technology: one place answers it' {
        [string] $machine = Get-Content -Raw -LiteralPath (Join-Path $script:Root (
                'deploy/dsc/ansible/roles/xmip_machine/tasks/libvirt-machine.yml'))
        $machine | Should -Match "xmip_definition \+ \['State'\]"
        $machine | Should -Not -Match 'virsh'
        # Under --check a domain not defined yet is not started.
        $machine | Should -Match (
            'when: not ansible_check_mode or \(xmip_record.stdout \| from_json\).defined')
    }

    It 'presses a Windows ISO''s boot key through the one script both technologies run' {
        # 2026-11-24: the Hyper-V press was written twice, so changing Space to
        # Enter the day before took two edits (ADR-0015, amendment 2026-11-24).
        [string] $machine = Join-Path $script:Root 'deploy/dsc/machine/HyperVBootKey.ps1'
        [string] $tasks = Get-Content -Raw -LiteralPath (Join-Path $script:Root (
                'deploy/dsc/ansible/roles/xmip_machine/tasks/hyperv-machine.yml'))

        $tasks | Should -Match "xmip_boot_key: .+/HyperVBootKey\.ps1"
        $tasks | Should -Match 'Send-HyperVBootKey -Name \$Name'
        Get-Content -Raw -LiteralPath (Join-Path $script:Root (
                'deploy/dsc/msdsc/hyperv/HyperVResource.ps1')) |
            Should -Match 'machine/HyperVBootKey\.ps1'
        [string[]] $pressing = @(
            Get-ChildItem -LiteralPath (Join-Path $script:Root 'deploy/dsc') -Recurse -File |
                Where-Object { $_.Extension -in '.ps1', '.yml', '.yaml' } |
                Select-String -Pattern 'Msvm_Keyboard' -List |
                ForEach-Object { [System.IO.Path]::GetFileName($_.Path) }
        )
        $pressing | Should -Be @('HyperVBootKey.ps1')
        # Ansible runs it on the host in Windows PowerShell.
        Get-Content -Raw -LiteralPath $machine | Should -Not -Match '#requires'
    }

    It 'writes no network, pool, domain or kickstart in any task: the machine folder does' {
        [string[]] $found = @(Get-ChildItem -LiteralPath (
                Join-Path $script:Root 'deploy/dsc/ansible') -Recurse -File -Filter '*.yml' |
            Select-String -Pattern '<domain|<network|<pool|%post|%packages' |
            ForEach-Object { "$($_.Path):$($_.LineNumber)" })
        $found | Should -BeNullOrEmpty
    }
}

Describe 'The private state' {
    BeforeEach {
        if ($null -eq (Get-Command -Name ssh-keygen -ErrorAction SilentlyContinue)) {
            Set-ItResult -Skipped -Because 'ssh-keygen (OpenSSH) is not on PATH'
        }
    }

    It 'makes a host key per AlmaLinux machine and known_hosts of exactly those' {
        $made = New-Environment -Linux
        [string] $folder = Join-Path $made.Folder 'state'
        [hashtable[]] $twice = @(foreach ($round in 1, 2) {
                Initialize-State -Environment $made -Folder $folder
            })
        [hashtable] $state = $twice[0]
        [hashtable] $read = Read-XmipTestEnvironment -Environment $made -Run $folder
        [object[]] $linux = @($read.Machines | Where-Object { $_['image'].family -eq 'Linux' })
        @($state.HostKey.Keys | Sort-Object) |
            Should -Be @($linux | ForEach-Object { $_['name'] } | Sort-Object)
        [string[]] $known = @(Get-Content -LiteralPath $state.KnownHosts)
        foreach ($index in 0, 2) {
            $known[$index] | Should -BeLike (
                "$($linux[$index]['name']),$($linux[$index]['address']) ssh-ed25519 *")
        }
        # The environment's own key, with no passphrase, so a run needs no one.
        Get-Content -LiteralPath "$($state.Key).pub" | Should -BeLike "ssh-ed25519 * xmip-$(
            $read.Name)"
        & ssh-keygen -y -P '' -f $state.Key | Should -BeLike 'ssh-ed25519 *'
        if (-not $IsWindows) {
            [IO.File]::GetUnixFileMode($state.Key) |
                Should -Be ([IO.UnixFileMode] 'UserRead, UserWrite')
        }
        Get-Content -LiteralPath "$($twice[1].Key).pub" |
            Should -Be (Get-Content -LiteralPath "$($state.Key).pub") -Because 'a key is kept'
    }

    It 'makes the Windows machines'' Administrator secret once, encrypted for this account' -Skip:(
        -not $IsWindows) {
        $made = New-XmipTestEnvironment -Folder (Join-Path $TestDrive 'secret')
        [string] $folder = Join-Path $made.Folder 'state'
        Initialize-State -Environment $made -Folder $folder | Out-Null
        [byte[]] $first = [IO.File]::ReadAllBytes($made.Facts.Secret)
        Initialize-State -Environment $made -Folder $folder | Out-Null
        [IO.File]::ReadAllBytes($made.Facts.Secret) | Should -Be $first -Because 'it is made once'
        [pscredential] $secret = Import-Clixml -LiteralPath $made.Facts.Secret
        $secret.UserName | Should -Be 'Administrator'
        [string] $password = $secret.GetNetworkCredential().Password
        $password.Length | Should -Be 24
        foreach ($kind in '[A-Z]', '[a-z]', '[0-9]', '[^A-Za-z0-9]') {
            $password | Should -Match $kind
        }
        # What every template reads it by: encrypted, so refused nowhere on Windows.
        . (Join-Path $script:Root 'deploy/dsc/machine/MachineSecret.ps1')
        (Read-MachineSecret -Path $made.Facts.Secret).UserName | Should -Be 'Administrator'
    }

    It 'keeps the state on Linux out of the clone, and on Windows in the run folder' {
        [string] $folder = & (Get-Module -Name Xmip) {
            param($Cluster)
            Get-XmipDeployStateFolder -Name $Cluster -Run 'run'
        } $script:Cluster
        if ($IsWindows) {
            $folder | Should -Be (Join-Path 'run' 'state')
        }
        else {
            $folder | Should -BeLike "*/xmip/deploy/$script:Cluster"
            $folder | Should -Not -BeLike 'run*'
        }
    }

    It 'refuses the other technology over an environment one made, and a test records none' {
        $made = New-Environment -Linux
        [string] $folder = Join-Path $made.Folder 'state'
        # Tested only, by ansible: nothing recorded, so msdsc may still make it.
        Initialize-State -Environment $made -Folder $folder -Technology 'ansible' |
            Out-Null
        Test-Path -LiteralPath (Join-Path $folder 'technology') | Should -BeFalse
        Initialize-State -Environment $made -Folder $folder -Record | Out-Null
        Get-Content -LiteralPath (Join-Path $folder 'technology') | Should -Be 'msdsc'
        { Initialize-State -Environment $made -Folder $folder -Technology 'ansible' } |
            Should -Throw 'REFUSED: * was made by msdsc, not ansible*never a mix*'
        Initialize-State -Environment $made -Folder $folder -Record |
            ForEach-Object { $_.Folder } | Should -Be $folder
    }

    It 'refuses a second run before it writes the state: known_hosts keeps its bytes' {
        $made = New-Environment -Linux
        [string] $folder = Join-Path $made.Folder 'state'
        [string] $known = (Initialize-State -Environment $made -Folder (
                $folder)).KnownHosts
        [byte[]] $before = [IO.File]::ReadAllBytes($known)
        InModuleScope Xmip -Parameters @{ Made = $made; Folder = $folder
            Cluster = $script:Cluster } {
            param($Made, $Folder, $Cluster)
            $script:Folder = $Folder
            Mock Get-XmipDeployRunFolder { $script:Folder }
            Mock Get-XmipDeployStateFolder { $script:Folder }
            Mock Test-XmipDeployElevated { $true }
            [IO.FileStream] $running = Lock-XmipDeployState -Folder $Folder
            try {
                { Deploy-XmipEnvironment -Path $Made.File -Cluster $Cluster -WhatIf } |
                    Should -Throw 'REFUSED: another run of this environment holds*'
            }
            finally {
                $running.Dispose()
            }
        }
        [IO.File]::ReadAllBytes($known) | Should -Be $before
    }
}
