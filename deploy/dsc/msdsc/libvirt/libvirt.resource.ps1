#requires -Version 7.7.0

<#
    The Xmip resources of the libvirt template (README.md): an environment's
    machines on KVM through libvirt, for a host that runs Linux, as the
    Hyper-V template is for one that runs Windows. A resource manifest
    beside this file names each kind, and DSC runs this script with the kind
    and the operation, the instance's properties as JSON on standard input;
    it answers the instance's state as JSON.

    - Network: a libvirt network with NAT; its DHCP and DNS give each
      machine its address and name, and the names the environment adds.
    - Pool: a directory pool for the machines' disks, images and answers.
    - Machine: one machine, a domain installed unattended from its ISO.

    Every rule about a network, a pool or a domain is libvirt's; this only
    asks virsh and hands it definitions.

    Style: doc/governance/powershell-style.md
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Network', 'Pool', 'Machine')]
    [string] $Kind,

    [Parameter(Mandatory = $true)]
    [ValidateSet('get', 'set', 'test')]
    [string] $Operation
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

foreach ($part in 'LibvirtCommon.ps1', 'LibvirtNetwork.ps1', 'LibvirtMachine.ps1') {
    . (Join-Path -Path $PSScriptRoot -ChildPath $part)
}

[hashtable] $instance = [Console]::In.ReadToEnd() | ConvertFrom-Json -AsHashtable

# What the instance's kind finds wrong, in words: nothing is its desired state.
[scriptblock] $finding = {
    switch ($Kind) {
        'Network' { @(Get-LibvirtNetworkFinding -Instance $instance) }
        'Pool' { @(Get-LibvirtPoolFinding -Instance $instance) }
        'Machine' {
            [hashtable] $state = Get-LibvirtMachineState -Instance $instance
            if ($state.installation -ne 'Done' -or -not $state.running) {
                "$($instance['name']): $($state.installation), running $($state.running)."
            }
        }
    }
}

if ($Operation -eq 'set') {
    switch ($Kind) {
        'Network' { Set-LibvirtNetwork -Instance $instance -Confirm:$false }
        'Pool' { Set-LibvirtPool -Instance $instance -Confirm:$false }
        'Machine' { Set-LibvirtMachine -Instance $instance -Confirm:$false }
    }
}

[string[]] $found = @(& $finding)
# The instance as asked, with what was found: DSC holds the answer to the
# schema, whose required properties are the instance's own.
[hashtable] $state = $instance.Clone()
$state['findings'] = $found
if ($Kind -eq 'Machine') {
    [hashtable] $machine = Get-LibvirtMachineState -Instance $instance
    $state['installation'] = $machine.installation
    $state['running'] = $machine.running
}
if ($Operation -ne 'get') {
    $state['_inDesiredState'] = $found.Count -eq 0
}
$state | ConvertTo-Json -Compress -Depth 10
