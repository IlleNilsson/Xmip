#requires -PSEdition Core
#requires -Version 7.7.0

<#
    The Microsoft DSC v3 template for Hyper-V (deploy/dsc/msdsc/hyperv)
    without Hyper-V: what can be held on any machine, unelevated.

    - The documents and the example parameters parse as YAML, read by the
      module's YAML reader and evaluated by DSC below; each document
      declares every parameter it uses and uses every one it declares, and
      depends only on its own instances.
    - The example environment runs through DSC with every resource replaced
      by Microsoft.DSC.Debug/Echo: each machine gets every value its
      document asks for, and is the machine README.md's table names.
    - The install answers: a Windows machine's autounattend.xml parses,
      names its computer and image and holds no plain-text password; an
      AlmaLinux machine's kickstart gives its host name, static address and
      key; the answer medium is an ISO with the label its installer reads.
    - The hardware and installation steps, with every Hyper-V command a stub.

    The VMs themselves are proved by running the template:
    deploy/dsc/msdsc/hyperv/README.md.

    Style: doc/governance/powershell-style.md
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    [string] $script:Template = Join-Path $script:Root 'deploy/dsc/msdsc/hyperv'
    . (Join-Path $script:Template 'HyperVMachine.ps1')
    [bool] $script:HasDsc = $null -ne (Get-Command -Name dsc -ErrorAction SilentlyContinue)
    [string] $script:NoDsc = 'dsc (Microsoft DSC v3) is not on PATH; README.md installs it'
    [string[]] $script:Document = @('network.dsc.yaml', 'machine.dsc.yaml')
    [string] $script:ExamplePath = Join-Path $script:Template 'environment.example.toml'


    # A copy of a document, in YAML, whose every instance is an Echo of its
    # properties, so evaluating it changes nothing.
    function Write-EchoDocument {
        param(
            [Parameter(Mandatory = $true)]
            [string] $Name
        )

        [hashtable] $document = Read-XmipTestYaml -Path (Join-Path $script:Template $Name)
        # The elevated security context is the real run's; an Echo needs none.
        $document.Remove('directives')
        $document.resources = @(foreach ($instance in $document.resources) {
            [hashtable] $output = @{ type = $instance.type; properties = $instance.properties }
            @{ name = $instance.name; type = 'Microsoft.DSC.Debug/Echo'
                properties = @{ output = $output } }
        })
        Write-XmipTestYaml -Path (Join-Path $TestDrive $Name) -Value $document
    }

    # The example environment as Deploy-XmipEnvironment applies it, one
    # document per step with the parameters it declares, each evaluated by
    # DSC as Echoes: each step's Echo results by instance name.
    function Invoke-EchoEnvironment {
        foreach ($name in $script:Document) {
            Write-EchoDocument -Name $name
        }
        [hashtable[]] $steps = @(InModuleScope Xmip -Parameters @{
            Path = $script:ExamplePath; Template = [string] $TestDrive
        } {
            param($Path, $Template)
            $environment = Read-XmipToml -Path $Path
            $environment['linux_account'] = 'account'
            Get-XmipDeployStep -Environment $environment -Template $Template
        })
        [hashtable] $result = @{}
        foreach ($step in $steps) {
            [Collections.IDictionary] $declared = (
                Read-XmipTestYaml -Path $step.Document).parameters
            [hashtable] $value = @{}
            foreach ($name in $declared.Keys) {
                $value[$name] = $step.Value[$name]
            }
            [string] $file = Join-Path $TestDrive "$($step.Name).parameters.yaml"
            Write-XmipTestYaml -Path $file -Value @{ parameters = $value }
            [string] $json = dsc config --parameters-file $file get --file $step.Document
            if ($LASTEXITCODE -ne 0) {
                throw "dsc could not evaluate the example's $($step.Name)."
            }
            [hashtable] $instance = @{}
            foreach ($echo in ($json | ConvertFrom-Json -AsHashtable).results) {
                $instance[$echo.name] = $echo.result.actualState.output
            }
            $result[$step.Name] = $instance
        }
        return $result
    }

    if ($script:HasDsc) {
        $script:Parsed = @{}
        foreach ($name in $script:Document) {
            $script:Parsed[$name] = Read-XmipTestYaml -Path (Join-Path $script:Template $name)
        }
        $script:Example = InModuleScope Xmip -Parameters @{ Path = $script:ExamplePath } {
            param($Path)
            Read-XmipToml -Path $Path
        }
        $script:Evaluated = Invoke-EchoEnvironment
        $script:Machine = @($script:Evaluated.Keys | Where-Object { $_ -ne 'network' } |
            Sort-Object | ForEach-Object {
                [pscustomobject] $script:Evaluated[$_]['Installation'].properties.input
            })
    }
}

