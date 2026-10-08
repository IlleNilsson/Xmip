#requires -PSEdition Core
#requires -Version 7.6.5
using namespace System.Security.Cryptography.X509Certificates

<#
    The Hyper-V lab (deploy/dsc/hyperv-lab) without Hyper-V: what can be held
    on any machine, unelevated, is held here.

    - lab.example.json reads, and the configuration refuses what the lab
      cannot build: a machine's roles follow its Os, a standby names a
      PostgreSQL primary, every address is in the lab's /24.
    - The lab's cluster file declares exactly the lab's Xmip machines, each in
      node::NodeRole's words, so the slice on each node finds its node.
    - A Linux guest's cloud-init seed, its DSC parameters and its payload are
      what the guest needs and carry no secret.
    - VM creation and its findings, with every Hyper-V command a stub: a
      Linux guest gets its Secure Boot template, static MAC and seed disk; a
      Windows 11 guest its TPM.
    - The DSC manifests name the lab's own scripts and scopes, and the
      document names only resources the manifests declare.

    The guests themselves are proved by running the lab: DSC v3 reports their
    findings (deploy/dsc/hyperv-lab/README.md).

    Style: doc/governance/powershell-style.md
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    [string] $script:LabPath = Join-Path $script:Root 'deploy/dsc/hyperv-lab'
    foreach ($file in @('LabHost.ps1', 'LabLinux.ps1', 'LabMedia.ps1', 'LabLinuxFleet.ps1')) {
        . (Join-Path $script:LabPath $file)
    }
    [string] $script:Example = Join-Path $script:LabPath 'lab.example.json'

    # The example with one change, written where only this run reads it.
    function Read-ChangedLab {
        param(
            [Parameter(Mandatory = $true)]
            [scriptblock] $Change
        )

        [hashtable] $lab = Get-Content -LiteralPath $script:Example -Raw |
            ConvertFrom-Json -AsHashtable
        & $Change $lab
        [string] $path = Join-Path $TestDrive 'lab.json'
        $lab | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path
        return Read-LabConfiguration -Path $path
    }

    function Get-ExampleMachine {
        param(
            [Parameter(Mandatory = $true)]
            [hashtable] $Lab,

            [Parameter(Mandatory = $true)]
            [string] $Role,

            [Parameter(Mandatory = $true)]
            [string] $Family
        )

        return @($Lab.Machines | Where-Object { $_.Role -eq $Role -and $_.Family -eq $Family })
    }

    # Every Hyper-V and storage command the lab calls, as a stub a test mocks:
    # a function wins over a cmdlet, so no test reaches a real Hyper-V.
    function Get-VM { param([string] $Name, [object] $ErrorAction) }
    function New-VHD {
        param([string] $Path, [string] $ParentPath, [switch] $Differencing, [long] $SizeBytes,
            [switch] $Dynamic)
    }
    function New-VM {
        param([string] $Name, [int] $Generation, [string] $VHDPath, [string] $Path,
            [long] $MemoryStartupBytes, [string] $SwitchName)
    }
    function Set-VM { param([string] $Name, [string] $Notes, [bool] $AutomaticCheckpointsEnabled) }
    function Set-VMProcessor { param([string] $VMName, [int] $Count) }
    function Set-VMMemory { param([string] $VMName, [bool] $DynamicMemoryEnabled) }
    function Set-VMFirmware {
        param([string] $VMName, [string] $EnableSecureBoot, [string] $SecureBootTemplate)
    }
    function Set-VMKeyProtector { param([string] $VMName, [switch] $NewLocalKeyProtector) }
    function Enable-VMTPM { param([string] $VMName) }
    function Start-VM { param([string] $Name) }
    function Set-VMNetworkAdapter { param([string] $VMName, [string] $StaticMacAddress) }
    function Add-VMHardDiskDrive { param([string] $VMName, [string] $Path) }
    function Get-VMNetworkAdapter { param([string] $VMName) }
    function Get-VMMemory { param([string] $VMName) }
    function Get-VMHardDiskDrive { param([string] $VMName) }
    function Get-VMFirmware { param([string] $VMName) }
    function Get-VMSecurity { param([string] $VMName) }
}

