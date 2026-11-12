#requires -PSEdition Core
#requires -Version 7.7.0

<#
    The environment templates (deploy/dsc/msdsc/environment and
    deploy/dsc/ansible; ADR-0015, amendment 2026-10-21) without the
    machines: what can be held on any machine, unelevated.

    - The Microsoft DSC v3 documents parse as YAML, read by the module's
      YAML reader and evaluated by DSC below; each document declares every
      parameter it uses and uses every one it declares — but staging, which
      Xmip.Environment/Machine gives every document it applies.
    - Every document requires DSC 3.4.0-preview.2 and none asks for
      elevation whole; each resource manifest elevates exactly the methods
      that need administrator rights.
    - The resource manifests of the folder are found by DSC.
    - The Ansible role makes node.xmip the node's alone to write, and masks
      the node's key, never logging or diffing it; ansible-playbook
      --syntax-check where Ansible is here, SKIPPED where it is not.
    - The Hyper-V example environment, deploy/dsc/hyperv.example.toml, runs
      through DSC as Deploy-XmipEnvironment applies it, with every resource
      replaced by Microsoft.DSC.Debug/Echo: the names are given every node
      machine's address, each node machine is given its node's files and
      values and the environment's known_hosts, and every node mapped is one
      the Essentials' cluster file declares.
    - An AlmaLinux machine is reached over OpenSSH with the environment's
      key and known_hosts, checked strictly, and DSC is brought to it only
      from a tarball whose SHA-256 is the one named.
    - The Xmip resources' own steps that touch nothing but a folder:
      a file in place, the ports a configuration listens on, the staging
      folder, and node.xmip made the node's alone to write on a file of the
      test's own (Windows; on Linux that needs root and is SKIPPED).

    The machines themselves are proved by running Deploy-XmipEnvironment:
    deploy/dsc/README.md.

    Style: doc/governance/powershell-style.md
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    [string] $script:Template = Join-Path $script:Root 'deploy/dsc/msdsc/environment'
    foreach ($part in 'Program.ps1', 'NodeMachine.ps1', 'NodeFile.ps1', 'NodeOpening.ps1',
        'NodeAccess.ps1', 'NodePackage.ps1', 'EnvironmentSsh.ps1', 'EnvironmentMachine.ps1',
        'EnvironmentSlice.ps1') {
        . (Join-Path $script:Template $part)
    }
    [bool] $script:HasDsc = $null -ne (Get-Command -Name dsc -ErrorAction SilentlyContinue)
    [string] $script:NoDsc = 'dsc (Microsoft DSC v3) is not on PATH; README.md installs it'
    [string[]] $script:Document = @('machine.dsc.yaml', 'names.dsc.yaml', 'node.dsc.yaml',
        'name.dsc.yaml', 'started.dsc.yaml')

    # A copy of a document, in YAML, whose every instance is an Echo of its
    # type and properties, its condition kept, so evaluating it changes
    # nothing.
    function Write-EchoDocument {
        param(
            [Parameter(Mandatory = $true)]
            [string] $Name
        )

        [hashtable] $document = Read-XmipTestYaml -Path (Join-Path $script:Template $Name)
        $document.Remove('directives')
        $document.resources = @($document.resources | ForEach-Object {
            [hashtable] $output = @{ type = $_.type; properties = $_.properties }
            [hashtable] $echo = @{ name = $_.name; type = 'Microsoft.DSC.Debug/Echo'
                properties = @{ output = $output } }
            if ($_.Contains('condition')) {
                $echo.condition = $_.condition
            }
            $echo
        })
        Write-XmipTestYaml -Path (Join-Path $TestDrive $Name) -Value $document
    }

    # The Hyper-V example as Deploy-XmipEnvironment applies it: its steps of
    # this folder, the names and each node, each evaluated with the values
    # of the parameters its document declares. The machine an instance is
    # applied on by its step's name, its slice as "<name> slice".
    $script:Example = Read-XmipTestEnvironment -Path (
        Join-Path $script:Root 'deploy/dsc/hyperv.example.toml') -Folder (
        Join-Path $TestDrive 'environment')
    [hashtable[]] $script:Steps = @(Get-XmipTestDeployStep -Environment $script:Example -Run (
            [string] $TestDrive) | Where-Object {
            [IO.Path]::GetFullPath((Split-Path -Path $_.Document -Parent)) -eq
                [IO.Path]::GetFullPath($script:Template) })
    $script:Nodes = @{}
    foreach ($step in $script:Steps | Where-Object { $_.Value.ContainsKey('node') }) {
        $script:Nodes[$step.Name] = $step.Value.machine
    }

    function Invoke-EchoEnvironment {
        foreach ($name in $script:Document) {
            Write-EchoDocument -Name $name
        }
        [hashtable] $result = @{}
        foreach ($step in $script:Steps) {
            [string] $document = Join-Path $TestDrive (Split-Path -Path $step.Document -Leaf)
            [Collections.IDictionary] $declared = (Read-XmipTestYaml -Path $document).parameters
            [hashtable] $value = @{}
            foreach ($name in $declared.Keys) {
                if ($step.Value.ContainsKey($name)) {
                    $value[$name] = $step.Value[$name]
                }
            }
            [string] $file = Join-Path $TestDrive "$($step.Name).parameters.yaml"
            Write-XmipTestYaml -Path $file -Value @{ parameters = $value }
            [string] $json = dsc config --parameters-file $file get --file $document
            if ($LASTEXITCODE -ne 0) {
                throw "dsc could not evaluate the example's $($step.Name)."
            }
            foreach ($echo in ($json | ConvertFrom-Json -AsHashtable).results) {
                $output = $echo.result.actualState.output
                switch ($output.type) {
                    'Xmip.Environment/Machine' { $result[$step.Name] = $output.properties }
                    'Xmip.Environment/Slice' { $result["$($step.Name) slice"] = $output.properties }
                }
            }
        }
        return $result
    }

    if ($script:HasDsc) {
        $script:Parsed = @{}
        foreach ($name in $script:Document) {
            $script:Parsed[$name] = Read-XmipTestYaml -Path (Join-Path $script:Template $name)
        }
        $script:Evaluated = Invoke-EchoEnvironment
    }

    $script:Declared = InModuleScope Xmip { Read-XmipEssentialsCluster }
}

