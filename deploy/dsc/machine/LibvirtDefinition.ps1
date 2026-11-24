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

foreach ($part in 'MachineAnswer.ps1', 'MachineGuest.ps1') {
    . (Join-Path -Path $PSScriptRoot -ChildPath $part)
}

# KVM's MAC prefix: a machine's static MAC ends in its address's last three
# octets (MachineAnswer.ps1), so the network's DHCP and the kickstart match it.
$script:LibvirtMacPrefix = '525400'
# The package of the guest services on KVM, which the kickstart installs.
$script:LibvirtGuestPackage = 'qemu-guest-agent'
# KVM's clock as chrony's source (MachineGuest.ps1): the module ptp_kvm gives
# it, which AlmaLinux 10's kernel builds as a module and nothing loads, and
# udev links it as ptp_kvm.
$script:LibvirtClock = @(Get-MachineClockLine -Device 'ptp_kvm' -Module 'ptp_kvm')
# What KVM gives a Windows guest of Hyper-V's own interface, which Windows
# uses as it does on Hyper-V, and its clock: what virt-install's osinfo gives
# Windows Server 2025 and Windows 11, every one built into KVM, no driver.
$script:LibvirtWindowsFeature = @(
    '    <hyperv>'
    "      <relaxed state='on'/><vapic state='on'/><spinlocks state='on' retries='8191'/>"
    "      <vpindex state='on'/><runtime state='on'/><synic state='on'/>"
    "      <stimer state='on'/><frequencies state='on'/><tlbflush state='on'/>"
    "      <ipi state='on'/><evmcs state='on'/><avic state='on'/>"
    '    </hyperv>'
)
$script:LibvirtWindowsClock = "    <timer name='hypervclock' present='yes'/>"
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
    A machine's static MAC on KVM, colon-separated as libvirt writes it;
    -Uplink, a gateway machine's second adapter's (MachineAnswer.ps1).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Address,

        [Parameter()]
        [switch] $Uplink
    )

    [hashtable] $asked = @{ Address = $Address; Prefix = $script:LibvirtMacPrefix }
    [string] $raw = Get-MachineMacAddress @asked -Uplink:$Uplink
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
    $Instance: name, bridge, gateway, prefixLength, nat, machines (each name
    and address: a DHCP host and a DNS host) and names (each name and its
    addresses: DNS hosts the environment adds). It forwards with NAT where
    nat says, the host the way out; otherwise it is isolated, a gateway
    machine the way out, or none.
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
        if ([bool] $Instance['nat']) { "  <forward mode='nat'/>" }
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
    SATA disk and e1000e adapter its installer has drivers for, and Hyper-V's
    interface and clock, which KVM gives; an AlmaLinux guest virtio, the
    guest agent's channel and the balloon. A gateway machine's second
    adapter is on the uplink, a bridge of the host's.
    .DESCRIPTION
    The domain boots its disk first, then the DVD: the empty disk does not
    boot, so the firmware moves on to the ISO, which installs onto the disk,
    and every later boot starts from the disk. Its memory is
    Get-LibvirtMemoryLine's, and a TPM is given where its image asks for one.
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
    # A gateway machine's second adapter, on the uplink, a bridge of the host's.
    [string] $uplink = ConvertTo-LibvirtText -Value ([string] $Instance['network']['uplink'])
    [string] $outside = Get-LibvirtMacAddress -Address $Instance['address'] -Uplink
    [string[]] $guest = @(Get-LibvirtGuestDevice -Instance $Instance)
    [string[]] $feature = @()
    [string[]] $clock = @()
    if ($windows) {
        $feature = $script:LibvirtWindowsFeature
        $clock = @($script:LibvirtWindowsClock)
    }
    return @(
        "<domain type='kvm'>"
        "  <name>$(ConvertTo-LibvirtText -Value $Instance['name'])</name>"
        "  <description>$(ConvertTo-LibvirtText -Value $Instance['environment'])</description>"
        @(Get-LibvirtMemoryLine -Instance $Instance)
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
        '  <features>'
        "    <acpi/><apic/><smm state='on'/>"
        $feature
        '  </features>'
        "  <cpu mode='host-passthrough'/>"
        # UTC, the time zone every machine's answer gives it.
        "  <clock offset='utc'>"
        "    <timer name='rtc' tickpolicy='catchup'/><timer name='pit' tickpolicy='delay'/>"
        "    <timer name='hpet' present='no'/>"
        $clock
        '  </clock>'
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
        if ($uplink) {
            "    <interface type='bridge'><source bridge='$uplink'/>"
            "      <mac address='$outside'/><model type='$model'/></interface>"
        }
        "    <serial type='pty'/><console type='pty'/>"
        "    <graphics type='vnc' listen='127.0.0.1'/>"
        "    <video><model type='virtio'/></video>"
        $guest
        '  </devices>'
        '</domain>'
    ) -join "`n"
}

function Get-LibvirtMemoryLine {
    <#
    .SYNOPSIS
    The domain's memory lines, in MiB. Static, memory_gb, where the machine
    says no more; where its dynamic memory names its most, that is the
    domain's memory and memory_gb its balloon's start, currentMemory: the
    guest starts with memory_gb and is given back up to its most from its
    balloon once it runs short. libvirt has no least: minimum_gb is
    Hyper-V's alone.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [long] $start = [long] $Instance['memoryGB'] * 1024
    [Collections.IDictionary] $dynamic = Get-MachineDynamicMemory -Instance $Instance
    [long] $most = if ($dynamic.Count -gt 0) { [long] $dynamic['maximumMB'] } else { $start }
    "  <memory unit='MiB'>$most</memory>"
    "  <currentMemory unit='MiB'>$start</currentMemory>"
}

function Get-LibvirtGuestDevice {
    <#
    .SYNOPSIS
    The domain's devices that depend on its guest: for AlmaLinux the guest
    agent's channel and the virtio balloon, which deflates as the guest runs
    short (autodeflate) and gives the host back every page the guest frees
    (freePageReporting); for Windows, which has no balloon driver of its
    own, no balloon. And a TPM 2.0 from swtpm where the machine's image
    asks for one, tpm = true, as Windows 11's Setup does: refused where this
    host has no swtpm to give it.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    if (Test-LibvirtWindows -Instance $Instance) {
        "    <memballoon model='none'/>"
    }
    else {
        "    <channel type='unix'><target type='virtio' name='org.qemu.guest_agent.0'/></channel>"
        "    <memballoon model='virtio' autodeflate='on' freePageReporting='on'/>"
    }
    if (-not [bool] (Get-MachineValue -Of $Instance['image'] -Name 'tpm')) {
        return
    }
    if ($null -eq (Get-Command -Name swtpm -ErrorAction SilentlyContinue)) {
        throw ("REFUSED: $($Instance['name'])'s image asks for a TPM, and this host has no " +
            'swtpm to give it (deploy/dsc/msdsc/libvirt/README.md).')
    }
    "    <tpm model='tpm-crb'><backend type='emulator' version='2.0'/></tpm>"
}

function New-LibvirtAnswerMedium {
    <#
    .SYNOPSIS
    Writes one machine's answer medium at $Path, as KVM's machines read it:
    its static MAC by KVM's prefix, the guest agent in its packages and
    KVM's clock as chrony's source.
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
        Clock = $script:LibvirtClock
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
