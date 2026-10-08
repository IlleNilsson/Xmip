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
    - The install answers: a Windows guest's autounattend.xml parses, names
      its computer and image and holds no plain-text password; a Linux
      guest's kickstart gives its host name, static address and key, on a
      medium labelled OEMDRV; the answer medium is an ISO with that label.
    - A Linux guest's DSC parameters and its payload are what the guest
      needs and carry no secret.
    - VM creation, its findings and its media ejected, with every Hyper-V
      command a stub: each guest gets a new disk, its ISO and answer medium,
      the disk first in the boot order and its family's Secure Boot
      template; a Windows guest is given the key its ISO asks for; a
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
    [string[]] $sources = @('LabHost.ps1', 'LabMachine.ps1', 'LabAnswer.ps1', 'LabLinux.ps1',
        'LabMedia.ps1', 'LabLinuxFleet.ps1')
    foreach ($file in $sources) {
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
    function New-VHD { param([string] $Path, [long] $SizeBytes, [switch] $Dynamic) }
    function New-VM {
        param([string] $Name, [int] $Generation, [string] $VHDPath, [string] $Path,
            [long] $MemoryStartupBytes, [string] $SwitchName)
    }
    function Set-VM { param([string] $Name, [string] $Notes, [bool] $AutomaticCheckpointsEnabled) }
    function Set-VMProcessor { param([string] $VMName, [int] $Count) }
    function Set-VMMemory { param([string] $VMName, [bool] $DynamicMemoryEnabled) }
    function Set-VMFirmware {
        param([string] $VMName, [string] $EnableSecureBoot, [string] $SecureBootTemplate,
            [object[]] $BootOrder)
    }
    function Set-VMKeyProtector { param([string] $VMName, [switch] $NewLocalKeyProtector) }
    function Enable-VMTPM { param([string] $VMName) }
    function Start-VM { param([string] $Name) }
    function Set-VMNetworkAdapter { param([string] $VMName, [string] $StaticMacAddress) }
    function Add-VMDvdDrive { param([string] $VMName, [string] $Path, [switch] $Passthru) }
    function Get-VMDvdDrive { param([string] $VMName) }
    function Set-VMDvdDrive {
        param([string] $VMName, [int] $ControllerNumber, [int] $ControllerLocation,
            [string] $Path)
    }
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
        @{
            Case = 'a Windows image with no edition to install'
            Change = { param($Lab) $Lab.Images.WindowsServer2025.Remove('Edition') }
            Refusal = 'WindowsServer2025 needs its Edition*'
        }
        @{
            Case = 'Windows 11 in less memory than its installer accepts'
            Change = {
                param($Lab)
                ($Lab.Machines | Where-Object Name -eq 'XMIP-DEV01').MemoryGB = 2
            }
            Refusal = '*Windows11 installs with 4 GB of memory and 64 GB of disk at least*'
        }
        @{
            Case = 'a machine with no disk size'
            Change = {
                param($Lab)
                ($Lab.Machines | Where-Object Name -eq 'XMIP-IN01').Remove('DiskGB')
            }
            Refusal = '*AlmaLinux10 installs with*'
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

Describe 'The install answers' {
    BeforeAll {
        [hashtable] $script:Lab = Read-LabConfiguration -Path $script:Example
        [string] $script:Key = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMadeForThisTestOnly'
        [string] $script:Password = 'Made-For-This-Test-0nly'
        [securestring] $secure = ConvertTo-SecureString -String $script:Password -AsPlainText
        [hashtable] $asked = @{
            Lab = $script:Lab
            Machine = $script:Lab.Machines | Where-Object Name -eq 'XMIP-APP02'
            AdministratorPassword = $secure
        }
        [string] $script:Answer = Get-LabWindowsAnswer @asked
        [xml] $script:Xml = $script:Answer
        [System.Xml.XmlNamespaceManager] $script:Ns = [System.Xml.XmlNamespaceManager]::new(
            $script:Xml.NameTable)
        $script:Ns.AddNamespace('u', 'urn:schemas-microsoft-com:unattend')
    }

    It 'gives the adapter a MAC from the address under Hyper-V''s prefix' {
        Get-LabMacAddress -Address '10.77.0.42' | Should -Be '00155D4D002A'
    }

    It 'answers Windows Setup with the computer name and the image lab.json names' {
        [string] $name = $script:Xml.SelectSingleNode('//u:ComputerName', $script:Ns).InnerText
        [string] $image = $script:Xml.SelectSingleNode(
            '//u:InstallFrom/u:MetaData[u:Key="/IMAGE/NAME"]/u:Value', $script:Ns).InnerText

        $name | Should -Be 'XMIP-APP02'
        $image | Should -Be 'Windows Server 2025 SERVERDATACENTER'
        @($script:Xml.SelectNodes('//u:CreatePartition/u:Type', $script:Ns).InnerText) |
            Should -Be @('EFI', 'MSR', 'Primary')
        $script:Answer | Should -Match ([regex]::Escape('net user Administrator /active:yes'))
    }

    It 'holds the Administrator password encoded, never in plain text' {
        [System.Xml.XmlNode] $password = $script:Xml.SelectSingleNode(
            '//u:AdministratorPassword', $script:Ns)
        [string] $decoded = [Text.Encoding]::Unicode.GetString(
            [Convert]::FromBase64String($password.Value))

        $script:Answer | Should -Not -Match ([regex]::Escape($script:Password))
        $password.PlainText | Should -Be 'false'
        $decoded | Should -Be "$($script:Password)AdministratorPassword"
    }

    It 'answers Anaconda with the host name, static address, DNS and key, on OEMDRV' {
        [hashtable] $standby = $script:Lab.Machines | Where-Object Name -eq 'XMIP-DB02'
        [string] $kickstart = Get-LabKickstart -Lab $script:Lab -Machine $standby -PublicKey (
            $script:Key)
        Mock Get-LabPublicKey { $script:Key }
        [hashtable] $medium = Get-LabAnswerMedium -Lab $script:Lab -Machine $standby
        [string] $network = '(?m)^network --device=00:15:5D:4D:00:2A --bootproto=static ' +
            '--ip=10\.77\.0\.42 --netmask=255\.255\.255\.0 --gateway=10\.77\.0\.1 ' +
            '--nameserver=10\.77\.0\.10 --hostname=xmip-db02\.xmip\.test '

        $kickstart | Should -Match $network
        $kickstart | Should -Match ([regex]::Escape("sshkey --username=xmiplab `"$script:Key`""))
        $kickstart | Should -Match '(?m)^rootpw --lock$'
        $kickstart | Should -Match '(?m)^cdrom$'
        $kickstart | Should -Not -Match "`r"
        $medium.Label | Should -Be 'OEMDRV'
        @($medium.File.Keys) | Should -Be @('ks.cfg')
        $medium.File['ks.cfg'] | Should -Be $kickstart
    }

    It 'writes the answer medium as an ISO carrying its label and file' -Skip:(-not $IsWindows) {
        [string] $path = Join-Path $TestDrive 'answer.iso'
        [hashtable] $medium = @{
            Label = 'OEMDRV'
            File = [ordered] @{ 'ks.cfg' = "text`n" }
        }

        New-LabAnswerMedium -Path $path -Medium $medium -Confirm:$false

        [byte[]] $image = [IO.File]::ReadAllBytes($path)
        [Text.Encoding]::ASCII.GetString($image, 0x8028, 32).Trim() | Should -Be 'OEMDRV'
        [Text.Encoding]::ASCII.GetString($image) | Should -Match 'KS\.CFG;1'
        Test-Path -LiteralPath "$path.files" | Should -BeFalse
    }
}

Describe 'A Linux guest''s parameters and payload' {
    BeforeAll {
        [hashtable] $script:Lab = Read-LabConfiguration -Path $script:Example
        [hashtable] $script:Standby = $script:Lab.Machines | Where-Object Name -eq 'XMIP-DB02'
        [hashtable] $script:Primary = $script:Lab.Machines | Where-Object Name -eq 'XMIP-DB01'
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
        [hashtable] $script:Medium = @{ Label = 'OEMDRV'; File = [ordered] @{} }
        # No VM before it is created; the created one off after, to be started.
        [int] $script:Asked = 0
        Mock Get-VM {
            $script:Asked++
            if ($script:Asked -gt 1) {
                [pscustomobject] @{ Notes = 'Xmip-HyperV-Lab'; State = 'Off' }
            }
        }
        Mock Add-VMDvdDrive { [pscustomobject] @{ Path = $Path } }
        Mock Get-VMDvdDrive { [pscustomobject] @{ Path = 'the.iso' } }
        Mock Get-VMHardDiskDrive { [pscustomobject] @{ Path = 'os.vhdx' } }
        Mock Get-VMNetworkAdapter { [pscustomobject] @{ SwitchName = 'Xmip-Lab' } }
        foreach ($command in @('New-VHD', 'New-VM', 'Set-VM', 'Set-VMProcessor', 'Set-VMMemory',
            'Set-VMFirmware', 'Set-VMKeyProtector', 'Enable-VMTPM', 'Set-VMNetworkAdapter',
            'Start-VM', 'New-LabAnswerMedium', 'Send-LabBootKey')) {
            Mock $command { }
        }
    }

    It 'installs a Linux guest from its ISO on a new disk, the disk booting first' {
        [hashtable] $machine = $script:Lab.Machines | Where-Object Name -eq 'XMIP-IN01'

        [hashtable] $create = @{ Lab = $script:Lab; Machine = $machine; Medium = $script:Medium }
        Set-LabVirtualMachine @create -Confirm:$false

        Should -Invoke New-VHD -Times 1 -Exactly -ParameterFilter {
            $SizeBytes -eq 32GB -and $Dynamic -and $Path -like '*XMIP-IN01*os.vhdx'
        }
        Should -Invoke New-LabAnswerMedium -Times 1 -Exactly -ParameterFilter {
            $Path -like '*XMIP-IN01*answer.iso' -and $Medium.Label -eq 'OEMDRV'
        }
        Should -Invoke Add-VMDvdDrive -Times 1 -Exactly -ParameterFilter {
            $Path -eq $script:Lab.Images.AlmaLinux10.Path
        }
        Should -Invoke Add-VMDvdDrive -Times 1 -Exactly -ParameterFilter {
            $Path -like '*XMIP-IN01*answer.iso'
        }
        Should -Invoke Set-VMFirmware -Times 1 -Exactly -ParameterFilter {
            $SecureBootTemplate -eq 'MicrosoftUEFICertificateAuthority' -and
                $EnableSecureBoot -eq 'On' -and $BootOrder[0].Path -eq 'os.vhdx' -and
                $BootOrder[1].Path -eq $script:Lab.Images.AlmaLinux10.Path
        }
        Should -Invoke Set-VMNetworkAdapter -Times 1 -Exactly -ParameterFilter {
            $StaticMacAddress -eq '00155D4D003D'
        }
        Should -Invoke Start-VM -Times 1 -Exactly
        Should -Invoke Send-LabBootKey -Times 0 -Exactly
        Should -Invoke Enable-VMTPM -Times 0 -Exactly
    }

    It 'gives a Windows 11 guest its template, its TPM and the key its ISO asks for' {
        [hashtable] $machine = $script:Lab.Machines | Where-Object Name -eq 'XMIP-DEV01'

        [hashtable] $create = @{ Lab = $script:Lab; Machine = $machine; Medium = $script:Medium }
        Set-LabVirtualMachine @create -Confirm:$false

        Should -Invoke Set-VMFirmware -Times 1 -Exactly -ParameterFilter {
            $SecureBootTemplate -eq 'MicrosoftWindows' -and $BootOrder[0].Path -eq 'os.vhdx'
        }
        Should -Invoke Set-VMKeyProtector -Times 1 -Exactly
        Should -Invoke Enable-VMTPM -Times 1 -Exactly
        Should -Invoke Send-LabBootKey -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'XMIP-DEV01'
        }
    }

    It 'gives a Windows Server guest no TPM' {
        [hashtable] $machine = $script:Lab.Machines | Where-Object Name -eq 'XMIP-FS01'

        [hashtable] $create = @{ Lab = $script:Lab; Machine = $machine; Medium = $script:Medium }
        Set-LabVirtualMachine @create -Confirm:$false

        Should -Invoke Enable-VMTPM -Times 0 -Exactly
        Should -Invoke Add-VMDvdDrive -Times 1 -Exactly -ParameterFilter {
            $Path -eq $script:Lab.Images.WindowsServer2025.Path
        }
    }

    It 'refuses a VM of the same name the lab does not own' {
        Mock Get-VM { [pscustomobject] @{ Notes = 'someone else' } }
        [hashtable] $machine = $script:Lab.Machines | Where-Object Name -eq 'XMIP-IN01'

        [hashtable] $create = @{ Lab = $script:Lab; Machine = $machine; Medium = $script:Medium }

        { Set-LabVirtualMachine @create -Confirm:$false } |
            Should -Throw -ExpectedMessage 'REFUSED*'
    }
}

Describe 'A VM''s findings, Hyper-V stubbed' {
    BeforeEach {
        [hashtable] $script:Lab = Read-LabConfiguration -Path $script:Example
        [hashtable] $script:Machine = $script:Lab.Machines | Where-Object Name -eq 'XMIP-OUT01'
        [string] $script:Disk = Join-Path (Join-Path $script:Lab.Root 'XMIP-OUT01') 'os.vhdx'
        Mock Get-VM {
            [pscustomobject] @{
                Notes = 'Xmip-HyperV-Lab'
                Generation = 2
                ProcessorCount = 2
                State = 'Running'
            }
        }
        Mock Get-VMMemory { [pscustomobject] @{ Startup = 4GB; DynamicMemoryEnabled = $false } }
        Mock Get-VMHardDiskDrive { [pscustomobject] @{ Path = $script:Disk } }
        Mock Get-VMNetworkAdapter {
            [pscustomobject] @{ SwitchName = 'Xmip-Lab'; MacAddress = '00155D4D0047' }
        }
        Mock Get-VMFirmware {
            [pscustomobject] @{
                SecureBoot = 'On'
                SecureBootTemplate = 'MicrosoftUEFICertificateAuthority'
                BootOrder = @(
                    [pscustomobject] @{ BootType = 'File'; Device = $null }
                    [pscustomobject] @{
                        BootType = 'Drive'
                        Device = [pscustomobject] @{ Path = $script:Disk }
                    }
                )
            }
        }
        Mock Get-VMDvdDrive {
            [pscustomobject] @{ Path = $null; ControllerNumber = 0; ControllerLocation = 1 }
        }
    }

    It 'finds nothing on a guest installed, its media ejected' {
        Get-LabVirtualMachineFinding -Lab $script:Lab -Machine $script:Machine |
            Should -BeNullOrEmpty
    }

    It 'finds a MAC the kickstart would not match' {
        Mock Get-VMNetworkAdapter {
            [pscustomobject] @{ SwitchName = 'Xmip-Lab'; MacAddress = '00155D010203' }
        }

        Get-LabVirtualMachineFinding -Lab $script:Lab -Machine $script:Machine |
            Should -Be 'XMIP-OUT01: static MAC differs.'
    }

    It 'finds a guest still installing while its media are in' {
        Mock Get-VMDvdDrive {
            [pscustomobject] @{ Path = 'the.iso'; ControllerNumber = 0; ControllerLocation = 1 }
        }

        Get-LabVirtualMachineFinding -Lab $script:Lab -Machine $script:Machine |
            Should -Be ('XMIP-OUT01: installing from its ISO; the media are ejected once it ' +
                'answers.')
    }

    It 'finds a DVD drive booting before the disk' {
        Mock Get-VMFirmware {
            [pscustomobject] @{
                SecureBoot = 'On'
                SecureBootTemplate = 'MicrosoftUEFICertificateAuthority'
                BootOrder = @([pscustomobject] @{
                    BootType = 'Drive'
                    Device = [pscustomobject] @{ Path = 'the.iso' }
                })
            }
        }

        Get-LabVirtualMachineFinding -Lab $script:Lab -Machine $script:Machine |
            Should -Be 'XMIP-OUT01: boots from another drive before its disk.'
    }

    It 'ejects the media and deletes the answer medium once the guest answers' {
        $script:Lab.Root = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        [string] $directory = Join-Path $script:Lab.Root 'XMIP-OUT01'
        New-Item -Path $directory -ItemType Directory | Out-Null
        [string] $answer = Join-Path $directory 'answer.iso'
        Set-Content -LiteralPath $answer -Value 'answer'
        Mock Get-VMDvdDrive {
            [pscustomobject] @{ Path = 'the.iso'; ControllerNumber = 0; ControllerLocation = 1 }
            [pscustomobject] @{ Path = $null; ControllerNumber = 0; ControllerLocation = 2 }
        }
        Mock Set-VMDvdDrive { }

        Complete-LabInstallation -Lab $script:Lab -Machine $script:Machine -Confirm:$false

        Should -Invoke Set-VMDvdDrive -Times 1 -Exactly -ParameterFilter {
            $ControllerLocation -eq 1 -and [string]::IsNullOrEmpty($Path)
        }
        Test-Path -LiteralPath $answer | Should -BeFalse
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