Describe 'The documents' {
    BeforeEach {
        if (-not $script:HasDsc) {
            Set-ItResult -Skipped -Because $script:NoDsc
        }
    }

    It 'parses <_> as YAML' -ForEach @('machine.dsc.yaml', 'names.dsc.yaml', 'node.dsc.yaml',
        'name.dsc.yaml', 'started.dsc.yaml') {
        $script:Parsed[$_] | Should -Not -BeNullOrEmpty
    }

    It 'declares in <_> every parameter it uses, and uses every one' -ForEach @(
        'machine.dsc.yaml', 'names.dsc.yaml', 'node.dsc.yaml', 'name.dsc.yaml',
        'started.dsc.yaml') {
        [string] $text = Get-Content -LiteralPath (Join-Path $script:Template $_) -Raw
        [string[]] $used = @(@([regex]::Matches($text, "parameters\('(\w+)'\)") |
            ForEach-Object { $_.Groups[1].Value }) + 'staging' | Sort-Object -Unique)
        [string[]] $declared = @(@($script:Parsed[$_].parameters.Keys) + 'staging' |
            Sort-Object -Unique)
        ($used -join ',') | Should -Be ($declared -join ',')
    }

    It 'requires DSC 3.4.0-preview.2 or newer in <_>' -ForEach @('machine.dsc.yaml',
        'names.dsc.yaml', 'node.dsc.yaml', 'name.dsc.yaml', 'started.dsc.yaml') {
        $script:Parsed[$_].directives.version | Should -Be '^3.4.0-preview.2'
    }

    It 'leaves elevation in <_> to each resource, never the whole document' -ForEach @(
        'machine.dsc.yaml', 'names.dsc.yaml', 'node.dsc.yaml', 'name.dsc.yaml',
        'started.dsc.yaml') {
        $script:Parsed[$_].directives.Contains('securityContext') | Should -BeFalse
    }

    It 'elevates exactly the methods of <Type> that need administrator rights' -ForEach @(
        @{ Type = 'Xmip.Environment/Machine'; Elevated = @() }
        @{ Type = 'Xmip.Environment/Slice'; Elevated = @() }
        @{ Type = 'Xmip.Environment/Started'; Elevated = @() }
        @{ Type = 'Xmip.Environment/Name'; Elevated = @('get', 'set', 'test') }
        @{ Type = 'Xmip.Node/Account'; Elevated = @('set') }
        @{ Type = 'Xmip.Node/File'; Elevated = @('get', 'set', 'test') }
        @{ Type = 'Xmip.Node/Opening'; Elevated = @('get', 'set', 'test') }
        @{ Type = 'Xmip.Node/Package'; Elevated = @('set') }
        @{ Type = 'Xmip.Node/Service'; Elevated = @('set') }
        @{ Type = 'Xmip.Node/Slice'; Elevated = @('get', 'set', 'test') }
    ) {
        [string] $file = ($Type -replace '^Xmip\.', 'xmip-' -replace '/', '-').ToLowerInvariant()
        [hashtable] $manifest = Read-XmipTestYaml -Path (
            Join-Path $script:Template "$file.dsc.resource.yaml")
        [string[]] $found = @('get', 'set', 'test' | Where-Object {
            $manifest[$_]['requireSecurityContext'] -eq 'elevated'
        })

        ($found -join ',') | Should -Be ($Elevated -join ',')
    }

    It 'uses no Windows PowerShell adapter' {
        foreach ($name in $script:Document) {
            [string] $text = Get-Content -LiteralPath (Join-Path $script:Template $name) -Raw
            $text | Should -Not -Match 'WindowsPowerShell' -Because "$name uses DSC's own"
        }
    }

    It 'finds every Xmip resource of the folder' {
        [string] $path = $env:PATH

        try {
            $env:PATH = "$script:Template$([System.IO.Path]::PathSeparator)$path"
            [string[]] $found = @(dsc resource list 'Xmip.*' | ConvertFrom-Json |
                ForEach-Object { $_.type } | Sort-Object)
        }
        finally {
            $env:PATH = $path
        }

        $found | Should -Be @('Xmip.Environment/Machine', 'Xmip.Environment/Name',
            'Xmip.Environment/Slice', 'Xmip.Environment/Started',
            'Xmip.Node/Account', 'Xmip.Node/File', 'Xmip.Node/Opening', 'Xmip.Node/Package',
            'Xmip.Node/Service', 'Xmip.Node/Slice')
    }
}

