#requires -PSEdition Core
#requires -Version 7.7.0
# What a machine is on a libvirt host, as libvirt reads it: the network, the
# pool and the domain definitions, the pool volumes a machine is made of, the
# DVD drives its media are in and the record that says it is installed. One
# home for both technologies: Microsoft DSC's Xmip.Libvirt resources
# (deploy/dsc/msdsc/libvirt) and Ansible's xmip_machine role
# (deploy/dsc/ansible, through machine.ps1) ask it, and neither writes a
# definition of its own. Every rule about a network, a pool or a domain is
# libvirt's; this only writes what it is handed.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path -Path $PSScriptRoot -ChildPath 'MachineAnswer.ps1')

# KVM's MAC prefix: a machine's static MAC ends in its address's last three
# octets (MachineAnswer.ps1), so the network's DHCP and the kickstart match it.
$script:LibvirtMacPrefix = '525400'
# The package of the guest services on KVM, which the kickstart installs.
$script:LibvirtGuestPackage = 'qemu-guest-agent'
# The namespace of the machine's own record in its domain's metadata.
$script:LibvirtMetadata = 'urn:xmip:machine'
# The DVD drives' targets on the SATA bus; the disk is vda or sda before them.
$script:LibvirtInstallTarget = 'sdb'
$script:LibvirtAnswerTarget = 'sdc'

function ConvertTo-LibvirtText {
    <#
    .SYNOPSIS
    A value as XML text, for a definition written as a string.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string] $Value
    )

    return [Security.SecurityElement]::Escape($Value)
}

function Get-LibvirtMacAddress {
    <#
    .SYNOPSIS
    A machine's static MAC on KVM, colon-separated as libvirt writes it.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Address
    )

    [string] $raw = Get-MachineMacAddress -Address $Address -Prefix $script:LibvirtMacPrefix
    return ($raw -replace '(..)(?!$)', '$1:').ToLowerInvariant()
}

function Get-LibvirtVolumeName {
    <#
    .SYNOPSIS
    The pool volume names of one machine: its disk, its answer medium, and
    its image, named by its SHA-256 so machines of one image share it.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    return @{
        Disk = "$($Instance['name']).qcow2"
        Answer = "$($Instance['name'])-answer.iso"
        Image = "image-$($Instance['image'].sha256.Substring(0, 16).ToLowerInvariant()).iso"
    }
}

function Test-LibvirtWindows {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    return $Instance['image'].family -eq 'Windows'
}

function Get-LibvirtNetworkDefinition {
    <#
    .SYNOPSIS
    The network's definition as libvirt reads it, from the instance.
    .DESCRIPTION
    $Instance: name, bridge, gateway, prefixLength, machines (each name and
    address: a DHCP host and a DNS host) and names (each name and its
    addresses: DNS hosts the environment adds).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    # libvirt takes one DNS host per address, holding every name it answers.
    [Collections.Specialized.OrderedDictionary] $named = [ordered] @{}
    [Collections.Generic.List[string]] $dhcp = [Collections.Generic.List[string]]::new()
    foreach ($machine in @($Instance['machines'])) {
        [string] $name = ConvertTo-LibvirtText -Value $machine.name
        [string] $mac = Get-LibvirtMacAddress -Address $machine.address
        $dhcp.Add("      <host mac='$mac' name='$name' ip='$($machine.address)'/>")
        $named[$machine.address] = @($named[$machine.address]) + $name
    }
    foreach ($entry in @($Instance['names'])) {
        foreach ($address in @($entry.addresses)) {
            $named[$address] = @($named[$address]) + (ConvertTo-LibvirtText -Value $entry.name)
        }
    }
    [string[]] $dns = @(foreach ($address in $named.Keys) {
        [string[]] $names = @($named[$address] | Where-Object { $_ })
        "    <host ip='$address'>" +
            (($names | ForEach-Object { "<hostname>$_</hostname>" }) -join '') + '</host>'
    })
    [string] $network = ConvertTo-LibvirtText -Value $Instance['name']
    [string] $bridge = ConvertTo-LibvirtText -Value $Instance['bridge']
    return @(
        '<network>'
        "  <name>$network</name>"
        "  <forward mode='nat'/>"
        "  <bridge name='$bridge' stp='on' delay='0'/>"
        '  <dns>'
        $dns
        '  </dns>'
        "  <ip address='$($Instance['gateway'])' prefix='$($Instance['prefixLength'])'>"
        '    <dhcp>'
        $dhcp
        '    </dhcp>'
        '  </ip>'
        '</network>'
    ) -join "`n"
}

function Get-LibvirtPoolDefinition {
    <#
    .SYNOPSIS
    The pool's definition as libvirt reads it: a directory pool, $Instance's
    name at its path.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    return @(
        "<pool type='dir'>"
        "  <name>$(ConvertTo-LibvirtText -Value $Instance['name'])</name>"
        "  <target><path>$(ConvertTo-LibvirtText -Value $Instance['path'])</path></target>"
        '</pool>'
    ) -join "`n"
}