Describe 'The documents' {
    BeforeEach {
        if (-not $script:HasDsc) {
            Set-ItResult -Skipped -Because $script:NoDsc
        }
    }

    It 'parses <_> as YAML' -ForEach @('network.dsc.yaml', 'machine.dsc.yaml') {
        $script:Parsed[$_] | Should -Not -BeNullOrEmpty
    }

    It 'declares in <_> every parameter it uses, and uses every one' -ForEach @(
        'network.dsc.yaml', 'machine.dsc.yaml') {
        [string] $text = Get-Content -LiteralPath (Join-Path $script:Template $_) -Raw
        [string[]] $used = @([regex]::Matches($text, "parameters\('(\w+)'\)") |
            ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        [string[]] $declared = @($script:Parsed[$_].parameters.Keys | Sort-Object)
        ($used -join ',') | Should -Be ($declared -join ',')
    }

    It 'requires DSC 3.4.0-preview.2 or newer in <_>, elevated' -ForEach @(
        'network.dsc.yaml', 'machine.dsc.yaml') {
        # Its resources are adapted, HyperVDsc's, and state no context of
        # their own, so the document does.
        $script:Parsed[$_].directives.version | Should -Be '^3.4.0-preview.2'
        $script:Parsed[$_].directives.securityContext | Should -Be 'elevated'
    }

    It 'depends in <_> only on its own instances' -ForEach @(
        'network.dsc.yaml', 'machine.dsc.yaml') {
        [object[]] $resources = $script:Parsed[$_].resources
        [string[]] $own = @($resources | ForEach-Object { "$($_.type)|$($_.name)" })
        [string[]] $named = @($resources | Where-Object { $_.Contains('dependsOn') } |
            ForEach-Object { $_.dependsOn } | ForEach-Object {
                $_ -replace "^\[resourceId\('([^']+)', '([^']+)'\)\]$", '$1|$2'
            })
        $named | Where-Object { $_ -notin $own } | Should -BeNullOrEmpty
    }
}

Describe 'The example environment' {
    BeforeEach {
        if (-not $script:HasDsc) {
            Set-ItResult -Skipped -Because $script:NoDsc
        }
    }

    It 'gives the network every value it asks for' {
        [hashtable] $network = $script:Evaluated['network']
        $network['Switch'].properties.Name | Should -Be 'Xmip'
        $network['Gateway'].properties.IPAddress | Should -Be @('10.77.0.1/24')
        $network['Nat'].properties.input.prefix | Should -Be '10.77.0.0/24'
    }

    It 'gives each machine a VM of its own values' {
        [string] $root = $script:Example['root']
        foreach ($machine in $script:Machine) {
            [hashtable] $vm = $script:Evaluated[$machine.name]
            # DSC's path() joins with a backslash on Windows.
            [string] $directory = "$root\$($machine.name)"
            $vm['Virtual machine'].properties.VhdPath | Should -Be "$directory\os.vhdx"
            $vm['Virtual machine'].properties.Name | Should -Be $machine.name
            $vm['Disk'].properties.Path | Should -Be $directory
            $vm['Hardware'].properties.input.image.family | Should -Be $machine.image.family
        }
    }

    It 'has unique names, addresses and MACs, every address on the network' {
        # ForEach-Object, not .address: an array's .Address is its own method.
        [string[]] $addresses = @($script:Machine | ForEach-Object { $_.address })
        [string[]] $macs = @($addresses | ForEach-Object {
            Get-MachineMacAddress -Address $_ -Prefix '00155D' })
        $script:Machine.Count | Should -Be 10
        @($script:Machine | ForEach-Object { $_.name } | Sort-Object -Unique).Count |
            Should -Be 10
        @($addresses | Sort-Object -Unique).Count | Should -Be 10
        @($macs | Sort-Object -Unique).Count | Should -Be 10
        [string] $prefix = $script:Example['network']['prefix']
        [string] $mask = Get-MachineNetmask -PrefixLength ([int] ($prefix -replace '^.*/', ''))
        [uint32] $want = ([ipaddress] ($prefix -replace '/.*$')).Address
        $addresses | Where-Object {
            (([ipaddress] $_).Address -band ([ipaddress] $mask).Address) -ne $want
        } | Should -BeNullOrEmpty
    }

    It 'is the environment README.md names' {
        [string] $readme = Get-Content -LiteralPath (Join-Path $script:Template 'README.md') -Raw
        [string[]] $rows = @([regex]::Matches($readme, '(?m)^\| (XMIP-\S+) \|.*\| (\S+) \|$') |
            ForEach-Object { "$($_.Groups[1].Value) $($_.Groups[2].Value)" } | Sort-Object)
        [string[]] $machines = @($script:Machine |
            ForEach-Object { "$($_.name) $($_.address)" } | Sort-Object)
        ($rows -join ',') | Should -Be ($machines -join ',')
    }
}

Describe 'The install answers' {
    BeforeEach {
        if (-not $script:HasDsc) {
            Set-ItResult -Skipped -Because $script:NoDsc
        }
    }

    It 'gives each Windows machine an autounattend.xml that names it and hides its password' {
        [securestring] $password = ConvertTo-SecureString -String 'Pa55word' -AsPlainText -Force
        foreach ($machine in @($script:Machine | Where-Object { $_.image.family -eq 'Windows' })) {
            [string] $text = Get-MachineWindowsAnswer -Machine $machine -AdministratorPassword (
                $password)
            [xml] $answer = $text
            $answer.unattend | Should -Not -BeNullOrEmpty
            $text | Should -Match "<ComputerName>$($machine.name)</ComputerName>"
            $text | Should -Match "<Value>$([regex]::Escape($machine.image.edition))</Value>"
            $text | Should -Not -Match 'Pa55word'
            $text | Should -Match '<PlainText>false</PlainText>'
            $text | Should -Not -Match "`r"
        }
    }

    It 'gives each AlmaLinux machine a kickstart with its host name, address and key' {
        [string] $key = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDummyKeyForTheTestOnly'
        foreach ($machine in @($script:Machine | Where-Object { $_.image.family -eq 'Linux' })) {
            [string] $raw = Get-MachineMacAddress -Address $machine.address -Prefix '00155D'
            [hashtable] $asked = @{
                Machine = $machine
                PublicKey = $key
                MacAddress = $raw
                GuestPackage = 'hyperv-daemons'
            }
            [string] $kickstart = Get-MachineKickstart @asked
            [string] $mac = $raw -replace '(..)(?!$)', '$1:'
            $kickstart | Should -Match '(?m)^hyperv-daemons$'
            [string] $hostName = "$($machine.name.ToLowerInvariant()).xmip.test"
            $kickstart | Should -Match "--device=$mac --bootproto=static --ip=$($machine.address) "
            $kickstart | Should -Match '--netmask=255\.255\.255\.0 --gateway=10\.77\.0\.1 '
            $kickstart | Should -Match "--hostname=$([regex]::Escape($hostName)) "
            $kickstart | Should -Match ([regex]::Escape("sshkey --username=account `"$key`""))
            $kickstart | Should -Not -Match "`r"
        }
    }

    It 'writes an answer medium with the label <Label>' -ForEach @(
        @{ Label = 'XMIP'; File = 'autounattend.xml' }
        @{ Label = 'OEMDRV'; File = 'ks.cfg' }
    ) {
        if (-not $IsWindows) {
            Set-ItResult -Skipped -Because 'the image mastering API is Windows''s'
        }
        [string] $path = Join-Path $TestDrive "$Label.iso"
        [hashtable] $medium = @{ Label = $Label; File = [ordered] @{ $File = "answer`n" } }
        New-MachineAnswerMedium -Path $path -Medium $medium -Confirm:$false
        [byte[]] $bytes = [IO.File]::ReadAllBytes($path)
        # The primary volume descriptor is at 0x8000; its volume name at 40.
        [Text.Encoding]::ASCII.GetString($bytes, 0x8028, 32).Trim() | Should -Be $Label
    }
}

Describe 'The hardware and the installation, Hyper-V stubbed' {
    BeforeAll {
        # Windows 11's values: Secure Boot template and a TPM.
        $script:Stubbed = [pscustomobject] @{
            name = 'XMIP-DEV01'
            address = '10.77.0.30'
            directory = [string] $TestDrive
            image = @{ family = 'Windows'; secureBootTemplate = 'MicrosoftWindows'; tpm = $true }
        }
        $script:State = 'Off'
        $script:Order = @(0, 1, 2)
        function Get-VM {
            param([string] $Name)
            [pscustomobject] @{ Name = $Name; State = $script:State }
        }
        function Get-VMNetworkAdapter {
            param([string] $VMName)
            [pscustomobject] @{ MacAddress = '00155D4D001E' }
        }
        function Get-VMSecurity {
            param([string] $VMName)
            [pscustomobject] @{ TpmEnabled = $true }
        }
        function Get-VMFirmware {
            param([string] $VMName)
            [pscustomobject] @{
                SecureBoot = 'On'
                SecureBootTemplate = 'MicrosoftWindows'
                BootOrder = @($script:Order | ForEach-Object {
                    [pscustomobject] @{
                        BootType = 'Drive'
                        Device = [pscustomobject] @{ ControllerLocation = $_ }
                    }
                })
            }
        }
    }

    It 'finds nothing to change in hardware that is as the machine needs' {
        $script:Order = @(0, 1, 2)
        Get-MachineHardwareFinding -Machine $script:Stubbed | Should -BeNullOrEmpty
    }

    It 'finds a VM that boots a DVD drive before its disk' {
        $script:Order = @(1, 0, 2)
        Get-MachineHardwareFinding -Machine $script:Stubbed | Should -Match 'boot its disk first'
    }

    It 'refuses to change the hardware of a running VM' {
        $script:State = 'Running'
        { Set-MachineHardware -Machine $script:Stubbed -Confirm:$false } |
            Should -Throw -ExpectedMessage 'REFUSED*'
    }

    It 'says a VM never started is NotStarted, a started one Installing' {
        $script:State = 'Off'
        Get-MachineInstallationState -Machine $script:Stubbed | Should -Be 'NotStarted'
        $script:State = 'Running'
        function Test-MachineGuestInstalled { param([object] $Machine) $false }
        Get-MachineInstallationState -Machine $script:Stubbed | Should -Be 'Installing'
    }

    It 'says a machine whose installation was completed is Done, even when off' {
        $script:State = 'Off'
        New-Item -Path (Join-Path $TestDrive 'installed') -ItemType File -Force | Out-Null
        Get-MachineInstallationState -Machine $script:Stubbed | Should -Be 'Done'
        Test-MachineInstallation -Machine $script:Stubbed | Should -BeFalse
    }
}
