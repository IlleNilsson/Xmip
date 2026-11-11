#requires -PSEdition Core
#requires -Version 7.7.0

<#
    The Microsoft DSC v3 template for Hyper-V (deploy/dsc/msdsc/hyperv)
    without Hyper-V: what can be held on any machine, unelevated, without
    membership of Hyper-V Administrators.

    - The documents parse as YAML, read by the module's YAML reader; each
      declares every parameter it uses and uses every one it declares; the
      network's asks for elevation as a whole, a machine's for none, and no
      manifest elevates a method. Only the template's own resources are
      used, each given every property its manifest requires and none it
      does not declare, and DSC finds both manifests.
    - The example environment, as Deploy-XmipEnvironment applies it: the
      network, then each machine, each step evaluated by DSC with every
      resource replaced by Microsoft.DSC.Debug/Echo; each machine is the
      machine README.md's table names. A step whose dsc fails is refused,
      tested or set: every resource answers what is not there as absent.
    - The install answers: a Windows machine's autounattend.xml parses,
      names its computer and image and holds no plain-text password; an
      AlmaLinux machine's kickstart gives its host name, static address and
      key; the answer medium is an ISO with the label its installer reads.
    - The resources' get, test and set, every Hyper-V and network command a
      stub over a host held in memory: a switch, a NAT and a machine that
      are not there answered absent, a host's refusal kept an error, an
      absent network and machine made, a Windows 11 machine's TPM given
      before its media and Space pressed for its first twenty seconds, a
      machine still installing answered by its state alone, a VM with two
      adapters refused, an installed one's media removed.

    The VMs themselves are proved by running the template:
    deploy/dsc/msdsc/hyperv/README.md.

    Style: doc/governance/powershell-style.md
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    [string] $script:Template = Join-Path $script:Root 'deploy/dsc/msdsc/hyperv'
    . (Join-Path $script:Template 'HyperVResource.ps1')
    [bool] $script:HasDsc = $null -ne (Get-Command -Name dsc -ErrorAction SilentlyContinue)
    [string] $script:NoDsc = 'dsc (Microsoft DSC v3) is not on PATH; README.md installs it'
    [string[]] $script:Document = @('network.dsc.yaml', 'machine.dsc.yaml')
    [string] $script:ExamplePath = Join-Path $script:Template 'environment.example.toml'

    $script:Parsed = @{}
    foreach ($name in $script:Document) {
        $script:Parsed[$name] = Read-XmipTestYaml -Path (Join-Path $script:Template $name)
    }
    $script:Example = InModuleScope Xmip -Parameters @{ Path = $script:ExamplePath } {
        param($Path)
        Read-XmipToml -Path $Path
    }
    # The example's steps as Deploy-XmipEnvironment applies them.
    [hashtable[]] $script:Steps = @(InModuleScope Xmip -Parameters @{
        Path = $script:ExamplePath; Template = $script:Template
    } {
        param($Path, $Template)
        $environment = Read-XmipToml -Path $Path
        $environment['linux_account'] = 'account'
        Get-XmipDeployStep -Environment $environment -Template $Template
    })
    $script:Machine = @($script:Steps | Select-Object -Skip 1 |
        ForEach-Object { [pscustomobject] $_.Value })

    # A resource manifest of the folder, read by the module's YAML reader.
    function Read-Manifest {
        param(
            [Parameter(Mandatory = $true)]
            [string] $Type
        )

        [string] $file = ($Type -replace '^Xmip\.', 'xmip-' -replace '/', '-').ToLowerInvariant()
        return Read-XmipTestYaml -Path (Join-Path $script:Template "$file.dsc.resource.yaml")
    }

    # A copy of a document, in YAML, whose every instance is an Echo of its
    # properties, so evaluating it changes nothing.
    function Write-EchoDocument {
        param(
            [Parameter(Mandatory = $true)]
            [string] $Name
        )

        [hashtable] $document = Read-XmipTestYaml -Path (Join-Path $script:Template $Name)
        # The network's elevated security context is the real run's; an Echo needs none.
        $document.Remove('directives')
        $document.resources = @(foreach ($instance in $document.resources) {
            [hashtable] $output = @{ type = $instance.type; properties = $instance.properties }
            @{ name = $instance.name; type = 'Microsoft.DSC.Debug/Echo'
                properties = @{ output = $output } }
        })
        Write-XmipTestYaml -Path (Join-Path $TestDrive $Name) -Value $document
    }

    # Each step of the example evaluated by DSC as Echoes, with the
    # parameters its document declares: each step's Echo results by name.
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
                $value[$name] = $step.Value[$name]
            }
            [string] $file = Join-Path $TestDrive "$($step.Name).parameters.yaml"
            Write-XmipTestYaml -Path $file -Value @{ parameters = $value }
            [string] $json = dsc config --parameters-file $file get --file $document
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
        $script:Evaluated = Invoke-EchoEnvironment
    }

    # A Hyper-V host held in memory for the resources' get, test and set:
    # every Hyper-V and network command they call is a stub over it, and
    # each one that changes it is recorded in $script:Called, in order.
    function Reset-FakeHost {
        $script:Fake = @{
            Switch = @(); Address = @(); Nat = @(); Vm = @(); Tpm = $false
            Firmware = [pscustomobject] @{
                SecureBoot = 'Off'; SecureBootTemplate = ''; BootOrder = @() }
        }
        $script:Called = [Collections.Generic.List[string]]::new()
        Get-ChildItem -LiteralPath $TestDrive -Directory -Filter 'XMIP-*' |
            Remove-Item -Recurse -Force
    }

    function Add-FakeSwitch {
        param([string] $Name, [string] $Type)
        $script:Fake.Switch += [pscustomobject] @{ Name = $Name; SwitchType = $Type }
    }

    function Add-FakeAddress {
        param([string] $Alias, [string] $Address, [string] $Origin, [int] $PrefixLength = 24)
        $script:Fake.Address += [pscustomobject] @{ InterfaceAlias = $Alias
            IPAddress = $Address; PrefixLength = $PrefixLength; PrefixOrigin = $Origin }
    }

    function New-FakeDrive {
        param([int] $Location, [string] $Path)
        return [pscustomobject] @{ ControllerNumber = 0; ControllerLocation = $Location
            Path = $Path }
    }

    function New-FakeBoot {
        param([int] $Location)
        return [pscustomobject] @{ BootType = 'Drive'
            Device = [pscustomobject] @{ ControllerLocation = $Location } }
    }

    # A machine's instance as its document gives it: an AlmaLinux machine,
    # or a Windows 11 one with its TPM and its Administrator's credential
    # file, its image a file of the test's own.
    function New-FakeInstance {
        param([string] $Family)
        [string] $iso = Join-Path $TestDrive 'image.iso'
        Set-Content -LiteralPath $iso -Value 'an installation image' -NoNewline
        [string] $key = Join-Path $TestDrive 'xmip.pub'
        Set-Content -LiteralPath $key -Value (
            'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDummyKeyForTheTestOnly test')
        [hashtable] $image = @{ path = $iso; family = $Family; tpm = $false
            sha256 = (Get-FileHash -LiteralPath $iso -Algorithm SHA256).Hash
            secureBootTemplate = 'MicrosoftUEFICertificateAuthority' }
        [hashtable] $instance = @{ name = 'XMIP-IN01'; address = '10.77.0.61'
            environment = 'Xmip-HyperV'; root = [string] $TestDrive
            memoryGB = 4; cpu = 2; diskGB = 32; domainName = 'xmip.test'
            network = @{ name = 'Xmip'; gateway = '10.77.0.1'; prefixLength = 24
                dnsServer = '10.77.0.10' }
            linuxAccount = 'account'; sshPublicKeyPath = $key; credentialPath = ''
            image = $image }
        if ($Family -eq 'Windows') {
            $instance['name'] = 'XMIP-DEV01'
            $instance['address'] = '10.77.0.30'
            [string] $credential = Join-Path $TestDrive 'credential.xml'
            [securestring] $password = ConvertTo-SecureString -String 'Pa55word' -AsPlainText -Force
            [pscredential]::new('Administrator', $password) |
                Export-Clixml -LiteralPath $credential
            $instance['credentialPath'] = $credential
            $image['edition'] = 'Windows 11 Pro'
            $image['secureBootTemplate'] = 'MicrosoftWindows'
            $image['tpm'] = $true
        }
        return $instance
    }

    # A VM on the fake host exactly as the instance needs it.
    function Add-FakeMachine {
        param([hashtable] $Instance, [string] $State)
        [string] $disk = Get-HyperVMachineDisk -Instance $Instance
        New-Item -Path (Split-Path -Path $disk -Parent) -ItemType Directory -Force | Out-Null
        [string] $mac = Get-MachineMacAddress -Address $Instance['address'] -Prefix (
            $script:HyperVMacPrefix)
        $script:Fake.Vm += [pscustomobject] @{
            Name = $Instance['name']; State = $State; ProcessorCount = [long] $Instance['cpu']
            MemoryStartup = [long] $Instance['memoryGB'] * 1GB; DynamicMemoryEnabled = $false
            AutomaticCheckpointsEnabled = $false; Notes = $Instance['environment']
            HardDrives = @(New-FakeDrive -Location 0 -Path $disk)
            DVDDrives = @(New-FakeDrive -Location 1 -Path ''; New-FakeDrive -Location 2 -Path '')
            NetworkAdapters = @([pscustomobject] @{
                SwitchName = $Instance['network'].name; MacAddress = $mac })
        }
        $script:Fake.Firmware = [pscustomobject] @{ SecureBoot = 'On'
            SecureBootTemplate = $Instance['image'].secureBootTemplate
            BootOrder = @(0, 1, 2 | ForEach-Object { New-FakeBoot -Location $_ }) }
        $script:Fake.Tpm = [bool] $Instance['image'].tpm
    }

    function Get-VMSwitch {
        return $script:Fake.Switch
    }

    function New-VMSwitch {
        param([string] $Name, [string] $SwitchType)
        $script:Called.Add("New-VMSwitch $Name $SwitchType")
        Add-FakeSwitch -Name $Name -Type $SwitchType
    }

    function Get-NetIPAddress {
        param([string] $AddressFamily)
        return $script:Fake.Address
    }

    function New-NetIPAddress {
        param([string] $InterfaceAlias, [string] $IPAddress, [int] $PrefixLength)
        $script:Called.Add("New-NetIPAddress $InterfaceAlias $IPAddress/$PrefixLength")
        Add-FakeAddress -Alias $InterfaceAlias -Address $IPAddress -Origin 'Manual' -PrefixLength (
            $PrefixLength)
    }

    function Remove-NetIPAddress {
        [CmdletBinding(SupportsShouldProcess = $true)]
        param([Parameter(ValueFromPipeline = $true)] [object] $InputObject)
        process {
            [string] $text = "$($InputObject.IPAddress)/$($InputObject.PrefixLength)"
            $script:Called.Add("Remove-NetIPAddress $text")
            $script:Fake.Address = @($script:Fake.Address | Where-Object {
                "$($_.IPAddress)/$($_.PrefixLength)" -ne $text })
        }
    }

    function Get-NetNat {
        return $script:Fake.Nat
    }

    function New-NetNat {
        param([string] $Name, [string] $InternalIPInterfaceAddressPrefix)
        $script:Called.Add("New-NetNat $Name $InternalIPInterfaceAddressPrefix")
        $script:Fake.Nat += [pscustomobject] @{
            Name = $Name; InternalIPInterfaceAddressPrefix = $InternalIPInterfaceAddressPrefix }
    }

    function Remove-NetNat {
        [CmdletBinding(SupportsShouldProcess = $true)]
        param([string] $Name)
        $script:Called.Add("Remove-NetNat $Name")
        $script:Fake.Nat = @($script:Fake.Nat | Where-Object { $_.Name -ne $Name })
    }

    function Get-VM {
        return $script:Fake.Vm
    }

    function New-VHD {
        param([string] $Path, [long] $SizeBytes, [switch] $Dynamic)
        $script:Called.Add('New-VHD')
        New-Item -Path $Path -ItemType File | Out-Null
    }

    function New-VM {
        param([string] $Name, [int] $Generation, [long] $MemoryStartupBytes,
            [string] $VHDPath, [string] $SwitchName, [string] $Path)
        $script:Called.Add('New-VM')
        $script:Fake.Vm += [pscustomobject] @{
            Name = $Name; State = 'Off'; ProcessorCount = 1; MemoryStartup = $MemoryStartupBytes
            DynamicMemoryEnabled = $true; AutomaticCheckpointsEnabled = $true; Notes = ''
            HardDrives = @(New-FakeDrive -Location 0 -Path $VHDPath); DVDDrives = @()
            NetworkAdapters = @([pscustomobject] @{
                SwitchName = $SwitchName; MacAddress = '000000000000' })
        }
    }

    function Set-VM {
        param([string] $Name, [long] $ProcessorCount, [switch] $StaticMemory,
            [long] $MemoryStartupBytes, [bool] $AutomaticCheckpointsEnabled, [string] $Notes)
        $script:Called.Add('Set-VM')
        [object] $vm = $script:Fake.Vm[0]
        $vm.ProcessorCount = $ProcessorCount
        $vm.DynamicMemoryEnabled = -not $StaticMemory
        $vm.MemoryStartup = $MemoryStartupBytes
        $vm.AutomaticCheckpointsEnabled = $AutomaticCheckpointsEnabled
        $vm.Notes = $Notes
    }

    function Connect-VMNetworkAdapter {
        param([string] $VMName, [string] $SwitchName)
        $script:Called.Add('Connect-VMNetworkAdapter')
        $script:Fake.Vm[0].NetworkAdapters[0].SwitchName = $SwitchName
    }

    function Set-VMNetworkAdapter {
        param([string] $VMName, [string] $StaticMacAddress)
        $script:Called.Add("Set-VMNetworkAdapter $StaticMacAddress")
        $script:Fake.Vm[0].NetworkAdapters[0].MacAddress = $StaticMacAddress
    }

    function Get-VMNetworkAdapter {
        param([string] $VMName)
        return $script:Fake.Vm[0].NetworkAdapters
    }

    function Add-VMDvdDrive {
        param([string] $VMName, [int] $ControllerNumber, [int] $ControllerLocation)
        $script:Called.Add("Add-VMDvdDrive $ControllerLocation")
        $script:Fake.Vm[0].DVDDrives += New-FakeDrive -Location $ControllerLocation -Path ''
    }

    function Get-VMDvdDrive {
        param([string] $VMName, [int] $ControllerNumber, [int] $ControllerLocation)
        [bool] $every = -not $PSBoundParameters.ContainsKey('ControllerLocation')
        return @($script:Fake.Vm[0].DVDDrives | Where-Object {
            $every -or $_.ControllerLocation -eq $ControllerLocation })
    }

    function Set-VMDvdDrive {
        param([string] $VMName, [int] $ControllerNumber, [int] $ControllerLocation,
            [string] $Path)
        $script:Called.Add("Set-VMDvdDrive $ControllerLocation")
        @($script:Fake.Vm[0].DVDDrives | Where-Object {
            $_.ControllerLocation -eq $ControllerLocation }) | ForEach-Object { $_.Path = $Path }
    }

    function Get-VMHardDiskDrive {
        param([string] $VMName, [int] $ControllerNumber, [int] $ControllerLocation)
        return @($script:Fake.Vm[0].HardDrives | Where-Object {
            $_.ControllerLocation -eq $ControllerLocation })
    }

    function Get-VMFirmware {
        param([string] $VMName)
        return $script:Fake.Firmware
    }

    function Set-VMFirmware {
        param([string] $VMName, [string] $EnableSecureBoot, [string] $SecureBootTemplate,
            [object[]] $BootOrder)
        [int[]] $drives = @($BootOrder | Where-Object {
            $null -ne $_.PSObject.Properties['ControllerLocation'] } |
            ForEach-Object { $_.ControllerLocation })
        $script:Called.Add("Set-VMFirmware $($drives -join ',')")
        $script:Fake.Firmware = [pscustomobject] @{
            SecureBoot = $EnableSecureBoot; SecureBootTemplate = $SecureBootTemplate
            BootOrder = @($drives | ForEach-Object { New-FakeBoot -Location $_ }) }
    }

    function Get-VMSecurity {
        param([string] $VMName)
        return [pscustomobject] @{ TpmEnabled = $script:Fake.Tpm }
    }

    function Set-VMKeyProtector {
        param([string] $VMName, [switch] $NewLocalKeyProtector)
        $script:Called.Add('Set-VMKeyProtector')
    }

    function Enable-VMTPM {
        param([string] $VMName)
        $script:Called.Add('Enable-VMTPM')
        $script:Fake.Tpm = $true
    }

    function Start-VM {
        param([string] $Name)
        $script:Called.Add('Start-VM')
        $script:Fake.Vm[0].State = 'Running'
    }
}

