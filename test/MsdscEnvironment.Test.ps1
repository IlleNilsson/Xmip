#requires -PSEdition Core
#requires -Version 7.6.7

<#
    The environment templates (deploy/dsc/msdsc/environment and
    deploy/dsc/ansible; ADR-0015, amendment 2026-10-21) without the
    machines: what can be held on any machine, unelevated.

    - The Microsoft DSC v3 documents and the example parameters parse as
      YAML, read by DSC itself; each document declares every parameter it
      uses and uses every one it declares — but staging, which
      Xmip.Environment/Machine gives every document it applies.
    - The resource manifests of the folder are found by DSC.
    - The example environment runs through DSC with every resource replaced
      by Microsoft.DSC.Debug/Echo: the names are given every node machine's
      address, each node machine is given its node's files and values, the
      mapping of nodes onto machines is the Ansible inventory's, and every
      node mapped is one the Playground's cluster file declares.
    - The Xmip resources' own steps that touch nothing but a folder:
      a file in place, the ports a configuration listens on, the staging
      folder.

    The machines themselves are proved by running the templates:
    deploy/dsc/msdsc/environment/README.md and deploy/dsc/ansible/README.md.

    Style: doc/governance/powershell-style.md
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    [string] $script:Template = Join-Path $script:Root 'deploy/dsc/msdsc/environment'
    foreach ($part in 'NodeMachine.ps1', 'NodeFile.ps1', 'NodeOpening.ps1',
        'EnvironmentMachine.ps1') {
        . (Join-Path $script:Template $part)
    }
    [bool] $script:HasDsc = $null -ne (Get-Command -Name dsc -ErrorAction SilentlyContinue)
    [string] $script:NoDsc = 'dsc (Microsoft DSC v3) is not on PATH; README.md installs it'
    [string[]] $script:Document = @('environment.example.dsc.yaml', 'machine.dsc.yaml',
        'node.dsc.yaml', 'name.dsc.yaml')

    # A YAML file as DSC reads it: Echo hands its input back as JSON, and an
    # expression in a resource's input is not evaluated.
    function Read-DscYaml {
        param(
            [Parameter(Mandatory = $true)]
            [string] $Path
        )

        # A YAML document's start marker is no line of a mapping's value.
        [string[]] $lines = @(Get-Content -LiteralPath $Path | Where-Object { $_ -ne '---' } |
            ForEach-Object { "  $_" })
        [string] $echo = "output:`n" + ($lines -join "`n")
        [string] $json = dsc resource get --resource Microsoft.DSC.Debug/Echo --input $echo
        if ($LASTEXITCODE -ne 0) {
            throw "dsc could not read $Path as YAML."
        }
        return ($json | ConvertFrom-Json -AsHashtable).actualState.output
    }

    # A copy of a document, as JSON, whose every instance is an Echo of its
    # type and properties, its condition kept, so evaluating it changes
    # nothing; an Include names the copy of the file it includes.
    function Write-EchoDocument {
        param(
            [Parameter(Mandatory = $true)]
            [string] $Name
        )

        [hashtable] $document = Read-DscYaml -Path (Join-Path $script:Template $Name)
        $document.Remove('directives')
        $document.resources = @($document.resources | ForEach-Object {
            if ($_.type -eq 'Microsoft.DSC/Include') {
                $_.Remove('dependsOn')
                $_
            }
            else {
                [hashtable] $output = @{ type = $_.type; properties = $_.properties }
                [hashtable] $echo = @{ name = $_.name; type = 'Microsoft.DSC.Debug/Echo'
                    properties = @{ output = $output } }
                if ($_.Contains('condition')) {
                    $echo.condition = $_.condition
                }
                $echo
            }
        })
        $document | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath (Join-Path $TestDrive $Name)
    }

    # The example environment evaluated: each instance's Echo by name, an
    # Include's beneath it.
    function Invoke-EchoEnvironment {
        foreach ($name in $script:Document) {
            Write-EchoDocument -Name $name
        }
        [hashtable] $parameters = Read-DscYaml -Path (
            Join-Path $script:Template 'environment.example.parameters.yaml')
        $parameters.parameters.common.template = [string] $TestDrive
        $parameters.parameters.common.linuxAccount = 'account'
        [string] $file = Join-Path $TestDrive 'parameters.json'
        $parameters | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $file
        [string] $environment = Join-Path $TestDrive 'environment.example.dsc.yaml'
        [string] $json = dsc config --parameters-file $file get --file $environment
        if ($LASTEXITCODE -ne 0) {
            throw 'dsc could not evaluate the example environment.'
        }
        [hashtable] $result = @{}
        foreach ($instance in ($json | ConvertFrom-Json -AsHashtable).results) {
            $result[$instance.name] = if ($instance.type -eq 'Microsoft.DSC/Include') {
                $instance.result[0].result.actualState.output.properties
            }
            else {
                $instance.result.actualState.output.properties
            }
        }
        return $result
    }

    if ($script:HasDsc) {
        $script:Parsed = @{}
        foreach ($name in $script:Document + 'environment.example.parameters.yaml') {
            $script:Parsed[$name] = Read-DscYaml -Path (Join-Path $script:Template $name)
        }
        $script:Evaluated = Invoke-EchoEnvironment
        $script:Nodes = $script:Parsed['environment.example.parameters.yaml'].parameters.nodes
        [hashtable] $inventory = Read-DscYaml -Path (
            Join-Path $script:Root 'deploy/dsc/ansible/inventory.example.yml')
        $script:Inventory = $inventory.all.children.xmip_nodes.hosts
    }

    $script:Declared = InModuleScope Xmip { Read-XmipPlaygroundCluster }
}

