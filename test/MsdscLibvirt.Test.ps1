#requires -PSEdition Core
#requires -Version 7.7.0

<#
    The Microsoft DSC v3 template for libvirt (deploy/dsc/msdsc/libvirt)
    without libvirt: what can be held on any machine.

    - The network's definition: NAT where the environment says, isolated
      otherwise, the bridge, the gateway, a DHCP host per machine by its
      static MAC, and one DNS host per address holding every name it
      answers; its summary ignores what libvirt adds.
    - The domain's definition: UEFI with Secure Boot, the disk first, the
      DVD drives on SATA, virtio for AlmaLinux and SATA and e1000e for
      Windows; its memory, the most of a dynamic one with memory_gb its
      balloon's start, static where it says no more; the balloon for
      AlmaLinux and none for Windows, which gets Hyper-V's interface and
      clock; a TPM where its image asks, refused where the host has no
      swtpm; a gateway machine's second adapter on the uplink, a bridge.
    - The answer: an AlmaLinux machine's kickstart keeps KVM's clock,
      ptp_kvm loaded at every start.
    - The System Tests' cluster file on a Linux host, every machine AlmaLinux
      (ADR-0015, amendment 2026-11-25), as Deploy-XmipEnvironment reads it:
      the network, then each machine, each with every parameter its document
      declares, and the names of each far end and node, then the cluster's;
      the host the way out, through its NAT, of each node that declares
      online alone, no machine on an uplink, and a desktop on XMIP-DEV02;
      each machine's domain with its description and its memory. Refused: a
      Windows machine, which a Linux host makes none of yet (ADR-0015, the
      third amendment of 2026-11-22), and dynamic memory on a Windows machine
      on libvirt.
    - The machine's set while it installs, virsh a stub: it is left to
      install and nothing is written, since DSC reads what the resource
      writes as its answer.

    The machines themselves are proved by running the template:
    deploy/dsc/msdsc/libvirt/README.md.

    Style: doc/governance/powershell-style.md
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    [string] $script:Template = Join-Path $script:Root 'deploy/dsc/msdsc/libvirt'
    foreach ($part in '../../machine/LibvirtInstallation.ps1', 'LibvirtNetwork.ps1',
        'LibvirtMachine.ps1') {
        . (Join-Path $script:Template $part)
    }

    # The names are configuration (ADR-0056): the test cluster's own first
    # node and its name.
    $script:TestCluster = Get-XmipTestCluster
    [string] $script:Node = @($script:TestCluster.Nodes)[0]
    [string] $script:Cluster = $script:TestCluster.Name

    $script:Network = @{
        name = 'xmip'
        bridge = 'virbr-xmip'
        gateway = '10.77.0.1'
        prefixLength = 24
        nat = $true
        machines = @(
            @{ name = 'XMIP-IN01'; address = '10.77.0.61' }
            @{ name = 'XMIP-APP01'; address = '10.77.0.51' }
        )
        names = @(
            @{ name = $script:Node; addresses = @('10.77.0.61') }
            @{ name = $script:Cluster; addresses = @('10.77.0.61', '10.77.0.51') }
        )
    }

    function New-Machine {
        param([string] $Family)

        [string] $system = if ($Family -eq 'Windows') { 'Windows Server 2025' }
        else { 'AlmaLinux 10' }
        return @{
            name = 'XMIP-IN01'
            description = "Receiving node IN01 $([char] 0x00B7) $system"
            address = '10.77.0.61'
            memoryGB = 4
            cpu = 2
            diskGB = 32
            pool = 'xmip'
            network = @{ name = 'xmip'; gateway = '10.77.0.1'; prefixLength = 24 }
            image = @{ family = $Family; sha256 = ('90244AC532F67C97' + ('0' * 48)) }
        }
    }
}