Describe 'The documents and the resources' {
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

    It 'requires DSC 3.4.0-preview.2 or newer in <Name>, elevated whole: <Elevated>' -ForEach @(
        @{ Name = 'network.dsc.yaml'; Elevated = $true }
        @{ Name = 'machine.dsc.yaml'; Elevated = $false }
    ) {
        # A switch's host address and NAT are an administrator's to set; a
        # member of Hyper-V Administrators manages VMs unelevated.
        [Collections.IDictionary] $directives = $script:Parsed[$Name].directives
        $directives.version | Should -Be '^3.4.0-preview.2'
        $directives.Contains('securityContext') | Should -Be $Elevated
        if ($Elevated) {
            $directives.securityContext | Should -Be 'elevated'
        }
    }

    It 'elevates no method of <_>: the documents say what is elevated' -ForEach @(
        'Xmip.HyperV/Network', 'Xmip.HyperV/Machine') {
        [Collections.IDictionary] $manifest = Read-Manifest -Type $_
        @('get', 'set', 'test' | Where-Object {
            $manifest[$_].Contains('requireSecurityContext') }) | Should -BeNullOrEmpty
    }

    It 'uses only the template''s own resources, run in PowerShell 7' {
        [string[]] $types = @($script:Document | ForEach-Object {
            $script:Parsed[$_].resources | ForEach-Object { $_.type } })
        $types | Should -Be @('Xmip.HyperV/Network', 'Xmip.HyperV/Machine')
        [string] $others = 'HyperVDsc|NetworkingDsc|WindowsPowerShell|PowerShellScript'
        foreach ($file in Get-ChildItem -LiteralPath $script:Template -File) {
            Get-Content -LiteralPath $file.FullName -Raw | Should -Not -Match $others -Because (
                "$($file.Name) uses Xmip's own resources")
        }
    }

    It 'gives <_> every property its manifest requires, and none it does not declare' -ForEach @(
        'network.dsc.yaml', 'machine.dsc.yaml') {
        [Collections.IDictionary] $resource = @($script:Parsed[$_].resources)[0]
        [Collections.IDictionary] $schema = (Read-Manifest -Type $resource.type).schema
        [string[]] $given = @($resource.properties.Keys)
        $schema.required | Where-Object { $_ -notin $given } | Should -BeNullOrEmpty
        $given | Where-Object { -not $schema.properties.Contains($_) } | Should -BeNullOrEmpty
    }

    It 'finds both Xmip resources of the folder' {
        if (-not $script:HasDsc) {
            Set-ItResult -Skipped -Because $script:NoDsc
        }
        [string] $path = $env:PATH
        try {
            $env:PATH = "$script:Template$([System.IO.Path]::PathSeparator)$path"
            [string[]] $found = @(dsc resource list 'Xmip.HyperV/*' | ConvertFrom-Json |
                ForEach-Object { $_.type } | Sort-Object)
        }
        finally {
            $env:PATH = $path
        }
        $found | Should -Be @('Xmip.HyperV/Machine', 'Xmip.HyperV/Network')
    }
}