Describe 'The example environment' {
    BeforeEach {
        if (-not $script:HasDsc) {
            Set-ItResult -Skipped -Because $script:NoDsc
        }
    }

    It 'maps only nodes the Essentials''s cluster file declares' {
        $script:Nodes.Count | Should -Be 6
        foreach ($node in $script:Nodes.Keys) {
            $node | Should -BeIn $script:Declared.Nodes
        }
    }

    It 'gives the names every node machine''s address under the cluster''s name' {
        $names = $script:Evaluated['names']
        $names.document | Should -Be 'name.dsc.yaml'
        $names.name | Should -Be 'XMIP-DC01'
        [string[]] $addresses = @($script:Nodes.Values | ForEach-Object { $_.address } |
            Sort-Object)
        [string] $named = $script:Example['cluster']
        $cluster = $names.parameters.records | Where-Object { $_.name -eq $named }
        @($cluster.addresses | Sort-Object) | Should -Be $addresses
    }

    It 'gives each node machine its node, its files and its family''s package' {
        foreach ($node in $script:Nodes.Keys) {
            $machine = $script:Evaluated[$node]
            $machine.name | Should -Be $script:Nodes[$node].name
            $machine.document | Should -Be 'node.dsc.yaml'
            $machine.parameters.node | Should -Be $node
            $machine.parameters.family | Should -Be $script:Nodes[$node].family
            # The node is given its slice, signed here, and the authority's
            # certificate; never the cluster's file (ADR-0031, 2026-11-06).
            $machine.files.Keys | Should -Contain 'node.xmip'
            $machine.files.Keys | Should -Contain 'authority.pem'
            $machine.files.Keys | Should -Not -Contain 'cluster.xmip'
            $machine.files['node.xmip'] | Should -BeLike "**node.xmip"
            $machine.files['node.key'] | Should -BeLike "*$node*node.key"
            $machine.knownHosts | Should -Be 'known_hosts'
            [string] $tool = if ($machine.family -eq 'Linux') { 'dsc,pwsh' } else { '' }
            (@($machine.tools.Keys | Sort-Object) -join ',') | Should -Be $tool
            [string] $account = if ($machine.parameters.family -eq 'Windows') {
                "NT SERVICE\xmip-$node"
            }
            else {
                'xmip'
            }
            $machine.parameters.account | Should -Be $account
        }
    }

    It 'tells each node machine the far end and every node the Locations are placed over' {
        [string] $farEnd = $script:Example['far_end']
        $farEnd | Should -Not -BeNullOrEmpty
        [string[]] $mapped = @($script:Nodes.Keys | Sort-Object)

        foreach ($node in $script:Nodes.Keys) {
            $slice = $script:Evaluated["$node slice"]
            $slice.node | Should -Be $node
            $slice.bind | Should -Be $farEnd
            @($slice.nodes -split ',' | Sort-Object) | Should -Be $mapped
            $slice.authority | Should -Be $script:Example['authority']
            $slice.into | Should -BeLike "*$node"
        }
    }
}