Describe 'The lab configuration' {
    BeforeAll {
        [hashtable] $script:Lab = Read-LabConfiguration -Path $script:Example
    }

    It 'reads the example: its machines, each with the family its Os gives' {
        [string[]] $seen = @($script:Lab.Machines | ForEach-Object {
            "$($_.Name)=$($_.Os)/$($_.Role)/$($_.Family)"
        })

        $seen | Should -Be @(
            'XMIP-DC01=WindowsServer2025/DomainController/Windows'
            'XMIP-FS01=WindowsServer2025/FileServer/Windows'
            'XMIP-DEV01=Windows11/Developer/Windows'
            'XMIP-DB01=AlmaLinux10/PostgreSql/Linux'
            'XMIP-DB02=AlmaLinux10/PostgreSql/Linux'
            'XMIP-APP01=WindowsServer2025/Xmip/Windows'
            'XMIP-APP02=WindowsServer2025/Xmip/Windows'
            'XMIP-APP03=WindowsServer2025/Xmip/Windows'
            'XMIP-IN01=AlmaLinux10/Xmip/Linux'
            'XMIP-OUT01=AlmaLinux10/Xmip/Linux'
        )
    }

    It 'makes the second PostgreSQL server a standby of the first' {
        [hashtable] $standby = $script:Lab.Machines | Where-Object Name -eq 'XMIP-DB02'

        $standby.StandbyOf | Should -Be 'XMIP-DB01'
    }

    It 'installs PostgreSQL on Windows nowhere' {
        [string[]] $named = @(Get-ChildItem -LiteralPath $script:LabPath -Recurse -File |
            Select-String -Pattern 'postgresql\.exe|XmipPostgreSql|PostgreSqlPassword' |
            ForEach-Object { "$($_.Filename):$($_.LineNumber)" })

        $named | Should -BeNullOrEmpty
    }

    It 'refuses <Case>' -ForEach @(
        @{
            Case = 'a domain controller on Linux'
            Change = {
                param($Lab)
                ($Lab.Machines | Where-Object Name -eq 'XMIP-DC01').Os = 'AlmaLinux10'
            }
            Refusal = '*carries only*'
        }
        @{
            Case = 'an Xmip node on Windows 11'
            Change = {
                param($Lab)
                ($Lab.Machines | Where-Object Name -eq 'XMIP-APP01').Os = 'Windows11'
            }
            Refusal = '*carries only*'
        }
        @{
            Case = 'a standby of a machine that is no PostgreSQL primary'
            Change = {
                param($Lab)
                ($Lab.Machines | Where-Object Name -eq 'XMIP-DB02').StandbyOf = 'XMIP-APP01'
            }
            Refusal = '*StandbyOf names no PostgreSQL primary*'
        }
        @{
            Case = 'an address outside the lab subnet'
            Change = {
                param($Lab)
                ($Lab.Machines | Where-Object Name -eq 'XMIP-IN01').Address = '10.78.0.61'
            }
            Refusal = 'Address outside the lab subnet*'
        }
        @{
            Case = 'an Os the lab has no image for'
            Change = { param($Lab) $Lab.Images.Remove('AlmaLinux10') }
            Refusal = '*Os must be one of the lab''s images*'
        }
        @{
            Case = 'a relative path'
            Change = { param($Lab) $Lab.SshKeyPath = 'ssh/xmip-lab' }
            Refusal = 'Lab paths must be absolute*'
        }
    ) {
        { Read-ChangedLab -Change $Change } | Should -Throw -ExpectedMessage $Refusal
    }
}

