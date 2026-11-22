#requires -PSEdition Core
#requires -Version 7.7.0
# What a machine's hypervisor gives its guest, the same rule on every
# hypervisor (hyperv, libvirt) and in both technologies: its memory, as its
# instance says it, and its clock, as chrony takes it. HyperVDefinition.ps1
# and LibvirtDefinition.ps1 dot-source it, each with its own device; the
# environment file's dynamic_memory is read once, by
# Get-XmipDeployDynamicMemory, and reaches a template as dynamicMemory.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-MachineDynamicMemory {
    <#
    .SYNOPSIS
    The machine's dynamic memory, minimumMB and maximumMB; empty where its
    memory is static, as it is where the instance says none.
    #>
    [CmdletBinding()]
    [OutputType([Collections.IDictionary])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable] $Instance
    )

    [object] $dynamic = $Instance['dynamicMemory']
    if ($dynamic -is [Collections.IDictionary] -and $dynamic.Contains('maximumMB')) {
        return $dynamic
    }
    return @{}
}

function Get-MachineClockLine {
    <#
    .SYNOPSIS
    The kickstart's %post lines that give chrony its hypervisor's clock, a
    PTP hardware clock at /dev/<Device>, the link systemd's own udev rules
    make for each hypervisor's clock (50-udev-default.rules, systemd 257 on
    AlmaLinux 10): the host keeps it, so a machine with no way out keeps
    time, and the far ends and nodes on different machines time what they
    carry on one clock. -Module is the kernel module that gives the clock,
    loaded at every start, where nothing else loads it.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^ptp_[a-z0-9_]+$')]
        [string] $Device,

        [Parameter()]
        [ValidatePattern('^([a-z0-9_]+)?$')]
        [string] $Module = ''
    )

    if ($Module) {
        "echo $Module > /etc/modules-load.d/$Module.conf"
    }
    "echo 'refclock PHC /dev/$Device poll 3 dpoll -2 offset 0 stratum 2' >> /etc/chrony.conf"
}
