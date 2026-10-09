#requires -PSEdition Core
#requires -Version 7.6.5

<#
    The Microsoft DSC v3 template for Hyper-V (deploy/dsc/msdsc/hyperv)
    without Hyper-V: what can be held on any machine, unelevated.

    - The documents and the example parameters parse as YAML, read by DSC
      itself; each document declares every parameter it uses and uses every
      one it declares, and depends only on its own instances.
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
    [string[]] $script:Document = @('network.dsc.yaml', 'machine.dsc.yaml',
        'environment.example.dsc.yaml')

    # A YAML file as DSC reads it: Echo hands its input back as JSON, and
    # an expression in a resource's input is not evaluated.
    function Read-DscYaml {
        param(
            [Parameter(Mandatory = $true)]
            [string] $Path
        )

        [string[]] $lines = @(Get-Content -LiteralPath $Path | ForEach-Object { "  $_" })
        [string] $echo = "output:`n" + ($lines -join "`n")
        [string] $json = dsc resource get --resource Microsoft.DSC.Debug/Echo --input $echo
        if ($LASTEXITCODE -ne 0) {
            throw "dsc could not read $Path as YAML."
        }
        return ($json | ConvertFrom-Json -AsHashtable).actualState.output
    }

    # A copy of a document, as JSON, whose every instance is an Echo of its
    # properties, so evaluating it changes nothing; Includes stay.
    function Write-EchoDocument {
        param(
            [Parameter(Mandatory = $true)]
            [string] $Name
        )

        [hashtable] $document = Read-DscYaml -Path (Join-Path $script:Template $Name)
        $document.Remove('metadata')
        $document.resources = @(foreach ($instance in $document.resources) {
            if ($instance.type -eq 'Microsoft.DSC/Include') {
                $instance.Remove('dependsOn')
                $instance
                continue
            }
            [hashtable] $output = @{ type = $instance.type; properties = $instance.properties }
            @{ name = $instance.name; type = 'Microsoft.DSC.Debug/Echo'
                properties = @{ output = $output } }
        })
        $document | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $TestDrive $Name)
    }

    # The example environment evaluated: each machine's Echo results by name.
    function Invoke-EchoEnvironment {
        foreach ($name in $script:Document) {
            Write-EchoDocument -Name $name
        }
        [hashtable] $parameters = Read-DscYaml -Path (
            Join-Path $script:Template 'environment.example.parameters.yaml')
        $parameters.parameters.common.template = [string] $TestDrive
        $parameters.parameters.common.linuxAccount = 'account'
        [string] $file = Join-Path $TestDrive 'parameters.json'
        $parameters | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $file
        [string] $environment = Join-Path $TestDrive 'environment.example.dsc.yaml'
        [string] $json = dsc config --parameters-file $file get --file $environment
        if ($LASTEXITCODE -ne 0) {
            throw 'dsc could not evaluate the example environment.'
        }
        [hashtable] $result = @{}
        foreach ($include in ($json | ConvertFrom-Json -AsHashtable).results) {
            [hashtable] $instance = @{}
            foreach ($echo in $include.result) {
                $instance[$echo.name] = $echo.result.actualState.output
            }
            $result[$include.name] = $instance
        }
        return $result
    }

    if ($script:HasDsc) {
        $script:Parsed = @{}
        foreach ($name in $script:Document + 'environment.example.parameters.yaml') {
            $script:Parsed[$name] = Read-DscYaml -Path (Join-Path $script:Template $name)
        }
        $script:Evaluated = Invoke-EchoEnvironment
        $script:Machine = @($script:Evaluated.Keys | Where-Object { $_ -ne 'Network' } |
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

    It 'parses <_> as YAML' -ForEach @('network.dsc.yaml', 'machine.dsc.yaml',
        'environment.example.dsc.yaml', 'environment.example.parameters.yaml') {
        $script:Parsed[$_] | Should -Not -BeNullOrEmpty
    }

    It 'declares in <_> every parameter it uses, and uses every one' -ForEach @(
        'network.dsc.yaml', 'machine.dsc.yaml', 'environment.example.dsc.yaml') {
        [string] $text = Get-Content -LiteralPath (Join-Path $script:Template $_) -Raw
        [string[]] $used = @([regex]::Matches($text, "parameters\('(\w+)'\)") |
            ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        [string[]] $declared = @($script:Parsed[$_].parameters.Keys | Sort-Object)
        ($used -join ',') | Should -Be ($declared -join ',')
    }

    It 'depends in <_> only on its own instances' -ForEach @(
        'network.dsc.yaml', 'machine.dsc.yaml', 'environment.example.dsc.yaml') {
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
        [hashtable] $network = $script:Evaluated['Network']
        $network['Switch'].properties.Name | Should -Be 'Xmip'
        $network['Gateway'].properties.IPAddress | Should -Be @('10.77.0.1/24')
        $network['Nat'].properties.input.prefix | Should -Be '10.77.0.0/24'
    }

    It 'gives each machine a VM of its own values' {
        [hashtable] $example = $script:Parsed['environment.example.parameters.yaml']
        [string] $root = $example.parameters.common.root
        foreach ($machine in $script:Machine) {
            [hashtable] $vm = $script:Evaluated[$machine.name -replace '-', ' ']
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
        [string[]] $macs = @($addresses | ForEach-Object { Get-MachineMacAddress -Address $_ })
        $script:Machine.Count | Should -Be 10
        @($script:Machine | ForEach-Object { $_.name } | Sort-Object -Unique).Count |
            Should -Be 10
        @($addresses | Sort-Object -Unique).Count | Should -Be 10
        @($macs | Sort-Object -Unique).Count | Should -Be 10
        [object] $network = $script:Parsed['environment.example.parameters.yaml'].parameters.network
        [string] $mask = Get-MachineNetmask -PrefixLength $network.prefixLength
        [uint32] $want = ([ipaddress] ($network.prefix -replace '/.*$')).Address
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
            [string] $kickstart = Get-MachineKickstart -Machine $machine -PublicKey $key
            [string] $mac = (Get-MachineMacAddress -Address $machine.address) -replace (
                '(..)(?!$)'), '$1:'
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