Describe 'The cluster file the lab slices' {
    It 'declares exactly the lab''s Xmip machines, each in the node''s role words' {
        [hashtable] $lab = Read-LabConfiguration -Path $script:Example
        [string] $file = Join-Path $script:LabPath 'xmip.toml'
        [pscustomobject] $cluster = InModuleScope Xmip -Parameters @{ Path = $file } {
            param($Path)
            Read-XmipTestCluster -Path $Path
        }
        [string[]] $words = @(InModuleScope Xmip { Get-XmipNodeRoleWord })
        [string[]] $machines = @($lab.Machines | Where-Object Role -eq 'Xmip' |
            ForEach-Object { $_.Name } | Sort-Object)

        @($cluster.Nodes | Sort-Object) | Should -Be $machines
        foreach ($node in $cluster.Nodes) {
            @($cluster.Role[$node] -split '[,+]' | ForEach-Object { $_.Trim() }) |
                Should -BeIn $words -Because "$node declares its roles in node::NodeRole's words"
        }
    }
}

Describe 'A Linux guest from the GenericCloud image' {
    BeforeAll {
        [hashtable] $script:Lab = Read-LabConfiguration -Path $script:Example
        [hashtable] $script:Standby = $script:Lab.Machines | Where-Object Name -eq 'XMIP-DB02'
        [hashtable] $script:Primary = $script:Lab.Machines | Where-Object Name -eq 'XMIP-DB01'
        [string] $script:Key = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMadeForThisTestOnly'
    }

    It 'gives the adapter a MAC from the address under Hyper-V''s prefix' {
        Get-LabMacAddress -Address '10.77.0.42' | Should -Be '00155D4D002A'
    }

    It 'seeds the host name, the static address, the domain DNS and the key' {
        [hashtable] $asked = @{
            Lab = $script:Lab
            Machine = $script:Standby
            PublicKey = $script:Key
        }
        [System.Collections.Specialized.OrderedDictionary] $seed = Get-LabCloudInitData @asked

        @($seed.Keys) | Should -Be @('meta-data', 'user-data', 'network-config')
        $seed['meta-data'] | Should -Match '(?m)^local-hostname: xmip-db02$'
        $seed['user-data'] | Should -Match '(?m)^#cloud-config$'
        $seed['user-data'] | Should -Match ([regex]::Escape("- '$script:Key'"))
        $seed['user-data'] | Should -Match '(?m)^ssh_pwauth: false$'
        $seed['network-config'] | Should -Match ([regex]::Escape("macaddress: '00:15:5d:4d:00:2a'"))
        $seed['network-config'] | Should -Match ([regex]::Escape("addresses: ['10.77.0.42/24']"))
        $seed['network-config'] | Should -Match '(?m)^\s+via: 10\.77\.0\.1$'
        $seed['network-config'] | Should -Match ([regex]::Escape('addresses: [10.77.0.10]'))
        $seed.Values | ForEach-Object { $_ | Should -Not -Match "`r" }
    }

    It 'refuses a key that is not ed25519' {
        [string] $key = Join-Path $TestDrive 'lab'
        Set-Content -LiteralPath "$key.pub" -Value 'ssh-rsa AAAAB3NzaC1yc2E= someone'
        [hashtable] $lab = $script:Lab.Clone()
        $lab.SshKeyPath = $key

        { Get-LabPublicKey -Lab $lab } | Should -Throw -ExpectedMessage 'Not an ed25519 public key*'
    }

    It 'tells a standby its primary and its slot, and the primary the standby' {
        [hashtable] $standby = Get-LabLinuxGuestParameter -Lab $script:Lab -Machine $script:Standby
        [hashtable] $primary = Get-LabLinuxGuestParameter -Lab $script:Lab -Machine $script:Primary

        $standby.PostgreSql.Primary.Fqdn | Should -Be 'xmip-db01.xmip.test'
        $primary.PostgreSql.Primary | Should -BeNullOrEmpty
        $primary.PostgreSql.Standbys[0].Address | Should -Be '10.77.0.42'
        $primary.PostgreSql.Standbys[0].Slot | Should -Be $standby.PostgreSql.Primary.Slot
        $standby.DomainController | Should -Be 'xmip-dc01.xmip.test'
    }

    It 'gives a guest no secret in its parameters' {
        foreach ($machine in @($script:Lab.Machines | Where-Object Family -eq 'Linux')) {
            [string] $json = Get-LabLinuxGuestParameter -Lab $script:Lab -Machine $machine |
                ConvertTo-Json -Depth 10

            $json | Should -Not -Match '(?i)password|secret|\.key'
        }
    }

    It 'gives the primary the generated scripts, the standby none, a node its cluster file' {
        [hashtable] $primary = Get-LabLinuxMedia -Lab $script:Lab -Machine $script:Primary
        [hashtable] $standby = Get-LabLinuxMedia -Lab $script:Lab -Machine $script:Standby
        [hashtable] $node = Get-LabLinuxMedia -Lab $script:Lab -Machine (
            $script:Lab.Machines | Where-Object Name -eq 'XMIP-IN01')
        [string[]] $scripts = @(Get-ChildItem -LiteralPath (
            Join-Path $script:Root 'deploy/database/postgresql') -Filter '*.sql' |
            ForEach-Object { "sql/$($_.Name)" })

        @($primary.Keys | Where-Object { $_ -like 'sql/*' } | Sort-Object) | Should -Be $scripts
        @($standby.Keys | Where-Object { $_ -like 'sql/*' }) | Should -BeNullOrEmpty
        $standby.Keys | Should -Contain 'tls/server.key'
        $node['xmip/xmip.toml'] | Should -Be $script:Lab.Xmip.Cluster
        $node['xmip/xmip-service'] | Should -Be $script:Lab.Xmip.LinuxService
    }
}