Describe 'The Ansible role xmip_node' {
    BeforeAll {
        [string] $script:Tasks = Join-Path $script:Root 'deploy/dsc/ansible/roles/xmip_node/tasks'
        $script:Role = @{}
        foreach ($family in 'linux', 'windows') {
            $script:Role[$family] = @(Read-XmipTestYaml -Path (
                Join-Path $script:Tasks "$family.yml"))
        }
        [bool] $script:HasAnsible = $null -ne (
            Get-Command -Name ansible-playbook -ErrorAction SilentlyContinue)
    }

    It 'makes node.xmip on Linux the node account''s and root''s, mode 0640' {
        [object[]] $held = @($script:Role.linux | Where-Object {
            $_.Contains('ansible.builtin.file') -and
            $_['ansible.builtin.file'].path -like '*/node.xmip'
        })
        [object[]] $written = @($script:Role.linux | Where-Object {
            $_.Contains('ansible.builtin.copy') -and
            $_['ansible.builtin.copy'].dest -like '*/node.xmip'
        })

        $held.Count | Should -Be 1
        $written.Count | Should -Be 1
        foreach ($task in $held[0]['ansible.builtin.file'], $written[0]['ansible.builtin.copy']) {
            $task.owner | Should -Be '{{ xmip_account }}'
            $task.group | Should -Be 'root'
            $task.mode | Should -Be '0640'
        }
    }

    It 'makes node.xmip on Windows writable by the node''s account and the administrators alone' {
        $inheritance = $script:Role.windows | Where-Object {
            $_.Contains('ansible.windows.win_acl_inheritance') -and
            $_['ansible.windows.win_acl_inheritance'].path -like '*node.xmip'
        }
        $acl = $script:Role.windows | Where-Object {
            $_.Contains('ansible.windows.win_acl') -and
            $_['ansible.windows.win_acl'].path -like '*node.xmip'
        }

        $inheritance['ansible.windows.win_acl_inheritance'].state | Should -Be 'absent'
        @($acl.loop | ForEach-Object { "$($_.user)=$($_.rights)" }) | Should -Be @(
            'SYSTEM=FullControl', 'Administrators=FullControl', '{{ xmip_account }}=Modify')
    }

    It 'masks the node''s key on <_>, never logged or diffed' -ForEach 'linux', 'windows' {
        [object[]] $key = @($script:Role[$_] | Where-Object { $_.name -like '*key*' })

        $key.Count | Should -Be 1
        $key[0].no_log | Should -BeTrue
        $key[0].Contains('diff') | Should -BeTrue
        $key[0].diff | Should -BeFalse
        $key[0].vars.xmip_node_key | Should -Match 'register_secret'
        @($script:Role[$_] | Where-Object { "$($_['loop'])" -match 'node\.key' }) |
            Should -BeNullOrEmpty -Because 'the key is copied by its own task alone'
    }

    It 'names only modules the installed collections have, Hyper-V''s included' {
        if (-not $script:HasAnsible) {
            Set-ItResult -Skipped -Because ('SKIPPED: ansible-doc is not on PATH; ' +
                'deploy/dsc/README.md installs it')
            return
        }

        [string] $roles = Join-Path $script:Root 'deploy/dsc/ansible/roles'
        [string[]] $named = @(Get-ChildItem -LiteralPath $roles -Recurse -File -Filter '*.yml' |
            Select-String -Pattern '^\s+(?:- )?([a-z0-9_]+\.[a-z0-9_]+\.[a-z0-9_]+):\s*$' |
            ForEach-Object { $_.Matches[0].Groups[1].Value } | Sort-Object -Unique)
        [hashtable] $listed = & ansible-doc --list --json 2>$null | ConvertFrom-Json -AsHashtable
        [string[]] $known = @($listed.Keys)
        $named | Should -Contain 'microsoft.hyperv.hv_vm'
        $named | Should -Contain 'community.libvirt.virt'
        @($named | Where-Object { $_ -notin $known }) | Should -BeNullOrEmpty
    }

    It 'passes ansible-playbook <_> over the inventory each example writes' -ForEach @(
        '--syntax-check', '--list-tasks') {
        if (-not $script:HasAnsible) {
            Set-ItResult -Skipped -Because ('SKIPPED: ansible-playbook is not on PATH; ' +
                'deploy/dsc/README.md installs it')
            return
        }

        [string] $playbook = Join-Path $script:Root 'deploy/dsc/ansible/environment.yml'
        foreach ($example in 'libvirt', 'hyperv') {
            [string] $folder = Join-Path $TestDrive "ansible-$example"
            [string] $inventory = Write-XmipTestInventory -Environment (
                Read-XmipTestEnvironment -Path (
                    Join-Path $script:Root "deploy/dsc/$example.example.toml") -Folder (
                    $folder) -Technology 'ansible') -Run $folder
            [string[]] $said = @(& ansible-playbook $_ -i $inventory $playbook 2>&1)
            $LASTEXITCODE | Should -Be 0 -Because "$example`: $($said -join ' ')"
        }
    }
}

