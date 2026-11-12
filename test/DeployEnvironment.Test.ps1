#requires -PSEdition Core
#requires -Version 7.7.0

<#
    Deploy-XmipEnvironment (Xmip/Deploy-XmipEnvironment.ps1) without a
    hypervisor: what the one environment file makes of both technologies.

    - The file names its technology, msdsc or ansible, or is refused naming
      the line to add; a hypervisor with no template in that technology is
      refused; a machine running two nodes is refused; Ansible on Windows is
      refused, naming the command to run in WSL; a second run of an
      environment is refused while one holds its private state, before it
      writes anything there.
    - msdsc installs one machine at a time: the next machine's first set
      comes only once the one before is in its desired state.
    - Each node is given the environment template's machine.dsc.yaml, with
      every parameter it declares and has no default for, its machine's
      family, every placed node and its family's package; every
      hypervisor's machine document is given what the answer medium reads,
      the host key among it; the names step is there only where a machine
      is the network's DNS server.
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
      one run to the next.
    - No task of the Ansible set writes a network, pool, domain or kickstart
      of its own: deploy/dsc/machine does (test/DeployMachine.Test.ps1).

    The machines themselves are proved by running the command:
    deploy/dsc/README.md.

    Style: doc/governance/powershell-style.md
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    [string] $script:Example = Join-Path $script:Root 'deploy/dsc/libvirt.example.toml'

    # The libvirt example with what its nodes need, changed as asked, in a
    # folder of its own: the file, its path and the folder.
    function New-Environment {
        param(
            [string] $Technology = 'msdsc',
            [hashtable] $Change = @{}
        )

        [string] $folder = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $environment = Read-XmipTestEnvironment -Path $script:Example -Folder $folder -Technology (
            $Technology)
        foreach ($key in $Change.Keys) {
            if ($null -eq $Change[$key]) {
                $environment.Remove($key)
            }
            else {
                $environment[$key] = $Change[$key]
            }
        }
        [string] $path = Join-Path $folder 'environment.toml'
        & (Get-Module -Name Xmip) {
            param($Path, $Value)
            Write-XmipToml -Path $Path -Value $Value
        } $path $environment
        return @{ Environment = $environment; Path = $path; Folder = $folder }
    }

    <#
        .SYNOPSIS
        The nodes an environment places, machine by machine in its order: a
        name is the environment's configuration, never the test's (ADR-0056,
        amendment 2026-10-03).
    #>
    function Get-PlacedNode {
        param([System.Collections.IDictionary] $Environment)

        @($Environment['machines'] | ForEach-Object { $_['nodes'] } | Where-Object { $_ })
    }

    function Read-Environment {
        param([System.Collections.IDictionary] $Environment)

        return & (Get-Module -Name Xmip) {
            param($Environment, $Estate, $Run)
            Get-XmipDeployEnvironment -Environment $Environment -Estate $Estate -Run $Run
        } $Environment $script:Root ([string] $TestDrive)
    }

    # The private state the module makes, in a folder of the test's own.
    function Initialize-State {
        param(
            [System.Collections.IDictionary] $Environment,
            [string] $Folder,
            [string] $Technology = 'msdsc',
            [switch] $Record
        )

        return & (Get-Module -Name Xmip) {
            param($Environment, $Folder, $Technology, $Record)
            [IO.FileStream] $held = Lock-XmipDeployState -Folder $Folder
            try {
                Initialize-XmipDeployState -Environment $Environment -Folder $Folder -Technology (
                    $Technology) -Record:$Record
            }
            finally {
                $held.Dispose()
            }
        } $Environment $Folder $Technology $Record.IsPresent
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

Describe 'The environment file' {
    It 'refuses a file that names no technology, naming the line to add' {
        $made = New-Environment -Change @{ technology = $null }
        { Read-Environment -Environment $made.Environment } |
            Should -Throw '*technology = "msdsc" or technology = "ansible"*'
    }

    It 'refuses a hypervisor with no template in the technology it names' {
        $made = New-Environment -Technology 'ansible' -Change @{ hypervisor = 'nothing' }
        { Read-Environment -Environment $made.Environment } |
            Should -Throw '*ansible has no template*nothing*'
    }

    It 'refuses a machine that runs two nodes' {
        $made = New-Environment
        [Collections.IDictionary] $last = @($made.Environment['machines'])[-1]
        [string[]] $two = @(@($last['nodes'])[0], 'n')
        $last['nodes'] = $two
        { Read-Environment -Environment $made.Environment } |
            Should -Throw "*$($last['name']) names $($two -join ', ')*"
    }

    It 'refuses Ansible on Windows, naming the command to run in WSL' -Skip:(-not $IsWindows) {
        $made = New-Environment -Technology 'ansible'
        { Deploy-XmipEnvironment -Path $made.Path -WhatIf } | Should -Throw '*wsl.exe -- pwsh*'
    }

    It 'refuses a second run of the environment while one runs, before any step' {
        $made = New-Environment
        [string[]] $calls = @(InModuleScope Xmip -Parameters @{ Path = $made.Path } {
                param($Path)
                $script:Called = [Collections.Generic.List[string]]::new()
                Mock Get-XmipDeployStateFolder { [string] $TestDrive }
                Mock Initialize-XmipDeployState {
                    @{ Folder = [string] $TestDrive; Key = 'k'; KnownHosts = 'h'; HostKey = @{} } }
                Mock Write-XmipDeployLine { }
                Mock Invoke-XmipDeployStep {
                    $script:Called.Add($Step.Name)
                    @{ Step = $Step.Name; InDesiredState = $true; Seconds = 0 }
                }
                [IO.FileStream] $first = Lock-XmipDeployState -Folder $TestDrive
                try {
                    { Deploy-XmipEnvironment -Path $Path -WhatIf } |
                        Should -Throw 'REFUSED: another run of this environment holds*run.lock*'
                    $script:Called.Count | Should -Be 0
                }
                finally {
                    $first.Dispose()
                }
                # Released, the next run runs, and releases it in its turn.
                Deploy-XmipEnvironment -Path $Path -WhatIf | Out-Null
                Lock-XmipDeployState -Folder $TestDrive | ForEach-Object { $_.Dispose() }
                $script:Called
            })
        $calls.Count | Should -Be 8
    }
}

Describe 'msdsc' {
    It 'installs one machine at a time' {
        $made = New-Environment
        [string[]] $calls = @(InModuleScope Xmip -Parameters @{ Path = $made.Path } {
                param($Path)
                $script:Called = [Collections.Generic.List[string]]::new()
                $script:Rounds = @{}
                Mock Get-XmipDeployStateFolder { [string] $TestDrive }
                Mock Initialize-XmipDeployState {
                    @{ Folder = [string] $TestDrive; Key = 'k'; KnownHosts = 'h'; HostKey = @{} } }
                Mock Start-Sleep { }
                Mock Write-XmipDeployLine { }
                Mock Invoke-XmipDeployStep {
                    $script:Called.Add("$($Step.Name) $Operation")
                    $script:Rounds[$Step.Name] = 1 + [int] $script:Rounds[$Step.Name]
                    # Each machine answers on its third round.
                    [bool] $done = -not $Step.ContainsKey('Install') -or
                        $script:Rounds[$Step.Name] -ge 3
                    @{ Step = $Step.Name; InDesiredState = $done; Seconds = 0 }
                }
                Deploy-XmipEnvironment -Path $Path | Out-Null
                $script:Called
            })
        [string[]] $machine = @('XMIP-APP03', 'XMIP-APP04', 'XMIP-IN01' | ForEach-Object {
                "$_ set", "$_ set", "$_ set" })
        [string[]] $node = @(Get-PlacedNode -Environment $made.Environment | ForEach-Object {
                "$_ set" })
        $calls | Should -Be (@('network set') + $machine + $node + @('started set'))
    }

    It 'tests a node again once every node is started, and fails one that still differs' {
        $made = New-Environment
        [string] $running = @(Get-PlacedNode -Environment $made.Environment)[-1]
        [scriptblock] $deploy = {
            param($Path, $Settled, $Running)
            [hashtable] $given = @{ Path = $Path; Settled = $Settled; Running = $Running }
            InModuleScope Xmip -Parameters $given {
                param($Path, $Settled, $Running)
                $script:Called = [Collections.Generic.List[string]]::new()
                $script:Settled = $Settled
                $script:Running = $Running
                Mock Get-XmipDeployStateFolder { [string] $TestDrive }
                Mock Initialize-XmipDeployState {
                    @{ Folder = [string] $TestDrive; Key = 'k'; KnownHosts = 'h'; HostKey = @{} } }
                Mock Write-XmipDeployLine { }
                Mock Invoke-XmipDeployStep {
                    $script:Called.Add("$($Step.Name) $Operation")
                    # A node runs once the nodes are started together.
                    [bool] $done = $Step.Name -ne $script:Running -or (
                        $Operation -eq 'test' -and $script:Settled)
                    @{ Step = $Step.Name; InDesiredState = $done; Seconds = 0 }
                }
                Deploy-XmipEnvironment -Path $Path | Out-Null
                $script:Called
            }
        }
        [string[]] $calls = @(& $deploy $made.Path $true $running)
        $calls[-2..-1] | Should -Be @('started set', "$running test")
        { & $deploy $made.Path $false $running } |
            Should -Throw "*not in their desired state after set: $running*"
    }

    It 'gives each node its machine, every placed node and its family''s package' {
        $made = New-Environment
        [string[]] $placed = @(Get-PlacedNode -Environment $made.Environment)
        [hashtable[]] $steps = @(Get-XmipTestDeployStep -Environment $made.Environment -Run (
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
        $nodes[2].Value.placed | Should -Be ($placed -join ',')
        $nodes[2].Value.machine.name | Should -Be 'XMIP-IN01'
        $nodes[2].Value.machine.family | Should -Be 'Linux'
        $nodes[2].Value.packages.Linux.file | Should -Be 'xmip.rpm'
        $nodes[2].Value.tools.Linux.pwsh.sha256 | Should -Be 'ab'
        $nodes[2].Value.common.knownHosts | Should -Be 'known_hosts'
    }

    It 'starts every node together last, since none accepts work before its Storage' {
        $made = New-Environment
        [hashtable[]] $steps = @(Get-XmipTestDeployStep -Environment $made.Environment -Run (
                [string] $TestDrive))
        $steps[-1].Name | Should -Be 'started'
        @($steps[-1].Value.nodes | ForEach-Object { $_.node }) |
            Should -Be @(Get-PlacedNode -Environment $made.Environment)
        $steps[-1].Value.common.keyPath | Should -Be 'key'
    }

    It 'gives every hypervisor''s machine document what the answer medium reads, in <_>' -ForEach @(
        'libvirt.example.toml', 'hyperv.example.toml') {
        # What deploy/dsc/machine's answer reads of a machine: a document
        # that does not pass one installs an AlmaLinux machine without it,
        # its host key among them, and every login to it is then refused.
        [string[]] $answered = @('name', 'address', 'domainName', 'network', 'image',
            'linuxAccount', 'sshPublicKeyPath', 'hostKeyPath', 'secretPath')
        [string] $folder = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        $environment = Read-XmipTestEnvironment -Path (
            Join-Path $script:Root "deploy/dsc/$_") -Folder $folder
        [hashtable[]] $machines = @(Get-XmipTestDeployStep -Environment $environment -Run (
                [string] $TestDrive) | Where-Object { $_.ContainsKey('Install') })
        @($machines | Where-Object { $_.Value['image'].family -eq 'Linux' }).Count |
            Should -BeGreaterThan 0
        $document = Read-XmipTestYaml -Path $machines[0].Document
        [Collections.IDictionary] $passed = @($document.resources)[0].properties
        foreach ($name in $answered) {
            $document.parameters.Contains($name) | Should -BeTrue -Because "it declares $name"
            $passed[$name] | Should -Be "[parameters('$name')]" -Because "it passes $name"
            $machines[0].Value.ContainsKey($name) | Should -BeTrue -Because "the step gives $name"
        }
    }

    It 'gives the names to a DNS server only where one of the machines is it' {
        [string[]] $without = @(Get-XmipTestDeployStep -Environment (
                New-Environment).Environment -Run ([string] $TestDrive) |
            ForEach-Object { $_.Name })
        $without | Should -Not -Contain 'names'
        $made = New-Environment
        $made.Environment['network']['dns_server'] = '10.77.0.53'
        [hashtable] $names = @(Get-XmipTestDeployStep -Environment $made.Environment -Run (
                [string] $TestDrive) | Where-Object { $_.Name -eq 'names' })[0]
        $names.Value.server.name | Should -Be 'XMIP-APP03'
        @($names.Value.records | ForEach-Object { $_.name }) |
            Should -Contain @(Get-PlacedNode -Environment $made.Environment)[-1]
    }
}

Describe 'Ansible' {
    It 'maps the nodes onto the machines as the msdsc steps do, reached strictly' {
        $made = New-Environment -Technology 'ansible'
        [string] $path = Write-XmipTestInventory -Environment $made.Environment -Run $made.Folder
        $inventory = (Read-XmipTestYaml -Path $path).all.children
        [Collections.IDictionary] $nodes = $inventory.xmip_nodes.hosts
        [string[]] $mapped = @(Get-XmipTestDeployStep -Environment $made.Environment -Run (
                $made.Folder) | Where-Object { $_.Value.ContainsKey('node') } |
            ForEach-Object { "$($_.Value.machine.name) $($_.Name)" })
        # In the file's order, the order the nodes play runs them in.
        [string] $text = Get-Content -LiteralPath $path -Raw
        [string[]] $order = @([regex]::Matches($text.Substring($text.IndexOf('xmip_nodes:')),
                '(?m)^\s+(XMIP-[\w-]+):\s*$') | ForEach-Object { $_.Groups[1].Value })
        @($order | ForEach-Object { "$_ $($nodes[$_].xmip_node_name)" }) | Should -Be $mapped
        $inventory.linux.vars.ansible_ssh_common_args |
            Should -Be '-o UserKnownHostsFile=known_hosts -o StrictHostKeyChecking=yes'
        $inventory.linux.vars.ansible_python_interpreter | Should -Be '/usr/bin/python3'
        $inventory.xmip_hypervisor_host.hosts.localhost.ansible_connection | Should -Be 'local'
        # No machine is the DNS server: its group is there, and empty.
        $inventory.Contains('xmip_name_server') | Should -BeTrue
        $inventory.xmip_name_server.hosts.Count | Should -Be 0
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
        $made = New-Environment
        [string] $folder = Join-Path $made.Folder 'state'
        [hashtable[]] $twice = @(foreach ($round in 1, 2) {
                Initialize-State -Environment $made.Environment -Folder $folder
            })
        [hashtable] $state = $twice[0]
        @($state.HostKey.Keys | Sort-Object) |
            Should -Be @('XMIP-APP03', 'XMIP-APP04', 'XMIP-IN01')
        [string[]] $known = @(Get-Content -LiteralPath $state.KnownHosts)
        $known[0] | Should -BeLike 'XMIP-APP03,10.77.0.53 ssh-ed25519 *'
        $known[2] | Should -BeLike 'XMIP-IN01,10.77.0.61 ssh-ed25519 *'
        # The environment's own key, with no passphrase, so a run needs no one.
        Get-Content -LiteralPath "$($state.Key).pub" | Should -BeLike 'ssh-ed25519 * xmip-xmip'
        & ssh-keygen -y -P '' -f $state.Key | Should -BeLike 'ssh-ed25519 *'
        if (-not $IsWindows) {
            [IO.File]::GetUnixFileMode($state.Key) |
                Should -Be ([IO.UnixFileMode] 'UserRead, UserWrite')
        }
        Get-Content -LiteralPath "$($twice[1].Key).pub" |
            Should -Be (Get-Content -LiteralPath "$($state.Key).pub") -Because 'a key is kept'
    }

    It 'keeps the state on Linux out of the clone, and on Windows in the run folder' {
        [string] $folder = & (Get-Module -Name Xmip) {
            Get-XmipDeployStateFolder -Name 'xmip' -Run 'run'
        }
        if ($IsWindows) {
            $folder | Should -Be (Join-Path 'run' 'state')
        }
        else {
            $folder | Should -BeLike '*/xmip/deploy/xmip'
            $folder | Should -Not -BeLike 'run*'
        }
    }

    It 'refuses the other technology over an environment one made, and a test records none' {
        $made = New-Environment
        [string] $folder = Join-Path $made.Folder 'state'
        # Tested only, by ansible: nothing recorded, so msdsc may still make it.
        Initialize-State -Environment $made.Environment -Folder $folder -Technology 'ansible' |
            Out-Null
        Test-Path -LiteralPath (Join-Path $folder 'technology') | Should -BeFalse
        Initialize-State -Environment $made.Environment -Folder $folder -Record | Out-Null
        Get-Content -LiteralPath (Join-Path $folder 'technology') | Should -Be 'msdsc'
        { Initialize-State -Environment $made.Environment -Folder $folder -Technology 'ansible' } |
            Should -Throw 'REFUSED: xmip was made by msdsc, not ansible*never a mix*'
        Initialize-State -Environment $made.Environment -Folder $folder -Record |
            ForEach-Object { $_.Folder } | Should -Be $folder
    }

    It 'refuses a second run before it writes the state: known_hosts keeps its bytes' {
        $made = New-Environment
        [string] $folder = Join-Path $made.Folder 'state'
        [string] $known = (Initialize-State -Environment $made.Environment -Folder (
                $folder)).KnownHosts
        [byte[]] $before = [IO.File]::ReadAllBytes($known)
        # The file changes under the running run: another machine's address.
        @($made.Environment['machines'])[0]['address'] = '10.77.0.99'
        & (Get-Module -Name Xmip) {
            param($Path, $Value)
            Write-XmipToml -Path $Path -Value $Value
        } $made.Path $made.Environment
        InModuleScope Xmip -Parameters @{ Path = $made.Path; Folder = $folder } {
            param($Path, $Folder)
            $script:Folder = $Folder
            Mock Get-XmipDeployStateFolder { $script:Folder }
            [IO.FileStream] $running = Lock-XmipDeployState -Folder $Folder
            try {
                { Deploy-XmipEnvironment -Path $Path -WhatIf } |
                    Should -Throw 'REFUSED: another run of this environment holds*'
            }
            finally {
                $running.Dispose()
            }
        }
        [IO.File]::ReadAllBytes($known) | Should -Be $before
    }
}