Describe 'The network' {
    It 'gives each machine a DHCP host by its static MAC' {
        [xml] $network = Get-LibvirtNetworkDefinition -Instance $script:Network
        $network.network.forward.mode | Should -Be 'nat'
        $network.network.bridge.name | Should -Be 'virbr-xmip'
        $network.network.ip.address | Should -Be '10.77.0.1'
        [object] $dhcp = $network.SelectSingleNode("//dhcp/host[@name='XMIP-IN01']")
        $dhcp.mac | Should -Be '52:54:00:4d:00:3d'
        $dhcp.ip | Should -Be '10.77.0.61'
    }

    It 'is isolated where a gateway machine is the way out, the host''s NAT off' {
        [hashtable] $isolated = $script:Network.Clone()
        $isolated['nat'] = $false
        [xml] $network = Get-LibvirtNetworkDefinition -Instance $isolated
        $network.SelectSingleNode('/network/forward') | Should -BeNullOrEmpty
        $network.network.ip.address | Should -Be '10.77.0.1'
        Get-LibvirtNetworkSummary -Xml $network | Should -Not -Be (
            Get-LibvirtNetworkSummary -Xml ([xml] (Get-LibvirtNetworkDefinition -Instance (
                        $script:Network))))
    }

    It 'answers every name of an address in one DNS host' {
        [xml] $network = Get-LibvirtNetworkDefinition -Instance $script:Network
        [object[]] $hosts = @($network.SelectNodes('//dns/host'))
        $hosts.Count | Should -Be 2
        [object] $in01 = $network.SelectSingleNode("//dns/host[@ip='10.77.0.61']")
        @($in01.hostname) | Should -Be @('XMIP-IN01', $script:Node, $script:Cluster)
    }

    It 'summarizes a definition as libvirt returns it like the one it was given' {
        [string] $given = Get-LibvirtNetworkDefinition -Instance $script:Network
        [xml] $returned = $given
        $returned.network.AppendChild($returned.CreateElement('uuid')).InnerText = 'u'
        [Xml.XmlElement] $mac = $returned.CreateElement('mac')
        $mac.SetAttribute('address', '52:54:00:00:00:01')
        $returned.network.AppendChild($mac) | Out-Null
        Get-LibvirtNetworkSummary -Xml $returned | Should -Be (
            Get-LibvirtNetworkSummary -Xml ([xml] $given))
    }
}