Describe 'The example environment' {
    It 'applies the network, then each machine, with every parameter declared' {
        $script:Steps[0].Name | Should -Be 'network'
        [string[]] $machines = @($script:Example['machines'] | ForEach-Object { $_['name'] })
        @($script:Steps | Select-Object -Skip 1 | ForEach-Object { $_.Name }) |
            Should -Be $machines
        foreach ($step in $script:Steps) {
            [Collections.IDictionary] $declared = (
                Read-XmipTestYaml -Path $step.Document).parameters
            foreach ($name in $declared.Keys) {
                $step.Value.ContainsKey($name) | Should -BeTrue -Because "$($step.Name) $name"
            }
        }
    }

    It 'gives the network every value it asks for' {
        if (-not $script:HasDsc) {
            Set-ItResult -Skipped -Because $script:NoDsc
        }
        [hashtable] $network = $script:Evaluated['network']['Network'].properties
        $network.name | Should -Be 'Xmip'
        $network.environment | Should -Be 'Xmip-HyperV'
        $network.gateway | Should -Be '10.77.0.1'
        $network.prefixLength | Should -Be 24
        $network.prefix | Should -Be '10.77.0.0/24'
        $network.nat | Should -BeTrue
    }

    It 'gives each machine its own values' {
        if (-not $script:HasDsc) {
            Set-ItResult -Skipped -Because $script:NoDsc
        }
        foreach ($machine in $script:Machine) {
            [hashtable] $vm = $script:Evaluated[$machine.name]['Machine'].properties
            foreach ($key in 'name', 'address', 'memoryGB', 'cpu', 'diskGB', 'root') {
                $vm[$key] | Should -Be $machine.$key -Because "$($machine.name) $key"
            }
            $vm.network.name | Should -Be 'Xmip'
            $vm.image.family | Should -Be $machine.image.family
        }
    }

    It 'has unique names, addresses and MACs, every address on the network' {
        # ForEach-Object, not .address: an array's .Address is its own method.
        [string[]] $addresses = @($script:Machine | ForEach-Object { $_.address })
        [string[]] $macs = @($addresses | ForEach-Object {
            Get-MachineMacAddress -Address $_ -Prefix $script:HyperVMacPrefix })
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

    It 'refuses a step whose dsc <_> fails, never reading it as not yet made' -ForEach @(
        'test', 'set') {
        if (-not $script:HasDsc) {
            Set-ItResult -Skipped -Because $script:NoDsc
        }
        [string] $operation = $_
        Mock -ModuleName Xmip dsc { $global:LASTEXITCODE = 1 }
        {
            InModuleScope Xmip -Parameters @{
                Step = $script:Steps[0]; Operation = $operation; Log = [string] $TestDrive
            } {
                param($Step, $Operation, $Log)
                Invoke-XmipDeployStep -Step $Step -Operation $Operation -Log $Log
            }
        } | Should -Throw -ExpectedMessage "REFUSED: network: dsc $operation exit 1*"
    }
}

Describe 'The install answers' {
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
            [string] $raw = Get-MachineMacAddress -Address $machine.address -Prefix (
                $script:HyperVMacPrefix)
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

Describe 'The network, every Hyper-V and network command a stub' {
    BeforeAll {
        $script:Network = @{
            name = 'Xmip'; environment = 'Xmip-HyperV'; prefix = '10.77.0.0/24'
            gateway = '10.77.0.1'; prefixLength = 24; nat = $true
        }
    }

    BeforeEach {
        Reset-FakeHost
    }

    It 'answers a switch, its address and NAT that are not there as absent, never refused' {
        [hashtable] $got = Invoke-HyperVResource -Kind Network -Operation get -Instance (
            $script:Network)
        $got._exist | Should -BeFalse
        $got.findings | Should -Contain 'Xmip: absent.'
        $got.findings | Should -Contain 'Xmip-HyperV: NAT for 10.77.0.0/24 absent.'
        $got.Contains('_inDesiredState') | Should -BeFalse
        $got.name | Should -Be 'Xmip'
        (Invoke-HyperVResource -Kind Network -Operation test -Instance $script:Network).
            _inDesiredState | Should -BeFalse
    }

    It 'keeps the host''s refusal to list its switches an error' {
        function Get-VMSwitch { throw 'You do not have the required permission.' }
        { Invoke-HyperVResource -Kind Network -Operation get -Instance $script:Network } |
            Should -Throw -ExpectedMessage '*required permission*'
    }

    It 'makes an absent network, then finds it in its desired state and changes nothing' {
        [hashtable] $set = Invoke-HyperVResource -Kind Network -Operation set -Instance (
            $script:Network)
        $set._exist | Should -BeTrue
        $set._inDesiredState | Should -BeTrue
        $script:Called | Should -Be @('New-VMSwitch Xmip Internal',
            'New-NetIPAddress vEthernet (Xmip) 10.77.0.1/24', 'New-NetNat Xmip-HyperV 10.77.0.0/24')
        $script:Called.Clear()
        Invoke-HyperVResource -Kind Network -Operation set -Instance $script:Network | Out-Null
        $script:Called | Should -BeNullOrEmpty
    }

    It 'leaves the gateway the switch adapter''s one manual address, and removes NAT turned off' {
        Add-FakeSwitch -Name 'Xmip' -Type 'Internal'
        Add-FakeAddress -Alias 'vEthernet (Xmip)' -Address '10.78.0.1' -Origin 'Manual'
        Add-FakeAddress -Alias 'vEthernet (Xmip)' -Address '169.254.170.15' -Origin 'WellKnown'
        $script:Fake.Nat = @([pscustomobject] @{
            Name = 'Xmip-HyperV'; InternalIPInterfaceAddressPrefix = '10.77.0.0/24' })
        [hashtable] $off = $script:Network.Clone()
        $off['nat'] = $false
        (Invoke-HyperVResource -Kind Network -Operation set -Instance $off)._inDesiredState |
            Should -BeTrue
        $script:Called | Should -Be @('Remove-NetIPAddress 10.78.0.1/24',
            'New-NetIPAddress vEthernet (Xmip) 10.77.0.1/24', 'Remove-NetNat Xmip-HyperV')
    }

    It 'refuses a switch of the name that is not internal, and changes nothing' {
        Add-FakeSwitch -Name 'Xmip' -Type 'External'
        { Invoke-HyperVResource -Kind Network -Operation set -Instance $script:Network } |
            Should -Throw -ExpectedMessage 'REFUSED: Xmip: not one internal switch (External)*'
        $script:Called | Should -BeNullOrEmpty
    }
}

Describe 'The machine, every Hyper-V command a stub' {
    BeforeAll {
        # The answer medium is written by MachineAnswer.ps1, held above; an
        # AlmaLinux guest answers SSH only where an It says so.
        function New-MachineAnswerMedium {
            [CmdletBinding(SupportsShouldProcess = $true)]
            param([string] $Path, [hashtable] $Medium)
            $script:Called.Add("New-MachineAnswerMedium $($Medium.Label)")
            Set-Content -LiteralPath $Path -Value $Medium.Label
        }

        function Test-Connection {
            return $false
        }
    }

    BeforeEach {
        Reset-FakeHost
        $script:Linux = New-FakeInstance -Family 'Linux'
    }

    It 'answers a machine that is not there as absent, never refused' {
        [hashtable] $got = Invoke-HyperVResource -Kind Machine -Operation get -Instance (
            $script:Linux)
        $got._exist | Should -BeFalse
        $got.installation | Should -Be 'Absent'
        $got.running | Should -BeFalse
        $got.findings | Should -Be @('XMIP-IN01: absent.')
        (Invoke-HyperVResource -Kind Machine -Operation test -Instance $script:Linux).
            _inDesiredState | Should -BeFalse
    }

    It 'keeps the host''s refusal to list its VMs an error' {
        function Get-VM { throw 'You do not have the required permission.' }
        { Invoke-HyperVResource -Kind Machine -Operation test -Instance $script:Linux } |
            Should -Throw -ExpectedMessage '*required permission*'
    }

    It 'makes an absent machine, gives it its hardware and media, and starts it installing' {
        [hashtable] $set = Invoke-HyperVResource -Kind Machine -Operation set -Instance (
            $script:Linux)
        $script:Called | Should -Be @('New-VHD', 'New-VM', 'Set-VM', 'Connect-VMNetworkAdapter',
            'Set-VMNetworkAdapter 00155D4D003D', 'Add-VMDvdDrive 1', 'Add-VMDvdDrive 2',
            'Set-VMFirmware 0,1,2', 'New-MachineAnswerMedium OEMDRV', 'Set-VMDvdDrive 1',
            'Set-VMDvdDrive 2', 'Start-VM')
        $set._exist | Should -BeTrue
        $set.installation | Should -Be 'Installing'
        $set.running | Should -BeTrue
        $set.findings | Should -Be @('XMIP-IN01: Installing, running True.')
        $set._inDesiredState | Should -BeFalse
    }

    It 'gives a Windows 11 machine its TPM before its media, then presses Space as it starts' {
        [hashtable] $windows = New-FakeInstance -Family 'Windows'
        function Get-CimInstance {
            param([string] $Namespace, [string] $ClassName, [string] $Filter)
            return [pscustomobject] @{ Class = $ClassName
                ElementName = $Filter -replace "^ElementName = '(.*)'$", '$1' }
        }
        function Get-CimAssociatedInstance {
            param([object] $InputObject, [string] $ResultClassName)
            return [pscustomobject] @{
                Name = "$ResultClassName of $($InputObject.Class) $($InputObject.ElementName)" }
        }
        function Invoke-CimMethod {
            param([object] $InputObject, [string] $MethodName, [hashtable] $Arguments)
            $script:Called.Add("$($InputObject.Name) $MethodName $($Arguments.keyCode)")
        }
        function Start-Sleep {
            param([int] $Milliseconds)
            $script:Slept += $Milliseconds
        }
        # PowerShell Direct does not answer while Windows installs.
        function Invoke-Command { }
        $script:Slept = 0
        [hashtable] $set = Invoke-HyperVResource -Kind Machine -Operation set -Instance $windows
        [string[]] $press = @('Msvm_Keyboard of Msvm_ComputerSystem XMIP-DEV01 TypeKey 32') * 40
        $script:Called | Should -Be (@('New-VHD', 'New-VM', 'Set-VM', 'Connect-VMNetworkAdapter',
            'Set-VMNetworkAdapter 00155D4D001E', 'Add-VMDvdDrive 1', 'Add-VMDvdDrive 2',
            'Set-VMFirmware 0,1,2', 'Set-VMKeyProtector', 'Enable-VMTPM',
            'New-MachineAnswerMedium XMIP', 'Set-VMDvdDrive 1', 'Set-VMDvdDrive 2', 'Start-VM') +
            $press)
        $script:Slept | Should -Be 20000
        $set.installation | Should -Be 'Installing'
        $set.findings | Should -Be @('XMIP-DEV01: Installing, running True.')
    }

    It 'answers its state alone while it installs: nothing on another stream before it' {
        # DSC reads the first line a resource writes as its answer, and
        # pwsh -File writes a warning to standard output too.
        Add-FakeMachine -Instance $script:Linux -State 'Running'
        [object[]] $written = @(Invoke-HyperVResource -Kind Machine -Operation set -Instance (
            $script:Linux) *>&1)
        $written.Count | Should -Be 1
        $written[0] | Should -BeOfType [hashtable]
        $written[0].installation | Should -Be 'Installing'
        $written[0]._inDesiredState | Should -BeFalse
        $script:Called | Should -BeNullOrEmpty
    }

    It 'refuses a VM with two adapters, never giving both its MAC, and changes nothing' {
        Add-FakeMachine -Instance $script:Linux -State 'Off'
        $script:Fake.Vm[0].NetworkAdapters += [pscustomobject] @{
            SwitchName = 'Default Switch'; MacAddress = '00155D000001' }
        Get-HyperVHardwareFinding -Instance $script:Linux -Vm $script:Fake.Vm[0] |
            Should -Be 'XMIP-IN01: has not one adapter, on Xmip, with the MAC 00155D4D003D.'
        { Invoke-HyperVResource -Kind Machine -Operation set -Instance $script:Linux } |
            Should -Throw -ExpectedMessage 'REFUSED: XMIP-IN01 has 2 adapters, not one*'
        $script:Called | Should -BeNullOrEmpty
    }

    It 'removes an installed guest''s media and is then in its desired state' {
        Invoke-HyperVResource -Kind Machine -Operation set -Instance $script:Linux | Out-Null
        function Test-Connection { $true }
        [hashtable] $set = Invoke-HyperVResource -Kind Machine -Operation set -Instance (
            $script:Linux)
        @($script:Fake.Vm[0].DVDDrives | Where-Object { $_.Path }) | Should -BeNullOrEmpty
        Join-Path $TestDrive 'XMIP-IN01/answer.iso' | Should -Not -Exist
        Join-Path $TestDrive 'XMIP-IN01/installed' | Should -Exist
        $set.installation | Should -Be 'Done'
        $set._inDesiredState | Should -BeTrue
    }

    It 'finds nothing to change in hardware that is as the machine needs' {
        [hashtable] $windows = New-FakeInstance -Family 'Windows'
        Add-FakeMachine -Instance $windows -State 'Off'
        Get-HyperVHardwareFinding -Instance $windows -Vm $script:Fake.Vm[0] | Should -BeNullOrEmpty
    }

    It 'finds a VM that boots a DVD drive before its disk, and one with dynamic memory' {
        Add-FakeMachine -Instance $script:Linux -State 'Off'
        $script:Fake.Firmware.BootOrder = @(New-FakeBoot -Location 1; New-FakeBoot -Location 0)
        $script:Fake.Vm[0].DynamicMemoryEnabled = $true
        [string[]] $found = @(Get-HyperVHardwareFinding -Instance $script:Linux -Vm (
            $script:Fake.Vm[0]))
        $found | Should -Contain 'XMIP-IN01: does not boot its disk first, then its DVD drives.'
        $found | Should -Contain 'XMIP-IN01: its DynamicMemoryEnabled is True, not False.'
    }

    It 'refuses to change the hardware of a VM that is not off, never stopping it' {
        Add-FakeMachine -Instance $script:Linux -State 'Running'
        { Set-HyperVHardware -Instance $script:Linux -Confirm:$false } |
            Should -Throw -ExpectedMessage 'REFUSED: XMIP-IN01 is Running*'
        $script:Called | Should -BeNullOrEmpty
    }

    It 'says a VM never started is NotStarted, a started one Installing, an installed one Done' {
        Add-FakeMachine -Instance $script:Linux -State 'Off'
        [object] $vm = $script:Fake.Vm[0]
        Get-HyperVInstallationState -Instance $script:Linux -Vm $vm | Should -Be 'NotStarted'
        $vm.State = 'Running'
        Get-HyperVInstallationState -Instance $script:Linux -Vm $vm | Should -Be 'Installing'
        $vm.State = 'Off'
        New-Item -Path (Join-Path $TestDrive 'XMIP-IN01/installed') -ItemType File -Force |
            Out-Null
        Get-HyperVInstallationState -Instance $script:Linux -Vm $vm | Should -Be 'Done'
        (Invoke-HyperVResource -Kind Machine -Operation test -Instance $script:Linux).
            _inDesiredState | Should -BeFalse
    }
}