Describe 'Creating a VM, Hyper-V stubbed' {
    BeforeEach {
        [hashtable] $script:Lab = Read-LabConfiguration -Path $script:Example
        $script:Lab.Root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        # No VM before it is created; the created one running after.
        [int] $script:Asked = 0
        Mock Get-VM {
            $script:Asked++
            if ($script:Asked -gt 1) {
                [pscustomobject] @{ Notes = 'Xmip-HyperV-Lab'; State = 'Running' }
            }
        }
        foreach ($command in @('New-VHD', 'New-VM', 'Set-VM', 'Set-VMProcessor', 'Set-VMMemory',
            'Set-VMFirmware', 'Set-VMKeyProtector', 'Enable-VMTPM', 'Set-VMNetworkAdapter',
            'Add-VMHardDiskDrive', 'New-LabCloudInitSeed')) {
            Mock $command { }
        }
    }

    It 'gives a Linux guest its boot template, static MAC and seed disk, and no TPM' {
        [hashtable] $machine = $script:Lab.Machines | Where-Object Name -eq 'XMIP-IN01'

        Set-LabVirtualMachine -Lab $script:Lab -Machine $machine -BaseImage 'b' -Confirm:$false

        Should -Invoke Set-VMFirmware -Times 1 -Exactly -ParameterFilter {
            $SecureBootTemplate -eq 'MicrosoftUEFICertificateAuthority' -and
                $EnableSecureBoot -eq 'On'
        }
        Should -Invoke Set-VMNetworkAdapter -Times 1 -Exactly -ParameterFilter {
            $StaticMacAddress -eq '00155D4D003D'
        }
        Should -Invoke New-LabCloudInitSeed -Times 1 -Exactly
        Should -Invoke Add-VMHardDiskDrive -Times 1 -Exactly -ParameterFilter {
            $Path -like '*XMIP-IN01*seed.vhdx'
        }
        Should -Invoke Enable-VMTPM -Times 0 -Exactly
    }

    It 'gives a Windows 11 guest its TPM and no seed' {
        [hashtable] $machine = $script:Lab.Machines | Where-Object Name -eq 'XMIP-DEV01'

        Set-LabVirtualMachine -Lab $script:Lab -Machine $machine -BaseImage 'b' -Confirm:$false

        Should -Invoke Enable-VMTPM -Times 1 -Exactly
        Should -Invoke New-LabCloudInitSeed -Times 0 -Exactly
        Should -Invoke Set-VMFirmware -Times 1 -Exactly -ParameterFilter {
            [string]::IsNullOrEmpty($SecureBootTemplate)
        }
    }

    It 'refuses a VM of the same name the lab does not own' {
        Mock Get-VM { [pscustomobject] @{ Notes = 'someone else' } }
        [hashtable] $machine = $script:Lab.Machines | Where-Object Name -eq 'XMIP-IN01'

        [hashtable] $create = @{ Lab = $script:Lab; Machine = $machine; BaseImage = 'b' }

        { Set-LabVirtualMachine @create -Confirm:$false } |
            Should -Throw -ExpectedMessage 'REFUSED*'
    }
}