function Get-LibvirtMachineDefinition {
    <#
    .SYNOPSIS
    The machine's domain as libvirt reads it. A Windows guest is given the
    SATA disk and e1000e adapter its installer has drivers for; an AlmaLinux
    guest virtio and the guest agent's channel.
    .DESCRIPTION
    The domain boots its disk first, then the DVD: the empty disk does not
    boot, so the firmware moves on to the ISO, which installs onto the disk,
    and every later boot starts from the disk. A TPM is given wherever the
    host has one to give, never required.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [hashtable] $volume = Get-LibvirtVolumeName -Instance $Instance
    [bool] $windows = Test-LibvirtWindows -Instance $Instance
    [string] $pool = ConvertTo-LibvirtText -Value $Instance['pool']
    [string] $disk = if ($windows) { "dev='sda' bus='sata'" } else { "dev='vda' bus='virtio'" }
    [string] $model = if ($windows) { 'e1000e' } else { 'virtio' }
    [string] $mac = Get-LibvirtMacAddress -Address $Instance['address']
    [string[]] $tpm = @()
    if ($null -ne (Get-Command -Name swtpm -ErrorAction SilentlyContinue)) {
        $tpm = @("    <tpm model='tpm-crb'><backend type='emulator' version='2.0'/></tpm>")
    }
    [string[]] $agent = @()
    if (-not $windows) {
        $agent = @("    <channel type='unix'><target type='virtio' " +
            "name='org.qemu.guest_agent.0'/></channel>")
    }
    return @(
        "<domain type='kvm'>"
        "  <name>$(ConvertTo-LibvirtText -Value $Instance['name'])</name>"
        "  <description>$(ConvertTo-LibvirtText -Value $Instance['environment'])</description>"
        "  <memory unit='GiB'>$($Instance['memoryGB'])</memory>"
        "  <vcpu>$($Instance['cpu'])</vcpu>"
        "  <os firmware='efi'>"
        "    <type arch='x86_64' machine='q35'>hvm</type>"
        '    <firmware>'
        "      <feature enabled='yes' name='secure-boot'/>"
        "      <feature enabled='yes' name='enrolled-keys'/>"
        '    </firmware>'
        "    <boot dev='hd'/>"
        "    <boot dev='cdrom'/>"
        '  </os>'
        "  <features><acpi/><apic/><smm state='on'/></features>"
        "  <cpu mode='host-passthrough'/>"
        "  <clock offset='utc'/>"
        '  <devices>'
        "    <disk type='volume' device='disk'><driver name='qemu' type='qcow2'/>"
        "      <source pool='$pool' volume='$($volume.Disk)'/><target $disk/></disk>"
        "    <disk type='volume' device='cdrom'><driver name='qemu' type='raw'/>"
        "      <source pool='$pool' volume='$($volume.Image)'/>"
        "      <target dev='$script:LibvirtInstallTarget' bus='sata'/><readonly/></disk>"
        "    <disk type='volume' device='cdrom'><driver name='qemu' type='raw'/>"
        "      <source pool='$pool' volume='$($volume.Answer)'/>"
        "      <target dev='$script:LibvirtAnswerTarget' bus='sata'/><readonly/></disk>"
        "    <interface type='network'>"
        "      <source network='$(ConvertTo-LibvirtText -Value $Instance['network'].name)'/>"
        "      <mac address='$mac'/><model type='$model'/></interface>"
        "    <serial type='pty'/><console type='pty'/>"
        "    <graphics type='vnc' listen='127.0.0.1'/>"
        "    <video><model type='virtio'/></video>"
        $agent
        $tpm
        '  </devices>'
        '</domain>'
    ) -join "`n"
}

function New-LibvirtAnswerMedium {
    <#
    .SYNOPSIS
    Writes one machine's answer medium at $Path, as KVM's machines read it:
    its static MAC by KVM's prefix and the guest agent in its packages.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([void])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance,

        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    [hashtable] $asked = @{
        Machine = [pscustomobject] $Instance
        MacAddress = Get-MachineMacAddress -Address $Instance['address'] -Prefix (
            $script:LibvirtMacPrefix)
        GuestPackage = $script:LibvirtGuestPackage
    }
    if ($PSCmdlet.ShouldProcess($Path, 'Write the answer medium')) {
        [hashtable] $medium = Get-MachineAnswerMedium @asked
        New-MachineAnswerMedium -Path $Path -Medium $medium -Confirm:$false
    }
}

function Get-LibvirtMachinePlan {
    <#
    .SYNOPSIS
    Everything a template needs to make one machine, beyond running virsh:
    its domain's definition, its volumes, the DVD drives its media are in,
    and the metadata record that says it is installed and which technology,
    msdsc or ansible, made it.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [string] $technology = ConvertTo-LibvirtText -Value ([string] $Instance['technology'])
    return @{
        definition = Get-LibvirtMachineDefinition -Instance $Instance
        volume = Get-LibvirtVolumeName -Instance $Instance
        drives = @($script:LibvirtInstallTarget, $script:LibvirtAnswerTarget)
        metadata = @{
            uri = $script:LibvirtMetadata
            key = 'xmip'
            record = "<machine installed='yes' technology='$technology'/>"
        }
        port = if (Test-LibvirtWindows -Instance $Instance) { 5985 } else { 22 }
    }
}