Describe 'The documents' {
    BeforeEach {
        if (-not $script:HasDsc) {
            Set-ItResult -Skipped -Because $script:NoDsc
        }
    }

    It 'parses <_> as YAML' -ForEach @('environment.example.dsc.yaml', 'machine.dsc.yaml',
        'node.dsc.yaml', 'name.dsc.yaml', 'environment.example.parameters.yaml') {
        $script:Parsed[$_] | Should -Not -BeNullOrEmpty
    }

    It 'declares in <_> every parameter it uses, and uses every one' -ForEach @(
        'environment.example.dsc.yaml', 'machine.dsc.yaml', 'node.dsc.yaml', 'name.dsc.yaml') {
        [string] $text = Get-Content -LiteralPath (Join-Path $script:Template $_) -Raw
        [string[]] $used = @(@([regex]::Matches($text, "parameters\('(\w+)'\)") |
            ForEach-Object { $_.Groups[1].Value }) + 'staging' | Sort-Object -Unique)
        [string[]] $declared = @(@($script:Parsed[$_].parameters.Keys) + 'staging' |
            Sort-Object -Unique)
        ($used -join ',') | Should -Be ($declared -join ',')
    }

    It 'requires DSC 3.2 or newer in <_>' -ForEach @('environment.example.dsc.yaml',
        'machine.dsc.yaml', 'node.dsc.yaml', 'name.dsc.yaml') {
        $script:Parsed[$_].directives.version | Should -Be '^3.2'
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

    It 'maps only nodes the Playground''s cluster file declares' {
        foreach ($node in $script:Nodes.Keys) {
            $node | Should -BeIn $script:Declared.Nodes
        }
    }

    It 'maps the nodes onto the machines as the Ansible inventory does' {
        foreach ($machine in $script:Inventory.Keys) {
            [string] $node = $script:Inventory[$machine].xmip_node_name
            $script:Nodes[$node].name | Should -Be $machine
            $script:Nodes[$node].address | Should -Be $script:Inventory[$machine].ansible_host
        }
        $script:Inventory.Count | Should -Be $script:Nodes.Count
    }

    It 'gives the names every node machine''s address under the cluster''s name' {
        $names = $script:Evaluated['Names']
        $names.document | Should -Be 'name.dsc.yaml'
        [string[]] $addresses = @($script:Nodes.Values | ForEach-Object { $_.address } |
            Sort-Object)
        $example = $script:Parsed['environment.example.parameters.yaml']
        [string] $named = $example.parameters.common.cluster
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
            $machine.files.Keys | Should -Contain 'xmip.toml'
            $machine.files['node.key'] | Should -BeLike "*$node*node.key"
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
        $example = $script:Parsed['environment.example.parameters.yaml']
        [string] $farEnd = $example.parameters.common.farEnd
        $farEnd | Should -Not -BeNullOrEmpty
        [string[]] $mapped = @($script:Nodes.Keys | Sort-Object)

        foreach ($node in $script:Nodes.Keys) {
            $machine = $script:Evaluated[$node]
            $machine.parameters.bind | Should -Be $farEnd
            @($machine.parameters.placed -split ',' | Sort-Object) | Should -Be $mapped
        }
    }
}

Describe 'The Xmip resources'' own steps' {
    It 'finds a file in place only once it holds its source''s bytes' {
        [string] $source = Join-Path $TestDrive 'source.toml'
        Set-Content -LiteralPath $source -Value 'one'
        [hashtable] $file = @{ path = (Join-Path $TestDrive 'config/xmip.toml'); source = $source }

        (Get-NodeFileState -Instance $file)._exist | Should -BeFalse
        Set-NodeFile -Instance $file -Confirm:$false
        (Get-NodeFileState -Instance $file)._exist | Should -BeTrue
        Set-Content -LiteralPath $source -Value 'two'
        (Get-NodeFileState -Instance $file)._exist | Should -BeFalse
    }

    It 'opens the ports xmip-service --listening says, each once' {
        Mock -CommandName Invoke-NodeProgram -MockWith {
            @('7401/tcp operate', '9100/tcp receive location orders', '7401/tcp again', 'noise')
        }
        [hashtable] $asked = @{ program = 'xmip-service'; configuration = 'xmip-node.toml' }

        Get-NodeListening -Instance $asked | Should -Be @('7401/tcp', '9100/tcp')
    }

    It 'asks xmip-service for the slice with the far end and the nodes, where given' {
        Mock -CommandName Invoke-NodeProgram -MockWith { $Argument -join ' ' }
        [hashtable] $asked = @{
            program = 'xmip-service'; configuration = 'xmip.toml'; node = 'n'; cluster = 'c'
        }

        Get-NodeSliced -Instance $asked |
            Should -Be '--configuration xmip.toml --node n --cluster c --slice'
        $asked.bind = '10.77.0.1'
        $asked.nodes = 'n,m'
        Get-NodeSliced -Instance $asked | Should -Be ('--configuration xmip.toml --node n ' +
            '--cluster c --bind 10.77.0.1 --nodes n,m --slice')
    }

    It 'stages a machine''s files in a folder of the machine''s own' {
        Get-EnvironmentStaging -Family Windows | Should -Be 'C:\ProgramData\Xmip\environment'
        Get-EnvironmentStaging -Family Linux | Should -Be '/var/tmp/xmip-environment'
    }
}