Describe 'The domain' {
    It 'boots an AlmaLinux machine with UEFI, Secure Boot and virtio, its disk first' {
        [hashtable] $machine = New-Machine -Family 'Linux'
        [xml] $domain = Get-LibvirtMachineDefinition -Instance $machine
        # Its role and system in one line, the domain's description.
        $domain.domain.description | Should -Be $machine['description']
        # The attribute, not the <firmware> element of the same name.
        $domain.domain.os.GetAttribute('firmware') | Should -Be 'efi'
        $domain.SelectSingleNode("//feature[@name='secure-boot']").enabled | Should -Be 'yes'
        @($domain.domain.os.boot | ForEach-Object { $_.dev }) | Should -Be @('hd', 'cdrom')
        $domain.SelectSingleNode("//disk[@device='disk']/target").bus | Should -Be 'virtio'
        $domain.SelectSingleNode('//interface/model').type | Should -Be 'virtio'
        $domain.SelectSingleNode('//interface/mac').address | Should -Be '52:54:00:4d:00:3d'
        $domain.SelectSingleNode("//disk[@device='cdrom']/source").volume |
            Should -Be 'image-90244ac532f67c97.iso'
    }

    It 'gives a Windows machine the SATA disk and e1000e adapter its installer knows' {
        [xml] $domain = Get-LibvirtMachineDefinition -Instance (New-Machine -Family 'Windows')
        $domain.SelectSingleNode("//disk[@device='disk']/target").bus | Should -Be 'sata'
        $domain.SelectSingleNode('//interface/model').type | Should -Be 'e1000e'
        $domain.SelectSingleNode("//interface[@type='bridge']") | Should -BeNullOrEmpty
    }

    It 'gives a gateway machine a second adapter on the uplink, a bridge, its MAC its own' {
        [hashtable] $machine = New-Machine -Family 'Windows'
        $machine['network']['uplink'] = 'br-outside'
        [xml] $domain = Get-LibvirtMachineDefinition -Instance $machine
        [Xml.XmlElement] $uplink = $domain.SelectSingleNode("//interface[@type='bridge']")
        $uplink.source.bridge | Should -Be 'br-outside'
        $uplink.mac.address | Should -Be '02:54:00:4d:00:3d'
        $uplink.model.type | Should -Be 'e1000e'
        $domain.SelectSingleNode("//interface[@type='network']/mac").address |
            Should -Be '52:54:00:4d:00:3d'
    }

    It 'gives a TPM where the image asks for one, refused where the host has no swtpm' {
        [hashtable] $machine = New-Machine -Family 'Windows'
        function Get-Command { param($Name, $ErrorAction) [pscustomobject] @{ Name = $Name } }
        [xml] $none = Get-LibvirtMachineDefinition -Instance $machine
        $none.SelectSingleNode('//tpm') | Should -BeNullOrEmpty -Because 'its image asks for none'
        $machine['image']['tpm'] = $true
        [xml] $with = Get-LibvirtMachineDefinition -Instance $machine
        $with.SelectSingleNode('//tpm').model | Should -Be 'tpm-crb'
        function Get-Command { param($Name, $ErrorAction) $null }
        { Get-LibvirtMachineDefinition -Instance $machine } | Should -Throw '*has no swtpm*'
    }

    It 'gives a dynamic machine its most, its balloon starting with memory_gb' {
        [hashtable] $machine = New-Machine -Family 'Linux'
        $machine['memoryGB'] = 2
        $machine['dynamicMemory'] = @{ minimumMB = 512; maximumMB = 3072 }
        [xml] $domain = Get-LibvirtMachineDefinition -Instance $machine
        $domain.SelectSingleNode('/domain/memory[@unit="MiB"]').InnerText | Should -Be '3072'
        $domain.SelectSingleNode('/domain/currentMemory[@unit="MiB"]').InnerText |
            Should -Be '2048'
        [Xml.XmlElement] $balloon = $domain.SelectSingleNode('//devices/memballoon')
        @($balloon.model, $balloon.autodeflate, $balloon.freePageReporting) |
            Should -Be @('virtio', 'on', 'on')
        # Static: the memory it starts with is all it has.
        $machine['dynamicMemory'] = @{}
        [xml] $static = Get-LibvirtMachineDefinition -Instance $machine
        $static.SelectSingleNode('/domain/memory[@unit="MiB"]').InnerText | Should -Be '2048'
        $static.SelectSingleNode('/domain/currentMemory[@unit="MiB"]').InnerText |
            Should -Be '2048'
    }

    It 'gives a Windows machine Hyper-V''s interface and clock, and no balloon' {
        # Windows has no virtio balloon driver of its own; KVM gives the rest.
        [xml] $windows = Get-LibvirtMachineDefinition -Instance (New-Machine -Family 'Windows')
        $windows.SelectSingleNode('//devices/memballoon').model | Should -Be 'none'
        $windows.SelectSingleNode('//features/hyperv/relaxed').state | Should -Be 'on'
        $windows.SelectSingleNode("//clock/timer[@name='hypervclock']").present |
            Should -Be 'yes'
        $windows.SelectSingleNode('//clock').offset | Should -Be 'utc'
        [xml] $linux = Get-LibvirtMachineDefinition -Instance (New-Machine -Family 'Linux')
        $linux.SelectSingleNode('//features/hyperv') | Should -BeNullOrEmpty
        $linux.SelectSingleNode("//clock/timer[@name='hypervclock']") | Should -BeNullOrEmpty
    }
}

Describe 'The answer' {
    It 'gives an AlmaLinux machine''s kickstart KVM''s clock, its module loaded at every start' {
        $script:Clock = $null
        function Get-MachineAnswerMedium {
            param($Machine, $MacAddress, $GuestPackage, $Clock)
            $script:Clock = $Clock
            return @{ Label = 'OEMDRV'; File = @{} }
        }
        function New-MachineAnswerMedium { param($Path, $Medium, [switch] $Confirm) }
        [hashtable] $asked = @{ Instance = New-Machine -Family 'Linux'; Path = 'answer.iso' }
        New-LibvirtAnswerMedium @asked -Confirm:$false
        [string] $refclock = "echo 'refclock PHC /dev/ptp_kvm poll 3 dpoll -2 offset 0 " +
            "stratum 2' >> /etc/chrony.conf"
        $script:Clock | Should -Be @('echo ptp_kvm > /etc/modules-load.d/ptp_kvm.conf', $refclock)
    }
}

