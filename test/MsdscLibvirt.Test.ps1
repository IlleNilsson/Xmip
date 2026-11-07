#requires -PSEdition Core
#requires -Version 7.7.0

<#
    The Microsoft DSC v3 template for libvirt (deploy/dsc/msdsc/libvirt)
    without libvirt: what can be held on any machine.

    - The network's definition: NAT, the bridge, the gateway, a DHCP host
      per machine by its static MAC, and one DNS host per address holding
      every name it answers; its summary ignores what libvirt adds.
    - The domain's definition: UEFI with Secure Boot, the disk first, the
      DVD drives on SATA, virtio for AlmaLinux and SATA and e1000e for
      Windows, a TPM only where the host has swtpm.
    - The example, as Deploy-XmipEnvironment reads it: the network, then
      each machine, each with every parameter its document declares.

    The machines themselves are proved by running the template:
    deploy/dsc/msdsc/libvirt/README.md.

    Style: doc/governance/powershell-style.md
#>

BeforeAll {
    . (Join-Path $PSScriptRoot 'Initialize-XmipTest.ps1')

    [string] $script:Template = Join-Path $script:Root 'deploy/dsc/msdsc/libvirt'
    foreach ($part in 'LibvirtCommon.ps1', 'LibvirtNetwork.ps1', 'LibvirtMachine.ps1') {
        . (Join-Path $script:Template $part)
    }

    # The names are configuration (ADR-0056): the example's own node and cluster.
    $script:Example = InModuleScope Xmip -Parameters @{
        Path = Join-Path $script:Template 'environment.example.xmip'
    } {
        param($Path)
        Read-XmipToml -Path $Path
    }
    [string] $script:Node = @($script:Example['machines'])[0]['nodes'][0]
    [string] $script:Cluster = $script:Example['cluster']

    $script:Network = @{
        name = 'xmip'
        bridge = 'virbr-xmip'
        gateway = '10.77.0.1'
        prefixLength = 24
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

        return @{
            name = 'XMIP-IN01'
            environment = 'xmip'
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
        [xml] $domain = Get-LibvirtMachineDefinition -Instance (New-Machine -Family 'Linux')
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
    }

    It 'gives a TPM only where the host has swtpm' {
        function Get-Command { param($Name, $ErrorAction) $null }
        [xml] $without = Get-LibvirtMachineDefinition -Instance (New-Machine -Family 'Linux')
        $without.SelectSingleNode('//tpm') | Should -BeNullOrEmpty
        function Get-Command { param($Name, $ErrorAction) [pscustomobject] @{ Name = $Name } }
        [xml] $with = Get-LibvirtMachineDefinition -Instance (New-Machine -Family 'Linux')
        $with.SelectSingleNode('//tpm').model | Should -Be 'tpm-crb'
    }
}

Describe 'The documents and the resources' {
    It 'requires DSC 3.4.0-preview.2 or newer in <_>, never elevated' -ForEach @(
        'network.dsc.yaml', 'machine.dsc.yaml') {
        [hashtable] $document = Read-XmipTestYaml -Path (Join-Path $script:Template $_)

        $document.directives.version | Should -Be '^3.4.0-preview.2'
        $document.directives.Contains('securityContext') | Should -BeFalse
    }

    It 'elevates no method of <_>: it runs as the account in the libvirt group' -ForEach @(
        'xmip-libvirt-machine', 'xmip-libvirt-network', 'xmip-libvirt-pool') {
        [string] $text = Get-Content -LiteralPath (
            Join-Path $script:Template "$_.dsc.resource.yaml") -Raw

        $text | Should -Not -Match 'requireSecurityContext: elevated'
    }
}

Describe 'The example, as Deploy-XmipEnvironment reads it' {
    It 'applies the network, then each machine, with every parameter declared' {
        [hashtable[]] $steps = @(InModuleScope Xmip -Parameters @{
            Path = Join-Path $script:Template 'environment.example.xmip'
            Template = $script:Template
        } {
            param($Path, $Template)
            Get-XmipDeployStep -Environment (Read-XmipToml -Path $Path) -Template $Template
        })
        $steps[0].Name | Should -Be 'network'
        @($steps | Select-Object -Skip 1 | ForEach-Object { $_.Name }) | Should -Be @('XMIP-IN01')
        foreach ($step in $steps) {
            [Collections.IDictionary] $declared = (
                Read-XmipTestYaml -Path $step.Document).parameters
            foreach ($name in $declared.Keys) {
                $step.Value.ContainsKey($name) | Should -BeTrue -Because "$($step.Name) $name"
            }
        }
        @($steps[0].Value['names'] | ForEach-Object { $_.name }) |
            Should -Be @($script:Node, $script:Cluster)
    }
}