Describe 'A Linux VM''s findings, Hyper-V stubbed' {
    BeforeEach {
        [hashtable] $script:Lab = Read-LabConfiguration -Path $script:Example
        [hashtable] $script:Machine = $script:Lab.Machines | Where-Object Name -eq 'XMIP-OUT01'
        Mock Get-VM {
            [pscustomobject] @{
                Notes = 'Xmip-HyperV-Lab'
                Generation = 2
                ProcessorCount = 2
                State = 'Running'
            }
        }
        Mock Get-VMMemory { [pscustomobject] @{ Startup = 4GB; DynamicMemoryEnabled = $false } }
        Mock Get-VMHardDiskDrive {
            [string] $directory = Join-Path $script:Lab.Root 'XMIP-OUT01'
            @('os.vhdx', 'seed.vhdx') | ForEach-Object {
                [pscustomobject] @{ Path = Join-Path $directory $_ }
            }
        }
        Mock Get-VMFirmware {
            [pscustomobject] @{
                SecureBoot = 'On'
                SecureBootTemplate = 'MicrosoftUEFICertificateAuthority'
            }
        }
    }

    It 'finds nothing on a guest as built' {
        Mock Get-VMNetworkAdapter {
            [pscustomobject] @{ SwitchName = 'Xmip-Lab'; MacAddress = '00155D4D0047' }
        }

        Get-LabVirtualMachineFinding -Lab $script:Lab -Machine $script:Machine |
            Should -BeNullOrEmpty
    }

    It 'finds a MAC cloud-init would not match' {
        Mock Get-VMNetworkAdapter {
            [pscustomobject] @{ SwitchName = 'Xmip-Lab'; MacAddress = '00155D010203' }
        }

        Get-LabVirtualMachineFinding -Lab $script:Lab -Machine $script:Machine |
            Should -Be 'XMIP-OUT01: Linux boot template or static MAC differs.'
    }
}

Describe 'The lab''s TLS files' {
    It 'issues each PostgreSQL machine a certificate for its name under one authority' {
        [hashtable] $lab = Get-Content -LiteralPath $script:Example -Raw |
            ConvertFrom-Json -AsHashtable
        [string] $directory = Join-Path $TestDrive 'tls'
        $lab.PostgreSql.Tls.Directory = $directory
        $lab.PostgreSql.Tls.Authority = Join-Path $directory 'authority.pem'
        [string] $config = Join-Path $TestDrive 'tls-lab.json'
        $lab | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $config

        & (Join-Path $script:LabPath 'New-LabCertificate.ps1') -ConfigPath $config 6> $null

        [X509Certificate2] $authority = [X509Certificate2]::CreateFromPem(
            (Get-Content -LiteralPath $lab.PostgreSql.Tls.Authority -Raw))
        [X509Chain] $chain = [X509Chain]::new()
        $chain.ChainPolicy.TrustMode = 'CustomRootTrust'
        $chain.ChainPolicy.RevocationMode = 'NoCheck'
        $chain.ChainPolicy.CustomTrustStore.Add($authority) | Out-Null
        foreach ($name in @('XMIP-DB01', 'XMIP-DB02')) {
            [string] $base = Join-Path $directory $name
            [X509Certificate2] $leaf = [X509Certificate2]::CreateFromPemFile(
                "$base.crt", "$base.key")

            $leaf.HasPrivateKey | Should -BeTrue
            $leaf.MatchesHostname("$($name.ToLowerInvariant()).xmip.test") | Should -BeTrue
            $chain.Build($leaf) | Should -BeTrue -Because "$name chains to the lab's authority"
        }
    }
}