Describe 'The documents and the resources' {
    It 'requires DSC''s floor or newer in <_>, never elevated' -ForEach @(
        'network.dsc.yaml', 'machine.dsc.yaml') {
        [hashtable] $document = Read-XmipTestYaml -Path (Join-Path $script:Template $_)

        $document.directives.version | Should -Be "^$(Get-XmipTestFloor -Name 'dsc')"
        $document.directives.Contains('securityContext') | Should -BeFalse
    }

    It 'elevates no method of <_>: it runs as the account in the libvirt group' -ForEach @(
        'xmip-libvirt-machine', 'xmip-libvirt-network', 'xmip-libvirt-pool') {
        [string] $text = Get-Content -LiteralPath (
            Join-Path $script:Template "$_.dsc.resource.yaml") -Raw

        $text | Should -Not -Match 'requireSecurityContext: elevated'
    }
}

Describe 'The System Tests'' cluster file on a Linux host, as Deploy-XmipEnvironment reads it' {
    BeforeAll {
        # Every machine AlmaLinux; the developer's desktop, a Linux image too,
        # kept.
        $script:Made = New-XmipTestEnvironment -Folder (Join-Path $TestDrive 'environment') -Linux
        $script:Made.Content['environment']['machines']['DEV02']['os'] = 'AlmaLinux10Desktop'
        $script:Read = Read-XmipTestEnvironment -Environment $script:Made -Run ([string] $TestDrive)
        [hashtable[]] $script:Steps = @(Get-XmipTestDeployStep -Environment $script:Made -Run (
                [string] $TestDrive) | Where-Object {
                [IO.Path]::GetFullPath((Split-Path -Path $_.Document -Parent)) -eq
                    [IO.Path]::GetFullPath($script:Template) })
        [hashtable[]] $script:Machines = @($script:Steps | Select-Object -Skip 1 |
            ForEach-Object { $_.Value })
    }

    It 'applies the network, then each machine, with every parameter declared' {
        $script:Steps[0].Name | Should -Be 'network'
        # The owner's node plan of 2026-11-22: 21 machines, the Mac aside.
        @($script:Steps | Select-Object -Skip 1 | ForEach-Object { $_.Name }) |
            Should -Be @($script:Read.Machines | ForEach-Object { $_['name'] })
        $script:Steps.Count | Should -Be 22
        foreach ($step in $script:Steps) {
            [Collections.IDictionary] $declared = (
                Read-XmipTestYaml -Path $step.Document).parameters
            foreach ($name in $declared.Keys) {
                $step.Value.ContainsKey($name) | Should -BeTrue -Because "$($step.Name) $name"
            }
        }
        # Each far end and each node by its name, then the cluster.
        $farEnds = $script:Made.Content['environment']['far_ends']
        [string[]] $named = @(@($farEnds['senders']) + @($farEnds['receivers']) +
            @($script:Made.Content['nodes'].Keys))
        @($script:Steps[0].Value['names'] | ForEach-Object { $_.name }) |
            Should -Be @($named + $script:Read.Cluster)
    }

    It 'makes the host the names'' server and, through its NAT, the way out of online nodes' {
        $nodes = $script:Made.Content['nodes']
        [string[]] $online = @($nodes.Keys | Where-Object {
                'online' -in @($nodes[$_]['capabilities']) } | ForEach-Object { "XMIP-$_" })
        $online | Should -Not -BeNullOrEmpty
        @($script:Machines | Where-Object { $_.network.gateway } |
            ForEach-Object { "$($_.name) $($_.network.gateway)" }) |
            Should -Be @($online | ForEach-Object { "$_ 10.77.0.1" })
        # No domain controller and no gateway machine: nothing on an uplink.
        $script:Read.NameServer | Should -BeNullOrEmpty
        $script:Read.Gateway | Should -BeNullOrEmpty
        @($script:Machines | Where-Object { $_.network.uplink }) | Should -BeNullOrEmpty
        $script:Steps[0].Value.network.enableNat | Should -BeTrue
        $script:Steps[0].Value.network.dnsServer | Should -Be '10.77.0.1'
    }

    It 'gives the developer a desktop' {
        @($script:Machines | Where-Object { $_.image['environment'] } |
            ForEach-Object { $_.name }) | Should -Be @('XMIP-DEV02')
    }

    It 'defines every machine''s domain, its description, a TPM for Windows 11 alone' {
        function Get-Command { param($Name, $ErrorAction) [pscustomobject] @{ Name = $Name } }
        foreach ($machine in $script:Machines) {
            [xml] $domain = Get-LibvirtMachineDefinition -Instance $machine
            $domain.domain.description | Should -Be $machine.description -Because $machine.name
            [long] $start = $machine.memoryGB * 1024
            [long] $most = if ($machine.dynamicMemory.Count) { $machine.dynamicMemory.maximumMB }
            else { $start }
            $domain.SelectSingleNode('/domain/memory').InnerText | Should -Be "$most"
            $domain.SelectSingleNode('/domain/currentMemory').InnerText | Should -Be "$start"
            [bool] $tpm = $null -ne $domain.SelectSingleNode('//tpm')
            $tpm | Should -Be ("$($machine.image['edition'])" -like 'Windows 11*') -Because (
                $machine.name)
        }
    }

}