Describe 'The Xmip resources'' own steps' {
    It 'finds a file in place only once it holds its source''s bytes' {
        [string] $source = Join-Path $TestDrive 'source.xmip'
        Set-Content -LiteralPath $source -Value 'one'
        [string] $path = Join-Path $TestDrive 'config/cluster.xmip'
        [hashtable] $file = @{ path = $path; source = $source }

        (Get-NodeFileState -Instance $file)._exist | Should -BeFalse
        Set-NodeFile -Instance $file -Confirm:$false
        (Get-NodeFileState -Instance $file)._exist | Should -BeTrue
        Set-Content -LiteralPath $source -Value 'two'
        (Get-NodeFileState -Instance $file)._exist | Should -BeFalse
    }

    It 'places a file not private 0644, whatever the mode of its staged source' -Skip:$IsWindows {
        # The staging folder is the login's alone, its files 0600: a copy
        # keeping that mode left the authority's certificate unread by the node.
        [string] $source = Join-Path $TestDrive 'authority.pem'
        Set-Content -LiteralPath $source -Value 'authority'
        [IO.File]::SetUnixFileMode($source, [IO.UnixFileMode] 'UserRead, UserWrite')
        [hashtable] $file = @{ path = Join-Path $TestDrive 'authority/authority.pem'
            source = $source; private = $false }
        Set-NodeFile -Instance $file -Confirm:$false
        (Get-Item -LiteralPath $file.path).UnixMode | Should -Be '-rw-r--r--'
        (Get-NodeFileState -Instance $file)._exist | Should -BeTrue
        [IO.File]::SetUnixFileMode($file.path, [IO.UnixFileMode] 'UserRead, UserWrite')
        (Get-NodeFileState -Instance $file)._exist | Should -BeFalse
    }

    It 'opens the ports xmip-service --listening says, each once' {
        Mock -CommandName Invoke-DscProgram -MockWith {
            @('7401/tcp operate', '9100/tcp receive location orders', '7401/tcp again', 'noise')
        }
        [hashtable] $asked = @{ program = 'xmip-service'; configuration = 'node.xmip' }

        Get-NodeListening -Instance $asked | Should -Be @('7401/tcp', '9100/tcp')
    }

    It 'asks xmip-service here for the slice the environment''s authority signs, placed as given' {
        Mock -CommandName Invoke-DscProgram -MockWith { $Argument -join ' ' }
        [hashtable] $asked = @{
            program = 'xmip-service'; configuration = 'cluster.xmip'; node = 'n'; cluster = 'c'
            authority = 'keep'
        }

        [string] $asking = '--configuration cluster.xmip --node n --cluster c --authority keep'
        Get-EnvironmentSliced -Instance $asked | Should -Be "$asking --slice`n"
        $asked.bind = '10.77.0.1'
        $asked.nodes = 'n,m'
        Get-EnvironmentSliced -Instance $asked |
            Should -Be "$asking --bind 10.77.0.1 --nodes n,m --slice`n"
    }

    It 'keeps a slice whose signed text is the one there, so its node is shipped the same bytes' {
        # DSC asks set without a test first; a new signature each run would
        # replace node.xmip on the machine and restart its node every time.
        $script:Signature = 'a'
        Mock -CommandName Invoke-DscProgram -MockWith {
            "[service]`nnode_name = `"n`"`n[signature]`nvalue = `"$script:Signature`""
        }
        [string] $authority = Join-Path $TestDrive 'keep'
        New-Item -ItemType Directory -Force -Path $authority | Out-Null
        Set-Content -LiteralPath (Join-Path $authority 'authority.pem') -Value 'authority'
        [hashtable] $asked = @{ program = 'xmip-service'; configuration = 'cluster.xmip'
            node = 'n'; cluster = 'c'; authority = $authority; into = Join-Path $TestDrive 'n' }
        Set-EnvironmentSlice -Instance $asked -Confirm:$false
        [string] $slice = Join-Path $TestDrive 'n/node.xmip'
        [string] $first = Get-Content -LiteralPath $slice -Raw
        $script:Signature = 'b'
        Set-EnvironmentSlice -Instance $asked -Confirm:$false
        Get-Content -LiteralPath $slice -Raw | Should -BeExactly $first
        Mock -CommandName Invoke-DscProgram -MockWith {
            "[service]`nnode_name = `"m`"`n[signature]`nvalue = `"c`""
        }
        Set-EnvironmentSlice -Instance $asked -Confirm:$false
        Get-Content -LiteralPath $slice -Raw | Should -BeLike "*node_name = `"m`"*"
    }

    It 'compares a signed slice by the text it signs, the same however often it is signed' {
        [string] $text = "[service]`nnode_name = `"n`"`n"
        foreach ($value in 'a', 'b') {
            Get-EnvironmentSignedText -Slice "$text[signature]`nvalue = `"$value`"`n" |
                Should -BeExactly $text
        }
        Get-EnvironmentSignedText -Slice $text | Should -BeExactly $text
    }

    It 'places the node''s shipped slice and its authority''s certificate, then finds them' {
        # Who may write it is the next tests'; here it is as wanted once set.
        Mock -CommandName Test-NodePackage -MockWith { $false }
        Mock -CommandName Set-NodeSliceAccess -MockWith { $script:AccessSet = $true }
        Mock -CommandName Get-NodeSliceAccess -MockWith {
            if ($script:AccessSet) {
                @(Get-NodeSliceWanted -Account 'NT SERVICE\xmip-n')
            }
        }
        $script:AccessSet = $false
        [string] $shipped = Join-Path $TestDrive 'files'
        New-Item -ItemType Directory -Force -Path $shipped | Out-Null
        Set-Content -LiteralPath (Join-Path $shipped 'node.xmip') -Value 'slice'
        Set-Content -LiteralPath (Join-Path $shipped 'authority.pem') -Value 'certificate'
        [hashtable] $slice = @{
            configuration = Join-Path $TestDrive 'config'
            source        = Join-Path $shipped 'node.xmip'
            certificate   = Join-Path $shipped 'authority.pem'
            node          = 'n'
            account       = 'NT SERVICE\xmip-n'
        }

        Test-NodeSlice -Instance $slice | Should -BeFalse
        Set-NodeSlice -Instance $slice -Confirm:$false
        Test-NodeSlice -Instance $slice | Should -BeTrue
        Join-Path $TestDrive 'config/authority/authority.pem' | Should -Exist
        Should -Invoke -CommandName Set-NodeSliceAccess -Times 1 -ParameterFilter {
            $Account -eq 'NT SERVICE\xmip-n' -and $Path -like '*node.xmip'
        }

        # Its bytes in place and its access list another: out of desired state.
        $script:AccessSet = $false
        Test-NodeSlice -Instance $slice | Should -BeFalse
    }

    It 'hands the slice its node''s account in node.dsc.yaml' {
        if (-not $script:HasDsc) {
            Set-ItResult -Skipped -Because $script:NoDsc
            return
        }

        $slice = $script:Parsed['node.dsc.yaml'].resources | Where-Object {
            $_.type -eq 'Xmip.Node/Slice'
        }
        $slice.properties.account | Should -Be "[parameters('account')]"
    }

    It 'computes a virtual account''s SID as Windows does, before its service exists' {
        if (-not $IsWindows) {
            Set-ItResult -Skipped -Because 'SKIPPED: a virtual account is Windows'' alone'
            return
        }

        [string] $named = 'NT SERVICE\TrustedInstaller'
        [string] $windows = [System.Security.Principal.NTAccount]::new($named).Translate(
            [System.Security.Principal.SecurityIdentifier]).Value

        Get-NodeAccountSid -Account $named | Should -Be $windows
        Get-NodeAccountSid -Account 'NT SERVICE\xmip-no-such-node' |
            Should -Match '^S-1-5-80(-\d+){5}$'
    }

    It 'makes node.xmip the node''s alone to write, and finds it so' {
        if (-not $IsWindows) {
            Set-ItResult -Skipped -Because ('SKIPPED: on Linux the slice is chowned to the ' +
                'node''s account, which needs root')
            return
        }

        # Unelevated: the file's owner may set its access list, and read it.
        [string] $path = Join-Path $TestDrive 'access/node.xmip'
        New-Item -ItemType Directory -Force -Path (Split-Path -Path $path) | Out-Null
        Set-Content -LiteralPath $path -Value 'slice'
        [string] $account = 'NT SERVICE\xmip-n'
        [string] $wanted = @(Get-NodeSliceWanted -Account $account) -join ','

        (@(Get-NodeSliceAccess -Path $path) -join ',') | Should -Not -Be $wanted

        try {
            Set-NodeSliceAccess -Path $path -Account $account -Confirm:$false
            (@(Get-NodeSliceAccess -Path $path) -join ',') | Should -Be $wanted
        }
        finally {
            # Inheritance given back, so Pester may remove its drive.
            $open = [System.Security.AccessControl.FileSecurity]::new()
            $open.SetAccessRuleProtection($false, $false)
            [System.IO.FileSystemAclExtensions]::SetAccessControl(
                [System.IO.FileInfo]::new($path), $open)
        }
    }

    It 'stages a machine''s files in a folder of the machine''s own' {
        Get-EnvironmentStaging -Family Windows | Should -Be 'C:\ProgramData\Xmip\environment'
        Get-EnvironmentStaging -Family Linux | Should -Be '/var/tmp/xmip-environment'
    }

    It 'keeps nothing a node is given in the staging folder once dsc ran, in one this login owns' {
        $script:Said = [Collections.Generic.List[string]]::new()
        function Invoke-EnvironmentSsh {
            param([hashtable] $Instance, [string] $Command, [string] $Trace)
            $script:Said.Add($Command)
            if ($Command -like '*dsc config*') {
                '{"results":[]}'
            }
        }
        function Send-EnvironmentFile { param($Instance, $File, $Folder) }
        function Install-EnvironmentTool { param($Instance, $Staging) '/s/tools/dsc' }
        [hashtable] $instance = @{ name = 'XMIP-IN01'; document = 'node.dsc.yaml'
            files = [ordered] @{ 'node.key' = 'node.key' } }
        [hashtable] $asked = @{ Instance = $instance; Operation = 'test'; Staging = '/s'
            Parameters = 'parameters.yaml' }
        Invoke-EnvironmentSshDocument @asked | Out-Null
        # Made 0700, and refused where another account owns it.
        $script:Said[0] | Should -BeLike "mkdir -p -m 0700 '/s' && { ``[ -O '/s' ``]*exit 3*"
        $script:Said[0] | Should -BeLike "*chmod 0700 '/s'/files"
        # The node's files read by this login and root alone, and removed whatever dsc said.
        $script:Said[1] | Should -BeLike "chmod -R go-rwx '/s/files' && sudo env *dsc config*"
        $script:Said[1] | Should -BeLike "*; status=`$?; rm -rf -- '/s/files'; exit `$status"
    }

    It 'reaches an AlmaLinux machine with its key and known_hosts, checked strictly' {
        [string[]] $option = Get-EnvironmentSshOption -Instance @{
            keyPath = 'state/ssh/id_ed25519'; knownHosts = 'state/known_hosts' }
        ($option -join ' ') | Should -Be ('-i state/ssh/id_ed25519 -o ' +
            'UserKnownHostsFile=state/known_hosts -o StrictHostKeyChecking=yes ' +
            '-o BatchMode=yes -o ConnectTimeout=10')
    }

    It 'brings DSC to a machine only from a tarball whose SHA-256 is the one named' {
        [string] $tarball = Join-Path $TestDrive 'pwsh.tar.gz'
        Set-Content -LiteralPath $tarball -Value 'not the release'
        $script:Reached = $false
        function ssh { $script:Reached = $true }
        function scp { $script:Reached = $true }
        [hashtable] $instance = @{ name = 'XMIP-IN01'; address = '10.77.0.61'; login = 'a'
            keyPath = 'k'; knownHosts = 'h'
            tools = @{ pwsh = @{ path = $tarball; sha256 = ('0' * 64) } } }
        { Install-EnvironmentTool -Instance $instance -Staging '/var/tmp/xmip-environment' } |
            Should -Throw "REFUSED: $tarball has SHA-256 *, not $('0' * 64)."
        $script:Reached | Should -BeFalse -Because 'nothing is sent before the check'
    }

    It 'names in node.dsc.yaml no resource one family lacks, so DSC runs it on both' {
        [object[]] $resources = (Read-XmipTestYaml -Path (
                Join-Path $script:Template 'node.dsc.yaml')).resources
        [string[]] $types = @($resources | ForEach-Object { $_.type })
        @($types | Where-Object { $_ -notlike 'Xmip.*' }) | Should -BeNullOrEmpty
    }

    It 'answers the openings absent, never refused, before the package is installed' {
        [hashtable] $state = Get-NodeMachineState -Kind 'Opening' -Instance @{
            program = (Join-Path $TestDrive 'no-such-xmip-service'); node = 'n'
            configuration = 'node.xmip' }
        $state._exist | Should -BeFalse
        @($state.ports).Count | Should -Be 0
    }

    It 'finds an .rpm installed only where it is the one shipped, by its header' -Skip:$IsWindows {
        function Test-NodeRegistered { param($Node) $true }
        $script:Header = @{ Shipped = 'aa'; Installed = 'bb' }
        function rpm {
            $global:LASTEXITCODE = 0
            if ($args[0] -eq '-qp') { $script:Header.Shipped } else { $script:Header.Installed }
        }
        [hashtable] $package = @{ node = 'n'; path = 'xmip.rpm' }
        Test-NodePackage -Instance $package | Should -BeFalse -Because 'a build made again'
        $script:Header.Installed = 'aa'
        Test-NodePackage -Instance $package | Should -BeTrue
    }

    It 'installs an .rpm with dnf, and over another build with rpm''s upgrade' -Skip:$IsWindows {
        $script:Ran = [Collections.Generic.List[string]]::new()
        $script:Installed = ''
        function rpm {
            $script:Ran.Add("rpm $($args -join ' ')")
            [bool] $none = $args[0] -eq '-q' -and -not $script:Installed
            $global:LASTEXITCODE = if ($none) { 1 } else { 0 }
            if ($args[0] -eq '-q') { $script:Installed }
        }
        function dnf { $script:Ran.Add("dnf $($args -join ' ')"); $global:LASTEXITCODE = 0 }
        [hashtable] $package = @{ node = 'n'; path = 'xmip.rpm'; cluster = 'c'; account = 'xmip' }
        Install-NodePackage -Instance $package -Confirm:$false
        $script:Installed = 'aa'
        Install-NodePackage -Instance $package -Confirm:$false
        @($script:Ran | Where-Object { $_ -notlike 'rpm -q *' }) |
            Should -Be @('dnf install --assumeyes xmip.rpm',
                'rpm --upgrade --replacepkgs --replacefiles xmip.rpm')
    }

    It 'quotes every value it hands the machine''s shell as one word' {
        ConvertTo-EnvironmentShellWord -Value "it's /var/tmp" | Should -Be "'it'\''s /var/tmp'"
    }
}