Describe 'What DSC on a guest answers' {
    It 'reads <Case>' -ForEach @(
        @{
            Case = 'a test with findings'
            Output = '{"results":[{"result":{"actualState":' +
                '{"Findings":["firewalld is not running."]}}}]}'
            ExitCode = 0
            Ready = $false
            Findings = @('firewalld is not running.')
        }
        @{
            Case = 'a set that left nothing'
            Output = '{"results":[{"result":{"afterState":{"Findings":[]}}}]}'
            ExitCode = 0
            Ready = $true
            Findings = @()
        }
        @{
            Case = 'a guest never given its payload'
            Output = ''
            ExitCode = 1
            Ready = $false
            Findings = @('the payload has not been copied yet.')
        }
    ) {
        [pscustomobject] $answer = [pscustomobject] @{
            ExitCode = $ExitCode
            Output = [string[]] @($Output)
            Error = [string[]] @()
        }

        [pscustomobject] $read = ConvertFrom-LabDscResult -Answer $answer -Operation 'Test'

        $read.Ready | Should -Be $Ready
        @($read.Findings) | Should -Be $Findings
    }
}

Describe 'The DSC documents and manifests' {
    BeforeAll {
        [hashtable] $script:HostManifest = Get-Content -LiteralPath (
            Join-Path $script:LabPath 'xmip-lab.dsc.manifests.json') -Raw |
            ConvertFrom-Json -AsHashtable
        [hashtable] $script:Guest = Get-Content -LiteralPath (
            Join-Path $script:LabPath 'linux/xmip-lab-linux.dsc.resource.json') -Raw |
            ConvertFrom-Json -AsHashtable
    }

    It 'runs a lab script that exists, in a scope it accepts, for every operation' {
        [string] $resource = Join-Path $script:LabPath 'LabResource.ps1'
        [string[]] $scopes = @((Get-Command -Name $resource).Parameters['Scope'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } |
            ForEach-Object { $_.ValidValues })

        foreach ($manifest in $script:HostManifest.resources) {
            foreach ($operation in @('get', 'test', 'set')) {
                [string[]] $arguments = $manifest[$operation].args
                $arguments | Should -Contain './LabResource.ps1'
                $arguments[[array]::IndexOf($arguments, '-Scope') + 1] | Should -BeIn $scopes
            }
        }
        [string] $guest = Join-Path $script:LabPath 'linux/LabLinuxGuest.ps1'
        Test-Path -LiteralPath $guest | Should -BeTrue
        $script:Guest.set.args | Should -Contain './LabLinuxGuest.ps1'
    }

    It 'names in each document only resources a manifest declares' {
        [string[]] $declared = @($script:HostManifest.resources.type) + $script:Guest.type
        foreach ($document in @('hyperv-lab.dsc.yaml', 'linux/linux.dsc.yaml')) {
            # A resource's type has a namespace; a parameter's type has none.
            [string] $path = Join-Path $script:LabPath $document
            [string] $pattern = '^\s+type:\s+(\S+/\S+)$'
            [string[]] $named = @(Select-String -LiteralPath $path -Pattern $pattern |
                ForEach-Object { $_.Matches[0].Groups[1].Value })

            $named | Should -Not -BeNullOrEmpty
            $named | ForEach-Object { $_ | Should -BeIn $declared }
        }
    }
}