Describe 'A Windows machine on a Linux host' {
    It 'is refused, naming it, since a Linux host makes none yet' {
        [hashtable] $made = New-XmipTestEnvironment -Folder (Join-Path $TestDrive 'windows') -Linux
        $made.Content['environment']['machines']['DC01']['os'] = 'WindowsServer2025'
        { Read-XmipTestEnvironment -Environment $made -Run ([string] $TestDrive) } |
            Should -Throw -ExpectedMessage ('REFUSED: a Linux host makes no Windows machine ' +
                'yet, XMIP-DC01: *(ADR-0015, the third amendment of 2026-11-22)*')
    }

    It 'is refused dynamic memory on libvirt, Windows having no balloon driver of its own' {
        [hashtable] $sized = @{ name = 'XMIP-DC01'; memory_gb = 2
            dynamic_memory = @{ minimum_gb = 1; maximum_gb = 4 } }
        {
            InModuleScope Xmip -Parameters @{ Sized = $sized } {
                param($Sized)
                Get-XmipDeployDynamicMemory -Machine $Sized -Hypervisor 'libvirt' -Family (
                    'Windows')
            }
        } | Should -Throw -ExpectedMessage '*XMIP-DC01 runs Windows on libvirt*no balloon driver*'
    }
}

Describe 'The machine, virsh a stub' {
    It 'leaves a machine that installs to it, and writes nothing on any stream' {
        # DSC reads the first line a resource writes as its answer, and
        # pwsh -File writes a warning to standard output too.
        $script:Asked = [Collections.Generic.List[string]]::new()
        function Invoke-Virsh {
            param([string[]] $Argument, [switch] $Quiet)
            $script:Asked.Add($Argument -join ' ')
            if ($Argument[0] -eq 'domstate') {
                return 'running'
            }
            return $null
        }
        # The guest does not answer while it installs.
        function Test-Connection { $false }
        [hashtable] $machine = New-Machine -Family 'Linux'
        @(Set-LibvirtMachine -Instance $machine -Confirm:$false *>&1) | Should -BeNullOrEmpty
        $script:Asked | Should -Be @('domstate XMIP-IN01',
            'metadata XMIP-IN01 urn:xmip:machine --config', 'domstate XMIP-IN01')
    }

    It 'hashes an ISO only where its volume is not in the pool whole: once, not per machine' {
        # The volumes the pool holds whole; vol-info of any other answers nothing.
        $script:Held = @()
        function Invoke-Virsh {
            param([string[]] $Argument, [switch] $Quiet)
            if ($Argument[0] -eq 'vol-info' -and $Argument[-1] -in $script:Held) {
                return "Name: $($Argument[-1])`nCapacity:       10 bytes`nAllocation:     12 bytes"
            }
            if ($Argument[0] -eq 'domstate') {
                return 'running'
            }
            return $null
        }
        function Get-FileHash { throw 'the ISO was read' }
        function New-LibvirtAnswerMedium { param($Instance, $Path, [switch] $Confirm) }
        function Invoke-VirshDefinition { param($Command, $Definition) }
        function Start-LibvirtMachine { param($Instance) }
        [hashtable] $machine = New-Machine -Family 'Linux'
        $machine['image']['path'] = Join-Path $TestDrive 'image.iso'
        { Start-LibvirtMachineInstallation -Instance $machine } | Should -Throw 'the ISO was read'
        $script:Held = @('image-90244ac532f67c97.iso', 'XMIP-IN01.qcow2', 'XMIP-IN01-answer.iso')
        { Start-LibvirtMachineInstallation -Instance $machine } | Should -Not -Throw
    }
}
